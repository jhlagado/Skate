/**
 * Generate the checked runtime byte table used by the scope compiler.
 *
 * With `--check`, compare the committed files with a fresh generation instead
 * of writing them, and fail when either has drifted from the runtime source.
 */

import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";
import { probeDefinitions } from "../../tests/z80.ts";

const root = new URL("../../", import.meta.url);
const assembled = await assembleAtomProject({
  root: root.pathname,
  entry: "src/runtime/image.asm",
  definitions: probeDefinitions(root.pathname),
  assembler: undefined,
  target: undefined,
  maxInstructions: 1_000_000_000,
  maxCycles: 10_000_000_000,
  sink: undefined,
});
const image = materializeAtomGeneration(assembled.generation);
if (!image) throw new Error("scope-control runtime produced no image");
const payload = image.bytes.slice(0x0100);
const symbols = new Map<string, number>(
  assembled.generation.symbols.map((symbol: {
    name: string;
    value: number;
  }) => [symbol.name.toLowerCase(), symbol.value]),
);

function address(name: string): number {
  const value = symbols.get(name.toLowerCase());
  if (value === undefined) {
    throw new Error(`scope-control runtime has no ${name}`);
  }
  return value;
}

function offset(name: string): number {
  return address(name) - 0x0100;
}

const values = [
  "; Runtime addresses used by the scope-control compiler.",
  `RT_SIZE EQU ${payload.length}`,
  `RT_CORE EQU ${offset("STD_MOD")}`,
  `RT_STD EQU ${offset("NUM_MOD")}`,
  `RT_NUMS EQU ${offset("IO_START")}`,
  `RT_CALLP EQU ${offset("RT_CALL") + 1}`,
  `RT_LOAD EQU ${address("RT_LOAD")}`,
  `RT_STORE EQU ${address("RT_STORE")}`,
  `RT_SET EQU ${address("RT_SET")}`,
  `RT_TEST EQU ${address("RT_TEST")}`,
  `HEAP_LAM EQU ${address("HEAP_LAM")}`,
  `INV_CALL EQU ${address("INV_CALL")}`,
  `INV_OP EQU ${address("INV_OP")}`,
  `INV_OPTL EQU ${address("INV_OPTL")}`,
  `INV_OPTC EQU ${address("INV_OPTC")}`,
  `OPS_PUSH EQU ${address("OPS_PUSH")}`,
  `OPS_POP EQU ${address("OPS_POP")}`,
  `STD_CASE EQU ${address("STD_CASE")}`,
  `QT_BUILD EQU ${address("QT_BUILD")}`,
  `ARG_PUSH EQU ${address("ARG_PUSH")}`,
  `ARG_POP EQU ${address("ARG_POP")}`,
  `PRIM_OP EQU ${address("PRIM_OP")}`,
  `PRIM_TL EQU ${address("PRIM_TL")}`,
  `G_LOAD EQU ${address("G_LOAD")}`,
  `G_OPSH EQU ${address("G_OPSH")}`,
  `G_STORE EQU ${address("G_STORE")}`,
  `G_SET EQU ${address("G_SET")}`,
  `L_LOAD EQU ${address("L_LOAD")}`,
  `L_STORE EQU ${address("L_STORE")}`,
  `L_SET EQU ${address("L_SET")}`,
  `EC_CALL EQU ${address("EC_CALL")}`,
  `INV_TAIL EQU ${address("INV_TAIL")}`,
  `INV_TC EQU ${address("INV_TC")}`,
  `FRM_CLR EQU ${address("FRM_CLR")}`,
  `RT_CLR EQU ${address("RT_CLR")}`,
  `RT_LIMIT EQU ${offset("RT_LIMIT")}`,
  `RT_LOEND EQU ${address("RT_LOEND")}`,
  `G_BASE EQU ${offset("G_BASE")}`,
  `G_END EQU ${offset("G_END")}`,
  `QT_START EQU ${offset("QT_START")}`,
  `QT_STOP EQU ${offset("QT_STOP")}`,
  `DR_DIR EQU ${offset("DR_DIR")}`,
  `DR_DEND EQU ${offset("DR_DEND")}`,
  `OUT_SHOW EQU ${address("OUT_SHOW")}`,
  `QT_PUSH EQU ${address("QT_PUSH")}`,
];
const lines = [
  "; Runtime image generated from image.asm.",
  "RT_IMAGE:",
];
for (let index = 0; index < payload.length; index += 32) {
  const bytes = [...payload.slice(index, index + 32)].map((byte) =>
    `$${byte.toString(16).padStart(2, "0")}`
  );
  lines.push(`        DB ${bytes.join(",")}`);
}
lines.push("RT_IEND:");
const outputs: [string, string][] = [
  ["src/runtime/values.inc", values.join("\n") + "\n"],
  ["src/runtime/template.inc", lines.join("\n") + "\n"],
];

async function readOptional(url: URL): Promise<string | undefined> {
  try {
    return await Deno.readTextFile(url);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
}

if (Deno.args.includes("--check")) {
  const stale = [];
  for (const [path, text] of outputs) {
    if (await readOptional(new URL(path, root)) !== text) stale.push(path);
  }
  if (stale.length > 0) {
    console.error(
      `Generated runtime files are out of date: ${stale.join(", ")}\n` +
        "Run `deno task runtime` and commit the result.",
    );
    Deno.exit(1);
  }
  console.log(
    `Scope-control runtime template is current: ${payload.length} bytes`,
  );
} else {
  for (const [path, text] of outputs) {
    await Deno.writeTextFile(new URL(path, root), text);
  }
  console.log(`Scope-control runtime template: ${payload.length} bytes`);
}
