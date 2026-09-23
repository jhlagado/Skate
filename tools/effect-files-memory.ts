import { checkedBytes, EffectProtocolError, integer } from "./effect-wire.ts";
import type {
  FileBackend,
  FileHandleStatus,
  FileMode,
} from "./effect-files.ts";

interface MemoryHandle {
  readonly path: string;
  readonly mode: FileMode;
  position: number;
  data: Uint8Array;
  dirty: boolean;
  failed: boolean;
}

export interface MemoryFileOptions {
  readonly maxFileBytes?: number;
  readonly files?: Readonly<Record<string, Uint8Array>>;
}

/** Small deterministic backend for host tests and harness examples. */
export class MemoryFileBackend implements FileBackend {
  private readonly files = new Map<string, Uint8Array>();
  private readonly handles = new Map<number, MemoryHandle>();
  private readonly maxFileBytes: number;
  private nextHandle = 1;

  constructor(options: MemoryFileOptions = {}) {
    this.maxFileBytes = options.maxFileBytes ?? 0xffff;
    integer(this.maxFileBytes, "maxFileBytes", 0xffff);
    for (const [path, bytes] of Object.entries(options.files ?? {})) {
      this.files.set(path, checkedBytes(bytes, "file").slice());
    }
  }

  open(path: string, mode: FileMode): number {
    const handle = this.allocateHandle();
    const data = mode === "read"
      ? this.files.get(path)?.slice()
      : new Uint8Array(0);
    if (data === undefined) {
      throw new EffectProtocolError("device", `File ${path} does not exist`);
    }
    this.handles.set(handle, {
      path,
      mode,
      position: 0,
      data,
      dirty: false,
      failed: false,
    });
    return handle;
  }

  read(handle: number, maximum: number): Uint8Array {
    const entry = this.entry(handle, "read");
    integer(maximum, "read length", 0xffff);
    const end = Math.min(entry.position + maximum, entry.data.length);
    const result = entry.data.slice(entry.position, end);
    entry.position = end;
    return result;
  }

  write(handle: number, bytes: Uint8Array): void {
    const entry = this.entry(handle, "write");
    const incoming = checkedBytes(bytes, "file write");
    const end = entry.position + incoming.length;
    if (end > this.maxFileBytes) {
      entry.failed = true;
      throw new EffectProtocolError("capacity", "File exceeds its size limit");
    }
    const data = new Uint8Array(Math.max(entry.data.length, end));
    data.set(entry.data);
    data.set(incoming, entry.position);
    entry.data = data;
    entry.position = end;
    entry.dirty = true;
  }

  close(handle: number): void {
    const entry = this.entry(handle);
    if (!entry.failed && entry.mode === "write") this.commit(entry);
    this.handles.delete(handle);
  }

  sync(handle: number): void {
    const entry = this.entry(handle, "write");
    if (!entry.failed) this.commit(entry);
  }

  status(handle: number): FileHandleStatus {
    const entry = this.entry(handle);
    return {
      mode: entry.mode,
      position: entry.position,
      length: entry.data.length,
      dirty: entry.dirty,
    };
  }

  abort(handle: number): void {
    this.handles.delete(handle);
  }

  private allocateHandle(): number {
    for (let count = 0; count < 0xffff; count++) {
      const handle = this.nextHandle;
      this.nextHandle = this.nextHandle === 0xffff ? 1 : this.nextHandle + 1;
      if (!this.handles.has(handle)) return handle;
    }
    throw new EffectProtocolError("capacity", "File handle table is full");
  }

  private entry(handle: number, mode?: FileMode): MemoryHandle {
    const entry = this.handles.get(handle);
    if (entry === undefined) {
      throw new EffectProtocolError("device", "File handle is not open");
    }
    if (mode !== undefined && entry.mode !== mode) {
      throw new EffectProtocolError(
        "device",
        `File handle is open for ${entry.mode}, not ${mode}`,
      );
    }
    return entry;
  }

  private commit(entry: MemoryHandle): void {
    this.files.set(entry.path, entry.data.slice());
    entry.dirty = false;
  }
}
