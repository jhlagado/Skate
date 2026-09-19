import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";

export async function readerMachine() {
  const { runtime, address } = await loadAssembly("tests/reader.asm");
  const cpu = runtime.cpu, memory = runtime.hardware.memory;
  const word = (p: number) => memory[p] | memory[p + 1] << 8;
  const put = (p: number, value: number) => {
    memory[p] = value & 255;
    memory[p + 1] = value >>> 8;
  };
  let lowStack = 0xf000;
  const workspaces = [
    [address("LEXWORK"), address("LEXWEND")],
    [address("DWORK"), address("DWEND")],
    [address("IWORK"), address("IWEND")],
    [address("RWORK"), address("RWEND")],
    [address("RFWORK"), address("RFWEND")],
  ];
  const writable = [
    ...workspaces,
    [0xef00, 0xf000],
    [0x6000, 0x601c],
    [0x6100, 0x6130],
    [0x6200, 0x6240],
    [0x6400, 0x6600],
    [0x6800, 0x6a00],
  ];
  assert(address("RFWEND") < 0x6000, "Compiler fixture overlaps test tables");
  (runtime.hardware as typeof runtime.hardware & {
    memWrite: (p: number, v: number) => void;
  }).memWrite = (p, v) => {
    assert(
      writable.some(([start, end]) => p >= start && p < end),
      `Unexpected reader write ${p.toString(16)}`,
    );
    if (p >= 0xef00 && p < 0xf000) lowStack = Math.min(lowStack, p);
    memory[p] = v;
  };
  const stats = new Map<
    string,
    { calls: number; cycles: number; stack: number }
  >();
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
    lowStack = 0xf000;
    let steps = 0, cycles = 0;
    while (cpu.pc !== 0xff00) {
      assert(
        ++steps < 5000000 && !runtime.isHalted(),
        `${name} failed to return at ${cpu.pc.toString(16)}`,
      );
      cycles += runtime.step().cycles ?? 0;
    }
    assert.equal(cpu.sp, 0xf002);
    assert.equal(cpu.ix, ix);
    assert.equal(cpu.iy, 0x2468);
    const s = stats.get(name) ?? { calls: 0, cycles: 0, stack: 0 };
    s.calls++;
    s.cycles = Math.max(s.cycles, cycles);
    s.stack = Math.max(s.stack, 0xf000 - lowStack);
    stats.set(name, s);
    return {
      kind: cpu.a,
      carry: cpu.flags.C,
      payload: cpu.h * 256 + cpu.l,
      tag: memory[address("RTAG")],
      at: [
        word(address("LTOKOFF")),
        word(address("LTOKLIN")),
        word(address("LTOKCOL")),
      ],
    };
  }
  function table(
    context: number,
    kind: number,
    base: number,
    pool: number,
    entries = 16,
    poolBytes = 512,
  ) {
    put(context, base);
    put(context + 2, entries);
    put(context + 4, pool);
    put(context + 6, poolBytes);
    memory[context + 12] = kind;
    assert.equal(call("IINIT", 0, 0, 0, context).carry, 0);
  }
  function init(source: string | Uint8Array, entries = 16, poolBytes = 512) {
    const bytes = typeof source === "string"
      ? new TextEncoder().encode(source)
      : source;
    assert(bytes.length <= 0x6000);
    memory.set(bytes, 0x8000);
    put(address("RFPTR"), 0x8000);
    put(address("RFLIMIT"), 0x8000 + bytes.length);
    table(0x6000, 0, 0x6100, 0x6400, entries, poolBytes);
    table(0x600e, 1, 0x6200, 0x6800, entries, poolBytes);
    assert.equal(call("RINIT", address("RFSOURCE"), 0x600e, 0x6000).carry, 0);
  }
  function tables() {
    return [{ context: 0x6000, stride: 3 }, { context: 0x600e, stride: 4 }].map(
      ({ context, stride }) => ({
        descriptors: memory.slice(
          word(context),
          word(context) + word(context + 8) * stride,
        ),
        pool: memory.slice(
          word(context + 4),
          word(context + 4) + word(context + 10),
        ),
      }),
    );
  }
  return { call, init, tables, memory, address, word, put, stats };
}
