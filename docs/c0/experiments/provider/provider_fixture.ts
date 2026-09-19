import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";
import { encodeNobj1, parseNobj1 } from "@jhlagado/z80-tool-services";
import {
  DEFAULT_SKATE_TPA_PROFILE,
  type SkateTpaProfile,
} from "../../../../tools/m7-compiler.ts";
import { type WritableSpan } from "./provider_memory.ts";

const projectRoot = fileURLToPath(new URL("../../../../", import.meta.url));
export const profile = DEFAULT_SKATE_TPA_PROFILE;
const runtime = { key: "org.skate.runtime", majorVersion: 2, minorVersion: 0 };
const region = {
  id: 1,
  addressSpaceKey: "z80.cpu",
  storageKey: "cpm.ram",
  base: 0x0100,
  capacity: 0xe300,
  imageFill: 0,
  permissions: 7,
  banked: false,
};
export const PROVIDER_BASE = 0x0100;
export const PROVIDER_END = 0x2a05;
export const PAYLOAD_END = 0x2ac4;
export const ROOTBASE = 0x3000;
export const ROOTEND = 0x3040;
export const ACTBASE = 0x3100;
export const ACTEND = 0x3180;
export const BMAPBASE = 0x3200;
export const BMAPBYTES = 0x400;
export const WORKBASE = 0x3600;
export const WORKEND = 0x3700;
export const WORKSPACE_BYTES = WORKEND - WORKBASE;
export const HEAPBASE = 0x3700;
export const HEAPCELLS = 0x2000;
export const HEAPBYTES = HEAPCELLS * 4;
export const STACKLOW = 0xd400;
export const STACKTOP = 0xe400;

export type Assembly = {
  readonly base: number;
  readonly bytes: Uint8Array;
  readonly symbols: ReadonlyMap<string, number>;
};

async function assemble(entry: string): Promise<Assembly> {
  const result = await assembleAtomProject({
    root: projectRoot,
    entry,
    assembler: undefined,
    target: undefined,
    maxInstructions: undefined,
    maxCycles: undefined,
    sink: undefined,
  });
  const image = materializeAtomGeneration(result.generation);
  if (image === undefined) {
    throw new Error(`ATOM produced no image for ${entry}`);
  }
  return {
    base: image.base,
    bytes: image.bytes,
    symbols: new Map(
      result.generation.symbols.map((
        symbol: { name: string; value: number },
      ) => [
        symbol.name.toUpperCase(),
        symbol.value,
      ]),
    ),
  };
}

export async function assembleFixture(): Promise<[Assembly, Assembly]> {
  return await Promise.all([
    assemble("docs/c0/experiments/provider/provider.asm"),
    assemble("docs/c0/experiments/provider/payload.asm"),
  ]);
}

export function address(assembly: Assembly, name: string): number {
  const value = assembly.symbols.get(name.toUpperCase());
  if (value === undefined) throw new Error(`ATOM omitted ${name}`);
  return value;
}

function sliceImage(assembly: Assembly, base: number, end: number): Uint8Array {
  const start = base - assembly.base;
  const finish = end - assembly.base;
  assert.ok(start >= 0 && finish <= assembly.bytes.length);
  return assembly.bytes.slice(start, finish);
}

export function word(bytes: Uint8Array, offset: number): number {
  return bytes[offset]! | (bytes[offset + 1]! << 8);
}

export function providerPrivateBytes(assembly: Assembly): number {
  return [
    ["HWORK", "HWEND"],
    ["GCWORK", "GCWEND"],
    ["F16WORK", "F16WEND"],
    ["NWORK", "NWEND"],
    ["RTWORK", "RTWEND"],
    ["RTLIPTR", "RTLIEND"],
  ].reduce(
    (n, [start, end]) =>
      n + address(assembly, end!) - address(assembly, start!),
    0,
  );
}

export function writableSpans(
  providerAssembly: Assembly,
  payloadAssembly: Assembly,
): WritableSpan[] {
  const privateSpans = [
    ["allocator state", "HWORK", "HWEND"],
    ["collector state", "GCWORK", "GCWEND"],
    ["binary16 state", "F16WORK", "F16WEND"],
    ["numeric state", "NWORK", "NWEND"],
    ["execution state", "RTWORK", "RTWEND"],
    ["literal scratch", "RTLIPTR", "RTLIEND"],
  ] as const;
  return [
    ...privateSpans.map(([name, start, end]) => ({
      name,
      start: address(providerAssembly, start),
      end: address(providerAssembly, end),
    })),
    {
      name: "payload input/result scratch",
      start: address(payloadAssembly, "INPUTL"),
      end: address(payloadAssembly, "PAYEND"),
    },
    { name: "roots", start: ROOTBASE, end: ROOTEND },
    { name: "activations", start: ACTBASE, end: ACTEND },
    { name: "bitmap", start: BMAPBASE, end: BMAPBASE + BMAPBYTES },
    { name: "workspace", start: WORKBASE, end: WORKEND },
    { name: "heap", start: HEAPBASE, end: HEAPBASE + HEAPBYTES },
  ];
}

export const providerServices = [
  ["numeric.classify", "PVNCLS", "NCLASS"],
  ["numeric.add", "PVNADD", "NADD"],
  ["numeric.sub", "PVNSUB", "NSUB"],
  ["numeric.mul", "PVNMUL", "NMUL"],
  ["numeric.div", "PVNDIV", "NDIV"],
  ["numeric.negate", "PVNNEG", "NNEG"],
  ["heap.initialize", "PVHINI", "HINIT"],
  ["collector.configure", "PVGCST", "GCSET"],
  ["execution.initialize", "PVRTIN", "RTINIT"],
  ["execution.packet-new", "PVPKNW", "RTPKNEW"],
  ["execution.invoke", "PVRTIVO", "RTINVOKE"],
  ["pairs.cons", "PVCONS", "RTCONSP"],
  ["execution.literal-init", "PVLIT", "RTLIT"],
] as const;

export function providerObject(assembly: Assembly) {
  const symbols = [
    {
      id: 1,
      binding: "local" as const,
      valueKind: 1 as const,
      sectionId: 1,
      offset: address(assembly, "PVENTRY") - PROVIDER_BASE,
    },
    ...providerServices.map(([_, vector], index) => ({
      id: index + 2,
      binding: "local" as const,
      valueKind: 1 as const,
      sectionId: 1,
      offset: address(assembly, vector) - PROVIDER_BASE,
    })),
    ...providerServices.map(([_, __, target], index) => ({
      id: index + 15,
      binding: "local" as const,
      valueKind: 1 as const,
      sectionId: 1,
      offset: address(assembly, target) - PROVIDER_BASE,
    })),
    {
      id: 28,
      binding: "import" as const,
      valueKind: 1 as const,
      namespace: "skate.generated",
      name: "entry",
    },
  ];
  const relocations = [
    {
      siteSectionId: 1,
      siteOffset: 1,
      kind: 1 as const,
      use: 1 as const,
      targetSymbolId: 28,
      addend: 0,
    },
    ...providerServices.map(([_, vector], index) => ({
      siteSectionId: 1,
      siteOffset: address(assembly, vector) - PROVIDER_BASE + 1,
      kind: 1 as const,
      use: 1 as const,
      targetSymbolId: index + 15,
      addend: 0,
    })),
  ];
  return parseNobj1(encodeNobj1({
    begin: { targetId: 1 },
    contracts: [{ id: 1, ...runtime, data: new Uint8Array(4) }],
    regions: [region],
    sections: [{
      id: 1,
      storageKind: 1,
      permissions: 7,
      alignment: 1,
      length: PROVIDER_END - PROVIDER_BASE,
      runRegionId: 1,
      runPlacement: "fixed",
      runOffset: 0,
      loadPlacement: "same",
      loadRegionId: 1,
      loadOffset: 0,
      fill: 0,
    }],
    ranges: [],
    images: [{
      sectionId: 1,
      offset: 0,
      bytes: sliceImage(assembly, PROVIDER_BASE, PROVIDER_END),
    }],
    patches: [],
    symbols,
    relocations,
    metadata: [],
    layout: { mode: "module", entrySymbolId: 0 },
  }));
}

export function payloadObject(
  assembly: Assembly,
  workspaceBase = WORKBASE,
  heapBase = HEAPBASE,
) {
  const callSites: number[] = [];
  const bytes = sliceImage(assembly, PROVIDER_END, PAYLOAD_END);
  for (let offset = 0; offset + 2 < bytes.length; offset += 1) {
    if (
      bytes[offset] === 0xcd && bytes[offset + 1] === 0 &&
      bytes[offset + 2] === 0
    ) {
      callSites.push(offset + 1);
    }
  }
  assert.equal(callSites.length, 4, "payload has four service CALL sites");
  const keys = [
    "heap.initialize",
    "collector.configure",
    "execution.initialize",
    "numeric.add",
  ];
  const symbols = [
    {
      id: 1,
      binding: "export" as const,
      valueKind: 1 as const,
      sectionId: 1,
      offset: 0,
      namespace: "skate.generated",
      name: "entry",
    },
    ...keys.map((serviceKey, index) => ({
      id: index + 2,
      binding: "service-import" as const,
      valueKind: 1 as const,
      contractId: 1,
      serviceKey,
    })),
  ];
  const sections = [
    {
      id: 1,
      storageKind: 1 as const,
      permissions: 7,
      alignment: 1,
      length: PAYLOAD_END - PROVIDER_END,
      runRegionId: 1,
      runPlacement: "fixed" as const,
      runOffset: PROVIDER_END - PROVIDER_BASE,
      loadPlacement: "same" as const,
      loadRegionId: 1,
      loadOffset: 0,
      fill: 0,
    },
    zeroSection(2, ROOTBASE, ROOTEND - ROOTBASE),
    zeroSection(3, ACTBASE, ACTEND - ACTBASE),
    zeroSection(4, BMAPBASE, BMAPBYTES),
    zeroSection(5, heapBase, HEAPBYTES),
    zeroSection(6, workspaceBase, WORKEND - WORKBASE),
  ];
  return parseNobj1(encodeNobj1({
    begin: { targetId: 1 },
    contracts: [{ id: 1, ...runtime, data: Uint8Array.of(1, 0, 1, 0) }],
    regions: [region],
    sections,
    ranges: [{
      id: 1,
      sectionId: 1,
      view: "run",
      offset: address(assembly, "BOOTDESC") - PROVIDER_END,
      length: 40,
    }],
    images: [{ sectionId: 1, offset: 0, bytes }],
    patches: [],
    symbols,
    relocations: callSites.map((siteOffset, index) => ({
      siteSectionId: 1,
      siteOffset,
      kind: 1 as const,
      use: 1 as const,
      targetSymbolId: index + 2,
      addend: 0,
    })),
    metadata: [],
    layout: { mode: "module", entrySymbolId: 1 },
  }));
}

function zeroSection(id: number, base: number, length: number) {
  return {
    id,
    storageKind: 2 as const,
    permissions: 3,
    alignment: 1,
    length,
    runRegionId: 1,
    runPlacement: "fixed" as const,
    runOffset: base - PROVIDER_BASE,
    fill: 0,
  };
}

export function linkOptions(allocationBase = WORKBASE, heapBase = HEAPBASE) {
  return {
    mainObjectId: "payload",
    profile,
    providers: [{
      id: "prepared-runtime-v2",
      objectId: "provider",
      supports: [runtime],
      services: providerServices.map(([key], index) => ({
        contract: runtime,
        key,
        symbolId: index + 2,
      })),
    }],
    allocations: [{
      objectId: "payload",
      roots: { address: ROOTBASE, bytes: ROOTEND - ROOTBASE },
      activations: { address: ACTBASE, bytes: ACTEND - ACTBASE },
      bitmap: { address: BMAPBASE, bytes: BMAPBYTES },
      heap: { address: heapBase, bytes: HEAPBYTES },
      workspace: [{ address: allocationBase, bytes: WORKEND - WORKBASE }],
      stack: { address: STACKLOW, bytes: STACKTOP - STACKLOW },
    }],
  };
}

function extentMap() {
  return [
    ["provider image", PROVIDER_BASE, PROVIDER_END],
    ["payload code/static data", PROVIDER_END, PAYLOAD_END],
    ["roots", ROOTBASE, ROOTEND],
    ["activations", ACTBASE, ACTEND],
    ["bitmap", BMAPBASE, BMAPBASE + BMAPBYTES],
    ["workspace", WORKBASE, WORKEND],
    ["heap", HEAPBASE, HEAPBASE + HEAPBYTES],
    ["guarded stack", STACKLOW, STACKTOP],
  ] as const;
}

export function assertMap(profileToCheck: SkateTpaProfile) {
  const extents = extentMap();
  for (const [name, start, end] of extents) {
    assert.ok(start >= profileToCheck.base, `${name} below TPA`);
    assert.ok(
      end <= profileToCheck.base + profileToCheck.capacity,
      `${name} above TPA`,
    );
  }
  const sorted = [...extents].sort((left, right) => left[1] - right[1]);
  for (let index = 1; index < sorted.length; index += 1) {
    assert.ok(
      sorted[index - 1]![2] <= sorted[index]![1],
      "map extents overlap",
    );
  }
  assert.equal(HEAPBASE, WORKEND, "heap starts at measured workspace end");
  assert.equal(STACKLOW - WORKEND, 0x9d00, "derived pre-stack heap window");
  assert.equal(
    STACKLOW - (HEAPBASE + HEAPBYTES),
    0x1d00,
    "unallocated guard-side headroom after maximum heap",
  );
}
