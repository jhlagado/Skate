import assert from "node:assert/strict";
import { encodeNobj1 } from "@jhlagado/z80-tool-services";
import { createZ80Runtime } from "@jhlagado/debug80-runtime";
import { SKATE_TPA_PROFILES } from "../tools/m7-compiler.ts";
import {
  linkTargetStreams,
  toPhysicalNobjRecords,
} from "../tools/target-linker.ts";

const profile = SKATE_TPA_PROFILES["cpm-32k"];
const region = {
  id: 1,
  addressSpaceKey: "z80.cpu",
  storageKey: "cpm.ram",
  base: profile.base,
  capacity: profile.capacity,
  imageFill: 0,
  permissions: 7,
  banked: false,
};
const runtime = {
  key: "org.skate.runtime",
  majorVersion: 2,
  minorVersion: 0,
};
const value = {
  key: "org.skate.value",
  majorVersion: 2,
  minorVersion: 0,
};

function providerObject(): Uint8Array {
  return encodeNobj1({
    begin: { targetId: 1 },
    contracts: [
      { id: 1, ...runtime, data: Uint8Array.of(0, 0, 0, 0) },
      { id: 2, ...value, data: new Uint8Array() },
    ],
    regions: [region],
    sections: [{
      id: 1,
      storageKind: 1,
      permissions: 5,
      alignment: 1,
      length: 3,
      runRegionId: 1,
      runPlacement: "fixed",
      runOffset: 0x200,
      loadPlacement: "same",
      loadRegionId: 1,
      loadOffset: 0,
      fill: 0,
    }],
    ranges: [],
    images: [{ sectionId: 1, offset: 0, bytes: Uint8Array.of(0x3e, 42, 0xc9) }],
    patches: [],
    symbols: [
      {
        id: 1,
        binding: "export",
        valueKind: 1,
        sectionId: 1,
        offset: 0,
        namespace: "org.skate.test",
        name: "answer",
      },
      {
        id: 2,
        binding: "export",
        valueKind: 2,
        sectionId: 1,
        offset: 1,
        namespace: "org.skate.test",
        name: "answer-data",
      },
    ],
    relocations: [],
    metadata: [],
    layout: { mode: "module", entrySymbolId: 0 },
  });
}

function callerObject(options: { bssRelocation?: boolean } = {}): Uint8Array {
  return encodeNobj1({
    begin: { targetId: 1 },
    contracts: [
      { id: 1, ...runtime, data: Uint8Array.of(0, 0, 0, 0) },
      { id: 2, ...value, data: new Uint8Array() },
    ],
    regions: [region],
    sections: [
      {
        id: 1,
        storageKind: 1,
        permissions: 5,
        alignment: 1,
        length: 8,
        runRegionId: 1,
        runPlacement: "allocate",
        runOffset: 0,
        loadPlacement: "same",
        loadRegionId: 1,
        loadOffset: 0,
        fill: 0,
      },
      {
        id: 2,
        storageKind: 2,
        permissions: 3,
        alignment: 4,
        length: 64,
        runRegionId: 1,
        runPlacement: "allocate",
        runOffset: 0,
      },
    ],
    ranges: [],
    images: [{
      sectionId: 1,
      offset: 0,
      // CALL answer; RET; one word reserved for an ordinary data pointer.
      bytes: Uint8Array.of(0xcd, 0, 0, 0xc9, 0, 0, 0, 0),
    }],
    patches: [],
    symbols: [
      { id: 1, binding: "local", valueKind: 1, sectionId: 1, offset: 0 },
      {
        id: 2,
        binding: "service-import",
        valueKind: 1,
        contractId: 1,
        serviceKey: "answer",
      },
      {
        id: 3,
        binding: "import",
        valueKind: 2,
        namespace: "org.skate.test",
        name: "answer-data",
      },
    ],
    relocations: [
      {
        siteSectionId: options.bssRelocation ? 2 : 1,
        siteOffset: 1,
        kind: 1,
        use: 1,
        targetSymbolId: 2,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: 4,
        kind: 1,
        use: 2,
        targetSymbolId: 3,
        addend: 0,
      },
    ],
    metadata: [],
    layout: { mode: "module", entrySymbolId: 1 },
  });
}

function input(
  id: string,
  bytes: Uint8Array,
): { id: string; records: Uint8Array[] } {
  return { id, records: toPhysicalNobjRecords(bytes) };
}

function options() {
  return {
    mainObjectId: "caller",
    profile,
    providers: [{
      id: "test-provider",
      objectId: "provider",
      supports: [runtime, value],
      services: [{ contract: runtime, key: "answer", symbolId: 1 }],
    }],
  };
}

Deno.test("N3 links bounded CP/M streams with service and data relocations", () => {
  const result = linkTargetStreams([
    input("caller", callerObject()),
    input("provider", providerObject()),
  ], options());
  assert.equal(result.objects.length, 2);
  assert.ok(result.physicalRecords >= 2);
  assert.equal(result.linked.entry?.address, 0x0100);
  assert.equal(result.linked.relocations.length, 2);
  const caller = (result.linked.placements as readonly {
    objectId: string;
    sectionId: number;
    runAddress: number;
  }[]).find((item) => item.objectId === "caller" && item.sectionId === 1);
  assert.ok(caller);
  const serviceOperand =
    result.comBytes[caller.runAddress - profile.base + 1]! |
    result.comBytes[caller.runAddress - profile.base + 2]! << 8;
  const dataOperand = result.comBytes[caller.runAddress - profile.base + 4]! |
    result.comBytes[caller.runAddress - profile.base + 5]! << 8;
  assert.equal(serviceOperand, 0x0300);
  assert.equal(dataOperand, 0x0301);

  const memory = new Uint8Array(65536);
  memory.set(result.comBytes, profile.base);
  memory[0xf000] = 0;
  memory[0xf001] = 0xff;
  const machine = createZ80Runtime({ memory, startAddress: 0x0100 });
  machine.cpu.pc = 0x0100;
  machine.cpu.sp = 0xf000;
  let steps = 0;
  while (machine.cpu.pc !== 0xff00) {
    assert.ok(++steps < 100, "linked target fixture did not return");
    machine.step();
  }
  assert.equal(machine.cpu.a, 42);
  assert.equal(machine.cpu.sp, 0xf002);
});

Deno.test("N3 strips only permitted physical padding after COMMIT", () => {
  const object = input("caller", callerObject());
  const padded = object.records[object.records.length - 1]!;
  padded[padded.length - 1] = 0;
  assert.throws(
    () => linkTargetStreams([object], options()),
    /padding/,
  );
  const truncated = { id: object.id, records: object.records.slice(0, -1) };
  assert.throws(
    () => linkTargetStreams([truncated], options()),
    /COMMIT|empty|truncated/,
  );
});

Deno.test("N3 rejects an unresolved import, a BSS relocation and target budgets", () => {
  assert.throws(
    () =>
      linkTargetStreams([
        input("caller", callerObject()),
      ], options()),
    /provider|service|import|contract/i,
  );
  assert.throws(
    () =>
      linkTargetStreams([
        input("caller", callerObject({ bssRelocation: true })),
        input("provider", providerObject()),
      ], options()),
    /BSS|initialized|relocation/i,
  );
  assert.throws(
    () =>
      linkTargetStreams(
        [
          input("caller", callerObject()),
          input("provider", providerObject()),
        ],
        options(),
        { maxObjects: 1 },
      ),
    /object budget/,
  );
});
