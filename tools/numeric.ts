/** Non-production host model of Skate's checked two-type numeric policy. */
import * as f16 from "./binary16-reference.ts";

export type Value = readonly [number, number];
export type Operation = "add" | "sub" | "mul" | "div";

export function isNumber(value: Value): boolean {
  const [tag, bits] = value;
  return Number.isInteger(bits) && bits >= 0 && bits <= 65535 &&
    (tag === 3 || (tag === 0 &&
      ((bits & 0x7fff) <= 0x7c00 || bits === f16.CANONICAL_NAN)));
}

function checked(value: Value): void {
  if (!isNumber(value)) throw new TypeError("Expected a Skate number");
}

export function integer(n: number): Value {
  if (!Number.isInteger(n) || n < -32768 || n > 32767) {
    throw new RangeError("Signed integer overflow");
  }
  return [3, n & 65535];
}

function signed(bits: number): number {
  return bits >= 32768 ? bits - 65536 : bits;
}

function floating(value: Value): number {
  return value[0] === 3 ? f16.fromInt16(signed(value[1])) : value[1];
}

export function binary(name: Operation, left: Value, right: Value): Value {
  checked(left);
  checked(right);
  if (left[0] === 3 && right[0] === 3 && name !== "div") {
    const a = signed(left[1]);
    const b = signed(right[1]);
    return integer(name === "add" ? a + b : name === "sub" ? a - b : a * b);
  }
  return [0, f16[name](floating(left), floating(right))];
}

export function negate(value: Value): Value {
  checked(value);
  return value[0] === 3
    ? integer(-signed(value[1]))
    : [0, value[1] === f16.CANONICAL_NAN ? value[1] : value[1] ^ 0x8000];
}

export function compare(left: Value, right: Value): -1 | 0 | 1 | null {
  checked(left);
  checked(right);
  const a = left[0] === 3 ? signed(left[1]) : f16.toNumber(left[1]);
  const b = right[0] === 3 ? signed(right[1]) : f16.toNumber(right[1]);
  if (Number.isNaN(a) || Number.isNaN(b)) return null;
  return a < b ? -1 : a > b ? 1 : 0;
}

/** A token-level policy model, not the production reader or its capacity rules. */
export function parseNumericToken(token: string): Value | null {
  if (token === "+inf.0") return [0, 0x7c00];
  if (token === "-inf.0") return [0, 0xfc00];
  if (token === "+nan.0") return [0, f16.CANONICAL_NAN];
  if (/^[+-]?\d+$/.test(token)) {
    const n = BigInt(token);
    if (n < -32768n || n > 32767n) {
      throw new RangeError("Integer literal out of range");
    }
    return integer(Number(n));
  }
  const match = /^([+-]?)(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([+-]?\d+))?$/
    .exec(token);
  if (!match) {
    if (/^[+-]?(?:\d|\.\d)/.test(token) || /^[+-](?:inf|nan)\./.test(token)) {
      throw new SyntaxError("Malformed numeric token");
    }
    return null;
  }
  const fraction = match[3] ?? match[4] ?? "";
  const digits = ((match[2] ?? "") + fraction).replace(/^0+/, "");
  const negative = match[1] === "-";
  if (!digits) return [0, negative ? 0x8000 : 0];
  const exponent = BigInt(match[5] ?? "0") - BigInt(fraction.length);
  const order = BigInt(digits.length - 1) + exponent;
  // Bound huge exponents before constructing powers; these bounds are safely
  // beyond binary16's largest finite value and half its smallest subnormal.
  if (order > 5n) return [0, negative ? 0xfc00 : 0x7c00];
  if (order < -9n) return [0, negative ? 0x8000 : 0];
  let numerator = BigInt(digits) * (negative ? -1n : 1n);
  let denominator = 1n;
  if (exponent >= 0n) numerator *= 10n ** exponent;
  else denominator = 10n ** -exponent;
  return [0, f16.fromRational(numerator, denominator, negative)];
}

export function formatNumber(value: Value): string {
  checked(value);
  if (value[0] === 3) return String(signed(value[1]));
  const bits = value[1];
  if (bits === f16.CANONICAL_NAN) return "+nan.0";
  if (bits === 0x7c00) return "+inf.0";
  if (bits === 0xfc00) return "-inf.0";
  if (bits === 0x8000) return "-0.0";
  const n = f16.toNumber(bits);
  for (let precision = 1; precision <= 5; precision++) {
    let token = n.toPrecision(precision);
    if (!/[.eE]/.test(token)) token += ".0";
    if (parseNumericToken(token)?.[1] === bits) return token;
  }
  throw new Error("Binary16 printer failed to round trip");
}
