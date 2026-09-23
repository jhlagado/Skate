/** Separate ordinary text from framed effect traffic on one byte stream. */

import {
  DEFAULT_EFFECT_LIMITS,
  type EffectFrame,
  EffectFrameDecoder,
  type EffectLimits,
  EffectProtocolError,
} from "./effect-wire.ts";

const ESC = 0x1b;
const FRAME_MARKER_TAIL = 0x7e;

export type MixedEffectItem =
  | { readonly type: "text"; readonly bytes: Uint8Array }
  | { readonly type: "frame"; readonly frame: EffectFrame };

/** Escape literal ESC bytes before writing them beside effect frames. */
export function encodeEffectText(bytes: Uint8Array): Uint8Array {
  if (!(bytes instanceof Uint8Array)) {
    throw new EffectProtocolError("malformed", "Effect text must be bytes");
  }
  let escapes = 0;
  for (const byte of bytes) if (byte === ESC) escapes++;
  if (escapes === 0) return bytes.slice();
  const encoded = new Uint8Array(bytes.length + escapes);
  let cursor = 0;
  for (const byte of bytes) {
    encoded[cursor++] = byte;
    if (byte === ESC) encoded[cursor++] = ESC;
  }
  return encoded;
}

/**
 * Decode a stream carrying escaped text and version-one effect frames.
 *
 * Text is returned in chunks at frame boundaries or input boundaries. A
 * literal ESC is written as ESC ESC. ESC followed by `~` starts a frame;
 * unescaped frame bytes are never silently returned as text.
 */
export class MixedEffectStreamDecoder {
  private readonly frames: EffectFrameDecoder;
  private escaped = false;
  private inFrame = false;

  constructor(private readonly limits: EffectLimits = DEFAULT_EFFECT_LIMITS) {
    this.frames = new EffectFrameDecoder(limits);
  }

  push(chunk: Uint8Array): MixedEffectItem[] {
    if (!(chunk instanceof Uint8Array)) {
      throw new EffectProtocolError("malformed", "Effect input must be bytes");
    }
    const items: MixedEffectItem[] = [];
    const text: number[] = [];
    const flushText = (): void => {
      if (text.length === 0) return;
      items.push({ type: "text", bytes: Uint8Array.from(text) });
      text.length = 0;
    };

    for (const byte of chunk) {
      if (this.inFrame) {
        const decoded = this.frames.push(Uint8Array.of(byte));
        for (const frame of decoded) {
          items.push({ type: "frame", frame });
          this.inFrame = false;
        }
        continue;
      }
      if (this.escaped) {
        this.escaped = false;
        if (byte === ESC) {
          text.push(ESC);
        } else if (byte === FRAME_MARKER_TAIL) {
          flushText();
          this.inFrame = true;
          this.frames.push(Uint8Array.of(ESC, FRAME_MARKER_TAIL));
        } else {
          text.push(ESC, byte);
        }
        continue;
      }
      if (byte === ESC) {
        this.escaped = true;
      } else {
        text.push(byte);
      }
    }
    flushText();
    return items;
  }

  finish(): void {
    if (this.inFrame) {
      this.frames.finish();
      throw new EffectProtocolError(
        "truncated",
        "Mixed effect stream ended inside a frame",
      );
    }
    if (this.escaped) {
      throw new EffectProtocolError(
        "truncated",
        "Mixed effect stream ended after an ESC byte",
      );
    }
  }
}
