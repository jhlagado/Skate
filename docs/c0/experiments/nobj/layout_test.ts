import assert from "node:assert/strict";
import { parseNobj1 } from "@jhlagado/z80-tool-services";
import {
  commit,
  PATCH_LIMIT,
  records,
  REGION_BYTES,
  streamLayout,
} from "./layout.ts";

function once(chunks: Uint8Array[]): Iterable<Uint8Array> {
  let consumed = false;
  return {
    *[Symbol.iterator]() {
      assert.equal(consumed, false, "emitter byte stream was replayed");
      consumed = true;
      yield* chunks;
    },
  };
}

Deno.test("reserved declaration length is finalized before CRC/COMMIT", () => {
  const bytes = Uint8Array.from({ length: 1025 }, (_, i) => i & 255);
  const patches = [{ offset: 127, bytes: Uint8Array.of(0xcd, 0x34, 0x12) }, {
    offset: 1024,
    bytes: Uint8Array.of(0xc9),
  }];
  const result = streamLayout(
    once([bytes.slice(0, 113), bytes.slice(113, 896), bytes.slice(896)]),
    patches,
  );
  const expected = bytes.slice();
  for (const p of patches) expected.set(p.bytes, p.offset);
  assert.equal(result.inputChunks, 3);
  assert.deepEqual(result.modeledDiskTraversals, {
    nobjSequentialEmission: 1,
    finalCrc: 1,
    comSequentialEmission: 1,
  });
  assert.equal(result.sectionLength, 1025);
  assert.equal(result.materialized.usedLength, 1025);
  assert.deepEqual(result.com, expected);
  assert.deepEqual(result.materialized.bytes.slice(0, 1025), expected);
  assert.throws(() => parseNobj1(result.uncommitted), /COMMIT|commit/i);
});

Deno.test("complete retained-CCP image boundary and first excess", () => {
  const result = streamLayout([new Uint8Array(REGION_BYTES)], []);
  assert.equal(result.sectionLength + 0x0100, 0xe400);
  assert.throws(
    () => streamLayout([new Uint8Array(REGION_BYTES + 1)], []),
    /image capacity/,
  );
  assert.throws(() => streamLayout([], []), /empty executable/);
});

Deno.test("bounded patches accept exact capacity and reject overlap and bounds", () => {
  const patches = Array.from(
    { length: PATCH_LIMIT },
    (_, offset) => ({ offset, bytes: Uint8Array.of(offset + 1) }),
  );
  assert.equal(streamLayout([new Uint8Array(32)], patches).com[15], 16);
  assert.throws(
    () => streamLayout([new Uint8Array(32)], [...patches, patches[0]]),
    /patch capacity/,
  );
  assert.throws(
    () => streamLayout([new Uint8Array(32)], [patches[0], patches[0]]),
    /overlap/i,
  );
  assert.throws(
    () =>
      streamLayout([new Uint8Array(32)], [{
        offset: 32,
        bytes: Uint8Array.of(1),
      }]),
    /patch bounds/,
  );
});

Deno.test("real validator rejects out-of-order records even with valid checksum", () => {
  const valid = streamLayout([Uint8Array.of(0xc9)], []).objectBytes;
  const parts = records(valid).filter((r) => r.kind !== 12).map((r) => r.bytes);
  const section = parts.findIndex((r) => r[0] === 4);
  const image = parts.findIndex((r) => r[0] === 6);
  [parts[section], parts[image]] = [parts[image], parts[section]];
  assert.throws(() => parseNobj1(commit(parts)), /order|phase/i);
});

Deno.test("validator rejects stale checksum, stale length and trailing bytes", () => {
  const good = streamLayout([Uint8Array.of(0, 0, 0xc9)], []).objectBytes;
  const staleCrc = good.slice();
  staleCrc[staleCrc.length - 1] ^= 1;
  assert.throws(() => parseNobj1(staleCrc), /CRC|checksum/i);
  const parts = records(good).filter((r) => r.kind !== 12).map((r) => r.bytes);
  parts.find((r) => r[0] === 4)![9] = 1;
  assert.throws(() => parseNobj1(commit(parts)), /SECTION|section/i);
  assert.throws(
    () => parseNobj1(Uint8Array.from([...good, 0x1a])),
    /COMMIT|commit|truncat|trailing/i,
  );
});
