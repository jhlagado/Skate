/** Adapt bounded provider files to the provider-neutral Scheme port table. */

import { EffectFileClient } from "./effect-files.ts";
import { EffectPendingError } from "./effect-wire.ts";
import {
  PORT_REPLY_BYTES,
  PortError,
  type PortProvider,
  type PortReadResult,
} from "./effect-ports.ts";

/** Handles in this range are owned by this adapter, not by the text service. */
export const FILE_PORT_HANDLE_BASE = 0x8000;
export const FILE_PORT_HANDLE_END = 0xffff;

interface FilePortRecord {
  readonly rawHandle: number;
  readonly writable: boolean;
  failed: boolean;
}

/**
 * File adapter for the bounded provider service. Writable records are marked
 * failed after an unsuccessful write or sync and can only be discarded.
 */
export class EffectFilePortProvider implements PortProvider {
  private readonly files = new Map<number, FilePortRecord>();
  private nextHandle = FILE_PORT_HANDLE_BASE;

  constructor(
    private readonly inner: PortProvider,
    private readonly client: EffectFileClient,
  ) {}

  openRead(path: string): number {
    const rawHandle = this.client.open(path, "read");
    try {
      const handle = this.allocate();
      this.files.set(handle, {
        rawHandle,
        writable: false,
        failed: false,
      });
      return handle;
    } catch (error) {
      try {
        this.client.close(rawHandle);
      } catch {
        // Preserve the allocation error; read-only cleanup is best effort.
      }
      throw error;
    }
  }

  openWrite(path: string): number {
    const rawHandle = this.client.open(path, "write");
    try {
      const handle = this.allocate();
      this.files.set(handle, {
        rawHandle,
        writable: true,
        failed: false,
      });
      return handle;
    } catch (error) {
      try {
        this.client.abort(rawHandle);
      } catch {
        // Preserve the allocation error; the provider owns recovery policy.
      }
      throw error;
    }
  }

  isFileHandle(handle: number): boolean {
    return this.files.has(handle);
  }

  requiresTransactional(handle: number): boolean {
    return this.files.get(handle)?.writable ??
      this.inner.requiresTransactional?.(handle) ?? false;
  }

  read(handle: number, maximum: number): PortReadResult {
    const record = this.files.get(handle);
    if (record === undefined) return this.inner.read(handle, maximum);
    if (!Number.isInteger(maximum) || maximum < 1) {
      throw new PortError("malformed", "file read size must be positive");
    }
    if (maximum > PORT_REPLY_BYTES) {
      throw new PortError(
        "capacity",
        `file read size exceeds ${PORT_REPLY_BYTES} bytes`,
      );
    }
    try {
      const bytes = this.client.read(record.rawHandle, maximum);
      return bytes.length === 0 ? { status: "eof" } : { status: "data", bytes };
    } catch (error) {
      if (error instanceof EffectPendingError) {
        return { status: "pending", task: error.task };
      }
      throw error;
    }
  }

  write(handle: number, bytes: Uint8Array): void {
    const record = this.files.get(handle);
    if (record !== undefined) {
      if (!record.writable) {
        throw new PortError("unsupported", "file port is read-only");
      }
      if (record.failed) {
        throw new PortError("device", "file port has a failed write");
      }
      try {
        this.client.write(record.rawHandle, bytes);
      } catch (error) {
        record.failed = true;
        throw error;
      }
      return;
    }
    this.inner.write(handle, bytes);
  }

  close(handle: number): void {
    const record = this.files.get(handle);
    if (record === undefined) {
      this.inner.close(handle);
      return;
    }
    if (record.failed) this.client.abort(record.rawHandle);
    else this.client.close(record.rawHandle);
    this.files.delete(handle);
  }

  /** Abort is available now so fatal cleanup cannot commit a future write. */
  abort(handle: number): void {
    const record = this.files.get(handle);
    if (record === undefined) {
      if (this.inner.abort === undefined) {
        throw new PortError("unsupported", "inner provider has no abort");
      }
      this.inner.abort(handle);
      return;
    }
    this.client.abort(record.rawHandle);
    this.files.delete(handle);
  }

  flush(handle: number): void {
    const record = this.files.get(handle);
    if (record !== undefined) {
      if (!record.writable) return;
      if (record.failed) {
        throw new PortError("device", "file port has a failed write");
      }
      try {
        this.client.sync(record.rawHandle);
      } catch (error) {
        record.failed = true;
        throw error;
      }
      return;
    }
    this.inner.flush?.(handle);
  }

  private allocate(): number {
    for (
      let attempt = FILE_PORT_HANDLE_BASE;
      attempt <= FILE_PORT_HANDLE_END;
      attempt++
    ) {
      const handle = this.nextHandle;
      this.nextHandle = handle === FILE_PORT_HANDLE_END
        ? FILE_PORT_HANDLE_BASE
        : handle + 1;
      if (!this.files.has(handle)) return handle;
    }
    throw new PortError("capacity", "file port handle table is full");
  }
}
