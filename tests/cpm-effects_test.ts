import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";

async function effectMachine() {
  const { runtime, address } = await loadAssembly("tests/cpm-effects.asm");
  const cpu = runtime.cpu;
  const memory = runtime.hardware.memory;
  const input: number[] = [];
  const output: number[] = [];
  const calls: number[] = [];
  const argumentsSeen: { fn: number; e: number }[] = [];

  memory[5] = 0xc9;
  (runtime.hardware as typeof runtime.hardware & {
    memWrite: (address: number, value: number) => void;
  }).memWrite = (location, value) => {
    assert.ok(
      location >= 0xefe0 && location < 0xf000,
      `unexpected bridge write at ${location.toString(16)}`,
    );
    memory[location] = value;
  };

  function bdos(): void {
    calls.push(cpu.c);
    argumentsSeen.push({ fn: cpu.c, e: cpu.e });
    if (cpu.c === 6 && cpu.e !== 0xff) {
      output.push(cpu.e);
      cpu.a = 0;
    } else if (cpu.c === 6) {
      cpu.a = input.shift() ?? 0;
    } else {
      throw new Error(`unexpected BDOS function ${cpu.c}`);
    }
    cpu.ix = 0;
    cpu.iy = 0;
    cpu.b =
      cpu.c =
      cpu.d =
      cpu.e =
      cpu.h =
      cpu.l =
        0xaa;
  }

  function call(
    name: string,
    value?: number,
  ): { value: number; carry: number } {
    cpu.pc = address(name);
    cpu.sp = 0xf000;
    cpu.ix = 0x1357;
    cpu.iy = 0x2468;
    if (value !== undefined) cpu.a = value;
    memory[0xf000] = 0;
    memory[0xf001] = 0xff;
    let steps = 0;
    while (cpu.pc !== 0xff00) {
      assert.ok(++steps < 10_000, `${name} did not return`);
      if (cpu.pc === 5) bdos();
      runtime.step();
    }
    assert.equal(cpu.sp, 0xf002, `${name} balances SP`);
    assert.equal(cpu.ix, 0x1357, `${name} preserves IX`);
    assert.equal(cpu.iy, 0x2468, `${name} preserves IY`);
    return { value: cpu.a, carry: cpu.flags.C };
  }

  return {
    call,
    input,
    output,
    calls,
    argumentsSeen,
  };
}

Deno.test("CP/M direct output preserves bytes except its reserved FF selector", async () => {
  const machine = await effectMachine();
  for (const byte of [0x00, 0x09, 0x1b, 0x7e]) {
    assert.deepEqual(machine.call("SEPUT", byte), { value: 0, carry: 0 });
  }
  assert.deepEqual(machine.call("SEPUT", 0xff), { value: 1, carry: 1 });
  assert.deepEqual(machine.output, [0x00, 0x09, 0x1b, 0x7e]);
  assert.deepEqual(machine.calls, [6, 6, 6, 6]);
  assert.deepEqual(machine.argumentsSeen, [
    { fn: 6, e: 0x00 },
    { fn: 6, e: 0x09 },
    { fn: 6, e: 0x1b },
    { fn: 6, e: 0x7e },
  ]);
});

Deno.test("CP/M direct input carries available control bytes and reports empty as zero", async () => {
  const machine = await effectMachine();
  machine.input.push(0x1b, 0x7e, 0xff);
  assert.deepEqual(
    [
      machine.call("SEGET").value,
      machine.call("SEGET").value,
      machine.call("SEGET").value,
      machine.call("SEGET").value,
    ],
    [0x1b, 0x7e, 0xff, 0x00],
  );
  assert.deepEqual(machine.calls, [6, 6, 6, 6]);
  assert.ok(machine.argumentsSeen.every(({ fn, e }) => fn === 6 && e === 0xff));
});
