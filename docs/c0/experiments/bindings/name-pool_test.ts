import assert from "node:assert/strict";
import {
  ARENA_BYTES,
  DIRECTORY_BYTES,
  NAME_COUNT,
  NamePool,
  SPELLING_BYTES,
} from "./name-pool.ts";

const name = (id: number, length: number) =>
  `n${id.toString(36).padStart(3, "0")}`.padEnd(length, "x");

function guarded() {
  const backing = new Uint8Array(ARENA_BYTES + 32).fill(0xa5);
  const arena = backing.subarray(16, 16 + ARENA_BYTES);
  const pool = new NamePool(arena);
  const checkGuards = () => {
    assert.ok(backing.subarray(0, 16).every((byte) => byte === 0xa5));
    assert.ok(
      backing.subarray(16 + ARENA_BYTES).every((byte) => byte === 0xa5),
    );
  };
  return { pool, arena, checkGuards };
}

function unchanged(
  pool: NamePool,
  arena: Uint8Array,
  action: () => unknown,
  error: RegExp,
) {
  const before = arena.slice(), metrics = pool.snapshot();
  assert.throws(action, error);
  assert.deepEqual(arena, before);
  assert.deepEqual(pool.snapshot(), metrics);
}

Deno.test("exact byte account, guarded view and directory capacity", () => {
  assert.equal(DIRECTORY_BYTES, 288 * 6);
  assert.equal(ARENA_BYTES, 6336);
  const { pool, arena, checkGuards } = guarded();
  for (let i = 0; i < NAME_COUNT; i++) assert.equal(pool.intern(name(i, 4)), i);
  assert.equal(pool.snapshot().liveNames, 288);
  unchanged(pool, arena, () => pool.intern("extra"), /directory capacity/);
  assert.equal(pool.intern(name(137, 4)), 137);
  for (let i = 0; i < NAME_COUNT; i++) {
    assert.equal(pool.spelling(i), name(i, 4));
  }
  checkGuards();
});

Deno.test("exact spelling capacity refuses one extra byte with spare IDs", () => {
  const { pool, arena, checkGuards } = guarded();
  for (let i = 0; i < 148; i++) pool.intern(name(i, 31));
  pool.intern(name(148, 20)); // 148*31 + 20 = 4608; 139 directory slots remain.
  assert.equal(pool.snapshot().liveSpellingBytes, SPELLING_BYTES);
  assert.equal(pool.snapshot().allocatedSpellingBytes, SPELLING_BYTES);
  unchanged(pool, arena, () => pool.intern("z"), /spelling capacity/);
  assert.equal(pool.intern(name(12, 31)), 12);
  checkGuards();
});

Deno.test("256 simultaneous sixteen-byte names leave exactly 512 bytes", () => {
  const { pool, arena, checkGuards } = guarded();
  for (let i = 0; i < 256; i++) pool.intern(name(i, 16));
  assert.equal(pool.snapshot().liveSpellingBytes, 4096);
  for (let i = 256; i < 272; i++) pool.intern(name(i, 31));
  pool.intern(name(272, 16));
  assert.equal(pool.snapshot().liveSpellingBytes, 4608);
  unchanged(pool, arena, () => pool.intern("z"), /spelling capacity/);
  for (let i = 0; i < 256; i++) assert.equal(pool.spelling(i), name(i, 16));
  checkGuards();
});

Deno.test("compaction preserves stable IDs and metadata after directory-slot reuse", () => {
  const { pool, checkGuards } = guarded();
  for (let i = 0; i < 148; i++) pool.intern(name(i, 31));
  for (let i = 0; i < 148; i++) {
    pool.setFlags(i, (i * 7) & 255);
    pool.setMeta(i, (65535 - i * 137) & 65535);
  }
  pool.release(0);
  pool.release(73);
  // Append fits: ID 0 now denotes a spelling physically after the other IDs.
  assert.equal(pool.intern("reuse"), 0);
  pool.setFlags(0, 255);
  pool.setMeta(0, 65535);
  assert.equal(pool.snapshot().compactions, 0);
  assert.equal(pool.intern(name(200, 31)), 73); // Requires reclamation of holes.
  assert.equal(pool.snapshot().compactions, 1);
  assert.equal(pool.spelling(0), "reuse");
  assert.equal(pool.getFlags(0), 255);
  assert.equal(pool.getMeta(0), 65535);
  assert.equal(pool.getFlags(73), 0);
  assert.equal(pool.getMeta(73), 0);
  for (let i = 1; i < 148; i++) {
    if (i === 73) continue;
    assert.equal(pool.spelling(i), name(i, 31));
    assert.equal(pool.getFlags(i), (i * 7) & 255);
    assert.equal(pool.getMeta(i), (65535 - i * 137) & 65535);
    assert.equal(pool.intern(name(i, 31)), i);
  }
  checkGuards();
});

Deno.test("failed spelling allocation does not compact or move existing names", () => {
  const { pool, arena, checkGuards } = guarded();
  for (let i = 0; i < 148; i++) pool.intern(name(i, 31));
  const small = pool.intern("small");
  pool.intern("end-of-pool-123"); // 4588 + 5 + 15 = 4608.
  pool.release(small); // Only five bytes free, with an allocated high-water of 4608.
  unchanged(pool, arena, () => pool.intern("123456"), /spelling capacity/);
  assert.equal(pool.snapshot().compactions, 0);
  assert.equal(pool.intern("abcde"), small);
  assert.equal(pool.snapshot().compactions, 1);
  checkGuards();
});

Deno.test("repeated local lifetimes retain bounded peaks and release directory IDs", () => {
  const { pool, checkGuards } = guarded();
  const anchor = pool.intern("persistent");
  for (let i = 0; i < 2000; i++) {
    const id = pool.intern(name(i, 31));
    assert.equal(id, 1);
    assert.equal(pool.spelling(anchor), "persistent");
    pool.release(id);
    assert.equal(pool.snapshot().liveNames, 1);
    assert.equal(pool.snapshot().liveSpellingBytes, 10);
  }
  const metrics = pool.snapshot();
  assert.equal(metrics.peakLiveNames, 2);
  assert.equal(metrics.peakLiveSpellingBytes, 41);
  assert.ok(metrics.peakAllocatedSpellingBytes <= SPELLING_BYTES);
  assert.ok(metrics.compactions > 0);
  pool.release(anchor);
  assert.equal(pool.snapshot().liveNames, 0);
  checkGuards();
});

Deno.test("invalid input, metadata and IDs fail before changing the arena", () => {
  const { pool, arena, checkGuards } = guarded();
  const id = pool.intern("valid");
  for (const invalid of ["", "x".repeat(32), "caf\u00e9", "\u{1f600}"]) {
    unchanged(pool, arena, () => pool.intern(invalid), /length|ASCII/);
  }
  assert.equal(pool.intern("x".repeat(31)), 1);
  for (const invalid of [-1, 1.5, 288, NaN, Infinity]) {
    unchanged(pool, arena, () => pool.release(invalid), /integer/);
    unchanged(pool, arena, () => pool.spelling(invalid), /integer/);
  }
  for (const invalid of [-1, 256, 1.5, NaN]) {
    unchanged(pool, arena, () => pool.setFlags(id, invalid), /integer/);
  }
  for (const invalid of [-1, 65536, 1.5, Infinity]) {
    unchanged(pool, arena, () => pool.setMeta(id, invalid), /integer/);
  }
  pool.release(id);
  unchanged(pool, arena, () => pool.release(id), /inactive/);
  unchanged(pool, arena, () => pool.spelling(id), /inactive/);
  unchanged(pool, arena, () => pool.setFlags(id, 1), /inactive/);
  unchanged(pool, arena, () => pool.setMeta(id, 1), /inactive/);
  checkGuards();
  for (const size of [ARENA_BYTES - 1, ARENA_BYTES + 1]) {
    const incorrect = new Uint8Array(size).fill(0xa5);
    assert.throws(() => new NamePool(incorrect), /exactly/);
    assert.ok(incorrect.every((byte) => byte === 0xa5));
  }
});
