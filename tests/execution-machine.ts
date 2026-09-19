import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";

export async function executionMachine() {
  const { runtime, address, symbols } = await loadAssembly(
    "tests/execution.asm",
  );
  const cpu = runtime.cpu;
  const memory = runtime.hardware.memory;
  const stackLow = 0xe000;
  const stackTop = 0xf000;
  const sentinel = 0x7f00;
  let writes: number[] = [];
  let lowestStack = stackTop;

  const allowedWork = [
    [address("HWORK"), address("HWEND")],
    [address("GCWORK"), address("GCWEND")],
    [address("RTWORK"), address("RTWEND")],
    [address("TESTWORK"), address("TESTWEND")],
  ] as const;
  const ranges = [
    [address("ROOTBASE"), address("ROOTEND")],
    [address("ACTBASE"), address("ACTEND")],
    [address("BMAPBAS"), address("BMAPBAS") + 16],
    [address("HEAPBASE"), address("HEAPBASE") + 4 * 128],
  ] as const;

  (runtime.hardware as typeof runtime.hardware & {
    memWrite: (address: number, value: number) => void;
  }).memWrite = (p, value) => {
    const stack = p >= stackLow && p < stackTop;
    const work = allowedWork.some(([lo, hi]) => p >= lo && p < hi);
    const region = ranges.some(([lo, hi]) => p >= lo && p < hi);
    assert.ok(
      stack || work || region,
      `unexpected write at $${p.toString(16)}`,
    );
    if (stack) lowestStack = Math.min(lowestStack, p);
    writes.push(p);
    memory[p] = value;
  };

  function run(name: string, maxSteps = 200_000) {
    writes = [];
    lowestStack = stackTop;
    cpu.pc = address(name);
    cpu.sp = stackTop;
    cpu.ix = 0xffff;
    cpu.iy = 0xeeee;
    cpu.flags.C = 1;
    memory[stackTop] = sentinel & 255;
    memory[stackTop + 1] = sentinel >>> 8;
    let steps = 0;
    while (cpu.pc !== sentinel) {
      assert.ok(
        ++steps <= maxSteps,
        `${name} did not return; PC=$${cpu.pc.toString(16)}`,
      );
      assert.ok(
        !runtime.isHalted(),
        `${name} halted with error ${memory[address("TERROR")]}`,
      );
      runtime.step();
    }
    assert.equal(
      cpu.sp,
      stackTop + 2,
      `${name} returned with an unbalanced stack`,
    );
    return {
      steps,
      stackBytes: stackTop - lowestStack,
      writes: [...writes],
    };
  }

  function runToError(name: string, maxSteps = 200_000) {
    writes = [];
    lowestStack = stackTop;
    cpu.pc = address(name);
    cpu.sp = stackTop;
    cpu.ix = 0xffff;
    cpu.iy = 0xeeee;
    cpu.flags.C = 1;
    memory[stackTop] = sentinel & 255;
    memory[stackTop + 1] = sentinel >>> 8;
    let steps = 0;
    while (!runtime.isHalted()) {
      assert.ok(
        ++steps <= maxSteps,
        `${name} did not reach the terminal test error; PC=$${
          cpu.pc.toString(16)
        }`,
      );
      runtime.step();
    }
    return { steps, writes: [...writes], code: memory[address("TERROR")]! };
  }

  const word = (p: number) => memory[p]! | memory[p + 1]! << 8;
  return { run, runToError, runtime, cpu, memory, address, symbols, word };
}
