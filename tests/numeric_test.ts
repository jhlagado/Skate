import assert from "node:assert/strict";
import { numericMachine } from "./numeric-machine.ts";
import * as ref from "../tools/numeric.ts";
import { classify, type Value } from "../tools/representation.ts";
const m = await numericMachine();
const ops = ["add", "sub", "mul", "div"] as const;
function expected(name: string, a: Value, b: Value = [0, 0]): Value {
  if (name === "NCLASS") {
    if (!ref.isNumber(a)) throw new TypeError();
    return a;
  }
  if (name === "NNEG") return ref.negate(a);
  if (name === "NCMP") {
    const c = ref.compare(a, b);
    return [0, c === null ? 2 : c & 65535];
  }
  return ref.binary(name.slice(1).toLowerCase() as typeof ops[number], a, b);
}
function check(name: string, a: Value, b: Value = [0, 0]) {
  let want: Value, carry = 0;
  try {
    want = expected(name, a, b);
  } catch (e) {
    if (!(e instanceof TypeError || e instanceof RangeError)) throw e;
    want = [e instanceof TypeError ? 1 : 2, a[1]];
    carry = 1;
  }
  const got = m.call(name, a, b);
  assert.equal(got.carry, carry, `${name} ${a} ${b} carry`);
  assert.deepEqual(got.value, want, `${name} ${a} ${b}`);
  return got;
}
Deno.test("every integer payload: classify, negate and boundary arithmetic", () => {
  for (let bits = 0; bits < 65536; bits++) {
    const a: Value = [3, bits];
    check("NCLASS", a);
    check("NNEG", a);
    for (const b of [[3, 1], [3, 65535]] as Value[]) {
      check("NADD", a, b);
      check("NSUB", a, b);
      check("NMUL", a, b);
      check("NCMP", a, b);
    }
  }
});
Deno.test("every binary16 scalar: classify, negate, exact mixed comparisons in both orders", () => {
  for (let bits = 0; bits < 65536; bits++) {
    const f: Value = [0, bits];
    check("NCLASS", f);
    check("NNEG", f);
    for (const n of [-32768, -2049, -1, 0, 1, 2049, 32767]) {
      const i = ref.integer(n);
      check("NCMP", i, f);
      check("NCMP", f, i);
    }
  }
});
Deno.test("numeric boundary cross product and deterministic integer/mixed operations", () => {
  const values: Value[] = [
    ...[
      -32768,
      -32767,
      -2049,
      -2048,
      -257,
      -256,
      -1,
      0,
      1,
      2,
      255,
      256,
      2048,
      2049,
      32766,
      32767,
    ].map(ref.integer),
    ...[
      0,
      1,
      0x3ff,
      0x400,
      0x3555,
      0x3bff,
      0x3c00,
      0x3c01,
      0x6800,
      0x7800,
      0x7bff,
      0x7c00,
      0x7e00,
      0x8000,
      0xbc00,
      0xf800,
      0xfc00,
    ].map((bits) => [0, bits] as Value),
  ];
  for (const a of values) {
    for (const b of values) {
      for (const op of ops) check("N" + op.toUpperCase(), a, b);
      check("NCMP", a, b);
    }
  }
  let seed = 0x1e67;
  function next() {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed >>> 16;
  }
  for (let j = 0; j < 10000; j++) {
    const a: Value = [j % 3 === 0 ? 0 : 3, next()],
      b: Value = [j % 3 === 1 ? 0 : 3, next()];
    for (const op of ops) check("N" + op.toUpperCase(), a, b);
    check("NCMP", a, b);
  }
});
Deno.test("all nonnumeric scalar values and outer tags rejected before coercion", () => {
  for (let bits = 0; bits < 65536; bits++) {
    if (classify(bits) !== "number") {
      for (const op of [...ops.map((op) => "N" + op.toUpperCase()), "NCMP"]) {
        check(op, [0, bits], [3, 1]);
        check(op, [3, 1], [0, bits]);
      }
    }
  }
  for (let tag = 1; tag < 256; tag++) {
    if (tag !== 3) {
      for (const op of [...ops.map((op) => "N" + op.toUpperCase()), "NCMP"]) {
        check(op, [tag, 0x3c00], [3, 1]);
        check(op, [3, 1], [tag, 0x3c00]);
      }
      check("NCLASS", [tag, 0]);
      check("NNEG", [tag, 0]);
    }
  }
});
Deno.test("executed exact counter advances through 30000 and overflows explicitly", () => {
  let counter: Value = [3, 0];
  for (let i = 0; i < 30000; i++) {
    const result = m.call("NADD", counter, [3, 1]);
    assert.equal(result.carry, 0);
    counter = result.value;
  }
  assert.deepEqual(counter, [3, 30000]);
  assert.deepEqual(check("NADD", [3, 32767], [3, 1]).value, [2, 32767]);
  assert.deepEqual(check("NCMP", [3, 2049], [0, 0x6800]).value, [0, 1]);
});
Deno.test("generic numeric runtime byte and cycle census", () => {
  console.log(JSON.stringify(
    {
      code: m.address("NEND") - m.address("NCLASS"),
      workspace: m.address("NWEND") - m.address("NWORK"),
      withBinary16: m.address("NWEND") - m.address("F16CLASS"),
      operations: Object.fromEntries(m.stats),
    },
    null,
    2,
  ));
});
