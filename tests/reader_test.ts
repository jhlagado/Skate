import assert from "node:assert/strict";
import { SourceReader } from "../tools/reader.ts";
import { readerMachine } from "./reader-machine.ts";

Deno.test("native reader matches host events, values, tables and positions", async () => {
  const m = await readerMachine();
  const corpus = [
    "",
    "; empty\r\n",
    "(lambda () '(2049 2049.0 -0 -0.0 #t #f . #\\xFF))",
    "'() (quote (a . b)) ''x",
    "'(quote . x)",
    "(a . '(b . c))",
    "(define (f x) (lambda () x))\r\n(f 1)",
    '"A" "\\x41;" "" "\\n\\r\\t\\\\\\""',
    "-32768 32767 .5 1. 1e2 +inf.0 -inf.0 +nan.0 1.00048828125 1e999999 -1e-999999 + -",
    "a\rb\nc\r\nd\t e",
    "#\\) #\\; #\\\" #\\' #\\( #\\\\ #\\space #\\newline",
  ];
  const kinds = {
    open: 1,
    close: 2,
    quote: 3,
    dot: 4,
    symbol: 5,
    value: 7,
    string: 8,
  };
  for (const source of corpus) {
    m.init(source);
    const host = new SourceReader(new TextEncoder().encode(source));
    for (const event of host.events()) {
      const native = m.call("RNEXT");
      assert.equal(native.carry, 0, source);
      assert.equal(native.kind, kinds[event.kind], source);
      assert.deepEqual(native.at, [
        event.at.offset,
        event.at.line,
        event.at.column,
      ], source);
      if (event.kind === "value") {
        assert.deepEqual([native.tag, native.payload], event.value, source);
      }
      if (event.kind === "symbol" || event.kind === "string") {
        assert.deepEqual([native.tag, native.payload], [
          1,
          (event.kind === "symbol" ? 0x2000 : 0x8000) | event.id,
        ], source);
      }
    }
    assert.equal(m.call("RNEXT").kind, 0, source);
    const before = m.word(m.address("RFPTR"));
    assert.equal(m.call("RNEXT").kind, 0);
    assert.equal(m.word(m.address("RFPTR")), before);
    assert.deepEqual(m.tables(), [
      host.symbols.snapshot(),
      host.strings.snapshot(),
    ], source);
  }
  console.log({
    readerCode: m.address("REND") - m.address("RINIT"),
    readerWorkspace: m.address("RWEND") - m.address("RWORK"),
    stats: [...m.stats],
  });
});
Deno.test("native reader rejects structure, lexical and capacity failures terminally", async () => {
  const m = await readerMachine();
  const cases: Array<[string, number]> = [
    [")", 128],
    ["(", 128],
    ["'", 128],
    ["(.)", 128],
    ["(. a)", 128],
    ["(a .)", 128],
    ["(a . b c)", 128],
    ["(a ')", 128],
    ["(a . ')", 128],
    ["(a . . b)", 128],
    ["1e", 128],
    ["32768", 130],
    ["-32769", 130],
    ["#true", 128],
    ["#\\x414", 128],
    ['"\\x1;"', 128],
    ["é", 131],
    ["a".repeat(32), 129],
    ["0".repeat(65), 129],
    ['"' + "a".repeat(256) + '"', 129],
    ["'".repeat(65) + "x", 129],
  ];
  for (const [source, code] of cases) {
    m.init(source);
    let event = m.call("RNEXT"), count = 0;
    while (!event.carry && event.kind !== 0) {
      assert(++count < 100);
      event = m.call("RNEXT");
    }
    assert.equal(event.carry, 1, source);
    assert.equal(event.kind, code, source);
    const before = m.word(m.address("RFPTR"));
    const repeated = m.call("RNEXT");
    assert.deepEqual([repeated.kind, repeated.carry, repeated.at], [
      event.kind,
      event.carry,
      event.at,
    ]);
    assert.equal(m.word(m.address("RFPTR")), before);
  }
  m.init("a b", 1);
  assert.equal(m.call("RNEXT").carry, 0);
  const tables = m.tables();
  assert.equal(m.call("RNEXT").kind, 129);
  assert.deepEqual(m.tables(), tables);
  m.init("(a . b c)");
  let steps = 0;
  while (!m.call("RNEXT").carry) assert(++steps < 10);
  assert.equal(m.word(0x6008), 2, "Rejected extra datum must not be interned");
});
Deno.test("native reader bounded nesting and long flat stream", async () => {
  const m = await readerMachine();
  for (
    const source of [
      "(".repeat(64) + "x" + ")".repeat(64),
      "'".repeat(64) + "x",
      "('".repeat(32) + "x" + ")".repeat(32),
      "(" + "x ".repeat(5000) + ")",
    ]
  ) {
    m.init(source);
    let count = 0;
    for (;;) {
      const event = m.call("RNEXT");
      assert.equal(event.carry, 0);
      if (event.kind === 0) break;
      count++;
      assert(count < 10100);
    }
    assert.equal(m.word(0x6008), 1);
    assert.equal(m.memory[m.address("RDEPTH")], 0);
  }
});
