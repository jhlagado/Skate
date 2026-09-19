import assert from "node:assert/strict";
import { encodeNobj1, parseNobj1 } from "@jhlagado/z80-tool-services";
import { loadAssembly } from "./z80.ts";
import { linkSkateObjects } from "../tools/link.ts";
import { SKATE_TPA_PROFILES } from "../tools/m7-compiler.ts";

Deno.test("native descriptor envelope survives placed NOBJ validation", async () => {
  const assembled = await loadAssembly("compiler/skate.asm");
  const raw = assembled.image.bytes.slice(
    assembled.address("N4OBJ"),
    assembled.address("N4OBJEND"),
  );
  const template = parseNobj1(raw);
  const mainBytes = encodeNobj1({
    begin: template.begin,
    contracts: template.contracts,
    regions: template.regions,
    sections: template.sections,
    ranges: template.ranges,
    images: template.images,
    patches: template.patches,
    symbols: template.symbols,
    relocations: template.relocations,
    metadata: template.metadata,
    layout: template.layout,
  });
  const provider = encodeNobj1({
    begin: { targetId: 1 },
    contracts: [{
      id: 1,
      key: "org.skate.runtime",
      majorVersion: 2,
      minorVersion: 0,
      data: new Uint8Array(4),
    }],
    regions: [{
      id: 1,
      addressSpaceKey: "z80.cpu",
      storageKey: "cpm.ram",
      base: 0x0100,
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
      length: 1,
      runRegionId: 1,
      runPlacement: "fixed",
      runOffset: 0x2000,
      loadPlacement: "same",
      loadRegionId: 1,
      loadOffset: 0,
      fill: 0,
    }],
    ranges: [],
    images: [{ sectionId: 1, offset: 0, bytes: Uint8Array.of(0xc9) }],
    patches: [],
    symbols: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13].map((id) => ({
      id,
      binding: "local" as const,
      valueKind: 1,
      sectionId: 1,
      offset: 0,
    })),
    relocations: [],
    metadata: [],
    layout: { mode: "module", entrySymbolId: 1 },
  });
  const profile = SKATE_TPA_PROFILES["cpm-64k"];
  const linked = linkSkateObjects([
    { id: "main", bytes: mainBytes },
    { id: "provider", bytes: provider },
  ], {
    profile,
    mainObjectId: "main",
    providers: [{
      id: "runtime-v2",
      objectId: "provider",
      supports: [{
        key: "org.skate.runtime",
        majorVersion: 2,
        minorVersion: 0,
      }],
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
        contract: {
          key: "org.skate.runtime",
          majorVersion: 2,
          minorVersion: 0,
        },
        key,
        symbolId: index + 1,
      })),
    }],
    allocations: [{
      objectId: "main",
      bss: { address: 0x1100, bytes: 136 },
      roots: { address: 0x1100, bytes: 32 },
      activations: { address: 0x1120, bytes: 16 },
      bitmap: { address: 0x1140, bytes: 8 },
      heap: { address: 0x1148, bytes: 64 },
      workspace: [{ address: 0x1130, bytes: 16 }],
      stack: { address: profile.stackLow, bytes: profile.stackCapacity },
    }],
  });
  assert.equal(linked.entry?.address, 0x0100);
  assert.equal(
    linked.relocations.find(({ siteSectionId, siteOffset }) =>
      siteSectionId === 1 && siteOffset === 4
    )?.value,
    0x010c,
  );
  assert.equal(
    linked.relocations.find(({ siteSectionId, siteOffset }) =>
      siteSectionId === 1 && siteOffset === 7
    )?.value,
    0x0200,
  );
  assert.equal(
    linked.relocations.find(({ siteSectionId, siteOffset }) =>
      siteSectionId === 1 && siteOffset === 10
    )?.value,
    0x0208,
  );
  const generatedEntry = linked.relocations.find((
    { siteSectionId, siteOffset },
  ) => siteSectionId === 1 && siteOffset === 459)?.value;
  assert.equal(
    generatedEntry,
    linked.placements.find(
      (placement: { objectId: string; sectionId: number }) =>
        placement.objectId === "main" && placement.sectionId === 5,
    )?.runAddress,
  );
});

Deno.test("native emitter rejects dynamic spans before CRC and COMMIT", async () => {
  const assembled = await loadAssembly("compiler/skate.asm");
  const { runtime, address } = assembled;
  const memory = runtime.hardware.memory;
  const put = (at: number, value: number) => {
    memory[at] = value & 0xff;
    memory[at + 1] = value >>> 8;
  };
  const callValid = (
    messageLength: number,
    recipeLength: number,
    head: number,
    codeLength = 64,
  ) => {
    put(address("N8MLEN"), messageLength);
    put(address("N8OUTLEN"), recipeLength);
    put(address("N8RHEAD"), head);
    put(address("N8CLENW"), codeLength);
    runtime.cpu.pc = address("N8VALID");
    runtime.cpu.sp = 0xf000;
    put(0xf000, 0xff00);
    runtime.cpu.flags.C = 1;
    for (let steps = 0; runtime.cpu.pc !== 0xff00; steps += 1) {
      assert.ok(steps < 1_000, "N8VALID did not return");
      runtime.step();
    }
    return runtime.cpu.flags.C;
  };
  assert.equal(callValid(128, 2047, 2047), 0);
  assert.equal(callValid(129, 0, 0), 1);
  assert.equal(callValid(0, 2049, 2049), 1);
  assert.equal(callValid(0, 1, 0), 1);
  assert.equal(callValid(0, 0, 0, 65), 1);
});
