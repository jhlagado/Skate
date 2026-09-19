import assert from "node:assert/strict";
// @deno-types="../../atom/node_modules/@jhlagado/z80-tool-services/dist/index.d.ts"
import { encodeNobj1, nobjCrc16CcittFalse } from "@jhlagado/z80-tool-services";
import { loadAssembly } from "./z80.ts";

const INPUT = 0x8000;
const TARGET = 0x4000;
const TARGET_CAPACITY = 0x100;
const OUTPUT = TARGET + 0x10;
const STACK = 0x7000;
const RETURN = 0x7100;
const TARGET_SENTINEL = 0xcc;

const region = (base = TARGET) => ({
  id: 1,
  addressSpaceKey: "z80.cpu",
  storageKey: "cpm.ram",
  base,
  capacity: TARGET_CAPACITY,
  imageFill: 0,
  permissions: 7,
  banked: false,
});

const sourceBytes = Uint8Array.of(
  0xcd,
  0x00,
  0x00,
  0xc9,
  0x00,
  0x3e,
  0x2a,
  0xc9,
);

function object(options: {
  readonly regionBase?: number;
  readonly sectionLength?: number;
  readonly symbolCount?: number;
  readonly contract?: boolean;
  readonly symbolOffset?: number;
  readonly addend?: number;
  readonly relocationSites?: readonly number[];
  readonly imageRecords?: readonly {
    readonly offset: number;
    readonly bytes: Uint8Array;
  }[];
} = {}): Uint8Array {
  const sectionLength = options.sectionLength ?? sourceBytes.length;
  const symbols = Array.from(
    { length: options.symbolCount ?? 1 },
    (_, index) => ({
      id: index + 1,
      binding: "local" as const,
      valueKind: (index === 0 ? 1 : 2) as 1 | 2,
      sectionId: 1,
      offset: index === 0 ? options.symbolOffset ?? 5 : index - 1,
    }),
  );
  const images = options.imageRecords?.map(({ offset, bytes }) => ({
    sectionId: 1,
    offset,
    bytes: bytes.slice(),
  })) ?? [{
    sectionId: 1,
    offset: 0,
    bytes: sectionLength === sourceBytes.length
      ? sourceBytes.slice()
      : new Uint8Array(sectionLength),
  }];
  return encodeNobj1({
    begin: { targetId: 1 },
    contracts: options.contract === true
      ? [{
        id: 1,
        key: "org.skate.value",
        majorVersion: 2,
        minorVersion: 0,
        data: new Uint8Array(),
      }]
      : [],
    regions: [region(options.regionBase ?? TARGET)],
    sections: [{
      id: 1,
      storageKind: 1,
      permissions: 5,
      alignment: 1,
      length: sectionLength,
      runRegionId: 1,
      runPlacement: "fixed",
      runOffset: 0x10,
      loadPlacement: "same",
      loadRegionId: 1,
      loadOffset: 0,
      fill: 0,
    }],
    ranges: [],
    images,
    patches: [],
    symbols,
    relocations: (options.relocationSites ?? [1]).map((siteOffset) => ({
      siteSectionId: 1,
      siteOffset,
      kind: 1,
      use: 1,
      targetSymbolId: 1,
      addend: options.addend ?? -1,
    })),
    metadata: [],
    layout: { mode: "module", entrySymbolId: 1 },
  });
}

function recalcCommitCrc(bytes: Uint8Array): void {
  const crc = nobjCrc16CcittFalse(bytes.slice(0, -2));
  bytes[bytes.length - 2] = crc & 0xff;
  bytes[bytes.length - 1] = crc >>> 8;
}

function overlappingRelocations(first: number, second: number): Uint8Array {
  const bytes = object({ relocationSites: [first, 4] });
  let cursor = 0;
  let relocationCount = 0;
  while (cursor < bytes.length) {
    const kind = bytes[cursor]!;
    const length = bytes[cursor + 1]! | bytes[cursor + 2]! << 8;
    const payload = cursor + 3;
    if (kind === 9 && ++relocationCount === 2) {
      bytes[payload + 2] = second;
      bytes[payload + 3] = 0;
      bytes[payload + 4] = 0;
      bytes[payload + 5] = 0;
      break;
    }
    cursor += 3 + length;
  }
  recalcCommitCrc(bytes);
  return bytes;
}

const setup = await loadAssembly("tests/nobj1-target-proof.asm");
const { runtime, image, address } = setup;
const memory = runtime.hardware.memory;
const cpu = runtime.cpu;
let minStack = STACK;
const written: number[] = [];
(runtime.hardware as typeof runtime.hardware & {
  memWrite: (address: number, value: number) => void;
}).memWrite = (p, value) => {
  const work = p >= address("TGWORK") && p < address("TGWEND");
  const stage = p >= address("TGSTAG") && p < address("TGSEND");
  const target = p >= TARGET && p < TARGET + TARGET_CAPACITY;
  const stack = p >= STACK - 64 && p < STACK;
  assert.ok(
    work || stage || target || stack,
    `unexpected write at ${p.toString(16)}`,
  );
  if (stack) minStack = Math.min(minStack, p);
  written.push(p);
  memory[p] = value;
};

function run(bytes: Uint8Array) {
  memory.fill(0);
  memory.set(image.bytes, image.base);
  memory.fill(TARGET_SENTINEL, TARGET, TARGET + TARGET_CAPACITY);
  memory.set(bytes, INPUT);
  memory[STACK] = RETURN & 0xff;
  memory[STACK + 1] = RETURN >>> 8;
  cpu.pc = address("TGLINK");
  cpu.sp = STACK;
  cpu.h = INPUT >>> 8;
  cpu.l = INPUT & 0xff;
  cpu.b = bytes.length >>> 8;
  cpu.c = bytes.length & 0xff;
  cpu.ix = 0x1357;
  cpu.iy = 0x2468;
  cpu.flags.C = 1;
  minStack = STACK;
  written.length = 0;
  let steps = 0;
  while (cpu.pc !== RETURN) {
    assert.ok(
      ++steps < 2_000_000 && !runtime.isHalted(),
      "TGLINK did not return",
    );
    runtime.step();
  }
  assert.equal(cpu.sp, STACK + 2, "TGLINK balances SP");
  assert.equal(cpu.ix, 0x1357, "TGLINK preserves IX");
  assert.equal(cpu.iy, 0x2468, "TGLINK preserves IY");
  return {
    status: cpu.a,
    carry: cpu.flags.C,
    output: memory.slice(TARGET, TARGET + TARGET_CAPACITY),
    maxStack: STACK - minStack,
    writes: [...written],
  };
}

Deno.test("ATOM NOBJ1 target proof verifies and applies a real ABS16_RUN call", () => {
  const bytes = object();
  const outcome = run(bytes);
  assert.deepEqual(
    { status: outcome.status, carry: outcome.carry },
    { status: 0, carry: 0 },
  );
  assert.deepEqual(
    [...outcome.output.slice(0x10, 0x18)],
    [0xcd, 0x14, 0x40, 0xc9, 0x00, 0x3e, 0x2a, 0xc9],
  );
  assert.ok(outcome.maxStack <= 8, `stack use ${outcome.maxStack}`);

  cpu.pc = OUTPUT;
  cpu.sp = STACK;
  memory[STACK] = RETURN & 0xff;
  memory[STACK + 1] = RETURN >>> 8;
  let steps = 0;
  while (cpu.pc !== RETURN) {
    assert.ok(
      ++steps < 100 && !runtime.isHalted(),
      "linked routine did not return",
    );
    runtime.step();
  }
  assert.equal(cpu.a, 42);
  assert.equal(cpu.sp, STACK + 2);

  const codeBytes = address("TGCEND") - address("TGCODE");
  const workspaceBytes = address("TGWEND") - address("TGWORK");
  const stagingBytes = address("TGSEND") - address("TGSTAG");
  const imageBytes = address("TGEND") - address("TGCODE");
  assert.ok(codeBytes <= 2048, `code bytes ${codeBytes}`);
  assert.ok(workspaceBytes <= 96, `workspace bytes ${workspaceBytes}`);
  assert.equal(stagingBytes, 32);
  assert.ok(imageBytes <= 2176, `total module image ${imageBytes}`);
  assert.equal(imageBytes, codeBytes + workspaceBytes + stagingBytes);
});

Deno.test("positive relocation addends are applied without wrapping", () => {
  const outcome = run(object({ symbolOffset: 4, addend: 1 }));
  assert.deepEqual(
    { status: outcome.status, carry: outcome.carry },
    { status: 0, carry: 0 },
  );
  assert.deepEqual([...outcome.output.slice(0x10, 0x13)], [0xcd, 0x15, 0x40]);
});

Deno.test("bad CRC never publishes the staged section", () => {
  const bytes = object();
  bytes[bytes.length - 1] ^= 1;
  const outcome = run(bytes);
  assert.deepEqual(
    { status: outcome.status, carry: outcome.carry },
    { status: 4, carry: 1 },
  );
  assert.ok(outcome.output.every((value) => value === TARGET_SENTINEL));
});

Deno.test("truncated COMMIT input fails without publishing staged bytes", () => {
  const truncated = object().slice(0, -1);
  const outcome = run(truncated);
  assert.deepEqual(
    { status: outcome.status, carry: outcome.carry },
    { status: 1, carry: 1 },
  );
  assert.ok(outcome.output.every((value) => value === TARGET_SENTINEL));
});

Deno.test("unsupported required contracts are rejected before publication", () => {
  const outcome = run(object({ contract: true }));
  assert.deepEqual(
    { status: outcome.status, carry: outcome.carry },
    { status: 2, carry: 1 },
  );
  assert.ok(outcome.output.every((value) => value === TARGET_SENTINEL));
});

Deno.test("target limits reject oversized sections, symbol tables and spools", () => {
  for (
    const bytes of [
      object({ sectionLength: 33 }),
      object({ symbolCount: 5 }),
      object({
        sectionLength: 12,
        imageRecords: [0, 2, 4, 6, 8].map((offset) => ({
          offset,
          bytes: Uint8Array.of(offset),
        })),
      }),
      object({ sectionLength: 10, relocationSites: [0, 2, 4, 6, 8] }),
      new Uint8Array(513),
    ]
  ) {
    const outcome = run(bytes);
    assert.deepEqual(
      { status: outcome.status, carry: outcome.carry },
      { status: 3, carry: 1 },
    );
    assert.ok(outcome.output.every((value) => value === TARGET_SENTINEL));
  }
});

Deno.test("a valid object for another target region is refused", () => {
  const outcome = run(object({ regionBase: 0x5000 }));
  assert.deepEqual(
    { status: outcome.status, carry: outcome.carry },
    { status: 2, carry: 1 },
  );
  assert.ok(outcome.output.every((value) => value === TARGET_SENTINEL));
});

Deno.test("a valid CRC cannot hide a SECTION extent beyond the target window", () => {
  const bytes = object();
  let cursor = 0;
  while (cursor < bytes.length) {
    const kind = bytes[cursor]!;
    const length = bytes[cursor + 1]! | bytes[cursor + 2]! << 8;
    const payload = cursor + 3;
    if (kind === 4) {
      bytes[payload + 13] = 0xff;
      bytes[payload + 14] = 0;
      recalcCommitCrc(bytes);
      break;
    }
    cursor += 3 + length;
  }
  const outcome = run(bytes);
  assert.deepEqual(
    { status: outcome.status, carry: outcome.carry },
    { status: 5, carry: 1 },
  );
  assert.ok(outcome.output.every((value) => value === TARGET_SENTINEL));
});

Deno.test("overlapping ABS16 sites and unrepresentable addends are rejected", () => {
  for (const [first, second] of [[1, 2], [2, 1]]) {
    const intersecting = run(overlappingRelocations(first, second));
    assert.deepEqual(
      { status: intersecting.status, carry: intersecting.carry },
      { status: 5, carry: 1 },
    );
    assert.ok(intersecting.output.every((value) => value === TARGET_SENTINEL));
  }

  const oversized = run(object({ addend: 0x1_0000 }));
  assert.deepEqual(
    { status: oversized.status, carry: oversized.carry },
    { status: 5, carry: 1 },
  );
  assert.ok(oversized.output.every((value) => value === TARGET_SENTINEL));
});
