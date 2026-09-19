import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";

export async function internerMachine() {
  const { runtime, address } = await loadAssembly("tests/interner.asm");
  const cpu = runtime.cpu, memory = runtime.hardware.memory;
  const ranges: Array<[number, number]> = [];
  let minimumSP = 0x7000;
  let writes: number[] = [];
  (runtime.hardware as typeof runtime.hardware & {
    memWrite: (p: number, v: number) => void;
  }).memWrite = (p, v) => {
    assert.ok(
      (p >= address("IWORK") && p < address("IWEND")) ||
        (p >= 0x6fc0 && p < 0x7000) ||
        ranges.some(([start, end]) => p >= start && p < end),
      `Unexpected write at ${p.toString(16)}`,
    );
    if (p >= 0x6fc0 && p < 0x7000) minimumSP = Math.min(minimumSP, p);
    writes.push(p);
    memory[p] = v;
  };
  const word = (p: number) => memory[p] | memory[p + 1] << 8;
  function putWord(p: number, value: number) {
    memory[p] = value & 255;
    memory[p + 1] = value >>> 8;
  }
  function configure(
    context = 0x2000,
    kind = 0,
    entries = 16,
    bytes = 512,
    table = 0x3000,
    pool = 0x4000,
  ) {
    putWord(context, table);
    putWord(context + 2, entries);
    putWord(context + 4, pool);
    putWord(context + 6, bytes);
    memory[context + 12] = kind;
    ranges.push([context, context + 14]);
    ranges.push([
      table,
      Math.min(65536, table + entries * (kind === 0 ? 3 : 4)),
    ]);
    ranges.push([pool, Math.min(65536, pool + bytes)]);
  }
  function call(name: string, context = 0x2000, source = 0x6000, length = 0) {
    cpu.pc = address(name);
    cpu.sp = 0x7000;
    cpu.ix = context;
    cpu.iy = 0x2468;
    cpu.h = source >>> 8;
    cpu.l = source & 255;
    cpu.b = length >>> 8;
    cpu.c = length & 255;
    cpu.flags.C = 1;
    memory[0x7000] = 0;
    memory[0x7001] = 0x71;
    minimumSP = 0x7000;
    writes = [];
    let steps = 0, cycles = 0;
    while (cpu.pc !== 0x7100) {
      assert.ok(
        ++steps < 5000000 && !runtime.isHalted(),
        `${name} did not return`,
      );
      cycles += runtime.step().cycles ?? 0;
    }
    assert.equal(cpu.sp, 0x7002);
    assert.equal(cpu.ix, context);
    assert.equal(cpu.iy, 0x2468);
    if (cpu.flags.C) {
      assert.ok(
        writes.every((p) =>
          (p >= address("IWORK") && p < address("IWEND")) ||
          (p >= 0x6fc0 && p < 0x7000)
        ),
        "error wrote caller-owned context, table or pool",
      );
    }
    return {
      status: cpu.a,
      carry: cpu.flags.C,
      id: cpu.h * 256 + cpu.l,
      stackBytes: 0x7000 - minimumSP,
      cycles,
      writes: [...writes],
    };
  }
  function snapshot(context = 0x2000) {
    const table = word(context), pool = word(context + 4);
    return {
      context: memory.slice(context, context + 14),
      descriptors: memory.slice(
        table,
        table + word(context + 8) * (memory[context + 12] === 0 ? 3 : 4),
      ),
      pool: memory.slice(pool, pool + word(context + 10)),
    };
  }
  return { configure, call, snapshot, memory, word, putWord, address };
}
