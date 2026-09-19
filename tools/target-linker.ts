/** Bounded target-facing NOBJ stream adapter for the native linker milestone. */
import { DEFAULT_SKATE_TPA_PROFILE } from "./m7-compiler.ts";
import { linkSkateObjects } from "./link.ts";

export interface PhysicalNobjStream {
  readonly id: string;
  /** CP/M physical records. Every record is exactly one 128-byte DMA block. */
  readonly records: readonly Uint8Array[];
}

export interface TargetStreamLimits {
  readonly maxRecords?: number;
  readonly maxBytes?: number;
  readonly maxObjects?: number;
}

const DEFAULT_LIMITS: Required<TargetStreamLimits> = {
  maxRecords: 512,
  maxBytes: 65535,
  maxObjects: 8,
};

function streamBytes(
  input: PhysicalNobjStream,
  limits: Required<TargetStreamLimits>,
): Uint8Array {
  if (input.records.length === 0) {
    throw new RangeError(`${input.id}: empty NOBJ stream`);
  }
  if (input.records.length > limits.maxRecords) {
    throw new RangeError(`${input.id}: physical record budget exceeded`);
  }
  const length = input.records.length * 128;
  if (length > limits.maxBytes) {
    throw new RangeError(`${input.id}: object spool budget exceeded`);
  }
  if (input.records.some((record) => record.length !== 128)) {
    throw new RangeError(`${input.id}: physical records must be 128 bytes`);
  }
  const bytes = new Uint8Array(length);
  input.records.forEach((record, index) => bytes.set(record, index * 128));

  let cursor = 0;
  let commitEnd = -1;
  while (cursor + 3 <= bytes.length) {
    const kind = bytes[cursor]!;
    const payloadLength = bytes[cursor + 1]! | bytes[cursor + 2]! << 8;
    const end = cursor + 3 + payloadLength;
    if (end > bytes.length) break;
    if (kind === 0x0c) {
      if (payloadLength !== 9) {
        throw new RangeError(
          `${input.id}: COMMIT has the wrong payload length`,
        );
      }
      commitEnd = end;
      break;
    }
    cursor = end;
  }
  if (commitEnd < 0) {
    throw new RangeError(`${input.id}: NOBJ stream has no complete COMMIT`);
  }
  for (let index = commitEnd; index < bytes.length; index += 1) {
    if (bytes[index] !== 0x1a) {
      throw new RangeError(`${input.id}: non-padding bytes follow COMMIT`);
    }
  }
  return bytes.slice(0, commitEnd);
}

export interface TargetLinkResult {
  readonly objects: readonly {
    readonly id: string;
    readonly bytes: Uint8Array;
  }[];
  readonly linked: ReturnType<typeof linkSkateObjects>;
  readonly comBytes: Uint8Array;
  readonly usedLength: number;
  readonly physicalRecords: number;
}

/**
 * Convert bounded CP/M records into committed NOBJ objects and link them with
 * the same contracts and target profile used by the host path. The adapter
 * retains only one logical object at a time before handing it to the linker;
 * callers can therefore account for the spool and record budgets explicitly.
 */
export function linkTargetStreams(
  inputs: readonly PhysicalNobjStream[],
  options: Parameters<typeof linkSkateObjects>[1],
  limits: TargetStreamLimits = {},
): TargetLinkResult {
  const budget = { ...DEFAULT_LIMITS, ...limits };
  if (inputs.length === 0) throw new RangeError("target link needs one object");
  if (inputs.length > budget.maxObjects) {
    throw new RangeError("target object budget exceeded");
  }
  const objects = inputs.map((input) => ({
    id: input.id,
    bytes: streamBytes(input, budget),
  }));
  const linked = linkSkateObjects(objects, options);
  const profile = options.profile ?? DEFAULT_SKATE_TPA_PROFILE;
  const region = linked.regions.find((item) =>
    item.targetRegionId === profile.id
  );
  if (region === undefined) {
    throw new RangeError("target link produced no selected CP/M region");
  }
  return {
    objects,
    linked,
    comBytes: region.bytes.slice(0, region.usedLength),
    usedLength: region.usedLength,
    physicalRecords: inputs.reduce(
      (total, input) => total + input.records.length,
      0,
    ),
  };
}

/** Split a committed object into CP/M-sized records, padding only its tail. */
export function toPhysicalNobjRecords(bytes: Uint8Array): Uint8Array[] {
  if (bytes.length === 0) {
    throw new RangeError("cannot transport an empty object");
  }
  const count = Math.ceil(bytes.length / 128);
  return Array.from({ length: count }, (_, index) => {
    const record = new Uint8Array(128).fill(0x1a);
    record.set(bytes.slice(index * 128, (index + 1) * 128));
    return record;
  });
}
