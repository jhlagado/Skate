import assert from "node:assert/strict";
import { createZ80Runtime } from "@jhlagado/debug80-runtime";
import { compileM10, type M10CompileResult } from "../tools/m7-compiler.ts";
import { toNumber } from "../tools/binary16-reference.ts";

interface RunOptions {
  readonly input?: readonly number[];
  readonly maxSteps?: number;
  readonly heapCells?: number;
}

interface RunResult {
  readonly output: string;
  readonly resultTag: number;
  readonly result: number;
  readonly runtimeErrorCode: number | null;
  readonly steps: number;
  readonly returnedSp: number;
  readonly stackTop: number;
}

function runCom(
  compiled: M10CompileResult,
  options: RunOptions = {},
): RunResult {
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
  const input = [...(options.input ?? [])];
  const output: string[] = [];
  let runtimeErrorCode: number | null = null;
  let returnedSp = 0;
  let steps = 0;
  const maxSteps = options.maxSteps ?? 1_000_000;
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
    if (cpu.c === 1) {
      cpu.a = input.shift() ?? 26;
    } else if (cpu.c === 2) {
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
    steps,
    returnedSp,
    stackTop: compiled.stackTopAddress,
  };
}

async function runFile(
  file: string,
  options: RunOptions = {},
): Promise<RunResult> {
  const sourceUrl = new URL(`../examples/${file}`, import.meta.url);
  const source = await Deno.readFile(sourceUrl);
  const compiled = await compileM10(source, file, {
    heapCells: options.heapCells,
  });
  return runCom(compiled, options);
}

async function runSource(
  source: string,
  options: RunOptions = {},
): Promise<RunResult> {
  const compiled = await compileM10(
    new TextEncoder().encode(source),
    "m12.sk8",
    { heapCells: options.heapCells },
  );
  return runCom(compiled, options);
}

Deno.test("M12 make-adder retains its captured binding", async () => {
  const result = await runFile("make-adder.sk8");
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 12);
  assert.equal(result.output, "12\r\n");
  assert.equal(result.returnedSp, result.stackTop);
});

Deno.test("M8 capture-free closure loops stay bounded and fresh", async () => {
  const result = await runSource(
    "((lambda () " +
      "(define make (lambda () " +
      "(lambda () " +
      "(define count 0) " +
      "(set! count (+ count 1)) " +
      "count))) " +
      "(define apply-two (lambda (left right) (+ (left) (right)))) " +
      "(define loop (lambda (remaining) " +
      "(if (= remaining 1) " +
      "(apply-two (make) (make)) " +
      "(begin (apply-two (make) (make)) " +
      "(loop (- remaining 1)))))) " +
      "(loop 64)))",
    // Full operand validation makes each numeric step deliberately more
    // expensive; keep enough headroom for the same bounded 64-iteration run.
    { heapCells: 80, maxSteps: 1_200_000 },
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 2);
  assert.equal(result.output, "2\r\n");
  assert.equal(result.returnedSp, result.stackTop);
});

Deno.test("M12 evaluates the same capture-free lambda twice as fresh closures", async () => {
  const result = await runSource(
    "((lambda (make) (if (eq? (make) (make)) 0 1)) " +
      "(lambda () (lambda () 1)))",
  );
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 1);
  assert.equal(result.output, "1\r\n");
  assert.equal(result.returnedSp, result.stackTop);
});

Deno.test("M12 bounded higher-order sums pass procedures through calls", async () => {
  const result = await runFile("higher-order-sum.sk8");
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 55);
  assert.equal(result.output, "55\r\n");
});

Deno.test("M12 closures share one mutable counter binding", async () => {
  const result = await runFile("shared-counter.sk8");
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 2);
  assert.equal(result.output, "2\r\n");
});

Deno.test("M12 rational and proper/improper list examples run", async () => {
  const rational = await runFile("rational.sk8");
  assert.equal(rational.resultTag, 3);
  assert.equal(rational.result, 3);
  assert.equal(rational.output, "3\r\n");

  const lists = await runFile("lists.sk8");
  assert.equal(lists.resultTag, 3);
  assert.equal(lists.result, 84);
  assert.equal(lists.output, "84\r\n");
});

Deno.test("M12 mutual tail calls count exactly 30000 with an exact integer", async () => {
  const result = await runFile("mutual-tail.sk8", {
    maxSteps: 120_000_000,
  });
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 42);
  assert.equal(result.output, "42\r\n");
  assert.equal(result.returnedSp, result.stackTop);
});

Deno.test("M12 reports exact overflow at the signed integer boundary", async () => {
  const result = await runSource("(+ 32767 1)");
  assert.equal(result.output, "RUNTIME ERROR\r\n");
  assert.equal(result.runtimeErrorCode, 6);
});

Deno.test("M12 root finding states a binary16 tolerance and terminates", async () => {
  const result = await runFile("root.sk8");
  assert.equal(result.resultTag, 0);
  const approximation = toNumber(result.result);
  assert.ok(Math.abs(approximation - Math.SQRT2) <= 1 / 256);
  assert.equal(result.output, "");
});

Deno.test("M12 predicate and console primitives use the value ABI", async () => {
  const predicates = await runSource(
    "(and (not #f) (number? 1) (boolean? #t) (symbol? 'x) " +
      '(procedure? (lambda () 1)) (string? "x") (char? #\\A))',
  );
  assert.equal(predicates.resultTag, 0);
  assert.equal(predicates.result, 0xfe01);

  const consoleResult = await runSource(
    "(begin (display -42) (newline) (char? (read-char)))",
    { input: [65] },
  );
  assert.equal(consoleResult.resultTag, 0);
  assert.equal(consoleResult.result, 0xfe01);
  assert.equal(consoleResult.output, "-42\r\n");

  const eofResult = await runSource(
    "(eof-object? (read-char))",
    { input: [26] },
  );
  assert.equal(eofResult.resultTag, 0);
  assert.equal(eofResult.result, 0xfe01);
});

Deno.test("M12 treats primitive values as procedures", async () => {
  const result = await runSource("(procedure? +)");
  assert.equal(result.resultTag, 0);
  assert.equal(result.result, 0xfe01);
});

Deno.test("M12 prints zero and preserves write character syntax", async () => {
  const finalZero = await runSource("0");
  assert.equal(finalZero.output, "0\r\n");

  const zero = await runSource("(begin (display 0) (newline))");
  assert.equal(zero.output, "0\r\n");

  const character = await runSource("(begin (write #\\A) (newline))");
  assert.equal(character.output, "#\\A\r\n");
});

Deno.test("M12 enforces zero-argument console procedure arity", async () => {
  const newline = await runSource("(newline 123)");
  assert.equal(newline.runtimeErrorCode, 2);
  assert.equal(newline.output, "RUNTIME ERROR\r\n");

  const readChar = await runSource("(read-char 123)", { input: [65] });
  assert.equal(readChar.runtimeErrorCode, 2);
  assert.equal(readChar.output, "RUNTIME ERROR\r\n");
});

Deno.test("M12 validates every arithmetic operand before folding", async () => {
  const result = await runSource("(+ 32767 1 #f)");
  assert.equal(result.runtimeErrorCode, 1);
  assert.equal(result.output, "RUNTIME ERROR\r\n");
});

Deno.test("M12 keeps floating signed zero distinct from exact zero", async () => {
  const result = await runSource("(if (eq? -0.0 0.0) 0 1)");
  assert.equal(result.resultTag, 3);
  assert.equal(result.result, 1);
  assert.equal(result.output, "1\r\n");
});

Deno.test("M12 cond without a matching clause does not print an integer", async () => {
  const result = await runSource("(cond (#f 1))");
  assert.equal(result.resultTag, 0);
  assert.equal(result.result, 0xfe04);
  assert.equal(result.output, "");
  assert.equal(result.returnedSp, result.stackTop);
});
