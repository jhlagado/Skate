import { loadAssembly } from "../tests/z80.ts";
import assert from "node:assert/strict";
const { address, image } = await loadAssembly(
  Deno.args[0] ?? "tests/cpm-reader.asm",
);
const spans = [
  ["lexer", "LEXINIT", "LEXCODE", "LEXWORK", "LEXWEND"],
  ["decimal", "DPARSE", "DEND", "DWORK", "DWEND"],
  ["interner", "IINIT", "IEND", "IWORK", "IWEND"],
  ["reader", "RINIT", "REND", "RWORK", "RWEND"],
  ["cpm-source", "CSOPEN", "CSWORK", "CSWORK", "CSWEND"],
];
const corpus = [
  "(define (square x) (* x x)) (display (square 12))",
  "(lambda () '(2049 2049.0 -0 -0.0 #t #f . #\\xFF))",
  '"A" "\\x41;" "" "\\n\\r\\t\\\\\\""',
  "1.00048828125 1e999999 -1e-999999",
  "(a . b c)",
];
const proofs = [];
for (const source of corpus) {
  const { runtime, address: at } = await loadAssembly(
    Deno.args[1] ?? "tests/reader.asm",
  );
  const cpu = runtime.cpu, memory = runtime.hardware.memory;
  const put = (p: number, value: number) => {
    memory[p] = value & 255;
    memory[p + 1] = value >>> 8;
  };
  const call = (name: string, hl = 0, bc = 0, de = 0, ix = 0x1357) => {
    cpu.pc = at(name);
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
    let cycles = 0, instructions = 0;
    while (cpu.pc !== 0xff00) {
      assert(++instructions < 5000000 && !runtime.isHalted());
      cycles += runtime.step().cycles ?? 0;
    }
    assert.equal(cpu.sp, 0xf002);
    assert.equal(cpu.ix, ix);
    assert.equal(cpu.iy, 0x2468);
    return { cycles, instructions, kind: cpu.a, carry: cpu.flags.C };
  };
  for (
    const [context, table, pool, kind] of [[0x6000, 0x6100, 0x6400, 0], [
      0x600e,
      0x6200,
      0x6800,
      1,
    ]]
  ) {
    put(context, table);
    put(context + 2, 16);
    put(context + 4, pool);
    put(context + 6, 512);
    memory[context + 12] = kind;
    assert.equal(call("IINIT", 0, 0, 0, context).carry, 0);
  }
  const bytes = new TextEncoder().encode(source);
  memory.set(bytes, 0x8000);
  put(at("RFPTR"), 0x8000);
  put(at("RFLIMIT"), 0x8000 + bytes.length);
  assert.equal(call("RINIT", at("RFSOURCE"), 0x600e, 0x6000).carry, 0);
  let events = 0, cycles = 0, instructions = 0, maxCallCycles = 0;
  while (true) {
    const x = call("RNEXT");
    events++;
    cycles += x.cycles;
    instructions += x.instructions;
    maxCallCycles = Math.max(maxCallCycles, x.cycles);
    if (x.carry || x.kind === 0) break;
  }
  proofs.push({ source, events, cycles, instructions, maxCallCycles });
}
console.log(JSON.stringify(
  {
    modules: spans.map(([name, start, end, ws, we]) => ({
      name,
      codeAndConstants: address(end) - address(start),
      workspace: address(we) - address(ws),
    })),
    comBytes: image.bytes.length - (0x100 - image.base),
    proofs,
  },
  null,
  2,
));
