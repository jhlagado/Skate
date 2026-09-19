import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";

export async function allocatorMachine(entry = "tests/allocator.asm") {
  const { runtime, image, symbols, address } = await loadAssembly(entry);
  const cpu = runtime.cpu, memory = runtime.hardware.memory;
  let base = 0, end = 0, lowestStack = 0, writes: number[] = [];
  const stackTop = 0x7000, returnPC = 0x7100;
  const workStart = address("HWORK"), workEnd = address("HWEND");
  const stats = new Map<
    string,
    { calls: number; minCycles: number; maxCycles: number; stackBytes: number }
  >();
  (runtime.hardware as typeof runtime.hardware & {
    memWrite: (p: number, v: number) => void;
  }).memWrite = (p, v) => {
    const heap = p >= base + 4 && p < end;
    const work = (p >= workStart && p < workEnd) ||
      (symbols.has("nwork") && p >= symbols.get("nwork")! &&
        p < symbols.get("nwend")!) ||
      (symbols.has("f16work") && p >= symbols.get("f16work")! &&
        p < symbols.get("f16wend")!);
    const stack = p >= stackTop - 64 && p < stackTop;
    assert.ok(
      heap || work || stack,
      `write outside allowed regions at ${p.toString(16)}`,
    );
    if (stack) lowestStack = Math.min(lowestStack, p);
    writes.push(p);
    memory[p] = v;
  };
  const word = (p: number) => memory[p] | memory[p + 1] << 8;
  function state() {
    return {
      base: word(address("HBASE")),
      cells: word(address("HCOUNT")),
      head: word(address("HHEAD")),
      free: word(address("HFCOUNT")),
      left: word(address("HLEFT")),
      active: memory[address("HACTIVE")],
      ready: memory[address("HREADY")],
    };
  }
  function arena(start: number, cells: number) {
    base = start;
    end = start + 4 * cells;
  }
  function call(name: string, hl = 0, bc = 0, tag = 0xa5, de = 0x9669) {
    writes = [];
    lowestStack = stackTop;
    cpu.pc = address(name);
    cpu.sp = stackTop;
    cpu.h = hl >>> 8;
    cpu.l = hl & 255;
    cpu.b = bc >>> 8;
    cpu.c = bc & 255;
    cpu.a = tag;
    cpu.d = de >>> 8;
    cpu.e = de & 255;
    cpu.ix = 0x1357;
    cpu.iy = 0x2468;
    cpu.flags.C = (hl ^ bc) & 1;
    memory[stackTop] = returnPC & 255;
    memory[stackTop + 1] = returnPC >>> 8;
    let cycles = 0, steps = 0;
    while (cpu.pc !== returnPC) {
      assert.ok(
        ++steps < 1000000 && !runtime.isHalted(),
        `${name} did not return`,
      );
      cycles += runtime.step().cycles ?? 0;
    }
    assert.equal(cpu.sp, stackTop + 2, `${name} SP`);
    assert.equal(cpu.ix, 0x1357, `${name} IX`);
    assert.equal(cpu.iy, 0x2468, `${name} IY`);
    const s = stats.get(name) ??
      { calls: 0, minCycles: Infinity, maxCycles: 0, stackBytes: 0 };
    s.calls++;
    s.minCycles = Math.min(s.minCycles, cycles);
    s.maxCycles = Math.max(s.maxCycles, cycles);
    s.stackBytes = Math.max(s.stackBytes, stackTop - lowestStack);
    stats.set(name, s);
    return {
      status: cpu.a,
      carry: cpu.flags.C,
      hl: cpu.h * 256 + cpu.l,
      de: cpu.d * 256 + cpu.e,
      cycles,
      steps,
      writes: [...writes],
    };
  }
  return {
    call,
    arena,
    state,
    memory,
    word,
    address,
    image,
    stats,
    workStart,
    workEnd,
    symbols,
  };
}
