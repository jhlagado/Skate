/** Generate the checked runtime byte table used by the scope compiler. */

import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";

const root = new URL("../../", import.meta.url);
const assembled = await assembleAtomProject({
  root: root.pathname,
  entry: "src/compiler/scope-control-runtime-image.asm",
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
  `SRTLEN EQU ${payload.length}`,
  `SRTCLP EQU ${offset("SRTCALL") + 1}`,
  `SRTLDA EQU ${address("SRTLOAD")}`,
  `SRTQGET EQU ${address("SRTQGET")}`,
  `SRTSTA EQU ${address("SRTSTORE")}`,
  `SRTSETS EQU ${address("SRTSET")}`,
  `SRTFAL EQU ${address("SRTFALSE")}`,
  `SRTADD EQU ${address("SRTADD")}`,
  `SRTSUB EQU ${address("SRTSUB")}`,
  `SRTMUL EQU ${address("SRTMUL")}`,
  `SRTMAKE EQU ${address("SRTMAKE")}`,
  `SRTINVOK EQU ${address("SRTINVOK")}`,
  `SRTOPINV EQU ${address("SRTOPINV")}`,
  `SRTOTAIL EQU ${address("SRTOTAIL")}`,
  `SRTOTCL EQU ${address("SRTOTCL")}`,
  `SRTOPUSH EQU ${address("SRTOPUSH")}`,
  `SRTNROOT EQU ${address("SRTNROOT")}`,
  `SRTNPOPB EQU ${address("SRTNPOPB")}`,
  `SRTNPOP1 EQU ${address("SRTNPOP1")}`,
  `SRTTAIL EQU ${address("SRTTAIL")}`,
  `SRTTCALL EQU ${address("SRTTCALL")}`,
  `SRTLOADI EQU ${address("SRTLOADI")}`,
  `SRTSTORI EQU ${address("SRTSTORI")}`,
  `SRTSETI EQU ${address("SRTSETI")}`,
  `SRTCLRI EQU ${address("SRTCLRI")}`,
  `SRTCLRS EQU ${address("SRTCLRS")}`,
  `SRTHEP EQU ${address("SRTHEAPP")}`,
  `SRTIMGE EQU ${offset("SRTIMGE")}`,
  `SRTGBASE EQU ${offset("SRTGBASE")}`,
  `SRTGEND EQU ${offset("SRTGEND")}`,
  `SRTQROOT EQU ${offset("SRTQROOT")}`,
  `SRTQENDR EQU ${offset("SRTQENDR")}`,
  `SRTLOW EQU ${address("SRTLOWSP")}`,
  `SRTZERO EQU ${address("SRTZERO")}`,
  `SRTPRI EQU ${address("SRTPRINT")}`,
  `SRTQPUT EQU ${address("SRTQPUT")}`,
  `SRTQBLD EQU ${address("SRTQBLD")}`,
  `SRTCONS EQU ${address("SRTCONS")}`,
  `SRTCAR EQU ${address("SRTCAR")}`,
  `SRTCDR EQU ${address("SRTCDR")}`,
  `SRTPAIRP EQU ${address("SRTPAIRP")}`,
  `SRTNULLP EQU ${address("SRTNULLP")}`,
];
const lines = [
  "; Runtime image generated from scope-control-runtime-image.asm.",
  "SRTIMAGE:",
];
for (let index = 0; index < payload.length; index += 32) {
  const bytes = [...payload.slice(index, index + 32)].map((byte) =>
    `$${byte.toString(16).padStart(2, "0")}`
  );
  lines.push(`        DB ${bytes.join(",")}`);
}
lines.push("SRTIEND:");
await Deno.writeTextFile(
  new URL(
    "../../src/compiler/scope-control-runtime-values.inc",
    import.meta.url,
  ),
  values.join("\n") + "\n",
);
await Deno.writeTextFile(
  new URL(
    "../../src/compiler/scope-control-runtime-template.inc",
    import.meta.url,
  ),
  lines.join("\n") + "\n",
);
console.log(`Scope-control runtime template: ${payload.length} bytes`);
