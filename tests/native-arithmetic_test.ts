import assert from "node:assert/strict";
import { parseNobj1 } from "@jhlagado/z80-tool-services";
import {
  compileNativeArithmetic,
  nativeMessage,
} from "../tools/native-arithmetic.ts";

const source = (text: string) => new TextEncoder().encode(text);

Deno.test("N4 reader-driven arithmetic keeps exact integers and binary16", () => {
  const exact = compileNativeArithmetic(source("(+ 2048 1)"), "exact.sk8");
  assert.deepEqual(exact.value, [3, 2049]);
  assert.equal(exact.message, "2049\r\n");

  const mixed = compileNativeArithmetic(
    source("(+ 2049 0.0)"),
    "mixed.sk8",
  );
  assert.deepEqual(mixed.value, [0, 0x6800]);
  assert.equal(mixed.message, "F16:6800\r\n");

  const large = compileNativeArithmetic(source("(+ 30000 0)"), "large.sk8");
  assert.deepEqual(large.value, [3, 30000]);

  assert.deepEqual(compileNativeArithmetic(source("(- 44 2)")).value, [3, 42]);
  assert.deepEqual(compileNativeArithmetic(source("(* 6 7)")).value, [3, 42]);
  assert.deepEqual(compileNativeArithmetic(source("(/ 84 2)")).value, [
    0,
    0x5140,
  ]);
});

Deno.test("N4 emits a committed NOBJ with a service relocation", () => {
  const compiled = compileNativeArithmetic(source("(+ 40 2)"), "add.sk8");
  const parsed = parseNobj1(compiled.objectBytes);
  assert.equal(parsed.commit.recordCount, 10);
  assert.equal(parsed.layout.entrySymbolId, 1);
  assert.equal(parsed.relocations.length, 1);
  assert.equal(parsed.relocations[0]?.siteOffset, 4);
  assert.deepEqual(
    [...parsed.images[0]!.bytes.slice(20, 25)],
    [...new TextEncoder().encode("42\r\n$")],
  );
  assert.deepEqual([...compiled.comBytes], [...parsed.images[0]!.bytes]);
});

Deno.test("N4 reports source locations and refuses unsupported forms", () => {
  assert.throws(
    () => compileNativeArithmetic(source("(+ 32767 1)"), "overflow.sk8"),
    /overflow\.sk8:1:2: Signed integer overflow/,
  );
  assert.throws(
    () => compileNativeArithmetic(source("(+ 1 #t)"), "type.sk8"),
    /type\.sk8:1:2: Expected a Skate number/,
  );
  assert.throws(
    () => compileNativeArithmetic(source("(+ 1 2"), "syntax.sk8"),
    /syntax\.sk8:1:1: Unclosed list/,
  );
  assert.throws(
    () => compileNativeArithmetic(source("(display 1)"), "form.sk8"),
    /form\.sk8:1:2: Unsupported form display/,
  );
});

Deno.test("N4 message format is deterministic for every numeric result kind", () => {
  assert.equal(nativeMessage([3, 0]), "0\r\n");
  assert.equal(nativeMessage([3, 0x8000]), "-32768\r\n");
  assert.equal(nativeMessage([0, 0x3800]), "F16:3800\r\n");
});
