import assert from "node:assert/strict";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const runtimeRoot = fileURLToPath(
  new URL("../../src/runtime/", import.meta.url),
);

async function runtimeSources(directory: string): Promise<string[]> {
  const sources: string[] = [];
  for await (const entry of Deno.readDir(directory)) {
    const path = join(directory, entry.name);
    if (entry.isDirectory) sources.push(...await runtimeSources(path));
    else if (entry.name.endsWith(".asm")) {
      sources.push(await Deno.readTextFile(path));
    }
  }
  return sources;
}

function number(text: string): number {
  const value = text.trim().toUpperCase();
  return value.endsWith("H")
    ? parseInt(value.slice(0, -1), 16)
    : parseInt(value, 10);
}

Deno.test("startup LDIR clears stay inside their reserved tables", async () => {
  const reserved = new Map<string, number>();
  for (const source of await runtimeSources(runtimeRoot)) {
    for (const match of source.matchAll(/^(\w+):\s+DS\s+(\w+)/gm)) {
      reserved.set(match[1].toUpperCase(), number(match[2]));
    }
  }
  const startup = await Deno.readTextFile(
    join(runtimeRoot, "core", "startup.asm"),
  );
  const clear =
    /LD HL,(\w+)[^\n]*\n\s+LD DE,\1\+1[^\n]*\n\s+LD BC,(\w+)[^\n]*\n(?:\s+(?:XOR A|LD \(HL\),A)[^\n]*\n)*\s+LDIR/g;
  let checked = 0;
  for (const match of startup.matchAll(clear)) {
    const size = reserved.get(match[1].toUpperCase());
    if (size === undefined) continue;
    // LDIR from HL to HL+1 with BC=n writes n+1 bytes including the seed.
    assert.equal(
      number(match[2]) + 1,
      size,
      `${match[1]} clear covers ${number(match[2]) + 1} of ${size} bytes`,
    );
    checked++;
  }
  assert.ok(checked >= 5, `only ${checked} reserved-table clears were found`);
});
