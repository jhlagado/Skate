import assert from "node:assert/strict";
import {
  EffectClient,
  EffectProtocolError,
  FILE_CAPABILITY,
  type FileBackend,
  FileEffectProvider,
  type FileHandleStatus,
  MemoryFileBackend,
  ProviderTransport,
} from "./effect-protocol.ts";
import {
  RecordingTriptychBackend,
  TRIPTYCH_CAPABILITY,
  TriptychEffectProvider,
} from "./triptych-provider.ts";
import { createFileClient, EffectFileClient } from "./effect-files.ts";

const text = (value: string) => new TextEncoder().encode(value);

function filesClient(backend: FileBackend): EffectFileClient {
  return createFileClient(
    new TriptychEffectProvider(new RecordingTriptychBackend()),
    backend,
  );
}

class CountingMemoryFileBackend extends MemoryFileBackend {
  opens = 0;

  override open(path: string, mode: "read" | "write"): number {
    this.opens++;
    return super.open(path, mode);
  }
}

Deno.test("bounded files support short reads, sync and replacement", () => {
  const backend = new CountingMemoryFileBackend({
    files: { "SAVE.DAT": text("old") },
  });
  const client = filesClient(backend);
  const writer = client.open("SAVE.DAT", "write");
  assert.deepEqual(client.status(writer), {
    mode: "write",
    position: 0,
    length: 0,
    dirty: false,
  });
  client.write(writer, text("new"));
  assert.deepEqual(client.status(writer), {
    mode: "write",
    position: 3,
    length: 3,
    dirty: true,
  });
  client.sync(writer);
  assert.equal(client.status(writer).dirty, false);

  const reader = client.open("SAVE.DAT", "read");
  assert.deepEqual(client.read(reader, 2), text("ne"));
  assert.deepEqual(client.read(reader, 8), text("w"));
  assert.deepEqual(client.read(reader, 8), new Uint8Array(0));
  assert.deepEqual(client.status(reader), {
    mode: "read",
    position: 3,
    length: 3,
    dirty: false,
  });
  client.close(reader);
  client.close(writer);
});

Deno.test("file paths preserve BOMs and reject invalid UTF-8", () => {
  const backend = new CountingMemoryFileBackend({
    files: {
      X: text("plain"),
      "\ufeffX": text("bom"),
      "\ufffdX": text("replacement"),
    },
  });
  const client = filesClient(backend);
  const handle = client.open("\ufeffX", "read");
  assert.deepEqual(client.read(handle, 20), text("bom"));
  client.close(handle);
  assert.throws(() => client.open("\ud800X", "read"), RangeError);
  assert.equal(backend.opens, 1);

  const provider = new FileEffectProvider(
    new TriptychEffectProvider(new RecordingTriptychBackend()),
    backend,
  );
  const effect = new EffectClient(new ProviderTransport(provider));
  const response = effect.request({
    type: "control",
    capability: FILE_CAPABILITY,
    bytes: Uint8Array.of(1, 0, 0xff),
  });
  assert.equal(response.status, "error");
  if (response.status === "error") {
    assert.equal(response.code, "invalid-command");
  }
});

Deno.test("file operations compose with Triptych and ordinary provider services", () => {
  const triptych = new RecordingTriptychBackend();
  const inner = new TriptychEffectProvider(triptych);
  inner.setQueryReply(7, text("status"), text("ready"));
  const provider = new FileEffectProvider(inner, new MemoryFileBackend());
  const transport = new ProviderTransport(provider);
  const effect = new EffectClient(transport);
  const client = new EffectFileClient(effect);

  effect.sendControl(TRIPTYCH_CAPABILITY.video, Uint8Array.of(1, 2));
  assert.deepEqual(effect.query(7, text("status")), text("ready"));
  const handle = client.open("NEW.DAT", "write");
  client.write(handle, text("ok"));
  client.close(handle);
  assert.deepEqual(triptych.transcript, [
    { domain: "video", bytes: Uint8Array.of(1, 2) },
  ]);
});

Deno.test("missing files and disk-full writes preserve the previous image", () => {
  const backend = new MemoryFileBackend({
    maxFileBytes: 4,
    files: { "SAVE.DAT": text("keep") },
  });
  const client = filesClient(backend);
  assert.throws(() => client.open("SAVE.DAT", "append" as never), RangeError);
  assert.throws(
    () => client.open("MISSING.DAT", "read"),
    (error) => error instanceof EffectProtocolError && error.code === "device",
  );
  const writer = client.open("SAVE.DAT", "write");
  assert.throws(
    () => client.write(writer, text("too long")),
    (error) =>
      error instanceof EffectProtocolError && error.code === "capacity",
  );
  const reader = client.open("SAVE.DAT", "read");
  assert.deepEqual(client.read(reader, 20), text("keep"));
  client.close(reader);
});

class InterruptingCloseBackend implements FileBackend {
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
      throw new EffectProtocolError("device", "interrupted close");
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

class BoundaryBackend implements FileBackend {
  constructor(
    private readonly readBytes: Uint8Array,
    private readonly reportedStatus: FileHandleStatus = {
      mode: "read",
      position: 0,
      length: 0,
      dirty: false,
    },
  ) {}

  open(): number {
    return 1;
  }

  read(): Uint8Array {
    return this.readBytes.slice();
  }

  write(): void {}
  close(): void {}
  sync(): void {}

  status(): FileHandleStatus {
    return this.reportedStatus;
  }

  abort(): void {}
}

Deno.test("provider rejects overlong reads and malformed backend status", () => {
  const overlong = filesClient(new BoundaryBackend(Uint8Array.of(1, 2, 3)));
  const handle = overlong.open("ignored", "read");
  assert.throws(
    () => overlong.read(handle, 1),
    (error) => error instanceof EffectProtocolError && error.code === "device",
  );

  const malformed = filesClient(
    new BoundaryBackend(new Uint8Array(0), {
      mode: "read",
      position: -1,
      length: 1.5,
      dirty: false,
    } as never),
  );
  const malformedHandle = malformed.open("ignored", "read");
  assert.throws(
    () => malformed.status(malformedHandle),
    (error) =>
      error instanceof EffectProtocolError && error.code === "capacity",
  );
});

Deno.test("an interrupted close is discarded and a later write can replace the file", () => {
  const backend = new InterruptingCloseBackend(
    new MemoryFileBackend({ files: { "SAVE.DAT": text("old") } }),
  );
  const client = filesClient(backend);
  const interrupted = client.open("SAVE.DAT", "write");
  client.write(interrupted, text("new"));
  assert.throws(
    () => client.close(interrupted),
    (error) => error instanceof EffectProtocolError && error.code === "device",
  );
  const beforeRetry = client.open("SAVE.DAT", "read");
  assert.deepEqual(client.read(beforeRetry, 20), text("old"));
  client.close(beforeRetry);

  const replacement = client.open("SAVE.DAT", "write");
  client.write(replacement, text("new"));
  client.close(replacement);
  const afterRetry = client.open("SAVE.DAT", "read");
  assert.deepEqual(client.read(afterRetry, 20), text("new"));
  client.close(afterRetry);
});
