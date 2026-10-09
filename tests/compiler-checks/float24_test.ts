import assert from "node:assert/strict";
import { loadAssembly } from "../z80.ts";
import * as F from "../../tools/compiler-checks/float24-reference.ts";

// The runtime's float24 routines must agree bit for bit with the host
// reference in tools/compiler-checks/float24-reference.ts.

const EDGES = [
  0x000000, // +0
  0x800000, // -0
  0x000001, // smallest subnormal
  0x00ffff, // largest subnormal
  0x010000, // smallest normal
  0x3f0000, // 1.0
  0xbf0000, // -1.0
  0x3f0001, // 1 + ulp
  0x3effff, // 1 - ulp/2
  0x3f8000, // 1.5
  0x500000, // 131072
  0x7effff, // largest finite
  0xfeffff, // most negative finite
  0x7f0000, // +inf
  0xff0000, // -inf
  0x7f8000, // NaN
];

// A small deterministic generator, weighted toward ordinary magnitudes.
function* operands(count: number, seed: number) {
  let x = seed;
  const next = () => {
    x ^= x << 13;
    x ^= x >>> 17;
    x ^= x << 5;
    return x >>> 0;
  };
  for (let i = 0; i < count; i++) {
    const r = next();
    const kind = r & 7;
    let bits = next() & 0xffffff;
    if (kind < 5) {
      // Exponent near 1.0 so sums and products stay finite and interesting.
      const exponent = 50 + (next() % 27);
      bits = (bits & 0x80ffff) | (exponent << 16);
    } else if (kind === 5) {
      bits &= 0x80ffff; // subnormal or zero
    }
    if ((bits & 0x7f0000) === 0x7f0000 && (bits & 0xffff) !== 0) {
      bits = F.NAN;
    }
    yield bits;
  }
}

function cases(count: number, seed: number): [number, number][] {
  const list: [number, number][] = [];
  for (const a of EDGES) for (const b of EDGES) list.push([a, b]);
  const left = [...operands(count, seed)];
  const right = [...operands(count, seed * 7 + 1)];
  for (let i = 0; i < count; i++) list.push([left[i], right[i]]);
  // Pairs with nearby exponents exercise cancellation and ties.
  for (let i = 0; i < count; i++) {
    list.push([left[i], (left[i] & 0xff0000) | (right[i] & 0xffff)]);
  }
  return list;
}

async function runtime() {
  const assembled = await loadAssembly("src/runtime/image.asm");
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu as {
    a: number;
    b: number;
    c: number;
    d: number;
    e: number;
    h: number;
    l: number;
    pc: number;
    sp: number;
    flags: { C: number };
  };
  const x = assembled.address("NUM_X");
  const y = assembled.address("NUM_Y");
  function cell(at: number, bits: number) {
    memory[at] = bits & 255;
    memory[at + 1] = (bits >>> 8) & 255;
    memory[at + 2] = bits >>> 16;
    memory[at + 3] = 9;
  }
  function call(label: string) {
    cpu.pc = assembled.address(label);
    cpu.sp = 0xb3f0;
    memory[0xb3f0] = 0x00;
    memory[0xb3f1] = 0xef;
    let steps = 0;
    while (cpu.pc !== 0xef00) {
      assert.ok(++steps < 200_000, `${label} did not return`);
      assembled.runtime.step();
    }
    assert.equal(cpu.sp, 0xb3f2, `${label} stack`);
    return {
      bits: (cpu.c << 16) | (cpu.h << 8) | cpu.l,
      a: cpu.a,
      carry: cpu.flags.C,
    };
  }
  return {
    binary(label: string, a: number, b: number) {
      cell(x, a);
      cell(y, b);
      return call(label);
    },
    unary(label: string, a: number, tag = 9) {
      cpu.a = tag;
      cpu.c = a >>> 16;
      cpu.h = (a >>> 8) & 255;
      cpu.l = a & 255;
      return call(label);
    },
  };
}

const ARITH: [string, (a: number, b: number) => number][] = [
  ["F24_ADD", F.add],
  ["F24_SUB", F.sub],
  ["F24_MUL", F.mul],
  ["F24_DIV", F.div],
];

for (const [label, reference] of ARITH) {
  Deno.test(`${label} rounds exactly as the reference`, async () => {
    const rt = await runtime();
    let failures = 0;
    for (const [a, b] of cases(1500, label.length * 977 + 3)) {
      const got = rt.binary(label, a, b);
      const want = reference(a, b);
      if (got.bits !== want || got.a !== 9 || got.carry !== 0) {
        if (failures++ < 8) {
          console.log(
            `${label} ${F.hex(a)} ${F.hex(b)}: got ${F.hex(got.bits)} want ${
              F.hex(want)
            }`,
          );
        }
      }
    }
    assert.equal(failures, 0);
  });
}

Deno.test("F24_CMP orders floats as the reference", async () => {
  const rt = await runtime();
  let failures = 0;
  for (const [a, b] of cases(1500, 4242)) {
    const got = rt.binary("F24_CMP", a, b).bits & 0xffff;
    const code = F.compare(a, b);
    const want = code === -1 ? 0xffff : code;
    if (got !== want && failures++ < 8) {
      console.log(`CMP ${F.hex(a)} ${F.hex(b)}: got ${got} want ${code}`);
    }
  }
  assert.equal(failures, 0);
});

Deno.test("integer and float conversions match the reference", async () => {
  const rt = await runtime();
  const ints = [
    0,
    1,
    -1,
    131071,
    131072,
    131073,
    131075,
    -131073,
    8388607,
    -8388608,
    65535,
    1234567,
    -7654321,
  ];
  for (let i = 0; i < 400; i++) ints.push(((i * 2654435761) >>> 8) - 8388608);
  for (const n of ints) {
    const got = rt.unary("F24_ITOF", n & 0xffffff);
    assert.equal(got.bits, F.fromInteger(n), `ITOF ${n}`);
  }
  for (const [a] of cases(1500, 99)) {
    const got = rt.unary("F24_FTOI", a);
    const want = F.toInteger(a);
    if (want === null) {
      assert.equal(got.carry, 1, `FTOI ${F.hex(a)} should fail`);
    } else {
      assert.equal(got.carry, 0, `FTOI ${F.hex(a)}`);
      const value = got.bits & 0x800000 ? got.bits - 0x1000000 : got.bits;
      assert.equal(value, want, `FTOI ${F.hex(a)}`);
    }
  }
});

Deno.test("float validation and negation", async () => {
  const rt = await runtime();
  assert.equal(rt.unary("F24_CHK", 0x7f8000).carry, 0);
  assert.equal(rt.unary("F24_CHK", 0x7f0001).carry, 1);
  assert.equal(rt.unary("F24_CHK", 0xff8000).carry, 1);
  assert.equal(rt.unary("F24_CHK", 0x3f0000, 3).carry, 1);
  assert.equal(rt.unary("F24_NEG", 0x3f0000).bits, 0xbf0000);
  assert.equal(rt.unary("F24_NEG", 0x000000).bits, 0x800000);
  assert.equal(rt.unary("F24_NEG", 0x7f8000).bits, 0x7f8000);
});
