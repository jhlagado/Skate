import assert from "node:assert/strict";

const skateUrl = new URL("../compiler/skate.asm", import.meta.url);
const compilerUrl = new URL("../compiler/", import.meta.url);
const atomSourcePartLimit = 0xffff;

function productionIncludes(source: string): string[] {
  return [...source.matchAll(/^%INCLUDE\s+"([^"]+)"\s*$/gm)].map((match) =>
    match[1]!
  );
}

Deno.test("production ATOM source parts stay below the 16-bit limit", async () => {
  const entry = await Deno.readTextFile(skateUrl);
  const includes = productionIncludes(entry);
  assert.ok(includes.length > 0);

  const encoder = new TextEncoder();
  for (const include of includes) {
    const url = new URL(include, compilerUrl);
    const bytes = encoder.encode(await Deno.readTextFile(url));
    assert.ok(
      bytes.length < atomSourcePartLimit,
      `${include} is ${bytes.length} bytes; ATOM source parts must stay below ` +
        `${atomSourcePartLimit}`,
    );
  }
});

Deno.test("the split macro and procedure parts retain useful headroom", async () => {
  const encoder = new TextEncoder();
  const bytes = async (name: string) =>
    encoder.encode(await Deno.readTextFile(new URL(name, compilerUrl))).length;

  assert.equal(await bytes("native-macro.asm"), 30346);
  assert.equal(await bytes("native-macro-expand.asm"), 35670);
  assert.equal(await bytes("native-procedure.asm"), 35443);
  assert.equal(await bytes("native-procedure-quoted.asm"), 29137);
});
