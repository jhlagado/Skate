import {
  binary,
  compare,
  formatNumber,
  integer,
  isNumber,
  negate,
  parseNumericToken,
  type Value,
} from "./numeric.ts";
import { fromInt16 } from "./binary16-reference.ts";

function equal(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}
function throws(action: () => unknown, kind: typeof Error): void {
  try {
    action();
  } catch (error) {
    if (error instanceof kind) return;
    throw error;
  }
  throw new Error(`Expected ${kind.name}`);
}
const float = (token: string): Value => parseNumericToken(token)!;

Deno.test("all signed integers retain exact literal/printing identity and float coercion", () => {
  for (let n = -32768; n <= 32767; n++) {
    const value = integer(n);
    equal(parseNumericToken(formatNumber(value)), value);
    equal(binary("add", value, [0, 0x8000]), [0, fromInt16(n)]);
  }
});

Deno.test("all valid float encodings print and read with type and bits intact", () => {
  for (let bits = 0; bits <= 65535; bits++) {
    const value: Value = [0, bits];
    if (isNumber(value)) equal(parseNumericToken(formatNumber(value)), value);
  }
});

Deno.test("checked integer arithmetic reaches the counter limit and rejects overflow", () => {
  let count = integer(0);
  for (let n = 1; n <= 32767; n++) count = binary("add", count, integer(1));
  equal(count, integer(32767));
  for (
    const action of [
      () => binary("add", count, integer(1)),
      () => binary("sub", integer(-32768), integer(1)),
      () => binary("mul", integer(-32768), integer(-1)),
      () => binary("mul", integer(256), integer(128)),
      () => negate(integer(-32768)),
    ]
  ) throws(action, RangeError);
  equal(binary("sub", integer(-32767), integer(1)), integer(-32768));
  equal(binary("mul", integer(-256), integer(128)), integer(-32768));
  equal(negate(integer(32767)), integer(-32767));
});

Deno.test("mixed arithmetic rounds on coercion; division is always floating", () => {
  equal(binary("add", integer(2049), float("0.0")), float("2048.0"));
  equal(binary("div", integer(2049), integer(2048)), float("1.0"));
  equal(binary("div", integer(1), integer(0)), float("+inf.0"));
  equal(binary("div", integer(0), integer(0)), float("+nan.0"));
  equal(binary("div", integer(-32768), integer(-1)), float("32768.0"));
  equal(negate(float("+nan.0")), float("+nan.0"));
  equal(negate(float("0.0")), float("-0.0"));
  // Left folding must overflow before a later float can change the type.
  throws(
    () =>
      binary("add", binary("add", integer(32767), integer(1)), float("0.0")),
    RangeError,
  );
  equal(
    binary("add", binary("add", float("0.0"), integer(32767)), integer(1)),
    float("32768.0"),
  );
});

Deno.test("mixed comparisons preserve actual values at rounding and range boundaries", () => {
  const cases: [number, string, -1 | 0 | 1 | null][] = [
    [2049, "2048.0", 1],
    [-2049, "-2048.0", -1],
    [32767, "32768.0", -1],
    [-32768, "-32768.0", 0],
    [0, "-0.0", 0],
    [1, "1.5", -1],
    [-1, "-1.5", 1],
    [0, "0.000000059604644775390625", -1],
    [32767, "+inf.0", -1],
    [-32768, "-inf.0", 1],
    [0, "+nan.0", null],
  ];
  for (const [n, token, expected] of cases) {
    equal(compare(integer(n), float(token)), expected);
    equal(
      compare(float(token), integer(n)),
      expected === null ? null : -expected,
    );
  }
});

Deno.test("number validation rejects immediates before arithmetic or comparison", () => {
  for (
    const value of [[0, 0xfe00], [0, 0xff00], [0, 0x7e01], [1, 1], [3, -1], [
      3,
      65536,
    ], [3, 1.5]] as Value[]
  ) {
    equal(isNumber(value), false);
    throws(() => binary("add", integer(32767), value), TypeError);
    throws(() => binary("mul", value, integer(0)), TypeError);
    throws(() => compare(float("+nan.0"), value), TypeError);
    throws(() => negate(value), TypeError);
  }
});

Deno.test("numeric token grammar, exact decimal rounding, and range diagnostics", () => {
  equal(parseNumericToken("2049"), integer(2049));
  equal(parseNumericToken("2049.0"), float("2048.0"));
  equal(parseNumericToken("1e0"), float("1.0"));
  equal(parseNumericToken(".5"), float("0.5"));
  equal(parseNumericToken("-0"), integer(0));
  equal(parseNumericToken("-0e999999"), float("-0.0"));
  equal(parseNumericToken("1e999999"), float("+inf.0"));
  equal(parseNumericToken("-1e-999999"), float("-0.0"));
  for (const token of ["32768", "-32769", "999999999999999999999"]) {
    throws(() => parseNumericToken(token), RangeError);
  }
  for (const token of ["1e", "1e+", "12abc", "1.2.3", "+nan.1"]) {
    throws(() => parseNumericToken(token), SyntaxError);
  }
  for (const token of ["+", "-", "hello", "."]) {
    equal(parseNumericToken(token), null);
  }
});
