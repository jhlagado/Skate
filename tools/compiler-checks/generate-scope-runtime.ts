/** Generate the checked runtime byte table used by the scope compiler. */

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
  `RT_STD EQU ${offset("IO_START")}`,
  `RT_CALLP EQU ${offset("RT_CALL") + 1}`,
  `RT_LOAD EQU ${address("RT_LOAD")}`,
  `QT_CACHE EQU ${address("QT_CACHE")}`,
  `RT_STORE EQU ${address("RT_STORE")}`,
  `RT_SET EQU ${address("RT_SET")}`,
  `RT_TEST EQU ${address("RT_TEST")}`,
  `RT_ADD EQU ${address("RT_ADD")}`,
  `RT_SUB EQU ${address("RT_SUB")}`,
  `RT_MUL EQU ${address("RT_MUL")}`,
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
  `ROOT_ADD EQU ${address("ROOT_ADD")}`,
  `ROOT_CUT EQU ${address("ROOT_CUT")}`,
  `ROOT_POP EQU ${address("ROOT_POP")}`,
  `EC_CALL EQU ${address("EC_CALL")}`,
  `INV_TAIL EQU ${address("INV_TAIL")}`,
  `INV_TC EQU ${address("INV_TC")}`,
  `FRM_LOAD EQU ${address("FRM_LOAD")}`,
  `FRM_INIT EQU ${address("FRM_INIT")}`,
  `FRM_SET EQU ${address("FRM_SET")}`,
  `FRM_CLR EQU ${address("FRM_CLR")}`,
  `RT_CLR EQU ${address("RT_CLR")}`,
  `HEAP_LIM EQU ${address("HEAP_LIM")}`,
  `RT_LIMIT EQU ${offset("RT_LIMIT")}`,
  `G_BASE EQU ${offset("G_BASE")}`,
  `G_END EQU ${offset("G_END")}`,
  `QT_START EQU ${offset("QT_START")}`,
  `QT_STOP EQU ${offset("QT_STOP")}`,
  `DR_DIR EQU ${offset("DR_DIR")}`,
  `DR_DEND EQU ${offset("DR_DEND")}`,
  `RT_LOWSP EQU ${address("RT_LOWSP")}`,
  `NUM_ZERO EQU ${address("NUM_ZERO")}`,
  `OUT_SHOW EQU ${address("OUT_SHOW")}`,
  `QT_PUSH EQU ${address("QT_PUSH")}`,
  `QT_FOLD EQU ${address("QT_FOLD")}`,
  `CONS EQU ${address("CONS")}`,
  `CAR EQU ${address("CAR")}`,
  `CDR EQU ${address("CDR")}`,
  `PAIR_IS EQU ${address("PAIR_IS")}`,
  `PAIR_NIL EQU ${address("PAIR_NIL")}`,
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
await Deno.writeTextFile(
  new URL(
    "../../src/runtime/values.inc",
    import.meta.url,
  ),
  values.join("\n") + "\n",
);
await Deno.writeTextFile(
  new URL(
    "../../src/runtime/template.inc",
    import.meta.url,
  ),
  lines.join("\n") + "\n",
);
console.log(`Scope-control runtime template: ${payload.length} bytes`);
