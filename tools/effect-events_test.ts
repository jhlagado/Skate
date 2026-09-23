import assert from "node:assert/strict";
import {
  decodeEffectEvent,
  EffectClient,
  EffectProtocolError,
  ProviderTransport,
  RecordingEffectProvider,
} from "./effect-protocol.ts";

Deno.test("normalized and raw event reads remain separate", () => {
  const provider = new RecordingEffectProvider();
  const client = new EffectClient(new ProviderTransport(provider));
  const raw = {
    source: 4,
    sequence: 9,
    type: "raw" as const,
    bytes: Uint8Array.of(0x1b, 0x5b, 0x41),
  };
  provider.queueEvent(raw);
  assert.throws(
    () => client.readEvent(),
    (error) => error instanceof EffectProtocolError && error.code === "device",
  );
  assert.deepEqual(client.readEvent("raw"), raw);
  assert.equal(client.readEvent(), null);

  const text = { source: 4, sequence: 10, type: "text" as const, text: "A" };
  provider.queueEvent(text);
  assert.throws(
    () => client.readEvent("raw"),
    (error) => error instanceof EffectProtocolError && error.code === "device",
  );
  assert.deepEqual(client.readEvent(), text);
});

Deno.test("event queues enforce their configured capacity without dropping data", () => {
  const provider = new RecordingEffectProvider({
    maxPayloadBytes: 1024,
    maxFrameBytes: 1035,
    maxEventQueue: 1,
  });
  const first = {
    source: 1,
    sequence: 1,
    type: "text" as const,
    text: "first",
  };
  provider.queueEvent(first);
  assert.throws(
    () =>
      provider.queueEvent({
        source: 1,
        sequence: 2,
        type: "text",
        text: "second",
      }),
    (error) =>
      error instanceof EffectProtocolError && error.code === "capacity",
  );
  const client = new EffectClient(new ProviderTransport(provider));
  assert.deepEqual(client.readEvent(), first);
  assert.equal(client.readEvent(), null);
});

Deno.test("malformed events and unknown read modes are rejected", () => {
  assert.throws(
    () => decodeEffectEvent(Uint8Array.of(0xff, 0, 0, 0, 0)),
    (error) =>
      error instanceof EffectProtocolError && error.code === "invalid-event",
  );
  const provider = new RecordingEffectProvider();
  const client = new EffectClient(new ProviderTransport(provider));
  assert.throws(
    () => client.readEvent("other" as never),
    (error) =>
      error instanceof EffectProtocolError && error.code === "invalid-command",
  );
  assert.equal(provider.textWrites.length, 0);
});
