import assert from "node:assert/strict";
import {
  calculate,
  integer,
  type IntegerOperation,
  signed,
  slot,
  valueKind,
} from "./contracts.ts";

Deno.test("C0 ABI2 retains every exact integer independently of the float seam", () => {
  for (let n = -32768; n <= 32767; n++) {
    const value = integer(n);
    assert.equal(signed(value), n);
    assert.equal(valueKind(value, false), "integer");
    assert.equal(valueKind(value, true), "integer");
    const bytes = slot(value);
    assert.deepEqual([...bytes], [3, n & 255, (n & 65535) >>> 8, 0]);
  }
});

Deno.test("C0 float seam classifies every tag-0 payload without aliasing integers", () => {
  let floatPatterns = 0;
  for (let bits = 0; bits < 65536; bits++) {
    // Independent arithmetic decomposition of IEEE binary16 fields.
    const exponent = Math.floor(bits / 1024) % 32;
    const fraction = bits % 1024;
    const numeric = exponent !== 31 || fraction === 0 || bits === 0x7e00;
    assert.equal(valueKind([0, bits], true) === "float", numeric);
    assert.equal(valueKind([0, bits], false) === "unsupported-float", numeric);
    if (numeric) floatPatterns++;
    assert.equal(valueKind([3, bits], true), "integer");
  }
  assert.equal(floatPatterns, 63491);
  for (const tag of [2, 4, 5, 6, 7, 8, 255]) {
    assert.equal(valueKind([tag, 42], true), "invalid");
  }
  assert.equal(valueKind([0, 0xfe00], true), "immediate");
  assert.equal(valueKind([0, 0xffff], true), "character");
});

Deno.test("C0 checked arithmetic agrees with independent BigInt boundary oracle", () => {
  const edges = [
    -32768,
    -32767,
    -256,
    -255,
    -17,
    -2,
    -1,
    0,
    1,
    2,
    17,
    255,
    256,
    32766,
    32767,
  ];
  const operations: IntegerOperation[] = [
    "add",
    "sub",
    "mul",
    "quotient",
    "remainder",
  ];
  for (const a of edges) {
    for (const b of edges) {
      for (const op of operations) {
        const x = BigInt(a), y = BigInt(b);
        if ((op === "quotient" || op === "remainder") && b === 0) {
          assert.throws(
            () => calculate(op, integer(a), integer(b)),
            /division-by-zero/,
          );
          continue;
        }
        const result = op === "add"
          ? x + y
          : op === "sub"
          ? x - y
          : op === "mul"
          ? x * y
          : op === "quotient"
          ? x / y
          : x % y;
        if (result < -32768n || result > 32767n) {
          assert.throws(
            () => calculate(op, integer(a), integer(b)),
            /overflow/,
          );
        } else {
          assert.equal(
            signed(calculate(op, integer(a), integer(b))),
            Number(result),
          );
        }
      }
    }
  }
});

Deno.test("C0 division sign and exceptional pair across all signed16 dividends", () => {
  for (let a = -32768; a <= 32767; a++) {
    for (const b of [-32768, -17, -1, 1, 17, 32767]) {
      const remainder = signed(calculate("remainder", integer(a), integer(b)));
      assert.equal(BigInt(remainder), BigInt(a) % BigInt(b));
      assert.ok(Math.abs(remainder) < Math.abs(b));
      assert.ok(remainder === 0 || Math.sign(remainder) === Math.sign(a));
      if (a === -32768 && b === -1) {
        assert.throws(
          () => calculate("quotient", integer(a), integer(b)),
          /overflow/,
        );
        assert.equal(remainder, 0);
      } else {
        const quotient = signed(calculate("quotient", integer(a), integer(b)));
        assert.equal(a, b * quotient + remainder);
        assert.equal(BigInt(quotient), BigInt(a) / BigInt(b));
      }
    }
  }
});

Deno.test("C0 arithmetic rejects nonintegers before division and overflow", () => {
  for (
    const value of [[0, 0xfe00], [0, 0x3c00], [1, 1], [3, 65536], [
      3,
      -1,
    ]] as const
  ) {
    assert.throws(() => calculate("quotient", value, integer(0)), /type/);
    assert.throws(() => calculate("mul", integer(32767), value), /type/);
  }
});
