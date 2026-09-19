import assert from "node:assert/strict";
import { decimalMachine } from "./decimal-machine.ts";
import { formatNumber, parseNumericToken } from "../tools/numeric.ts";

Deno.test("native decimal exact values, syntax, and capacity", async () => {
  const m = await decimalMachine();
  for (
    const token of [
      "0",
      "-0",
      "+1",
      "32767",
      "-32768",
      "2049",
      "30000",
      "0.0",
      "-0.0",
      ".5",
      "1.",
      "1e0",
      "1E+2",
      "1e-2",
      "+inf.0",
      "-inf.0",
      "+nan.0",
      "65504.0",
      "65519.0",
      "65520.0",
      "65521.0",
      "1e99999999999999999",
      "-1e-99999999999",
      "0e99999999999999999999",
      "1.00048828125",
      "1.00146484375",
      "0.0000000298023223876953125",
      "0.00000002980232238769531250001",
      "0.00000002980232238769531249999",
      "0.0000610053539276123046875",
      "12345678901234567890123456789012345678901234567890123456789e-56",
      "000000000000000000000000000000000000000000000000000000000001e-2",
      "999999999999999999999999999999999999999999999999999999999999e-64",
    ]
  ) {
    const expected = parseNumericToken(token)!;
    const actual = m.parse(token);
    assert.equal(actual.carry, 0, token);
    assert.deepEqual([actual.tag, actual.bits], expected, token);
  }
  for (
    const token of [
      "",
      "+",
      "-",
      ".",
      "1..0",
      "1e",
      "1e+",
      "1e-",
      "1e2e3",
      "--1",
      "-nan.0",
      "nan.0",
      "inf.0",
      "1x",
      "1e999999999999999999x",
      "1e-99999999999999x",
      "1.2.3",
      "1 2",
      ".e1",
      "e1",
      "1\0",
      "1e+-2",
    ]
  ) {
    const actual = m.parse(token);
    assert.equal(actual.carry, 1, token);
    assert.equal(actual.tag, 128, token);
  }
  for (
    const token of [
      "32768",
      "-32769",
      "65536",
      "9999999999999999999999999999999999999999999999999999999999999999",
    ]
  ) {
    assert.equal(m.parse(token).tag, 130, token);
  }
  assert.deepEqual(
    [m.parse("0".repeat(64)).tag, m.parse("0".repeat(64)).bits],
    [3, 0],
  );
  assert.equal(m.parse("0".repeat(65)).tag, 129);
  assert.equal(m.parse("", 0x8000, 256).tag, 129);
  assert.equal(m.parse("12", 0xffff).tag, 129);
  assert.equal(m.parse("1", 0xffff).bits, 1);
  console.log("decimal census", m.census());
});

Deno.test("native decimal printed binary16 values and decimal boundary probes", async () => {
  const m = await decimalMachine();
  // Every exponent region, both signs, and every mantissa at three transitions.
  const bits = new Set<number>();
  for (let exponent = 0; exponent <= 30; exponent++) {
    for (const mantissa of [0, 1, 2, 511, 512, 1022, 1023]) {
      bits.add(exponent * 1024 + mantissa);
    }
  }
  for (const base of [0, 1024, 30 * 1024]) {
    for (let mantissa = 0; mantissa < 1024; mantissa++) {
      bits.add(base + mantissa);
    }
  }
  for (const raw of bits) {
    for (const sign of [0, 0x8000]) {
      const value = raw | sign;
      const token = formatNumber([0, value]);
      const actual = m.parse(token);
      assert.equal(actual.carry, 0, token);
      assert.deepEqual([actual.tag, actual.bits], [0, value], token);
    }
  }
  console.log("decimal sampled roundtrips", bits.size * 2, m.census());
});

Deno.test("native decimal exact midpoint neighbors and long significands", async () => {
  const m = await decimalMachine();
  const check = (token: string) => {
    const expected = parseNumericToken(token)!;
    const actual = m.parse(token);
    assert.equal(actual.carry, 0, token);
    assert.deepEqual([actual.tag, actual.bits], expected, token);
  };
  for (let exponent = 0; exponent <= 30; exponent++) {
    for (const mantissa of [0, 1, 511, 1023]) {
      const significand = exponent === 0 ? mantissa : 1024 + mantissa;
      const units = BigInt(2 * significand + 1) <<
        BigInt(Math.max(exponent - 1, 0));
      const scaled = units * 5n ** 25n * 100000n;
      for (const side of [-1n, 0n, 1n]) {
        const digits = (scaled + side).toString().padStart(31, "0");
        const token = digits.slice(0, -30) + "." + digits.slice(-30);
        check(token);
        check("-" + token);
      }
    }
  }
  let state = 0x5c8dec;
  const next = () => state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
  for (let i = 0; i < 256; i++) {
    const length = 1 + next() % 55;
    let digits = String(1 + next() % 9);
    for (let j = 1; j < length; j++) digits += String(next() % 10);
    const point = next() % (length + 1);
    const mantissa = digits.slice(0, point) + "." + digits.slice(point);
    check(
      (next() & 1 ? "-" : "") + mantissa + "e" + (Number(next() % 80) - 70),
    );
  }
});
