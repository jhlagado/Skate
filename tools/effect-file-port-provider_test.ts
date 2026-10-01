import assert from "node:assert/strict";
import {
  createFileClient,
  EffectClient,
  EffectFileClient,
  EffectFilePortProvider,
  EffectPortProvider,
  FILE_CAPABILITY,
  type FileBackend,
  FileEffectProvider,
  type FileHandleStatus,
  MemoryFileBackend,
  PORT_EOF,
  PortError,
  type PortProvider,
  PortTable,
  ProviderTransport,
} from "./effect-protocol.ts";
import {
  decodeEffectCommand,
  decodeEffectFrame,
  type EffectFrame,
  type EffectProvider,
  encodeEffectResponse,
} from "./effect-protocol.ts";
import {
  RecordingTriptychBackend,
  TriptychEffectProvider,
} from "./triptych-provider.ts";

const text = (value: string): Uint8Array => new TextEncoder().encode(value);
const standard = { input: 1, output: 2, error: 3 };

function makeProvider(files: FileBackend): EffectFilePortProvider {
  const effects = new TriptychEffectProvider(new RecordingTriptychBackend());
  const client = createFileClient(effects, files);
  const standardClient = new EffectClient(new ProviderTransport(effects));
  return new EffectFilePortProvider(
    new EffectPortProvider(standardClient),
    client,
  );
}

class FailingCloseBackend implements FileBackend {
  private fail = true;

  constructor(private readonly inner: FileBackend) {}

  open(path: string, mode: "read" | "write"): number {
    return this.inner.open(path, mode);
  }

  read(handle: number, maximum: number): Uint8Array {
    return this.inner.read(handle, maximum);
  }

  write(handle: number, bytes: Uint8Array): void {
    this.inner.write(handle, bytes);
  }

  close(handle: number): void {
    if (this.fail) {
      this.fail = false;
      throw new Error("interrupted close");
    }
    this.inner.close(handle);
  }

  sync(handle: number): void {
    this.inner.sync(handle);
  }

  status(handle: number): FileHandleStatus {
    return this.inner.status(handle);
  }

  abort(handle: number): void {
    this.inner.abort(handle);
  }
}

class TransactionalInnerProvider implements PortProvider {
  readonly aborted: number[] = [];

  requiresTransactional(handle: number): boolean {
    return handle === 99;
  }

  read(): { status: "eof" } {
    return { status: "eof" };
  }

  write(): void {}
  close(): void {}

  abort(handle: number): void {
    this.aborted.push(handle);
  }
}

class PendingReadProvider implements EffectProvider {
  private pending = true;

  constructor(private readonly inner: EffectProvider) {}

  handle(request: EffectFrame): EffectFrame {
    const command = decodeEffectCommand(request);
    if (
      this.pending && command.type === "control" &&
      command.capability === FILE_CAPABILITY && command.bytes[0] === 2
    ) {
      this.pending = false;
      return decodeEffectFrame(
        encodeEffectResponse(
          { status: "pending", task: 7 },
          request.correlation,
          request.opcode,
        ),
      );
    }
    return this.inner.handle(request);
  }
}

function makePendingProvider(files: MemoryFileBackend): EffectFilePortProvider {
  const effects = new TriptychEffectProvider(new RecordingTriptychBackend());
  const service = new FileEffectProvider(effects, files);
  const client = new EffectFileClient(
    new EffectClient(new ProviderTransport(new PendingReadProvider(service))),
  );
  const standardClient = new EffectClient(new ProviderTransport(effects));
  return new EffectFilePortProvider(
    new EffectPortProvider(standardClient),
    client,
  );
}

Deno.test("read-only file handles use the ordinary port table", () => {
  const provider = makeProvider(
    new MemoryFileBackend({ files: { "DATA.DAT": text("abc") } }),
  );
  const handle = provider.openRead("DATA.DAT");
  assert.equal(provider.isFileHandle(handle), true);
  const ports = new PortTable(provider, standard);
  const port = ports.open({
    handle,
    direction: "input",
    mode: "binary",
  });

  assert.deepEqual(ports.readBytes(port, 2), text("ab"));
  assert.deepEqual(ports.readBytes(port, 2), text("c"));
  assert.deepEqual(ports.readBytes(port, 2), new Uint8Array(0));
  ports.closePort(port);
  assert.equal(provider.isFileHandle(handle), false);
  assert.throws(
    () => ports.readBytes(port, 1),
    (error) => error instanceof PortError && error.code === "closed",
  );
});

Deno.test("text file ports apply Scheme newline rules without changing bytes", () => {
  const provider = makeProvider(
    new MemoryFileBackend({ files: { "TEXT.DAT": text("A\r\nB\rC") } }),
  );
  const handle = provider.openRead("TEXT.DAT");
  const ports = new PortTable(provider, standard);
  const port = ports.open({ handle, direction: "input" });
  assert.equal(ports.readChar(port), 0x41);
  assert.equal(ports.readChar(port), 0x0a);
  assert.equal(ports.readChar(port), 0x42);
  assert.equal(ports.readChar(port), 0x0a);
  assert.equal(ports.readChar(port), 0x43);
  assert.equal(ports.readChar(port), PORT_EOF);
});

Deno.test("pending file reads remain live and return data on retry", () => {
  const provider = makePendingProvider(
    new MemoryFileBackend({ files: { "DATA.DAT": text("abc") } }),
  );
  const handle = provider.openRead("DATA.DAT");
  const ports = new PortTable(provider, standard);
  const port = ports.open({ handle, direction: "input", mode: "binary" });
  assert.throws(
    () => ports.readBytes(port, 3),
    (error) => error instanceof PortError && error.code === "would-block",
  );
  assert.deepEqual(ports.readBytes(port, 3), text("abc"));
});

Deno.test("writable file ports commit on close and reject writes on readers", () => {
  const provider = makeProvider(
    new MemoryFileBackend({ files: { "SAVE.DAT": text("old") } }),
  );
  const writeHandle = provider.openWrite("SAVE.DAT");
  const ports = new PortTable(provider, standard);
  const writer = ports.open({
    handle: writeHandle,
    direction: "output",
    mode: "binary",
    transactional: true,
  });
  ports.writeBytes(writer, text("new"));
  ports.closePort(writer);

  const readHandle = provider.openRead("SAVE.DAT");
  const reader = ports.open({
    handle: readHandle,
    direction: "input",
    mode: "binary",
  });
  assert.deepEqual(ports.readBytes(reader, 20), text("new"));
  ports.closePort(reader);

  const readOnlyHandle = provider.openRead("SAVE.DAT");
  assert.throws(
    () => provider.write(readOnlyHandle, text("x")),
    (error) => error instanceof PortError && error.code === "unsupported",
  );
  provider.close(readOnlyHandle);
});

Deno.test("writable handles must be adopted transactionally", () => {
  const provider = makeProvider(
    new MemoryFileBackend({ files: { "SAVE.DAT": text("old") } }),
  );
  const handle = provider.openWrite("SAVE.DAT");
  const ports = new PortTable(provider, standard);
  assert.throws(
    () => ports.open({ handle, direction: "output", mode: "binary" }),
    (error) => error instanceof PortError && error.code === "unsupported",
  );
  assert.equal(provider.isFileHandle(handle), false);
  const reader = provider.openRead("SAVE.DAT");
  assert.deepEqual(provider.read(reader, 20), {
    status: "data",
    bytes: text("old"),
  });
  provider.close(reader);
});

Deno.test("delegated handles retain the inner transaction requirement", () => {
  const inner = new TransactionalInnerProvider();
  const effects = new TriptychEffectProvider(new RecordingTriptychBackend());
  const adapter = new EffectFilePortProvider(
    inner,
    createFileClient(effects, new MemoryFileBackend()),
  );
  const ports = new PortTable(adapter, standard);
  assert.throws(
    () => ports.open({ handle: 99, direction: "output", mode: "binary" }),
    (error) => error instanceof PortError && error.code === "unsupported",
  );
  assert.deepEqual(inner.aborted, [99]);
});

Deno.test("sync commits a prefix while abort discards later changes", () => {
  const provider = makeProvider(
    new MemoryFileBackend({ files: { "SAVE.DAT": text("old") } }),
  );
  const handle = provider.openWrite("SAVE.DAT");
  const ports = new PortTable(provider, standard);
  const writer = ports.open({
    handle,
    direction: "output",
    mode: "binary",
    transactional: true,
  });
  ports.writeBytes(writer, text("new"));
  ports.flush(writer);
  ports.writeBytes(writer, text("later"));
  const result = ports.cleanup(true);
  assert.deepEqual(result.failures, []);
  assert.deepEqual(result.aborted, [3]);

  const readerHandle = provider.openRead("SAVE.DAT");
  const reader = ports.open({
    handle: readerHandle,
    direction: "input",
    mode: "binary",
  });
  assert.deepEqual(ports.readBytes(reader, 20), text("new"));
  ports.closePort(reader);
});

Deno.test("fatal cleanup can abort an adopted file handle", () => {
  const provider = makeProvider(
    new MemoryFileBackend({ files: { "DATA.DAT": text("abc") } }),
  );
  const handle = provider.openWrite("DATA.DAT");
  const ports = new PortTable(provider, standard);
  const port = ports.open({
    handle,
    direction: "output",
    mode: "binary",
    transactional: true,
  });
  ports.writeBytes(port, text("replacement"));
  const result = ports.cleanup(true);
  assert.deepEqual(result.failures, []);
  assert.deepEqual(result.aborted, [3]);
  assert.equal(provider.isFileHandle(handle), false);
  const readerHandle = provider.openRead("DATA.DAT");
  const reader = ports.open({
    handle: readerHandle,
    direction: "input",
    mode: "binary",
  });
  assert.deepEqual(ports.readBytes(reader, 20), text("abc"));
  ports.closePort(reader);
});

Deno.test("a failed write remains abortable and preserves the old file", () => {
  const provider = makeProvider(
    new MemoryFileBackend({
      maxFileBytes: 3,
      files: { "SAVE.DAT": text("old") },
    }),
  );
  const handle = provider.openWrite("SAVE.DAT");
  const ports = new PortTable(provider, standard);
  const writer = ports.open({
    handle,
    direction: "output",
    mode: "binary",
    transactional: true,
  });
  assert.throws(
    () => ports.writeBytes(writer, text("too long")),
    (error) => error instanceof PortError && error.code === "capacity",
  );
  const result = ports.cleanup(true);
  assert.deepEqual(result.failures, []);
  assert.deepEqual(result.aborted, [3]);

  const readerHandle = provider.openRead("SAVE.DAT");
  const reader = ports.open({
    handle: readerHandle,
    direction: "input",
    mode: "binary",
  });
  assert.deepEqual(ports.readBytes(reader, 20), text("old"));
  ports.closePort(reader);

  const retryHandle = provider.openWrite("SAVE.DAT");
  const retry = ports.open({
    handle: retryHandle,
    direction: "output",
    mode: "binary",
    transactional: true,
  });
  ports.writeBytes(retry, text("ok"));
  ports.closePort(retry);
  const finalHandle = provider.openRead("SAVE.DAT");
  const final = ports.open({
    handle: finalHandle,
    direction: "input",
    mode: "binary",
  });
  assert.deepEqual(ports.readBytes(final, 20), text("ok"));
  ports.closePort(final);
});

Deno.test("a failed close retains the handle for abort cleanup", () => {
  const provider = makeProvider(
    new FailingCloseBackend(
      new MemoryFileBackend({ files: { "SAVE.DAT": text("old") } }),
    ),
  );
  const handle = provider.openWrite("SAVE.DAT");
  const ports = new PortTable(provider, standard);
  const writer = ports.open({
    handle,
    direction: "output",
    mode: "binary",
    transactional: true,
  });
  ports.writeBytes(writer, text("new"));
  assert.throws(
    () => ports.closePort(writer),
    (error) => error instanceof PortError && error.code === "device",
  );
  const result = ports.cleanup(true);
  assert.deepEqual(result.failures, []);
  assert.deepEqual(result.aborted, [3]);

  const readerHandle = provider.openRead("SAVE.DAT");
  const reader = ports.open({
    handle: readerHandle,
    direction: "input",
    mode: "binary",
  });
  assert.deepEqual(ports.readBytes(reader, 20), text("old"));
  ports.closePort(reader);
});
