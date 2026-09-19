import assert from "node:assert/strict";
import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";
import { fileURLToPath } from "node:url";
import { linkSkateObjects } from "../../../../tools/link.ts";
import { SKATE_TPA_PROFILES } from "../../../../tools/m7-compiler.ts";
import { runObserved, type WritableSpan } from "../provider/provider_memory.ts";
import { encodeNobj1, parseNobj1 } from "@jhlagado/z80-tool-services";

const ROOT = fileURLToPath(new URL("../../../../", import.meta.url));
const PROVIDER_ENTRY = "docs/c0/experiments/binary16/provider-integer.asm";
const PAYLOAD_ENTRY = "docs/c0/experiments/binary16/payload-integer.asm";
export const PROVIDER_BASE = 0x0100;
export const PAYLOAD_BASE = 0x2a05;
export const ROOTBASE = 0x3000;
export const ROOTEND = 0x3040;
export const ACTBASE = 0x3100;
export const ACTEND = 0x3180;
export const BMAPBASE = 0x3200;
export const BMAPBYTES = 0x400;
export const WORKBASE = 0x3600;
export const WORKEND = 0x3700;
export const HEAPBASE = 0x3700;
export const HEAPBYTES = 0x2000 * 4;
export const STACKLOW = 0xd400;
export const STACKTOP = 0xe400;
const runtime = {
  key: "org.skate.runtime",
  majorVersion: 2,
  minorVersion: 0,
};
const services = [
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

export interface Assembly {
  readonly bytes: Uint8Array;
  readonly address: (name: string) => number;
}

export async function assemble(entry: string): Promise<Assembly> {
  const result = await assembleAtomProject({
    root: ROOT,
    entry,
    assembler: undefined,
    target: undefined,
    maxInstructions: 1_000_000_000,
    maxCycles: 10_000_000_000,
    sink: undefined,
  });
  const image = materializeAtomGeneration(result.generation);
  if (!image) throw new Error(`ATOM produced no image for ${entry}`);
  const symbols = new Map(
    result.generation.symbols.map((s: { name: string; value: number }) => [
      s.name.toLowerCase(),
      s.value,
    ]),
  );
  return {
    bytes: image.bytes,
    address(name: string): number {
      const value = symbols.get(name.toLowerCase());
      if (typeof value !== "number") throw new Error(`ATOM omitted ${name}`);
      return value;
    },
  };
}

function slice(assembly: Assembly, start: number, end: number): Uint8Array {
  const base = assembly.bytes.length === 0 ? 0 : 0;
  assert.ok(start >= base && end <= assembly.bytes.length);
  return assembly.bytes.slice(start, end);
}

export function privateBytes(assembly: Assembly): number {
  return [
    ["HWORK", "HWEND"],
    ["GCWORK", "GCWEND"],
    ["NWORK", "NWEND"],
    ["RTWORK", "RTWEND"],
    ["RTLIPTR", "RTLIEND"],
  ].reduce(
    (bytes, [start, end]) =>
      bytes + assembly.address(end) - assembly.address(start),
    0,
  );
}

function providerObject(assembly: Assembly) {
  const end = assembly.address("PVEND");
  const symbols = [
    {
      id: 1,
      binding: "local" as const,
      valueKind: 1 as const,
      sectionId: 1,
      offset: assembly.address("PVENTRY") - PROVIDER_BASE,
    },
    ...services.map(([_, vector], index) => ({
      id: index + 2,
      binding: "local" as const,
      valueKind: 1 as const,
      sectionId: 1,
      offset: assembly.address(vector) - PROVIDER_BASE,
    })),
    ...services.map(([_, __, target], index) => ({
      id: index + 15,
      binding: "local" as const,
      valueKind: 1 as const,
      sectionId: 1,
      offset: assembly.address(target) - PROVIDER_BASE,
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
    ...services.map(([_, vector], index) => ({
      siteSectionId: 1,
      siteOffset: assembly.address(vector) - PROVIDER_BASE + 1,
      kind: 1 as const,
      use: 1 as const,
      targetSymbolId: index + 15,
      addend: 0,
    })),
  ];
  return parseNobj1(encodeNobj1({
    begin: { targetId: 1 },
    contracts: [{ id: 1, ...runtime, data: new Uint8Array(4) }],
    regions: [{
      id: 1,
      addressSpaceKey: "z80.cpu",
      storageKey: "cpm.ram",
      base: PROVIDER_BASE,
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
      length: end - PROVIDER_BASE,
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
      bytes: slice(assembly, PROVIDER_BASE, end),
    }],
    patches: [],
    symbols,
    relocations,
    metadata: [],
    layout: { mode: "module", entrySymbolId: 0 },
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

function payloadObject(assembly: Assembly) {
  const end = assembly.address("PAYEND");
  const bytes = slice(assembly, PAYLOAD_BASE, end);
  const callSites: number[] = [];
  for (let offset = 0; offset + 2 < bytes.length; offset++) {
    if (bytes[offset] === 0xcd && bytes[offset + 1] === 0) {
      callSites.push(offset + 1);
    }
  }
  assert.equal(callSites.length, 4);
  const keys = [
    "heap.initialize",
    "collector.configure",
    "execution.initialize",
    "numeric.add",
  ];
  return parseNobj1(encodeNobj1({
    begin: { targetId: 1 },
    contracts: [{ id: 1, ...runtime, data: Uint8Array.of(1, 0, 1, 0) }],
    regions: [{
      id: 1,
      addressSpaceKey: "z80.cpu",
      storageKey: "cpm.ram",
      base: PROVIDER_BASE,
      capacity: 0xe300,
      imageFill: 0,
      permissions: 7,
      banked: false,
    }],
    sections: [
      {
        id: 1,
        storageKind: 1 as const,
        permissions: 7,
        alignment: 1,
        length: end - PAYLOAD_BASE,
        runRegionId: 1,
        runPlacement: "fixed" as const,
        runOffset: PAYLOAD_BASE - PROVIDER_BASE,
        loadPlacement: "same" as const,
        loadRegionId: 1,
        loadOffset: 0,
        fill: 0,
      },
      zeroSection(2, ROOTBASE, ROOTEND - ROOTBASE),
      zeroSection(3, ACTBASE, ACTEND - ACTBASE),
      zeroSection(4, BMAPBASE, BMAPBYTES),
      zeroSection(5, HEAPBASE, HEAPBYTES),
      zeroSection(6, WORKBASE, WORKEND - WORKBASE),
    ],
    ranges: [{
      id: 1,
      sectionId: 1,
      view: "run" as const,
      offset: assembly.address("BOOTDESC") - PAYLOAD_BASE,
      length: 40,
    }],
    images: [{ sectionId: 1, offset: 0, bytes }],
    patches: [],
    symbols: [
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
    ],
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

export async function integerProof() {
  const [providerAssembly, payloadAssembly] = await Promise.all([
    assemble(PROVIDER_ENTRY),
    assemble(PAYLOAD_ENTRY),
  ]);
  const linked = linkSkateObjects([
    { id: "provider", bytes: providerObject(providerAssembly).serialized },
    { id: "payload", bytes: payloadObject(payloadAssembly).serialized },
  ], {
    mainObjectId: "payload",
    profile: SKATE_TPA_PROFILES["cpm-64k"],
    providers: [{
      id: "integer-runtime-v2",
      objectId: "provider",
      supports: [runtime],
      services: services.map(([key], index) => ({
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
      heap: { address: HEAPBASE, bytes: HEAPBYTES },
      workspace: [{ address: WORKBASE, bytes: WORKEND - WORKBASE }],
      stack: { address: STACKLOW, bytes: STACKTOP - STACKLOW },
    }],
  });
  const region = linked.regions.find(({ targetRegionId }) =>
    targetRegionId === SKATE_TPA_PROFILES["cpm-64k"].id
  );
  assert.ok(region);
  const privateSpans = [
    ["allocator", "HWORK", "HWEND"],
    ["collector", "GCWORK", "GCWEND"],
    ["numeric", "NWORK", "NWEND"],
    ["execution", "RTWORK", "RTWEND"],
    ["literal", "RTLIPTR", "RTLIEND"],
  ] as const;
  const allowed: WritableSpan[] = privateSpans.map(([name, start, end]) => ({
    name,
    start: providerAssembly.address(start),
    end: providerAssembly.address(end),
  }));
  allowed.push(
    {
      name: "payload scratch",
      start: payloadAssembly.address("INPUTL"),
      end: payloadAssembly.address("PAYEND"),
    },
    { name: "roots", start: ROOTBASE, end: ROOTEND },
    { name: "activations", start: ACTBASE, end: ACTEND },
    { name: "bitmap", start: BMAPBASE, end: BMAPBASE + BMAPBYTES },
    { name: "workspace", start: WORKBASE, end: WORKEND },
    { name: "heap", start: HEAPBASE, end: HEAPBASE + HEAPBYTES },
  );
  const runs = [41, 100].map((left, index) =>
    runObserved(region!, {
      entry: linked.entry!.address,
      left,
      right: index === 0 ? 1 : 23,
      stackLow: STACKLOW,
      stackTop: STACKTOP,
      allowedSpans: allowed,
    })
  );
  for (const run of runs) {
    assert.equal(
      run.cpu.a,
      3,
      `result A=${run.cpu.a} HL=${(run.cpu.h * 256 + run.cpu.l).toString(16)}`,
    );
    assert.equal(run.cpu.flags.C, 0);
    assert.equal(run.cpu.sp, STACKTOP);
    assert.equal(run.violations.length, 0, run.violations.join("; "));
    assert.equal(run.canariesIntact, true);
  }
  assert.equal(runs[0]!.cpu.h * 256 + runs[0]!.cpu.l, 42);
  assert.equal(runs[1]!.cpu.h * 256 + runs[1]!.cpu.l, 123);
  return {
    providerAssembly,
    payloadAssembly,
    providerBytes: providerAssembly.address("PVEND") - PROVIDER_BASE,
    payloadBytes: payloadAssembly.address("PAYEND") - PAYLOAD_BASE,
    privateBytes: privateBytes(providerAssembly),
    stackBytes: Math.max(...runs.map((run) => STACKTOP - run.stackLowWater)),
    runs: runs.map((run) => ({
      result: run.cpu.h * 256 + run.cpu.l,
      tag: run.cpu.a,
      carry: run.cpu.flags.C ? 1 : 0,
      writeCount: run.writeCount,
      stackWrites: run.stackWrites,
      stackLowWater: run.stackLowWater,
      violations: run.violations.length,
      canariesIntact: run.canariesIntact,
    })),
    linkedBytes:
      linked.regions.find(({ targetRegionId }) =>
        targetRegionId === SKATE_TPA_PROFILES["cpm-64k"].id
      )!.bytes.length,
  };
}
