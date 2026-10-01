/** Bounded Scheme-facing ports above the provider effect boundary. */

import {
  EffectProtocolError,
  type EffectProtocolErrorCode,
} from "./effect-wire.ts";

export const PORT_SLOT_COUNT = 8;
export const STANDARD_PORT_COUNT = 3;
export const ADDITIONAL_PORT_COUNT = PORT_SLOT_COUNT - STANDARD_PORT_COUNT;
export const PORT_GENERATION_MAX = 0x1ff;
export const PORT_REPLY_BYTES = 0xff;
export const PORT_TOKEN_BASE = 0xf000;
export const CALL_EC_TOKEN_BASE = 0xe000;
export const CALL_EC_TOKEN_END = 0xefff;

export const PORT_EOF = Symbol("skate-port-eof");

export type PortDirection = "input" | "output";
export type PortMode = "text" | "binary";
export type PortErrorCode =
  | "wrong-direction"
  | "closed"
  | "unsupported"
  | "capacity"
  | "transport"
  | "malformed"
  | "device"
  | "would-block"
  | "not-port";

export class PortError extends Error {
  constructor(
    readonly code: PortErrorCode,
    message: string,
    readonly protocolCode?: EffectProtocolErrorCode,
  ) {
    super(message);
    this.name = "PortError";
  }
}

export type PortReadResult =
  | { readonly status: "data"; readonly bytes: Uint8Array }
  | { readonly status: "eof" }
  | { readonly status: "empty" }
  | { readonly status: "pending"; readonly task?: number }
  | {
    readonly status: "error";
    readonly code: PortErrorCode;
    readonly message: string;
    readonly protocolCode?: EffectProtocolErrorCode;
  };

export interface PortProvider {
  read(handle: number, maximum: number): PortReadResult;
  write(handle: number, bytes: Uint8Array): void;
  close(handle: number): void;
  /** True when adopting this handle without abort-safe ownership is unsafe. */
  requiresTransactional?(handle: number): boolean;
  /** Discard a rejected handle without committing a writable operation. */
  release?(handle: number): void;
  abort?(handle: number): void;
  /** True only when retrying a failed close is part of the provider contract. */
  closeIdempotent?: boolean;
  flush?(handle: number): void;
}

export interface OpenPortOptions {
  readonly handle: number;
  readonly direction: PortDirection;
  readonly mode?: PortMode;
  readonly translateControlZ?: boolean;
  readonly newline?: "crlf" | "lf";
  readonly transactional?: boolean;
}

interface PortRecord {
  readonly slot: number;
  readonly standard: boolean;
  generation: number;
  state: "free" | "open" | "closed" | "poisoned" | "retired";
  owned: boolean;
  handle: number;
  direction: PortDirection;
  mode: PortMode;
  translateControlZ: boolean;
  newline: "crlf" | "lf";
  transactional: boolean;
  pending: number[];
  skipLf: boolean;
  eof: boolean;
}

export interface StandardPortHandles {
  readonly input: number;
  readonly output: number;
  readonly error: number;
}

/** Translation policy for the three standard ports. */
export interface StandardPortProfile {
  readonly inputTranslateControlZ?: boolean;
  readonly outputNewline?: "crlf" | "lf";
  readonly errorNewline?: "crlf" | "lf";
}

export interface PortCleanupResult {
  readonly closed: number[];
  readonly aborted: number[];
  readonly failures: readonly PortError[];
}

function tokenFor(slot: number, generation: number): number {
  return PORT_TOKEN_BASE | (generation << 3) | slot;
}

function decodeToken(value: unknown):
  | { readonly slot: number; readonly generation: number }
  | undefined {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value < 0 ||
    value > 0xffff ||
    (value & 0xf000) !== PORT_TOKEN_BASE
  ) {
    return undefined;
  }
  const slot = value & 7;
  const generation = (value & 0x0ff8) >>> 3;
  if (generation < 1 || generation > PORT_GENERATION_MAX) return undefined;
  return { slot, generation };
}

function asPortError(error: unknown, fallback: PortErrorCode): PortError {
  if (error instanceof PortError) return error;
  if (error instanceof EffectProtocolError) {
    const code: PortErrorCode = error.code === "empty"
      ? "would-block"
      : error.code === "invalid-command" ||
          error.code === "invalid-event" ||
          error.code === "truncated" ||
          error.code === "checksum" ||
          error.code === "version"
      ? "malformed"
      : error.code === "malformed" ||
          error.code === "capacity" ||
          error.code === "unsupported" ||
          error.code === "device"
      ? error.code
      : fallback;
    return new PortError(code, error.message, error.code);
  }
  return new PortError(
    fallback,
    error instanceof Error ? error.message : String(error),
  );
}

function checkByte(value: number, name: string): void {
  if (!Number.isInteger(value) || value < 0 || value > 0xff) {
    throw new PortError("malformed", `${name} must be a byte`);
  }
}

function checkHandle(handle: number): void {
  if (!Number.isInteger(handle) || handle < 0 || handle > 0xffff) {
    throw new PortError("malformed", "provider handle is not a word");
  }
}

/**
 * Provider-neutral port table. It owns logical text translation and bounded
 * pending bytes; the provider owns handles and physical I/O.
 */
export class PortTable {
  private readonly records: PortRecord[];

  constructor(
    private readonly provider: PortProvider,
    standard: StandardPortHandles,
    profile: StandardPortProfile = {},
  ) {
    checkHandle(standard.input);
    checkHandle(standard.output);
    checkHandle(standard.error);
    const inputTranslateControlZ = profile.inputTranslateControlZ ?? true;
    const outputNewline = profile.outputNewline ?? "crlf";
    const errorNewline = profile.errorNewline ?? "crlf";
    this.records = Array.from({ length: PORT_SLOT_COUNT }, (_, slot) => ({
      slot,
      standard: slot < STANDARD_PORT_COUNT,
      generation: slot < STANDARD_PORT_COUNT ? 1 : 0,
      state: slot < STANDARD_PORT_COUNT ? "open" : "free",
      owned: slot < STANDARD_PORT_COUNT,
      handle: slot === 0
        ? standard.input
        : slot === 1
        ? standard.output
        : slot === 2
        ? standard.error
        : 0,
      direction: slot === 0 ? "input" : "output",
      mode: "text",
      translateControlZ: slot === 0 ? inputTranslateControlZ : false,
      newline: slot === 2 ? errorNewline : outputNewline,
      transactional: false,
      pending: [],
      skipLf: false,
      eof: false,
    }));
  }

  currentInputPort(): number {
    return tokenFor(0, 1);
  }

  currentOutputPort(): number {
    return tokenFor(1, 1);
  }

  currentErrorPort(): number {
    return tokenFor(2, 1);
  }

  open(options: OpenPortOptions): number {
    checkHandle(options.handle);
    const transactional = options.transactional ?? false;
    const requiresTransactional = !transactional &&
      this.provider.requiresTransactional?.(options.handle) === true;
    if (requiresTransactional) {
      if (
        this.provider.abort === undefined && this.provider.release === undefined
      ) {
        throw new PortError(
          "unsupported",
          "provider cannot abort a required transactional handle",
        );
      }
      this.releaseRejected(options.handle, true);
      throw new PortError(
        "unsupported",
        "provider handle requires a transactional port",
      );
    }
    if (transactional && this.provider.abort === undefined) {
      if (this.provider.release !== undefined) {
        this.releaseRejected(options.handle, true);
      }
      throw new PortError(
        "unsupported",
        "transactional ports require provider abort support",
      );
    }
    let slot: PortRecord | undefined;
    for (const candidate of this.records) {
      if (
        candidate.standard || candidate.state === "poisoned" ||
        candidate.state === "retired"
      ) {
        continue;
      }
      if (
        (candidate.state === "free" || candidate.state === "closed") &&
        candidate.generation >= PORT_GENERATION_MAX
      ) {
        candidate.state = "retired";
        continue;
      }
      if (candidate.state === "free" || candidate.state === "closed") {
        slot = candidate;
        break;
      }
    }
    if (slot === undefined) {
      this.releaseRejected(options.handle, transactional);
      throw new PortError("capacity", "port table is full");
    }
    slot.generation++;
    slot.state = "open";
    slot.owned = true;
    slot.handle = options.handle;
    slot.direction = options.direction;
    slot.mode = options.mode ?? "text";
    slot.translateControlZ = options.translateControlZ ?? false;
    slot.newline = options.newline ?? "crlf";
    slot.transactional = transactional;
    slot.pending.length = 0;
    slot.skipLf = false;
    slot.eof = false;
    return tokenFor(slot.slot, slot.generation);
  }

  isPort(value: unknown): value is number {
    return this.lookup(value) !== undefined;
  }

  isInputPort(value: unknown): boolean {
    return this.lookup(value)?.direction === "input";
  }

  isOutputPort(value: unknown): boolean {
    return this.lookup(value)?.direction === "output";
  }

  readChar(value: unknown): number | typeof PORT_EOF {
    const record = this.requireOpen(value);
    this.requireDirection(record, "input");
    if (record.mode !== "text") {
      throw new PortError("unsupported", "read-char requires a text port");
    }
    for (;;) {
      const raw = this.pullByte(record);
      if (raw === PORT_EOF) {
        record.skipLf = false;
        return PORT_EOF;
      }
      if (record.skipLf) {
        record.skipLf = false;
        if (raw === 0x0a) continue;
      }
      if (record.translateControlZ && raw === 0x1a) {
        record.pending.length = 0;
        record.eof = true;
        return PORT_EOF;
      }
      if (raw === 0x0d) {
        record.skipLf = true;
        return 0x0a;
      }
      if (raw === 0x0a) return 0x0a;
      return raw;
    }
  }

  readBytes(value: unknown, maximum: number): Uint8Array {
    const record = this.requireOpen(value);
    this.requireDirection(record, "input");
    if (record.mode !== "binary") {
      throw new PortError("unsupported", "read-bytes requires a binary port");
    }
    if (
      !Number.isInteger(maximum) || maximum < 0 || maximum > PORT_REPLY_BYTES
    ) {
      throw new PortError(
        "capacity",
        `read size must be 0 through ${PORT_REPLY_BYTES}`,
      );
    }
    while (record.pending.length < maximum && !record.eof) {
      this.fetch(record, Math.max(1, maximum - record.pending.length));
      if (record.pending.length === 0 && record.eof) break;
    }
    const bytes = record.pending.splice(0, maximum);
    return Uint8Array.from(bytes);
  }

  writeChar(value: unknown, character: number): void {
    const record = this.requireOpen(value);
    this.requireDirection(record, "output");
    if (record.mode !== "text") {
      throw new PortError("unsupported", "write-char requires a text port");
    }
    checkByte(character, "character");
    if (character === 0x0a && record.newline === "crlf") {
      this.writeRaw(record, Uint8Array.of(0x0d, 0x0a));
    } else {
      this.writeRaw(record, Uint8Array.of(character));
    }
  }

  writeText(value: unknown, bytes: Uint8Array): void {
    const record = this.requireOpen(value);
    this.requireDirection(record, "output");
    if (record.mode !== "text") {
      throw new PortError("unsupported", "text output requires a text port");
    }
    if (!(bytes instanceof Uint8Array)) {
      throw new PortError("malformed", "text output must be bytes");
    }
    for (const byte of bytes) this.writeChar(value, byte);
  }

  writeBytes(value: unknown, bytes: Uint8Array): void {
    const record = this.requireOpen(value);
    this.requireDirection(record, "output");
    if (record.mode !== "binary") {
      throw new PortError("unsupported", "write-bytes requires a binary port");
    }
    if (!(bytes instanceof Uint8Array) || bytes.length > PORT_REPLY_BYTES) {
      throw new PortError(
        "capacity",
        "binary write exceeds the native chunk bound",
      );
    }
    this.writeRaw(record, bytes);
  }

  newline(value: unknown): void {
    this.writeChar(value, 0x0a);
  }

  flush(value: unknown): void {
    const record = this.requireOpen(value);
    this.requireDirection(record, "output");
    if (this.provider.flush === undefined) return;
    try {
      this.provider.flush(record.handle);
    } catch (error) {
      throw asPortError(error, "transport");
    }
  }

  closePort(value: unknown): void {
    const record = this.requireRecord(value);
    if (record.standard) {
      throw new PortError("unsupported", "standard ports cannot be closed");
    }
    if (record.state === "closed") return;
    if (record.state !== "open") {
      throw new PortError("closed", "port is not open");
    }
    try {
      this.provider.close(record.handle);
      record.state = "closed";
      record.owned = false;
    } catch (error) {
      record.state = "poisoned";
      throw asPortError(error, "transport");
    }
  }

  cleanup(fatal = false): PortCleanupResult {
    const closed: number[] = [];
    const aborted: number[] = [];
    const failures: PortError[] = [];
    for (const record of this.records) {
      if (
        record.standard ||
        !record.owned ||
        (record.state !== "open" && record.state !== "poisoned" &&
          record.state !== "retired")
      ) continue;
      try {
        const retired = record.state === "retired";
        const shouldAbort = fatal &&
          (record.transactional || record.state === "poisoned" || retired);
        if (shouldAbort && this.provider.abort !== undefined) {
          this.provider.abort(record.handle);
          aborted.push(record.slot);
        } else if (
          (record.state === "poisoned" || retired) &&
          !this.provider.closeIdempotent
        ) {
          throw new PortError(
            "device",
            "provider does not permit retrying a failed close",
          );
        } else if (shouldAbort) {
          throw new PortError(
            "unsupported",
            "provider has no abort operation",
          );
        } else {
          this.provider.close(record.handle);
          closed.push(record.slot);
        }
        record.owned = false;
        if (!retired) record.state = "closed";
      } catch (error) {
        record.state = "poisoned";
        failures.push(asPortError(error, "transport"));
      }
    }
    return { closed, aborted, failures };
  }

  reset(): PortCleanupResult {
    const result = this.cleanup(true);
    for (const record of this.records) {
      if (record.standard || record.state === "open") continue;
      if (record.state === "poisoned") {
        // Invalidate the token even when the provider could not release it.
        // An exhausted slot remains retired through later recovery; it must
        // never issue an earlier generation again.
        if (record.generation < PORT_GENERATION_MAX) {
          record.generation++;
        } else {
          record.state = "retired";
        }
        continue;
      }
      if (record.state === "retired") continue;
      if (record.generation >= PORT_GENERATION_MAX) {
        record.state = "retired";
      } else {
        record.generation++;
        record.state = "free";
      }
    }
    return result;
  }

  private lookup(value: unknown): PortRecord | undefined {
    const decoded = decodeToken(value);
    if (decoded === undefined) return undefined;
    const record = this.records[decoded.slot];
    if (record === undefined || record.generation !== decoded.generation) {
      return undefined;
    }
    if (record.state === "free" || record.state === "retired") return undefined;
    return record;
  }

  private requireRecord(value: unknown): PortRecord {
    const record = this.lookup(value);
    if (record === undefined) {
      throw new PortError("not-port", "value is not a current port");
    }
    return record;
  }

  private requireOpen(value: unknown): PortRecord {
    const record = this.requireRecord(value);
    if (record.state !== "open") {
      throw new PortError("closed", "port is closed");
    }
    return record;
  }

  private requireDirection(record: PortRecord, direction: PortDirection): void {
    if (record.direction !== direction) {
      throw new PortError(
        "wrong-direction",
        `port is not open for ${direction}`,
      );
    }
  }

  private fetch(record: PortRecord, maximum: number): void {
    if (record.eof) return;
    const request = Math.min(PORT_REPLY_BYTES, Math.max(1, maximum));
    let result: PortReadResult;
    try {
      result = this.provider.read(record.handle, request);
    } catch (error) {
      throw asPortError(error, "transport");
    }
    if (result.status === "eof") {
      record.eof = true;
      return;
    }
    if (result.status === "empty" || result.status === "pending") {
      throw new PortError("would-block", "provider has no text byte yet");
    }
    if (result.status === "error") {
      throw new PortError(result.code, result.message, result.protocolCode);
    }
    if (!(result.bytes instanceof Uint8Array) || result.bytes.length === 0) {
      throw new PortError(
        "malformed",
        "provider returned an empty data result",
      );
    }
    if (
      result.bytes.length > request || result.bytes.length > PORT_REPLY_BYTES
    ) {
      throw new PortError("capacity", "provider reply exceeds the port bound");
    }
    if (record.pending.length + result.bytes.length > PORT_REPLY_BYTES) {
      throw new PortError("capacity", "port pending-byte queue is full");
    }
    record.pending.push(...result.bytes);
  }

  private pullByte(record: PortRecord): number | typeof PORT_EOF {
    if (record.pending.length === 0) {
      this.fetch(record, PORT_REPLY_BYTES);
    }
    if (record.pending.length === 0) return PORT_EOF;
    return record.pending.shift()!;
  }

  private writeRaw(record: PortRecord, bytes: Uint8Array): void {
    try {
      this.provider.write(record.handle, bytes);
    } catch (error) {
      throw asPortError(error, "transport");
    }
  }

  private releaseRejected(handle: number, transactional: boolean): void {
    try {
      if (transactional && this.provider.abort !== undefined) {
        this.provider.abort(handle);
      } else if (transactional && this.provider.release !== undefined) {
        this.provider.release(handle);
      } else {
        this.provider.close(handle);
      }
    } catch (error) {
      throw asPortError(error, "transport");
    }
  }
}
