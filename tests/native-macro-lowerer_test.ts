import assert from "node:assert/strict";
import { SourceReader } from "../tools/reader.ts";
import { expandSyntaxRules } from "../tools/syntax-rules.ts";
import { loadAssembly } from "./z80.ts";

const m = await loadAssembly("tests/native-macro-lowerer-machine.asm", {
  maxInstructions: 400_000_000,
  maxCycles: 5_000_000_000,
});
const { runtime, address } = m;
const memory = runtime.hardware.memory;
const cpu = runtime.cpu;

const SOURCE = 0xc000;
const SYMBOL_CONTEXT = 0xc200;
const STRING_CONTEXT = 0xc20e;
const SYMBOL_TABLE = 0xc300;
const STRING_TABLE = 0xc500;
const SYMBOL_POOL = 0xc700;
const STRING_POOL = 0xcb00;

const put = (p: number, value: number) => {
  memory[p] = value & 255;
  memory[p + 1] = (value >>> 8) & 255;
};

const word = (p: number) => memory[p]! | (memory[p + 1]! << 8);

function call(
  name: string,
  hl = 0,
  bc = 0,
  de = 0,
  ix = 0x1357,
  maxSteps = 20_000_000,
) {
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
    assert(++steps < maxSteps, `${name} did not return`);
    assert(!runtime.isHalted(), `${name} halted`);
    runtime.step();
  }
  assert.equal(cpu.sp, 0xf002, `${name} stack`);
  return { carry: cpu.flags.C, tag: cpu.a, payload: cpu.h * 256 + cpu.l };
}

function table(context: number, kind: number, base: number, pool: number) {
  put(context, base);
  put(context + 2, 128);
  put(context + 4, pool);
  put(context + 6, 4096);
  memory[context + 12] = kind;
  assert.equal(call("IINIT", 0, 0, 0, context).carry, 0);
}

function evaluate(source: string) {
  const bytes = new TextEncoder().encode(source);
  memory.fill(0, SOURCE, SOURCE + 512);
  memory.set(bytes, SOURCE);
  put(address("NMSPTR"), SOURCE);
  put(address("NMSEND"), SOURCE + bytes.length);

  table(SYMBOL_CONTEXT, 0, SYMBOL_TABLE, SYMBOL_POOL);
  table(STRING_CONTEXT, 1, STRING_TABLE, STRING_POOL);
  assert.equal(
    call("RINIT", address("NMSOURCE"), STRING_CONTEXT, SYMBOL_CONTEXT).carry,
    0,
    source,
  );
  assert.equal(call("NMINIT", 0xa000, 0x2000).carry, 0, source);
  assert.equal(call("NMPARSE").carry, 0, source);
  assert.equal(call("NMREW").carry, 0, source);
  assert.equal(call("NMEXPALL").carry, 0, source);
  assert.equal(call("NMOUTRW").carry, 0, source);
  assert.equal(call("N6PLANM").carry, 0, source);
  assert.equal(call("NMOUTRW").carry, 0, source);
  assert.equal(call("N6RESET").carry, 0, source);
  assert.equal(call("N6SPOOLM").carry, 0, source);
  assert.equal(call("N9RESV").carry, 0, source);
  return call("N9TOP", 0, 0, 0, 0x1357, 100_000_000);
}

type CanonicalEvent =
  | { kind: "open" | "close" | "quote" | "dot" }
  | { kind: "symbol"; text: string }
  | { kind: "value"; tag: number; payload: number };

function prepareMacroSource(source: string) {
  const bytes = new TextEncoder().encode(source);
  memory.fill(0, SOURCE, SOURCE + 512);
  memory.set(bytes, SOURCE);
  put(address("NMSPTR"), SOURCE);
  put(address("NMSEND"), SOURCE + bytes.length);
  table(SYMBOL_CONTEXT, 0, SYMBOL_TABLE, SYMBOL_POOL);
  table(STRING_CONTEXT, 1, STRING_TABLE, STRING_POOL);
  assert.equal(
    call("RINIT", address("NMSOURCE"), STRING_CONTEXT, SYMBOL_CONTEXT).carry,
    0,
    source,
  );
  assert.equal(call("NMINIT", 0xa000, 0x2000).carry, 0, source);
  assert.equal(call("NMPARSE").carry, 0, source);
  assert.equal(call("NMREW").carry, 0, source);
  assert.equal(call("NMEXPALL").carry, 0, source);
  assert.equal(call("NMOUTRW").carry, 0, source);
}

function nativeEvents(source: string): CanonicalEvent[] {
  prepareMacroSource(source);
  const events: CanonicalEvent[] = [];
  for (;;) {
    const event = call("NMNEXT");
    assert.equal(event.carry, 0, source);
    if (event.tag === 0) break;
    if (event.tag === 1) events.push({ kind: "open" });
    else if (event.tag === 2) events.push({ kind: "close" });
    else if (event.tag === 3) events.push({ kind: "quote" });
    else if (event.tag === 4) events.push({ kind: "dot" });
    else if (event.tag === 5) {
      const length = memory[address("LBUFLEN")]!;
      const text = String.fromCharCode(
        ...memory.slice(address("LBUFFER"), address("LBUFFER") + length),
      );
      events.push({ kind: "symbol", text });
    } else if (event.tag === 7) {
      events.push({
        kind: "value",
        tag: memory[address("RTAG")]!,
        payload: event.payload,
      });
    } else {
      assert.fail(`unsupported native parity event ${event.tag}`);
    }
  }
  return events;
}

function internedText(
  snapshot: { descriptors: Uint8Array; pool: Uint8Array },
  id: number,
  stride: number,
) {
  const descriptor = id * stride;
  const offset = snapshot.descriptors[descriptor]! |
    (snapshot.descriptors[descriptor + 1]! << 8);
  const length = snapshot.descriptors[descriptor + 2]!;
  return String.fromCharCode(...snapshot.pool.slice(offset, offset + length));
}

function hostEvents(source: string): CanonicalEvent[] {
  const expanded = expandSyntaxRules(
    new TextEncoder().encode(source),
    "parity.sk8",
  ).bytes;
  const reader = new SourceReader(expanded, "parity.sk8");
  const events: CanonicalEvent[] = [];
  for (const event of reader.events()) {
    if (
      event.kind === "open" || event.kind === "close" ||
      event.kind === "quote" || event.kind === "dot"
    ) {
      events.push({ kind: event.kind });
    } else if (event.kind === "symbol") {
      events.push({
        kind: "symbol",
        text: internedText(reader.symbols.snapshot(), event.id, 3),
      });
    } else if (event.kind === "value") {
      events.push({
        kind: "value",
        tag: event.value[0],
        payload: event.value[1],
      });
    } else {
      assert.fail("string events are outside this parity corpus");
    }
  }
  return events;
}

function assertEquivalentEvents(
  actual: CanonicalEvent[],
  expected: CanonicalEvent[],
  source: string,
) {
  assert.equal(actual.length, expected.length, source);
  for (let index = 0; index < expected.length; index += 1) {
    const left = actual[index]!;
    const right = expected[index]!;
    if (
      left.kind === "symbol" && right.kind === "symbol" &&
      right.text.startsWith("$m")
    ) {
      // The host oracle alpha-renames generated binders for readability.  The
      // target preserves authored spelling and carries the binding identity in
      // its scope mark; native-macro_test.ts checks that identity directly.
      continue;
    }
    assert.deepEqual(left, right, `${source} event ${index}`);
  }
}

Deno.test("native macro output feeds the native lowerer", () => {
  const result = evaluate(
    "(define-syntax inc (syntax-rules () " +
      "((inc x) (+ x 1)))) (inc 41)",
  );
  assert.equal(result.carry, 0);
  assert.equal(result.tag, 3);
  assert.equal(result.payload, 42);
});

Deno.test("native macro output retains ordinary top-level forms", () => {
  const result = evaluate(
    "(define-syntax twice (syntax-rules () " +
      "((twice x) (+ x x)))) (twice 21)",
  );
  assert.equal(result.carry, 0);
  assert.equal(result.tag, 3);
  assert.equal(result.payload, 42);
});

Deno.test("native macro expansion recurses through generated applications", () => {
  const result = evaluate(
    "(define-syntax twice (syntax-rules () " +
      "((twice x) (+ x x)))) (twice (twice 3))",
  );
  assert.equal(result.carry, 0);
  assert.equal(result.tag, 3);
  assert.equal(result.payload, 12);
});

Deno.test("native lowerer preserves nested application heads", () => {
  const result = evaluate("((lambda (x) (+ x 1)) 41)");
  assert.equal(result.carry, 0);
  assert.equal(result.tag, 3);
  assert.equal(result.payload, 42);
});

Deno.test("native lowerer preserves top-level global identities", () => {
  const result = evaluate("(define answer 42) answer");
  assert.equal(result.carry, 0);
  assert.equal(result.tag, 3);
  assert.equal(result.payload, 42);
});

Deno.test("native macro expansion matches the host event corpus", () => {
  const corpus = [
    "(define-syntax inc (syntax-rules () " +
    "((inc x) (+ x 1)))) (inc 41)",
    "(define-syntax sum (syntax-rules () " +
    "((sum x ...) (+ x ...)))) (sum 1 2 3)",
    "(define-syntax all (syntax-rules () " +
    "((all . args) (list . args)))) (all 1 2)",
    "(define-syntax twice (syntax-rules () " +
    "((twice x) (+ x x)))) (twice (twice 3))",
    "(define-syntax capture (syntax-rules () " +
    "((_ value) (let ((tmp 1)) value)))) " +
    "(let ((tmp 40)) (capture tmp))",
  ];
  for (const source of corpus) {
    assertEquivalentEvents(nativeEvents(source), hostEvents(source), source);
  }
});

Deno.test("native lowerer planner rejects an over-capacity expanded stream", () => {
  const arena = 0xa000;
  const nodes = 1024;
  const nodeWidth = 18;
  const end = arena + nodes * nodeWidth + 0x0200;
  assert.ok(end < 0xf000);
  assert.equal(call("NMINIT", arena, end - arena).carry, 0);
  for (let index = 0; index < nodes; index++) {
    const node = arena + index * nodeWidth;
    memory[node] = 2;
    memory[node + 1] = 0;
    put(node + 2, 0);
    put(node + 4, index + 1 < nodes ? node + nodeWidth : 0);
    put(node + 6, 0);
    memory[node + 8] = 3;
    put(node + 9, 1);
    put(node + 11, index);
    put(node + 13, 1);
    put(node + 15, 1);
    memory[node + 17] = 0;
  }
  put(address("NMOUTRT"), arena);
  put(address("NMOTAIL"), arena + (nodes - 1) * nodeWidth);
  put(address("NMPTR"), arena + nodes * nodeWidth);
  assert.equal(call("NMOUTRW").carry, 0);
  const spool = address("N6SPOOLB");
  memory[spool] = 0xa5;
  assert.equal(call("N6PLANM").carry, 1);
  assert.equal(
    word(address("NMTRHI")),
    word(address("NMTRBASE")) + 6,
  );
  assert.equal(memory[spool], 0xa5);
  const planned = word(address("N6SPLEN"));
  assert.equal(planned, 1024);
});

Deno.test("native lowerer planner rejects an arena collision before output", () => {
  const arena = 0xa000;
  assert.equal(call("NMINIT", arena, 0x2000).carry, 0);
  const collision = arena + 0x1000;
  put(address("NMPTR"), collision + 1);
  put(address("NMCAPPTR"), collision);
  const spool = address("N6SPOOLB");
  memory[spool] = 0x5a;
  put(address("N6SPLEN"), 0x1234);
  assert.equal(call("N6PLANM").carry, 1);
  assert.equal(memory[spool], 0x5a);
  assert.equal(word(address("N6SPLEN")), 0x1234);
});
