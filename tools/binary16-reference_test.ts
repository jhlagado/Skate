import {
  add,
  CANONICAL_NAN,
  canonicalize,
  compare,
  div,
  fromInt16,
  fromRational,
  fromUint16,
  mul,
  sub,
  toInt16,
  toNumber,
  toUint16,
} from "./binary16-reference.ts";

// Local assertions keep this independent oracle free of package dependencies.
const assert = {
  equal(actual: unknown, expected: unknown): void {
    if (!Object.is(actual, expected)) {
      throw new Error(
        `Expected ${String(expected)}, received ${String(actual)}`,
      );
    }
  },
  throws(action: () => unknown, constructor: typeof RangeError): void {
    try {
      action();
    } catch (error) {
      if (error instanceof constructor) return;
      throw error;
    }
    throw new Error("Expected an exception");
  },
};

Deno.test("rational rounding covers ties, carry, underflow and overflow", () => {
  const vectors: [bigint, bigint, number][] = [
    [1n, 1n, 0x3c00],
    [2049n, 1n, 0x6800],
    [2051n, 1n, 0x6802],
    [1n, 1n << 24n, 1],
    [1n, 1n << 25n, 0],
    [-1n, 1n << 25n, 0x8000],
    [3n, 1n << 25n, 2],
    [2047n, 1n << 25n, 0x400],
    [4095n, 2048n, 0x4000],
    [65519n, 1n, 0x7bff],
    [65520n, 1n, 0x7c00],
    [-65520n, 1n, 0xfc00],
    [1n, 3n, 0x3555],
  ];
  for (const [n, d, expected] of vectors) {
    assert.equal(fromRational(n, d), expected);
  }
  assert.equal(fromRational(0n, 1n, true), 0x8000);
  assert.throws(() => fromRational(1n, 0n), RangeError);
});

Deno.test("raw arithmetic known vectors and IEEE special cases", () => {
  const vectors: [typeof add, number, number, number][] = [
    [add, 0x3c00, 0x4000, 0x4200],
    [add, 0x6800, 0x3c00, 0x6800],
    [add, 0x7bff, 0x4c00, 0x7c00],
    [add, 0x8000, 0x8000, 0x8000],
    [add, 0, 0x8000, 0],
    [sub, 0x3c00, 0x3c00, 0],
    [sub, 0x8000, 0, 0x8000],
    [sub, 0x400, 1, 0x3ff],
    [mul, 0x8000, 0xbc00, 0],
    [mul, 0, 0xbc00, 0x8000],
    [mul, 1, 0x3800, 0],
    [mul, 3, 0x3800, 2],
    [mul, 0x400, 0x3800, 0x200],
    [div, 0x3c00, 0x4200, 0x3555],
    [div, 0x3c00, 0x8000, 0xfc00],
    [div, 0xbc00, 0xfc00, 0],
    [div, 0x3c00, 0xfc00, 0x8000],
    [div, 0, 0, CANONICAL_NAN],
    [div, 0x7c00, 0xfc00, CANONICAL_NAN],
    [mul, 0x7c00, 0, CANONICAL_NAN],
    [add, 0x7c00, 0xfc00, CANONICAL_NAN],
    [sub, 0xfc00, 0xfc00, CANONICAL_NAN],
  ];
  for (const [op, a, b, expected] of vectors) assert.equal(op(a, b), expected);
});

Deno.test("every raw NaN is canonicalized by every operation", () => {
  for (let bits = 0; bits < 65536; bits++) {
    if ((bits & 0x7fff) <= 0x7c00) continue;
    assert.equal(canonicalize(bits), CANONICAL_NAN);
    assert.equal(compare(bits, 0), null);
    for (const operation of [add, sub, mul, div]) {
      assert.equal(operation(bits, 0x3c00), CANONICAL_NAN);
      assert.equal(operation(0x3c00, bits), CANONICAL_NAN);
    }
  }
});

Deno.test("every finite encoding round-trips exactly and integer conversions truncate", () => {
  for (let bits = 0; bits < 65536; bits++) {
    const value = toNumber(bits);
    if (!Number.isFinite(value)) {
      assert.equal(toInt16(bits), null);
      assert.equal(toUint16(bits), null);
      continue;
    }
    assert.equal(
      fromRational(BigInt(value * 2 ** 24), 1n << 24n, Object.is(value, -0)),
      bits,
    );
    const integer = Math.trunc(value) || 0;
    assert.equal(
      toInt16(bits),
      integer < -32768 || integer > 32767 ? null : integer,
    );
    assert.equal(
      toUint16(bits),
      integer < 0 || integer > 65535 ? null : integer,
    );
  }
});

Deno.test("all signed and unsigned 16-bit inputs agree with host half rounding", () => {
  for (let n = 0; n <= 65535; n++) {
    assert.equal(toNumber(fromUint16(n)), Math.f16round(n));
    const signed = n - 32768;
    assert.equal(toNumber(fromInt16(signed)), Math.f16round(signed));
  }
  assert.throws(() => fromInt16(32768), RangeError);
  assert.throws(() => fromInt16(-32769), RangeError);
  assert.throws(() => fromUint16(-1), RangeError);
  assert.throws(() => fromUint16(65536), RangeError);
  assert.throws(() => fromUint16(0.5), RangeError);
});

Deno.test("every adjacent finite positive midpoint selects the even encoding", () => {
  for (let lower = 0; lower < 0x7bff; lower++) {
    const sumUnits = BigInt((toNumber(lower) + toNumber(lower + 1)) * 2 ** 24);
    const expected = lower + (lower & 1);
    assert.equal(fromRational(sumUnits, 1n << 25n), expected);
    assert.equal(fromRational(-sumUnits, 1n << 25n), expected | 0x8000);
  }
});

Deno.test("deterministic raw pairs independently agree with host rounded arithmetic", () => {
  let state = 0x5ca7e;
  const next = () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state >>> 16;
  };
  const operations: [typeof add, (a: number, b: number) => number][] = [
    [add, (a, b) => a + b],
    [sub, (a, b) => a - b],
    [mul, (a, b) => a * b],
    [div, (a, b) => a / b],
  ];
  for (let trial = 0; trial < 20000; trial++) {
    const a = next();
    const b = next();
    const x = toNumber(a);
    const y = toNumber(b);
    for (const [reference, host] of operations) {
      assert.equal(toNumber(reference(a, b)), Math.f16round(host(x, y)));
    }
    assert.equal(
      compare(a, b),
      Number.isNaN(x) || Number.isNaN(y) ? null : x < y ? -1 : x > y ? 1 : 0,
    );
  }
  assert.equal(compare(0, 0x8000), 0);
  assert.equal(compare(0xfc00, 0xfbff), -1);
  assert.equal(compare(0x7bff, 0x7c00), -1);
});
