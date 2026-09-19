/** Host-only output-framing experiment; buffers model staged disk files. */
import {
  encodeNobj1,
  materializeNobj1Object,
  nobjCrc16CcittFalse,
  parseNobj1,
} from "@jhlagado/z80-tool-services";

const u16 = (n: number) => [n & 255, (n >>> 8) & 255];
const u32 = (n: number) => [...u16(n), ...u16(n >>> 16)];
const record = (kind: number, payload: number[]) =>
  Uint8Array.from([kind, ...u16(payload.length), ...payload]);
const join = (chunks: Uint8Array[]) => {
  const result = new Uint8Array(
    chunks.reduce((sum, chunk) => sum + chunk.length, 0),
  );
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return result;
};

export interface Patch {
  offset: number;
  bytes: Uint8Array;
}
export const REGION_BYTES = 0xe400 - 0x0100;
export const IMAGE_CHUNK = 119; // Three framing + six site bytes = one 128-byte record.
export const PATCH_LIMIT = 16;

export function records(
  bytes: Uint8Array,
): { kind: number; offset: number; bytes: Uint8Array }[] {
  const result = [];
  for (let at = 0; at < bytes.length;) {
    if (at + 3 > bytes.length) throw new Error("truncated envelope");
    const end = at + 3 + bytes[at + 1] + 256 * bytes[at + 2];
    if (end > bytes.length) throw new Error("truncated payload");
    result.push({ kind: bytes[at], offset: at, bytes: bytes.slice(at, end) });
    at = end;
  }
  return result;
}

function template() {
  return records(encodeNobj1({
    begin: { targetId: 1 },
    contracts: [],
    regions: [{
      id: 1,
      addressSpaceKey: "z80.cpu",
      storageKey: "cpm.ram",
      base: 0x0100,
      capacity: REGION_BYTES,
      imageFill: 0,
      permissions: 7,
      banked: false,
    }],
    sections: [{
      id: 1,
      storageKind: 1,
      permissions: 7,
      alignment: 1,
      length: REGION_BYTES,
      runRegionId: 1,
      runPlacement: "fixed",
      runOffset: 0,
      loadPlacement: "same",
      loadRegionId: 1,
      loadOffset: 0,
      fill: 0,
    }],
    ranges: [],
    images: [],
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
    layout: { mode: "placed", entrySymbolId: 1 },
  }));
}

export function commit(chunks: Uint8Array[]): Uint8Array {
  // Commit's last two CRC bytes are excluded from its own coverage.
  const prefix = Uint8Array.from([
    12,
    9,
    0,
    ...u32(chunks.length + 1),
    1,
    ...u16(1),
  ]);
  const covered = join([...chunks, prefix]);
  return join([covered, Uint8Array.from(u16(nobjCrc16CcittFalse(covered)))]);
}

export function streamLayout(
  chunks: Iterable<Uint8Array>,
  patches: readonly Patch[],
) {
  if (patches.length > PATCH_LIMIT) throw new Error("patch capacity");
  const declarations = template();
  const output = declarations.filter((r) => r.kind <= 5).map((r) => r.bytes);
  const comChunks: Uint8Array[] = [];
  let length = 0, inputChunks = 0, imageRecords = 0;
  for (const chunk of chunks) {
    inputChunks++;
    if (length + chunk.length > REGION_BYTES) throw new Error("image capacity");
    comChunks.push(chunk.slice()); // Sequential writes to the staged COM model.
    for (let at = 0; at < chunk.length; at += IMAGE_CHUNK) {
      const bytes = chunk.subarray(at, at + IMAGE_CHUNK);
      output.push(record(6, [...u16(1), ...u32(length + at), ...bytes]));
      imageRecords++;
    }
    length += chunk.length;
  }
  if (length === 0) throw new Error("empty executable");
  // SECTION header is rewritten in place; payload size and following offsets stay fixed.
  const section = output.find((r) => r[0] === 4)!;
  section.set(u32(length), 3 + 6);
  for (const patch of patches) {
    if (
      !Number.isInteger(patch.offset) || patch.offset < 0 ||
      patch.bytes.length === 0 ||
      patch.offset + patch.bytes.length > length
    ) throw new Error("patch bounds");
    output.push(record(7, [...u16(1), ...u32(patch.offset), ...patch.bytes]));
  }
  output.push(
    ...declarations.filter((r) => r.kind === 8 || r.kind === 11).map((r) =>
      r.bytes
    ),
  );
  const uncommitted = join(output);
  const objectBytes = commit(output);
  // The real existing decoder checks order, overlapping sites, count and CRC.
  const object = parseNobj1(objectBytes);
  const com = join(comChunks);
  for (const patch of patches) com.set(patch.bytes, patch.offset);
  const materialized = materializeNobj1Object(object).regions[0];
  return {
    objectBytes,
    uncommitted,
    com,
    materialized,
    inputChunks,
    imageRecords,
    sectionLength: object.sections[0].length,
    outputRewrites: {
      sectionLengthBytes: 4,
      patchBytes: patches.reduce((n, p) => n + p.bytes.length, 0),
    },
    modeledDiskTraversals: {
      nobjSequentialEmission: 1,
      finalCrc: 1,
      comSequentialEmission: 1,
    },
    qualification:
      "Host framing model only. All host buffer copies and validator/materializer memory and traversals are excluded from the modeled disk account; they are not a proposed native compiler implementation. No CP/M transfers or provider/publication execution measured.",
  };
}
