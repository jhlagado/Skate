import assert from "node:assert/strict";

import {
  decodeEffectFrame,
  EffectClient,
  EffectPortProvider,
  type EffectResponse,
  type EffectTransport,
  encodeEffectResponse,
  EventLibrary,
  PortError,
  PortTable,
  ProviderTransport,
  RecordingEffectProvider,
} from "./effect-protocol.ts";

const standard = { input: 1, output: 2, error: 3 };

function textEvent(text: string, sequence = 1) {
  return { type: "text" as const, source: 1, sequence, text };
}

function makePorts(provider: RecordingEffectProvider) {
  const client = new EffectClient(new ProviderTransport(provider));
  return new PortTable(new EffectPortProvider(client), standard, {
    inputTranslateControlZ: true,
    outputNewline: "lf",
    errorNewline: "lf",
  });
}

Deno.test("the effect port preserves the Scheme text contract", () => {
  const provider = new RecordingEffectProvider();
  provider.queueEvent(textEvent("Ada\r\n"));
  const ports = makePorts(provider);
  const input = ports.currentInputPort();
  const output = ports.currentOutputPort();

  assert.equal(ports.readChar(input), 65);
  assert.equal(ports.readChar(input), 100);
  assert.equal(ports.readChar(input), 97);
  assert.equal(ports.readChar(input), 10);
  ports.writeText(output, new TextEncoder().encode("Ada\n"));
  assert.deepEqual(provider.textWrites.map((bytes) => [...bytes]), [
    [65],
    [100],
    [97],
    [10],
  ]);
});

Deno.test("oversized effect text is rejected at the port boundary", () => {
  const provider = new RecordingEffectProvider();
  provider.queueEvent(textEvent("x".repeat(300)));
  const client = new EffectClient(new ProviderTransport(provider));
  const adapter = new EffectPortProvider(client);
  assert.deepEqual(adapter.read(1, 255), {
    status: "error",
    code: "capacity",
    message: "effect text exceeds 255 bytes",
  });
});

Deno.test("effect text uses byte characters and rejects larger code points", () => {
  const provider = new RecordingEffectProvider();
  provider.queueEvent(textEvent("é"));
  provider.queueEvent(textEvent("😀", 2));
  const client = new EffectClient(new ProviderTransport(provider));
  const adapter = new EffectPortProvider(client);
  assert.deepEqual(adapter.read(1, 1), {
    status: "data",
    bytes: Uint8Array.of(0xe9),
  });
  assert.deepEqual(adapter.read(1, 1), {
    status: "error",
    code: "malformed",
    message: "effect text contains a character outside Skate's byte range",
    protocolCode: undefined,
  });
});

Deno.test("effect reads validate their bounded request size", () => {
  const adapter = new EffectPortProvider(
    new EffectClient(new ProviderTransport(new RecordingEffectProvider())),
  );
  assert.deepEqual(adapter.read(1, 0), {
    status: "error",
    code: "malformed",
    message: "effect read size must be a positive integer",
  });
  assert.deepEqual(adapter.read(1, 256), {
    status: "error",
    code: "capacity",
    message: "effect read size exceeds 255 bytes",
  });
});

Deno.test("empty and non-text events stay distinct from EOF", () => {
  const provider = new RecordingEffectProvider();
  provider.queueEvent({
    type: "pointer",
    source: 2,
    sequence: 1,
    x: 4,
    y: 9,
    buttons: 1,
  });
  const client = new EffectClient(new ProviderTransport(provider));
  const adapter = new EffectPortProvider(client);
  assert.deepEqual(adapter.read(1, 255), {
    status: "error",
    code: "device",
    message: "event has no text for read-char",
  });
  assert.deepEqual(adapter.read(1, 255), { status: "empty" });
  const ports = new PortTable(adapter, standard);
  assert.throws(
    () => ports.readChar(ports.currentInputPort()),
    (error) => error instanceof PortError && error.code === "would-block",
  );
});

Deno.test("event input can be shared with a Triptych provider", () => {
  const provider = new RecordingEffectProvider();
  provider.queueEvent({
    type: "key",
    source: 7,
    sequence: 2,
    key: "Enter",
    modifiers: 0,
    text: "\n",
  });
  const client = new EffectClient(new ProviderTransport(provider));
  const events = new EventLibrary(client);
  assert.deepEqual(events.readText(), "\n");
});

class ResponseTransport implements EffectTransport {
  constructor(private readonly response: EffectResponse) {}

  transact(request: Uint8Array): Uint8Array {
    const frame = decodeEffectFrame(request);
    return encodeEffectResponse(
      this.response,
      frame.correlation,
      frame.opcode,
    );
  }
}

Deno.test("provider errors retain their wire identity", () => {
  const cases = [
    ["malformed", "malformed"],
    ["checksum", "malformed"],
    ["unsupported", "unsupported"],
    ["device", "device"],
  ] as const;
  for (const [protocolCode, portCode] of cases) {
    const client = new EffectClient(
      new ResponseTransport({
        status: "error",
        code: protocolCode,
        message: `${protocolCode} reply`,
      }),
    );
    const adapter = new EffectPortProvider(client);
    assert.deepEqual(adapter.read(1, 1), {
      status: "error",
      code: portCode,
      message: `${protocolCode} reply`,
      protocolCode,
    });
  }
  const pending = new EffectPortProvider(
    new EffectClient(
      new ResponseTransport({ status: "pending", task: 7 }),
    ),
  );
  assert.deepEqual(pending.read(1, 1), {
    status: "error",
    code: "would-block",
    message: "Effect request is pending on task 7",
  });
});
