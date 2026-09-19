import assert from "node:assert/strict";
import { createZ80Runtime } from "@jhlagado/debug80-runtime";
import { compileM7 } from "../tools/m7-compiler.ts";

function runCom(compiled: Awaited<ReturnType<typeof compileM7>>) {
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
  let returnedSp = 0;
  let steps = 0;
  while (cpu.pc !== 0xff00) {
    assert.ok(
      ++steps <= 1_000_000,
      `COM did not terminate through CP/M BDOS: PC=$${cpu.pc.toString(16)} ` +
        `SP=$${cpu.sp.toString(16)}`,
    );
    assert.ok(!machine.isHalted(), "COM halted instead of returning to CP/M");
    if (cpu.pc !== 5) {
      machine.step();
      continue;
    }
    if (cpu.c === 0) {
      returnedSp = cpu.sp + 2;
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
        assert.ok(++length < 256, "BDOS string lacks its '$' terminator");
      }
    } else {
      assert.fail(`Unexpected CP/M BDOS function ${cpu.c}`);
    }
    const returnAddress = machineMemory[cpu.sp]! |
      (machineMemory[cpu.sp + 1]! << 8);
    cpu.sp += 2;
    cpu.pc = returnAddress;
  }
  const wordAt = (address: number) =>
    machineMemory[address]! | (machineMemory[address + 1]! << 8);
  return {
    output: output.join(""),
    resultTag: machineMemory[compiled.resultTagAddress]!,
    result: wordAt(compiled.resultAddress),
    rootBase: compiled.rootBaseAddress,
    rootHighWater: wordAt(compiled.rootHighWaterAddress),
    activationBase: compiled.activationBaseAddress,
    activationHighWater: wordAt(compiled.activationHighWaterAddress),
    sp: returnedSp,
    stackTop: compiled.stackTopAddress,
    steps,
  };
}

async function run(source: string) {
  return runCom(await compileM7(new TextEncoder().encode(source), "m7.sk8"));
}

Deno.test("M7 compiles fixed-arity lambdas and reads parameters in order", async () => {
  const compiled = await compileM7(
    new TextEncoder().encode("((lambda (a b) (+ a b)) 17 25)"),
    "fixed-arity.sk8",
  );
  assert.equal(compiled.resultKind, "dynamic");
  assert.equal(compiled.runtimeBase, 0x0103);
  assert.ok(compiled.object.relocations.length > 0);

  const result = runCom(compiled);
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
  assert.equal(result.sp, compiled.stackTopAddress);
});

Deno.test("M7 evaluates higher-order nested calls with live values rooted", async () => {
  const result = await run(
    "((lambda (f x) (+ (f x) (f x))) (lambda (v) (+ v 1)) 20)",
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
  assert.equal(result.sp, result.stackTop);
  assert.ok(result.rootHighWater > result.rootBase);
  assert.ok(result.activationHighWater > result.activationBase);
});

Deno.test("M7 tail applications work in if and begin tail positions", async () => {
  const conditional = await run(
    "((lambda (f x) (if #t (f x) 0)) (lambda (n) (+ n 1)) 41)",
  );
  assert.equal(conditional.result, 42);
  assert.equal(conditional.output, "42\r\n");
  assert.equal(conditional.sp, conditional.stackTop);

  const sequence = await run(
    "((lambda (f x) (begin 0 (f x))) (lambda (n) (+ n 1)) 41)",
  );
  assert.equal(sequence.result, 42);
  assert.equal(sequence.output, "42\r\n");
  assert.equal(sequence.sp, sequence.stackTop);
});

Deno.test("M7 permits a parameter to shadow an arithmetic form", async () => {
  const result = await run("((lambda (+) (+ 1 2)) (lambda (a b) 42))");
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
});

Deno.test("M7 reports wrong arity at runtime before returning a result", async () => {
  const result = await run("((lambda (x) x) 1 2)");
  assert.equal(result.output, "RUNTIME ERROR\r\n");
  assert.equal(result.resultTag, 0);
});

Deno.test("M7 rejects captured variables until M8", async () => {
  await assert.rejects(
    () => run("((lambda (x) (lambda () x)) 42)"),
    (error: unknown) =>
      error instanceof SyntaxError && error.message.includes("deferred to M8"),
  );
});
