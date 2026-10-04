// Bit-exact host reference for Skate's twenty-four-bit float (docs/float24.md).
//
// Every operation forms the exact result as a rational number and rounds it
// once to nearest, ties to even.  The runtime's Z80 routines are checked
// against these functions by tests/compiler-checks/float24_test.ts.

export const SIGN = 0x800000;
export const EXP_SHIFT = 16;
export const EXP_MASK = 0x7f;
export const FRAC_MASK = 0xffff;
export const BIAS = 63;
export const NAN = 0x7f8000;
export const POS_INF = 0x7f0000;
export const NEG_INF = 0xff0000;

/** Exact value of a float24 as a rational, or a class for the specials. */
export type Decoded =
  | { kind: "nan" }
  | { kind: "inf"; negative: boolean }
  | { kind: "finite"; negative: boolean; num: bigint; den: bigint };

export function decode(bits: number): Decoded {
  const negative = (bits & SIGN) !== 0;
  const exponent = (bits >>> EXP_SHIFT) & EXP_MASK;
  const fraction = bits & FRAC_MASK;
  if (exponent === EXP_MASK) {
    return fraction === 0 ? { kind: "inf", negative } : { kind: "nan" };
  }
  if (exponent === 0) {
    // Subnormal or zero: fraction * 2^-78.
    return { kind: "finite", negative, num: BigInt(fraction), den: 1n << 78n };
  }
  // (2^16 + fraction) * 2^(exponent - 63 - 16).
  const scale = exponent - BIAS - 16;
  const mantissa = BigInt(0x10000 + fraction);
  return scale >= 0
    ? { kind: "finite", negative, num: mantissa << BigInt(scale), den: 1n }
    : { kind: "finite", negative, num: mantissa, den: 1n << BigInt(-scale) };
}

function bitLength(value: bigint): number {
  return value === 0n ? 0 : value.toString(2).length;
}

/**
 * Round the exact nonnegative rational num/den to float24 with the given
 * sign, to nearest even, with gradual underflow and overflow to infinity.
 */
export function roundToFloat24(
  negative: boolean,
  num: bigint,
  den: bigint,
): number {
  const sign = negative ? SIGN : 0;
  if (num === 0n) return sign;
  // Find e with 2^e <= num/den < 2^(e+1).
  let e = bitLength(num) - bitLength(den);
  if (
    num * (1n << BigInt(Math.max(0, -e))) < den * (1n << BigInt(Math.max(0, e)))
  ) {
    e -= 1;
  }
  // The significand has 16 fraction bits for a normal; subnormals have a
  // fixed scale of 2^-78.
  let shift = e - 16; // value = significand * 2^shift
  const minNormal = 1 - BIAS; // e = -62
  if (e < minNormal) shift = -78;
  // significand = round(num/den / 2^shift)
  const scaledNum = shift >= 0 ? num : num << BigInt(-shift);
  const scaledDen = shift >= 0 ? den << BigInt(shift) : den;
  let significand = scaledNum / scaledDen;
  const remainder = scaledNum - significand * scaledDen;
  const twice = remainder * 2n;
  if (twice > scaledDen || (twice === scaledDen && (significand & 1n) === 1n)) {
    significand += 1n;
  }
  // Rounding may carry into the next binade.
  if (shift !== -78 && significand === 1n << 17n) {
    significand = 1n << 16n;
    shift += 1;
  }
  if (shift === -78) {
    if (significand >= 1n << 16n) {
      // The subnormal rounded up into the smallest normal.
      return sign | (1 << EXP_SHIFT) | Number(significand - (1n << 16n));
    }
    return sign | Number(significand);
  }
  const exponent = shift + 16 + BIAS;
  if (exponent >= EXP_MASK) return sign | POS_INF;
  return sign | (exponent << EXP_SHIFT) | Number(significand - (1n << 16n));
}

export function fromRational(negative: boolean, num: bigint, den: bigint) {
  if (num < 0n) {
    negative = !negative;
    num = -num;
  }
  return roundToFloat24(negative, num, den);
}

type Finite = { kind: "finite"; negative: boolean; num: bigint; den: bigint };

function signed(x: Finite): bigint {
  return x.negative ? -x.num : x.num;
}

export function add(a: number, b: number): number {
  const x = decode(a), y = decode(b);
  if (x.kind === "nan" || y.kind === "nan") return NAN;
  if (x.kind === "inf") {
    if (y.kind === "inf" && y.negative !== x.negative) return NAN;
    return a;
  }
  if (y.kind === "inf") return b;
  if (x.num === 0n && y.num === 0n) {
    return (x.negative && y.negative) ? SIGN : 0;
  }
  const num = signed(x) * y.den + signed(y) * x.den;
  const den = x.den * y.den;
  if (num === 0n) return 0; // Exact cancellation is +0.
  return fromRational(false, num, den);
}

export function sub(a: number, b: number): number {
  return add(a, b ^ SIGN);
}

export function mul(a: number, b: number): number {
  const x = decode(a), y = decode(b);
  if (x.kind === "nan" || y.kind === "nan") return NAN;
  const negative = ((a ^ b) & SIGN) !== 0;
  const sign = negative ? SIGN : 0;
  if (x.kind === "inf" || y.kind === "inf") {
    if (
      (x.kind === "finite" && x.num === 0n) ||
      (y.kind === "finite" && y.num === 0n)
    ) {
      return NAN;
    }
    return sign | POS_INF;
  }
  return roundToFloat24(negative, x.num * y.num, x.den * y.den);
}

export function div(a: number, b: number): number {
  const x = decode(a), y = decode(b);
  if (x.kind === "nan" || y.kind === "nan") return NAN;
  const negative = ((a ^ b) & SIGN) !== 0;
  const sign = negative ? SIGN : 0;
  if (x.kind === "inf") return y.kind === "inf" ? NAN : sign | POS_INF;
  if (y.kind === "inf") return sign;
  if (y.num === 0n) return x.num === 0n ? NAN : sign | POS_INF;
  return roundToFloat24(negative, x.num * y.den, x.den * y.num);
}

/** Raw comparison code: -1, 0, 1, or 2 for unordered. */
export function compare(a: number, b: number): number {
  const x = decode(a), y = decode(b);
  if (x.kind === "nan" || y.kind === "nan") return 2;
  const rank = (v: Decoded) => v.kind === "inf" ? (v.negative ? -2n : 2n) : 0n;
  if (x.kind === "inf" || y.kind === "inf") {
    const rx = rank(x), ry = rank(y);
    if (x.kind === "inf" && y.kind === "inf") {
      return rx === ry ? 0 : rx < ry ? -1 : 1;
    }
    return x.kind === "inf" ? Number(rx / 2n) : -Number(ry / 2n);
  }
  const left = signed(x as Finite) * y.den;
  const right = signed(y as Finite) * x.den;
  return left === right ? 0 : left < right ? -1 : 1;
}

export function negate(a: number): number {
  return decode(a).kind === "nan" ? NAN : a ^ SIGN;
}

/** Signed 24-bit integer to float24, rounding to nearest even. */
export function fromInteger(value: number): number {
  return fromRational(value < 0, BigInt(Math.abs(value)), 1n);
}

/** Float24 to signed 24-bit integer, truncating toward zero; null if it fails. */
export function toInteger(bits: number): number | null {
  const x = decode(bits);
  if (x.kind !== "finite") return null;
  const magnitude = x.num / x.den;
  const limit = x.negative ? 1n << 23n : (1n << 23n) - 1n;
  if (magnitude > limit) return null;
  return Number(x.negative ? -magnitude : magnitude);
}

/** Exact decimal spelling: the printer's output for a float24. */
export function print(bits: number): string {
  const x = decode(bits);
  if (x.kind === "nan") return "+nan.0";
  if (x.kind === "inf") return x.negative ? "-inf.0" : "+inf.0";
  const sign = x.negative ? "-" : "";
  // den is a power of two: 2^k.  num/2^k = num*5^k / 10^k.
  const k = bitLength(x.den) - 1;
  let digits = (x.num * 5n ** BigInt(k)).toString();
  if (k === 0) return `${sign}${digits}.0`;
  digits = digits.padStart(k + 1, "0");
  const point = digits.length - k;
  const fraction = digits.slice(point).replace(/0+$/, "");
  if (fraction === "") return `${sign}${digits.slice(0, point)}.0`;
  return `${sign}${digits.slice(0, point)}.${fraction}`;
}

/**
 * Parse a decimal literal (optional sign, digits, optional point, optional
 * exponent) exactly and round once.  Returns null for malformed text.
 */
export function parse(text: string): number | null {
  const special = /^([+-])(inf\.0|nan\.0)$/.exec(text);
  if (special) {
    if (special[2] === "nan.0") return special[1] === "+" ? NAN : null;
    return special[1] === "-" ? NEG_INF : POS_INF;
  }
  const m = /^([+-]?)(\d*)(?:\.(\d*))?(?:e([+-]?\d+))?$/i.exec(text);
  if (!m || (m[2] === "" && (m[3] ?? "") === "")) return null;
  const negative = m[1] === "-";
  const intPart = m[2], fracPart = m[3] ?? "";
  const exponent = m[4] === undefined ? 0 : Number(m[4]);
  let num = BigInt(intPart + fracPart || "0");
  let den = 1n;
  const scale = exponent - fracPart.length;
  if (scale >= 0) num *= 10n ** BigInt(scale);
  else den = 10n ** BigInt(-scale);
  return roundToFloat24(negative, num, den);
}

export function hex(bits: number): string {
  return bits.toString(16).padStart(6, "0").toUpperCase() + "H";
}
