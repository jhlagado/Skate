import assert from "node:assert/strict";

import { materializeAso } from "../../tools/aso.ts";

/** Check that an ASO image is the complete runnable prefix of a COM file. */
export function validateAso(aso, com, name) {
  const image = materializeAso([aso]);
  assert.equal(image.origin, 0x0100, `${name}: ASO origin`);
  assert.equal(
    image.finalCursor,
    image.highWater,
    `${name}: ASO final cursor differs from high-water mark`,
  );
  const expectedComLength = Math.ceil(image.bytes.length / 128) * 128;
  assert.equal(
    com.length,
    expectedComLength,
    `${name}: COM length is not a whole CP/M record count`,
  );
  assert.deepEqual(
    image.bytes,
    com.slice(0, image.bytes.length),
    `${name}: ASO image differs from COM`,
  );
  for (const padding of com.slice(image.bytes.length)) {
    assert.ok(
      padding === 0x1a,
      `${name}: non-padding after COM image`,
    );
  }
  return { imageBytes: image.bytes.length, asoBytes: aso.length };
}
