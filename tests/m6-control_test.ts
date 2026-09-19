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
  let returnedSp = cpu.sp;
  let steps = 0;
  while (cpu.pc !== 0xff00) {
    assert.ok(
      ++steps <= 200_000,
      `COM did not terminate: PC=$${cpu.pc.toString(16)} SP=$${
        cpu.sp.toString(16)
      }`,
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
  const result = {
    output: output.join(""),
    resultTag: machineMemory[compiled.resultTagAddress]!,
    result: machineMemory[compiled.resultAddress]! |
      (machineMemory[compiled.resultAddress + 1]! << 8),
    sp: returnedSp,
    steps,
  };
  return result;
}

async function run(source: string) {
  return runCom(await compileM5(new TextEncoder().encode(source), "m6.sk8"));
}

Deno.test("M6 if runs only the selected branch, even when the other would fail", async () => {
  const falseArm = await run("(if #f (+ 32767 1) (+ 40 2))");
  assert.equal(falseArm.output, "42\r\n");
  assert.equal(falseArm.resultTag, 3);
  assert.equal(falseArm.result, 42);
  assert.equal(falseArm.sp, 0xf000);

  const trueArm = await run("(if #t 42 (+ 32767 1))");
  assert.equal(trueArm.output, "42\r\n");
  assert.equal(trueArm.result, 42);
  assert.equal(trueArm.sp, 0xf000);

  const selectedFailure = await run("(if #t (+ 32767 1) 42)");
  assert.equal(selectedFailure.output, "NUMERIC ERROR\r\n");
  assert.equal(selectedFailure.resultTag, 0);
  assert.equal(selectedFailure.sp, 0xf000);
});

Deno.test("M6 treats only #f as false", async () => {
  const cases = [
    ["#f", 22],
    ["#t", 11],
    ["0", 11],
    ["0.0", 11],
    ["#\\space", 11],
  ] as const;
  for (const [test, expected] of cases) {
    const result = await run(`(if ${test} 11 22)`);
    assert.equal(result.resultTag, 3, test);
    assert.equal(result.result, expected, test);
    assert.equal(result.output, `${expected}\r\n`, test);
  }
});

Deno.test("M6 begin evaluates in order and returns its final expression", async () => {
  const sequence = await run("(begin (+ 1 2) (+ 20 22))");
  assert.equal(sequence.resultTag, 3);
  assert.equal(sequence.result, 42);
  assert.equal(sequence.output, "42\r\n");
  assert.equal(sequence.sp, 0xf000);

  const earlierFailure = await run("(begin (+ 32767 1) 42)");
  assert.equal(earlierFailure.output, "NUMERIC ERROR\r\n");
  assert.equal(earlierFailure.resultTag, 0);
  assert.equal(earlierFailure.sp, 0xf000);
});

Deno.test("M6 omitted alternatives and empty begin return UNSPECIFIED", async () => {
  for (const source of ["(if #f 42)", "(begin)"]) {
    const result = await run(source);
    assert.equal(result.resultTag, 0, source);
    assert.equal(result.result, 0xfe04, source);
    assert.equal(result.output, "", source);
  }
});

Deno.test("M6 nested arithmetic preserves values and relocates distinct services", async () => {
  const nested = await compileM5(
    new TextEncoder().encode("(+ 10 (* 2 16))"),
    "nested.sk8",
  );
  assert.equal(nested.object.relocations.length, 5);
  const nestedResult = runCom(nested);
  assert.equal(nestedResult.resultTag, 3);
  assert.equal(nestedResult.result, 42);
  assert.equal(nestedResult.output, "42\r\n");
  assert.equal(nestedResult.sp, 0xf000);

  const branch = await run("(+ 1 (if #f (+ 32767 1) 41))");
  assert.equal(branch.result, 42);
  assert.equal(branch.output, "42\r\n");
});

Deno.test("M6 validates a dynamic unary arithmetic value", async () => {
  const result = await run("(+ (if #t #f 1))");
  assert.equal(result.output, "NUMERIC ERROR\r\n");
  assert.equal(result.resultTag, 0);
  assert.equal(result.sp, 0xf000);
});

Deno.test("M6 rejects malformed control forms and multiple top-level forms", async () => {
  for (
    const source of [
      "(if)",
      "(if #t)",
      "(if #t 1 2 3)",
      "(begin 1 2) 3",
      "(when #t 1)",
    ]
  ) {
    await assert.rejects(
      () => compileM5(new TextEncoder().encode(source), "invalid-m6.sk8"),
      (error: unknown) => error instanceof Error,
      `invalid source: ${source}`,
    );
  }
});
