import assert from "node:assert/strict";
import {
  decodeEffectFrame,
  EffectProtocolError,
  encodeEffectCommand,
  encodeEffectFrame,
} from "./effect-protocol.ts";
import {
  encodeEffectText,
  type MixedEffectItem,
  MixedEffectStreamDecoder,
} from "./effect-stream.ts";

function join(...parts: Uint8Array[]): Uint8Array {
  const result = new Uint8Array(
    parts.reduce((length, part) => length + part.length, 0),
  );
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

function collect(items: readonly MixedEffectItem[]): {
  readonly text: Uint8Array;
  readonly frames: ReturnType<typeof decodeEffectFrame>[];
} {
  const textParts = items.filter((item) => item.type === "text").map((item) =>
    item.bytes
  );
  const text = join(...textParts);
  const frames = items.filter((item) => item.type === "frame").map((item) =>
    item.frame
  );
  return { text, frames };
}

Deno.test("mixed stream preserves text, literal markers and frame order at every split", () => {
  const firstText = encodeEffectText(Uint8Array.of(0x41, 0x1b, 0x7e, 0x42));
  const frame = encodeEffectCommand(
    { type: "control", capability: 9, bytes: Uint8Array.of(0x33) },
    7,
  );
  const secondText = encodeEffectText(Uint8Array.of(0x43, 0x1b, 0x44));
  const stream = join(firstText, frame, secondText);
  for (let split = 0; split <= stream.length; split++) {
    const decoder = new MixedEffectStreamDecoder();
    const items = [
      ...decoder.push(stream.slice(0, split)),
      ...decoder.push(stream.slice(split)),
    ];
    decoder.finish();
    const kinds: string[] = [];
    for (const item of items) {
      if (kinds.at(-1) !== item.type) kinds.push(item.type);
    }
    assert.deepEqual(kinds, ["text", "frame", "text"]);
    const result = collect(items);
    assert.deepEqual(
      result.text,
      Uint8Array.of(0x41, 0x1b, 0x7e, 0x42, 0x43, 0x1b, 0x44),
    );
    assert.deepEqual(result.frames, [decodeEffectFrame(frame)]);
  }
});

Deno.test("literal ESC encoding is unambiguous", () => {
  assert.deepEqual(
    encodeEffectText(Uint8Array.of(0x1b, 0x7e)),
    Uint8Array.of(0x1b, 0x1b, 0x7e),
  );
  const decoder = new MixedEffectStreamDecoder();
  assert.deepEqual(
    collect(decoder.push(Uint8Array.of(0x1b, 0x1b, 0x7e))).text,
    Uint8Array.of(0x1b, 0x7e),
  );
  decoder.finish();
});

Deno.test("incomplete and corrupt frames remain protocol errors", () => {
  const frame = encodeEffectFrame({
    kind: "request",
    opcode: 1,
    correlation: 1,
    payload: Uint8Array.of(0x41),
  });
  const partial = new MixedEffectStreamDecoder();
  partial.push(frame.slice(0, -1));
  assert.throws(
    () => partial.finish(),
    (error) =>
      error instanceof EffectProtocolError && error.code === "truncated",
  );
  const corrupt = frame.slice();
  corrupt[corrupt.length - 1] ^= 1;
  assert.throws(
    () => new MixedEffectStreamDecoder().push(corrupt),
    (error) =>
      error instanceof EffectProtocolError && error.code === "checksum",
  );
});

Deno.test("an unpaired ESC at end of stream is rejected", () => {
  const decoder = new MixedEffectStreamDecoder();
  assert.deepEqual(decoder.push(Uint8Array.of(0x41)), [
    { type: "text", bytes: Uint8Array.of(0x41) },
  ]);
  decoder.push(Uint8Array.of(0x1b));
  assert.throws(
    () => decoder.finish(),
    (error) =>
      error instanceof EffectProtocolError && error.code === "truncated",
  );
});
