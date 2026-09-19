import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";

const m = await loadAssembly("tests/native-control-machine.asm");
const { runtime, address } = m;
const memory = runtime.hardware.memory;
const cpu = runtime.cpu;
const put = (p: number, value: number) => {
  memory[p] = value & 255;
  memory[p + 1] = value >>> 8;
};
function call(name: string, hl = 0, bc = 0, de = 0, ix = 0x1357) {
  cpu.pc = address(name);
  cpu.sp = 0xf000;
  cpu.ix = ix;
  cpu.iy = 0x2468;
  cpu.h = hl >>> 8;
  cpu.l = hl & 255;
  cpu.b = bc >>> 8;
  cpu.c = bc & 255;
  cpu.d = de >>> 8;
  cpu.e = de & 255;
  cpu.flags.C = 1;
  put(0xf000, 0xff00);
  let steps = 0;
  while (cpu.pc !== 0xff00) {
    assert(++steps < 5_000_000, `${name} did not return`);
    assert(!runtime.isHalted(), `${name} halted`);
    runtime.step();
  }
  assert.equal(cpu.sp, 0xf002, `${name} stack`);
  return { carry: cpu.flags.C, tag: cpu.a, payload: cpu.h * 256 + cpu.l };
}
function table(context: number, kind: number, base: number, pool: number) {
  put(context, base);
  put(context + 2, 32);
  put(context + 4, pool);
  put(context + 6, 512);
  memory[context + 12] = kind;
  assert.equal(call("IINIT", 0, 0, 0, context).carry, 0);
}
function init(source: string) {
  const bytes = new TextEncoder().encode(source);
  memory.set(bytes, 0x8000);
  put(address("RFPTR"), 0x8000);
  put(address("RFLIMIT"), 0x8000 + bytes.length);
  table(0x6000, 0, 0x6100, 0x6400);
  table(0x600e, 1, 0x6200, 0x6800);
  assert.equal(
    call("RINIT", address("RFSOURCE"), 0x600e, 0x6000).carry,
    0,
  );
}
function evalSource(source: string) {
  init(source);
  const result = call("N5EXPR");
  assert.equal(result.carry, 0, source);
  return result;
}
Deno.test("native control evaluator handles nested forms and skips", () => {
  for (
    const [source, expected] of [
      ["(+ 40 2)", 42],
      ["(+ 10 (* 2 16))", 42],
      ["(if #f (+ 32767 1) (+ 40 2))", 42],
      ["(begin (+ 1 2) (+ 20 22))", 42],
      ["(if #t (if #f 1 42) (+ 3 4))", 42],
    ] as const
  ) {
    const result = evalSource(source);
    assert.equal(result.tag, 3, source);
    assert.equal(result.payload, expected, source);
  }
  assert.equal(evalSource("(if 0 11 22)").payload, 11);
  assert.equal(evalSource("(+)").payload, 0);
  assert.equal(evalSource("(*)").payload, 1);
  const notFalse = evalSource("(not #f)");
  assert.deepEqual([notFalse.tag, notFalse.payload], [0, 0xfe01]);
  const notTrue = evalSource("(not #t)");
  assert.deepEqual([notTrue.tag, notTrue.payload], [0, 0xfe00]);
  const number = evalSource("(number? 42)");
  assert.deepEqual([number.tag, number.payload], [0, 0xfe01]);
  const boolean = evalSource("(boolean? #t)");
  assert.deepEqual([boolean.tag, boolean.payload], [0, 0xfe01]);
  const zero = evalSource("(zero? 0)");
  assert.deepEqual([zero.tag, zero.payload], [0, 0xfe01]);
  assert.equal(evalSource("(- 40)").payload, 0xffd8);
  const sub = evalSource("(- 40 2)");
  assert.equal(sub.payload, 38);
  init("(/ 40)");
  assert.equal(call("N5EXPR").carry, 1);
  init("(-)");
  assert.equal(call("N5EXPR").carry, 1);
  init("(if #f (+ 32767 1) (+ 40 2))");
  const overflowSkipped = call("N5EXPR");
  assert.equal(overflowSkipped.carry, 0);
  assert.equal(overflowSkipped.payload, 42);

  for (
    const [source, expected] of [
      ["(if #f (quote (1 . 2)) 3)", 3],
      ["(if #t 3 (quote (1 2 . 3)))", 3],
    ] as const
  ) {
    const result = evalSource(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.tag, 3, source);
    assert.equal(result.payload, expected, source);
  }
});
