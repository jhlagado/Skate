/** C0 development model only. No Z80 compiler/runtime implementation. */
export type Value = readonly [tag: number, payload: number];
export type IntegerOperation = "add" | "sub" | "mul" | "quotient" | "remainder";

export function integer(value: number): Value {
  if (!Number.isInteger(value) || value < -32768 || value > 32767) {
    throw new RangeError("overflow");
  }
  return [3, value & 65535];
}

export function signed(value: Value): number {
  if (
    value[0] !== 3 || !Number.isInteger(value[1]) || value[1] < 0 ||
    value[1] > 65535
  ) {
    throw new TypeError("type");
  }
  return value[1] < 32768 ? value[1] : value[1] - 65536;
}

export function calculate(
  operation: IntegerOperation,
  a: Value,
  b: Value,
): Value {
  const left = signed(a), right = signed(b);
  if ((operation === "quotient" || operation === "remainder") && right === 0) {
    throw new RangeError("division-by-zero");
  }
  switch (operation) {
    case "add":
      return integer(left + right);
    case "sub":
      return integer(left - right);
    case "mul":
      return integer(left * right);
    case "quotient":
      return integer(Math.trunc(left / right));
    case "remainder":
      return integer(left % right);
  }
}

export function valueKind([tag, payload]: Value, floats: boolean): string {
  if (!Number.isInteger(payload) || payload < 0 || payload > 65535) {
    return "invalid";
  }
  if (tag === 3) return "integer";
  if (tag === 1) {
    const subtype = payload >>> 13, index = payload & 8191;
    if (subtype > 4 || ([0, 2, 3].includes(subtype) && index === 0)) {
      return "invalid";
    }
    return ["pair", "symbol", "closure", "environment", "string"][subtype];
  }
  if (tag !== 0) return "invalid";
  if (payload >= 0xfe00 && payload <= 0xfe05) return "immediate";
  if (payload >= 0xfe20 && payload <= 0xfe3c) return "prototype-primitive";
  if (payload >= 0xff00) return "character";
  const nan = (payload & 0x7c00) === 0x7c00 && (payload & 1023) !== 0;
  if (!nan || payload === 0x7e00) return floats ? "float" : "unsupported-float";
  return "invalid";
}

export function slot(value: Value): Uint8Array {
  return new Uint8Array([value[0], value[1] & 255, value[1] >>> 8, 0]);
}
