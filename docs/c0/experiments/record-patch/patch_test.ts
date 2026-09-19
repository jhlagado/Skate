import assert from "node:assert/strict";
import { machine } from "./machine.ts";
const fixture = await machine();
Deno.test("native staged patch covers every alignment and size without touching neighbours", () => {
  for (let offset = 0; offset < 256; offset++) {
    for (let size = 1; size <= 4; size++) {
      const before = Uint8Array.from({ length: 384 }, (_, i) => i & 255);
      const bytes = Uint8Array.from({ length: size }, (_, i) => 0xe0 + i);
      const got = fixture.patch(before, offset, bytes);
      const expected = before.slice();
      expected.set(bytes, offset);
      assert.deepEqual(got.disk, expected);
      assert.equal(got.status, 0);
      assert.equal(got.carry, 0);
      const records = Math.floor((offset + size - 1) / 128) -
        Math.floor(offset / 128) + 1;
      assert.equal(got.reads, records);
      assert.equal(got.writes, records);
      assert.equal(got.stack, 6);
      assert.equal(got.dmaSelections, 1);
    }
  }
});
Deno.test("native patch checks length and logical EOF before any disk transfer", () => {
  const file = new Uint8Array(257).fill(0x55);
  for (
    const [offset, size] of [[0, 0], [0, 5], [257, 1], [255, 3], [65535, 2]]
  ) {
    const got = fixture.patch(file, offset, new Uint8Array(size));
    assert.equal(got.status, 1);
    assert.equal(got.carry, 1);
    assert.equal(got.dmaSelections, 0);
    assert.equal(got.reads, 0);
    assert.equal(got.writes, 0);
    assert.deepEqual(got.disk.slice(0, file.length), file);
  }
  const good = fixture.patch(file, 256, Uint8Array.of(0xc9));
  assert.equal(good.status, 0);
  assert.equal(good.disk[256], 0xc9);
  assert.ok(good.disk.slice(257).every((x) => x === 0x1a));
});
Deno.test("native patch handles 16-bit record positions and terminal I/O errors", () => {
  const file = new Uint8Array(0xe300).fill(0x11);
  const far = fixture.patch(file, file.length - 4, Uint8Array.of(1, 2, 3, 4));
  assert.equal(far.status, 0);
  assert.deepEqual(far.disk.slice(-4), Uint8Array.of(1, 2, 3, 4));
  for (const which of ["read", "write"] as const) {
    for (const nth of [1, 2]) {
      const got = fixture.patch(file, 127, Uint8Array.of(1, 2, 3, 4), {
        [which]: nth,
      });
      assert.equal(got.status, which === "read" ? 2 : 3);
      assert.equal(got.carry, 1);
      assert.equal(got.reads, nth);
      assert.equal(got.writes, which === "read" ? nth - 1 : nth);
      assert.equal(got.disk[127], nth === 2 ? 1 : 0x11);
      assert.equal(got.disk[128], 0x11);
    }
  }
});
console.log(
  JSON.stringify({
    code: fixture.code,
    workspace: fixture.work,
    qualification:
      "ATOM native helper; injected BDOS boundary, not a Portable CP/M disk/publication proof",
  }),
);
