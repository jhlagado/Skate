import assert from "node:assert/strict";
import { createZ80Runtime } from "@jhlagado/debug80-runtime";
import { compileM10, type M10CompileResult } from "../tools/m7-compiler.ts";
import { expandSyntaxRules } from "../tools/syntax-rules.ts";

function runCom(compiled: M10CompileResult, maxSteps = 1_000_000) {
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
  let runtimeErrorCode: number | null = null;
  let returnedSp = 0;
  let steps = 0;
  while (cpu.pc !== 0xff00) {
    assert.ok(
      ++steps <= maxSteps,
      `COM did not terminate through CP/M BDOS: PC=$${cpu.pc.toString(16)} ` +
        `SP=$${cpu.sp.toString(16)}`,
    );
    assert.ok(!machine.isHalted(), "COM halted instead of returning to CP/M");
    if (cpu.pc === compiled.runtimeErrorAddress) runtimeErrorCode = cpu.a;
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
    runtimeErrorCode,
    returnedSp,
    stackTop: compiled.stackTopAddress,
  };
}

async function run(
  source: string,
  heapCells = 512,
  maxSteps = 1_000_000,
) {
  const compiled = await compileM10(
    new TextEncoder().encode(source),
    "m10.sk8",
    { heapCells },
  );
  return runCom(compiled, maxSteps);
}

Deno.test("M10 evaluates multiple top-level forms and function definitions", async () => {
  const result = await run(
    "(define (inc value) (+ value 1)) (define answer (inc 41)) answer",
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
  assert.equal(result.returnedSp, result.stackTop);
});

Deno.test("M10 resolves a global through a closure defined before that global", async () => {
  const result = await run(
    "(define get (lambda () answer)) (define answer 42) (get)",
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
});

Deno.test("M10 traps a forward global read before its definition runs", async () => {
  const result = await run(
    "(define get (lambda () answer)) (get) (define answer 42)",
  );
  assert.equal(result.output, "RUNTIME ERROR\r\n");
  assert.equal(result.runtimeErrorCode, 5);
});

Deno.test("M10 updates globals with set! and permits primitive reassignment", async () => {
  const result = await run(
    "(define value 1) (set! value 41) " +
      "(define + (lambda (left right) (- left right))) (+ 5 3)",
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 2);
  assert.equal(result.output, "2\r\n");
});

Deno.test("M10 reassigns a procedure global and keeps the call indirect", async () => {
  const result = await run(
    "(define f (lambda (value) (+ value 1))) " +
      "(set! f (lambda (value) (- value 1))) (f 42)",
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 41);
  assert.equal(result.output, "41\r\n");
});

Deno.test("M10 derived let, cond, and/or forms preserve Scheme truth", async () => {
  const letResult = await run("(let ((left 40) (right 2)) (+ left right))");
  assert.equal(letResult.result, 42);

  const condResult = await run(
    "(cond ((= 1 2) 0) ((= 2 2) 42) (else 7))",
  );
  assert.equal(condResult.result, 42);

  const andResult = await run("(and #t 1 2)");
  assert.equal(andResult.resultTag, 3);
  assert.equal(andResult.result, 2);

  const shortCircuit = await run("(and #f (+ 32767 1))");
  assert.equal(shortCircuit.resultTag, 0);
  assert.equal(shortCircuit.result, 0xfe00);

  const orResult = await run("(or #f 42)");
  assert.equal(orResult.resultTag, 3);
  assert.equal(orResult.result, 42);

  const orShortCircuit = await run("(or 42 (+ 32767 1))");
  assert.equal(orShortCircuit.resultTag, 3);
  assert.equal(orShortCircuit.result, 42);
});

Deno.test("P5 apply invokes fixed, rest and empty-argument procedures", async () => {
  const result = await run(
    "(define fixed (lambda (left right) (+ left right))) " +
      "(define rest (lambda (first . more) (+ first (car more)))) " +
      "(define empty (lambda () 40)) " +
      "(+ (apply fixed (list 40 2)) " +
      "   (apply rest (list 1 2 3)) " +
      "   (apply empty '()))",
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 85);
  assert.equal(result.output, "85\r\n");
  assert.equal(result.returnedSp, result.stackTop);
});

Deno.test("P5 apply preserves tail position and rejects improper lists", async () => {
  const tail = await run(
    "(define step (lambda (n) " +
      "(if (= n 50) n (apply step (list (+ n 1)))))) " +
      "(step 0)",
  );
  assert.equal(tail.resultTag, 3);
  assert.equal(tail.result, 50);
  assert.equal(tail.returnedSp, tail.stackTop);

  const wrongArity = await run(
    "(apply (lambda () 1) '() '())",
  );
  assert.equal(wrongArity.output, "RUNTIME ERROR\r\n");
  assert.equal(wrongArity.runtimeErrorCode, 2);

  const improper = await run(
    "((lambda (procedure) " +
      "(apply procedure (cons 1 2))) (lambda (value) value))",
  );
  assert.equal(improper.output, "RUNTIME ERROR\r\n");
  assert.equal(improper.runtimeErrorCode, 1);

  const excessive = await run(
    "(define make (lambda (n values) " +
      "(if (= n 0) values " +
      "(make (- n 1) (cons n values))))) " +
      "(define identity (lambda values values)) " +
      "(apply identity (make 511 '()))",
    1024,
    10_000_000,
  );
  assert.equal(excessive.output, "RUNTIME ERROR\r\n");
  assert.equal(excessive.runtimeErrorCode, 3);
});

Deno.test("P6 syntax-rules expands hygienic, repeated and defining macros", async () => {
  const source = "(define-syntax when " +
    "(syntax-rules () ((_ test body ...) " +
    "(if test (begin body ...))))) " +
    "(define-syntax sum " +
    "(syntax-rules () ((_ value ...) (+ value ...)))) " +
    "(define-syntax capture " +
    "(syntax-rules () ((_ value) (let ((tmp 1)) value)))) " +
    "(define-syntax define-constant " +
    "(syntax-rules () ((_ name value) (define name value)))) " +
    "(define-constant answer (sum 1 2 3)) " +
    "(when (= answer 6) (display answer) (newline)) " +
    "(let ((tmp 40)) (+ (capture tmp) answer))";
  const sourceBytes = new TextEncoder().encode(source);
  const compiled = await compileM10(sourceBytes, "macro.sk8");
  const expanded = expandSyntaxRules(sourceBytes, "macro.sk8");
  const direct = await compileM10(expanded.bytes, "expanded.sk8");
  assert.deepEqual(compiled.objectBytes, direct.objectBytes);
  assert.deepEqual(compiled.comBytes, direct.comBytes);
  const result = runCom(compiled);
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 46);
  assert.equal(result.output, "6\r\n46\r\n");
  assert.equal(result.returnedSp, result.stackTop);
});

Deno.test("M10 rejects unbound names and malformed top-level definitions", async () => {
  await assert.rejects(
    compileM10(new TextEncoder().encode("unknown")),
    /Unbound identifier "unknown"/,
  );
  await assert.rejects(
    compileM10(new TextEncoder().encode("(define value)")),
    /Expected definition initializer/,
  );
  await assert.rejects(
    compileM10(new TextEncoder().encode("(define (f x x) x)")),
    /Duplicate parameter/,
  );
});
