import assert from "node:assert/strict";
import { encodeNobj1 } from "@jhlagado/z80-tool-services";
import {
  linkSkateObjects,
  type PublicationIO,
  publishCom,
  publishFiles,
  recoverPublication,
} from "../tools/link.ts";
import { SKATE_TPA_PROFILES } from "../tools/m7-compiler.ts";
import type { SkateBootAllocation } from "../tools/skate-contract.ts";

function fixture(options: {
  readonly profile?: keyof typeof SKATE_TPA_PROFILES;
  readonly runtimeVersion?: number;
  readonly fixedOffset?: number;
} = {}): Uint8Array {
  const profile = SKATE_TPA_PROFILES[options.profile ?? "cpm-32k"];
  return encodeNobj1({
    begin: { targetId: 1 },
    contracts: options.runtimeVersion === undefined ? [] : [{
      id: 1,
      key: "org.skate.runtime",
      majorVersion: options.runtimeVersion,
      minorVersion: 0,
      data: options.runtimeVersion === 2
        ? Uint8Array.of(0, 0, 0, 0)
        : new Uint8Array(),
    }],
    regions: [{
      id: 1,
      addressSpaceKey: "z80.cpu",
      storageKey: "cpm.ram",
      base: profile.base,
      capacity: profile.capacity,
      imageFill: profile.imageFill,
      permissions: profile.permissions,
      banked: profile.banked,
    }],
    sections: [{
      id: 1,
      storageKind: 1,
      permissions: 5,
      alignment: 1,
      length: 1,
      runRegionId: 1,
      runPlacement: options.fixedOffset === undefined ? "allocate" : "fixed",
      runOffset: options.fixedOffset ?? 0,
      loadPlacement: "same",
      loadRegionId: 1,
      loadOffset: 0,
      fill: 0,
    }],
    ranges: [],
    images: [{ sectionId: 1, offset: 0, bytes: Uint8Array.of(0xc9) }],
    patches: [],
    symbols: [{
      id: 1,
      binding: "local",
      valueKind: 1,
      sectionId: 1,
      offset: 0,
    }],
    relocations: [],
    metadata: [],
    layout: { mode: "module", entrySymbolId: 1 },
  });
}

function invalidDescriptorFixture(
  words?: Readonly<Record<number, number>>,
): Uint8Array {
  const profile = SKATE_TPA_PROFILES["cpm-32k"];
  const bytes = new Uint8Array(47 + 4096 + 640 + 12 + 64);
  bytes[0] = 0xc9;
  if (words !== undefined) {
    const fields = {
      0: 1,
      10: 0x100,
      12: 0x129,
      14: 1024,
      16: 640,
      18: 4096,
      20: 64,
      22: 3,
      ...words,
    };
    for (const [offset, value] of Object.entries(fields)) {
      bytes[1 + Number(offset)] = value & 255;
      bytes[2 + Number(offset)] = value >>> 8;
    }
    bytes[42] = 1;
  }
  return encodeNobj1({
    begin: { targetId: 1 },
    contracts: [{
      id: 1,
      key: "org.skate.runtime",
      majorVersion: 2,
      minorVersion: 0,
      data: Uint8Array.of(1, 0, 1, 0),
    }],
    regions: [{
      id: 1,
      addressSpaceKey: "z80.cpu",
      storageKey: "cpm.ram",
      base: profile.base,
      capacity: profile.capacity,
      imageFill: profile.imageFill,
      permissions: profile.permissions,
      banked: profile.banked,
    }],
    sections: [{
      id: 1,
      storageKind: 1,
      permissions: 7,
      alignment: 1,
      length: bytes.length,
      runRegionId: 1,
      runPlacement: "allocate",
      runOffset: 0,
      loadPlacement: "same",
      loadRegionId: 1,
      loadOffset: 0,
      fill: 0,
    }],
    ranges: [{
      id: 1,
      sectionId: 1,
      view: "run",
      offset: 1,
      length: 40,
    }],
    images: [{ sectionId: 1, offset: 0, bytes }],
    patches: [],
    symbols: [{
      id: 1,
      binding: "local",
      valueKind: 1,
      sectionId: 1,
      offset: 0,
    }],
    relocations: [],
    metadata: [],
    layout: { mode: "module", entrySymbolId: 1 },
  });
}

class MemoryPublication implements PublicationIO {
  readonly files = new Map<string, Uint8Array>();
  renameCount = 0;
  failRenameAt: number | null = null;

  writeFile(path: string, bytes: Uint8Array): Promise<void> {
    this.files.set(path, bytes.slice());
    return Promise.resolve();
  }

  rename(from: string, to: string): Promise<void> {
    this.renameCount += 1;
    if (this.failRenameAt === this.renameCount) {
      return Promise.reject(new Error("simulated publication interruption"));
    }
    const bytes = this.files.get(from);
    if (bytes === undefined) {
      return Promise.reject(new Error(`missing ${from}`));
    }
    this.files.delete(from);
    this.files.set(to, bytes);
    return Promise.resolve();
  }

  remove(path: string): Promise<void> {
    this.files.delete(path);
    return Promise.resolve();
  }

  exists(path: string): Promise<boolean> {
    return Promise.resolve(this.files.has(path));
  }

  readFile(path: string): Promise<Uint8Array> {
    const bytes = this.files.get(path);
    return bytes === undefined
      ? Promise.reject(new Error(`missing ${path}`))
      : Promise.resolve(bytes.slice());
  }
}

Deno.test("M11 links a committed NOBJ object against each supported TPA profile", () => {
  const bytes = fixture();
  for (const profile of ["cpm-32k", "cpm-64k"] as const) {
    const linked = linkSkateObjects([{ id: "main", bytes }], {
      mainObjectId: "main",
      providers: [],
      profile: SKATE_TPA_PROFILES[profile],
    });
    assert.equal(linked.entry?.address, 0x0100);
    assert.equal(linked.regions[0]?.usedLength, 1);
    assert.equal(linked.regions[0]?.bytes[0], 0xc9);
  }
  assert.throws(
    () =>
      linkSkateObjects([{ id: "main", bytes: fixture() }], {
        mainObjectId: "main",
        providers: [],
        profile: {
          ...SKATE_TPA_PROFILES["cpm-32k"],
          capacity: 0x5f00,
          stackTop: 0x6000,
          stackLow: 0x5000,
        },
      }),
    /not supported by the target/,
  );
});

Deno.test("M11 rejects object placement in the reserved native stack", () => {
  const profile = SKATE_TPA_PROFILES["cpm-32k"];
  assert.throws(() =>
    linkSkateObjects([{
      id: "main",
      bytes: fixture({ fixedOffset: profile.stackLow - profile.base }),
    }], { mainObjectId: "main", providers: [], profile }), /stack/i);
});

Deno.test("M11 rejects corrupt and truncated NOBJ before placement", () => {
  const bytes = fixture();
  assert.throws(
    () =>
      linkSkateObjects([{ id: "main", bytes: bytes.slice(0, -1) }], {
        mainObjectId: "main",
        providers: [],
      }),
    /NOBJ|truncated|CRC/i,
  );
  const corrupt = bytes.slice();
  corrupt[corrupt.length - 1] ^= 1;
  assert.throws(
    () =>
      linkSkateObjects([{ id: "main", bytes: corrupt }], {
        mainObjectId: "main",
        providers: [],
      }),
    /CRC|NOBJ/i,
  );
});

Deno.test("M11 rejects a runtime contract with the wrong ABI revision", () => {
  assert.throws(
    () =>
      linkSkateObjects(
        [{ id: "main", bytes: fixture({ runtimeVersion: 1 }) }],
        { mainObjectId: "main", providers: [] },
      ),
    /contract|provider|runtime/i,
  );
});

Deno.test("M11 rejects an invalid placed Skate boot descriptor", () => {
  assert.throws(
    () =>
      linkSkateObjects(
        [{ id: "main", bytes: invalidDescriptorFixture() }],
        {
          mainObjectId: "main",
          providers: [{
            id: "self-runtime",
            objectId: "main",
            supports: [{
              key: "org.skate.runtime",
              majorVersion: 2,
              minorVersion: 0,
            }],
            services: [],
          }],
          profile: SKATE_TPA_PROFILES["cpm-32k"],
        },
      ),
    /descriptor|revision|boot/i,
  );
});

Deno.test("M11 validates descriptor addresses and capacity fields after placement", () => {
  const link = (
    words: Readonly<Record<number, number>>,
    allocation: Partial<SkateBootAllocation> | null = {},
  ) =>
    linkSkateObjects(
      [{ id: "main", bytes: invalidDescriptorFixture(words) }],
      {
        mainObjectId: "main",
        allocations: allocation === null ? [] : [{
          objectId: "main",
          roots: { address: 0x12f, bytes: 4096 },
          activations: { address: 0x112f, bytes: 640 },
          heap: { address: 0x13af, bytes: 12 },
          workspace: [{ address: 0x13bb, bytes: 64 }],
          stack: { address: 0x7000, bytes: 4096 },
          ...allocation,
        }],
        profile: SKATE_TPA_PROFILES["cpm-32k"],
        providers: [{
          id: "self-runtime",
          objectId: "main",
          services: [],
          supports: [{
            key: "org.skate.runtime",
            majorVersion: 2,
            minorVersion: 0,
          }],
        }],
      },
    );
  assert.equal(link({}).entry?.address, 0x100);
  assert.throws(() => link({}, null), /allocation map/);
  assert.throws(
    () => link({}, { heap: { address: 0x12f, bytes: 12 } }),
    /overlap/,
  );
  assert.throws(
    () => link({}, { heap: { address: 0xffff, bytes: 12 } }),
    /geometry/,
  );
  assert.throws(
    () => link({}, { heap: { address: 0x6000, bytes: 12 } }),
    /storage/,
  );
  assert.throws(
    () =>
      link({}, {
        heap: { address: 0x13af, bytes: 64 },
        bitmap: { address: 0x13ef, bytes: 1 },
      }),
    /bitmap/,
  );
  assert.throws(
    () => link({}, { stack: { address: 0x100, bytes: 4096 } }),
    /overlap/,
  );
  assert.throws(
    () => link({}, { stack: { address: 0x6000, bytes: 4096 } }),
    /profile/,
  );
  const invalidFields: Readonly<Record<number, number>>[] = [
    { 14: 0 },
    { 14: 1 },
    { 22: 8193 },
    { 22: 65535 },
    { 10: 0xffff },
    { 12: 0xffff },
    { 14: 1025 },
    { 16: 9 },
    { 18: 0 },
    { 18: 1 },
    { 18: 65535 },
    { 20: 1 },
    { 20: 65 },
    { 22: 4 },
    { 16: 650 },
    { 14: 1023 },
    { 20: 0 },
    { 22: 2 },
    { 2: 0x100 },
    { 2: 0xfffe, 4: 2 },
  ];
  for (const fields of invalidFields) {
    assert.throws(() => link(fields), /Skate/);
  }
});

Deno.test("M11 publishes related COM and NOBJ files as one recoverable generation", async () => {
  const io = new MemoryPublication();
  io.files.set("build/skate.com", Uint8Array.of(1, 2, 3));
  io.files.set("build/skate.nobj", Uint8Array.of(4, 5));
  io.failRenameAt = 4;
  await assert.rejects(
    publishFiles([
      { path: "build/skate.com", bytes: Uint8Array.of(9) },
      { path: "build/skate.nobj", bytes: Uint8Array.of(8) },
    ], io),
    /interruption/,
  );
  assert.deepEqual([...io.files.get("build/skate.com")!], [1, 2, 3]);
  assert.deepEqual([...io.files.get("build/skate.nobj")!], [4, 5]);
  assert.equal(
    [...io.files.keys()].some((path) => path.includes("skate-stage")),
    false,
  );
  assert.equal(
    [...io.files.keys()].some((path) => path.includes("skate-previous")),
    false,
  );
  assert.equal(io.files.has("build/skate.com.skate-generation"), false);

  io.failRenameAt = null;
  await publishCom("build/skate.com", Uint8Array.of(7), io);
  assert.deepEqual([...io.files.get("build/skate.com")!], [7]);
  assert.equal(io.files.has("build/skate.com.skate-generation"), false);
});

Deno.test("M11 recovers a marked interrupted generation before the next publish", async () => {
  const io = new MemoryPublication();
  io.files.set(
    "build/skate.com.skate-generation",
    new TextEncoder().encode(JSON.stringify({
      version: 1,
      token: "fixed",
      entries: [
        {
          path: "build/skate.com",
          staged: "build/skate.com.skate-stage-fixed-0",
          backup: "build/skate.com.skate-previous-fixed",
        },
        {
          path: "build/skate.nobj",
          staged: "build/skate.nobj.skate-stage-fixed-1",
          backup: "build/skate.nobj.skate-previous-fixed",
        },
      ],
    })),
  );
  // Simulate both old files moved and the first new file installed.
  io.files.set("build/skate.com.skate-previous-fixed", Uint8Array.of(1, 2));
  io.files.set("build/skate.nobj.skate-previous-fixed", Uint8Array.of(3, 4));
  io.files.set("build/skate.com", Uint8Array.of(7));
  io.files.set("build/skate.com.skate-stage-fixed-0", Uint8Array.of(5));
  io.files.set("build/skate.nobj.skate-stage-fixed-1", Uint8Array.of(6));

  assert.equal(
    await recoverPublication(["build/skate.com", "build/skate.nobj"], io),
    true,
  );
  assert.deepEqual([...io.files.get("build/skate.com")!], [1, 2]);
  assert.deepEqual([...io.files.get("build/skate.nobj")!], [3, 4]);
  assert.equal(io.files.has("build/skate.com.skate-generation"), false);
  assert.equal(
    [...io.files.keys()].some((path) => path.includes("skate-stage")),
    false,
  );
  assert.equal(
    [...io.files.keys()].some((path) => path.includes("skate-previous")),
    false,
  );
});
