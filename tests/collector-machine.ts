import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";
import type { Value } from "../tools/representation.ts";
export async function collectorMachine(entry = "tests/collector.asm") {
  const { runtime, address, image, symbols } = await loadAssembly(entry);
  const cpu = runtime.cpu, memory = runtime.hardware.memory;
  let heapBase = 0,
    heapEnd = 0,
    bitmapBase = 0,
    bitmapEnd = 0,
    minStack = 0x7000,
    writeCount = 0;
  const stats = new Map<
    string,
    { calls: number; maxCycles: number; maxSteps: number; stackBytes: number }
  >();
  const word = (p: number) => memory[p] | memory[p + 1] << 8;
  function putWord(p: number, w: number) {
    memory[p] = w & 255;
    memory[p + 1] = w >>> 8;
  }
  function slot(p: number, v: Value) {
    memory[p] = v[0];
    putWord(p + 1, v[1]);
    memory[p + 3] = 0;
  }
  function descriptor(p: number, start: number, count: number, stride = 4) {
    putWord(p, start);
    putWord(p + 2, count);
    putWord(p + 4, stride);
  }
  const workRanges = [[address("HWORK"), address("HWEND")], [
    address("GCWORK"),
    address("GCWEND"),
  ]];
  for (const [start, end] of [["NWORK", "NWEND"], ["F16WORK", "F16WEND"]]) {
    if (symbols.has(start.toLowerCase())) {
      workRanges.push([address(start), address(end)]);
    }
  }
  (runtime.hardware as typeof runtime.hardware & {
    memWrite: (p: number, v: number) => void;
  }).memWrite = (p, v) => {
    const stack = p >= 0x6f00 && p < 0x7000;
    assert.ok(
      stack || workRanges.some(([lo, hi]) => p >= lo && p < hi) ||
        (p >= heapBase + 4 && p < heapEnd) ||
        (p >= bitmapBase && p < bitmapEnd),
      `unexpected write ${p.toString(16)}`,
    );
    if (stack) minStack = Math.min(minStack, p);
    writeCount++;
    memory[p] = v;
  };
  function call(
    name: string,
    hl = 0,
    bc = 0,
    de = 0,
    maxSteps = 30000000,
    tag = 0x96,
  ) {
    cpu.pc = address(name);
    cpu.sp = 0x7000;
    cpu.a = tag;
    cpu.b = bc >>> 8;
    cpu.c = bc & 255;
    cpu.d = de >>> 8;
    cpu.e = de & 255;
    cpu.h = hl >>> 8;
    cpu.l = hl & 255;
    cpu.ix = 0x1357;
    cpu.iy = 0x2468;
    cpu.flags.C = (hl ^ bc ^ de) & 1;
    memory[0x7000] = 0;
    memory[0x7001] = 0x71;
    minStack = 0x7000;
    writeCount = 0;
    let steps = 0, cycles = 0;
    while (cpu.pc !== 0x7100) {
      assert.ok(
        ++steps <= maxSteps && !runtime.isHalted(),
        `${name} did not return at ${cpu.pc.toString(16)}`,
      );
      cycles += runtime.step().cycles ?? 0;
    }
    assert.equal(cpu.sp, 0x7002, `${name} SP`);
    assert.equal(cpu.ix, 0x1357, `${name} IX`);
    assert.equal(cpu.iy, 0x2468, `${name} IY`);
    const stat = stats.get(name) ??
      { calls: 0, maxCycles: 0, maxSteps: 0, stackBytes: 0 };
    stat.calls++;
    stat.maxCycles = Math.max(stat.maxCycles, cycles);
    stat.maxSteps = Math.max(stat.maxSteps, steps);
    stat.stackBytes = Math.max(stat.stackBytes, 0x7000 - minStack);
    stats.set(name, stat);
    return {
      status: cpu.a,
      carry: cpu.flags.C,
      hl: cpu.h * 256 + cpu.l,
      de: cpu.d * 256 + cpu.e,
      steps,
      cycles,
      writeCount,
    };
  }
  function heapRange(base: number, count: number) {
    heapBase = base;
    heapEnd = base + 4 * count;
  }
  function bitmapRange(base: number, bytes: number) {
    bitmapBase = base;
    bitmapEnd = base + bytes;
  }
  function state() {
    return {
      base: word(address("HBASE")),
      count: word(address("HCOUNT")),
      head: word(address("HHEAD")),
      free: word(address("HFCOUNT")),
      left: word(address("HLEFT")),
      active: memory[address("HACTIVE")],
      ready: memory[address("HREADY")],
    };
  }
  function freeSet() {
    const s = state(), seen = new Set<number>();
    let i = s.head;
    while (i) {
      assert.ok(i > 0 && i < s.count && !seen.has(i), `bad free index ${i}`);
      seen.add(i);
      assert.equal(word(s.base + 4 * i + 2), 0);
      i = word(s.base + 4 * i);
    }
    assert.equal(seen.size, s.free);
    return seen;
  }
  function cell(i: number, a: number, b: number) {
    putWord(heapBase + 4 * i, a);
    putWord(heapBase + 4 * i + 2, b);
  }
  return {
    call,
    memory,
    address,
    image,
    word,
    putWord,
    slot,
    descriptor,
    heapRange,
    bitmapRange,
    state,
    freeSet,
    cell,
    stats,
  };
}
