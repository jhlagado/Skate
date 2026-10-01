import assert from "node:assert/strict";

import { encodeAsoImage } from "../../tools/aso.ts";
import { validateAso } from "./aso-proof.mjs";

function padded(byte, length = 128) {
  const bytes = new Uint8Array(length).fill(0x1a);
  bytes[0] = byte;
  return bytes;
}

Deno.test("ASO proof accepts one exact CP/M record", () => {
  const aso = encodeAsoImage({ origin: 0x100, bytes: Uint8Array.of(0xc9) });
  assert.deepEqual(validateAso(aso, padded(0xc9), "ONE"), {
    imageBytes: 1,
    asoBytes: aso.length,
  });
});

Deno.test("ASO proof rejects missing or extra COM records", () => {
  const aso = encodeAsoImage({ origin: 0x100, bytes: Uint8Array.of(0xc9) });
  assert.throws(
    () => validateAso(aso, Uint8Array.of(0xc9), "SHORT"),
    /whole CP\/M record count/,
  );
  assert.throws(
    () => validateAso(aso, new Uint8Array(256).fill(0x1a), "LONG"),
    /whole CP\/M record count/,
  );
});

Deno.test("ASO proof rejects zero bytes in COM padding", () => {
  const aso = encodeAsoImage({ origin: 0x100, bytes: Uint8Array.of(0xc9) });
  const com = padded(0xc9);
  com[1] = 0;
  assert.throws(() => validateAso(aso, com, "ZERO"), /non-padding/);
});
