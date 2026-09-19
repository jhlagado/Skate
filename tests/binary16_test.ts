import assert from "node:assert/strict";
import { assemble } from "./z80.ts";
import * as ref from "../tools/binary16-reference.ts";
import { classify } from "../tools/representation.ts";
const machine = await assemble("tests/numeric.asm");
const call = (name: string, a: number, b = 0, tag = 0, rightTag = 0) =>
  machine.call(name, a, b, tag, rightTag);
function pick(r: { bits: number; status: number; carry: number }) {
  return { bits: r.bits, status: r.status, carry: r.carry };
}
const hex = (n: number) => n.toString(16).padStart(4, "0");
function check(
  name: string,
  a: number,
  b: number,
  expected: number,
  status = 0,
) {
  const got = call(name, a, b);
  assert.equal(got.bits, expected, `${name} ${hex(a)} ${hex(b)} bits`);
  assert.equal(got.status, status, `${name} status`);
  assert.equal(got.carry, status ? 1 : 0, `${name} carry`);
}
Deno.test("all scalar encodings: classification, negate, raw ingress and word conversions", () => {
  for (let bits = 0; bits < 65536; bits++) {
    const numeric = classify(bits) === "number";
    check("F16CLASS", bits, 0, bits, numeric ? 0 : 1);
    check(
      "F16NEG",
      bits,
      0,
      numeric ? (bits === 0x7e00 ? bits : bits ^ 0x8000) : bits,
      numeric ? 0 : 1,
    );
    check("F16BITS", bits, 0, ref.canonicalize(bits));
    for (
      const [name, convert] of [["F16TOI", ref.toInt16], [
        "F16TOU",
        ref.toUint16,
      ]] as const
    ) {
      const n = convert(bits);
      const status = !numeric ? 1 : n === null ? 2 : 0;
      check(name, bits, 0, status ? bits : n! & 65535, status);
    }
  }
});
Deno.test("every signed and unsigned word converts to binary16", () => {
  for (let word = 0; word < 65536; word++) {
    check("F16FRU", word, 0, ref.fromUint16(word));
    check(
      "F16FRI",
      word,
      0,
      ref.fromInt16(word < 32768 ? word : word - 65536),
    );
  }
});
const operations = [
  ["F16ADD", ref.add],
  ["F16SUB", ref.sub],
  ["F16MUL", ref.mul],
  ["F16DIV", ref.div],
  ["F16CMP", (a: number, b: number) => {
    const c = ref.compare(a, b);
    return c === null ? 2 : c & 65535;
  }],
] as const;
Deno.test("arithmetic and comparisons: boundary cross product and deterministic pairs", () => {
  const boundaries = [
    0,
    1,
    2,
    3,
    0x1ff,
    0x200,
    0x3fe,
    0x3ff,
    0x400,
    0x401,
    0x7ff,
    0x800,
    0x3555,
    0x3800,
    0x3bff,
    0x3c00,
    0x3c01,
    0x3fff,
    0x4000,
    0x6400,
    0x6800,
    0x7800,
    0x7bfe,
    0x7bff,
    0x7c00,
  ];
  const values = [...boundaries, ...boundaries.map((x) => x | 0x8000), 0x7e00];
  for (const a of values) {
    for (const b of values) {
      for (const [op, f] of operations) check(op, a, b, f(a, b));
    }
  }
  let seed = 0x5ca7e;
  function next() {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed >>> 16;
  }
  for (let i = 0; i < 20000; i++) {
    const a = ref.canonicalize(next()), b = ref.canonicalize(next());
    for (const [op, f] of operations) check(op, a, b, f(a, b));
  }
});
Deno.test("every nonnumeric scalar rejected in both binary operand positions", () => {
  for (let bits = 0; bits < 65536; bits++) {
    if (classify(bits) !== "number") {
      for (const [op] of operations) {
        check(op, bits, 0x3c00, bits, 1);
        check(op, 0x3c00, bits, 0x3c00, 1);
      }
    }
  }
  for (let tag = 1; tag < 256; tag++) {
    for (const [op] of operations) {
      assert.deepEqual(pick(call(op, 0x3c00, 0x4000, tag)), {
        bits: 0x3c00,
        status: 1,
        carry: 1,
      });
      assert.deepEqual(pick(call(op, 0x3c00, 0x4000, 0, tag)), {
        bits: 0x3c00,
        status: 1,
        carry: 1,
      });
    }
    for (const op of ["F16CLASS", "F16NEG", "F16TOI", "F16TOU"]) {
      assert.deepEqual(pick(call(op, 0x3c00, 0, tag)), {
        bits: 0x3c00,
        status: 1,
        carry: 1,
      });
    }
  }
});

Deno.test("measured module extent and call costs", () => {
  const code = machine.address("F16END") - machine.address("F16CLASS");
  const workspace = machine.address("F16WEND") - machine.address("F16WORK");
  assert.equal(workspace, 27);
  console.log(
    JSON.stringify(
      { code, workspace, operations: Object.fromEntries(machine.stats) },
      null,
      2,
    ),
  );
  for (const stat of machine.stats.values()) assert.ok(stat.stackBytes <= 4);
});
