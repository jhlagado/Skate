import assert from "node:assert/strict";
import { type ReaderLimits, ReadError, SourceReader } from "./reader.ts";
const bytes = (s: string) => new TextEncoder().encode(s);
function read(s: string, limits: Partial<ReaderLimits> = {}) {
  const reader = new SourceReader(bytes(s), "test.sk8", limits);
  return { events: [...reader.events()], reader };
}
function failure(
  s: string,
  code = "syntax",
  limits: Partial<ReaderLimits> = {},
) {
  let found: ReadError | undefined;
  try {
    read(s, limits);
  } catch (error) {
    assert(error instanceof ReadError);
    found = error;
  }
  assert(found, `Expected rejection: ${s}`);
  assert.equal(found.code, code);
  return found;
}
Deno.test("reader emits structure and typed scalars without an AST", () => {
  const { events } = read("(lambda () '(2049 2049.0 -0 -0.0 #t #f . #\\xFF))");
  assert.deepEqual(events.map(({ kind }) => kind), [
    "open",
    "symbol",
    "open",
    "close",
    "quote",
    "open",
    "value",
    "value",
    "value",
    "value",
    "value",
    "value",
    "dot",
    "value",
    "close",
    "close",
  ]);
  assert.deepEqual(
    events.filter((e) => e.kind === "value").map((e) => e.value),
    [[3, 2049], [0, 0x6800], [3, 0], [0, 0x8000], [0, 0xfe01], [0, 0xfe00], [
      0,
      0xffff,
    ]],
  );
  assert.deepEqual(read("'() (quote (a . b)) ''x").events.map((e) => e.kind), [
    "quote",
    "open",
    "close",
    "open",
    "symbol",
    "open",
    "symbol",
    "dot",
    "symbol",
    "close",
    "close",
    "quote",
    "quote",
    "symbol",
  ]);
});
Deno.test("reader rejects malformed datum structure and incomplete input", () => {
  for (
    const s of [
      ")",
      "(",
      "'",
      "(.)",
      "(. a)",
      "(a .)",
      "(a . b c)",
      "(a . . b)",
      "(a ')",
      "(a . ')",
      ".",
      "' .",
      "(a . (b) c)",
    ]
  ) failure(s);
  for (
    const s of [
      "(a . b)",
      "(a . 'b)",
      "(a . (b . c))",
      "'(quote . x)",
      "()",
      "(lambda () 1)",
    ]
  ) read(s);
});
Deno.test("reader numeric lexical policy and exact rounding", () => {
  const { events } = read(
    "-32768 32767 +12 .5 1. 1e2 +inf.0 -inf.0 +nan.0 1.00048828125 1e999999 -1e-999999 + -",
  );
  assert.deepEqual(
    events.filter((e) => e.kind === "value").map((e) => e.value),
    [
      [3, 32768],
      [3, 32767],
      [3, 12],
      [0, 0x3800],
      [0, 0x3c00],
      [0, 0x5640],
      [0, 0x7c00],
      [0, 0xfc00],
      [0, 0x7e00],
      [0, 0x3c00],
      [0, 0x7c00],
      [0, 0x8000],
    ],
  );
  for (
    const s of [
      "32768",
      "-32769",
      "1e",
      "2abc",
      "1/2",
      "1.2.3",
      "+nan.1",
      "-nan.0",
      "#x10",
      "#e1",
    ]
  ) failure(s);
});
Deno.test("reader decodes every byte escape and interns equal strings", () => {
  for (let b = 0; b < 256; b++) {
    const h = b.toString(16).padStart(2, "0");
    const { events, reader } = read(`#\\x${h} "\\x${h};"`);
    assert.deepEqual(events[0], {
      kind: "value",
      value: [0, 0xff00 | b],
      at: { source: "test.sk8", offset: 0, line: 1, column: 1 },
    });
    assert.deepEqual(reader.strings.snapshot().pool, Uint8Array.of(b));
  }
  const { events, reader } = read('"A" "\\x41;" "" "\\n\\r\\t\\\\\\""');
  assert.deepEqual(events.filter((e) => e.kind === "string").map((e) => e.id), [
    0,
    0,
    1,
    2,
  ]);
  assert.deepEqual([...reader.strings.snapshot().pool], [
    65,
    10,
    13,
    9,
    92,
    34,
  ]);
  for (const s of ['"', '"\\', '"\\x1;"', '"\\x00"', '"\\q"', '"\n"']) {
    failure(s);
  }
});
Deno.test("reader delimiter characters, comments and unsupported syntax", () => {
  const { events } = read(
    `#\\) #\\; #\\" #\\' #\\( #\\\\ #\\space #\\newline ; comment\r\n#t;EOF`,
  );
  assert.deepEqual(
    events.filter((e) => e.kind === "value").map((e) => e.value[1]),
    [0xff29, 0xff3b, 0xff22, 0xff27, 0xff28, 0xff5c, 0xff20, 0xff0a, 0xfe01],
  );
  for (
    const s of [
      "#true",
      "#f0",
      "#\\",
      "#\\spacex",
      "#\\x414",
      "#\\)x",
      "#(",
      "#;1",
      "#|x|#",
      "`x",
      ",x",
      "a.b",
      "foo@bar",
      "\0",
    ]
  ) failure(s);
  failure("é", "encoding");
});
Deno.test("reader capacities accept exact limits and reject the next unit", () => {
  read("a".repeat(31));
  failure("a".repeat(32), "capacity");
  read("0".repeat(64));
  failure("0".repeat(65), "capacity");
  read("1234", { numericBytes: 4 });
  failure("12345", "capacity", { numericBytes: 4 });
  read('"' + "a".repeat(255) + '"');
  failure('"' + "a".repeat(256) + '"', "capacity");
  read("(".repeat(64) + "x" + ")".repeat(64));
  failure("(".repeat(65), "capacity");
  read("'".repeat(64) + "x");
  failure("'".repeat(65) + "x", "capacity");
  read("a a", { symbols: 1, nameBytes: 1 });
  failure("a b", "capacity", { symbols: 1 });
  failure("aa", "capacity", { nameBytes: 1 });
  read('"a" "\\x61;"', { strings: 1, stringBytes: 1 });
  failure('"a" "b"', "capacity", { strings: 1 });
  failure('"ab"', "capacity", { stringBytes: 1 });
});
Deno.test("reader diagnostics retain source positions across CR LF CRLF", () => {
  const events = read("a\rb\nc\r\nd\t e").events;
  assert.deepEqual(events.map((e) => [e.at.offset, e.at.line, e.at.column]), [
    [0, 1, 1],
    [2, 2, 1],
    [4, 3, 1],
    [7, 4, 1],
    [10, 4, 4],
  ]);
  const error = failure(";comment\r\n  32768");
  assert.deepEqual(error.at, {
    source: "test.sk8",
    offset: 12,
    line: 2,
    column: 3,
  });
  assert.equal(failure("\n  (").at.column, 3);
});
Deno.test("reader is incremental and invariant under every input split", () => {
  const text = '(define x \'(#\\; . "A\\x42;"))\r\n; hi\r2049.0';
  const data = bytes(text), expected = read(text).events;
  for (let split = 0; split <= data.length; split++) {
    const chunks = function* () {
      yield* data.subarray(0, split);
      yield* data.subarray(split);
    };
    assert.deepEqual(
      [...new SourceReader(chunks(), "test.sk8").events()],
      expected,
    );
  }
  let pulled = 0;
  function* large() {
    pulled++;
    yield 40;
    for (let i = 0; i < 20000; i++) {
      pulled++;
      yield 120;
      pulled++;
      yield 32;
    }
    pulled++;
    yield 41;
  }
  const reader = new SourceReader(large());
  const events = reader.events();
  assert.equal(events.next().value?.kind, "open");
  assert.equal(pulled, 1);
  let count = 1;
  for (const _event of events) count++;
  assert.equal(count, 20002);
  assert.equal(reader.symbols.count, 1);
  assert.throws(() => [...reader.events()], /only be consumed once/);
});

Deno.test("reader rejects capacity before consuming an oversized source", () => {
  let consumed = 0;
  function* source() {
    for (let i = 0; i < 100000; i++) {
      consumed++;
      yield 48;
    }
  }
  assert.throws(() => [...new SourceReader(source()).events()], ReadError);
  assert.equal(consumed, 65);
  read("('".repeat(32) + "x" + ")".repeat(32));
  failure("('".repeat(32) + "'x" + ")".repeat(32), "capacity");
  read('"' + "\\x41;".repeat(255) + '"');
  failure('"' + "\\x41;".repeat(256) + '"', "capacity");
});
Deno.test("reader error position is independent of input segmentation", () => {
  for (const text of ["(a .", "'", '"\\x4', '\r\n"unterminated', "(a . b c)"]) {
    const expected = failure(text), data = bytes(text);
    for (let split = 0; split <= data.length; split++) {
      const source = function* () {
        yield* data.subarray(0, split);
        yield* data.subarray(split);
      };
      assert.throws(
        () => [...new SourceReader(source(), "test.sk8").events()],
        (error: unknown) => {
          assert(error instanceof ReadError);
          assert.equal(error.code, expected.code);
          assert.deepEqual(error.at, expected.at);
          return true;
        },
      );
    }
  }
});
