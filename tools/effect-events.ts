import {
  checkedBytes,
  DEFAULT_EFFECT_LIMITS,
  type EffectLimits,
  EffectProtocolError,
  integer,
  readWord,
  writeWord,
} from "./effect-wire.ts";

export type EffectEvent =
  | {
    readonly type: "text";
    readonly source: number;
    readonly sequence: number;
    readonly text: string;
  }
  | {
    readonly type: "key";
    readonly source: number;
    readonly sequence: number;
    readonly key: string;
    readonly modifiers: number;
    readonly text?: string;
  }
  | {
    readonly type: "pointer";
    readonly source: number;
    readonly sequence: number;
    readonly x: number;
    readonly y: number;
    readonly buttons: number;
  }
  | {
    readonly type: "timer";
    readonly source: number;
    readonly sequence: number;
    readonly ticks: number;
  }
  | {
    readonly type: "device";
    readonly source: number;
    readonly sequence: number;
    readonly status: number;
    readonly bytes: Uint8Array;
  }
  | {
    readonly type: "data";
    readonly source: number;
    readonly sequence: number;
    readonly bytes: Uint8Array;
  }
  | {
    readonly type: "raw";
    readonly source: number;
    readonly sequence: number;
    readonly bytes: Uint8Array;
  }
  | {
    readonly type: "error";
    readonly source: number;
    readonly sequence: number;
    readonly code: number;
    readonly message: string;
  };

export const EffectEventTypeCode = Object.freeze({
  text: 1,
  key: 2,
  pointer: 3,
  timer: 4,
  device: 5,
  data: 6,
  raw: 7,
  error: 8,
});
const eventTypeName: Record<number, EffectEvent["type"]> = {
  1: "text",
  2: "key",
  3: "pointer",
  4: "timer",
  5: "device",
  6: "data",
  7: "raw",
  8: "error",
};

function utf8(value: string, label: string): Uint8Array {
  if (typeof value !== "string") {
    throw new EffectProtocolError("invalid-event", `${label} must be text`);
  }
  return new TextEncoder().encode(value);
}

function writeSignedWord(
  bytes: Uint8Array,
  offset: number,
  value: number,
): void {
  writeWord(bytes, offset, signedWord(value));
}

function signedWord(value: number): number {
  if (!Number.isInteger(value) || value < -0x8000 || value > 0x7fff) {
    throw new EffectProtocolError(
      "invalid-event",
      "signed event coordinate must be from -32768 through 32767",
    );
  }
  return value < 0 ? value + 0x10000 : value;
}

function readSignedWord(bytes: Uint8Array, offset: number): number {
  const value = readWord(bytes, offset);
  return value < 0x8000 ? value : value - 0x10000;
}

function readTextField(
  bytes: Uint8Array,
  offset: number,
): { readonly value: string; readonly next: number } {
  if (offset + 2 > bytes.length) {
    throw new EffectProtocolError(
      "invalid-event",
      "Event text length is truncated",
    );
  }
  const length = readWord(bytes, offset);
  const end = offset + 2 + length;
  if (end > bytes.length) {
    throw new EffectProtocolError("invalid-event", "Event text is truncated");
  }
  return {
    value: new TextDecoder().decode(bytes.slice(offset + 2, end)),
    next: end,
  };
}

/** Encode a normalized event or a raw byte event for a read-event response. */
export function encodeEffectEvent(
  event: EffectEvent,
  limits: EffectLimits = DEFAULT_EFFECT_LIMITS,
): Uint8Array {
  integer(event.source, "event source", 0xffff);
  integer(event.sequence, "event sequence", 0xffff);
  let size = 5;
  let textData: Uint8Array | undefined;
  let keyData: Uint8Array | undefined;
  let keyText: Uint8Array | undefined;
  let eventBytes: Uint8Array | undefined;
  if (event.type === "text") {
    textData = utf8(event.text, "event text");
    size += 2 + textData.length;
  } else if (event.type === "key") {
    keyData = utf8(event.key, "event key");
    keyText = event.text === undefined
      ? undefined
      : utf8(event.text, "event text");
    integer(event.modifiers, "event modifiers", 0xff);
    size += 1 + 2 + keyData.length + 2 + (keyText?.length ?? 0);
  } else if (event.type === "pointer") {
    signedWord(event.x);
    signedWord(event.y);
    integer(event.buttons, "event buttons", 0xff);
    size += 5;
  } else if (event.type === "timer") {
    integer(event.ticks, "event ticks", 0xffffffff);
    size += 4;
  } else if (event.type === "device") {
    integer(event.status, "device status", 0xff);
    eventBytes = checkedBytes(event.bytes, "device bytes");
    size += 1 + 2 + eventBytes.length;
  } else if (event.type === "data" || event.type === "raw") {
    eventBytes = checkedBytes(event.bytes, `${event.type} bytes`);
    size += 2 + eventBytes.length;
  } else {
    integer(event.code, "event error code", 0xff);
    const message = utf8(event.message, "event error message");
    eventBytes = message;
    size += 1 + 2 + message.length;
  }
  if (size > limits.maxPayloadBytes) {
    throw new EffectProtocolError(
      "capacity",
      "Effect event exceeds payload capacity",
    );
  }
  const payload = new Uint8Array(size);
  payload[0] = EffectEventTypeCode[event.type];
  writeWord(payload, 1, event.source);
  writeWord(payload, 3, event.sequence);
  let cursor = 5;
  if (event.type === "text") {
    writeWord(payload, cursor, textData!.length);
    payload.set(textData!, cursor + 2);
  } else if (event.type === "key") {
    payload[cursor++] = event.modifiers;
    writeWord(payload, cursor, keyData!.length);
    cursor += 2;
    payload.set(keyData!, cursor);
    cursor += keyData!.length;
    writeWord(payload, cursor, keyText?.length ?? 0xffff);
    if (keyText !== undefined) payload.set(keyText, cursor + 2);
  } else if (event.type === "pointer") {
    writeSignedWord(payload, cursor, event.x);
    writeSignedWord(payload, cursor + 2, event.y);
    payload[cursor + 4] = event.buttons;
  } else if (event.type === "timer") {
    payload[cursor] = event.ticks & 0xff;
    payload[cursor + 1] = (event.ticks >>> 8) & 0xff;
    payload[cursor + 2] = (event.ticks >>> 16) & 0xff;
    payload[cursor + 3] = event.ticks >>> 24;
  } else if (event.type === "device") {
    payload[cursor++] = event.status;
    writeWord(payload, cursor, eventBytes!.length);
    payload.set(eventBytes!, cursor + 2);
  } else if (event.type === "data" || event.type === "raw") {
    writeWord(payload, cursor, eventBytes!.length);
    payload.set(eventBytes!, cursor + 2);
  } else {
    payload[cursor++] = event.code;
    writeWord(payload, cursor, eventBytes!.length);
    payload.set(eventBytes!, cursor + 2);
  }
  return payload;
}

export function decodeEffectEvent(payload: Uint8Array): EffectEvent {
  if (!(payload instanceof Uint8Array) || payload.length < 5) {
    throw new EffectProtocolError(
      "invalid-event",
      "Event payload is truncated",
    );
  }
  const type = eventTypeName[payload[0]!];
  if (type === undefined) {
    throw new EffectProtocolError("invalid-event", "Event type is unsupported");
  }
  const source = readWord(payload, 1);
  const sequence = readWord(payload, 3);
  let cursor = 5;
  if (type === "text") {
    const text = readTextField(payload, cursor);
    if (text.next !== payload.length) {
      throw new EffectProtocolError(
        "invalid-event",
        "Text event has trailing bytes",
      );
    }
    return { type, source, sequence, text: text.value };
  }
  if (type === "key") {
    if (cursor + 3 > payload.length) {
      throw new EffectProtocolError("invalid-event", "Key event is truncated");
    }
    const modifiers = payload[cursor++]!;
    const key = readTextField(payload, cursor);
    cursor = key.next;
    if (cursor + 2 > payload.length) {
      throw new EffectProtocolError(
        "invalid-event",
        "Key text length is truncated",
      );
    }
    const textLength = readWord(payload, cursor);
    cursor += 2;
    if (textLength !== 0xffff && cursor + textLength !== payload.length) {
      throw new EffectProtocolError("invalid-event", "Key text is malformed");
    }
    if (textLength === 0xffff) {
      if (cursor !== payload.length) {
        throw new EffectProtocolError(
          "invalid-event",
          "Key event has trailing bytes",
        );
      }
      return { type, source, sequence, key: key.value, modifiers };
    }
    if (cursor + textLength > payload.length) {
      throw new EffectProtocolError("invalid-event", "Key text is truncated");
    }
    return {
      type,
      source,
      sequence,
      key: key.value,
      modifiers,
      text: new TextDecoder().decode(
        payload.slice(cursor, cursor + textLength),
      ),
    };
  }
  if (type === "pointer") {
    if (payload.length !== cursor + 5) {
      throw new EffectProtocolError(
        "invalid-event",
        "Pointer event size is invalid",
      );
    }
    return {
      type,
      source,
      sequence,
      x: readSignedWord(payload, cursor),
      y: readSignedWord(payload, cursor + 2),
      buttons: payload[cursor + 4]!,
    };
  }
  if (type === "timer") {
    if (payload.length !== cursor + 4) {
      throw new EffectProtocolError(
        "invalid-event",
        "Timer event size is invalid",
      );
    }
    return {
      type,
      source,
      sequence,
      ticks: (payload[cursor]! | (payload[cursor + 1]! << 8) |
        (payload[cursor + 2]! << 16) | (payload[cursor + 3]! << 24)) >>> 0,
    };
  }
  if (type === "device") {
    if (cursor + 3 > payload.length) {
      throw new EffectProtocolError(
        "invalid-event",
        "Device event is truncated",
      );
    }
    const status = payload[cursor++]!;
    const length = readWord(payload, cursor);
    cursor += 2;
    if (cursor + length !== payload.length) {
      throw new EffectProtocolError(
        "invalid-event",
        "Device event size is invalid",
      );
    }
    return { type, source, sequence, status, bytes: payload.slice(cursor) };
  }
  if (type === "data" || type === "raw") {
    if (cursor + 2 > payload.length) {
      throw new EffectProtocolError("invalid-event", "Byte event is truncated");
    }
    const length = readWord(payload, cursor);
    cursor += 2;
    if (cursor + length !== payload.length) {
      throw new EffectProtocolError(
        "invalid-event",
        "Byte event size is invalid",
      );
    }
    return { type, source, sequence, bytes: payload.slice(cursor) };
  }
  if (cursor + 3 > payload.length) {
    throw new EffectProtocolError("invalid-event", "Error event is truncated");
  }
  const code = payload[cursor++]!;
  const length = readWord(payload, cursor);
  cursor += 2;
  if (cursor + length !== payload.length) {
    throw new EffectProtocolError(
      "invalid-event",
      "Error event size is invalid",
    );
  }
  return {
    type,
    source,
    sequence,
    code,
    message: new TextDecoder().decode(payload.slice(cursor)),
  };
}
