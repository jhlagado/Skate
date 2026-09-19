import assert from "node:assert/strict";
import {
  createNativeSourcePackage,
  NativeManifestError,
  parseNativeManifest,
} from "./native-source-package.ts";

const bytes = (text: string) => new TextEncoder().encode(text);

Deno.test("native manifests normalize bounded CP/M 8.3 names in order", () => {
  assert.deepEqual(
    parseNativeManifest(bytes("core.sk8\r\nTERM.LIB\n\x1aignored.sk8")),
    ["CORE.SK8", "TERM.LIB"],
  );
});

Deno.test("native manifests reject duplicate, missing and malformed parts", () => {
  assert.throws(
    () => parseNativeManifest(bytes("CORE.SK8\ncore.sk8\n")),
    (error) =>
      error instanceof NativeManifestError && error.code === "duplicate",
  );
  assert.throws(
    () => parseNativeManifest(bytes("TOO-LONG9.SK8\n")),
    (error) => error instanceof NativeManifestError && error.code === "invalid",
  );
  assert.throws(
    () =>
      createNativeSourcePackage(
        bytes("CORE.SK8\nMISSING.SK8\n"),
        new Map([["CORE.SK8", bytes("42")]]),
      ),
    (error) => error instanceof NativeManifestError && error.code === "missing",
  );
});

Deno.test("native manifest package preserves the ordered source contract", () => {
  const packageValue = createNativeSourcePackage(
    bytes("CORE.SK8\nAPP.SK8\n"),
    new Map([
      ["CORE.SK8", bytes("(define answer 40)\n")],
      ["APP.SK8", bytes("(+ answer 2)\n")],
    ]),
  );
  assert.deepEqual(packageValue.parts.map(({ name }) => name), [
    "CORE.SK8",
    "APP.SK8",
  ]);
  assert.equal(
    new TextDecoder().decode(packageValue.bytes),
    "(define answer 40)\n(+ answer 2)\n",
  );
});
