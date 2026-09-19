import assert from "node:assert/strict";
import { createZ80Runtime } from "@jhlagado/debug80-runtime";
import { compileM8, type M8CompileResult } from "../tools/m7-compiler.ts";

function runCom(compiled: M8CompileResult) {
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
  return {
    output: output.join(""),
    resultTag: machineMemory[compiled.resultTagAddress]!,
    result: machineMemory[compiled.resultAddress]! |
      (machineMemory[compiled.resultAddress + 1]! << 8),
    sp: returnedSp,
    stackTop: compiled.stackTopAddress,
  };
}

async function run(source: string, heapCells = 512) {
  const compiled = await compileM8(
    new TextEncoder().encode(source),
    "m8.sk8",
    { heapCells },
  );
  return runCom(compiled);
}

Deno.test("M8 closures keep an escaped lexical environment alive", async () => {
  const result = await run("(((lambda (x) (lambda () x)) 42))");
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
  assert.equal(result.sp, result.stackTop);
});

Deno.test("M8 propagates capture needs through an intervening lambda", async () => {
  const result = await run("((((lambda (x) (lambda () (lambda () x))) 42)))");
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
});

Deno.test("M8 sibling closures share a mutable binding", async () => {
  const result = await run(
    "((lambda (x) " +
      "(define get (lambda () x)) " +
      "(define put (lambda (value) (set! x value))) " +
      "(begin (put 41) (+ (get) 1))) 0)",
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
  assert.equal(result.sp, result.stackTop);
});

Deno.test("M8 closures can refer to a later internal definition", async () => {
  const result = await run(
    "((lambda () " +
      "(define get (lambda () later)) " +
      "(define later 42) " +
      "(get)))",
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
});

Deno.test("M8 internal definitions shadow outer lexical bindings", async () => {
  const result = await run(
    "((lambda (x) ((lambda () (define x 42) x))) 1)",
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
});

Deno.test("M8 mutually referring internal procedures run with a small heap", async () => {
  const result = await run(
    "((lambda () " +
      "(define even (lambda (flag) (if flag (odd #f) 42))) " +
      "(define odd (lambda (flag) (if flag 0 (even #f)))) " +
      "(even #t)))",
    32,
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
});

Deno.test("M8 collects temporary closures while preserving a live captured closure", async () => {
  const ephemeralClosures = Array.from(
    { length: 12 },
    () => "(lambda () x)",
  ).join(" ");
  const result = await run(
    `((lambda (x) (define get (lambda () x)) (begin ${ephemeralClosures} (get))) 42)`,
    10,
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
  assert.equal(result.sp, result.stackTop);
});

Deno.test("M8 keeps repeated fresh capture-free closures bounded", async () => {
  const repeatedCalls = Array.from(
    { length: 16 },
    () => "(apply-two (make) (make))",
  ).join(" ");
  const result = await run(
    "((lambda () " +
      "(define make (lambda () " +
      "(lambda () " +
      "(define count 0) " +
      "(set! count (+ count 1)) " +
      "count))) " +
      "(define apply-two (lambda (left right) (+ (left) (right)))) " +
      `(begin ${repeatedCalls} 2)))`,
    16,
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 2);
  assert.equal(result.output, "2\r\n");
  assert.equal(result.sp, result.stackTop);
});

Deno.test("M8 traps reads of an internal definition before initialization", async () => {
  const result = await run(
    "((lambda () " +
      "(define first (lambda () later)) " +
      "(define result (first)) " +
      "(define later 42) " +
      "result))",
  );
  assert.equal(result.output, "RUNTIME ERROR\r\n");
});

Deno.test("M8 rejects assignment to an internal definition before initialization", async () => {
  const result = await run(
    "((lambda () (define value (begin (set! value 1) 0)) value))",
  );
  assert.equal(result.output, "RUNTIME ERROR\r\n");
});

Deno.test("M8 rejects late and duplicate internal definitions", async () => {
  await assert.rejects(
    compileM8(new TextEncoder().encode("((lambda () 1 (define x 2) x))")),
    /Internal definitions must precede body expressions/,
  );
  await assert.rejects(
    compileM8(
      new TextEncoder().encode("((lambda (x) (define x 1) x) 0)"),
    ),
    /Duplicate parameter or definition/,
  );
});
