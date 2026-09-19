import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";

export async function decimalMachine() {
  const { runtime, address } = await loadAssembly("tests/decimal.asm");
  const cpu = runtime.cpu, memory = runtime.hardware.memory;
  const workStart = address("DWORK"), workEnd = address("DWEND");
  assert.equal(workEnd - workStart, 101, "workspace clear extent");
  let minStack = 0x7000;
  let maxCycles = 0;
  let maxStack = 0;
  (runtime.hardware as typeof runtime.hardware & {
    memWrite: (p: number, v: number) => void;
  }).memWrite = (p, v) => {
    const stack = p >= 0x6f00 && p < 0x7000;
    if (!stack && !(p >= workStart && p < workEnd)) {
      throw new Error(`unexpected write ${p.toString(16)}`);
    }
    if (stack) minStack = Math.min(minStack, p);
    memory[p] = v;
  };
  function parse(token: string, input = 0x8000, length = token.length) {
    const bytes = new TextEncoder().encode(token);
    if (input + bytes.length <= 65536) memory.set(bytes, input);
    memory.fill(0xa5, workStart, workEnd);
    cpu.pc = address("DPARSE");
    cpu.sp = 0x7000;
    cpu.ix = 0x1357;
    cpu.iy = 0x2468;
    cpu.h = input >>> 8;
    cpu.l = input & 255;
    cpu.b = length >>> 8;
    cpu.c = length & 255;
    cpu.flags.C = length & 1;
    memory[0x7000] = 0;
    memory[0x7001] = 0x71;
    minStack = 0x7000;
    let steps = 0, cycles = 0;
    while (cpu.pc !== 0x7100) {
      if (++steps >= 2000000 || runtime.isHalted()) {
        throw new Error(`${token}: no return at ${cpu.pc.toString(16)}`);
      }
      cycles += runtime.step().cycles ?? 0;
    }
    assert.equal(cpu.sp, 0x7002, `${token}: stack`);
    assert.equal(cpu.ix, 0x1357);
    assert.equal(cpu.iy, 0x2468);
    if (input + bytes.length <= 65536) {
      assert.deepEqual(memory.slice(input, input + bytes.length), bytes);
    }
    maxCycles = Math.max(maxCycles, cycles);
    maxStack = Math.max(maxStack, 0x7000 - minStack);
    return { tag: cpu.a, bits: cpu.h << 8 | cpu.l, carry: cpu.flags.C, cycles };
  }
  return {
    parse,
    census: () => ({
      codeBytes: address("DEND") - address("DPARSE"),
      workspaceBytes: address("DWEND") - address("DWORK"),
      maxCycles,
      maxStack,
    }),
  };
}
