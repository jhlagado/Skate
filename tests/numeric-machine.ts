import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";
import type { Value } from "../tools/representation.ts";
export async function numericMachine() {
  const { runtime, address, image } = await loadAssembly(
    "tests/numeric-v2.asm",
  );
  const cpu = runtime.cpu, memory = runtime.hardware.memory;
  const ranges = [[address("F16WORK"), address("F16WEND")], [
    address("NWORK"),
    address("NWEND"),
  ]];
  let minStack = 0xf000;
  (runtime.hardware as typeof runtime.hardware & {
    memWrite: (p: number, v: number) => void;
  }).memWrite = (p, v) => {
    const stack = p >= 0xefc0 && p < 0xf000;
    assert.ok(
      stack || ranges.some(([lo, hi]) => p >= lo && p < hi),
      `unexpected write ${p.toString(16)}`,
    );
    if (stack) minStack = Math.min(minStack, p);
    memory[p] = v;
  };
  const stats = new Map<
    string,
    { calls: number; minCycles: number; maxCycles: number; stackBytes: number }
  >();
  function call(name: string, left: Value, right: Value = [0, 0]) {
    for (const [lo, hi] of ranges) {
      memory.fill((left[1] ^ right[1]) & 255, lo, hi);
    }
    cpu.a = left[0];
    cpu.h = left[1] >>> 8;
    cpu.l = left[1] & 255;
    cpu.b = right[0];
    cpu.d = right[1] >>> 8;
    cpu.e = right[1] & 255;
    cpu.c = 0x96;
    cpu.flags.C = (left[1] ^ right[1]) & 1;
    cpu.ix = 0x1357;
    cpu.iy = 0x2468;
    cpu.sp = 0xf000;
    cpu.pc = address(name);
    memory[0xf000] = 0;
    memory[0xf001] = 0xff;
    minStack = 0xf000;
    let steps = 0, cycles = 0;
    while (cpu.pc !== 0xff00) {
      assert.ok(++steps < 20000 && !runtime.isHalted(), `${name} no return`);
      cycles += runtime.step().cycles ?? 0;
    }
    assert.equal(cpu.sp, 0xf002);
    assert.equal(cpu.ix, 0x1357);
    assert.equal(cpu.iy, 0x2468);
    const stat = stats.get(name) ??
      { calls: 0, minCycles: Infinity, maxCycles: 0, stackBytes: 0 };
    stat.calls++;
    stat.minCycles = Math.min(stat.minCycles, cycles);
    stat.maxCycles = Math.max(stat.maxCycles, cycles);
    stat.stackBytes = Math.max(stat.stackBytes, 0xf000 - minStack);
    stats.set(name, stat);
    return {
      value: [cpu.a, cpu.h * 256 + cpu.l] as Value,
      carry: cpu.flags.C,
      cycles,
    };
  }
  return { call, address, image, stats };
}
