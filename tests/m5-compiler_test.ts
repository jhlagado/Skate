import assert from "node:assert/strict";
import { createZ80Runtime } from "@jhlagado/debug80-runtime";
import { compileM5 } from "../tools/m5-compiler.ts";

function runCom(compiled: Awaited<ReturnType<typeof compileM5>>) {
  const memory = new Uint8Array(0x10000);
  memory.set(compiled.comBytes, compiled.entryAddress);
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
    assert.ok(
      ++steps <= 200_000,
      `COM did not terminate through CP/M BDOS: PC=$${
        cpu.pc.toString(16)
      } SP=$${cpu.sp.toString(16)} A=${cpu.a} BC=${cpu.b.toString(16)}${
        cpu.c.toString(16)
      } HL=${cpu.h.toString(16)}${cpu.l.toString(16)}`,
    );
    assert.ok(!machine.isHalted(), "COM halted instead of returning to CP/M");
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
      let length = 0;
      while (machineMemory[address] !== 0x24) {
        output.push(String.fromCharCode(machineMemory[address]!));
        address = (address + 1) & 0xffff;
        assert.ok(
          ++length < 256,
          "CP/M function 9 string has no '$' terminator",
        );
      }
    } else {
      assert.fail(`Unexpected CP/M BDOS function ${cpu.c}`);
    }
    const returnAddress = machineMemory[cpu.sp]! |
      (machineMemory[cpu.sp + 1]! << 8);
    cpu.sp += 2;
    cpu.pc = returnAddress;
  }
  return {
    memory,
    output: output.join(""),
    steps,
    resultTag: machineMemory[compiled.resultTagAddress]!,
    result: machineMemory[compiled.resultAddress]! |
      (machineMemory[compiled.resultAddress + 1]! << 8),
  };
}

Deno.test("M5 writes a committed NOBJ and links an exact integer COM", async () => {
  const compiled = await compileM5(
    new TextEncoder().encode("(+ 40 2)"),
    "add.sk8",
  );
  assert.equal(compiled.entryAddress, 0x0100);
  assert.equal(compiled.resultKind, "integer");
  assert.equal(compiled.object.begin.targetId, 1);
  assert.equal(compiled.object.layout.mode, "module");
  assert.equal(compiled.object.relocations.length, 4);
  assert.equal(compiled.object.ranges[0]?.length, 40);
  assert.ok(compiled.comBytes.length > compiled.runtimeBase - 0x0100);

  const result = runCom(compiled);
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
  assert.ok(result.steps < 200_000);
});

Deno.test("M5 preserves signed16 bounds and rejects exact overflow at runtime", async () => {
  const lower = await compileM5(
    new TextEncoder().encode("(+ -32767 -1)"),
    "lower.sk8",
  );
  const exact = runCom(lower);
  assert.equal(exact.resultTag, 3);
  assert.equal(exact.result, 0x8000);
  assert.equal(exact.output, "-32768\r\n");

  const overflow = await compileM5(
    new TextEncoder().encode("(+ 32767 1)"),
    "overflow.sk8",
  );
  const failed = runCom(overflow);
  assert.equal(failed.output, "NUMERIC ERROR\r\n");
  assert.equal(failed.resultTag, 0, "failure does not publish a result tag");
});

Deno.test("M5 links mixed arithmetic and division to binary16 runtime entries", async () => {
  const mixed = await compileM5(
    new TextEncoder().encode("(+ 2049 0.0)"),
    "mixed.sk8",
  );
  assert.equal(mixed.resultKind, "binary16");
  const mixedResult = runCom(mixed);
  assert.equal(mixedResult.resultTag, 0);
  assert.equal(mixedResult.result, 0x6800);
  assert.equal(mixedResult.output, "");

  const division = await compileM5(
    new TextEncoder().encode("(/ 1 2)"),
    "division.sk8",
  );
  const divisionResult = runCom(division);
  assert.equal(divisionResult.resultTag, 0);
  assert.equal(divisionResult.result, 0x3800);
});

Deno.test("M5 accepts only one flat literal arithmetic form", async () => {
  for (
    const source of [
      "",
      "(+ 1 x)",
      "(display 1)",
      "(+ 1) (+ 2)",
      "(-)",
      "(/ 1)",
      "(+ #t 1)",
    ]
  ) {
    await assert.rejects(
      () => compileM5(new TextEncoder().encode(source), "invalid.sk8"),
      (error: unknown) => error instanceof Error,
      `invalid source: ${source}`,
    );
  }
});
