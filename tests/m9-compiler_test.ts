import assert from "node:assert/strict";
import { createZ80Runtime } from "@jhlagado/debug80-runtime";
import { compileM9, type M9CompileResult } from "../tools/m7-compiler.ts";

function runCom(compiled: M9CompileResult) {
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
  let runtimeErrorCode: number | null = null;
  let steps = 0;
  while (cpu.pc !== 0xff00) {
    assert.ok(
      ++steps <= 1_000_000,
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
    sp: returnedSp,
    stackTop: compiled.stackTopAddress,
  };
}

async function run(source: string, heapCells = 512) {
  const compiled = await compileM9(
    new TextEncoder().encode(source),
    "m9.sk8",
    { heapCells },
  );
  return runCom(compiled);
}

Deno.test("M9 builds ordinary pairs and proper lists", async () => {
  const result = await run(
    "(+ (car (list 40 1)) (car (cdr (list 1 2 3))))",
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
  assert.equal(result.sp, result.stackTop);
});

Deno.test("M9 cons stores a numeric CDR in an escaped pair", async () => {
  const result = await run("(cdr (cons 1 42))");
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
});

Deno.test("M9 ordinary list links can point to escaped-pair anchors", async () => {
  const result = await run(
    "((lambda (pairs) (+ (car (cdr pairs)) (cdr (cdr pairs)))) " +
      "(cons 1 (cons 2 40)))",
    10,
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
});

Deno.test("M9 initializes quoted dotted pairs once and retains their root", async () => {
  const result = await run("(+ (car '(40 . 2)) (cdr '(1 . 0)))");
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 40);
  assert.equal(result.output, "40\r\n");
});

Deno.test("M9 pair and identity predicates use tagged-value identity", async () => {
  const pairs = await run(
    "(if (pair? (cons 1 2)) (if (eq? 'skate 'skate) 42 0) 0)",
  );
  assert.equal(pairs.resultTag, 3);
  assert.equal(pairs.result, 42);
  assert.equal(pairs.output, "42\r\n");

  const nullValue = await run("(if (null? '()) 42 0)");
  assert.equal(nullValue.result, 42);

  const notPair = await run("(if (pair? 5) 0 42)");
  assert.equal(notPair.result, 42);

  const notNull = await run("(if (null? 0) 0 42)");
  assert.equal(notNull.result, 42);

  const strings = await run('(if (eq? "same" "same") 42 0)');
  assert.equal(strings.result, 42);

  const nestedQuote = await run("(if (eq? (car ''name) 'quote) 42 0)");
  assert.equal(nestedQuote.result, 42);

  const shadowedCar = await run(
    "((lambda (car) (car 42)) (lambda (value) value))",
  );
  assert.equal(shadowedCar.result, 42);
});

Deno.test("M9 rejects car on a nonpair and statically rejects wrong arity", async () => {
  const result = await run("(car 1)");
  assert.equal(result.output, "RUNTIME ERROR\r\n");
  assert.equal(result.runtimeErrorCode, 1);
  await assert.rejects(
    compileM9(new TextEncoder().encode("(car)")),
    /car requires exactly 1 argument/,
  );
});

Deno.test("M9 collection preserves quoted roots while reclaiming temporary pairs", async () => {
  const garbage = Array.from(
    { length: 12 },
    (_, index) => `(cons ${index} ${index + 1})`,
  ).join(" ");
  const result = await run(`(begin ${garbage} (+ (car '(40 . 2)) 2))`, 10);
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
  assert.equal(result.sp, result.stackTop);
});

Deno.test("P4 binds fixed and surplus dotted arguments in order", async () => {
  const fixedAndRest = await run(
    "((lambda (first . rest) (+ first (car rest))) 40 2)",
  );
  assert.equal(fixedAndRest.resultTag, 3);
  assert.equal(fixedAndRest.result, 42);
  assert.equal(fixedAndRest.output, "42\r\n");

  const allRest = await run(
    "((lambda args (+ (car args) (car (cdr args)))) 40 2)",
  );
  assert.equal(allRest.resultTag, 3);
  assert.equal(allRest.result, 42);
  assert.equal(allRest.output, "42\r\n");

  const emptyRest = await run(
    "((lambda (first . rest) (if (null? rest) first 0)) 42)",
  );
  assert.equal(emptyRest.resultTag, 3);
  assert.equal(emptyRest.result, 42);
  assert.equal(emptyRest.output, "42\r\n");
});

Deno.test("P4 reports too few arguments for a dotted procedure", async () => {
  const result = await run("((lambda (first second . rest) first) 1)");
  assert.equal(result.output, "RUNTIME ERROR\r\n");
  assert.equal(result.runtimeErrorCode, 2);
});

Deno.test("P4 keeps a captured environment rooted while building a rest list", async () => {
  const result = await run(
    "(((lambda (captured) (lambda args captured)) 42) 1 2 3 4 5 6)",
    12,
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
});

Deno.test("P4 keeps the captured environment rooted through a tail rest call", async () => {
  const result = await run(
    "((lambda (invoke) (invoke 1 2 3 4 5 6)) " +
      "((lambda (captured) (lambda args captured)) 42))",
    12,
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
});
