import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";
export async function lexerMachine() {
  const { runtime, address } = await loadAssembly("tests/lexer.asm");
  const cpu = runtime.cpu, memory = runtime.hardware.memory;
  let minStack = 0x7000;
  const word = (p: number) => memory[p] | memory[p + 1] << 8;
  const put = (p: number, n: number) => {
    memory[p] = n & 255;
    memory[p + 1] = n >>> 8;
  };
  (runtime.hardware as typeof runtime.hardware & {
    memWrite: (p: number, v: number) => void;
  }).memWrite = (p, v) => {
    assert.ok(
      (p >= address("LEXWORK") && p < address("LEXWEND")) ||
        (p >= address("LSPTR") && p < address("LSEND") + 2) ||
        (p >= 0x6f00 && p < 0x7000),
      `Unexpected lexer write ${p.toString(16)}`,
    );
    if (p >= 0x6f00 && p < 0x7000) minStack = Math.min(minStack, p);
    memory[p] = v;
  };
  function call(name: string, hl = 0) {
    cpu.pc = address(name);
    cpu.sp = 0x7000;
    cpu.h = hl >>> 8;
    cpu.l = hl & 255;
    cpu.ix = 0x1357;
    cpu.iy = 0x2468;
    put(0x7000, 0x7100);
    minStack = 0x7000;
    let steps = 0, cycles = 0;
    while (cpu.pc !== 0x7100) {
      assert.ok(
        ++steps < 2000000 && !runtime.isHalted(),
        `Lexer stuck at ${cpu.pc.toString(16)}`,
      );
      cycles += runtime.step().cycles ?? 0;
    }
    assert.equal(cpu.sp, 0x7002);
    assert.equal(cpu.ix, 0x1357);
    assert.equal(cpu.iy, 0x2468);
    const kind = cpu.a,
      payload = cpu.h * 256 + cpu.l,
      length = cpu.b * 256 + cpu.c;
    return {
      kind,
      steps,
      cycles,
      stackBytes: 0x7000 - minStack,
      carry: cpu.flags.C,
      payload,
      text: kind === 5 || kind === 6 || kind === 8
        ? memory.slice(payload, payload + length)
        : new Uint8Array(),
      at: [
        word(address("LTOKOFF")),
        word(address("LTOKLIN")),
        word(address("LTOKCOL")),
      ],
    };
  }
  function init(text: string | Uint8Array) {
    const data = typeof text === "string"
      ? new TextEncoder().encode(text)
      : text;
    assert.ok(data.length <= 0x5000);
    memory.set(data, 0x8000);
    put(address("LSPTR"), 0x8000);
    put(address("LSEND"), 0x8000 + data.length);
    call("LEXINIT", address("LSOURCE"));
  }
  return { call, init, address, memory, word, put };
}
