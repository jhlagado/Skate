/** Independent raw-IEEE binary16 oracle: exact BigInt rationals and ordered-code
 * search, deliberately unlike a target mantissa/exponent arithmetic algorithm.
 * This is not a language-value validator: every raw NaN is accepted here.
 */
export const CANONICAL_NAN = 0x7e00;
const SCALE = 1n << 24n;

function checked(bits: number): number {
  if (!Number.isInteger(bits) || bits < 0 || bits > 0xffff) {
    throw new RangeError("Expected raw unsigned 16-bit bits");
  }
  return bits;
}

export function isNaN(bits: number): boolean {
  return (checked(bits) & 0x7fff) > 0x7c00;
}

export function canonicalize(bits: number): number {
  return isNaN(bits) ? CANONICAL_NAN : bits;
}

/** Magnitude expressed in exact units of the smallest subnormal (2^-24). */
function units(bits: number): bigint {
  const exponent = (bits >>> 10) & 31;
  const fraction = BigInt(bits & 1023);
  return exponent === 0 ? fraction : (1024n + fraction) << BigInt(exponent - 1);
}

function signedUnits(bits: number): bigint {
  const magnitude = units(bits);
  return bits & 0x8000 ? -magnitude : magnitude;
}

/** Round an exact rational once, nearest with ties to even. */
export function fromRational(
  numerator: bigint,
  denominator = 1n,
  negativeZero = false,
): number {
  if (denominator <= 0n) throw new RangeError("Denominator must be positive");
  if (numerator === 0n) return negativeZero ? 0x8000 : 0;
  const sign = numerator < 0n ? 0x8000 : 0;
  const scaled = (numerator < 0n ? -numerator : numerator) * SCALE;
  // 65520 is the halfway boundary between 65504 and the next exponent.
  if (scaled >= 65520n * SCALE * denominator) return sign | 0x7c00;
  let low = 0;
  let high = 0x7bff;
  while (low < high) {
    const middle = (low + high + 1) >>> 1;
    if (units(middle) * denominator <= scaled) low = middle;
    else high = middle - 1;
  }
  if (low === 0x7bff) return sign | low;
  const midpoint = (units(low) + units(low + 1)) * denominator;
  const twice = scaled * 2n;
  const roundUp = twice > midpoint || (twice === midpoint && (low & 1) !== 0);
  return sign | (low + (roundUp ? 1 : 0));
}

export function add(a: number, b: number): number {
  checked(a);
  checked(b);
  if (isNaN(a) || isNaN(b)) return CANONICAL_NAN;
  const aa = a & 0x7fff;
  const bb = b & 0x7fff;
  if (aa === 0x7c00 || bb === 0x7c00) {
    if (aa === bb && ((a ^ b) & 0x8000)) return CANONICAL_NAN;
    return aa === 0x7c00 ? a : b;
  }
  return fromRational(
    signedUnits(a) + signedUnits(b),
    SCALE,
    a === 0x8000 && b === 0x8000,
  );
}

export function sub(a: number, b: number): number {
  checked(b);
  return add(a, b ^ 0x8000);
}

export function mul(a: number, b: number): number {
  checked(a);
  checked(b);
  if (isNaN(a) || isNaN(b)) return CANONICAL_NAN;
  const aa = a & 0x7fff;
  const bb = b & 0x7fff;
  const sign = (a ^ b) & 0x8000;
  if (aa === 0x7c00 || bb === 0x7c00) {
    return aa === 0 || bb === 0 ? CANONICAL_NAN : sign | 0x7c00;
  }
  return fromRational(
    signedUnits(a) * signedUnits(b),
    SCALE * SCALE,
    sign !== 0,
  );
}

export function div(a: number, b: number): number {
  checked(a);
  checked(b);
  if (isNaN(a) || isNaN(b)) return CANONICAL_NAN;
  const aa = a & 0x7fff;
  const bb = b & 0x7fff;
  const sign = (a ^ b) & 0x8000;
  if ((aa === 0 && bb === 0) || (aa === 0x7c00 && bb === 0x7c00)) {
    return CANONICAL_NAN;
  }
  if (aa === 0x7c00 || bb === 0) return sign | 0x7c00;
  if (bb === 0x7c00 || aa === 0) return sign;
  return fromRational(sign ? -units(a) : units(a), units(b));
}

export function compare(a: number, b: number): -1 | 0 | 1 | null {
  checked(a);
  checked(b);
  if (isNaN(a) || isNaN(b)) return null;
  // Ordered IEEE encodings suffice, with the two zero encodings identified.
  const key = (bits: number) => bits & 0x8000 ? -(bits & 0x7fff) : bits;
  const x = key(a);
  const y = key(b);
  return x < y ? -1 : x > y ? 1 : 0;
}

function fromInteger(value: number, min: number, max: number): number {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new RangeError(`Expected integer in ${min}..${max}`);
  }
  return fromRational(BigInt(value));
}

export function fromInt16(value: number): number {
  return fromInteger(value, -32768, 32767);
}
export function fromUint16(value: number): number {
  return fromInteger(value, 0, 65535);
}

function toInteger(bits: number, min: number, max: number): number | null {
  checked(bits);
  if ((bits & 0x7fff) >= 0x7c00) return null;
  const truncated = Number(signedUnits(bits) / SCALE);
  return truncated < min || truncated > max ? null : truncated;
}

/** Truncate toward zero; null means NaN, infinity or out of range. */
export function toInt16(bits: number): number | null {
  return toInteger(bits, -32768, 32767);
}
export function toUint16(bits: number): number | null {
  return toInteger(bits, 0, 65535);
}

/** Exact widening to a host number, for independent host cross-checks. */
export function toNumber(bits: number): number {
  checked(bits);
  if (isNaN(bits)) return NaN;
  if ((bits & 0x7fff) === 0x7c00) return bits & 0x8000 ? -Infinity : Infinity;
  const magnitude = Number(units(bits)) / Number(SCALE);
  return bits & 0x8000 ? -magnitude : magnitude;
}
