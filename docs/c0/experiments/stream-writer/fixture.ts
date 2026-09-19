import assert from "node:assert/strict";
import {
  createStreamMachine,
  type FailureInjection,
  PATCH_SOURCE,
  SPOOL_PREFIX,
  STAGE_PREFIX,
} from "./machine.ts";

export type StreamMachine = Awaited<ReturnType<typeof createStreamMachine>>;

const u16 = (value: number): number[] => [value & 255, value >>> 8 & 255];
const record = (kind: number, payload: number[]): number[] => [
  kind,
  ...u16(payload.length),
  ...payload,
];

/** Host fixture metadata: these bytes are not native writer workspace. */
export function declarationBytes(): Uint8Array {
  const bytes = [
    ...record(1, [0x4e, 0x4f, 0x42, 0x4a, 1, 0, 1, 0, 0]),
    ...record(3, [
      1,
      0,
      7,
      0x7a,
      0x38,
      0x30,
      0x2e,
      0x63,
      0x70,
      0x6d,
      0x07,
      0x63,
      0x70,
      0x6d,
      0x2e,
      0x72,
      0x61,
      0x6d,
      0,
      1,
      0,
      0xe3,
      0,
      0,
      0,
      7,
      0,
    ]),
    ...record(4, [
      1,
      0,
      1,
      7,
      1,
      0,
      0,
      0xe3,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
    ]),
  ];
  assert.equal(bytes.length, 70, "C0 declaration fixture size");
  assert.equal(bytes[51], 0, "SECTION length starts at serialized offset 51");
  return Uint8Array.from(bytes);
}

export const declarations = declarationBytes();

export function imageBytes(length: number): Uint8Array {
  const image = new Uint8Array(length);
  for (let index = 0; index < image.length; index++) {
    image[index] = (index * 29 + 11) & 255;
  }
  return image;
}

export function start(
  machine: StreamMachine,
  bytes = declarations,
  injection: FailureInjection = {},
): void {
  machine.reset(injection);
  assert.deepEqual(
    Object.fromEntries(
      Object.entries(
        machine.call("SWINIT", { hl: STAGE_PREFIX, de: SPOOL_PREFIX }),
      ).filter(([key]) => key === "status" || key === "carry"),
    ),
    { status: 0, carry: 0 },
  );
  for (const byte of bytes) {
    assert.equal(machine.call("SWDECB", { a: byte }).status, 0);
  }
  assert.equal(machine.call("SWDECEND").status, 0);
}

export function patch(
  machine: StreamMachine,
  offset: number,
  bytes: Uint8Array,
  slot: number,
): void {
  const source = PATCH_SOURCE + slot * 8;
  machine.memory.set(bytes, source);
  const result = machine.call("SWPATCH", {
    b: bytes.length,
    hl: offset,
    de: source,
  });
  assert.deepEqual(
    { status: result.status, carry: result.carry },
    { status: 0, carry: 0 },
  );
}

export interface PatchCase {
  readonly offset: number;
  readonly bytes: Uint8Array;
  readonly slot: number;
}

export function streamImage(
  machine: StreamMachine,
  image: Uint8Array,
  patches: readonly PatchCase[] = [],
): void {
  for (let index = 0; index < image.length; index++) {
    assert.equal(machine.call("SWIMGB", { a: image[index] }).status, 0);
    for (const item of patches) {
      if (item.offset === index + 1) {
        patch(machine, item.offset, item.bytes, item.slot);
      }
    }
  }
}

export function finish(
  machine: StreamMachine,
  image: Uint8Array,
  patches: readonly PatchCase[] = [],
): Uint8Array {
  streamImage(machine, image, patches);
  const result = machine.call("SWFINAL", { maxSteps: 30_000_000 });
  assert.deepEqual(
    { status: result.status, carry: result.carry },
    { status: 0, carry: 0 },
  );
  return machine.logicalStage();
}
