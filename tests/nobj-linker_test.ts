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

interface Nobj1Region {
  id: number;
  addressSpaceKey: string;
  storageKey: string;
  base: number;
  capacity: number;
  imageFill: number;
  permissions: number;
  banked: boolean;
}
interface Nobj1ContractIdentity {
  key: string;
  majorVersion: number;
  minorVersion: number;
}
interface Nobj1TargetRegion {
  id: string;
  addressSpaceKey: string;
  storageKey: string;
  base: number;
  capacity: number;
  imageFill: number;
  permissions: number;
  banked: boolean;
}
interface Nobj1LinkObject {
  id: string;
  object: { serialized: Uint8Array; regions: readonly Nobj1Region[] };
}
interface Nobj1TargetLayout {
  regions: readonly Nobj1TargetRegion[];
  visibility: readonly {
    from: { addressSpaceKey: string; storageKey: string };
    to: { addressSpaceKey: string; storageKey: string };
    use: 1 | 2 | 3;
  }[];
}
interface Nobj1LinkResult {
  placements: readonly {
    objectId: string;
    sectionId: number;
    runAddress: number;
  }[];
  regions: readonly { base: number; bytes: Uint8Array }[];
  relocations: readonly { value: number }[];
  entry?: { address: number };
}

const projectRoot = fileURLToPath(new URL("../", import.meta.url));
const region: Nobj1Region = {
  id: 1,
  addressSpaceKey: "z80.cpu",
  storageKey: "cpm.ram",
  base: 0x0100,
  capacity: 0xff00,
  imageFill: 0,
  permissions: 7,
  banked: false,
};
const runtimeContract: Nobj1ContractIdentity = {
  key: "org.skate.runtime",
  majorVersion: 2,
  minorVersion: 0,
};
const valueContract: Nobj1ContractIdentity = {
  key: "org.skate.value",
  majorVersion: 2,
  minorVersion: 0,
};

async function assemble(entry: string, base: number) {
  const result = await assembleAtomProject({
    root: projectRoot,
    entry,
    assembler: undefined,
    target: undefined,
    maxInstructions: undefined,
    maxCycles: undefined,
    sink: undefined,
  });
  const fullImage = materializeAtomGeneration(result.generation);
  if (!fullImage) throw new Error(`ATOM produced no image for ${entry}`);
  const trim = base - fullImage.base;
  if (trim < 0 || trim > fullImage.bytes.length) {
    throw new Error(
      `ATOM image for ${entry} does not reach its requested origin`,
    );
  }
  const image = {
    base,
    end: fullImage.end,
    bytes: fullImage.bytes.slice(trim),
  };
  const symbols = new Map<string, number>(
    result.generation.symbols.map((symbol: { name: string; value: number }) => [
      symbol.name.toLowerCase(),
      symbol.value,
    ]),
  );
  return { image, symbols };
}

function symbol(symbols: Map<string, number>, name: string): number {
  const address = symbols.get(name.toLowerCase());
  if (address === undefined) throw new Error(`ATOM omitted ${name}`);
  return address;
}

function callerObject(code: Uint8Array): Nobj1LinkObject {
  const serialized = encodeNobj1({
    begin: { targetId: 1 },
    contracts: [
      {
        id: 1,
        ...runtimeContract,
        data: Uint8Array.of(0, 0, 1, 0),
      },
      { id: 2, ...valueContract, data: new Uint8Array() },
    ],
    regions: [region],
    sections: [
      {
        id: 1,
        storageKind: 1,
        permissions: 5,
        alignment: 1,
        length: code.length,
        runRegionId: 1,
        runPlacement: "allocate",
        runOffset: 0,
        loadPlacement: "same",
        loadRegionId: 1,
        loadOffset: 0,
        fill: 0,
      },
    ],
    ranges: [],
    images: [{ sectionId: 1, offset: 0, bytes: code.slice() }],
    patches: [],
    symbols: [
      { id: 1, binding: "local", valueKind: 1, sectionId: 1, offset: 0 },
      {
        id: 2,
        binding: "service-import",
        valueKind: 1,
        contractId: 1,
        serviceKey: "numeric.add",
      },
    ],
    relocations: [
      {
        siteSectionId: 1,
        siteOffset: 1,
        kind: 1,
        use: 1,
        targetSymbolId: 2,
        addend: 0,
      },
    ],
    metadata: [],
    layout: { mode: "module", entrySymbolId: 1 },
  });
  return { id: "caller", object: parseNobj1(serialized) };
}

function runtimeObject(
  image: { base: number; bytes: Uint8Array },
  naddAddress: number,
): Nobj1LinkObject {
  const serialized = encodeNobj1({
    begin: { targetId: 1 },
    contracts: [
      {
        id: 1,
        ...runtimeContract,
        data: Uint8Array.of(0, 0, 0, 0),
      },
      { id: 2, ...valueContract, data: new Uint8Array() },
    ],
    regions: [region],
    sections: [
      {
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
      },
    ],
    ranges: [],
    images: [{ sectionId: 1, offset: 0, bytes: image.bytes.slice() }],
    patches: [],
    symbols: [
      {
        id: 1,
        binding: "local",
        valueKind: 1,
        sectionId: 1,
        offset: naddAddress - image.base,
      },
    ],
    relocations: [],
    metadata: [],
    layout: { mode: "module", entrySymbolId: 0 },
  });
  return { id: "skate-runtime", object: parseNobj1(serialized) };
}

function targetFor(objects: readonly Nobj1LinkObject[]): Nobj1TargetLayout {
  const known = new Map<string, Nobj1Region>();
  for (const { object } of objects) {
    for (const item of object.regions) {
      const key =
        `${item.addressSpaceKey}\0${item.storageKey}\0${item.base}\0${item.capacity}`;
      known.set(key, item);
    }
  }
  return {
    regions: [...known.values()].map((item, index) => ({
      id: `region-${index}`,
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

function executeAdd(
  image: Uint8Array,
  base: number,
  entry: number,
  left: { tag: number; value: number },
  right: { tag: number; value: number },
) {
  const memory = new Uint8Array(0x10000);
  memory.set(image, base);
  memory[0xf000] = 0;
  memory[0xf001] = 0xff;
  const machine = createZ80Runtime({ memory, startAddress: entry });
  const { cpu } = machine;
  cpu.pc = entry;
  cpu.sp = 0xf000;
  cpu.a = left.tag;
  cpu.b = right.tag;
  cpu.h = left.value >>> 8;
  cpu.l = left.value & 0xff;
  cpu.d = right.value >>> 8;
  cpu.e = right.value & 0xff;
  cpu.ix = 0x1357;
  cpu.iy = 0x2468;
  let steps = 0;
  while (cpu.pc !== 0xff00) {
    assert.ok(++steps <= 20000, "linked caller did not return");
    assert.ok(!machine.isHalted(), "linked caller halted");
    machine.step();
  }
  assert.equal(cpu.sp, 0xf002, "linked call stack is balanced");
  assert.equal(cpu.ix, 0x1357, "IX is preserved");
  assert.equal(cpu.iy, 0x2468, "IY is preserved");
  return {
    tag: cpu.a,
    value: cpu.h * 256 + cpu.l,
    carry: cpu.flags.C,
  };
}

Deno.test("ATOM Skate runtime service links and executes at two placements", async () => {
  const callerAssembly = await assemble("tests/nobj-link-caller.asm", 0x0100);
  const caller = callerObject(callerAssembly.image.bytes);

  for (
    const [entry, expectedAddress] of [
      ["tests/nobj-link-provider-4200.asm", 0x4200],
      ["tests/nobj-link-provider-5200.asm", 0x5200],
    ] as const
  ) {
    const runtimeAssembly = await assemble(entry, expectedAddress);
    const naddAddress = symbol(runtimeAssembly.symbols, "NADD");
    assert.equal(runtimeAssembly.image.base, expectedAddress);
    const runtime = runtimeObject(runtimeAssembly.image, naddAddress);
    const linked: Nobj1LinkResult = linkNobj1([caller, runtime], {
      mainObjectId: caller.id,
      target: targetFor([caller, runtime]),
      providers: [
        {
          id: "skate-runtime-v2",
          objectId: runtime.id,
          supports: [runtimeContract, valueContract],
          services: [
            {
              contract: runtimeContract,
              key: "numeric.add",
              symbolId: 1,
            },
          ],
        },
      ],
    });
    const linkedRegion = linked.regions[0];
    assert.ok(linkedRegion);
    assert.equal(linked.entry?.address, 0x0100);
    assert.equal(linked.relocations[0]?.value, naddAddress);
    const callerPlacement = linked.placements.find(
      ({ objectId, sectionId }) => objectId === caller.id && sectionId === 1,
    );
    assert.ok(callerPlacement);
    const operandOffset = callerPlacement.runAddress + 1 - linkedRegion.base;
    assert.equal(
      linkedRegion.bytes[operandOffset] |
        (linkedRegion.bytes[operandOffset + 1] << 8),
      naddAddress,
    );

    const exact = executeAdd(linkedRegion.bytes, linkedRegion.base, 0x0100, {
      tag: 3,
      value: 41,
    }, { tag: 3, value: 1 });
    assert.deepEqual(exact, { tag: 3, value: 42, carry: 0 });

    const binary16 = executeAdd(
      linkedRegion.bytes,
      linkedRegion.base,
      0x0100,
      { tag: 0, value: 0x3c00 },
      { tag: 0, value: 0x4000 },
    );
    assert.deepEqual(binary16, { tag: 0, value: 0x4200, carry: 0 });
  }
});
