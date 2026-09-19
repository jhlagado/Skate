import assert from "node:assert/strict";
import { lexerMachine } from "./lexer-machine.ts";
Deno.test("native lexer returns structure, numbers and identifiers", async () => {
  const m = await lexerMachine();
  m.init("(lambda () '(2049 2049.0 -0 -0.0 #t #f . #\\xFF))");
  const kinds = [], values = [], strings = [];
  for (;;) {
    const r = m.call("LEXNEXT");
    assert.equal(r.carry, 0);
    if (!r.kind) break;
    kinds.push(r.kind);
    if (r.kind === 7) values.push(r.payload);
    if (r.kind === 5 || r.kind === 6) {
      strings.push(new TextDecoder().decode(r.text));
    }
  }
  assert.deepEqual(kinds, [1, 5, 1, 2, 3, 1, 6, 6, 6, 6, 7, 7, 4, 7, 2, 2]);
  assert.deepEqual(values, [0xfe01, 0xfe00, 0xffff]);
  assert.deepEqual(strings, ["lambda", "2049", "2049.0", "-0", "-0.0"]);
  assert.equal(m.call("LEXNEXT").kind, 0);
});
Deno.test("native lexer decimal grammar and malformed tokens", async () => {
  const m = await lexerMachine();
  for (
    const s of [
      "-32768",
      "32768",
      ".5",
      "1.",
      "1e2",
      "+inf.0",
      "-inf.0",
      "+nan.0",
      "1.00048828125",
      "1e999999",
      "-1e-999999",
    ]
  ) {
    m.init(s);
    const r = m.call("LEXNEXT");
    assert.equal(r.carry, 0, s);
    assert.equal(r.kind, 6, s);
    assert.equal(new TextDecoder().decode(r.text), s);
  }
  for (
    const s of [
      "1e",
      "2abc",
      "1/2",
      "1.2.3",
      "+nan.1",
      "-nan.0",
      "#x10",
      "#e1",
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
      ".e2",
      "1e+",
      "+.",
    ]
  ) {
    m.init(s);
    const r = m.call("LEXNEXT");
    assert.equal(r.carry, 1, s);
    assert.equal(r.kind, 128, s);
    assert.equal(m.call("LEXNEXT").kind, 128, s);
  }
  for (const s of ["+", "-", "abc", "a123", "!$%&*/:<=>?^_~+-"]) {
    m.init(s);
    assert.equal(m.call("LEXNEXT").kind, 5, s);
  }
});
Deno.test("native lexer decodes every byte and string escape", async () => {
  const m = await lexerMachine();
  for (let b = 0; b < 256; b++) {
    const h = b.toString(16).padStart(2, "0");
    m.init(`#\\x${h} "\\x${h};"`);
    let r = m.call("LEXNEXT");
    assert.equal(r.kind, 7, h);
    assert.equal(r.payload, 0xff00 | b, h);
    r = m.call("LEXNEXT");
    assert.equal(r.kind, 8, h);
    assert.deepEqual(r.text, Uint8Array.of(b));
  }
  m.init(
    `#\\) #\\; #\\" #\\' #\\( #\\\\ #\\space #\\newline "\\n\\r\\t\\\\\\\""`,
  );
  for (const value of [41, 59, 34, 39, 40, 92, 32, 10]) {
    assert.equal(m.call("LEXNEXT").payload, 0xff00 | value);
  }
  assert.deepEqual(m.call("LEXNEXT").text, Uint8Array.of(10, 13, 9, 92, 34));
  for (const s of ['"', '"\\', '"\\x1;"', '"\\x00"', '"\\q"', '"\n"']) {
    m.init(s);
    assert.equal(m.call("LEXNEXT").kind, 128, s);
  }
});
Deno.test("native lexer exact capacities, positions and reset", async () => {
  const m = await lexerMachine();
  for (
    const [s, k] of [["a".repeat(31), 5], ["0".repeat(64), 6], [
      '"' + "a".repeat(255) + '"',
      8,
    ], ['"' + "\\x41;".repeat(255) + '"', 8]] as const
  ) {
    m.init(s);
    assert.equal(m.call("LEXNEXT").kind, k);
  }
  for (
    const s of ["a".repeat(32), "0".repeat(65), '"' + "a".repeat(256) + '"']
  ) {
    m.init(s);
    assert.equal(m.call("LEXNEXT").kind, 129);
  }
  m.init("a\rb\nc\r\nd\t e");
  for (const at of [[0, 1, 1], [2, 2, 1], [4, 3, 1], [7, 4, 1], [10, 4, 4]]) {
    assert.deepEqual(m.call("LEXNEXT").at, at);
  }
  m.init("; comment\r\n#t;EOF");
  assert.equal(m.call("LEXNEXT").payload, 0xfe01);
  assert.equal(m.call("LEXNEXT").kind, 0);
  m.init(Uint8Array.of(128));
  assert.equal(m.call("LEXNEXT").kind, 130);
  m.init("a");
  m.put(m.address("LOFFSET"), 65535);
  assert.equal(m.call("LEXNEXT").kind, 131);
  m.init("a");
  assert.equal(m.call("LEXNEXT").kind, 5);
});
Deno.test("native lexer character classes and decimal grammar partitions", async () => {
  const m = await lexerMachine();
  for (let c = 33; c < 127; c++) {
    const s = String.fromCharCode(c);
    if ("()'\";#".includes(s)) continue;
    m.init(s);
    const r = m.call("LEXNEXT");
    const expected = /[0-9]/.test(s)
      ? 6
      : s === "."
      ? 4
      : /[A-Za-z!$%&*/:<=>?^_~+\-]/.test(s)
      ? 5
      : 128;
    assert.equal(r.kind, expected, s);
  }
  for (const sign of ["", "+", "-"]) {
    for (const body of ["0", "12", ".5", "1.", "1.25"]) {
      for (const exp of ["", "e0", "E+12", "e-32"]) {
        const s = sign + body + exp;
        m.init(s);
        assert.equal(m.call("LEXNEXT").kind, 6, s);
      }
    }
  }
  for (const body of ["1", "1.2", ".2"]) {
    for (const bad of ["e", "e+", "e-", "ee1", "e1.0", "e1x", "x"]) {
      const s = body + bad;
      m.init(s);
      assert.equal(m.call("LEXNEXT").kind, 128, s);
    }
  }
  for (const [field, input] of [["LCOLUMN", "a"], ["LLINENO", "\n"]] as const) {
    m.init(input);
    m.put(m.address(field), 65535);
    assert.equal(m.call("LEXNEXT").kind, 131);
  }
  m.init(Uint8Array.of(59, 128));
  assert.equal(m.call("LEXNEXT").kind, 130);
});
Deno.test("native lexer EOF and source failures retain their own locations", async () => {
  const m = await lexerMachine();
  m.init("a \r\n  ");
  m.call("LEXNEXT");
  let r = m.call("LEXNEXT");
  assert.equal(r.kind, 0);
  assert.deepEqual(r.at, [6, 2, 3]);
  m.init(Uint8Array.of(97, 32, 13, 10, 32, 128));
  m.call("LEXNEXT");
  r = m.call("LEXNEXT");
  assert.equal(r.kind, 130);
  assert.deepEqual(r.at, [5, 2, 2]);
});
