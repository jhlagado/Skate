import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";
// @deno-types="../../atom/node_modules/@jhlagado/debug80-runtime/dist/index.d.ts"
import { createZ80Runtime } from "@jhlagado/debug80-runtime";
// @deno-types="../../atom/node_modules/@jhlagado/z80-tool-services/dist/index.d.ts"
import {
  encodeNobj1,
  linkNobj1,
  parseNobj1,
} from "@jhlagado/z80-tool-services";
import { loadAssembly } from "./z80.ts";

const projectRoot = fileURLToPath(new URL("../", import.meta.url));
const runtimeContract = {
  key: "org.skate.runtime",
  majorVersion: 2,
  minorVersion: 0,
};
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

async function assemble(entry: string) {
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
  if (!image) throw new Error(`ATOM produced no image for ${entry}`);
  const symbols = new Map<string, number>(
    result.generation.symbols.map((symbol: { name: string; value: number }) => [
      symbol.name.toLowerCase(),
      symbol.value,
    ]),
  );
  return { image, symbols };
}

function word(bytes: Uint8Array, offset: number) {
  return bytes[offset]! | (bytes[offset + 1]! << 8);
}

function providerObject(
  image: { base: number; bytes: Uint8Array },
  symbols: ReadonlyMap<string, number>,
) {
  const serviceNames = [
    "nclass",
    "nadd",
    "nsub",
    "nmul",
    "ndiv",
    "nneg",
    "hinit",
    "gcset",
    "rtinit",
    "rtpknew",
    "rtinvoke",
    "rtconsp",
    "rtlit",
  ];
  const serialized = encodeNobj1({
    begin: { targetId: 1 },
    contracts: [{ id: 1, ...runtimeContract, data: new Uint8Array(4) }],
    regions: [region],
    sections: [{
      id: 1,
      storageKind: 1,
      permissions: 7,
      alignment: 1,
      length: image.bytes.length,
      runRegionId: 1,
      runPlacement: "fixed",
      runOffset: image.base - region.base,
      loadPlacement: "same",
      loadRegionId: 1,
      loadOffset: 0,
      fill: 0,
    }],
    ranges: [],
    images: [{ sectionId: 1, offset: 0, bytes: image.bytes.slice() }],
    patches: [],
    symbols: serviceNames.map((name, index) => ({
      id: index + 1,
      binding: "local" as const,
      valueKind: 1,
      sectionId: 1,
      offset: symbols.get(name)! - image.base,
    })),
    relocations: [],
    metadata: [],
    layout: { mode: "module", entrySymbolId: 1 },
  });
  return parseNobj1(serialized);
}

function linkedTarget() {
  return {
    regions: [region].map((item) => ({
      id: "cpm-ram",
      addressSpaceKey: item.addressSpaceKey,
      storageKey: item.storageKey,
      base: item.base,
      capacity: item.capacity,
      imageFill: item.imageFill,
      permissions: item.permissions,
      banked: item.banked,
    })),
    visibility: [],
  };
}

function executeGeneratedSlot(
  bytes: Uint8Array,
  base: number,
  entry: number,
  leftTag: number,
  leftPayload: number,
  rightTag: number,
  rightPayload: number,
) {
  const memory = new Uint8Array(0x10000);
  memory.set(bytes, base);
  memory[0xf000] = 0;
  memory[0xf001] = 0xff;
  const runtime = createZ80Runtime({ memory, startAddress: entry });
  const { cpu } = runtime;
  cpu.pc = entry;
  cpu.sp = 0xf000;
  cpu.a = leftTag;
  cpu.b = rightTag;
  cpu.h = leftPayload >>> 8;
  cpu.l = leftPayload & 0xff;
  cpu.d = rightPayload >>> 8;
  cpu.e = rightPayload & 0xff;
  cpu.ix = 0x1357;
  cpu.iy = 0x2468;
  let steps = 0;
  while (cpu.pc !== 0xff00) {
    assert.ok(++steps <= 20_000, "linked generated slot did not return");
    assert.ok(!runtime.isHalted(), "linked generated slot halted");
    runtime.step();
  }
  assert.equal(cpu.sp, 0xf002);
  assert.equal(cpu.ix, 0x1357);
  assert.equal(cpu.iy, 0x2468);
  return { tag: cpu.a, value: cpu.h * 256 + cpu.l, carry: cpu.flags.C };
}

function executeLinkedEntry(
  bytes: Uint8Array,
  base: number,
  entry: number,
  leftWorkspace: number,
  rightWorkspace: number,
  captureOutput = false,
) {
  const memory = new Uint8Array(0x10000);
  memory.set(bytes, base);
  // A tiny CP/M boundary: BDOS function 2 appends E to a scratch buffer and
  // function 0 exits to the host sentinel.  This lets the startup proof tell
  // runtime `write` output from the old compiler-side message path.
  memory[0] = 0xc3;
  memory[1] = 0;
  memory[2] = 0xff;
  memory.set([
    0x79, // LD A,C
    0xb7, // OR A
    0xca,
    0x00,
    0xff, // JP Z,FF00H (warm boot)
    0x3a,
    0xff,
    0xf0, // LD A,(F0FFH), current output length
    0x6f, // LD L,A
    0x26,
    0xf1, // LD HL,F100H + length
    0x7b, // LD A,E
    0x77, // LD (HL),A
    0x2c, // INC L
    0x7d, // LD A,L
    0x32,
    0xff,
    0xf0, // LD (F0FFH),A
    0xc9, // RET
  ], 5);
  memory[0xf0ff] = 0;
  const runtime = createZ80Runtime({ memory, startAddress: entry });
  const { cpu } = runtime;
  const runtimeMemory = runtime.hardware.memory;
  cpu.pc = entry;
  cpu.sp = 0xf000;
  let steps = 0;
  while (cpu.pc !== 0xff00) {
    assert.ok(++steps <= 100_000, "linked entry did not return");
    assert.ok(!runtime.isHalted(), "linked entry halted");
    runtime.step();
  }
  return {
    left: word(runtimeMemory, leftWorkspace),
    right: word(runtimeMemory, rightWorkspace),
    ...(captureOutput
      ? {
        output: String.fromCharCode(
          ...runtimeMemory.slice(0xf100, 0xf100 + runtimeMemory[0xf0ff]!),
        ),
      }
      : {}),
  };
}

function executeRuntimeCall(
  runtime: ReturnType<typeof createZ80Runtime>,
  entry: number,
  registers: { a?: number; hl?: number; bc?: number; de?: number } = {},
) {
  const { cpu } = runtime;
  cpu.pc = entry;
  cpu.sp = 0xf000;
  if (registers.a !== undefined) cpu.a = registers.a;
  if (registers.hl !== undefined) {
    cpu.h = registers.hl >>> 8;
    cpu.l = registers.hl & 0xff;
  }
  if (registers.bc !== undefined) {
    cpu.b = registers.bc >>> 8;
    cpu.c = registers.bc & 0xff;
  }
  if (registers.de !== undefined) {
    cpu.d = registers.de >>> 8;
    cpu.e = registers.de & 0xff;
  }
  let steps = 0;
  while (cpu.pc !== 0xff00) {
    assert.ok(++steps <= 100_000, "runtime call did not return");
    assert.ok(!runtime.isHalted(), "runtime call halted");
    runtime.step();
  }
  return {
    a: cpu.a,
    hl: cpu.h * 256 + cpu.l,
    bc: cpu.b * 256 + cpu.c,
    de: cpu.d * 256 + cpu.e,
    carry: cpu.flags.C,
  };
}

Deno.test("linked native entry reaches a provider-backed generated slot", async () => {
  const assembled = await loadAssembly("compiler/skate.asm");
  const template = parseNobj1(
    assembled.image.bytes.slice(
      assembled.address("N4OBJ"),
      assembled.address("N4OBJEND"),
    ),
  );
  const codeImage = template.images.find(({ sectionId }) => sectionId === 1);
  assert.ok(codeImage);
  const providerAssembly = await assemble("tests/nobj-link-runtime-4200.asm");
  const ndiv = providerAssembly.symbols.get("ndiv");
  const nneg = providerAssembly.symbols.get("nneg");
  const hinit = providerAssembly.symbols.get("hinit");
  const gcset = providerAssembly.symbols.get("gcset");
  const rtinit = providerAssembly.symbols.get("rtinit");
  const rtconsp = providerAssembly.symbols.get("rtconsp");
  const rtpknew = providerAssembly.symbols.get("rtpknew");
  const rtlit = providerAssembly.symbols.get("rtlit");
  const nleftwk = providerAssembly.symbols.get("nleftwk");
  const nrightwk = providerAssembly.symbols.get("nrightwk");
  assert.ok(ndiv !== undefined);
  assert.ok(nneg !== undefined);
  assert.ok(hinit !== undefined);
  assert.ok(gcset !== undefined);
  assert.ok(rtinit !== undefined);
  assert.ok(rtconsp !== undefined);
  assert.ok(rtpknew !== undefined);
  assert.ok(rtlit !== undefined);
  assert.ok(nleftwk !== undefined);
  assert.ok(nrightwk !== undefined);
  const provider = providerObject({
    base: 0x4200,
    bytes: providerAssembly.image.bytes.slice(0x4200),
  }, providerAssembly.symbols);
  const operations = [
    {
      name: "add",
      serviceId: 7,
      left: 40,
      right: 2,
      expectedTag: 3,
      expectedPayload: 42,
    },
    {
      name: "sub",
      serviceId: 8,
      left: 40,
      right: 2,
      expectedTag: 3,
      expectedPayload: 38,
    },
    {
      name: "mul",
      serviceId: 9,
      left: 40,
      right: 2,
      expectedTag: 3,
      expectedPayload: 80,
    },
    {
      name: "div",
      serviceId: 10,
      left: 40,
      right: 2,
      expectedTag: 0,
      expectedPayload: 0x4d00,
    },
  ] as const;
  let linked = undefined as ReturnType<typeof linkNobj1> | undefined;
  let linkedRegion: ReturnType<typeof linkNobj1>["regions"][number] | undefined;
  let mainPlacement:
    | ReturnType<typeof linkNobj1>["placements"][number]
    | undefined;
  let providerPlacement:
    | ReturnType<typeof linkNobj1>["placements"][number]
    | undefined;
  for (const operation of operations) {
    const code = codeImage.bytes.slice();
    code.set([
      0x3e,
      3,
      0x21,
      operation.left,
      0,
      0x06,
      3,
      0x11,
      operation.right,
      0,
      0xcd,
      0,
      0,
      0xc9,
      0,
      0,
    ], 192);
    const mainBytes = encodeNobj1({
      begin: template.begin,
      contracts: template.contracts,
      regions: template.regions,
      sections: template.sections,
      ranges: template.ranges,
      images: template.images.map((image) =>
        image.sectionId === 1
          ? { ...image, bytes: code }
          : image.sectionId === 5
          ? { ...image, bytes: code.slice(192, 256) }
          : image
      ),
      patches: template.patches,
      symbols: template.symbols,
      relocations: template.relocations.map((relocation) =>
        relocation.siteSectionId === 1 && relocation.siteOffset === 203
          ? { ...relocation, targetSymbolId: operation.serviceId }
          : relocation
      ).concat([{
        siteSectionId: 5,
        siteOffset: 11,
        kind: 1,
        use: 1,
        targetSymbolId: operation.serviceId,
        addend: 0,
      }]),
      metadata: template.metadata,
      layout: template.layout,
    });
    const main = parseNobj1(mainBytes);
    linked = linkNobj1([{
      id: "main",
      object: main,
    }, {
      id: "provider",
      object: provider,
    }], {
      mainObjectId: "main",
      target: linkedTarget(),
      providers: [{
        id: "skate-runtime-v2",
        objectId: "provider",
        supports: [runtimeContract],
        services: [
          "numeric.classify",
          "numeric.add",
          "numeric.sub",
          "numeric.mul",
          "numeric.div",
          "numeric.negate",
          "heap.initialize",
          "collector.configure",
          "execution.initialize",
          "execution.packet-new",
          "execution.invoke",
          "pairs.cons",
          "execution.literal-init",
        ].map((key, index) => ({
          contract: runtimeContract,
          key,
          symbolId: index + 1,
        })),
      }],
    });
    linkedRegion = linked.regions.find(({ base }) => base === 0x0100);
    assert.ok(linkedRegion);
    mainPlacement = linked.placements.find(
      ({ objectId, sectionId }: { objectId: string; sectionId: number }) =>
        objectId === "main" && sectionId === 1,
    );
    assert.ok(mainPlacement);
    providerPlacement = linked.placements.find(
      ({ objectId, sectionId }: { objectId: string; sectionId: number }) =>
        objectId === "provider" && sectionId === 1,
    );
    assert.ok(providerPlacement);
    const imageOffset = (offset: number) =>
      mainPlacement!.runAddress + offset - linkedRegion!.base;
    assert.equal(
      word(linkedRegion.bytes, imageOffset(203)),
      providerAssembly.symbols.get(
        operation.name === "add"
          ? "nadd"
          : operation.name === "sub"
          ? "nsub"
          : operation.name === "mul"
          ? "nmul"
          : "ndiv",
      ),
    );
    assert.deepEqual(
      executeGeneratedSlot(
        linkedRegion.bytes,
        linkedRegion.base,
        mainPlacement.runAddress + 192,
        3,
        operation.left,
        3,
        operation.right,
      ),
      {
        tag: operation.expectedTag,
        value: operation.expectedPayload,
        carry: 0,
      },
      operation.name,
    );
  }
  const unaryCode = codeImage.bytes.slice();
  unaryCode.set([
    0x3e,
    3,
    0x21,
    5,
    0,
    0xcd,
    0,
    0,
    0xc9,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ], 192);
  const unaryMainBytes = encodeNobj1({
    begin: template.begin,
    contracts: template.contracts,
    regions: template.regions,
    sections: template.sections,
    ranges: template.ranges,
    images: template.images.map((image) =>
      image.sectionId === 1
        ? { ...image, bytes: unaryCode }
        : image.sectionId === 5
        ? { ...image, bytes: unaryCode.slice(192, 256) }
        : image
    ),
    patches: template.patches,
    symbols: template.symbols,
    relocations: template.relocations.map((relocation) =>
      relocation.siteSectionId === 1 && relocation.siteOffset === 203
        ? { ...relocation, siteOffset: 198, targetSymbolId: 11 }
        : relocation
    ).concat([{
      siteSectionId: 5,
      siteOffset: 6,
      kind: 1,
      use: 1,
      targetSymbolId: 11,
      addend: 0,
    }]),
    metadata: template.metadata,
    layout: template.layout,
  });
  const unaryMain = parseNobj1(unaryMainBytes);
  const unaryLinked = linkNobj1([{
    id: "main",
    object: unaryMain,
  }, {
    id: "provider",
    object: provider,
  }], {
    mainObjectId: "main",
    target: linkedTarget(),
    providers: [{
      id: "skate-runtime-v2",
      objectId: "provider",
      supports: [runtimeContract],
      services: [
        "numeric.classify",
        "numeric.add",
        "numeric.sub",
        "numeric.mul",
        "numeric.div",
        "numeric.negate",
        "heap.initialize",
        "collector.configure",
        "execution.initialize",
        "execution.packet-new",
        "execution.invoke",
        "pairs.cons",
        "execution.literal-init",
      ].map((key, index) => ({
        contract: runtimeContract,
        key,
        symbolId: index + 1,
      })),
    }],
  });
  const unaryRegion = unaryLinked.regions.find(({ base }) => base === 0x0100);
  const unaryPlacement = unaryLinked.placements.find(
    ({ objectId, sectionId }: { objectId: string; sectionId: number }) =>
      objectId === "main" && sectionId === 1,
  );
  assert.ok(unaryRegion);
  assert.ok(unaryPlacement);
  const unaryImageOffset = (offset: number) =>
    unaryPlacement!.runAddress + offset - unaryRegion!.base;
  assert.equal(word(unaryRegion.bytes, unaryImageOffset(198)), nneg);
  assert.deepEqual(
    executeGeneratedSlot(
      unaryRegion.bytes,
      unaryRegion.base,
      unaryPlacement.runAddress + 192,
      3,
      5,
      0,
      0,
    ),
    { tag: 3, value: 0xfffb, carry: 0 },
    "negate",
  );
  const pairCode = codeImage.bytes.slice();
  pairCode.set([
    0x18,
    14,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ], 192);
  pairCode.set([
    0x01,
    0x02,
    0x00,
    0xcd,
    0x00,
    0x00,
    0x21,
    0x00,
    0x00,
    0x36,
    0x03,
    0x23,
    0x11,
    0x28,
    0x00,
    0x73,
    0x23,
    0x72,
    0x23,
    0x36,
    0x00,
    0x23,
    0x36,
    0x03,
    0x23,
    0x11,
    0x02,
    0x00,
    0x73,
    0x23,
    0x72,
    0x23,
    0x36,
    0x00,
    0x11,
    0x00,
    0x00,
    0x01,
    0x02,
    0x00,
    0xcd,
    0x00,
    0x00,
    0xc9,
  ], 208);
  const pairMainBytes = encodeNobj1({
    begin: template.begin,
    contracts: template.contracts,
    regions: template.regions,
    sections: template.sections,
    ranges: template.ranges,
    images: template.images.map((image) =>
      image.sectionId === 1
        ? { ...image, bytes: pairCode }
        : image.sectionId === 5
        ? { ...image, bytes: pairCode.slice(192, 256) }
        : image
    ),
    patches: template.patches,
    symbols: template.symbols,
    relocations: template.relocations.concat([
      {
        siteSectionId: 5,
        siteOffset: 20,
        kind: 1,
        use: 1,
        targetSymbolId: 18,
        addend: 0,
      },
      {
        siteSectionId: 5,
        siteOffset: 23,
        kind: 1,
        use: 2,
        targetSymbolId: 21,
        addend: 0,
      },
      {
        siteSectionId: 5,
        siteOffset: 51,
        kind: 1,
        use: 2,
        targetSymbolId: 20,
        addend: 0,
      },
      {
        siteSectionId: 5,
        siteOffset: 57,
        kind: 1,
        use: 1,
        targetSymbolId: 19,
        addend: 0,
      },
    ]),
    metadata: template.metadata,
    layout: template.layout,
  });
  const pairMain = parseNobj1(pairMainBytes);
  const pairLinked = linkNobj1([{
    id: "main",
    object: pairMain,
  }, {
    id: "provider",
    object: provider,
  }], {
    mainObjectId: "main",
    target: linkedTarget(),
    providers: [{
      id: "skate-runtime-v2",
      objectId: "provider",
      supports: [runtimeContract],
      services: [
        "numeric.classify",
        "numeric.add",
        "numeric.sub",
        "numeric.mul",
        "numeric.div",
        "numeric.negate",
        "heap.initialize",
        "collector.configure",
        "execution.initialize",
        "execution.packet-new",
        "execution.invoke",
        "pairs.cons",
        "execution.literal-init",
      ].map((key, index) => ({
        contract: runtimeContract,
        key,
        symbolId: index + 1,
      })),
    }],
  });
  const pairRegion = pairLinked.regions.find(({ base }) => base === 0x0100);
  const pairPlacement = pairLinked.placements.find(
    ({ objectId, sectionId }: { objectId: string; sectionId: number }) =>
      objectId === "main" && sectionId === 1,
  );
  const pairProviderPlacement = pairLinked.placements.find(
    ({ objectId, sectionId }: { objectId: string; sectionId: number }) =>
      objectId === "provider" && sectionId === 1,
  );
  assert.ok(pairRegion);
  assert.ok(pairPlacement);
  assert.ok(pairProviderPlacement);
  assert.equal(
    word(
      pairRegion.bytes,
      pairPlacement.runAddress + 212 - pairRegion.base,
    ),
    rtpknew,
  );
  assert.equal(
    word(
      pairRegion.bytes,
      pairPlacement.runAddress + 249 - pairRegion.base,
    ),
    rtconsp,
  );
  const pairMemory = new Uint8Array(0x10000);
  pairMemory.set(pairRegion.bytes, pairRegion.base);
  pairMemory[0] = 0xc3;
  pairMemory[1] = 0;
  pairMemory[2] = 0xff;
  pairMemory[5] = 0xc9;
  pairMemory[6] = 0;
  pairMemory[7] = 0xf0;
  const pairRuntime = createZ80Runtime({
    memory: pairMemory,
    startAddress: pairPlacement.runAddress + 192,
  });
  const pairRuntimeMemory = pairRuntime.hardware.memory;
  assert.equal(
    executeRuntimeCall(pairRuntime, hinit, { hl: 0x1148, bc: 16 }).carry,
    0,
  );
  assert.equal(
    executeRuntimeCall(pairRuntime, gcset, { hl: 0x1140, bc: 2 }).carry,
    0,
  );
  assert.equal(
    executeRuntimeCall(pairRuntime, rtinit, {
      hl: pairPlacement.runAddress + 467,
    }).carry,
    0,
  );
  const pairResult = executeRuntimeCall(
    pairRuntime,
    pairPlacement.runAddress + 192,
  );
  assert.equal(pairResult.a, 1);
  assert.equal(pairResult.hl, 1);
  assert.equal(pairResult.carry, 0);
  assert.equal(word(pairRuntimeMemory, 0x114c), 40);
  assert.equal(word(pairRuntimeMemory, 0x114e), 0xe002);
  assert.equal(word(pairRuntimeMemory, 0x1150), 2);
  assert.equal(word(pairRuntimeMemory, 0x1152), 0xc01b);

  // Install the same two-atom postfix recipe used by the quoted-data object
  // and call the provider service directly.  This isolates runtime-owned
  // recipe interpretation from the compiler's static result message.
  const literalMemory = new Uint8Array(pairRuntimeMemory);
  const recipe = Uint8Array.of(0x83, 1, 0, 0x83, 2, 0, 0);
  literalMemory.set(recipe, 0x1300);
  const literalRuntime = createZ80Runtime({
    memory: literalMemory,
    startAddress: pairPlacement.runAddress + 192,
  });
  assert.equal(
    executeRuntimeCall(literalRuntime, hinit, { hl: 0x1148, bc: 16 }).carry,
    0,
  );
  assert.equal(
    executeRuntimeCall(literalRuntime, gcset, { hl: 0x1140, bc: 2 }).carry,
    0,
  );
  assert.equal(
    executeRuntimeCall(literalRuntime, rtinit, {
      hl: pairPlacement.runAddress + 467,
    }).carry,
    0,
  );
  const literalResult = executeRuntimeCall(literalRuntime, rtlit, {
    hl: 0x1300,
    bc: recipe.length,
  });
  assert.equal(literalResult.a, 1);
  assert.notEqual(literalResult.hl, 0);
  assert.equal(literalResult.carry, 0);
  const literalRuntimeMemory = literalRuntime.hardware.memory;
  assert.equal(literalRuntimeMemory[0x1100], 1);
  assert.equal(word(literalRuntimeMemory, 0x1101), literalResult.hl);
  assert.equal(literalRuntimeMemory[0x1104], 0);
  assert.equal(word(literalRuntimeMemory, 0x1105), 0xfe29);
  assert.ok(linked);
  assert.ok(linkedRegion);
  assert.ok(mainPlacement);
  assert.ok(providerPlacement);
  const generatedPlacement = linked.placements.find(
    ({ objectId, sectionId }: { objectId: string; sectionId: number }) =>
      objectId === "main" && sectionId === 5,
  );
  assert.ok(generatedPlacement);
  assert.equal(linked.entry?.address, 0x0100);
  const imageOffset = (offset: number) =>
    mainPlacement.runAddress + offset - linkedRegion.base;
  assert.equal(word(linkedRegion.bytes, imageOffset(4)), 0x010c);
  assert.equal(word(linkedRegion.bytes, imageOffset(7)), 0x0200);
  assert.equal(word(linkedRegion.bytes, imageOffset(10)), 0x0208);
  assert.equal(word(linkedRegion.bytes, imageOffset(203)), ndiv);
  assert.equal(providerPlacement.runAddress, 0x4200);
  assert.deepEqual(
    executeLinkedEntry(
      linkedRegion.bytes,
      linkedRegion.base,
      linked.entry!.address,
      nleftwk,
      nrightwk,
    ),
    { left: 0x5100, right: 2 },
  );

  // Reuse the fully linked startup image, replace only the generated slot
  // with the independently known add shape, and prove that COMSTART routes
  // its ABI-2 result through runtime `write` before warm boot.
  const startupImage = linkedRegion.bytes.slice();
  startupImage.set([
    0x3e,
    3,
    0x21,
    40,
    0,
    0x06,
    3,
    0x11,
    2,
    0,
    0xcd,
    0,
    0,
    0xc9,
  ], imageOffset(192));
  const nadd = providerAssembly.symbols.get("nadd");
  assert.ok(nadd !== undefined);
  startupImage[imageOffset(203)] = nadd & 0xff;
  startupImage[imageOffset(204)] = nadd >>> 8;
  const generatedOffset = generatedPlacement.runAddress - linkedRegion.base;
  startupImage.set(
    startupImage.slice(imageOffset(192), imageOffset(256)),
    generatedOffset,
  );
  startupImage[generatedOffset + 11] = nadd & 0xff;
  startupImage[generatedOffset + 12] = nadd >>> 8;
  assert.deepEqual(
    executeLinkedEntry(
      startupImage,
      linkedRegion.base,
      linked.entry!.address,
      nleftwk,
      nrightwk,
      true,
    ),
    { left: 40, right: 2, output: "42" },
  );
});
