import assert from "node:assert/strict";
import { compileM10, compileM10Package } from "../tools/m7-compiler.ts";
import { createSourcePackage } from "../tools/source-package.ts";

const bytes = (source: string) => new TextEncoder().encode(source);

Deno.test("packaged M10 output matches the equivalent concatenated source", async () => {
  const sourcePackage = createSourcePackage([
    { name: "prelude.sk8", bytes: bytes("(define (inc value) (+ value 1))") },
    { name: "app.sk8", bytes: bytes("(inc 41)") },
  ]);
  const packaged = await compileM10Package(sourcePackage);
  const direct = await compileM10(sourcePackage.bytes, "combined.sk8");
  assert.deepEqual(packaged.comBytes, direct.comBytes);
  assert.deepEqual(packaged.objectBytes, direct.objectBytes);
});

Deno.test("packaged compiler errors identify the authored source part", async () => {
  const sourcePackage = createSourcePackage([
    { name: "prelude.sk8", bytes: bytes("(define answer 41)") },
    { name: "app.sk8", bytes: bytes("(missing answer)") },
  ]);
  await assert.rejects(
    () => compileM10Package(sourcePackage),
    (error) =>
      error instanceof Error &&
      /app\.sk8:1:2: Unbound identifier/.test(error.message),
  );
});
