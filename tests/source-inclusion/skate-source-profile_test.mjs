import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";

import {
  createSkmManifest,
  resolveSkateSource,
} from "../../tools/source-inclusion/skate-source-profile.mjs";

async function withSources(files, check) {
  const root = await mkdtemp(join(Deno.cwd(), ".skate-source-"));
  try {
    for (const [name, source] of Object.entries(files)) {
      await writeFile(join(root, name), source);
    }
    await check(root);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

Deno.test("shared resolver prepares an import-once Skate graph and CP/M manifest", async () => {
  await withSources({
    "MAIN.SK8": '; first\n(include "A.SK8" "B.SK8")\n(write (f))\n',
    "A.SK8": '(include "COMMON.SK8")\n(define f (lambda () (g)))\n',
    "B.SK8": '(include "COMMON.SK8")\n(define b 1)\n',
    "COMMON.SK8": "(define g (lambda () 42))\n",
  }, async (root) => {
    const project = await resolveSkateSource({ root, entry: "MAIN.SK8" });
    assert.deepEqual(project.parts.map((part) => part.logicalIdentity), [
      "COMMON.SK8",
      "A.SK8",
      "B.SK8",
      "MAIN.SK8",
    ]);
    assert.equal(
      new TextDecoder().decode(createSkmManifest(project.parts)),
      "COMMON.SK8\nA.SK8\nB.SK8\nMAIN.SK8\n",
    );
    for (const part of project.parts) {
      assert.equal(part.compilerBytes.length, part.originalBytes.length);
      assert.deepEqual(
        [...part.compilerBytes].filter((byte) => byte === 10),
        [...part.originalBytes].filter((byte) => byte === 10),
      );
    }
    assert.match(
      new TextDecoder().decode(project.parts.at(-1).compilerBytes),
      /write \(f\)/,
    );
    assert.doesNotMatch(
      new TextDecoder().decode(project.parts.at(-1).compilerBytes),
      /include/,
    );
  });
});

Deno.test("shared resolver rejects cycles and paths outside the project", async () => {
  await withSources({
    "MAIN.SK8": '(include "A.SK8")\n',
    "A.SK8": '(include "MAIN.SK8")\n',
  }, async (root) => {
    await assert.rejects(
      resolveSkateSource({ root, entry: "MAIN.SK8" }),
      (error) => error.code === "dependency-cycle",
    );
  });
  await withSources(
    { "MAIN.SK8": '(include "../OUT.SK8")\n' },
    async (root) => {
      await assert.rejects(
        resolveSkateSource({ root, entry: "MAIN.SK8" }),
        (error) => error.code === "root-escape",
      );
    },
  );
});

Deno.test("late include and unrepresentable CP/M part names fail before compilation", async () => {
  await withSources(
    { "MAIN.SK8": '(define x 1)\n(include "A.SK8")\n' },
    async (root) => {
      await assert.rejects(
        resolveSkateSource({ root, entry: "MAIN.SK8" }),
        (error) => error.code === "late-include" && error.location.line === 2,
      );
    },
  );
  assert.throws(() =>
    createSkmManifest([
      { logicalIdentity: "one/A.SK8" },
      { logicalIdentity: "two/A.SK8" },
    ]), (error) => error.code === "invalid-cpm-part");
});

Deno.test("quoted include data is ordinary Scheme and CP/M text stops at Control-Z", async () => {
  await withSources({
    "MAIN.SK8":
      '(include "LIB.SK8")\n(write \'(include "DATA.SK8"))\n\x1a(include "AFTER.SK8")',
    "LIB.SK8": "(define value 42)\n",
  }, async (root) => {
    const project = await resolveSkateSource({ root, entry: "MAIN.SK8" });
    assert.deepEqual(project.parts.map((part) => part.logicalIdentity), [
      "LIB.SK8",
      "MAIN.SK8",
    ]);
  });
});
