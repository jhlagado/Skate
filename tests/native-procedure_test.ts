import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";

const m = await loadAssembly("tests/native-procedure-machine.asm");
const { runtime, address } = m;
const memory = runtime.hardware.memory;
const cpu = runtime.cpu;
// Keep fixture-owned tables above the compiler image.  The native compiler is
// deliberately allowed to grow through the low 0x6000s; placing a test pool at
// 0x6400 would eventually overwrite linked runtime code.
const SYMBOL_CONTEXT = 0xa000;
const STRING_CONTEXT = 0xa00e;
const SYMBOL_TABLE = 0xa100;
const STRING_TABLE = 0xa200;
const SYMBOL_POOL = 0xa400;
const STRING_POOL = 0xa800;
const put = (p: number, value: number) => {
  memory[p] = value & 255;
  memory[p + 1] = value >>> 8;
};
function call(
  name: string,
  hl = 0,
  bc = 0,
  de = 0,
  ix = 0x1357,
  maxSteps = 10_000_000,
) {
  cpu.pc = address(name);
  cpu.sp = 0xf000;
  cpu.ix = ix;
  cpu.iy = 0x2468;
  cpu.h = hl >>> 8;
  cpu.l = hl & 255;
  cpu.b = bc >>> 8;
  cpu.c = bc & 255;
  cpu.d = de >>> 8;
  cpu.e = de & 255;
  cpu.flags.C = 1;
  put(0xf000, 0xff00);
  let steps = 0;
  while (cpu.pc !== 0xff00) {
    assert(++steps < maxSteps, `${name} did not return`);
    assert(!runtime.isHalted(), `${name} halted`);
    runtime.step();
  }
  assert.equal(cpu.sp, 0xf002, `${name} stack`);
  return { carry: cpu.flags.C, tag: cpu.a, payload: cpu.h * 256 + cpu.l };
}
function table(context: number, kind: number, base: number, pool: number) {
  put(context, base);
  put(context + 2, 64);
  put(context + 4, pool);
  put(context + 6, 1024);
  memory[context + 12] = kind;
  assert.equal(call("IINIT", 0, 0, 0, context).carry, 0);
}
function init(source: string) {
  const bytes = new TextEncoder().encode(source);
  memory.set(bytes, 0x8000);
  put(address("RFPTR"), 0x8000);
  put(address("RFLIMIT"), 0x8000 + bytes.length);
  table(SYMBOL_CONTEXT, 0, SYMBOL_TABLE, SYMBOL_POOL);
  table(STRING_CONTEXT, 1, STRING_TABLE, STRING_POOL);
  assert.equal(
    call("RINIT", address("RFSOURCE"), STRING_CONTEXT, SYMBOL_CONTEXT).carry,
    0,
  );
  assert.equal(call("N6RESET").carry, 0);
  assert.equal(call("N6SPOOL").carry, 0, source);
  put(address("N6PC"), 0);
}
function evaluate(source: string, maxSteps = 10_000_000) {
  init(source);
  return call("N6EXPR", 0, 0, 0, 0x1357, maxSteps);
}
function evaluateTop(source: string, maxSteps = 10_000_000) {
  init(source);
  assert.equal(call("N9RESV").carry, 0, source);
  return call("N9TOP", 0, 0, 0, 0x1357, maxSteps);
}

function resultMessage() {
  const start = address("N8MSGBUF");
  const length = memory[address("N8MLEN")]! |
    (memory[address("N8MLEN") + 1]! << 8);
  return new TextDecoder().decode(memory.slice(start, start + length));
}

function generatedDetails(source: string, codeLength = 16) {
  init(source);
  const result = call("N6EXPR");
  memory[address("N4RTAG")] = result.tag;
  put(address("N4RVAL"), result.payload);
  if (result.tag === 1) assert.equal(call("N8SERIAL", result.payload).carry, 0);
  assert.equal(call("N8CODE").carry, 0, source);
  const object = address("N4OBJ");
  const slot = address("N8CODOF");
  const relocation = address("N8RELTG");
  const callCount = memory[address("N8GCALLN")]!;
  const calls = Array.from({ length: callCount }, (_, index) => {
    const record = address("N8GCTBL") + index * 4;
    return {
      site: memory[record]! | (memory[record + 1]! << 8),
      service: memory[record + 2]!,
    };
  });
  return {
    code: [...memory.slice(object + slot, object + slot + codeLength)],
    length: memory[address("N8CLENW")]! |
      (memory[address("N8CLENW") + 1]! << 8),
    service: memory[object + relocation]! |
      (memory[object + relocation + 1]! << 8),
    calls,
    nested: memory[address("N8GNEST")]!,
    generatedCalls: memory[address("N8GCALLN")]!,
    generatedOffset: memory[address("N8GOFF")]! |
      (memory[address("N8GOFF") + 1]! << 8),
  };
}

function generatedCode(source: string, codeLength = 16) {
  const generated = generatedDetails(source, codeLength);
  return {
    code: generated.code,
    length: generated.length,
    service: generated.service,
  };
}

Deno.test("native nested arithmetic lowers to executable service calls", () => {
  const generated = generatedDetails("(+ (+ 1 2) 3)", 64);
  assert.equal(generated.nested, 1);
  assert.equal(generated.generatedCalls, 2);
  assert.equal(generated.generatedOffset, 36);
  assert.equal(generated.length, 36);
  assert.deepEqual(generated.calls, [
    { site: 18, service: 7 },
    { site: 33, service: 7 },
  ]);
  assert.deepEqual(generated.code.slice(0, 36), [
    0x3e,
    3,
    0x21,
    1,
    0,
    0xf5,
    0xe5,
    0x3e,
    3,
    0x21,
    2,
    0,
    0x47,
    0x54,
    0x5d,
    0xe1,
    0xf1,
    0xcd,
    0,
    0,
    0xf5,
    0xe5,
    0x3e,
    3,
    0x21,
    3,
    0,
    0x47,
    0x54,
    0x5d,
    0xe1,
    0xf1,
    0xcd,
    0,
    0,
    0xc9,
  ]);
  for (
    const [source, service] of [
      ["(- (- 8 3) 2)", 8],
      ["(* (* 2 3) 4)", 9],
      ["(/ (/ 8 2) 2)", 10],
    ] as const
  ) {
    const operation = generatedDetails(source, 64);
    assert.equal(operation.length, 36, source);
    assert.deepEqual(
      operation.calls,
      [{ site: 18, service }, { site: 33, service }],
      source,
    );
  }
});

Deno.test("native recipe staging overlays the consumed event spool", () => {
  assert.equal(address("N8RECBUF"), address("N6SPOOLB"));
});

Deno.test("native code slot lowers the bounded integer pair shape", () => {
  const generated = generatedCode("(cons 40 2)", 64);
  assert.ok(generated.length <= 64);
  assert.deepEqual(generated.code.slice(0, 16), [
    0x18,
    14,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ]);
  assert.deepEqual(generated.code.slice(16, 60), [
    0x01,
    0x02,
    0x00,
    0xcd,
    0x00,
    0x00,
    0x21,
    0x00,
    0x00,
    0x36,
    0x03,
    0x23,
    0x11,
    0x28,
    0x00,
    0x73,
    0x23,
    0x72,
    0x23,
    0x36,
    0x00,
    0x23,
    0x36,
    0x03,
    0x23,
    0x11,
    0x02,
    0x00,
    0x73,
    0x23,
    0x72,
    0x23,
    0x36,
    0x00,
    0x11,
    0x00,
    0x00,
    0x01,
    0x02,
    0x00,
    0xcd,
    0x00,
    0x00,
    0xc9,
  ]);
});

Deno.test("native code slot lowers flat arithmetic to service ABI", () => {
  assert.deepEqual(generatedCode("(+ 40 2)"), {
    code: [
      0x3e,
      3,
      0x21,
      40,
      0,
      0x06,
      3,
      0x11,
      2,
      0,
      0xcd,
      0,
      0,
      0xc9,
      0,
      0,
    ],
    length: 14,
    service: 7,
  });
  assert.deepEqual(generatedCode("(- 5)"), {
    code: [
      0x3e,
      3,
      0x21,
      5,
      0,
      0xcd,
      0,
      0,
      0xc9,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ],
    length: 9,
    service: 11,
  });
  assert.deepEqual(generatedCode("(+ 1 2 3)"), {
    code: [
      0x3e,
      3,
      0x21,
      6,
      0,
      0xcd,
      0,
      0,
      0xc9,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ],
    length: 9,
    service: 2,
  });
  assert.equal(generatedCode("(* 2 3)").service, 9);
  assert.equal(generatedCode("(/ 4 2)").service, 10);
});

Deno.test("native procedure evaluator binds fixed arity calls", () => {
  for (
    const [source, expected] of [
      ["((lambda (x) x) 42)", 42],
      ["((lambda (a b) (+ a b)) 17 25)", 42],
      ["((lambda (x) (+ x 1)) 41)", 42],
      ["((lambda (x) (begin 0 (+ x 1))) 41)", 42],
    ] as const
  ) {
    const result = evaluate(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.tag, 3, source);
    assert.equal(result.payload, expected, source);
  }
});
Deno.test("native procedure evaluator supports higher order capture-free calls", () => {
  const result = evaluate(
    "((lambda (f x) (+ (f x) (f x))) (lambda (v) (+ v 1)) 20)",
  );
  assert.equal(result.carry, 0);
  assert.equal(result.tag, 3);
  assert.equal(result.payload, 42);
});
Deno.test("native procedure evaluator rejects wrong arity", () => {
  assert.equal(evaluate("((lambda (x) x) 1 2)").carry, 1);
});
Deno.test("native procedure evaluator captures and mutates lexical bindings", () => {
  for (
    const [source, expected] of [
      ["(((lambda (x) (lambda () x)) 42))", 42],
      [
        "(((lambda (x) (lambda () (begin (set! x (+ x 1)) x))) 41))",
        42,
      ],
      [
        "(((lambda (outer) ((lambda (inner) (lambda () inner)) 7)) 42))",
        7,
      ],
      [
        "((lambda (x) (begin ((lambda () (set! x (+ x 1)))) x)) 41)",
        42,
      ],
      [
        "((lambda (x) (begin (set! x ((lambda () (+ x 1)))) x)) 41)",
        42,
      ],
      [
        "((lambda (x) (begin ((lambda () (set! x (+ x 1)))) ((lambda () x)))) 41)",
        42,
      ],
    ] as const
  ) {
    const result = evaluate(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.tag, 3, source);
    assert.equal(result.payload, expected, source);
  }
});

Deno.test("native evaluator preserves lexical primitive shadowing", () => {
  const result = evaluate(
    "((lambda (+) (+ 5 3)) (lambda (a b) (- a b)))",
  );
  assert.equal(result.carry, 0);
  assert.equal(result.tag, 3);
  assert.equal(result.payload, 2);
});

Deno.test("native derived forms preserve tail calls", () => {
  const cases = [
    "((lambda (self n) (cond ((zero? n) 42) " +
    "(else (self self (- n 1))))) " +
    "(lambda (self n) (cond ((zero? n) 42) " +
    "(else (self self (- n 1))))) 30)",
    "((lambda (self n) (and #t (if (zero? n) 42 " +
    "(self self (- n 1))))) " +
    "(lambda (self n) (and #t (if (zero? n) 42 " +
    "(self self (- n 1))))) 30)",
    "((lambda (self n) (or #f (if (zero? n) 42 " +
    "(self self (- n 1))))) " +
    "(lambda (self n) (or #f (if (zero? n) 42 " +
    "(self self (- n 1))))) 30)",
    "((lambda (self n) (if (zero? n) 42 " +
    "(let ((next (- n 1))) (self self next)))) " +
    "(lambda (self n) (if (zero? n) 42 " +
    "(let ((next (- n 1))) (self self next)))) 30)",
  ];
  for (const source of cases) {
    const result = evaluateTop(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.tag, 3, source);
    assert.equal(result.payload, 42, source);
  }
});

Deno.test("native procedure evaluator reuses the frame for a long tail loop", () => {
  const result = evaluate(
    "((lambda (self n) (if (zero? n) 42 (self self (- n 1)))) " +
      "(lambda (self n) (if (zero? n) 42 (self self (- n 1)))) 30000)",
    100_000_000,
  );
  assert.equal(result.carry, 0);
  assert.equal(result.tag, 3);
  assert.equal(result.payload, 42);
});

Deno.test("native procedure evaluator handles quoted data and pair primitives", () => {
  for (
    const [source, expectedTag, expectedPayload] of [
      ["(car '(40 . 2))", 3, 40],
      ["(car (quote (40 . 2)))", 3, 40],
      ["(cdr '(1 . 42))", 3, 42],
      ["(cdr (cons 1 42))", 3, 42],
      ["(car (list 40 2))", 3, 40],
      ["(car (cdr (list 1 2 3)))", 3, 2],
      ["(pair? '(1 2))", 0, 0xfe01],
      ["(null? '())", 0, 0xfe01],
      ["(eq? 'skate 'skate)", 0, 0xfe01],
      ["(symbol? 'skate)", 0, 0xfe01],
      ['(string? "same")', 0, 0xfe01],
      ["(char? #\\A)", 0, 0xfe01],
      ["(car (cdr '(1 2)))", 3, 2],
      ["(eq? (car ''name) 'quote)", 0, 0xfe01],
      ["(symbol? (car ''name))", 0, 0xfe01],
      ["(write 1)", 0, 0xfe04],
      ['(display "A")', 0, 0xfe04],
      ["(newline)", 0, 0xfe04],
    ] as const
  ) {
    const result = evaluate(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.tag, expectedTag, source);
    assert.equal(result.payload, expectedPayload, source);
  }
});

Deno.test("native quoted pairs serialize to the postfix recipe contract", () => {
  const value = evaluate("(quote (1 2))");
  assert.equal(value.carry, 0);
  assert.equal(value.tag, 1);
  const serialized = call("N8SERIAL", value.payload);
  assert.equal(serialized.carry, 0);
  const length = memory[address("N8OUTLEN")]! |
    (memory[address("N8OUTLEN") + 1]! << 8);
  assert.equal(length, 11);
  assert.deepEqual(
    Array.from(memory.slice(address("N8RECBUF"), address("N8RECBUF") + length)),
    [
      0x83,
      0x01,
      0x00,
      0x83,
      0x02,
      0x00,
      0x80,
      0x02,
      0xfe,
      0x00,
      0x00,
    ],
  );
});

Deno.test("native serializer preserves enclosing pairs across nested values", () => {
  const value = evaluate("(quote (1 (2 3)))");
  assert.equal(value.carry, 0);
  assert.equal(value.tag, 1);
  const serialized = call("N8SERIAL", value.payload);
  assert.equal(serialized.carry, 0);
  const length = memory[address("N8OUTLEN")]! |
    (memory[address("N8OUTLEN") + 1]! << 8);
  assert.equal(length, 19);
  assert.deepEqual(
    Array.from(memory.slice(address("N8RECBUF"), address("N8RECBUF") + length)),
    [
      0x83,
      0x01,
      0x00,
      0x83,
      0x02,
      0x00,
      0x83,
      0x03,
      0x00,
      0x80,
      0x02,
      0xfe,
      0x00,
      0x00,
      0x80,
      0x02,
      0xfe,
      0x00,
      0x00,
    ],
  );
});

Deno.test("native first-class primitive values dispatch to their handlers", () => {
  for (
    const [source, expectedTag, expectedPayload] of [
      ["((lambda (f) (f 1 1)) eq?)", 0, 0xfe01],
      ["((lambda (f) (f 1 2)) eq?)", 0, 0xfe00],
      ["(car ((lambda (f) (f 1 2)) list))", 3, 1],
      ["((lambda (f) (f #f)) not)", 0, 0xfe01],
    ] as const
  ) {
    const result = evaluate(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.tag, expectedTag, source);
    assert.equal(result.payload, expectedPayload, source);
  }
});

Deno.test("native result printer writes bounded structural values", () => {
  for (
    const [source, expected] of [
      ["(quote (1 2))", "(1 2)\r\n"],
      ["(quote (1 . 2))", "(1 . 2)\r\n"],
      ["(quote skate)", "skate\r\n"],
      ['(quote "A$B")', '"A$B"\r\n'],
      ["(quote #\\A)", "#\\A\r\n"],
    ] as const
  ) {
    const value = evaluate(source);
    assert.equal(value.carry, 0, source);
    memory[address("N4RTAG")] = value.tag;
    put(address("N4RVAL"), value.payload);
    const printed = call("N8PRT");
    assert.equal(printed.carry, 0, source);
    assert.equal(resultMessage(), expected, source);
  }
});

Deno.test("native top-level evaluator handles globals and derived forms", () => {
  for (
    const [source, expected] of [
      [
        "(define (inc value) (+ value 1)) (define answer (inc 41)) answer",
        42,
      ],
      ["(define get (lambda () answer)) (define answer 42) (get)", 42],
      [
        "(define value 1) (set! value 41) " +
        "(define + (lambda (left right) (- left right))) (+ 5 3)",
        2,
      ],
      [
        "(define f (lambda (value) (+ value 1))) " +
        "(set! f (lambda (value) (- value 1))) (f 42)",
        41,
      ],
      ["(let ((left 40) (right 2)) (+ left right))", 42],
      ["(let ((x 1)) (let ((y 2)) (+ x y)))", 3],
      ["(cond ((= 1 2) 0) ((= 2 2) 42) (else 7))", 42],
      ["(and #t 1 2)", 2],
      ["(or #f 42)", 42],
      ["(begin (define x 40) (+ x 2))", 42],
      ["(begin (define (f x) (+ x 1)) (f 41))", 42],
    ] as const
  ) {
    const result = evaluateTop(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.tag, 3, source);
    assert.equal(result.payload, expected, source);
  }
  const boolean = evaluateTop("(define value #f) (set! value #t) value");
  assert.equal(boolean.carry, 0);
  assert.equal(boolean.tag, 0);
  assert.equal(boolean.payload, 0xfe01);
});

Deno.test("native top-level evaluator reserves and rejects uninitialised globals", () => {
  const result = evaluateTop(
    "(define get (lambda () answer)) (get) (define answer 42)",
  );
  assert.equal(result.carry, 1);
});

Deno.test("native top-level evaluator exposes predicates and comparisons", () => {
  for (
    const source of [
      "(procedure? +)",
      "(number? 42)",
      "(boolean? #t)",
      "(not #f)",
      "(= 2 2)",
      "(< 1 2)",
      "(> 2 1)",
      "(<= 2 2)",
      "(>= 2 2)",
      "(> 2049 2048.0)",
    ]
  ) {
    const result = evaluateTop(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.tag, 0, source);
    assert.equal(result.payload, 0xfe01, source);
  }
});

Deno.test("native arithmetic keeps its operator across a nested first operand", () => {
  const result = evaluateTop(
    "((lambda (term next current limit) (+ (term current) 1)) " +
      "(lambda (value) (* value value)) (lambda (value) (+ value 1)) 1 5)",
  );
  assert.equal(result.carry, 0);
  assert.equal(result.tag, 3);
  assert.equal(result.payload, 2);
});

Deno.test("native arithmetic completes division after nested operands", () => {
  const result = evaluateTop(
    "((lambda (left right) (/ (+ left right) 2.0)) 1.0 2.0)",
  );
  assert.equal(result.carry, 0);
  assert.equal(result.tag, 0);
  assert.equal(result.payload, 0x3e00);
});
