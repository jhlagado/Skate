import assert from "node:assert/strict";
import { createZ80Runtime } from "@jhlagado/debug80-runtime";
import { compileM10Package } from "../tools/m7-compiler.ts";
import { createSourcePackage } from "../tools/source-package.ts";

function runCom(
  compiled: Awaited<ReturnType<typeof compileM10Package>>,
): string {
  const memory = new Uint8Array(0x10000);
  memory.set(compiled.comBytes, compiled.entryAddress);
  memory.set([0xc3, 0x06, 0xf0], 5);
  const machine = createZ80Runtime({
    memory,
    startAddress: compiled.entryAddress,
  });
  const { cpu } = machine;
  const machineMemory = machine.hardware.memory;
  cpu.pc = compiled.entryAddress;
  cpu.sp = 0xf000;
  const output: string[] = [];
  let steps = 0;
  while (cpu.pc !== 0xff00) {
    assert.ok(++steps <= 1_000_000, "terminal demo did not terminate");
    assert.ok(!machine.isHalted(), "terminal demo halted");
    if (cpu.pc !== 5) {
      machine.step();
      continue;
    }
    if (cpu.c === 0) {
      cpu.pc = 0xff00;
      continue;
    }
    if (cpu.c === 2) {
      output.push(String.fromCharCode(cpu.e));
    } else if (cpu.c === 9) {
      let address = cpu.d * 256 + cpu.e;
      while (machineMemory[address] !== 0x24) {
        output.push(String.fromCharCode(machineMemory[address]!));
        address = (address + 1) & 0xffff;
      }
    } else {
      assert.fail(`unexpected BDOS function ${cpu.c}`);
    }
    const returnAddress = machineMemory[cpu.sp]! |
      (machineMemory[cpu.sp + 1]! << 8);
    cpu.sp += 2;
    cpu.pc = returnAddress;
  }
  return output.join("");
}

Deno.test("P1 package compiles the terminal Scheme library and ANSI demo", async () => {
  const sourcePackage = createSourcePackage([
    {
      name: "terminal.sk8",
      bytes: await Deno.readFile("libraries/terminal.sk8"),
    },
    {
      name: "terminal-demo.sk8",
      bytes: await Deno.readFile("examples/terminal-demo.sk8"),
    },
  ]);
  const compiled = await compileM10Package(sourcePackage);
  assert.equal(
    runCom(compiled),
    "\x1b[2J\x1b[H\x1b[31mHello from Skate\r\n\x1b[0m",
  );
  assert.ok(compiled.comBytes.length > 0);
});
