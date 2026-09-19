import { deepStrictEqual, equal, throws } from "node:assert/strict";
import { ByteInterner, type InternerOptions } from "./interner.ts";

const ascii = (text: string): Uint8Array => new TextEncoder().encode(text);

Deno.test("symbol identity is case-sensitive and tables are packed little-endian", () => {
  const table = new ByteInterner({
    kind: "symbol",
    maxEntries: 3,
    maxBytes: 8,
  });
  equal(table.intern(ascii("abc")), 0);
  equal(table.intern(ascii("ABC")), 1);
  equal(table.intern(ascii("abc")), 0);
  equal(table.intern(ascii("xy")), 2);
  equal(table.count, 3);
  equal(table.usedBytes, 8);
  deepStrictEqual(table.snapshot(), {
    descriptors: Uint8Array.of(0, 0, 3, 3, 0, 3, 6, 0, 2),
    pool: ascii("abcABCxy"),
  });
  equal(table.intern(ascii("ABC")), 1);
  const before = table.snapshot();
  throws(() => table.intern(ascii("z")), /table capacity/);
  deepStrictEqual(table.snapshot(), before);
});

Deno.test("string descriptors retain arbitrary bytes, empty strings and wide offsets", () => {
  const table = new ByteInterner({
    kind: "string",
    maxEntries: 4,
    maxBytes: 258,
  });
  equal(table.intern(new Uint8Array()), 0);
  equal(table.intern(new Uint8Array(255).fill(255)), 1);
  equal(table.intern(Uint8Array.of(0)), 2);
  equal(table.intern(Uint8Array.of(128, 10)), 3);
  equal(table.intern(new Uint8Array()), 0);
  deepStrictEqual(
    table.snapshot().descriptors,
    Uint8Array.of(
      0,
      0,
      0,
      0,
      0,
      0,
      255,
      0,
      255,
      0,
      1,
      0,
      0,
      1,
      2,
      0,
    ),
  );
  equal(table.usedBytes, 258);
});

Deno.test("invalid lengths, byte types and exhausted pools do not mutate the table", () => {
  const table = new ByteInterner({
    kind: "symbol",
    maxEntries: 3,
    maxBytes: 31,
  });
  table.intern(ascii("a".repeat(31)));
  const before = table.snapshot();
  for (
    const bytes of [new Uint8Array(), ascii("a".repeat(32)), Uint8Array.of(128)]
  ) {
    throws(() => table.intern(bytes), RangeError);
    deepStrictEqual(table.snapshot(), before);
  }
  throws(() => table.intern("x" as unknown as Uint8Array), TypeError);
  throws(() => table.intern(ascii("b")), /pool capacity/);
  deepStrictEqual(table.snapshot(), before);
  equal(table.count, 1);
  equal(table.usedBytes, 31);
  equal(table.intern(ascii("a".repeat(31))), 0);
  const strings = new ByteInterner({
    kind: "string",
    maxEntries: 1,
    maxBytes: 256,
  });
  throws(() => strings.intern(new Uint8Array(256)), RangeError);
  equal(strings.count, 0);
  equal(strings.usedBytes, 0);
});

Deno.test("input and snapshot mutation cannot change interned identity", () => {
  const table = new ByteInterner({
    kind: "symbol",
    maxEntries: 2,
    maxBytes: 4,
  });
  const input = ascii("hi");
  table.intern(input);
  input[0] = 65;
  const snapshot = table.snapshot();
  snapshot.pool.fill(0);
  snapshot.descriptors.fill(0);
  equal(table.intern(ascii("hi")), 0);
  equal(table.intern(input), 1);
});

Deno.test("all 8192 IDs fit and the next insertion fails atomically", () => {
  const table = new ByteInterner({
    kind: "symbol",
    maxEntries: 8192,
    maxBytes: 32768,
  });
  for (let id = 0; id < 8192; id++) {
    equal(table.intern(ascii(id.toString(16).padStart(4, "0"))), id);
  }
  const before = table.snapshot();
  equal(table.intern(ascii("1fff")), 8191);
  throws(() => table.intern(ascii("next")), /table capacity/);
  deepStrictEqual(table.snapshot(), before);
});

Deno.test("pool may end at 65536 but offsets must remain representable", () => {
  const table = new ByteInterner({
    kind: "string",
    maxEntries: 260,
    maxBytes: 65536,
  });
  for (let id = 0; id < 257; id++) {
    const bytes = new Uint8Array(255);
    bytes[0] = id & 255;
    bytes[1] = id >>> 8;
    equal(table.intern(bytes), id);
  }
  equal(table.usedBytes, 65535);
  equal(table.intern(Uint8Array.of(42)), 257);
  equal(table.usedBytes, 65536);
  const before = table.snapshot();
  deepStrictEqual(before.descriptors.slice(-4), Uint8Array.of(255, 255, 1, 0));
  throws(() => table.intern(new Uint8Array()), /pool capacity/);
  throws(() => table.intern(Uint8Array.of(43)), /pool capacity/);
  equal(table.intern(Uint8Array.of(42)), 257);
  deepStrictEqual(table.snapshot(), before);
});

Deno.test("configured capacities are bounded integers, including zero", () => {
  for (const maxEntries of [-1, 8193, 1.5, NaN, Infinity]) {
    throws(
      () => new ByteInterner({ kind: "symbol", maxEntries, maxBytes: 1 }),
      RangeError,
    );
  }
  for (const maxBytes of [-1, 65537, 1.5, NaN, Infinity]) {
    throws(
      () => new ByteInterner({ kind: "symbol", maxEntries: 1, maxBytes }),
      RangeError,
    );
  }
  throws(
    () =>
      new ByteInterner(
        {
          kind: "bad",
          maxEntries: 1,
          maxBytes: 1,
        } as unknown as InternerOptions,
      ),
    TypeError,
  );
  const zero = new ByteInterner({ kind: "symbol", maxEntries: 0, maxBytes: 0 });
  throws(() => zero.intern(ascii("x")), /table capacity/);
  const empty = new ByteInterner({
    kind: "string",
    maxEntries: 1,
    maxBytes: 0,
  });
  equal(empty.intern(new Uint8Array()), 0);
  equal(empty.intern(new Uint8Array()), 0);
});
