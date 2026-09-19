/** Generate the checked C1 NOBJ template from the ATOM runtime payload. */

import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";
import { encodeNobj1 } from "@jhlagado/z80-tool-services";

const payloadBase = 0x0100;
const root = new URL("../../", import.meta.url);
const assembled = await assembleAtomProject({
  root: root.pathname,
  entry: "src/compiler/c1-runtime.asm",
  assembler: undefined,
  target: undefined,
  maxInstructions: 1_000_000_000,
  maxCycles: 10_000_000_000,
  sink: undefined,
});
const image = materializeAtomGeneration(assembled.generation);
if (!image) throw new Error("C1 runtime produced no image");
const payload = image.bytes.slice(payloadBase);
const symbols = new Map<string, number>(
  assembled.generation.symbols.map((
    symbol: { name: string; value: number },
  ) => [
    symbol.name.toLowerCase(),
    symbol.value,
  ]),
);
function offset(name: string): number {
  const value = symbols.get(name.toLowerCase());
  if (value === undefined) throw new Error(`C1 runtime has no ${name}`);
  return value - payloadBase;
}
const object = encodeNobj1({
  begin: { targetId: 1 },
  contracts: [],
  regions: [{
    id: 1,
    addressSpaceKey: "z80.cpu",
    storageKey: "cpm.ram",
    base: payloadBase,
    capacity: 0xe300,
    imageFill: 0,
    permissions: 7,
    banked: false,
  }],
  sections: [{
    id: 1,
    storageKind: 1,
    permissions: 7,
    alignment: 1,
    length: payload.length,
    runRegionId: 1,
    runPlacement: "fixed",
    runOffset: 0,
    loadPlacement: "same",
    loadRegionId: 1,
    loadOffset: 0,
    fill: 0,
  }],
  ranges: [],
  images: [{ sectionId: 1, offset: 0, bytes: payload }],
  patches: [],
  symbols: [{
    id: 1,
    binding: "local" as const,
    valueKind: 1,
    sectionId: 1,
    offset: 0,
  }],
  relocations: [],
  metadata: [],
  layout: { mode: "module" as const, entrySymbolId: 1 },
});
let cursor = 0;
let imageOffset = -1;
let crcOffset = -1;
while (cursor + 3 <= object.length) {
  const kind = object[cursor]!;
  const length = object[cursor + 1]! | object[cursor + 2]! << 8;
  if (kind === 6) imageOffset = cursor + 3 + 6;
  if (kind === 12) crcOffset = cursor + 3 + length - 2;
  cursor += 3 + length;
}
if (imageOffset < 0 || crcOffset < 0 || cursor !== object.length) {
  throw new Error("generated C1 NOBJ has invalid records");
}
const lines = [
  "; Generated from c1-runtime.asm. C1 patches operands and recomputes CRC.",
  `N4OBLEN EQU ${object.length}`,
  `N4IMGOF EQU ${imageOffset}`,
  `N4IMGLN EQU ${payload.length}`,
  `N4CRCLN EQU ${crcOffset}`,
  `N4CRCOF EQU ${crcOffset}`,
  `C1ROPOF EQU ${offset("C1ROP")}`,
  `C1RLTOF EQU ${offset("C1RLT")}`,
  `C1RLVOF EQU ${offset("C1RLV")}`,
  `C1RRTOF EQU ${offset("C1RRT")}`,
  `C1RRVOF EQU ${offset("C1RRV")}`,
  `C1RSTOF EQU ${offset("C1RSTART")}`,
  "N4OBJ:",
];
for (let index = 0; index < object.length; index += 16) {
  const bytes = [...object.slice(index, index + 16)].map((byte) =>
    `$${byte.toString(16).padStart(2, "0")}`
  );
  lines.push(`        DB ${bytes.join(",")}`);
}
lines.push("N4OBJEND:");
await Deno.writeTextFile(
  new URL("../../src/compiler/c1-template.inc", import.meta.url),
  lines.join("\n") + "\n",
);
console.log(
  `C1 template: ${payload.length} runtime bytes, ${object.length} NOBJ bytes`,
);
