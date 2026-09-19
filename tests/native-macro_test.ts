import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";

const m = await loadAssembly("tests/native-macro-machine.asm");
const { runtime, address } = m;
const memory = runtime.hardware.memory;
const cpu = runtime.cpu;

const put = (p: number, value: number) => {
  memory[p] = value & 255;
  memory[p + 1] = (value >>> 8) & 255;
};

const get = (p: number) => memory[p] | (memory[p + 1] << 8);

function call(name: string, hl = 0, bc = 0, de = 0, ix = 0x1357) {
  cpu.pc = address(name);
  cpu.sp = 0xf000;
  cpu.ix = ix;
  cpu.iy = 0x2468;
  cpu.h = (hl >>> 8) & 255;
  cpu.l = hl & 255;
  cpu.b = (bc >>> 8) & 255;
  cpu.c = bc & 255;
  cpu.d = (de >>> 8) & 255;
  cpu.e = de & 255;
  cpu.flags.C = 1;
  put(0xf000, 0xff00);
  let steps = 0;
  while (cpu.pc !== 0xff00) {
    assert(++steps < 3_000_000, `${name} did not return`);
    assert(!runtime.isHalted(), `${name} halted`);
    runtime.step();
  }
  assert.equal(cpu.sp, 0xf002, `${name} stack`);
  return { carry: cpu.flags.C, a: cpu.a, hl: cpu.h * 256 + cpu.l };
}

function table(context: number, kind: number, base: number, pool: number) {
  put(context, base);
  put(context + 2, 128);
  put(context + 4, pool);
  put(context + 6, 4096);
  memory[context + 12] = kind;
  assert.equal(call("IINIT", 0, 0, 0, context).carry, 0);
}

function init(
  source: string,
  arena = 0xa000,
  size = 0x2000,
  parse = true,
) {
  const bytes = new TextEncoder().encode(source);
  memory.set(bytes, 0x8000);
  put(address("NMSPTR"), 0x8000);
  put(address("NMSEND"), 0x8000 + bytes.length);
  table(0x6000, 0, 0x6100, 0x6400);
  table(0x600e, 1, 0x6800, 0x7000);
  assert.equal(
    call("RINIT", address("NMSOURCE"), 0x600e, 0x6000).carry,
    0,
  );
  assert.equal(call("NMINIT", arena, size).carry, 0);
  if (parse) {
    assert.equal(call("NMPARSE").carry, 0);
    assert.equal(call("NMREW").carry, 0);
  }
}

function events(source: string) {
  init(source);
  const result: Array<[number, number, number, number, number, number]> = [];
  for (;;) {
    const event = call("NMNEXT");
    assert.equal(event.carry, 0, source);
    if (event.a === 0) return result;
    result.push([
      event.a,
      Number(memory[address("RTAG")]),
      event.hl,
      memory[address("LTOKOFF")] | (memory[address("LTOKOFF") + 1] << 8),
      memory[address("LTOKLIN")] | (memory[address("LTOKLIN") + 1] << 8),
      memory[address("LTOKCOL")] | (memory[address("LTOKCOL") + 1] << 8),
    ]);
  }
}

Deno.test("native syntax arena round-trips nested structure and values", () => {
  const actual = events('\'(1 (2 . 3) "x") ()');
  assert.deepEqual(
    actual.map(([kind]) => kind),
    [3, 1, 7, 1, 7, 4, 7, 2, 8, 2, 1, 2],
  );
  assert.deepEqual(actual[2]?.slice(0, 3), [7, 3, 1]);
  assert.deepEqual(actual[6]?.slice(0, 3), [7, 3, 3]);
  assert.deepEqual(actual[1]?.slice(3), [1, 1, 2]);
  assert.deepEqual(actual[2]?.slice(3), [2, 1, 3]);
  assert.deepEqual(actual[6]?.slice(3), [9, 1, 10]);
});

Deno.test("native syntax arena restores symbols for the lowerer", () => {
  init("(+ 40 2)");
  const kinds: number[] = [];
  for (;;) {
    const event = call("NMNEXT");
    assert.equal(event.carry, 0);
    if (event.a === 0) break;
    kinds.push(event.a);
    if (event.a === 5) {
      const length = memory[address("LBUFLEN")];
      const text = String.fromCharCode(
        ...memory.slice(address("LBUFFER"), address("LBUFFER") + length),
      );
      assert.equal(text, "+");
      assert.equal(event.hl, 0x2000);
    }
  }
  assert.deepEqual(kinds, [1, 5, 7, 7, 2]);
});

Deno.test("native syntax arena rejects node exhaustion before publication", () => {
  const source = "(" + "1 ".repeat(40) + ")";
  init(source, 0xa000, 18 * 4 + 384, false);
  assert.equal(call("NMPARSE").carry, 1);
});

Deno.test("native nested expansion enforces its call-stack depth limit", () => {
  init("(+ 1 2)");
  const root = get(address("NMROOT"));
  memory[address("NMDDEP")] = 64;
  assert.equal(call("NMDEEP", root).carry, 1);
  assert.equal(memory[address("NMDDEP")], 64);
});

Deno.test("native matcher binds a pattern variable without changing the reader ABI", () => {
  init("((inc) (inc x) (inc 42))");
  const outer = get(address("NMROOT"));
  const literals = get(outer + 2);
  const pattern = get(literals + 4);
  const input = get(pattern + 4);
  assert.equal(call("NMSETLIT", literals).carry, 0);
  const matched = call("NMMATCH", pattern, 0, input);
  assert.equal(matched.carry, 0);
  assert.equal(memory[address("NMBINDN")], 1);
  const binding = address("NMBINDS");
  const value = get(binding + 2);
  const inputHead = get(input + 2);
  assert.equal(get(binding), get(get(get(pattern + 2) + 4) + 9));
  assert.equal(value, get(inputHead + 4));
});

Deno.test("native template cloning substitutes a binding and marks introduced syntax", () => {
  init("((inc) (inc x) (inc 42) (+ x 1))");
  const outer = get(address("NMROOT"));
  const literals = get(outer + 2);
  const pattern = get(literals + 4);
  const input = get(pattern + 4);
  const template = get(input + 4);
  assert.equal(call("NMSETLIT", literals).carry, 0);
  assert.equal(call("NMMATCH", pattern, 0, input).carry, 0);
  const expanded = call("NMEXPAND", template);
  assert.equal(expanded.carry, 0);
  assert.equal(memory[expanded.hl], 4);
  const head = get(expanded.hl + 2);
  const argument = get(head + 4);
  const one = get(argument + 4);
  assert.equal(memory[head], 1);
  assert.equal(get(head + 9), get(get(template + 2) + 9));
  assert.equal(memory[argument], 2);
  assert.equal(memory[argument + 8], 3);
  assert.equal(get(argument + 9), 42);
  assert.equal(memory[one], 2);
  assert.equal(get(one + 9), 1);
  assert.notEqual(memory[head + 17], 0);
  assert.equal(memory[argument + 17], memory[get(get(input + 2) + 4) + 17]);
});

Deno.test("native template cloning preserves a captured symbol's scope", () => {
  init("((id) (id x) (id foo) x)");
  const outer = get(address("NMROOT"));
  const literals = get(outer + 2);
  const pattern = get(literals + 4);
  const input = get(pattern + 4);
  const template = get(input + 4);
  const captured = get(get(input + 2) + 4);
  assert.equal(call("NMSETLIT", literals).carry, 0);
  assert.equal(call("NMMATCH", pattern, 0, input).carry, 0);
  const expanded = call("NMEXPAND", template);
  assert.equal(expanded.carry, 0);
  assert.equal(memory[expanded.hl], 1);
  assert.equal(get(expanded.hl + 9), get(captured + 9));
  assert.equal(memory[expanded.hl + 17], memory[captured + 17]);
});

Deno.test("native quote cloning preserves authored symbol scope", () => {
  init("((tag) (tag) (tag) 'hello)");
  const outer = get(address("NMROOT"));
  const literals = get(outer + 2);
  const pattern = get(literals + 4);
  const input = get(pattern + 4);
  const template = get(input + 4);
  const authored = get(template + 2);
  assert.equal(call("NMSETLIT", literals).carry, 0);
  assert.equal(call("NMMATCH", pattern, 0, input).carry, 0);
  const expanded = call("NMEXPAND", template);
  assert.equal(expanded.carry, 0);
  assert.equal(memory[expanded.hl], 5);
  const quoted = get(expanded.hl + 2);
  assert.equal(memory[quoted], 1);
  assert.equal(get(quoted + 9), get(authored + 9));
  assert.equal(memory[quoted + 17], memory[authored + 17]);
});

Deno.test("native generated let bindings avoid use-site capture", () => {
  init(
    "(define-syntax capture (syntax-rules () " +
      "((capture x) (let ((tmp 1)) x)))) (capture tmp)",
  );
  const definition = get(address("NMROOT"));
  const input = get(definition + 4);
  const inputArg = get(get(input + 2) + 4);
  assert.equal(call("NMDECL", definition).carry, 0);
  assert.equal(call("NMHMARK", input).carry, 0);
  const expanded = call("NMEXPMAC", input);
  assert.equal(expanded.carry, 0);

  const output = expanded.hl;
  const outputHead = get(output + 2);
  const bindingList = get(outputHead + 4);
  const binding = get(bindingList + 2);
  const generatedBinder = get(binding + 2);
  const body = get(bindingList + 4);
  assert.equal(get(generatedBinder + 9), get(inputArg + 9));
  assert.notEqual(memory[generatedBinder + 17], memory[inputArg + 17]);
  assert.equal(memory[body + 17], memory[inputArg + 17]);
  assert.equal(memory[outputHead + 17], 0);
});

Deno.test("native generated lambda references its fresh formal", () => {
  init(
    "(define-syntax make (syntax-rules () " +
      "((make) (lambda (tmp) tmp)))) (make)",
  );
  const definition = get(address("NMROOT"));
  const input = get(definition + 4);
  assert.equal(call("NMDECL", definition).carry, 0);
  assert.equal(call("NMHMARK", input).carry, 0);
  const expanded = call("NMEXPMAC", input);
  assert.equal(expanded.carry, 0);

  const outputHead = get(expanded.hl + 2);
  const formals = get(outputHead + 4);
  const formal = get(formals + 2);
  const body = get(formals + 4);
  assert.equal(memory[outputHead + 17], 0);
  assert.notEqual(memory[formal + 17], 0);
  assert.equal(memory[body + 17], memory[formal + 17]);
  assert.equal(get(body + 9), get(formal + 9));
});

Deno.test("native generated free references keep definition scope", () => {
  init(
    "(define-syntax call-helper (syntax-rules () " +
      "((call-helper x) (helper x)))) (call-helper 2)",
  );
  const definition = get(address("NMROOT"));
  const input = get(definition + 4);
  assert.equal(call("NMDECL", definition).carry, 0);
  assert.equal(call("NMHMARK", input).carry, 0);
  const expanded = call("NMEXPMAC", input);
  assert.equal(expanded.carry, 0);

  const outputHead = get(expanded.hl + 2);
  assert.equal(memory[outputHead], 1);
  assert.equal(memory[outputHead + 17], 0);
});

Deno.test("native failed expansion restores allocation state", () => {
  init("((inc) (inc x) (inc 42) (+ x 1))");
  const outer = get(address("NMROOT"));
  const literals = get(outer + 2);
  const pattern = get(literals + 4);
  const input = get(pattern + 4);
  const template = get(input + 4);
  assert.equal(call("NMSETLIT", literals).carry, 0);
  assert.equal(call("NMMATCH", pattern, 0, input).carry, 0);
  const cap = get(address("NMCAPPTR"));
  const beforePtr = cap - 18;
  const beforeCount = get(address("NMCOUNT"));
  const beforeScope = memory[address("NMSCOPE")];
  put(address("NMPTR"), beforePtr);
  const failed = call("NMEXPAND", template);
  assert.equal(failed.carry, 1);
  assert.equal(get(address("NMPTR")), beforePtr);
  assert.equal(get(address("NMCOUNT")), beforeCount);
  assert.equal(memory[address("NMSCOPE")], beforeScope);
  assert.equal(memory[address("NMBINDN")], 0);
});

Deno.test("native failed matches discard partial bindings", () => {
  init("((inc) (inc x 42) (inc 7 43))");
  const outer = get(address("NMROOT"));
  const literals = get(outer + 2);
  const pattern = get(literals + 4);
  const input = get(pattern + 4);
  assert.equal(call("NMSETLIT", literals).carry, 0);
  assert.equal(call("NMMATCH", pattern, 0, input).carry, 1);
  assert.equal(memory[address("NMBINDN")], 0);
});

Deno.test("native capture allocation rejects subtraction underflow", () => {
  init("()", 0xa000, 0x2000, false);
  put(address("NMCAPPTR"), 4);
  put(address("NMPTR"), 0);
  assert.equal(call("NMCAP").carry, 1);
  assert.equal(get(address("NMCAPPTR")), 4);
  put(address("NMCAPPTR"), 10);
  assert.equal(call("NMCAPREP").carry, 1);
  assert.equal(get(address("NMCAPPTR")), 10);
});

Deno.test("native macro registry preserves ordered clauses", () => {
  init("((inc) (inc x) (inc 42) (+ x 1))");
  const outer = get(address("NMROOT"));
  const literals = get(outer + 2);
  const name = get(literals + 2);
  const pattern = get(literals + 4);
  const input = get(pattern + 4);
  const template = get(input + 4);
  assert.equal(call("NMREG", name, template, pattern, literals).carry, 0);
  assert.equal(memory[address("NMMACN")], 1);
  const expanded = call("NMEXPMAC", input);
  assert.equal(expanded.carry, 0);
  assert.equal(expanded.a, 1);
  assert.equal(memory[expanded.hl], 4);
  assert.equal(get(get(get(expanded.hl + 2) + 4) + 9), 42);
  assert.equal(call("NMREG", name, template, pattern, literals).carry, 0);
  assert.equal(memory[address("NMMACN")], 2);
});

Deno.test("native macro registry tries the next clause after a mismatch", () => {
  init("((inc) (inc 42) (+ 1) (inc x) (+ x 2) (inc 7))");
  const outer = get(address("NMROOT"));
  const literals = get(outer + 2);
  const name = get(literals + 2);
  const firstPattern = get(literals + 4);
  const firstTemplate = get(firstPattern + 4);
  const secondPattern = get(firstTemplate + 4);
  const secondTemplate = get(secondPattern + 4);
  const input = get(secondTemplate + 4);
  assert.equal(
    call("NMREG", name, firstTemplate, firstPattern, literals).carry,
    0,
  );
  assert.equal(
    call("NMREG", name, secondTemplate, secondPattern, literals).carry,
    0,
  );
  const expanded = call("NMEXPMAC", input);
  assert.equal(expanded.carry, 0);
  assert.equal(expanded.a, 1);
  const head = get(expanded.hl + 2);
  const seven = get(head + 4);
  const two = get(seven + 4);
  assert.equal(get(seven + 9), 7);
  assert.equal(get(two + 9), 2);
});

Deno.test("native declaration reader registers define-syntax source", () => {
  init(
    "((define-syntax inc (syntax-rules () ((inc x) (+ x 1)))) (inc 42))",
  );
  const outer = get(address("NMROOT"));
  const definition = get(outer + 2);
  const input = get(definition + 4);
  const declared = call("NMDECL", definition);
  assert.equal(declared.carry, 0);
  assert.equal(declared.a, 1);
  const expanded = call("NMEXPMAC", input);
  assert.equal(expanded.carry, 0);
  assert.equal(expanded.a, 1);
  assert.equal(get(get(get(expanded.hl + 2) + 4) + 9), 42);
});

Deno.test("native declaration reader registers every syntax-rules clause", () => {
  init(
    "(define-syntax inc (syntax-rules () ((inc 42) (+ 1)) ((inc x) (+ x 2)))) (inc 7)",
  );
  const definition = get(address("NMROOT"));
  const input = get(definition + 4);
  const declared = call("NMDECL", definition);
  assert.equal(declared.carry, 0);
  assert.equal(declared.a, 1);
  assert.equal(memory[address("NMMACN")], 2);
  const expanded = call("NMEXPMAC", input);
  assert.equal(expanded.carry, 0);
  assert.equal(expanded.a, 1);
  const head = get(expanded.hl + 2);
  const seven = get(head + 4);
  const two = get(seven + 4);
  assert.equal(get(seven + 9), 7);
  assert.equal(get(two + 9), 2);
});

Deno.test("native declaration reader rejects malformed and duplicate definitions", () => {
  init("(define-syntax inc)");
  const malformed = get(address("NMROOT"));
  assert.equal(call("NMDECL", malformed).carry, 1);

  init(
    "(define-syntax inc (syntax-rules () ((inc x) (+ x 1)))) " +
      "(define-syntax inc (syntax-rules () ((inc x) (+ x 2))))",
  );
  const first = get(address("NMROOT"));
  const second = get(first + 4);
  assert.equal(call("NMDECL", first).carry, 0);
  assert.equal(call("NMDECL", second).carry, 1);
  assert.equal(memory[address("NMMACN")], 1);
});

Deno.test("native declaration reader rejects the macro table limit before output", () => {
  const definitions = Array.from(
    { length: 9 },
    (_, index) =>
      `(define-syntax m${index} (syntax-rules () ` +
      `((m${index} x) x)))`,
  ).join(" ");
  init(definitions);
  assert.equal(call("NMEXPALL").carry, 1);
  assert.equal(memory[address("NMMACN")], 8);
  assert.equal(get(address("NMOUTRT")), 0);
});

Deno.test("native macro expansion rejects the 65535-step rewrite limit", () => {
  init(
    "(define-syntax inc (syntax-rules () ((inc x) (+ x 1)))) (inc 41)",
  );
  const definition = get(address("NMROOT"));
  const input = get(definition + 4);
  assert.equal(call("NMDECL", definition).carry, 0);
  put(address("NMREWCT"), 0xffff);
  assert.equal(call("NMEXPMAC", input).carry, 1);
  assert.equal(get(address("NMREWCT")), 0xffff);
});

Deno.test("native trailing ellipses match and expand repeated values", () => {
  init(
    "(define-syntax sum (syntax-rules () ((sum x ...) (+ x ...)))) (sum 1 2 3)",
  );
  const definition = get(address("NMROOT"));
  const input = get(definition + 4);
  assert.equal(call("NMDECL", definition).carry, 0);
  const expanded = call("NMEXPMAC", input);
  assert.equal(expanded.carry, 0);
  assert.equal(expanded.a, 1);
  const head = get(expanded.hl + 2);
  const one = get(head + 4);
  const two = get(one + 4);
  const three = get(two + 4);
  assert.equal(get(one + 9), 1);
  assert.equal(get(two + 9), 2);
  assert.equal(get(three + 9), 3);
  assert.equal(get(three + 4), 0);

  init(
    "(define-syntax sum (syntax-rules () ((sum x ...) (+ x ...)))) (sum)",
  );
  const emptyDefinition = get(address("NMROOT"));
  const emptyInput = get(emptyDefinition + 4);
  assert.equal(call("NMDECL", emptyDefinition).carry, 0);
  const empty = call("NMEXPMAC", emptyInput);
  assert.equal(empty.carry, 0);
  assert.equal(empty.a, 1);
  const emptyHead = get(empty.hl + 2);
  assert.equal(get(emptyHead + 4), 0);

  init(
    "(define-syntax pack (syntax-rules () ((pack x ...) (list x ...)))) (pack (...) 1)",
  );
  const rawDefinition = get(address("NMROOT"));
  const rawInput = get(rawDefinition + 4);
  assert.equal(call("NMDECL", rawDefinition).carry, 0);
  const raw = call("NMEXPMAC", rawInput);
  assert.equal(raw.carry, 0);
  const rawHead = get(raw.hl + 2);
  const capturedList = get(rawHead + 4);
  assert.equal(memory[capturedList], 4);
  assert.notEqual(get(capturedList + 2), 0);
  assert.equal(get(get(capturedList + 2) + 4), 0);
  const rawOne = get(capturedList + 4);
  assert.equal(memory[rawOne], 2);
  assert.equal(get(rawOne + 9), 1);
});

Deno.test("native compound repetitions preserve each item binding", () => {
  init(
    "(define-syntax pairwise (syntax-rules () " +
      "((pairwise (x y) ...) (list (cons x y) ...)))) " +
      "(pairwise (1 2) (3 4))",
  );
  const definition = get(address("NMROOT"));
  const input = get(definition + 4);
  assert.equal(call("NMDECL", definition).carry, 0);
  const expanded = call("NMEXPMAC", input);
  assert.equal(expanded.carry, 0);
  assert.equal(expanded.a, 1);
  const listHead = get(expanded.hl + 2);
  const firstPair = get(listHead + 4);
  const secondPair = get(firstPair + 4);
  const firstCons = get(firstPair + 2);
  const firstValue = get(firstCons + 4);
  const secondValue = get(firstValue + 4);
  assert.equal(get(firstValue + 9), 1);
  assert.equal(get(secondValue + 9), 2);
  const secondCons = get(secondPair + 2);
  const thirdValue = get(secondCons + 4);
  const fourthValue = get(thirdValue + 4);
  assert.equal(get(thirdValue + 9), 3);
  assert.equal(get(fourthValue + 9), 4);
  assert.equal(get(secondPair + 4), 0);

  init(
    "(define-syntax pairwise (syntax-rules () " +
      "((pairwise (x y) ...) (list (cons x y) ...)))) " +
      "(pairwise)",
  );
  const emptyDefinition = get(address("NMROOT"));
  const emptyInput = get(emptyDefinition + 4);
  assert.equal(call("NMDECL", emptyDefinition).carry, 0);
  const empty = call("NMEXPMAC", emptyInput);
  assert.equal(empty.carry, 0);
  assert.equal(empty.a, 1);
  const emptyHead = get(empty.hl + 2);
  assert.notEqual(emptyHead, 0);
  assert.equal(get(emptyHead + 4), 0);
});

Deno.test("native nested repetitions preserve inner sequence shape", () => {
  init(
    "(define-syntax nested (syntax-rules () " +
      "((nested ((x ...) ...)) (list (list x ...) ...)))) " +
      "(nested ((1 2) () (3)))",
  );
  const definition = get(address("NMROOT"));
  const input = get(definition + 4);
  assert.equal(call("NMDECL", definition).carry, 0);
  const expanded = call("NMEXPMAC", input);
  assert.equal(expanded.carry, 0);
  assert.equal(expanded.a, 1);
  const output = expanded.hl;
  const head = get(output + 2);
  const first = get(head + 4);
  const second = get(first + 4);
  const third = get(second + 4);
  assert.equal(memory[first], 4);
  assert.equal(memory[second], 4);
  assert.equal(memory[third], 4);
  const firstHead = get(first + 2);
  const firstOne = get(firstHead + 4);
  const firstTwo = get(firstOne + 4);
  assert.equal(get(firstOne + 9), 1);
  assert.equal(get(firstTwo + 9), 2);
  assert.equal(get(firstTwo + 4), 0);
  const secondHead = get(second + 2);
  assert.equal(get(secondHead + 4), 0);
  const thirdHead = get(third + 2);
  const thirdValue = get(thirdHead + 4);
  assert.equal(get(thirdValue + 9), 3);
  assert.equal(get(thirdValue + 4), 0);
  assert.equal(get(third + 4), 0);

  init(
    "(define-syntax nested (syntax-rules () " +
      "((nested ((x ...) ...)) (list (list x ...) ...)))) " +
      "(nested ())",
  );
  const emptyDefinition = get(address("NMROOT"));
  const emptyInput = get(emptyDefinition + 4);
  assert.equal(call("NMDECL", emptyDefinition).carry, 0);
  const empty = call("NMEXPMAC", emptyInput);
  assert.equal(empty.carry, 0);
  assert.equal(empty.a, 1);
  const emptyHead = get(empty.hl + 2);
  assert.equal(memory[emptyHead], 1);
  assert.equal(get(emptyHead + 4), 0);
});

Deno.test("native template path rejects the published depth limit", () => {
  init("()", 0xa000, 0x2000, false);
  memory[address("NMPATHN")] = 8;
  put(address("NMREPIDX"), 0);
  assert.equal(call("NMPTHPSH").carry, 1);
  assert.equal(memory[address("NMPATHN")], 8);
});

Deno.test("native nested repetitions preserve three context levels", () => {
  init(
    "(define-syntax triple (syntax-rules () " +
      "((triple (((x ...) ...) ...)) " +
      "(list (list (list x ...) ...) ...)))) " +
      "(triple (((1 2) (3)) () ((4))))",
  );
  const definition = get(address("NMROOT"));
  const input = get(definition + 4);
  assert.equal(call("NMDECL", definition).carry, 0);
  const expanded = call("NMEXPMAC", input);
  assert.equal(expanded.carry, 0);
  assert.equal(expanded.a, 1);
  const outer = get(expanded.hl + 2);
  const first = get(outer + 4);
  const second = get(first + 4);
  const third = get(second + 4);
  assert.equal(get(third + 4), 0);
  const firstInner = get(first + 2);
  const firstInnerOne = get(firstInner + 4);
  const firstInnerTwo = get(firstInnerOne + 4);
  assert.equal(get(firstInnerTwo + 4), 0);
  const firstLeaf = get(firstInnerOne + 2);
  const firstValue = get(firstLeaf + 4);
  const secondLeaf = get(firstInnerTwo + 2);
  const secondValue = get(secondLeaf + 4);
  assert.equal(get(firstValue + 9), 1);
  assert.equal(get(get(firstValue + 4) + 9), 2);
  assert.equal(get(secondValue + 9), 3);
  const emptyHead = get(second + 2);
  assert.equal(get(emptyHead + 4), 0);
  const thirdHead = get(third + 2);
  const thirdInner = get(thirdHead + 4);
  const thirdInnerHead = get(thirdInner + 2);
  const thirdLeaf = get(thirdInnerHead + 4);
  assert.equal(get(thirdLeaf + 9), 4);
});

Deno.test("native nested repetitions keep descriptor partitions independent", () => {
  init(
    "(define-syntax grouped (syntax-rules () " +
      "((grouped ((x y) ...) ...) (list (list (list x y) ...) ...)))) " +
      "(grouped ((1 2) (3 4)) ((5 6)))",
  );
  const definition = get(address("NMROOT"));
  const input = get(definition + 4);
  assert.equal(call("NMDECL", definition).carry, 0);
  const expanded = call("NMEXPMAC", input);
  assert.equal(expanded.carry, 0);
  assert.equal(expanded.a, 1);
  const outer = get(expanded.hl + 2);
  const first = get(outer + 4);
  const second = get(first + 4);
  assert.notEqual(first, 0);
  assert.notEqual(second, 0);
  assert.equal(get(second + 4), 0);

  const firstHead = get(first + 2);
  const firstPair = get(firstHead + 4);
  const secondPair = get(firstPair + 4);
  assert.equal(get(secondPair + 4), 0);
  const firstPairHead = get(firstPair + 2);
  const firstPairOne = get(firstPairHead + 4);
  const firstPairTwo = get(firstPairOne + 4);
  assert.equal(get(firstPairOne + 9), 1);
  assert.equal(get(firstPairTwo + 9), 2);
  assert.equal(get(firstPairTwo + 4), 0);
  const secondPairHead = get(secondPair + 2);
  const secondPairOne = get(secondPairHead + 4);
  const secondPairTwo = get(secondPairOne + 4);
  assert.equal(get(secondPairOne + 9), 3);
  assert.equal(get(secondPairTwo + 9), 4);
  assert.equal(get(secondPairTwo + 4), 0);

  const secondHead = get(second + 2);
  const secondPairOnly = get(secondHead + 4);
  assert.equal(get(secondPairOnly + 4), 0);
  const secondPairOnlyHead = get(secondPairOnly + 2);
  const secondPairOnlyOne = get(secondPairOnlyHead + 4);
  const secondPairOnlyTwo = get(secondPairOnlyOne + 4);
  assert.equal(get(secondPairOnlyOne + 9), 5);
  assert.equal(get(secondPairOnlyTwo + 9), 6);
  assert.equal(get(secondPairOnlyTwo + 4), 0);
});

Deno.test("native dotted rest patterns capture remaining proper-list items", () => {
  init(
    "(define-syntax all (syntax-rules () ((all . args) (list . args)))) (all 1 2)",
  );
  const definition = get(address("NMROOT"));
  const input = get(definition + 4);
  assert.equal(call("NMDECL", definition).carry, 0);
  const expanded = call("NMEXPMAC", input);
  assert.equal(expanded.carry, 0);
  assert.equal(expanded.a, 1);
  const output = expanded.hl;
  const head = get(output + 2);
  assert.equal(memory[head], 1);
  const tail = get(output + 6);
  assert.notEqual(tail, 0);
  const first = get(tail + 2);
  const second = get(first + 4);
  assert.equal(get(first + 9), 1);
  assert.equal(get(second + 9), 2);
  assert.equal(get(second + 4), 0);

  init(
    "(define-syntax all (syntax-rules () ((all . args) (list . args)))) (all)",
  );
  const emptyDefinition = get(address("NMROOT"));
  const emptyInput = get(emptyDefinition + 4);
  assert.equal(call("NMDECL", emptyDefinition).carry, 0);
  const empty = call("NMEXPMAC", emptyInput);
  assert.equal(empty.carry, 0);
  const emptyTail = get(empty.hl + 6);
  assert.notEqual(emptyTail, 0);
  assert.equal(get(emptyTail + 2), 0);
});

Deno.test("native dotted template tails accept repeated bindings", () => {
  init(
    "(define-syntax tail (syntax-rules () " +
      "((tail x ... . rest) (list . x)))) (tail 1 2 . 3)",
  );
  const definition = get(address("NMROOT"));
  const input = get(definition + 4);
  assert.equal(call("NMDECL", definition).carry, 0);
  const expanded = call("NMEXPMAC", input);
  assert.equal(expanded.carry, 0);
  assert.equal(expanded.a, 1);
  const output = expanded.hl;
  assert.equal(memory[output], 4);
  assert.equal(memory[output + 1] & 1, 1);
  const head = get(output + 2);
  const tail = get(output + 6);
  assert.equal(memory[head], 1);
  assert.equal(memory[tail], 4);
  const first = get(tail + 2);
  const second = get(first + 4);
  assert.equal(get(first + 9), 1);
  assert.equal(get(second + 9), 2);
  assert.equal(get(second + 4), 0);

  init(
    "(define-syntax tail (syntax-rules () " +
      "((tail value ... . rest) (list . value)))) (tail 1 2)",
  );
  const properDefinition = get(address("NMROOT"));
  const properInput = get(properDefinition + 4);
  assert.equal(call("NMDECL", properDefinition).carry, 0);
  assert.equal(call("NMEXPMAC", properInput).carry, 1);
});

Deno.test("native macro state is reset between source packages", () => {
  init("((m) (m x) x)");
  const outer = get(address("NMROOT"));
  const literals = get(outer + 2);
  const name = get(literals + 2);
  const pattern = get(literals + 4);
  const template = get(pattern + 4);
  assert.equal(call("NMREG", name, template, pattern, literals).carry, 0);

  init("(m 1)");
  const root = get(address("NMROOT"));
  const result = call("NMEXPMAC", root);
  assert.equal(result.carry, 0);
  assert.equal(result.a, 0);
  assert.equal(result.hl, root);
  assert.equal(memory[address("NMMACN")], 0);
});

Deno.test("native top-level expansion removes declarations before traversal", () => {
  init(
    "(define-syntax inc (syntax-rules () ((inc x) (+ x 1)))) (inc 42)",
  );
  assert.equal(call("NMEXPALL").carry, 0);
  const output = get(address("NMOUTRT"));
  assert.notEqual(output, 0);
  assert.equal(call("NMOUTRW").carry, 0);
  const kinds: number[] = [];
  for (;;) {
    const event = call("NMNEXT");
    assert.equal(event.carry, 0);
    if (event.a === 0) break;
    kinds.push(event.a);
    if (event.a === 7 && kinds.length === 3) {
      assert.equal(event.hl, 42);
    }
  }
  assert.deepEqual(kinds, [1, 5, 7, 7, 2]);
});

Deno.test("native source scope marking resolves nested let bindings", () => {
  init("(let ((x 1) (z 2)) (let ((x x) (z z)) (+ x z)))");
  const root = get(address("NMROOT"));
  assert.equal(call("NMHMARK", root).carry, 0);
  const seen = new Set<number>();
  const symbols: Array<{ node: number; name: number; scope: number }> = [];
  const walk = (node: number): void => {
    if (node === 0 || seen.has(node)) return;
    seen.add(node);
    const kind = memory[node];
    if (kind === 1) {
      symbols.push({ node, name: get(node + 9), scope: memory[node + 17] });
    }
    walk(get(node + 2));
    if ((memory[node + 1] & 1) !== 0) walk(get(node + 6));
    walk(get(node + 4));
  };
  walk(root);
  const xName = symbols.find(({ scope }) => scope !== 0)?.name;
  assert.notEqual(xName, undefined);
  const xScopes = symbols
    .filter(({ name }) => name === xName)
    .map(({ scope }) => scope);
  const zName = symbols.find(({ name, scope }) => name !== xName && scope !== 0)
    ?.name;
  assert.notEqual(zName, undefined);
  const zScopes = symbols
    .filter(({ name }) => name === zName)
    .map(({ scope }) => scope);
  assert.equal(xScopes.length, 4);
  assert.equal(zScopes.length, 4);
  assert.notEqual(xScopes[0], 0);
  assert.notEqual(xScopes[1], 0);
  assert.notEqual(xScopes[0], xScopes[1]);
  assert.equal(xScopes[2], xScopes[0]);
  assert.equal(xScopes[3], xScopes[1]);
  assert.notEqual(zScopes[0], 0);
  assert.notEqual(zScopes[1], 0);
  assert.notEqual(zScopes[0], zScopes[1]);
  assert.equal(zScopes[2], zScopes[0]);
  assert.equal(zScopes[3], zScopes[1]);
  assert.notEqual(xScopes[0], zScopes[0]);
});

Deno.test("native macro lookup respects a locally shadowed transformer", () => {
  init(
    "((define-syntax inc (syntax-rules () ((inc x) (+ x 1)))) " +
      "(let ((inc 7)) (inc 2)))",
  );
  const outer = get(address("NMROOT"));
  const definition = get(outer + 2);
  const input = get(definition + 4);
  assert.equal(call("NMDECL", definition).carry, 0);
  assert.equal(call("NMHMARK", input).carry, 0);

  const name = get(get(definition + 2) + 4);
  const namePayload = get(name + 9);
  const calls: number[] = [];
  const seen = new Set<number>();
  const walk = (node: number): void => {
    if (node === 0 || seen.has(node)) return;
    seen.add(node);
    if (memory[node] === 4) {
      const head = get(node + 2);
      if (head !== 0 && memory[head] === 1 && get(head + 9) === namePayload) {
        calls.push(node);
      }
    }
    walk(get(node + 2));
    if ((memory[node + 1] & 1) !== 0) walk(get(node + 6));
    walk(get(node + 4));
  };
  walk(input);
  assert.equal(calls.length, 2);
  for (const candidate of calls) {
    const selected = call("NMLOOKM", candidate);
    assert.equal(selected.carry, 0);
    assert.equal(selected.a, 0);
  }
});

Deno.test("native source scopes keep lambda bindings out of quoted data", () => {
  init("(lambda (x) (let ((y x)) '(x) (+ x y)))");
  const root = get(address("NMROOT"));
  assert.equal(call("NMHMARK", root).carry, 0);
  const seen = new Set<number>();
  const symbols: Array<
    { node: number; kind: number; name: number; scope: number }
  > = [];
  const walk = (node: number): void => {
    if (node === 0 || seen.has(node)) return;
    seen.add(node);
    if (memory[node] === 1) {
      symbols.push({
        node,
        kind: memory[node],
        name: get(node + 9),
        scope: memory[node + 17],
      });
    }
    walk(get(node + 2));
    if ((memory[node + 1] & 1) !== 0) walk(get(node + 6));
    walk(get(node + 4));
  };
  walk(root);
  const xName = symbols[1]?.name;
  const yName = symbols[3]?.name;
  assert.notEqual(xName, undefined);
  assert.notEqual(yName, undefined);
  const xScopes = symbols.filter(({ name }) => name === xName).map((
    { scope },
  ) => scope);
  const yScopes = symbols.filter(({ name }) => name === yName).map((
    { scope },
  ) => scope);
  assert.deepEqual(xScopes, [1, 1, 0, 1]);
  assert.deepEqual(yScopes, [2, 2]);
});

Deno.test("native named let binds its recursive name and parameters", () => {
  init("(let loop ((x 1)) (loop x))");
  const root = get(address("NMROOT"));
  assert.equal(call("NMHMARK", root).carry, 0);
  const seen = new Set<number>();
  const symbols: Array<{ name: number; scope: number }> = [];
  const walk = (node: number): void => {
    if (node === 0 || seen.has(node)) return;
    seen.add(node);
    if (memory[node] === 1) {
      symbols.push({ name: get(node + 9), scope: memory[node + 17] });
    }
    walk(get(node + 2));
    if ((memory[node + 1] & 1) !== 0) walk(get(node + 6));
    walk(get(node + 4));
  };
  walk(root);
  const loopName = symbols[1]?.name;
  const xName = symbols[2]?.name;
  assert.notEqual(loopName, undefined);
  assert.notEqual(xName, undefined);
  assert.deepEqual(
    symbols.filter(({ name }) => name === loopName).map(({ scope }) => scope),
    [1, 1],
  );
  assert.deepEqual(
    symbols.filter(({ name }) => name === xName).map(({ scope }) => scope),
    [2, 2],
  );
});

Deno.test("native named let keeps its name out of initializers", () => {
  init("(let loop ((x loop)) (loop x))");
  const root = get(address("NMROOT"));
  assert.equal(call("NMHMARK", root).carry, 0);
  const seen = new Set<number>();
  const symbols: Array<{ name: number; scope: number }> = [];
  const walk = (node: number): void => {
    if (node === 0 || seen.has(node)) return;
    seen.add(node);
    if (memory[node] === 1) {
      symbols.push({ name: get(node + 9), scope: memory[node + 17] });
    }
    walk(get(node + 2));
    if ((memory[node + 1] & 1) !== 0) walk(get(node + 6));
    walk(get(node + 4));
  };
  walk(root);
  const loopName = symbols[1]?.name;
  assert.notEqual(loopName, undefined);
  const loopScopes = symbols.filter(({ name }) => name === loopName).map((
    { scope },
  ) => scope);
  assert.equal(loopScopes.length, 3);
  assert.equal(loopScopes[1], 0);
  assert.notEqual(loopScopes[0], 0);
  assert.equal(loopScopes[2], loopScopes[0]);
});
