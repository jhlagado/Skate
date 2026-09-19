/** Placed validation for Skate's runtime ABI 2 boot contract. */
interface Nobj1Contract {
  readonly key: string;
  readonly majorVersion: number;
  readonly minorVersion: number;
  readonly data: Uint8Array;
}

interface Nobj1Section {
  readonly id: number;
  readonly storageKind: number;
  readonly permissions: number;
  readonly length: number;
}

interface Nobj1Range {
  readonly id: number;
  readonly sectionId: number;
  readonly view: "run" | "load";
  readonly offset: number;
  readonly length: number;
}

interface Nobj1Symbol {
  readonly id: number;
  readonly binding: string;
  readonly valueKind: number;
  readonly sectionId?: number;
  readonly offset?: number;
}

interface Nobj1Object {
  readonly contracts: readonly Nobj1Contract[];
  readonly sections: readonly Nobj1Section[];
  readonly ranges: readonly Nobj1Range[];
  readonly symbols: readonly Nobj1Symbol[];
}

interface Nobj1SectionPlacement {
  readonly objectId: string;
  readonly sectionId: number;
  readonly runAddress: number;
}

interface Nobj1LinkedRegionImage {
  readonly targetRegionId: string;
  readonly base: number;
  readonly capacity: number;
  readonly usedLength: number;
  readonly bytes: Uint8Array;
}

export interface SkatePlacedLinkResult {
  readonly placements: readonly Nobj1SectionPlacement[];
  readonly regions: readonly Nobj1LinkedRegionImage[];
  readonly entry?: { readonly address: number };
}

const RUNTIME_KEY = "org.skate.runtime";
const RUNTIME_MAJOR = 2;
const RUNTIME_MINOR = 0;
const DESCRIPTOR_BYTES = 40;
const CODE = 1;

export interface SkateContractObject {
  readonly id: string;
  readonly object: Nobj1Object;
}

export interface SkateStorageSpan {
  readonly address: number;
  readonly bytes: number;
}

/** Trusted allocations supplied by the target/runtime integration, not the object. */
export interface SkateBootAllocation {
  readonly objectId: string;
  /** Complete zero-initialized storage envelope, when exposed by the target. */
  readonly bss?: SkateStorageSpan;
  readonly roots: SkateStorageSpan;
  readonly activations: SkateStorageSpan;
  /** Mark bitmap span, when the target exposes it as a separate allocation. */
  readonly bitmap?: SkateStorageSpan;
  readonly heap: SkateStorageSpan;
  readonly workspace: readonly SkateStorageSpan[];
  readonly stack: SkateStorageSpan;
}

function validateAllocation(
  descriptor: Uint8Array,
  allocation: SkateBootAllocation,
  objects: readonly SkateContractObject[],
  linked: SkatePlacedLinkResult,
): void {
  const storage = [
    allocation.roots,
    allocation.activations,
    ...(allocation.bitmap === undefined ? [] : [allocation.bitmap]),
    allocation.heap,
    ...allocation.workspace,
  ];
  const spans = [...storage, allocation.stack];
  const stack = allocation.stack;
  if (
    !linked.regions.some((region) =>
      stack.address >= region.base &&
      stack.address + stack.bytes <= region.base + region.capacity
    )
  ) {
    fail("Skate stack allocation is outside the target region");
  }
  for (const { id, object } of objects) {
    for (const section of object.sections) {
      const placed = placementFor(linked, id, section.id);
      if (
        placed.runAddress < stack.address + stack.bytes &&
        stack.address < placed.runAddress + section.length
      ) {
        fail("Skate stack allocation overlaps a linked section");
      }
    }
  }
  for (const span of spans) {
    if (
      !Number.isInteger(span.address) || !Number.isInteger(span.bytes) ||
      span.address < 0 || span.bytes <= 0 || span.address + span.bytes > 65536
    ) {
      fail("Skate allocation has invalid geometry");
    }
  }
  const heapCells = allocation.heap.bytes % 4 === 0
    ? allocation.heap.bytes / 4
    : 0;
  if (heapCells < 3 || heapCells > 8192) {
    fail("Skate heap allocation is not a whole supported cell range");
  }
  if (
    allocation.bitmap !== undefined &&
    allocation.bitmap.bytes < Math.ceil(heapCells / 8)
  ) {
    fail("Skate mark bitmap is too small for its heap");
  }
  for (const span of storage) {
    if (
      !writableSpan(objects, linked, span.address, span.bytes) ||
      !objects.some(({ id, object }) =>
        object.sections.some((section) => {
          const placed = linked.placements.find((p) =>
            p.objectId === id && p.sectionId === section.id
          );
          return placed !== undefined && (section.permissions & 2) !== 0 &&
            span.address >= placed.runAddress &&
            span.address + span.bytes <= placed.runAddress + section.length;
        })
      )
    ) fail("Skate allocation is outside writable initialized storage");
  }
  for (let i = 0; i < spans.length; i++) {
    for (let j = i + 1; j < spans.length; j++) {
      if (
        spans[i]!.address < spans[j]!.address + spans[j]!.bytes &&
        spans[j]!.address < spans[i]!.address + spans[i]!.bytes
      ) {
        fail("Skate allocations overlap");
      }
    }
  }
  const requested = [
    word(descriptor, 14) * 4,
    word(descriptor, 16),
    word(descriptor, 22) * 4,
    word(descriptor, 20),
    word(descriptor, 18),
  ];
  const available = [
    allocation.roots.bytes,
    allocation.activations.bytes,
    allocation.heap.bytes,
    allocation.workspace.reduce((n, s) => n + s.bytes, 0),
    allocation.stack.bytes,
  ];
  for (let i = 0; i < requested.length; i++) {
    if (
      requested[i]! > available[i]! ||
      (i !== 2 && requested[i] !== available[i])
    ) {
      fail("Skate boot capacity does not match its allocation");
    }
  }
}

function fail(message: string): never {
  throw new Error(message);
}

function word(bytes: Uint8Array, offset: number): number {
  const low = bytes[offset];
  const high = bytes[offset + 1];
  if (low === undefined || high === undefined) {
    return fail("Skate boot descriptor is truncated");
  }
  return low | (high << 8);
}

function placementFor(
  linked: SkatePlacedLinkResult,
  objectId: string,
  sectionId: number,
): Nobj1SectionPlacement {
  return linked.placements.find(
    (candidate) =>
      candidate.objectId === objectId && candidate.sectionId === sectionId,
  ) ?? fail(`Skate contract section ${objectId}:${sectionId} is not placed`);
}

function sectionFor(object: Nobj1Object, sectionId: number): Nobj1Section {
  return object.sections.find(({ id }) => id === sectionId) ??
    fail(`Skate contract names missing SECTION ${sectionId}`);
}

function imageAt(
  linked: SkatePlacedLinkResult,
  address: number,
  length: number,
): Uint8Array {
  if (!Number.isInteger(address) || address < 0 || address > 0xffff) {
    return fail("Skate contract address is outside the Z80 address space");
  }
  if (!Number.isInteger(length) || length < 0) {
    return fail("Skate contract extent is invalid");
  }
  const region = linked.regions.find(
    (candidate) =>
      address >= candidate.base &&
      address + length <= candidate.base + candidate.capacity,
  );
  if (region === undefined) {
    return fail(
      `Skate contract address $${address.toString(16)} is outside linked image`,
    );
  }
  const offset = address - region.base;
  return region.bytes.subarray(offset, offset + length);
}

function initializedSpan(
  objects: readonly SkateContractObject[],
  linked: SkatePlacedLinkResult,
  address: number,
  length: number,
): boolean {
  if (length < 0 || address < 0 || address + length > 0x1_0000) return false;
  return objects.some(({ id, object }) =>
    object.sections.some((section) => {
      if (section.storageKind !== 1) return false;
      const placement = linked.placements.find(
        (candidate) =>
          candidate.objectId === id &&
          candidate.sectionId === section.id,
      );
      return placement !== undefined &&
        address >= placement.runAddress &&
        address + length <= placement.runAddress + section.length &&
        (section.permissions & 1) !== 0;
    })
  );
}

function writableSpan(
  objects: readonly SkateContractObject[],
  linked: SkatePlacedLinkResult,
  address: number,
  length: number,
): boolean {
  if (length < 0 || address < 0 || address + length > 0x1_0000) return false;
  return objects.some(({ id, object }) =>
    object.sections.some((section) => {
      if (
        (section.storageKind !== 1 && section.storageKind !== 2) ||
        (section.permissions & 2) === 0
      ) return false;
      const placement = linked.placements.find(
        (candidate) =>
          candidate.objectId === id && candidate.sectionId === section.id,
      );
      return placement !== undefined &&
        address >= placement.runAddress &&
        address + length <= placement.runAddress + section.length;
    })
  );
}

function executableAddress(
  objects: readonly SkateContractObject[],
  linked: SkatePlacedLinkResult,
  address: number,
  length = 1,
): boolean {
  return objects.some(({ id, object }) =>
    object.sections.some((section) => {
      if (section.storageKind !== 1 || (section.permissions & 4) === 0) {
        return false;
      }
      const placement = linked.placements.find(
        (candidate) =>
          candidate.objectId === id &&
          candidate.sectionId === section.id,
      );
      return placement !== undefined &&
        address >= placement.runAddress &&
        address + length <= placement.runAddress + section.length;
    })
  );
}

function rangeAddress(
  ownerId: string,
  object: Nobj1Object,
  linked: SkatePlacedLinkResult,
  rangeId: number,
): { address: number; length: number } {
  const range = object.ranges.find(({ id }) => id === rangeId);
  if (range === undefined) {
    return fail(`Skate contract names missing RANGE ${rangeId}`);
  }
  if (range.view !== "run") {
    return fail("Skate boot descriptor range must use RUN view");
  }
  const section = sectionFor(object, range.sectionId);
  if (section.storageKind !== 1 || (section.permissions & 1) === 0) {
    return fail("Skate boot descriptor range must use initialized storage");
  }
  if (
    range.offset < 0 || range.length < 0 ||
    range.offset + range.length > section.length
  ) {
    return fail("Skate boot descriptor range exceeds its SECTION");
  }
  const placement = placementFor(linked, ownerId, section.id);
  return { address: placement.runAddress + range.offset, length: range.length };
}

function tableExtent(
  objects: readonly SkateContractObject[],
  linked: SkatePlacedLinkResult,
  address: number,
  count: number,
  stride: number,
  name: string,
  storage: "initialized" | "writable" = "initialized",
): void {
  if (count === 0) {
    if (address !== 0) {
      fail(`Skate ${name} address must be zero for an empty table`);
    }
    return;
  }
  if (
    address === 0 || count < 0 || count > 0xffff || count * stride > 0x1_0000
  ) {
    fail(`Skate ${name} table geometry is invalid`);
  }
  const inStorage = storage === "initialized"
    ? initializedSpan(objects, linked, address, count * stride)
    : writableSpan(objects, linked, address, count * stride);
  if (!inStorage) {
    fail(`Skate ${name} table is outside initialized storage`);
  }
}

function symbolAddress(
  ownerId: string,
  object: Nobj1Object,
  linked: SkatePlacedLinkResult,
  symbolId: number,
): number {
  const symbol = object.symbols.find(({ id }) => id === symbolId);
  if (
    symbol === undefined ||
    (symbol.binding !== "local" && symbol.binding !== "export")
  ) {
    return fail("Skate top-level entry symbol is not a local CODE definition");
  }
  if (symbol.sectionId === undefined || symbol.offset === undefined) {
    return fail("Skate top-level entry is missing its section location");
  }
  if (symbol.valueKind !== CODE) {
    return fail("Skate top-level entry is not CODE");
  }
  const section = sectionFor(object, symbol.sectionId);
  if (section.storageKind !== 1 || (section.permissions & 4) === 0) {
    return fail("Skate top-level entry is not executable initialized storage");
  }
  const placement = placementFor(linked, ownerId, section.id);
  const address = placement.runAddress + symbol.offset;
  if (!executableAddress([{ id: ownerId, object }], linked, address)) {
    return fail("Skate top-level entry lies outside its executable SECTION");
  }
  return address;
}

function validateDescriptor(
  ownerId: string,
  object: Nobj1Object,
  linked: SkatePlacedLinkResult,
  contract: { readonly data: Uint8Array },
  allObjects: readonly SkateContractObject[],
  allocations: readonly SkateBootAllocation[],
): void {
  if (contract.data.length !== 4) {
    return fail("Skate runtime contract payload must be exactly four bytes");
  }
  const descriptorRangeId = word(contract.data, 0);
  const topSymbolId = word(contract.data, 2);
  if (descriptorRangeId === 0 && topSymbolId === 0) return;
  if (descriptorRangeId === 0 || topSymbolId === 0) {
    return fail("Skate runtime contract descriptor and entry must be paired");
  }
  const descriptorRange = rangeAddress(
    ownerId,
    object,
    linked,
    descriptorRangeId,
  );
  if (descriptorRange.length !== DESCRIPTOR_BYTES) {
    return fail("Skate boot descriptor range must be exactly 40 bytes");
  }
  if (
    !initializedSpan(
      allObjects,
      linked,
      descriptorRange.address,
      DESCRIPTOR_BYTES,
    )
  ) {
    return fail("Skate boot descriptor range is outside initialized storage");
  }
  const descriptor = imageAt(
    linked,
    descriptorRange.address,
    DESCRIPTOR_BYTES,
  );
  if (word(descriptor, 0) !== 1) {
    fail("Skate boot descriptor revision is not one");
  }

  const topEntry = symbolAddress(ownerId, object, linked, topSymbolId);
  const literalEntry = word(descriptor, 10);
  if (!executableAddress(allObjects, linked, literalEntry)) {
    fail("Skate literal-init entry is not executable initialized storage");
  }
  const topDescriptor = word(descriptor, 12);
  if (!initializedSpan(allObjects, linked, topDescriptor, 8)) {
    fail("Skate top-level procedure descriptor is outside initialized storage");
  }
  const topWords = imageAt(linked, topDescriptor, 8);
  if (word(topWords, 0) !== topEntry) {
    fail("Skate top-level descriptor does not name the contract entry");
  }
  if (
    word(topWords, 2) !== 0 || word(topWords, 4) !== 0 ||
    word(topWords, 6) !== 0
  ) {
    fail(
      "Skate top-level descriptor must have zero arity, slots and rest policy",
    );
  }

  const rootSlots = word(descriptor, 14);
  if (rootSlots < 2) fail("Skate root capacity cannot hold the startup packet");
  if (rootSlots > 1024) fail("Skate root-slot count exceeds the runtime arena");
  if (word(descriptor, 16) < 10) {
    fail("Skate activation capacity is below one record");
  }
  if (word(descriptor, 18) === 0) fail("Skate native-stack capacity is empty");
  if (word(descriptor, 20) === 0) {
    fail("Skate runtime workspace capacity is empty");
  }
  if (word(descriptor, 22) < 3) {
    fail("Skate heap-cell minimum is below the runtime minimum");
  }
  if (word(descriptor, 22) > 8192) {
    fail("Skate heap-cell minimum exceeds the allocator index space");
  }
  const allocation = allocations.find(({ objectId }) => objectId === ownerId);
  if (allocation === undefined) {
    fail("Skate boot descriptor requires a trusted allocation map");
  }
  validateAllocation(descriptor, allocation, allObjects, linked);

  tableExtent(
    allObjects,
    linked,
    word(descriptor, 2),
    word(descriptor, 4),
    6,
    "global",
  );
  tableExtent(
    allObjects,
    linked,
    word(descriptor, 6),
    word(descriptor, 8),
    4,
    "constant-root",
    "writable",
  );
  tableExtent(
    allObjects,
    linked,
    word(descriptor, 24),
    word(descriptor, 26),
    3,
    "symbol",
  );
  tableExtent(
    allObjects,
    linked,
    word(descriptor, 28),
    word(descriptor, 30),
    1,
    "name-pool",
  );
  tableExtent(
    allObjects,
    linked,
    word(descriptor, 32),
    word(descriptor, 34),
    4,
    "string-descriptor",
  );
  tableExtent(
    allObjects,
    linked,
    word(descriptor, 36),
    word(descriptor, 38),
    1,
    "string-pool",
  );
}

/** Validate every placed Skate runtime contract in a linked image. */
export function validateSkatePlacedContracts(
  objects: readonly SkateContractObject[],
  linked: SkatePlacedLinkResult,
  allocations: readonly SkateBootAllocation[] = [],
): void {
  for (const owner of objects) {
    for (const contract of owner.object.contracts) {
      if (
        contract.key !== RUNTIME_KEY ||
        contract.majorVersion !== RUNTIME_MAJOR ||
        contract.minorVersion !== RUNTIME_MINOR
      ) continue;
      validateDescriptor(
        owner.id,
        owner.object,
        linked,
        contract,
        objects,
        allocations,
      );
    }
  }
}
