import assert from "node:assert/strict";
import {
  createSourcePackage,
  parseSourceManifest,
  SourcePackageError,
} from "./source-package.ts";

const bytes = (source: string) => new TextEncoder().encode(source);

Deno.test("source packages preserve order and authored positions", () => {
  const sourcePackage = createSourcePackage([
    { name: "prelude.sk8", bytes: bytes("(define answer 41)") },
    { name: "app.sk8", bytes: bytes("(+ answer 1)") },
  ]);

  assert.equal(
    new TextDecoder().decode(sourcePackage.bytes),
    "(define answer 41)\n(+ answer 1)",
  );
  const appOffset = sourcePackage.bytes.indexOf(0x28, 1);
  assert.ok(appOffset > 0);
  assert.deepEqual(sourcePackage.locate(appOffset), {
    source: "app.sk8",
    line: 1,
    column: 1,
  });
  assert.deepEqual(sourcePackage.locate(appOffset + 2), {
    source: "app.sk8",
    line: 1,
    column: 3,
  });
});

Deno.test("source packages reject duplicate parts and malformed parts", () => {
  assert.throws(
    () =>
      createSourcePackage([
        { name: "same.sk8", bytes: bytes("1") },
        { name: "same.sk8", bytes: bytes("2") },
      ]),
    (error) =>
      error instanceof SourcePackageError && error.code === "duplicate",
  );
  assert.throws(
    () => createSourcePackage([{ name: "broken.sk8", bytes: bytes("(") }]),
    (error) => error instanceof Error && /broken\.sk8:1:1/.test(error.message),
  );
});

Deno.test("source manifests preserve their declared order", () => {
  assert.deepEqual(parseSourceManifest(" core.sk8\r\n\napp.sk8 \n"), [
    "core.sk8",
    "app.sk8",
  ]);
});
