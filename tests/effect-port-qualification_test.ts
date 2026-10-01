import assert from "node:assert/strict";
import {
  decodeEffectCommand,
  EffectClient,
  EffectFileClient,
  EffectFilePortProvider,
  EffectProtocolError,
  type EffectTransport,
  FileEffectProvider,
  MemoryFileBackend,
  PortError,
  PortTable,
  ProviderTransport,
} from "../tools/effect-protocol.ts";
import { decodeEffectFrame } from "../tools/effect-wire.ts";
import {
  RecordingTriptychBackend,
  TRIPTYCH_CAPABILITY,
  TriptychEffectProvider,
} from "../tools/triptych-provider.ts";
import { EffectPortProvider } from "../tools/effect-port-provider.ts";

const text = (value: string): Uint8Array => new TextEncoder().encode(value);
const standard = { input: 1, output: 2, error: 3 };

class RecordingTransport implements EffectTransport {
  readonly textWrites: number[] = [];
  readonly fileOperations: number[] = [];

  constructor(private readonly inner: EffectTransport) {}

  transact(request: Uint8Array): Uint8Array {
    const command = decodeEffectCommand(decodeEffectFrame(request));
    if (command.type === "text") this.textWrites.push(...command.bytes);
    if (command.type === "control" && command.capability === 0x0200) {
      this.fileOperations.push(command.bytes[0]!);
    }
    return this.inner.transact(request);
  }
}

function makeQualification() {
  const triptych = new RecordingTriptychBackend();
  const triptychProvider = new TriptychEffectProvider(triptych);
  triptychProvider.queueEvent({
    type: "text",
    source: 1,
    sequence: 1,
    text: "l",
  });
  const files = new MemoryFileBackend({ files: { "STATE.DAT": text("old") } });
  const fileService = new FileEffectProvider(triptychProvider, files);
  const transport = new RecordingTransport(new ProviderTransport(fileService));
  const client = new EffectClient(transport);
  const provider = new EffectFilePortProvider(
    new EffectPortProvider(client),
    new EffectFileClient(client),
  );
  const ports = new PortTable(provider, standard);
  return { ports, provider, transport, triptych, client };
}

Deno.test("port qualification keeps console, file and device effects separate", () => {
  const { ports, provider, transport, triptych, client } = makeQualification();
  const output = ports.currentOutputPort();
  const input = ports.currentInputPort();

  ports.writeText(output, text("Ready"));
  ports.newline(output);
  assert.equal(
    new TextDecoder().decode(Uint8Array.from(transport.textWrites)),
    "Ready\r\n",
  );
  assert.equal(ports.readChar(input), 0x6c);

  const writeHandle = provider.openWrite("STATE.DAT");
  const writer = ports.open({
    handle: writeHandle,
    direction: "output",
    mode: "binary",
    transactional: true,
  });
  ports.writeBytes(writer, text("new"));
  ports.closePort(writer);

  const readHandle = provider.openRead("STATE.DAT");
  const reader = ports.open({
    handle: readHandle,
    direction: "input",
    mode: "binary",
  });
  assert.deepEqual(ports.readBytes(reader, 16), text("new"));
  ports.closePort(reader);

  client.sendControl(TRIPTYCH_CAPABILITY.sound, Uint8Array.of(0x44));
  assert.deepEqual(triptych.transcript, [
    { domain: "sound", bytes: Uint8Array.of(0x44) },
  ]);
  const controlsBeforeUnsupported = triptych.transcript.length;
  assert.throws(
    () => client.sendControl(0x0102, Uint8Array.of(1)),
    (error) =>
      error instanceof EffectProtocolError && error.code === "unsupported",
  );
  assert.equal(triptych.transcript.length, controlsBeforeUnsupported);

  const standardInput = ports.currentInputPort();
  const standardOutput = ports.currentOutputPort();
  const fileOperationsBeforeReset = transport.fileOperations.length;
  const resetHandle = provider.openRead("STATE.DAT");
  const resetPort = ports.open({ handle: resetHandle, direction: "input" });
  const reset = ports.reset();
  assert.deepEqual(reset.failures, []);
  assert.deepEqual(reset.closed, [3]);
  assert.equal(provider.isFileHandle(resetHandle), false);
  assert.equal(ports.currentInputPort(), standardInput);
  assert.equal(ports.currentOutputPort(), standardOutput);
  assert.equal(transport.fileOperations.length, fileOperationsBeforeReset + 2);
  assert.equal(transport.fileOperations.at(-1), 4);
  ports.writeText(standardOutput, text("After"));
  assert.equal(
    new TextDecoder().decode(Uint8Array.from(transport.textWrites)),
    "Ready\r\nAfter",
  );
  assert.throws(
    () => ports.readChar(resetPort),
    (error) => error instanceof PortError && error.code === "not-port",
  );
});
