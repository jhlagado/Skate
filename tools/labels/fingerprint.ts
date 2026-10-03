// Print image hashes and symbol tables for the runtime and compiler entries.
import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";
import { createHash } from "node:crypto";
const root = Deno.args[0];
const out: Record<string, unknown> = {};
for (
  const entry of [
    "src/runtime/image.asm",
    "src/compiler/scope/compiler.asm",
    "tests/cpm-effects.asm",
    "tests/origin.asm",
  ]
) {
  try {
    const r = await assembleAtomProject({
      root,
      entry,
      assembler: undefined,
      target: undefined,
      maxInstructions: 1_000_000_000,
      maxCycles: 10_000_000_000,
      sink: undefined,
    });
    const img = materializeAtomGeneration(r.generation)!;
    const hash = createHash("sha256").update(img.bytes).digest("hex");
    const syms = r.generation.symbols.map((
      s: { name: string; value: number },
    ) => [s.name.toUpperCase(), s.value]);
    out[entry] = {
      base: img.base,
      length: img.bytes.length,
      hash,
      symbols: syms,
    };
    console.error(
      entry,
      img.base,
      img.bytes.length,
      hash.slice(0, 16),
      syms.length,
    );
  } catch (e) {
    console.error(entry, "FAILED", String(e).slice(0, 300));
    out[entry] = { error: String(e) };
  }
}
console.log(JSON.stringify(out));
