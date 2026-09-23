/** Bounded, synchronous command/event protocol for terminal and harness providers. */

export const EFFECT_VERSION = 1;
export const EFFECT_MAGIC = Object.freeze([0x1b, 0x7e]);
export const EFFECT_HEADER_BYTES = 9;
export const EFFECT_TRAILER_BYTES = 2;
export const MAX_EFFECT_PAYLOAD_BYTES = 1024;
export const MAX_EFFECT_FRAME_BYTES = EFFECT_HEADER_BYTES +
  MAX_EFFECT_PAYLOAD_BYTES + EFFECT_TRAILER_BYTES;
export const MAX_EFFECT_EVENT_QUEUE = 64;

export type EffectFrameKind = "request" | "response" | "event";

export const EffectFrameKindCode: Readonly<Record<EffectFrameKind, number>> =
  Object.freeze({
    request: 1,
    response: 2,
    event: 3,
  });
const frameKindName: Record<number, EffectFrameKind> = {
  1: "request",
  2: "response",
  3: "event",
};

export type EffectProtocolErrorCode =
  | "malformed"
  | "version"
  | "truncated"
  | "checksum"
  | "capacity"
  | "unsupported"
  | "invalid-command"
  | "invalid-event"
  | "empty"
  | "device";

export class EffectProtocolError extends Error {
  constructor(
    readonly code: EffectProtocolErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "EffectProtocolError";
  }
}

/** Raised when the synchronous convenience API meets a deferred response. */
export class EffectPendingError extends Error {
  constructor(readonly task: number) {
    super(`Effect request is pending on task ${task}`);
    this.name = "EffectPendingError";
  }
}

export interface EffectLimits {
  readonly maxPayloadBytes: number;
  readonly maxFrameBytes: number;
  readonly maxEventQueue: number;
}

export const DEFAULT_EFFECT_LIMITS: Readonly<EffectLimits> = Object.freeze({
  maxPayloadBytes: MAX_EFFECT_PAYLOAD_BYTES,
  maxFrameBytes: MAX_EFFECT_FRAME_BYTES,
  maxEventQueue: MAX_EFFECT_EVENT_QUEUE,
});

export interface EffectFrame {
  readonly kind: EffectFrameKind;
  readonly opcode: number;
  readonly correlation: number;
  readonly payload: Uint8Array;
}

export function integer(value: number, name: string, maximum: number): void {
  if (!Number.isInteger(value) || value < 0 || value > maximum) {
    throw new RangeError(
      `${name} must be an integer from 0 through ${maximum}`,
    );
  }
}

export function taskNumber(value: number, name: string): void {
  if (!Number.isInteger(value) || value < 1 || value > 0xffff) {
    throw new RangeError(`${name} must be a task ID from 1 through 65535`);
  }
}

export function checkLimits(limits: EffectLimits): void {
  integer(limits.maxPayloadBytes, "maxPayloadBytes", 0xffff);
  integer(limits.maxFrameBytes, "maxFrameBytes", 0xffff);
  integer(limits.maxEventQueue, "maxEventQueue", 0xffff);
  if (limits.maxFrameBytes < EFFECT_HEADER_BYTES + EFFECT_TRAILER_BYTES) {
    throw new RangeError("maxFrameBytes is smaller than an effect frame");
  }
  if (
    limits.maxFrameBytes <
      EFFECT_HEADER_BYTES + Math.min(limits.maxPayloadBytes, 0xffff) +
        EFFECT_TRAILER_BYTES
  ) {
    throw new RangeError("maxFrameBytes cannot hold maxPayloadBytes");
  }
}

function crc16(bytes: Uint8Array, start: number, end: number): number {
  let crc = 0xffff;
  for (let index = start; index < end; index++) {
    crc ^= bytes[index]! << 8;
    for (let bit = 0; bit < 8; bit++) {
      crc = (crc & 0x8000) !== 0 ? (crc << 1) ^ 0x1021 : crc << 1;
      crc &= 0xffff;
    }
  }
  return crc;
}

export function writeWord(
  bytes: Uint8Array,
  offset: number,
  value: number,
): void {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = value >>> 8;
}

export function readWord(bytes: Uint8Array, offset: number): number {
  return bytes[offset]! | (bytes[offset + 1]! << 8);
}

function validateFrame(frame: EffectFrame, limits: EffectLimits): void {
  checkLimits(limits);
  if (!(frame.payload instanceof Uint8Array)) {
    throw new EffectProtocolError("malformed", "Frame payload must be bytes");
  }
  if (!(frame.kind in EffectFrameKindCode)) {
    throw new EffectProtocolError("malformed", "Unknown effect frame kind");
  }
  integer(frame.opcode, "opcode", 0xff);
  integer(frame.correlation, "correlation", 0xffff);
  if (frame.payload.length > limits.maxPayloadBytes) {
    throw new EffectProtocolError(
      "capacity",
      `Effect payload exceeds ${limits.maxPayloadBytes} bytes`,
    );
  }
}

/** Encode one complete request, response, or reserved event frame. */
export function encodeEffectFrame(
  frame: EffectFrame,
  limits: EffectLimits = DEFAULT_EFFECT_LIMITS,
): Uint8Array {
  validateFrame(frame, limits);
  const size = EFFECT_HEADER_BYTES + frame.payload.length +
    EFFECT_TRAILER_BYTES;
  if (size > limits.maxFrameBytes) {
    throw new EffectProtocolError(
      "capacity",
      `Effect frame exceeds ${limits.maxFrameBytes} bytes`,
    );
  }
  const bytes = new Uint8Array(size);
  bytes.set(EFFECT_MAGIC, 0);
  bytes[2] = EFFECT_VERSION;
  bytes[3] = EffectFrameKindCode[frame.kind];
  bytes[4] = frame.opcode;
  writeWord(bytes, 5, frame.correlation);
  writeWord(bytes, 7, frame.payload.length);
  bytes.set(frame.payload, EFFECT_HEADER_BYTES);
  writeWord(bytes, size - EFFECT_TRAILER_BYTES, crc16(bytes, 2, size - 2));
  return bytes;
}

/** Decode exactly one complete frame. Trailing bytes are rejected. */
export function decodeEffectFrame(
  bytes: Uint8Array,
  limits: EffectLimits = DEFAULT_EFFECT_LIMITS,
): EffectFrame {
  checkLimits(limits);
  if (!(bytes instanceof Uint8Array)) {
    throw new EffectProtocolError("malformed", "Effect frame must be bytes");
  }
  if (bytes.length < EFFECT_HEADER_BYTES + EFFECT_TRAILER_BYTES) {
    throw new EffectProtocolError("truncated", "Effect frame is incomplete");
  }
  if (bytes[0] !== EFFECT_MAGIC[0] || bytes[1] !== EFFECT_MAGIC[1]) {
    throw new EffectProtocolError(
      "malformed",
      "Effect frame marker is invalid",
    );
  }
  if (bytes[2] !== EFFECT_VERSION) {
    throw new EffectProtocolError(
      "version",
      `Unsupported effect protocol version ${bytes[2]}`,
    );
  }
  const kind = frameKindName[bytes[3]!];
  if (kind === undefined) {
    throw new EffectProtocolError("malformed", "Effect frame kind is invalid");
  }
  const payloadLength = readWord(bytes, 7);
  if (payloadLength > limits.maxPayloadBytes) {
    throw new EffectProtocolError(
      "capacity",
      `Effect payload exceeds ${limits.maxPayloadBytes} bytes`,
    );
  }
  const expected = EFFECT_HEADER_BYTES + payloadLength + EFFECT_TRAILER_BYTES;
  if (expected > limits.maxFrameBytes) {
    throw new EffectProtocolError(
      "capacity",
      `Effect frame exceeds ${limits.maxFrameBytes} bytes`,
    );
  }
  if (bytes.length < expected) {
    throw new EffectProtocolError(
      "truncated",
      "Effect frame payload is incomplete",
    );
  }
  if (bytes.length !== expected) {
    throw new EffectProtocolError(
      "malformed",
      "Effect frame has trailing bytes",
    );
  }
  const actualCrc = readWord(bytes, expected - EFFECT_TRAILER_BYTES);
  const expectedCrc = crc16(bytes, 2, expected - EFFECT_TRAILER_BYTES);
  if (actualCrc !== expectedCrc) {
    throw new EffectProtocolError(
      "checksum",
      "Effect frame checksum is invalid",
    );
  }
  return Object.freeze({
    kind,
    opcode: bytes[4]!,
    correlation: readWord(bytes, 5),
    payload: bytes.slice(EFFECT_HEADER_BYTES, expected - EFFECT_TRAILER_BYTES),
  });
}

/** Incremental decoder used by serial transports that deliver partial chunks. */
export class EffectFrameDecoder {
  private buffer = new Uint8Array(0);

  constructor(private readonly limits: EffectLimits = DEFAULT_EFFECT_LIMITS) {
    checkLimits(limits);
  }

  push(chunk: Uint8Array): EffectFrame[] {
    if (!(chunk instanceof Uint8Array)) {
      throw new EffectProtocolError("malformed", "Effect input must be bytes");
    }
    if (chunk.length === 0) return [];
    const combined = new Uint8Array(this.buffer.length + chunk.length);
    combined.set(this.buffer);
    combined.set(chunk, this.buffer.length);
    this.buffer = combined;
    const frames: EffectFrame[] = [];
    for (;;) {
      if (this.buffer.length < EFFECT_HEADER_BYTES) return frames;
      if (
        this.buffer[0] !== EFFECT_MAGIC[0] ||
        this.buffer[1] !== EFFECT_MAGIC[1]
      ) {
        throw new EffectProtocolError(
          "malformed",
          "Effect frame marker is invalid",
        );
      }
      const payloadLength = readWord(this.buffer, 7);
      const expected = EFFECT_HEADER_BYTES + payloadLength +
        EFFECT_TRAILER_BYTES;
      if (
        payloadLength > this.limits.maxPayloadBytes ||
        expected > this.limits.maxFrameBytes
      ) {
        throw new EffectProtocolError(
          "capacity",
          "Effect frame exceeds limits",
        );
      }
      if (this.buffer.length < expected) return frames;
      frames.push(
        decodeEffectFrame(this.buffer.slice(0, expected), this.limits),
      );
      this.buffer = this.buffer.slice(expected);
      if (this.buffer.length === 0) return frames;
    }
  }

  finish(): void {
    if (this.buffer.length !== 0) {
      throw new EffectProtocolError(
        "truncated",
        "Effect stream ended mid-frame",
      );
    }
  }
}

/** Validate a byte buffer before copying it into a protocol value. */
export function checkedBytes(value: Uint8Array, label: string): Uint8Array {
  if (!(value instanceof Uint8Array)) {
    throw new EffectProtocolError(
      "invalid-command",
      `${label} must be bytes`,
    );
  }
  return value;
}
