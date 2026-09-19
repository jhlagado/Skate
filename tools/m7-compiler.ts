/** Compile Skate's M7 and M8 lambda/runtime slices to NOBJ and CP/M. */
import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";
// @deno-types="../../atom/node_modules/@jhlagado/z80-tool-services/dist/index.d.ts"
import {
  encodeNobj1,
  linkNobj1,
  parseNobj1,
} from "@jhlagado/z80-tool-services";
import { validateSkatePlacedContracts } from "./skate-contract.ts";
import { relative } from "node:path";
import { fileURLToPath } from "node:url";
import { isNumber, type Value } from "./numeric.ts";
import {
  DEFAULT_READER_LIMITS,
  type Position,
  type ReadEvent,
  type SourceLocator,
  SourceReader,
} from "./reader.ts";
import type { SourcePackage } from "./source-package.ts";
import { expandSyntaxRules } from "./syntax-rules.ts";

const projectRoot = fileURLToPath(new URL("../", import.meta.url));
const buildRoot = `${projectRoot}build`;
export interface SkateTpaProfile {
  readonly id: string;
  readonly base: number;
  readonly capacity: number;
  /** Exclusive top of the descending native stack, inside the TPA. */
  readonly stackTop: number;
  /** Guard address below the native stack. */
  readonly stackLow: number;
  /** Reserved native stack extent in bytes. */
  readonly stackCapacity: number;
  readonly imageFill: number;
  readonly permissions: number;
  readonly banked: boolean;
}

export const SKATE_NATIVE_STACK_BYTES = 4096;

/** Validate a profile before it is used for placement or code generation. */
export function validateSkateTpaProfile(profile: SkateTpaProfile): void {
  const end = profile.base + profile.capacity;
  if (
    !Number.isInteger(profile.base) ||
    !Number.isInteger(profile.capacity) ||
    profile.base < 0 ||
    profile.capacity <= 0 ||
    end > 0x10000
  ) {
    throw new RangeError("Skate TPA profile has an invalid address range");
  }
  if (
    !Number.isInteger(profile.stackTop) ||
    !Number.isInteger(profile.stackLow) ||
    !Number.isInteger(profile.stackCapacity) ||
    profile.stackLow < profile.base ||
    profile.stackTop > end ||
    profile.stackTop <= profile.stackLow ||
    profile.stackTop - profile.stackLow !== profile.stackCapacity
  ) {
    throw new RangeError(
      "Skate TPA profile has an invalid native-stack interval",
    );
  }
}

function tpaProfile(
  id: string,
  capacity: number,
): SkateTpaProfile {
  const stackTop = 0x0100 + capacity;
  return Object.freeze({
    id,
    base: 0x0100,
    capacity,
    stackTop,
    stackLow: stackTop - SKATE_NATIVE_STACK_BYTES,
    stackCapacity: SKATE_NATIVE_STACK_BYTES,
    imageFill: 0,
    permissions: 7,
    banked: false,
  });
}

/** Target profiles used by the host linker and the CP/M output adapter. */
export const SKATE_TPA_PROFILES = Object.freeze(
  {
    "cpm-64k": tpaProfile("cpm-tpa-64k", 0xe300),
    "cpm-32k": tpaProfile("cpm-tpa-32k", 0x7f00),
  } satisfies Record<string, SkateTpaProfile>,
);

export type SkateTpaProfileName = keyof typeof SKATE_TPA_PROFILES;
export const DEFAULT_SKATE_TPA_PROFILE = SKATE_TPA_PROFILES["cpm-64k"];

const ROOT_STORAGE_BYTES = 4096;
const ACTIVATION_STORAGE_BYTES = 640;
const MAX_HEAP_CELLS = 8192;

type SourceName = string | SourceLocator;

function shiftedSourceName(
  sourceName: SourceName,
  baseOffset: number,
): SourceName {
  if (typeof sourceName === "string") return sourceName;
  return {
    locate(offset) {
      return sourceName.locate(baseOffset + offset);
    },
  };
}

interface CallerBssLayout {
  readonly roots: { readonly offset: number; readonly bytes: number };
  readonly activations: { readonly offset: number; readonly bytes: number };
  readonly runtimeWorkspace: {
    readonly offset: number;
    readonly bytes: number;
  };
  readonly bitmap: { readonly offset: number; readonly bytes: number };
  readonly heap: { readonly offset: number; readonly bytes: number };
  readonly bytes: number;
}

function callerBssLayout(
  heapCells: number,
  runtimeWorkspaceBytes = 0,
): CallerBssLayout {
  if (
    !Number.isInteger(heapCells) || heapCells < 3 ||
    heapCells > MAX_HEAP_CELLS
  ) {
    throw new RangeError(
      `Skate heapCells must be an integer from 3 through ${MAX_HEAP_CELLS}`,
    );
  }
  const roots = { offset: 0, bytes: ROOT_STORAGE_BYTES };
  const activations = {
    offset: roots.offset + roots.bytes,
    bytes: ACTIVATION_STORAGE_BYTES,
  };
  const runtimeWorkspace = {
    offset: activations.offset + activations.bytes,
    bytes: runtimeWorkspaceBytes,
  };
  const bitmap = {
    offset: runtimeWorkspace.offset + runtimeWorkspace.bytes,
    bytes: Math.ceil(heapCells / 8),
  };
  const heap = {
    offset: bitmap.offset + bitmap.bytes,
    bytes: heapCells * 4,
  };
  return {
    roots,
    activations,
    runtimeWorkspace,
    bitmap,
    heap,
    bytes: heap.offset + heap.bytes,
  };
}

function align4(address: number): number {
  return (address + 3) & ~3;
}

/** Pick the largest representable heap that fits below the profile's stack guard. */
function largestHeapCells(
  callerEnd: number,
  profile: SkateTpaProfile,
  runtimeWorkspaceBytes = 0,
): number {
  const bssBase = align4(callerEnd);
  let low = 3;
  let high = MAX_HEAP_CELLS;
  let best = 0;
  while (low <= high) {
    const candidate = (low + high) >>> 1;
    if (
      bssBase + callerBssLayout(candidate, runtimeWorkspaceBytes).bytes <=
        profile.stackLow
    ) {
      best = candidate;
      low = candidate + 1;
    } else {
      high = candidate - 1;
    }
  }
  return best;
}

function imageRegion(profile: SkateTpaProfile) {
  return {
    id: 1,
    addressSpaceKey: "z80.cpu",
    storageKey: "cpm.ram",
    base: profile.base,
    capacity: profile.capacity,
    imageFill: profile.imageFill,
    permissions: profile.permissions,
    banked: profile.banked,
  } as const;
}

function targetRegion(profile: SkateTpaProfile) {
  const region = imageRegion(profile);
  return {
    id: profile.id,
    addressSpaceKey: region.addressSpaceKey,
    storageKey: region.storageKey,
    base: region.base,
    capacity: region.capacity,
    imageFill: region.imageFill,
    permissions: region.permissions,
    banked: region.banked,
  } as const;
}
const runtimeIdentity = {
  key: "org.skate.runtime",
  majorVersion: 2,
  minorVersion: 0,
} as const;
const valueIdentity = {
  key: "org.skate.value",
  majorVersion: 2,
  minorVersion: 0,
} as const;

const runtimeServices = [
  { key: "runtime.error", label: "RTERROR" },
  { key: "heap.initialize", label: "HINIT" },
  { key: "collector.configure", label: "GCSET" },
  { key: "numeric.add", label: "NADD" },
  { key: "numeric.sub", label: "NSUB" },
  { key: "numeric.mul", label: "NMUL" },
  { key: "numeric.div", label: "NDIV" },
  { key: "numeric.negate", label: "NNEG" },
  { key: "numeric.classify", label: "NCLASS" },
  { key: "execution.initialize", label: "RTINIT" },
  { key: "execution.stack_check", label: "RTSTKCHK" },
  { key: "execution.packet_new", label: "RTPKNEW" },
  { key: "execution.invoke", label: "RTINVOKE" },
  { key: "execution.tail", label: "RTTAIL" },
  { key: "execution.enter", label: "RTENTER" },
  { key: "execution.return", label: "RTRETURN" },
  { key: "execution.make_closure", label: "RTMKCLOS" },
  { key: "execution.get", label: "RTGETVAL" },
  { key: "execution.roots_refresh", label: "RTROOTS" },
  { key: "execution.current_environment", label: "RTCURENV" },
  { key: "execution.set_binding", label: "RTSETBND" },
  { key: "execution.initialize_binding", label: "RTINITBD" },
  { key: "execution.let_frame", label: "RTLETFRM" },
  { key: "execution.let_end", label: "RTLETEND" },
  { key: "pairs.cons", label: "RTCONSP" },
  { key: "pairs.car", label: "RTPAIRCA" },
  { key: "pairs.cdr", label: "RTPAIRCD" },
  { key: "pairs.pairp", label: "RTPAIRP" },
  { key: "pairs.nullp", label: "RTNULLP" },
  { key: "pairs.eq", label: "RTEQVAL" },
  { key: "pairs.list", label: "RTLIST" },
] as const;
type RuntimeService = typeof runtimeServices[number];
type RuntimeKey = RuntimeService["key"];
type ArithmeticOperator = "+" | "-" | "*" | "/";
type ResultKind = "integer" | "binary16" | "immediate" | "dynamic";
type ServiceOpcode = "CALL" | "JP";

const runtimeServiceByOperator = {
  "+": runtimeServices[3],
  "-": runtimeServices[4],
  "*": runtimeServices[5],
  "/": runtimeServices[6],
} satisfies Record<ArithmeticOperator, RuntimeService>;

interface PrimitiveApplication {
  readonly key: RuntimeKey;
  readonly arity: number | null;
  readonly resultKind: ResultKind;
}

const pairPrimitives: Readonly<Record<string, PrimitiveApplication>> = {
  cons: { key: "pairs.cons", arity: 2, resultKind: "dynamic" },
  car: { key: "pairs.car", arity: 1, resultKind: "dynamic" },
  cdr: { key: "pairs.cdr", arity: 1, resultKind: "dynamic" },
  "pair?": { key: "pairs.pairp", arity: 1, resultKind: "immediate" },
  "null?": { key: "pairs.nullp", arity: 1, resultKind: "immediate" },
  "eq?": { key: "pairs.eq", arity: 2, resultKind: "immediate" },
  list: { key: "pairs.list", arity: null, resultKind: "dynamic" },
};

const globalPrimitives = [
  { name: "+", id: 0 },
  { name: "-", id: 1 },
  { name: "*", id: 2 },
  { name: "/", id: 3 },
  { name: "=", id: 4 },
  { name: "<", id: 5 },
  { name: ">", id: 6 },
  { name: "<=", id: 7 },
  { name: ">=", id: 8 },
  { name: "cons", id: 9 },
  { name: "car", id: 10 },
  { name: "cdr", id: 11 },
  { name: "null?", id: 12 },
  { name: "pair?", id: 13 },
  { name: "list", id: 14 },
  { name: "eq?", id: 15 },
  { name: "not", id: 16 },
  { name: "number?", id: 17 },
  { name: "boolean?", id: 18 },
  { name: "symbol?", id: 19 },
  { name: "procedure?", id: 20 },
  { name: "string?", id: 21 },
  { name: "char?", id: 22 },
  { name: "display", id: 23 },
  { name: "write", id: 24 },
  { name: "newline", id: 25 },
  { name: "read-char", id: 26 },
  { name: "eof-object?", id: 27 },
  { name: "apply", id: 28 },
] as const;

export interface M7CompileResult {
  /** Canonical NOBJ 1.0 caller object before provider placement. */
  readonly objectBytes: Uint8Array;
  /** CP/M transient bytes, loaded at $0100. */
  readonly comBytes: Uint8Array;
  readonly resultKind: ResultKind;
  readonly entryAddress: number;
  /** Start of caller startup/code after the packed runtime. */
  readonly programAddress: number;
  readonly resultAddress: number;
  readonly resultTagAddress: number;
  readonly rootBaseAddress: number;
  readonly rootHighWaterAddress: number;
  readonly activationBaseAddress: number;
  readonly activationHighWaterAddress: number;
  readonly runtimeBase: number;
  readonly runtimeLength: number;
  readonly runtimeErrorAddress: number;
  /** Physical heap cells selected for this image, including reserved cell zero. */
  readonly heapCells: number;
  /** Start of the caller's zero-initialized runtime storage. */
  readonly bssBaseAddress: number;
  /** Bytes reserved in the caller's zero-initialized runtime storage. */
  readonly bssBytes: number;
  /** Exclusive end of the caller's zero-initialized runtime storage. */
  readonly bssEndAddress: number;
  /** Start of the zero-initialized mark bitmap. */
  readonly bitmapBaseAddress: number;
  readonly rootBytes: number;
  readonly activationBytes: number;
  readonly runtimeWorkspaceBytes: number;
  readonly bitmapBytes: number;
  readonly heapBytes: number;
  /** Start of the zero-initialized heap arena. */
  readonly heapBaseAddress: number;
  /** Bytes in the caller's initialized image section. */
  readonly callerImageBytes: number;
  /** Startup/procedure instructions plus the final-result printer. */
  readonly callerCodeBytes: number;
  /** Exclusive top of the profile-owned descending native stack. */
  readonly stackTopAddress: number;
  /** Inclusive lower guard address of the profile-owned native stack. */
  readonly stackLowAddress: number;
  readonly object: ReturnType<typeof parseNobj1>;
}

export interface M8CompileOptions {
  /** Physical cells, including reserved cell zero, for forced-collection tests. */
  readonly heapCells?: number;
}

export interface M9CompileOptions {
  /** Physical cells, including reserved cell zero, for forced-collection tests. */
  readonly heapCells?: number;
}

export interface M10CompileOptions {
  /** Physical cells, including reserved cell zero, for forced-collection tests. */
  readonly heapCells?: number;
  /** CP/M transient-memory profile used for placement and publication. */
  readonly tpaProfile?: SkateTpaProfile;
}

export interface M8CompileResult extends M7CompileResult {
  readonly heapCells: number;
}

export interface M9CompileResult extends M7CompileResult {
  readonly heapCells: number;
}

export interface M10CompileResult extends M7CompileResult {
  readonly heapCells: number;
  readonly tpaProfile: SkateTpaProfile;
}

interface AtomImage {
  readonly base: number;
  readonly end: number;
  readonly bytes: Uint8Array;
  readonly symbols: ReadonlyMap<string, number>;
}

function fail(at: Position | undefined, message: string): never {
  if (at === undefined) throw new SyntaxError(message);
  throw new SyntaxError(`${at.source}:${at.line}:${at.column}: ${message}`);
}

function symbolText(
  reader: SourceReader,
  event: Extract<ReadEvent, { kind: "symbol" }>,
): string {
  const table = reader.symbols.snapshot();
  const descriptor = event.id * 3;
  const offset = table.descriptors[descriptor]! |
    (table.descriptors[descriptor + 1]! << 8);
  const length = table.descriptors[descriptor + 2]!;
  return String.fromCharCode(...table.pool.subarray(offset, offset + length));
}

class EventCursor {
  private buffered: ReadEvent | null = null;
  private ready = false;

  constructor(private readonly events: Iterator<ReadEvent>) {}

  peek(): ReadEvent | null {
    if (!this.ready) {
      const next = this.events.next();
      this.buffered = next.done ? null : next.value;
      this.ready = true;
    }
    return this.buffered;
  }

  take(): ReadEvent | null {
    const event = this.peek();
    this.buffered = null;
    this.ready = false;
    return event;
  }
}

interface InternalDefinition {
  readonly name: string;
  readonly at: Position;
  readonly procedure: boolean;
}

function scannedEvent(
  events: Iterator<ReadEvent>,
  at: Position,
  context: string,
): ReadEvent {
  const next = events.next();
  if (next.done) fail(at, `Expected ${context}`);
  return next.value;
}

function skipScannedForm(
  events: Iterator<ReadEvent>,
  first: ReadEvent,
  at: Position,
): void {
  let event = first;
  while (event.kind === "quote") {
    event = scannedEvent(events, at, "quoted datum");
  }
  if (event.kind === "close") fail(event.at, "Unexpected closing parenthesis");
  if (event.kind !== "open") return;
  let nesting = 1;
  while (nesting > 0) {
    const next = scannedEvent(events, at, "closing parenthesis");
    if (next.kind === "open") nesting++;
    else if (next.kind === "close") nesting--;
  }
}

function skipScannedListTail(
  events: Iterator<ReadEvent>,
  consumedHead: ReadEvent,
  at: Position,
): void {
  let nesting = 1;
  if (consumedHead.kind === "open") nesting++;
  else if (consumedHead.kind === "close") nesting--;
  while (nesting > 0) {
    const next = scannedEvent(events, at, "closing parenthesis");
    if (next.kind === "open") nesting++;
    else if (next.kind === "close") nesting--;
  }
}

function scanLeadingDefinitions(
  sourceBytes: Uint8Array,
  sourceName: SourceName,
  bodyStart: Position,
  allowProcedureShorthand = false,
): { definitions: InternalDefinition[]; hasExpression: boolean } {
  const reader = new SourceReader(sourceBytes, sourceName);
  const events = reader.events()[Symbol.iterator]();
  let first: ReadEvent | null = null;
  for (;;) {
    const next = events.next();
    if (next.done) break;
    if (next.value.at.offset >= bodyStart.offset) {
      first = next.value;
      break;
    }
  }
  if (first === null) fail(bodyStart, "Expected a lambda body");

  const definitions: InternalDefinition[] = [];
  let hasExpression = false;
  let event: ReadEvent | null = first;
  while (event !== null && event.kind !== "close") {
    if (event.kind === "open") {
      const head = scannedEvent(events, event.at, "form after (");
      const isDefinition = head.kind === "symbol" &&
        symbolText(reader, head) === "define";
      if (isDefinition) {
        if (hasExpression) {
          fail(event.at, "Internal definitions must precede body expressions");
        }
        const target = scannedEvent(events, event.at, "definition target");
        if (target.kind === "symbol") {
          const initializer = scannedEvent(
            events,
            event.at,
            "internal definition initializer",
          );
          if (initializer.kind === "close") {
            fail(initializer.at, "An internal definition needs an initializer");
          }
          skipScannedForm(events, initializer, event.at);
          const close = scannedEvent(
            events,
            event.at,
            "closing ) after define",
          );
          if (close.kind !== "close") {
            fail(
              close.at,
              "An internal definition takes one name and one initializer",
            );
          }
          definitions.push({
            name: symbolText(reader, target),
            at: event.at,
            procedure: false,
          });
        } else if (allowProcedureShorthand && target.kind === "open") {
          const procedureName = scannedEvent(
            events,
            event.at,
            "procedure name",
          );
          if (procedureName.kind !== "symbol") {
            fail(procedureName.at, "A procedure definition needs a name");
          }
          skipScannedListTail(events, target, event.at);
          definitions.push({
            name: symbolText(reader, procedureName),
            at: event.at,
            procedure: true,
          });
        } else {
          fail(
            target.at,
            "An internal definition needs a name or procedure signature",
          );
        }
      } else {
        hasExpression = true;
        skipScannedListTail(events, head, event.at);
      }
    } else if (event.kind === "quote") {
      hasExpression = true;
      skipScannedForm(events, event, event.at);
    } else {
      hasExpression = true;
    }
    const next = events.next();
    event = next.done ? null : next.value;
  }
  return { definitions, hasExpression };
}

function scanTopLevelDefinitions(
  sourceBytes: Uint8Array,
  sourceName: SourceName,
): string[] {
  const reader = new SourceReader(sourceBytes, sourceName);
  const events = reader.events()[Symbol.iterator]();
  const names: string[] = [];
  const seen = new Set<string>();

  function remember(event: ReadEvent): void {
    if (event.kind !== "symbol") {
      fail(event.at, "A top-level definition needs an identifier");
    }
    const name = symbolText(reader, event);
    if (!seen.has(name)) {
      seen.add(name);
      names.push(name);
    }
  }

  function scanTopForm(first: ReadEvent): void {
    if (first.kind !== "open") {
      if (first.kind === "quote") skipScannedForm(events, first, first.at);
      return;
    }
    const head = scannedEvent(events, first.at, "form after (");
    const name = head.kind === "symbol" ? symbolText(reader, head) : null;
    if (name === "define") {
      const target = scannedEvent(events, first.at, "definition target");
      if (target.kind === "symbol") {
        remember(target);
        skipScannedListTail(events, target, first.at);
        return;
      }
      if (target.kind !== "open") {
        fail(
          target.at,
          "A definition target must be a name or procedure signature",
        );
      }
      const procedureName = scannedEvent(
        events,
        target.at,
        "procedure name",
      );
      remember(procedureName);
      skipScannedListTail(events, target, first.at);
      return;
    }
    if (name === "begin") {
      for (;;) {
        const next = events.next();
        if (next.done) {
          fail(first.at, "Expected closing ) after top-level begin");
        }
        if (next.value.kind === "close") return;
        scanTopForm(next.value);
      }
    }
    skipScannedListTail(events, head, first.at);
  }

  for (;;) {
    const next = events.next();
    if (next.done) return names;
    scanTopForm(next.value);
  }
}

interface ServiceSite {
  readonly label: string;
  readonly lines: string[];
  readonly opcodeLine: number;
  key: RuntimeKey;
  opcode: ServiceOpcode;
}

class ServiceEmitter {
  readonly sites: ServiceSite[] = [];
  private nextId: number;

  constructor(startId = 0) {
    this.nextId = startId;
  }

  emitCall(
    lines: string[],
    key: RuntimeKey,
    options: { checkCarry?: boolean } = {},
  ): ServiceSite {
    const id = this.nextLabelId();
    const label = "SVCALL" + id;
    const opcodeLine = lines.length + 1;
    lines.push(label + ":", "        CALL $0000");
    const site: ServiceSite = {
      label,
      lines,
      opcodeLine,
      key,
      opcode: "CALL",
    };
    this.sites.push(site);
    if (options.checkCarry === true) this.emitErrorJump(lines, id);
    return site;
  }

  emitJump(lines: string[], key: RuntimeKey): ServiceSite {
    const id = this.nextLabelId();
    const label = "SVCALL" + id;
    const opcodeLine = lines.length + 1;
    lines.push(label + ":", "        JP $0000");
    const site: ServiceSite = {
      label,
      lines,
      opcodeLine,
      key,
      opcode: "JP",
    };
    this.sites.push(site);
    return site;
  }

  private emitErrorJump(lines: string[], id: string): void {
    const label = "SVCERR" + id;
    const opcodeLine = lines.length + 1;
    lines.push(label + ":", "        JP C,$0000");
    this.sites.push({
      label,
      lines,
      opcodeLine,
      key: "runtime.error",
      opcode: "JP",
    });
  }

  private nextLabelId(): string {
    if (this.nextId >= 36 ** 2) {
      throw new RangeError(
        "M7 output exceeds its eight-character service-label table",
      );
    }
    const id = this.nextId.toString(36).toUpperCase().padStart(2, "0");
    this.nextId++;
    return id;
  }
}

interface LocalOperandReference {
  readonly label: string;
  readonly target: string;
  readonly addend: number;
}

interface LocalCallReference {
  readonly label: string;
  readonly target: string;
}

interface LocalDataReference {
  readonly siteLabel: string;
  readonly addend: number;
  readonly target: string;
  readonly valueKind: 2 | 3;
}

class LocalReferenceEmitter {
  readonly operandReferences: LocalOperandReference[] = [];
  readonly callReferences: LocalCallReference[] = [];
  readonly dataReferences: LocalDataReference[] = [];
  private operandIndex: number;
  private callIndex: number;

  constructor(operandIndex = 0, callIndex = 0) {
    this.operandIndex = operandIndex;
    this.callIndex = callIndex;
  }

  emitAddressLoad(lines: string[], target: string, addend = 0): void {
    if (this.operandIndex >= 36 ** 4) {
      throw new RangeError(
        "M7 output exceeds its local-address fixup capacity",
      );
    }
    const id = this.operandIndex.toString(36).toUpperCase().padStart(4, "0");
    this.operandIndex++;
    const label = "DREF" + id;
    this.operandReferences.push({ label, target, addend });
    lines.push(label + ":", "        LD HL,0");
  }

  emitLocalCall(lines: string[], target: string): void {
    if (this.callIndex >= 36 ** 4) {
      throw new RangeError("M9 output exceeds its local-call fixup capacity");
    }
    const id = this.callIndex.toString(36).toUpperCase().padStart(4, "0");
    this.callIndex++;
    const label = "LCRF" + id;
    this.callReferences.push({ label, target });
    lines.push(label + ":", "        CALL $0000");
  }

  addDataReference(
    siteLabel: string,
    addend: number,
    target: string,
    valueKind: 2 | 3 = 2,
  ): void {
    this.dataReferences.push({ siteLabel, addend, target, valueKind });
  }
}

interface ExpressionResult {
  readonly kind: ResultKind;
  readonly tailSites: readonly ServiceSite[];
}

interface ProcedureBlock {
  readonly entry: string;
  readonly entryAlias: string;
  readonly body: string;
  readonly descriptor: string;
  readonly minArity: number;
  readonly hasRest: boolean;
  readonly slotCount: number;
  readonly lines: string[];
}

interface FormalParameters {
  readonly required: readonly string[];
  readonly rest: string | null;
}

interface ProcedureScope {
  readonly label: string;
  readonly bindings: ReadonlyMap<string, number>;
  captureNeeded: boolean;
}

type CompilerMode = "M7" | "M8" | "M9" | "M10";

type LiteralAction =
  | { readonly kind: "value"; readonly tag: number; readonly payload: number }
  | { readonly kind: "pair" };

interface LiteralPlan {
  readonly actions: readonly LiteralAction[];
  readonly rootIndex: number;
}

interface ReaderTables {
  readonly symbols: ReturnType<SourceReader["symbols"]["snapshot"]>;
  readonly strings: ReturnType<SourceReader["strings"]["snapshot"]>;
}

interface GlobalSlot {
  readonly name: string;
  readonly symbolIndex: number;
  readonly tag: number;
  readonly payload: number;
}

interface CompilePlan {
  readonly topBody: readonly string[];
  readonly procedures: readonly ProcedureBlock[];
  readonly resultKind: ResultKind;
  readonly heapCells: number;
  readonly literals: readonly LiteralPlan[];
  readonly literalCellCount: number;
  readonly readerTables: ReaderTables;
  readonly globals: readonly GlobalSlot[];
}

function valueResultKind(value: Value): ResultKind {
  if (!isNumber(value)) return "immediate";
  return value[0] === 3 ? "integer" : "binary16";
}

function mergeResultKinds(left: ResultKind, right: ResultKind): ResultKind {
  return left === right ? left : "dynamic";
}

class SchemeExpressionCompiler {
  private readonly cursor: EventCursor;
  private readonly topBody: string[] = [];
  private readonly procedureBlocks: ProcedureBlock[] = [];
  private currentLines = this.topBody;
  private readonly scopeStack: ProcedureScope[] = [];
  private readonly literals: LiteralPlan[] = [];
  private readonly globalBindings = new Map<string, number>();
  private readonly globalNames: string[] = [];
  private readonly initializedGlobalNames = new Set<string>();
  private tempDepth = 0;
  private ifIndex = 0;
  private procedureIndex = 0;

  constructor(
    private readonly sourceBytes: Uint8Array,
    private readonly sourceName: SourceName,
    private readonly reader: SourceReader,
    private readonly services: ServiceEmitter,
    private readonly references: LocalReferenceEmitter,
    private readonly mode: CompilerMode = "M7",
    private readonly heapCells = 512,
    globalDefinitionNames: readonly string[] = [],
  ) {
    this.cursor = new EventCursor(reader.events());
    if (mode === "M10") {
      for (const primitive of globalPrimitives) {
        this.addGlobalName(primitive.name);
        this.initializedGlobalNames.add(primitive.name);
      }
      for (const name of globalDefinitionNames) this.addGlobalName(name);
    }
  }

  compile(): CompilePlan {
    const result = this.mode === "M10"
      ? this.readTopLevelProgram()
      : this.readExpression(true);
    const trailing = this.cursor.peek();
    if (trailing !== null) fail(trailing.at, "Unexpected trailing source");
    for (const site of result.tailSites) this.patchTailCall(site);
    this.services.emitJump(this.topBody, "execution.return");
    const globals = this.globalNames.map((name): GlobalSlot => {
      let symbolIndex: number;
      try {
        symbolIndex = this.reader.symbols.intern(
          new TextEncoder().encode(name),
        );
      } catch (error) {
        fail(
          undefined,
          error instanceof Error ? error.message : String(error),
        );
      }
      const primitive = globalPrimitives.find(({ name: candidate }) =>
        candidate === name
      );
      return {
        name,
        symbolIndex,
        tag: 0,
        payload: primitive === undefined ? 0xfe05 : 0xfe20 + primitive.id,
      };
    });
    return {
      topBody: this.topBody,
      procedures: this.procedureBlocks,
      resultKind: result.kind,
      heapCells: this.heapCells,
      literals: this.literals,
      literalCellCount: this.literals.reduce(
        (total, literal) => total + literalCellCount(literal.actions),
        0,
      ),
      readerTables: {
        symbols: this.reader.symbols.snapshot(),
        strings: this.reader.strings.snapshot(),
      },
      globals,
    };
  }

  private addGlobalName(name: string): number {
    const existing = this.globalBindings.get(name);
    if (existing !== undefined) return existing;
    const slot = this.globalNames.length;
    if (slot >= 8192) fail(undefined, "Global table exceeds 8192 bindings");
    this.globalBindings.set(name, slot);
    this.globalNames.push(name);
    return slot;
  }

  private readTopLevelProgram(): ExpressionResult {
    let result: ExpressionResult | null = null;
    while (this.cursor.peek() !== null) {
      result = this.readTopLevelForm(false);
    }
    if (result === null) fail(undefined, "Expected a top-level form");
    return result;
  }

  private readTopLevelForm(tailAllowed: boolean): ExpressionResult {
    const event = this.cursor.take();
    if (event === null) fail(undefined, "Expected a top-level form");
    if (event.kind !== "open") return this.readExpression(tailAllowed, event);
    const head = this.cursor.take();
    if (head === null) fail(event.at, "Expected a form after (");
    if (head.kind === "close") {
      fail(event.at, "The empty list is not an application");
    }
    if (head.kind === "symbol") {
      const name = symbolText(this.reader, head);
      if (name === "define") return this.readTopLevelDefinition(event.at);
      if (name === "begin") return this.readTopLevelBegin(event.at);
    }
    return this.readList(event.at, tailAllowed, head);
  }

  private readTopLevelBegin(at: Position): ExpressionResult {
    let result: ExpressionResult | null = null;
    for (;;) {
      const next = this.cursor.peek();
      if (next === null) fail(at, "Expected closing ) after top-level begin");
      if (next.kind === "close") {
        this.cursor.take();
        if (result === null) {
          this.emitValue([0, 0xfe04]);
          return { kind: "immediate", tailSites: [] };
        }
        return result;
      }
      result = this.readTopLevelForm(false);
    }
  }

  private readTopLevelDefinition(at: Position): ExpressionResult {
    const target = this.cursor.take();
    if (target?.kind === "symbol") {
      const name = symbolText(this.reader, target);
      const slot = this.globalBindings.get(name);
      if (slot === undefined) {
        fail(target.at, `Global ${JSON.stringify(name)} was not reserved`);
      }
      this.readRequiredExpression(at, "definition initializer");
      this.expectClose(at, "define");
      return this.writeGlobalDefinition(name, slot);
    }
    if (target?.kind !== "open") {
      fail(target?.at ?? at, "define requires a name or procedure signature");
    }
    const procedure = this.cursor.take();
    if (procedure?.kind !== "symbol") {
      fail(procedure?.at ?? at, "A procedure definition needs a name");
    }
    const name = symbolText(this.reader, procedure);
    const slot = this.globalBindings.get(name);
    if (slot === undefined) {
      fail(procedure.at, `Global ${JSON.stringify(name)} was not reserved`);
    }
    const parameters = this.readProcedureSignature(at);
    this.compileLambdaBody(at, parameters, "define");
    return this.writeGlobalDefinition(name, slot);
  }

  private writeGlobalDefinition(
    name: string,
    slot: number,
  ): ExpressionResult {
    const service = this.initializedGlobalNames.has(name)
      ? "execution.set_binding"
      : "execution.initialize_binding";
    this.services.emitCall(this.currentLines, service);
    this.currentLines.push(`        DW 65535,${slot}`);
    this.initializedGlobalNames.add(name);
    return { kind: "immediate", tailSites: [] };
  }

  private readExpression(
    tailAllowed = false,
    initialEvent?: ReadEvent,
  ): ExpressionResult {
    const event = initialEvent ?? this.cursor.take();
    if (event === null || event === undefined) {
      fail(undefined, "Expected one Scheme expression");
    }
    switch (event.kind) {
      case "value":
        this.emitValue(event.value);
        return { kind: valueResultKind(event.value), tailSites: [] };
      case "open":
        return this.readList(event.at, tailAllowed);
      case "symbol":
        return this.readIdentifier(event);
      case "string":
        if (this.mode !== "M9" && this.mode !== "M10") {
          return fail(
            event.at,
            `String literals are not emitted in ${this.mode}`,
          );
        }
        this.emitValue([1, 0x8000 | event.id]);
        return { kind: "dynamic", tailSites: [] };
      case "quote":
        if (this.mode !== "M9" && this.mode !== "M10") {
          return fail(event.at, `Quoted data is not emitted in ${this.mode}`);
        }
        return this.readQuotedExpression(event.at, false);
      case "dot":
        return fail(event.at, "A dot is not valid in an expression");
      case "close":
        return fail(event.at, "Unexpected closing parenthesis");
    }
  }

  private readIdentifier(
    event: Extract<ReadEvent, { kind: "symbol" }>,
  ): ExpressionResult {
    const name = symbolText(this.reader, event);
    const binding = this.findLexicalBinding(name);
    if (binding !== null) {
      if (binding.depth !== 0) {
        if (this.mode === "M7") {
          fail(
            event.at,
            `Captured variable ${JSON.stringify(name)} is deferred to M8`,
          );
        }
        this.markCapture(binding.depth);
      }
      this.services.emitCall(this.currentLines, "execution.get");
      this.currentLines.push(`        DW ${binding.depth},${binding.slot}`);
      return { kind: "dynamic", tailSites: [] };
    }
    if (this.mode === "M10") {
      const slot = this.globalBindings.get(name);
      if (slot !== undefined) {
        this.services.emitCall(this.currentLines, "execution.get");
        this.currentLines.push(`        DW 65535,${slot}`);
        return { kind: "dynamic", tailSites: [] };
      }
    }
    fail(event.at, `Unbound identifier ${JSON.stringify(name)}`);
  }

  private readList(
    at: Position,
    tailAllowed: boolean,
    suppliedHead?: ReadEvent,
  ): ExpressionResult {
    const head = suppliedHead ?? this.cursor.take();
    if (head === null) fail(at, "Expected a form after (");
    if (head.kind === "close") fail(at, "The empty list is not an application");
    if (head.kind === "symbol") {
      const name = symbolText(this.reader, head);
      if (name === "if") return this.readIf(head.at, tailAllowed);
      if (name === "begin") return this.readBegin(head.at, tailAllowed);
      if (name === "lambda") return this.readLambda(head.at);
      if (name === "set!" && this.mode !== "M7") return this.readSet(head.at);
      if (this.mode === "M10") {
        if (name === "let") return this.readLet(head.at, tailAllowed);
        if (name === "cond") return this.readCond(head.at, tailAllowed);
        if (name === "and" || name === "or") {
          return this.readAndOr(name, head.at, tailAllowed);
        }
      }
      if (
        (name === "+" || name === "-" || name === "*" || name === "/") &&
        this.mode !== "M10" && this.findLexicalBinding(name) === null
      ) {
        return this.readArithmetic(name, head.at);
      }
      if (
        this.mode === "M9" && this.findLexicalBinding(name) === null &&
        pairPrimitives[name] !== undefined
      ) {
        return this.readPairPrimitive(name, at, head.at);
      }
      if (name === "quote" && (this.mode === "M9" || this.mode === "M10")) {
        return this.readQuotedExpression(head.at, true);
      }
      if (name === "quote" || name === "define" || name === "set!") {
        fail(
          head.at,
          `Unsupported form ${JSON.stringify(name)} in ${this.mode}`,
        );
      }
    }
    return this.readApplication(at, head, tailAllowed);
  }

  private readIf(at: Position, tailAllowed: boolean): ExpressionResult {
    this.readRequiredExpression(at, "if test");
    const id = this.nextIfId(at);
    const trueLabel = "IFTR" + id;
    const falseLabel = "IFFL" + id;
    const endLabel = "IFEN" + id;

    this.currentLines.push(
      "        CP 0",
      "        JP NZ," + trueLabel,
      "        LD DE,$FE00",
      "        OR A",
      "        SBC HL,DE",
      "        JP Z," + falseLabel,
      trueLabel + ":",
    );

    const consequent = this.readRequiredExpression(
      at,
      "if consequent",
      tailAllowed,
    );
    const following = this.cursor.peek();
    if (following === null) fail(at, "Expected closing ) after if");
    this.currentLines.push("        JP " + endLabel, falseLabel + ":");

    let alternative: ExpressionResult;
    if (following.kind === "close") {
      this.emitValue([0, 0xfe04]);
      alternative = { kind: "immediate", tailSites: [] };
    } else {
      alternative = this.readRequiredExpression(
        at,
        "if alternative",
        tailAllowed,
      );
    }
    this.expectClose(at, "if");
    this.currentLines.push(endLabel + ":");
    return {
      kind: mergeResultKinds(consequent.kind, alternative.kind),
      tailSites: [...consequent.tailSites, ...alternative.tailSites],
    };
  }

  private readBegin(at: Position, tailAllowed: boolean): ExpressionResult {
    const first = this.cursor.peek();
    if (first === null) fail(at, "Expected closing ) after begin");
    if (first.kind === "close") {
      this.cursor.take();
      this.emitValue([0, 0xfe04]);
      return { kind: "immediate", tailSites: [] };
    }
    return this.readSequence(at, "begin", tailAllowed);
  }

  private readSequence(
    at: Position,
    form: string,
    tailAllowed: boolean,
  ): ExpressionResult {
    let finalResult: ExpressionResult | null = null;
    let remaining = 0;
    for (;;) {
      const next = this.cursor.peek();
      if (next === null) fail(at, `Expected closing ) after ${form}`);
      if (next.kind === "close") {
        this.cursor.take();
        if (finalResult === null) {
          this.emitValue([0, 0xfe04]);
          return { kind: "immediate", tailSites: [] };
        }
        return finalResult;
      }
      if (remaining === 0) {
        remaining = countRemainingForms(
          this.sourceBytes,
          next.at,
          this.sourceName,
        );
      }
      const result = this.readExpression(tailAllowed && remaining === 1);
      remaining--;
      finalResult = result;
    }
  }

  private readAndOr(
    form: "and" | "or",
    at: Position,
    tailAllowed: boolean,
  ): ExpressionResult {
    const first = this.cursor.peek();
    if (first === null) fail(at, `Expected closing ) after ${form}`);
    if (first.kind === "close") {
      this.cursor.take();
      this.emitValue(form === "and" ? [0, 0xfe01] : [0, 0xfe00]);
      return { kind: "immediate", tailSites: [] };
    }

    let remaining = countRemainingForms(
      this.sourceBytes,
      first.at,
      this.sourceName,
    );
    const endLabel = (form === "and" ? "ANDN" : "OREN") +
      this.nextIfId(at);
    const tailSites: ServiceSite[] = [];
    let resultKind: ResultKind | null = null;
    while (remaining > 0) {
      const isLast = remaining === 1;
      const operandAt = this.cursor.peek()?.at ?? at;
      const result = this.readRequiredExpression(
        at,
        `${form} operand`,
        tailAllowed && isLast,
      );
      resultKind = resultKind === null
        ? result.kind
        : mergeResultKinds(resultKind, result.kind);
      tailSites.push(...result.tailSites);
      remaining--;
      if (isLast) break;

      if (form === "and") {
        const continueLabel = "ANDX" + this.nextIfId(operandAt);
        this.currentLines.push(
          "        CP 0",
          "        JP NZ," + continueLabel,
          "        LD D,H",
          "        LD E,L",
          "        LD HL,0FE00H",
          "        OR A",
          "        SBC HL,DE",
          "        LD H,D",
          "        LD L,E",
          "        JP NZ," + continueLabel,
          "        XOR A",
          "        LD HL,0FE00H",
          "        JP " + endLabel,
          continueLabel + ":",
        );
      } else {
        const continueLabel = "ORNX" + this.nextIfId(operandAt);
        this.currentLines.push(
          "        CP 0",
          "        JP NZ," + endLabel,
          "        LD D,H",
          "        LD E,L",
          "        LD HL,0FE00H",
          "        OR A",
          "        SBC HL,DE",
          "        LD H,D",
          "        LD L,E",
          "        JP Z," + continueLabel,
          "        JP " + endLabel,
          continueLabel + ":",
        );
      }
    }
    this.expectClose(at, form);
    this.currentLines.push(endLabel + ":");
    return {
      kind: resultKind ?? "immediate",
      tailSites,
    };
  }

  private readCond(at: Position, tailAllowed: boolean): ExpressionResult {
    const endLabel = "CDEN" + this.nextIfId(at);
    const tailSites: ServiceSite[] = [];
    let resultKind: ResultKind = "immediate";
    let sawResult = false;
    let sawElse = false;
    for (;;) {
      const clause = this.cursor.take();
      if (clause === null) fail(at, "Expected closing ) after cond");
      if (clause.kind === "close") break;
      if (clause.kind !== "open") {
        fail(clause.at, "A cond clause must be a list");
      }
      if (sawElse) fail(clause.at, "The cond else clause must be last");

      const first = this.cursor.take();
      if (first === null || first.kind === "close") {
        fail(first?.at ?? clause.at, "A cond clause needs a test and body");
      }
      const isElse = first.kind === "symbol" &&
        symbolText(this.reader, first) === "else";
      if (isElse) {
        sawElse = true;
        const body = this.cursor.peek();
        if (body === null || body.kind === "close") {
          fail(body?.at ?? clause.at, "A cond else clause needs a body");
        }
        const bodyResult = this.readSequence(
          clause.at,
          "cond clause",
          tailAllowed,
        );
        resultKind = sawResult
          ? mergeResultKinds(resultKind, bodyResult.kind)
          : bodyResult.kind;
        sawResult = true;
        tailSites.push(...bodyResult.tailSites);
        const following = this.cursor.peek();
        if (following === null) fail(at, "Expected closing ) after cond");
        if (following.kind !== "close") {
          fail(following.at, "The cond else clause must be last");
        }
        this.cursor.take();
        break;
      }

      const testResult = this.readExpression(false, first);
      const body = this.cursor.peek();
      if (body === null || body.kind === "close") {
        fail(
          body?.at ?? clause.at,
          "A cond clause needs a body after its test",
        );
      }
      if (body.kind === "symbol" && symbolText(this.reader, body) === "=>") {
        fail(body.at, "cond arrow clauses are not supported");
      }
      const bodyLabel = "CDBD" + this.nextIfId(clause.at);
      const nextLabel = "CDNX" + this.nextIfId(clause.at);
      this.currentLines.push(
        "        CP 0",
        "        JP NZ," + bodyLabel,
        "        LD DE,0FE00H",
        "        OR A",
        "        SBC HL,DE",
        "        JP NZ," + bodyLabel,
        "        JP " + nextLabel,
        bodyLabel + ":",
      );
      const bodyResult = this.readSequence(
        clause.at,
        "cond clause",
        tailAllowed,
      );
      resultKind = sawResult
        ? mergeResultKinds(resultKind, bodyResult.kind)
        : bodyResult.kind;
      sawResult = true;
      tailSites.push(...testResult.tailSites, ...bodyResult.tailSites);
      this.currentLines.push("        JP " + endLabel, nextLabel + ":");
    }

    if (!sawElse) {
      this.emitValue([0, 0xfe04]);
      resultKind = mergeResultKinds(resultKind, "immediate");
    }
    this.currentLines.push(endLabel + ":");
    return { kind: sawResult ? resultKind : "immediate", tailSites };
  }

  private readLet(at: Position, tailAllowed: boolean): ExpressionResult {
    const bindingList = this.cursor.take();
    if (bindingList?.kind !== "open") {
      fail(bindingList?.at ?? at, "let requires a binding list");
    }
    const bindingCount = countListChildren(
      this.sourceBytes,
      bindingList.at,
      this.sourceName,
    );
    if (bindingCount > 510) {
      fail(bindingList.at, "let exceeds the configured heap frame capacity");
    }

    const bindings = new Map<string, number>();
    this.currentLines.push("        PUSH IY", "        LD BC," + bindingCount);
    this.services.emitCall(
      this.currentLines,
      "execution.packet_new",
      { checkCarry: true },
    );
    this.currentLines.push("        PUSH DE");

    for (let slot = 0; slot < bindingCount; slot++) {
      const entry = this.cursor.take();
      if (entry?.kind !== "open") {
        fail(entry?.at ?? bindingList.at, "Each let binding must be a list");
      }
      const nameEvent = this.cursor.take();
      if (nameEvent?.kind !== "symbol") {
        fail(nameEvent?.at ?? entry.at, "Each let binding needs an identifier");
      }
      const name = symbolText(this.reader, nameEvent);
      if (bindings.has(name)) {
        fail(nameEvent.at, `Duplicate let binding ${JSON.stringify(name)}`);
      }
      const initializer = this.cursor.peek();
      if (initializer === null || initializer.kind === "close") {
        fail(
          initializer?.at ?? entry.at,
          "Each let binding needs an initializer",
        );
      }
      this.readExpression(false);
      this.expectClose(entry.at, "let binding");
      this.storePacketValueFromStack(8 + slot * 4);
      bindings.set(name, slot);
    }
    this.expectClose(bindingList.at, "let bindings");

    this.currentLines.push("        POP DE", "        LD BC," + bindingCount);
    this.services.emitCall(this.currentLines, "execution.let_frame");

    const parentScopes = this.scopeStack.slice();
    this.scopeStack.push({
      label: "LET",
      bindings,
      captureNeeded: false,
    });
    let bodyResult: ExpressionResult;
    try {
      const body = this.cursor.peek();
      if (body === null || body.kind === "close") {
        fail(body?.at ?? at, "A let body must not be empty");
      }
      bodyResult = this.readSequence(at, "let", tailAllowed);
    } finally {
      this.scopeStack.pop();
      this.scopeStack.splice(0, this.scopeStack.length, ...parentScopes);
    }
    this.services.emitCall(this.currentLines, "execution.let_end");
    return bodyResult;
  }

  private readLambda(at: Position): ExpressionResult {
    const formalOpen = this.cursor.take();
    let parameters: FormalParameters;
    if (formalOpen?.kind === "open") {
      parameters = this.readParameterList(at, "lambda");
    } else if (formalOpen?.kind === "symbol") {
      parameters = {
        required: [],
        rest: symbolText(this.reader, formalOpen),
      };
    } else {
      fail(
        formalOpen?.at ?? at,
        "Expected a parameter list or rest identifier after lambda",
      );
    }
    return this.compileLambdaBody(at, parameters, "lambda");
  }

  private readProcedureSignature(at: Position): FormalParameters {
    return this.readParameterList(at, "procedure definition");
  }

  private readParameterList(at: Position, owner: string): FormalParameters {
    const parameters: string[] = [];
    const names = new Set<string>();
    let rest: string | null = null;
    for (;;) {
      const formal = this.cursor.take();
      if (formal === null) {
        fail(at, `Expected closing ) after ${owner} parameters`);
      }
      if (formal.kind === "close") break;
      if (formal.kind === "dot") {
        if (rest !== null || parameters.length === 0) {
          fail(formal.at, `${owner} rest marker needs preceding parameters`);
        }
        if (parameters.length >= 510) {
          fail(
            formal.at,
            "Procedure parameters exceed the configured heap frame capacity",
          );
        }
        const restFormal = this.cursor.take();
        if (restFormal?.kind !== "symbol") {
          fail(
            restFormal?.at ?? formal.at,
            `${owner} rest marker needs one identifier before )`,
          );
        }
        const restName = symbolText(this.reader, restFormal);
        if (names.has(restName)) {
          fail(
            restFormal.at,
            `Duplicate parameter ${JSON.stringify(restName)}`,
          );
        }
        const close = this.cursor.take();
        if (close?.kind !== "close") {
          fail(
            close?.at ?? restFormal.at,
            `${owner} rest parameter must be followed by )`,
          );
        }
        rest = restName;
        break;
      }
      if (formal.kind !== "symbol") {
        fail(
          formal.at,
          `${this.mode} procedures require distinct parameter identifiers`,
        );
      }
      const name = symbolText(this.reader, formal);
      if (names.has(name)) {
        fail(formal.at, `Duplicate parameter ${JSON.stringify(name)}`);
      }
      if (parameters.length >= 510) {
        fail(
          formal.at,
          "Procedure arity exceeds the configured heap frame capacity",
        );
      }
      names.add(name);
      parameters.push(name);
    }
    return { required: parameters, rest };
  }

  private compileLambdaBody(
    at: Position,
    parameters: FormalParameters,
    form: string,
    closureLines: string[] = this.currentLines,
  ): ExpressionResult {
    const bindings = new Map<string, number>();
    for (const name of parameters.required) bindings.set(name, bindings.size);
    if (parameters.rest !== null) {
      bindings.set(parameters.rest, bindings.size);
    }
    const firstBody = this.cursor.peek();
    if (firstBody === null || firstBody.kind === "close") {
      fail(firstBody?.at ?? at, `A ${form} body must not be empty`);
    }

    const internalDefinitions = this.mode !== "M7"
      ? scanLeadingDefinitions(
        this.sourceBytes,
        this.sourceName,
        firstBody.at,
        this.mode === "M10",
      )
      : { definitions: [], hasExpression: true };
    if (this.mode !== "M7" && !internalDefinitions.hasExpression) {
      fail(
        firstBody.at,
        `A ${form} body needs an expression after its definitions`,
      );
    }
    for (const definition of internalDefinitions.definitions) {
      if (bindings.has(definition.name)) {
        fail(
          definition.at,
          `Duplicate parameter or definition ${
            JSON.stringify(definition.name)
          }`,
        );
      }
      if (bindings.size >= 510) {
        fail(
          definition.at,
          "Lambda frame exceeds the configured heap capacity",
        );
      }
      bindings.set(definition.name, bindings.size);
    }

    const labels = this.nextProcedureLabels(at);
    const parentLines = this.currentLines;
    const bodyLines: string[] = [];
    const parentScopes = this.scopeStack.slice();
    const scope: ProcedureScope = {
      label: labels.entry,
      bindings,
      captureNeeded: false,
    };
    this.currentLines = bodyLines;
    this.scopeStack.push(scope);
    let bodyResult: ExpressionResult;
    try {
      for (const definition of internalDefinitions.definitions) {
        this.readInternalDefinition(
          definition,
          bindings.get(definition.name)!,
        );
      }
      bodyResult = this.readSequence(at, form, true);
    } finally {
      this.scopeStack.pop();
      this.currentLines = parentLines;
      this.scopeStack.splice(0, this.scopeStack.length, ...parentScopes);
    }
    for (const site of bodyResult.tailSites) this.patchTailCall(site);
    this.services.emitJump(bodyLines, "execution.return");

    const wrapperLines: string[] = [
      labels.entry + ":",
    ];
    this.references.emitAddressLoad(wrapperLines, labels.descriptor);
    this.services.emitCall(wrapperLines, "execution.enter");
    wrapperLines.push("        JP " + labels.body, labels.body + ":");
    wrapperLines.push(...bodyLines);
    this.procedureBlocks.push({
      entry: labels.entry,
      entryAlias: labels.entryAlias,
      body: labels.body,
      descriptor: labels.descriptor,
      minArity: parameters.required.length,
      hasRest: parameters.rest !== null,
      slotCount: bindings.size,
      lines: wrapperLines,
    });
    this.references.addDataReference(
      labels.descriptor,
      0,
      labels.entryAlias,
    );

    this.references.emitAddressLoad(closureLines, labels.descriptor);
    if (scope.captureNeeded) {
      this.services.emitCall(
        closureLines,
        "execution.current_environment",
      );
    } else {
      closureLines.push("        LD DE,0");
    }
    this.services.emitCall(closureLines, "execution.make_closure");
    return { kind: "dynamic", tailSites: [] };
  }

  private readInternalDefinition(
    definition: InternalDefinition,
    slot: number,
  ): void {
    const open = this.cursor.take();
    if (open?.kind !== "open") {
      fail(open?.at ?? definition.at, "Expected an internal definition");
    }
    const form = this.cursor.take();
    if (form?.kind !== "symbol" || symbolText(this.reader, form) !== "define") {
      fail(
        form?.at ?? definition.at,
        "Expected define in the internal definition",
      );
    }
    const target = this.cursor.take();
    if (definition.procedure) {
      if (target?.kind !== "open") {
        fail(target?.at ?? definition.at, "Expected a procedure signature");
      }
      const name = this.cursor.take();
      if (
        name?.kind !== "symbol" ||
        symbolText(this.reader, name) !== definition.name
      ) {
        fail(
          name?.at ?? definition.at,
          "Internal definition changed during compilation",
        );
      }
      const parameters = this.readProcedureSignature(definition.at);
      this.compileLambdaBody(definition.at, parameters, "define");
    } else {
      if (
        target?.kind !== "symbol" ||
        symbolText(this.reader, target) !== definition.name
      ) {
        fail(
          target?.at ?? definition.at,
          "Internal definition changed during compilation",
        );
      }
      this.readRequiredExpression(
        definition.at,
        "internal definition initializer",
      );
      this.expectClose(definition.at, "define");
    }
    this.services.emitCall(this.currentLines, "execution.initialize_binding");
    this.currentLines.push(`        DW 0,${slot}`);
  }

  private readSet(at: Position): ExpressionResult {
    const target = this.cursor.take();
    if (target?.kind !== "symbol") {
      fail(target?.at ?? at, "set! requires a lexical identifier");
    }
    const name = symbolText(this.reader, target);
    const binding = this.findLexicalBinding(name);
    const globalSlot = this.mode === "M10"
      ? this.globalBindings.get(name)
      : undefined;
    if (binding === null && globalSlot === undefined) {
      fail(target.at, `Unbound identifier ${JSON.stringify(name)}`);
    }
    if (binding !== null && binding.depth > 0) {
      this.markCapture(binding.depth);
    }
    this.readRequiredExpression(at, "set! value");
    this.expectClose(at, "set!");
    this.services.emitCall(this.currentLines, "execution.set_binding");
    this.currentLines.push(
      binding !== null
        ? `        DW ${binding.depth},${binding.slot}`
        : `        DW 65535,${globalSlot}`,
    );
    return { kind: "immediate", tailSites: [] };
  }

  private readApplication(
    at: Position,
    operatorEvent: ReadEvent,
    tailAllowed: boolean,
  ): ExpressionResult {
    const childCount = countListChildren(
      this.sourceBytes,
      at,
      this.sourceName,
    );
    if (childCount < 1) fail(at, "The empty list is not an application");
    const argumentCount = childCount - 1;
    if (argumentCount > 510) {
      fail(at, "Application arity exceeds the configured heap frame capacity");
    }
    this.currentLines.push("        LD BC," + argumentCount);
    this.services.emitCall(
      this.currentLines,
      "execution.packet_new",
      { checkCarry: true },
    );
    this.currentLines.push("        PUSH DE");

    this.readExpression(false, operatorEvent);
    this.storePacketValueFromStack(4);
    for (let slot = 0; slot < argumentCount; slot++) {
      this.readRequiredExpression(at, "application argument");
      this.storePacketValueFromStack(8 + slot * 4);
    }
    this.expectClose(at, "application");
    this.currentLines.push(
      "        POP DE",
      "        PUSH DE",
      "        LD BC," + argumentCount,
    );
    this.services.emitCall(
      this.currentLines,
      "execution.stack_check",
      { checkCarry: true },
    );
    const callSite = this.services.emitCall(
      this.currentLines,
      "execution.invoke",
    );
    this.currentLines.push("        POP DE");
    this.emitRootCleanupFromDE();
    return {
      kind: "dynamic",
      tailSites: tailAllowed ? [callSite] : [],
    };
  }

  private readPairPrimitive(
    name: string,
    listAt: Position,
    at: Position,
  ): ExpressionResult {
    const primitive = pairPrimitives[name];
    if (primitive === undefined) {
      throw new Error(`Unknown pair primitive ${name}`);
    }
    const childCount = countListChildren(
      this.sourceBytes,
      listAt,
      this.sourceName,
    );
    const argumentCount = childCount - 1;
    if (primitive.arity !== null && argumentCount !== primitive.arity) {
      fail(
        at,
        `${name} requires exactly ${primitive.arity} argument${
          primitive.arity === 1 ? "" : "s"
        }`,
      );
    }
    if (argumentCount > 510) {
      fail(listAt, "Application arity exceeds the configured root capacity");
    }

    this.currentLines.push("        LD BC," + argumentCount);
    this.services.emitCall(
      this.currentLines,
      "execution.packet_new",
      { checkCarry: true },
    );
    this.currentLines.push("        PUSH DE");
    for (let slot = 0; slot < argumentCount; slot++) {
      this.readRequiredExpression(at, `${name} argument`);
      this.storePacketValueFromStack(8 + slot * 4);
    }
    this.expectClose(at, name);
    this.currentLines.push(
      "        POP DE",
      "        PUSH DE",
      "        LD BC," + argumentCount,
    );
    this.services.emitCall(this.currentLines, primitive.key);
    this.currentLines.push("        POP DE");
    this.emitRootCleanupFromDE();
    return { kind: primitive.resultKind, tailSites: [] };
  }

  private readQuotedExpression(
    at: Position,
    explicitForm: boolean,
  ): ExpressionResult {
    const actions: LiteralAction[] = [];
    this.readQuotedDatum(actions, at);
    if (explicitForm) this.expectClose(at, "quote");

    const hasPair = actions.some((action) => action.kind === "pair");
    if (!hasPair) {
      const value = actions[0];
      if (actions.length !== 1 || value?.kind !== "value") {
        throw new Error("Atomic quoted data did not produce one value");
      }
      this.emitValue([value.tag, value.payload]);
      return { kind: value.tag === 1 ? "dynamic" : "immediate", tailSites: [] };
    }

    const rootIndex = this.literals.length;
    const peak = literalPeakSlots(actions);
    if (rootIndex + peak + 4 > 1024) {
      fail(at, "Quoted literal construction exceeds the 1024-slot root arena");
    }
    this.literals.push({ actions, rootIndex });
    this.emitLiteralRoot(rootIndex);
    return { kind: "dynamic", tailSites: [] };
  }

  private readQuotedDatum(
    actions: LiteralAction[],
    at: Position,
  ): void {
    const event = this.cursor.take();
    if (event === null) fail(at, "Quote requires a datum");
    switch (event.kind) {
      case "value":
        actions.push({
          kind: "value",
          tag: event.value[0],
          payload: event.value[1],
        });
        return;
      case "symbol":
        actions.push({
          kind: "value",
          tag: 1,
          payload: 0x2000 | event.id,
        });
        return;
      case "string":
        actions.push({
          kind: "value",
          tag: 1,
          payload: 0x8000 | event.id,
        });
        return;
      case "quote": {
        let quoteId: number;
        try {
          quoteId = this.reader.symbols.intern(
            Uint8Array.of(113, 117, 111, 116, 101),
          );
        } catch (error) {
          fail(
            event.at,
            error instanceof Error ? error.message : String(error),
          );
        }
        actions.push({
          kind: "value",
          tag: 1,
          payload: 0x2000 | quoteId,
        });
        this.readQuotedDatum(actions, event.at);
        actions.push({ kind: "value", tag: 0, payload: 0xfe02 });
        actions.push({ kind: "pair" }, { kind: "pair" });
        return;
      }
      case "open": {
        let itemCount = 0;
        for (;;) {
          const next = this.cursor.peek();
          if (next === null) {
            fail(event.at, "Expected closing ) in quoted list");
          }
          if (next.kind === "close") {
            this.cursor.take();
            actions.push({ kind: "value", tag: 0, payload: 0xfe02 });
            for (let index = 0; index < itemCount; index++) {
              actions.push({ kind: "pair" });
            }
            return;
          }
          if (next.kind === "dot") {
            this.cursor.take();
            if (itemCount === 0) {
              fail(next.at, "A dotted list needs a preceding element");
            }
            this.readQuotedDatum(actions, next.at);
            this.expectClose(event.at, "dotted list");
            for (let index = 0; index < itemCount; index++) {
              actions.push({ kind: "pair" });
            }
            return;
          }
          this.readQuotedDatum(actions, event.at);
          itemCount++;
        }
      }
      case "dot":
        return fail(event.at, "A dot is only valid inside quoted list data");
      case "close":
        return fail(event.at, "Unexpected closing parenthesis in quoted data");
    }
  }

  private emitLiteralRoot(rootIndex: number): void {
    this.references.emitAddressLoad(this.currentLines, "ROOTBASE");
    this.currentLines.push(
      "        LD DE," + (rootIndex * 4),
      "        ADD HL,DE",
      "        LD A,(HL)",
      "        INC HL",
      "        LD E,(HL)",
      "        INC HL",
      "        LD D,(HL)",
      "        EX DE,HL",
    );
  }

  private readArithmetic(
    operator: ArithmeticOperator,
    at: Position,
  ): ExpressionResult {
    const first = this.cursor.peek();
    if (first === null) fail(at, "Expected closing ) after " + operator);
    if (first.kind === "close") {
      this.cursor.take();
      if (operator === "-" || operator === "/") {
        fail(at, operator + " has too few operands in M7");
      }
      this.emitValue(operator === "+" ? [3, 0] : [3, 1]);
      return { kind: "integer", tailSites: [] };
    }

    const firstAt = first.at;
    const firstResult = this.readRequiredExpression(at, "arithmetic operand");
    this.requireNumber(firstResult.kind, firstAt);
    const next = this.cursor.peek();
    if (next === null) fail(at, "Expected closing ) after " + operator);
    if (next.kind === "close") {
      this.cursor.take();
      if (operator === "-") {
        this.services.emitCall(this.currentLines, "numeric.negate", {
          checkCarry: true,
        });
      } else if (
        (operator === "+" || operator === "*") &&
        firstResult.kind === "dynamic"
      ) {
        this.services.emitCall(this.currentLines, "numeric.classify", {
          checkCarry: true,
        });
      } else if (operator === "/") {
        fail(at, "/ has too few operands in M7");
      }
      return { kind: firstResult.kind, tailSites: [] };
    }

    let sawDynamic = firstResult.kind === "dynamic";
    let sawBinary16 = firstResult.kind === "binary16";
    const service = runtimeServiceByOperator[operator];
    for (;;) {
      const operand = this.cursor.peek();
      if (operand === null) fail(at, "Expected closing ) after " + operator);
      if (operand.kind === "close") break;

      let rightKind: ResultKind;
      let tempSlot: number | null = null;
      if (operand.kind === "value") {
        this.cursor.take();
        if (!isNumber(operand.value)) {
          fail(operand.at, "Arithmetic operands must be numeric");
        }
        rightKind = valueResultKind(operand.value);
        this.currentLines.push(
          "        LD B," + operand.value[0],
          "        LD DE," + numberLiteral(operand.value),
        );
      } else {
        tempSlot = this.spillLeft(operand.at);
        rightKind = this.readRequiredExpression(at, "arithmetic operand").kind;
        this.requireNumber(rightKind, operand.at);
        this.loadSpilledLeft();
      }
      this.services.emitCall(this.currentLines, service.key, {
        checkCarry: true,
      });
      if (tempSlot !== null) {
        this.tempDepth--;
        this.emitRootCleanupFromStack();
      }
      sawDynamic ||= rightKind === "dynamic";
      sawBinary16 ||= rightKind === "binary16";
    }

    this.expectClose(at, operator);
    if (operator === "/") {
      return { kind: "binary16", tailSites: [] };
    }
    if (sawDynamic) return { kind: "dynamic", tailSites: [] };
    return {
      kind: sawBinary16 ? "binary16" : "integer",
      tailSites: [],
    };
  }

  private readRequiredExpression(
    at: Position,
    description: string,
    tailAllowed = false,
  ): ExpressionResult {
    const next = this.cursor.peek();
    if (next === null || next.kind === "close") {
      fail(next?.at ?? at, "Expected " + description);
    }
    return this.readExpression(tailAllowed);
  }

  private expectClose(at: Position, form: string): void {
    const next = this.cursor.take();
    if (next?.kind !== "close") {
      fail(next?.at ?? at, "Expected closing ) after " + form);
    }
  }

  private requireNumber(kind: ResultKind, at: Position): void {
    if (kind === "immediate") {
      fail(at, "Arithmetic operands must be numeric");
    }
  }

  private findLexicalBinding(
    name: string,
  ): { readonly depth: number; readonly slot: number } | null {
    for (let depth = 0; depth < this.scopeStack.length; depth++) {
      const scope = this.scopeStack[this.scopeStack.length - depth - 1]!;
      const slot = scope.bindings.get(name);
      if (slot !== undefined) return { depth, slot };
    }
    return null;
  }

  private markCapture(bindingDepth: number): void {
    if (bindingDepth === 0) return;
    const owner = this.scopeStack.length - bindingDepth - 1;
    for (let index = owner + 1; index < this.scopeStack.length; index++) {
      this.scopeStack[index]!.captureNeeded = true;
    }
  }

  private emitValue(value: Value): void {
    this.currentLines.push(
      "        LD A," + value[0],
      "        LD HL," + numberLiteral(value),
    );
  }

  private spillLeft(at: Position): number {
    const slot = this.tempDepth;
    if (slot >= DEFAULT_READER_LIMITS.nesting) {
      fail(at, "Nested arithmetic exceeds temporary-root capacity");
    }
    this.tempDepth++;
    this.currentLines.push(
      "        PUSH AF",
      "        PUSH HL",
      "        LD BC,0",
    );
    this.services.emitCall(
      this.currentLines,
      "execution.packet_new",
      { checkCarry: true },
    );
    this.currentLines.push(
      "        POP HL",
      "        POP AF",
      "        PUSH DE",
      "        LD B,H",
      "        LD C,L",
      "        LD HL,0",
      "        ADD HL,DE",
      "        LD (HL),A",
      "        INC HL",
      "        LD (HL),C",
      "        INC HL",
      "        LD (HL),B",
      "        INC HL",
      "        LD (HL),0",
    );
    return slot;
  }

  private loadSpilledLeft(): void {
    this.currentLines.push(
      "        PUSH AF",
      "        PUSH HL",
      "        POP BC",
      "        POP AF",
      "        POP DE",
      "        PUSH DE",
      "        PUSH AF",
      "        PUSH BC",
      "        LD HL,0",
      "        ADD HL,DE",
      "        LD A,(HL)",
      "        INC HL",
      "        LD E,(HL)",
      "        INC HL",
      "        LD D,(HL)",
      "        EX DE,HL",
      "        POP DE",
      "        POP BC",
    );
  }

  private storePacketValueFromStack(offset: number): void {
    this.currentLines.push(
      "        PUSH AF",
      "        PUSH HL",
      "        POP BC",
      "        POP AF",
      "        POP DE",
      "        PUSH DE",
      "        LD HL," + offset,
      "        ADD HL,DE",
      "        LD (HL),A",
      "        INC HL",
      "        LD (HL),C",
      "        INC HL",
      "        LD (HL),B",
      "        INC HL",
      "        LD (HL),0",
    );
  }

  private emitRootCleanupFromDE(): void {
    this.currentLines.push(
      "        PUSH DE",
      "        PUSH DE",
      "        POP IY",
    );
    this.currentLines.push("        PUSH AF", "        PUSH HL");
    this.services.emitCall(this.currentLines, "execution.roots_refresh");
    this.currentLines.push(
      "        POP HL",
      "        POP AF",
      "        POP DE",
    );
  }

  private emitRootCleanupFromStack(): void {
    this.currentLines.push(
      "        POP DE",
      "        PUSH DE",
      "        PUSH DE",
      "        POP IY",
      "        PUSH AF",
      "        PUSH HL",
    );
    this.services.emitCall(this.currentLines, "execution.roots_refresh");
    this.currentLines.push(
      "        POP HL",
      "        POP AF",
      "        POP DE",
    );
  }

  private nextIfId(at: Position): string {
    if (this.ifIndex >= 36 ** 4) fail(at, "Too many control-flow labels");
    const id = this.ifIndex.toString(36).toUpperCase().padStart(4, "0");
    this.ifIndex++;
    return id;
  }

  private nextProcedureLabels(at: Position): {
    entry: string;
    entryAlias: string;
    body: string;
    descriptor: string;
  } {
    if (this.procedureIndex >= 36 ** 2) {
      fail(
        at,
        "Too many lambda procedures for the eight-character label space",
      );
    }
    const id = this.procedureIndex.toString(36).toUpperCase().padStart(2, "0");
    this.procedureIndex++;
    return {
      entry: "LAMBDA" + id,
      entryAlias: "LENT" + id,
      body: "LBODY" + id,
      descriptor: "LDESC" + id,
    };
  }

  private patchTailCall(site: ServiceSite): void {
    if (site.key !== "execution.invoke" || site.opcode !== "CALL") {
      throw new Error("Invalid M7 tail-call candidate");
    }
    site.lines[site.opcodeLine] = "        JP $0000";
    site.key = "execution.tail";
    site.opcode = "JP";
  }
}

function numberLiteral(value: Value): string {
  return wordLiteral(value[1]);
}

function wordLiteral(value: number): string {
  return "$" + value.toString(16).toUpperCase().padStart(4, "0");
}

function literalPeakSlots(actions: readonly LiteralAction[]): number {
  let depth = 0;
  let peak = 0;
  for (const action of actions) {
    if (action.kind === "value") {
      depth++;
      peak = Math.max(peak, depth);
    } else {
      if (depth < 2) throw new Error("Malformed postfix literal recipe");
      depth--;
    }
  }
  if (depth !== 1) throw new Error("Literal recipe did not leave one value");
  return peak;
}

interface LiteralRecipeData {
  readonly descriptors: Uint8Array;
  readonly recipes: Uint8Array;
}

/** Encode the host literal plans as the compact N8b target recipe stream. */
function literalRecipeData(plan: CompilePlan): LiteralRecipeData {
  const descriptors: number[] = [];
  const recipes: number[] = [];
  const word = (value: number): void => {
    if (!Number.isInteger(value) || value < 0 || value > 0xffff) {
      throw new RangeError("Literal recipe extent exceeds a 16-bit address");
    }
    descriptors.push(value & 0xff, value >>> 8);
  };
  for (const literal of plan.literals) {
    const start = recipes.length;
    for (const action of literal.actions) {
      if (action.kind === "pair") {
        recipes.push(0);
        continue;
      }
      if (
        !Number.isInteger(action.tag) || action.tag < 0 || action.tag > 0x7f ||
        !Number.isInteger(action.payload) || action.payload < 0 ||
        action.payload > 0xffff
      ) {
        throw new RangeError("Literal recipe contains an invalid value");
      }
      recipes.push(
        0x80 | action.tag,
        action.payload & 0xff,
        action.payload >>> 8,
      );
    }
    const length = recipes.length - start;
    word(start);
    word(length);
    // The planner already checks the peak root depth.  It is not part of the
    // target descriptor: the interpreter consumes one recipe at a time and
    // the runtime root checks remain the authority for the live arena.
    literalPeakSlots(literal.actions);
  }
  if (recipes.length > 0xffff) {
    throw new RangeError("Literal recipe table exceeds 65,535 bytes");
  }
  return {
    descriptors: Uint8Array.from(descriptors),
    recipes: Uint8Array.from(recipes),
  };
}

function byteTable(label: string, bytes: Uint8Array): string[] {
  const lines = [label + ":"];
  for (let offset = 0; offset < bytes.length; offset += 12) {
    const values = [...bytes.subarray(offset, offset + 12)].map((byte) =>
      "$" + byte.toString(16).toUpperCase().padStart(2, "0")
    );
    lines.push("        DB " + values.join(","));
  }
  return lines;
}

function literalCellCount(actions: readonly LiteralAction[]): number {
  type LiteralType = "nil" | "pair" | "other";
  const stack: LiteralType[] = [];
  let cells = 0;
  for (const action of actions) {
    if (action.kind === "value") {
      stack.push(
        action.tag === 0 && action.payload === 0xfe02
          ? "nil"
          : action.tag === 1 && (action.payload & 0xe000) === 0
          ? "pair"
          : "other",
      );
      continue;
    }
    if (stack.length < 2) throw new Error("Malformed postfix literal recipe");
    const cdr = stack.pop()!;
    stack.pop();
    cells += cdr === "nil" || cdr === "pair" ? 1 : 2;
    stack.push("pair");
  }
  if (stack.length !== 1) {
    throw new Error("Literal recipe did not leave one value");
  }
  return cells;
}

function countListChildren(
  sourceBytes: Uint8Array,
  at: Position,
  sourceName: SourceName,
): number {
  const suffix = sourceBytes.subarray(at.offset + 1);
  const countedSource = new Uint8Array(suffix.length + 1);
  countedSource[0] = 40;
  countedSource.set(suffix, 1);
  const reader = new SourceReader(
    countedSource,
    shiftedSourceName(sourceName, at.offset),
  );
  const events = reader.events();
  const opening = events.next();
  if (opening.done || opening.value.kind !== "open") {
    fail(at, "Expected an application list");
  }
  let nesting = 0;
  let count = 0;
  let quotedDatum = false;
  for (let next = events.next(); !next.done; next = events.next()) {
    const event = next.value;
    if (nesting === 0 && event.kind === "close") return count;
    if (nesting === 0) {
      if (event.kind === "quote") {
        if (!quotedDatum) count++;
        quotedDatum = true;
      } else if (event.kind === "open") {
        if (!quotedDatum) count++;
        nesting = 1;
      } else {
        if (!quotedDatum) count++;
        quotedDatum = false;
      }
    } else if (event.kind === "open") {
      nesting++;
    } else if (event.kind === "close") {
      nesting--;
      if (nesting === 0) quotedDatum = false;
    }
  }
  fail(at, "Expected closing ) after application");
}

function countRemainingForms(
  sourceBytes: Uint8Array,
  first: Position,
  sourceName: SourceName,
): number {
  const suffix = sourceBytes.subarray(first.offset);
  const countedSource = new Uint8Array(suffix.length + 1);
  countedSource[0] = 40;
  countedSource.set(suffix, 1);
  const reader = new SourceReader(
    countedSource,
    shiftedSourceName(sourceName, first.offset),
  );
  const events = reader.events();
  const opening = events.next();
  if (opening.done || opening.value.kind !== "open") {
    fail(first, "Expected an expression sequence");
  }
  let nesting = 0;
  let count = 0;
  let quotedDatum = false;
  for (let next = events.next(); !next.done; next = events.next()) {
    const event = next.value;
    if (nesting === 0 && event.kind === "close") return count;
    if (nesting === 0) {
      if (event.kind === "quote") {
        if (!quotedDatum) count++;
        quotedDatum = true;
      } else if (event.kind === "open") {
        if (!quotedDatum) count++;
        nesting = 1;
      } else {
        if (!quotedDatum) count++;
        quotedDatum = false;
      }
    } else if (event.kind === "open") {
      nesting++;
    } else if (event.kind === "close") {
      nesting--;
      if (nesting === 0) quotedDatum = false;
    }
  }
  fail(first, "Expected closing ) after expression sequence");
}

function assemblyText(
  plan: CompilePlan,
  services: ServiceEmitter,
  references: LocalReferenceEmitter,
  runtimeWorkspace: number,
  profile: SkateTpaProfile,
  programBase: number,
  heapCells: number,
): string {
  const bss = callerBssLayout(heapCells, runtimeWorkspace);
  const bitmapBytes = bss.bitmap.bytes;
  const symbolCount = plan.readerTables.symbols.descriptors.length / 3;
  const nameBytes = plan.readerTables.symbols.pool.length;
  const stringCount = plan.readerTables.strings.descriptors.length / 4;
  const stringBytes = plan.readerTables.strings.pool.length;
  const globalCount = plan.globals.length;
  const literalRecipes = literalRecipeData(plan);
  const literalInit: string[] = [];
  if (plan.literals.length > 0) {
    literalInit.push(
      "        PUSH IX",
      "        LD IX,LITDESC",
      "        LD HL," + plan.literals.length,
      "        LD (LITCOUNT),HL",
    );
    literalInit.push(
      "LITLOOP:",
      "        LD HL,(LITCOUNT)",
      "        LD A,H",
      "        OR L",
      "        JP Z,LITDONE",
      "        LD E,(IX)",
      "        INC IX",
      "        LD D,(IX)",
      "        INC IX",
      "        LD HL,LITREC",
      "        ADD HL,DE",
      "        LD (LITRPTR),HL",
      "        LD E,(IX)",
      "        INC IX",
      "        LD D,(IX)",
      "        INC IX",
      "        LD (LITLEFT),DE",
      "LITACT:",
      "        LD DE,(LITLEFT)",
      "        LD A,D",
      "        OR E",
      "        JP Z,LITNEXT",
      "        LD HL,(LITRPTR)",
      "        LD A,(HL)",
      "        INC HL",
      "        LD (LITRPTR),HL",
      "        DEC DE",
      "        LD (LITLEFT),DE",
      "        BIT 7,A",
      "        JP Z,LITPAIRX",
      "        LD B,A",
      "        LD HL,(LITRPTR)",
      "        LD E,(HL)",
      "        INC HL",
      "        LD D,(HL)",
      "        INC HL",
      "        LD (LITRPTR),HL",
      "        EX DE,HL",
      "        LD A,B",
      "        AND 127",
    );
    references.emitLocalCall(literalInit, "LITPUSH");
    literalInit.push(
      "        LD DE,(LITLEFT)",
      "        DEC DE",
      "        DEC DE",
      "        LD (LITLEFT),DE",
      "        JP LITACT",
      "LITPAIRX:",
      "        OR A",
      "        JP NZ,LITBAD",
    );
    references.emitLocalCall(literalInit, "LITPAIR");
    literalInit.push(
      "        JP LITACT",
      "LITNEXT:",
      "        LD HL,(LITCOUNT)",
      "        DEC HL",
      "        LD (LITCOUNT),HL",
      "        JP LITLOOP",
      "LITDONE:",
      "        POP IX",
      "        RET",
      "LITBAD:",
      "        LD A,3",
    );
    literalInit.push("        POP IX");
    services.emitCall(literalInit, "runtime.error");
    literalInit.push("        RET", "");
  }

  const literalHelpers: string[] = [];
  if (plan.literals.length > 0) {
    literalHelpers.push(
      "LITPUSH:",
      "        PUSH AF",
      "        PUSH HL",
      "        PUSH IY",
      "        POP DE",
      "        POP HL",
      "        EX DE,HL",
      "        POP AF",
      "        LD (HL),A",
      "        INC HL",
      "        LD (HL),E",
      "        INC HL",
      "        LD (HL),D",
      "        INC HL",
      "        LD (HL),0",
      "        INC HL",
      "        PUSH HL",
      "        POP IY",
      "        RET",
      "",
      "LITPAIR:",
      "        PUSH IY",
      "        POP HL",
      "        LD DE,8",
      "        OR A",
      "        SBC HL,DE",
      "        LD (LITDST),HL",
      "        LD BC,2",
    );
    services.emitCall(
      literalHelpers,
      "execution.packet_new",
      { checkCarry: true },
    );
    literalHelpers.push(
      "        LD (LITPACK),DE",
      "        LD HL,(LITDST)",
      "        PUSH HL",
      "        LD HL,(LITPACK)",
      "        LD BC,8",
      "        ADD HL,BC",
      "        EX DE,HL",
      "        POP HL",
      "        LD BC,8",
      "        LDIR",
      "        LD DE,(LITPACK)",
      "        LD BC,2",
    );
    services.emitCall(literalHelpers, "pairs.cons");
    literalHelpers.push(
      "        PUSH AF",
      "        PUSH HL",
      "        LD HL,(LITDST)",
      "        POP DE",
      "        POP AF",
      "        LD (HL),A",
      "        INC HL",
      "        LD (HL),E",
      "        INC HL",
      "        LD (HL),D",
      "        INC HL",
      "        LD (HL),0",
      "        LD HL,(LITDST)",
      "        LD DE,4",
      "        ADD HL,DE",
      "        PUSH HL",
      "        POP IY",
    );
    services.emitCall(literalHelpers, "execution.roots_refresh");
    literalHelpers.push("        RET", "");
  }

  const startup: string[] = [
    "ORG " + wordLiteral(programBase),
    "COMSTART:",
    "        LD HL,($0006) ; Read the destination of CP/M's JP at $0005.",
    "        LD L,0       ; Use the start of its page as the memory ceiling.",
    "        LD DE," + wordLiteral(profile.stackTop),
    "        OR A",
    "        SBC HL,DE",
    "        JP NC,MEMOK  ; Required stack top fits below resident BDOS.",
    "        LD DE,MEMMSG",
    "        LD C,9",
    "        CALL $0005   ; Report failure using the incoming CP/M stack.",
    "        JP $0000     ; Warm boot before touching runtime state.",
    "MEMOK:",
    "        LD SP," + wordLiteral(profile.stackTop),
  ];
  // The boot descriptor is the hand-off point between the initialized image
  // and its zero-initialized storage.  Read the storage geometry from there so
  // the startup path does not have a second, private copy of those addresses.
  const emitDescriptorAddress = (
    lines: string[],
    target: "BOOTDESC" | "STORDESC",
    fieldOffset: number,
  ): void => {
    references.emitAddressLoad(lines, target, fieldOffset);
    lines.push(
      "        LD E,(HL)",
      "        INC HL",
      "        LD D,(HL)",
      "        EX DE,HL",
    );
  };
  const emitDescriptorCount = (
    lines: string[],
    target: "BOOTDESC" | "STORDESC",
    fieldOffset: number,
  ): void => {
    references.emitAddressLoad(lines, target, fieldOffset);
    lines.push(
      "        LD C,(HL)",
      "        INC HL",
      "        LD B,(HL)",
    );
  };
  emitDescriptorAddress(startup, "STORDESC", 0);
  startup.push(
    "        PUSH HL",
  );
  emitDescriptorAddress(startup, "STORDESC", 2);
  startup.push(
    "        POP DE",
    "        OR A",
    "        SBC HL,DE",
    "        LD B,H",
    "        LD C,L",
  );
  emitDescriptorAddress(startup, "STORDESC", 0);
  startup.push(
    "        LD D,H",
    "        LD E,L",
    "        INC DE",
    "        LD (HL),0",
    "        DEC BC",
    "        LDIR",
  );
  emitDescriptorAddress(startup, "STORDESC", 16);
  startup.push("        PUSH HL");
  emitDescriptorCount(startup, "STORDESC", 18);
  startup.push("        POP HL");
  services.emitCall(startup, "heap.initialize", { checkCarry: true });
  emitDescriptorAddress(startup, "STORDESC", 12);
  startup.push("        PUSH HL");
  emitDescriptorCount(startup, "STORDESC", 14);
  startup.push("        POP HL");
  services.emitCall(startup, "collector.configure", { checkCarry: true });
  references.emitAddressLoad(startup, "RTCONFIG");
  services.emitCall(startup, "execution.initialize", { checkCarry: true });
  references.emitLocalCall(startup, "LITINIT");
  startup.push("        LD BC,0");
  services.emitCall(startup, "execution.packet_new", { checkCarry: true });
  startup.push("        LD (TOPPACK),DE");
  references.emitAddressLoad(startup, "TOPDESC");
  startup.push("        LD DE,0");
  services.emitCall(startup, "execution.make_closure");
  startup.push(
    "        PUSH AF",
    "        PUSH HL",
    "        LD HL,(TOPPACK)",
    "        LD DE,4",
    "        ADD HL,DE",
    "        POP DE",
    "        POP AF",
    "        LD (HL),A",
    "        INC HL",
    "        LD (HL),E",
    "        INC HL",
    "        LD (HL),D",
    "        INC HL",
    "        LD (HL),0",
    "        LD DE,(TOPPACK)",
    "        LD BC,0",
  );
  services.emitCall(startup, "execution.stack_check", { checkCarry: true });
  services.emitCall(startup, "execution.invoke");
  startup.push(
    "        LD (RESULT),HL",
    "        LD (RESULTAG),A",
  );
  if (plan.resultKind === "integer") {
    startup.push("        CALL PRTINT16");
  } else if (plan.resultKind === "dynamic") {
    startup.push(
      "        LD A,(RESULTAG)",
      "        CP 3",
      "        JP NZ,CPMEXIT",
      "        CALL PRTINT16",
    );
  }
  startup.push(
    "CPMEXIT:",
    "        LD C,0",
    "        CALL $0005",
    "        JP COMSTART",
  );

  const lines = [
    ...startup,
    "",
    "LITINIT:",
    ...literalInit,
    "        RET",
    "",
    ...literalHelpers,
    "",
    "TOPENTRY:",
  ];
  references.emitAddressLoad(lines, "TOPDESC");
  services.emitCall(lines, "execution.enter");
  lines.push("        JP TOPPROC", "TOPPROC:", ...plan.topBody, "");

  for (const procedure of plan.procedures) {
    lines.push(...procedure.lines, "");
  }

  lines.push(
    "TOPDESC:",
    "        DW 0,0,0,0",
  );
  references.addDataReference("TOPDESC", 0, "TOPADDR");
  for (const procedure of plan.procedures) {
    lines.push(
      procedure.descriptor + ":",
      "        DW 0",
      "        DW " + procedure.minArity,
      "        DW " + procedure.slotCount,
      "        DW " + (procedure.hasRest ? 1 : 0),
    );
  }
  for (const procedure of plan.procedures) {
    // The alias carries NOBJ's address-value kind for descriptor relocations.
    lines.push(procedure.entryAlias + " EQU " + procedure.entry);
  }
  lines.push("TOPADDR EQU TOPENTRY");
  lines.push("BOOTDESC:", "        DW 1");
  if (globalCount === 0) {
    lines.push("        DW 0,0");
  } else {
    lines.push("        DW 0," + globalCount);
    references.addDataReference("BOOTDESC", 2, "GLOBALS");
  }
  if (plan.literals.length === 0) {
    lines.push("        DW 0,0");
  } else {
    lines.push("        DW 0," + plan.literals.length);
    references.addDataReference("BOOTDESC", 6, "ROOTBASE");
  }
  lines.push(
    "        DW 0",
    "        DW 0",
    "        DW 1024",
    "        DW 640",
    "        DW " + profile.stackCapacity,
    "        DW " + runtimeWorkspace,
    "        DW " + heapCells,
  );
  if (symbolCount === 0) {
    lines.push("        DW 0,0");
  } else {
    lines.push("        DW 0," + symbolCount);
    references.addDataReference("BOOTDESC", 24, "SYMTAB");
  }
  if (nameBytes === 0) {
    lines.push("        DW 0,0");
  } else {
    lines.push("        DW 0," + nameBytes);
    references.addDataReference("BOOTDESC", 28, "NAMEPOOL");
  }
  if (stringCount === 0) {
    lines.push("        DW 0,0");
  } else {
    lines.push("        DW 0," + stringCount);
    references.addDataReference("BOOTDESC", 32, "STRDESC");
  }
  if (stringBytes === 0) {
    lines.push("        DW 0,0");
  } else {
    lines.push("        DW 0," + stringBytes);
    references.addDataReference("BOOTDESC", 36, "STRPOOL");
  }
  references.addDataReference("BOOTDESC", 10, "LITADDR");
  references.addDataReference("BOOTDESC", 12, "TOPDESC");
  lines.push("LITADDR EQU LITINIT");
  if (plan.literals.length > 0) {
    lines.push(
      "LITRPTR:",
      "        DW 0",
      "LITLEFT:",
      "        DW 0",
      "LITCOUNT:",
      "        DW 0",
      "LITPACK:",
      "        DW 0",
      "LITDST:",
      "        DW 0",
      ...byteTable("LITDESC", literalRecipes.descriptors),
      ...byteTable("LITREC", literalRecipes.recipes),
    );
  }
  if (symbolCount > 0) {
    lines.push(...byteTable("SYMTAB", plan.readerTables.symbols.descriptors));
  }
  if (nameBytes > 0) {
    lines.push(...byteTable("NAMEPOOL", plan.readerTables.symbols.pool));
  }
  if (stringCount > 0) {
    lines.push(...byteTable("STRDESC", plan.readerTables.strings.descriptors));
  }
  if (stringBytes > 0) {
    lines.push(...byteTable("STRPOOL", plan.readerTables.strings.pool));
  }
  if (globalCount > 0) {
    lines.push("GLOBALS:");
    for (const global of plan.globals) {
      lines.push(
        "        DW " + global.symbolIndex,
        "        DB " + global.tag,
        "        DW " + wordLiteral(global.payload),
        "        DB 0",
      );
    }
  }
  // The stable ABI-2 descriptor remains forty bytes because it is validated
  // by the shared NOBJ linker.  Its adjacent storage descriptor carries the
  // profile-selected zero-initialized geometry used during startup.
  lines.push(
    "STORDESC:",
    "        DW 0,0,0,0,0,0,0",
    "        DW " + bitmapBytes,
    "        DW 0",
    "        DW " + heapCells,
  );
  references.addDataReference("STORDESC", 0, "BSSBASE");
  references.addDataReference("STORDESC", 2, "BSSEND", 3);
  references.addDataReference("STORDESC", 4, "ROOTBASE");
  references.addDataReference("STORDESC", 6, "ROOTEND", 3);
  references.addDataReference("STORDESC", 8, "ACTBASE");
  references.addDataReference("STORDESC", 10, "ACTEND", 3);
  references.addDataReference("STORDESC", 12, "BMAPBASE");
  references.addDataReference("STORDESC", 16, "HEAPBASE");
  lines.push(
    "RTCONFIG:",
    "        DW 0,0,0,0,0,0,0," + wordLiteral(profile.stackLow) + ",0," +
      globalCount + ",0," + stringCount + ",0," + stringBytes,
    "RESULT:",
    "        DW 0",
    "RESULTAG:",
    "        DB 0",
    "TOPPACK:",
    "        DW 0",
  );
  lines.push(...integerPrinter());
  lines.push(...integerPrinterData());
  lines.push(
    ...byteTable(
      "MEMMSG",
      new TextEncoder().encode("INSUFFICIENT MEMORY\r\n$"),
    ),
  );

  lines.push(
    "        ALIGN 4",
    "CODEEND:",
    "BSSBASE EQU 0",
    "ROOTBASE EQU " + bss.roots.offset,
    "ROOTEND EQU " + (bss.roots.offset + bss.roots.bytes),
    "ACTBASE EQU " + bss.activations.offset,
    "ACTEND EQU " + (bss.activations.offset + bss.activations.bytes),
    "BMAPBASE EQU " + bss.bitmap.offset,
    "BMAPEND EQU " + (bss.bitmap.offset + bss.bitmap.bytes),
    "HEAPBASE EQU " + bss.heap.offset,
    "HEAPEND EQU " + (bss.heap.offset + bss.heap.bytes),
    "BSSEND EQU " + bss.bytes,
  );

  references.addDataReference("RTCONFIG", 0, "ROOTBASE");
  references.addDataReference("RTCONFIG", 2, "ROOTEND", 3);
  references.addDataReference("RTCONFIG", 4, "ACTBASE");
  references.addDataReference("RTCONFIG", 6, "ACTEND", 3);
  references.addDataReference("RTCONFIG", 8, "HEAPBASE");
  references.addDataReference("RTCONFIG", 10, "CODEBASE");
  references.addDataReference("RTCONFIG", 12, "CODEEND", 3);
  if (globalCount > 0) {
    references.addDataReference("RTCONFIG", 16, "GLOBALS");
  }
  if (stringCount > 0) {
    references.addDataReference("RTCONFIG", 20, "STRDESC");
  }
  if (stringBytes > 0) {
    references.addDataReference("RTCONFIG", 24, "STRPOOL");
  }

  // Every descriptor's first word is its entry point, patched by the shared linker.
  return [
    ...lines,
    "CODEBASE EQU COMSTART",
  ].join("\n") + "\n";
}

function integerPrinter(): string[] {
  return [
    "",
    "PRTINT16:",
    "        LD A,0",
    "        LD (PRINTFLG),A",
    "        BIT 7,H",
    "        JP Z,PRINTPOS",
    "        LD A,45",
    "        CALL PUTCHAR",
    "        LD A,0",
    "        SUB L",
    "        LD L,A",
    "        LD A,0",
    "        SBC A,H",
    "        LD H,A",
    "PRINTPOS:",
    "        LD DE,10000",
    "        CALL PLACEVAL",
    "        LD DE,1000",
    "        CALL PLACEVAL",
    "        LD DE,100",
    "        CALL PLACEVAL",
    "        LD DE,10",
    "        CALL PLACEVAL",
    "        LD DE,1",
    "        CALL PLACEVAL",
    "        LD A,13",
    "        CALL PUTCHAR",
    "        LD A,10",
    "        CALL PUTCHAR",
    "        RET",
    "PLACEVAL:",
    "        LD B,0",
    "PLACELOP:",
    "        OR A",
    "        SBC HL,DE",
    "        JP C,PLACEOK",
    "        INC B",
    "        JP PLACELOP",
    "PLACEOK:",
    "        ADD HL,DE",
    "        LD A,B",
    "        OR A",
    "        JP NZ,EMITDIG",
    "        LD A,(PRINTFLG)",
    "        OR A",
    "        JP NZ,EMITDIG",
    "        LD A,D",
    "        OR A",
    "        RET NZ",
    "        LD A,E",
    "        CP 1",
    "        RET NZ",
    "EMITDIG:",
    "        LD A,1",
    "        LD (PRINTFLG),A",
    "        LD A,B",
    "        ADD A,48",
    "        CALL PUTCHAR",
    "        RET",
    "PUTCHAR:",
    "        PUSH AF",
    "        PUSH BC",
    "        PUSH DE",
    "        PUSH HL",
    "        LD E,A",
    "        LD C,2",
    "        CALL $0005",
    "        POP HL",
    "        POP DE",
    "        POP BC",
    "        POP AF",
    "        RET",
  ];
}

function integerPrinterData(): string[] {
  return ["PRINTFLG:", "        DB 0"];
}

async function assemble(entry: string, base: number): Promise<AtomImage> {
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
  if (image == null) throw new Error(`ATOM produced no image for ${entry}`);
  const trim = base - image.base;
  if (trim < 0 || trim > image.bytes.length) {
    throw new Error(
      `ATOM image for ${entry} does not reach $${base.toString(16)}`,
    );
  }
  const symbols = new Map<string, number>(
    result.generation.symbols.map((item: { name: string; value: number }) => [
      item.name.toLowerCase(),
      item.value,
    ]),
  );
  return {
    base,
    end: image.end,
    bytes: image.bytes.slice(trim),
    symbols,
  };
}

function address(image: AtomImage, name: string): number {
  const value = image.symbols.get(name.toLowerCase());
  if (value === undefined) throw new Error(`ATOM omitted ${name}`);
  return value;
}

function offset(image: AtomImage, name: string): number {
  return address(image, name) - image.base;
}

const runtimeWorkspaceSpecs = [
  ["HWORK", "HWEND"],
  ["GCWORK", "GCWEND"],
  ["F16WORK", "F16WEND"],
  ["NWORK", "NWEND"],
  ["RTWORK", "RTWEND"],
  ["RTPRFLAG", "RTPRWEND"],
] as const;

interface RuntimeWorkspaceRange {
  readonly start: string;
  readonly end: string;
  readonly startAddress: number;
  readonly endAddress: number;
  readonly offset: number;
  readonly bytes: number;
}

function runtimeWorkspaceLayout(
  image: AtomImage,
): readonly RuntimeWorkspaceRange[] {
  let offset = 0;
  return runtimeWorkspaceSpecs.map(([start, end]) => {
    const startAddress = address(image, start);
    const endAddress = address(image, end);
    const bytes = endAddress - startAddress;
    if (bytes < 0) throw new Error(`${end} precedes ${start}`);
    const range = { start, end, startAddress, endAddress, offset, bytes };
    offset += bytes;
    return range;
  });
}

function runtimeWorkspaceBytes(image: AtomImage): number {
  return runtimeWorkspaceLayout(image).reduce(
    (total, range) => total + range.bytes,
    0,
  );
}

/**
 * Rebuild the packed runtime with its mutable workspace represented by
 * absolute aliases.  The code keeps using its original short labels, while
 * the emitted image contains no workspace bytes or implicit fixed addresses.
 */
async function runtimeSourceWithoutWorkspace(
  image: AtomImage,
  workspaceBase: number,
  outputRoot: string,
): Promise<string> {
  const ranges = runtimeWorkspaceLayout(image);
  const byStart = new Map(ranges.map((range) => [range.start, range]));
  const byEnd = new Map(ranges.map((range) => [range.end, range]));
  const sourceFiles = [
    "allocator.asm",
    "collector.asm",
    "binary16.asm",
    "numeric.asm",
    "execution.asm",
  ];
  const sourceRoot = `${outputRoot}/runtime-src`;
  await Deno.mkdir(sourceRoot, { recursive: true });
  const transform = async (file: string): Promise<void> => {
    const filePath = `${projectRoot}runtime/${file}`;
    const text = await Deno.readTextFile(filePath);
    const lines: string[] = [];
    let active: RuntimeWorkspaceRange | undefined;
    for (const line of text.split(/\r?\n/)) {
      const match = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:/.exec(line);
      const label = match?.[1];
      if (label !== undefined) {
        const range = byStart.get(label.toUpperCase());
        if (range !== undefined) active = range;
      }
      if (active !== undefined) {
        if (label !== undefined) {
          const original = image.symbols.get(label.toLowerCase());
          if (original !== undefined) {
            const relative = original - active.startAddress;
            if (relative >= 0 && relative <= active.bytes) {
              lines.push(
                `${label} EQU ${
                  wordLiteral(workspaceBase + active.offset + relative)
                }`,
              );
            }
          }
        }
        if (label !== undefined && byEnd.get(label.toUpperCase()) === active) {
          active = undefined;
        }
        continue;
      }
      lines.push(line);
    }
    if (active !== undefined) {
      throw new Error(`runtime workspace ${active.start} has no end label`);
    }
    await Deno.writeTextFile(`${sourceRoot}/${file}`, lines.join("\n") + "\n");
  };
  for (const file of sourceFiles) {
    await transform(file);
  }
  for (
    const file of [
      "execution-frame.asm",
      "execution-pairs.asm",
      "execution-primitives.asm",
      "execution-calls.asm",
      "execution-literals.asm",
    ]
  ) {
    await transform(file);
  }
  const body = await Deno.readTextFile(
    `${projectRoot}tests/m7-runtime-body.asm`,
  );
  const marker = "; M7's target adapter makes execution failures terminal";
  const markerOffset = body.indexOf(marker);
  if (markerOffset < 0) throw new Error("M7 runtime error adapter is missing");
  const includeLines = sourceFiles.map((file) => `%INCLUDE "${file}"`);
  const bodySource = [
    ...includeLines,
    body.slice(markerOffset).trimEnd(),
    "",
  ].join("\n");
  await Deno.writeTextFile(
    `${sourceRoot}/origin.asm`,
    "ORG " + wordLiteral(0x0103) + "\n",
  );
  await Deno.writeTextFile(`${sourceRoot}/body.asm`, bodySource);
  return [
    `%INCLUDE "runtime-src/origin.asm"`,
    `%INCLUDE "runtime-src/body.asm"`,
    "",
  ].join("\n");
}

interface LocalSymbolSpec {
  readonly label: string;
  readonly valueKind: 1 | 2 | 3;
  readonly sectionId?: number;
  readonly offset?: number;
}

function callerObject(
  image: AtomImage,
  services: readonly ServiceSite[],
  references: LocalReferenceEmitter,
  plan: CompilePlan,
  heapCells: number,
  runtimeWorkspace: number,
  region: ReturnType<typeof imageRegion>,
): Uint8Array {
  const sectionId = 1;
  const bssSectionId = 3;
  const bss = callerBssLayout(heapCells, runtimeWorkspace);
  const runtimeContractId = 1;
  const localSpecs: LocalSymbolSpec[] = [
    { label: "COMSTART", valueKind: 1 },
    { label: "TOPENTRY", valueKind: 1 },
    { label: "TOPADDR", valueKind: 2 },
    { label: "LITINIT", valueKind: 1 },
    { label: "LITADDR", valueKind: 2 },
    { label: "TOPDESC", valueKind: 2 },
    { label: "BOOTDESC", valueKind: 2 },
    { label: "STORDESC", valueKind: 2 },
    { label: "RESULT", valueKind: 2 },
    { label: "RESULTAG", valueKind: 2 },
    { label: "RTCONFIG", valueKind: 2 },
    {
      label: "BSSBASE",
      valueKind: 2,
      sectionId: bssSectionId,
      offset: 0,
    },
    {
      label: "ROOTBASE",
      valueKind: 2,
      sectionId: bssSectionId,
      offset: bss.roots.offset,
    },
    {
      label: "ROOTEND",
      valueKind: 3,
      sectionId: bssSectionId,
      offset: bss.roots.offset + bss.roots.bytes,
    },
    {
      label: "ACTBASE",
      valueKind: 2,
      sectionId: bssSectionId,
      offset: bss.activations.offset,
    },
    {
      label: "ACTEND",
      valueKind: 3,
      sectionId: bssSectionId,
      offset: bss.activations.offset + bss.activations.bytes,
    },
    {
      label: "BMAPBASE",
      valueKind: 2,
      sectionId: bssSectionId,
      offset: bss.bitmap.offset,
    },
    {
      label: "BMAPEND",
      valueKind: 3,
      sectionId: bssSectionId,
      offset: bss.bitmap.offset + bss.bitmap.bytes,
    },
    {
      label: "HEAPBASE",
      valueKind: 2,
      sectionId: bssSectionId,
      offset: bss.heap.offset,
    },
    {
      label: "HEAPEND",
      valueKind: 3,
      sectionId: bssSectionId,
      offset: bss.heap.offset + bss.heap.bytes,
    },
    {
      label: "BSSEND",
      valueKind: 3,
      sectionId: bssSectionId,
      offset: bss.bytes,
    },
    { label: "CODEBASE", valueKind: 2 },
    { label: "CODEEND", valueKind: 3 },
  ];
  if (plan.literals.length > 0) {
    localSpecs.push(
      { label: "LITDESC", valueKind: 2 },
      { label: "LITREC", valueKind: 2 },
      { label: "LITPUSH", valueKind: 1 },
      { label: "LITPAIR", valueKind: 1 },
    );
  }
  if (plan.readerTables.symbols.descriptors.length > 0) {
    localSpecs.push({ label: "SYMTAB", valueKind: 2 });
  }
  if (plan.readerTables.symbols.pool.length > 0) {
    localSpecs.push({ label: "NAMEPOOL", valueKind: 2 });
  }
  if (plan.readerTables.strings.descriptors.length > 0) {
    localSpecs.push({ label: "STRDESC", valueKind: 2 });
  }
  if (plan.readerTables.strings.pool.length > 0) {
    localSpecs.push({ label: "STRPOOL", valueKind: 2 });
  }
  if (plan.globals.length > 0) {
    localSpecs.push({ label: "GLOBALS", valueKind: 2 });
  }
  for (const procedure of plan.procedures) {
    localSpecs.push(
      { label: procedure.entry, valueKind: 1 },
      { label: procedure.entryAlias, valueKind: 2 },
      { label: procedure.descriptor, valueKind: 2 },
    );
  }
  const localIds = new Map<string, number>();
  const symbols: Record<string, unknown>[] = [];
  localSpecs.forEach((spec, index) => {
    const id = index + 1;
    const labelKey = spec.label.toLowerCase();
    localIds.set(labelKey + ":" + spec.valueKind, id);
    const symbolSectionId = spec.sectionId ?? sectionId;
    const symbolOffset = spec.offset ?? offset(image, spec.label);
    symbols.push({
      id,
      binding: "local",
      valueKind: spec.valueKind,
      sectionId: symbolSectionId,
      offset: symbolOffset,
    });
  });

  const usedKeys: RuntimeKey[] = [];
  for (const site of services) {
    if (!usedKeys.includes(site.key)) usedKeys.push(site.key);
  }
  const importIds = new Map<RuntimeKey, number>();
  const importSymbols = usedKeys.map((key, index) => {
    const id = 0x4000 + index;
    importIds.set(key, id);
    return {
      id,
      binding: "service-import" as const,
      valueKind: 1 as const,
      contractId: runtimeContractId,
      serviceKey: key,
    };
  });
  const serviceRelocations = services.map((site) => {
    const targetSymbolId = importIds.get(site.key);
    const siteAddress = image.symbols.get(site.label.toLowerCase());
    if (targetSymbolId === undefined || siteAddress === undefined) {
      throw new Error(`M7 service relocation is missing ${site.label}`);
    }
    return {
      siteSectionId: sectionId,
      siteOffset: siteAddress - image.base + 1,
      kind: 1 as const,
      use: 1 as const,
      targetSymbolId,
      addend: 0,
    };
  });
  const localRelocations = [
    ...references.callReferences.map((reference) => ({
      siteLabel: reference.label,
      siteAddend: 1,
      targetAddend: 0,
      target: reference.target,
      valueKind: 1 as const,
      use: 1 as const,
    })),
    ...references.operandReferences.map((reference) => ({
      siteLabel: reference.label,
      siteAddend: 1,
      targetAddend: reference.addend,
      target: reference.target,
      valueKind: 2 as const,
      use: 2 as const,
    })),
    ...references.dataReferences.map((reference) => ({
      siteLabel: reference.siteLabel,
      siteAddend: reference.addend,
      targetAddend: 0,
      target: reference.target,
      valueKind: reference.valueKind,
      use: 2 as const,
    })),
  ].map((reference) => {
    const targetSymbolId = localIds.get(
      reference.target.toLowerCase() + ":" + reference.valueKind,
    );
    if (targetSymbolId === undefined) {
      throw new Error(`M9 local symbol is missing ${reference.target}`);
    }
    return {
      siteSectionId: sectionId,
      siteOffset: offset(image, reference.siteLabel) + reference.siteAddend,
      kind: 1 as const,
      use: reference.use,
      targetSymbolId,
      addend: reference.targetAddend,
    };
  });

  const vectorSymbolId = 0x7fff;
  symbols.push({
    id: vectorSymbolId,
    binding: "local",
    valueKind: 1,
    sectionId: 2,
    offset: 0,
  });
  return encodeNobj1({
    begin: { targetId: 1 },
    contracts: [
      {
        id: runtimeContractId,
        ...runtimeIdentity,
        data: Uint8Array.of(1, 0, localIds.get("topentry:1")!, 0),
      },
      { id: 2, ...valueIdentity, data: new Uint8Array() },
    ],
    regions: [region],
    sections: [
      {
        id: sectionId,
        storageKind: 1,
        permissions: 7,
        alignment: 4,
        length: image.bytes.length,
        runRegionId: 1,
        runPlacement: "fixed",
        runOffset: image.base - region.base,
        loadPlacement: "same",
        loadRegionId: 1,
        loadOffset: 0,
        fill: 0,
      },
      {
        id: bssSectionId,
        storageKind: 2,
        permissions: 3,
        alignment: 4,
        length: bss.bytes,
        runRegionId: 1,
        runPlacement: "allocate",
        runOffset: 0,
      },
      {
        id: 2,
        storageKind: 1,
        permissions: 5,
        alignment: 1,
        length: 3,
        runRegionId: 1,
        runPlacement: "fixed",
        runOffset: 0x0100 - region.base,
        loadPlacement: "same",
        loadRegionId: 1,
        loadOffset: 0,
        fill: 0,
      },
    ],
    ranges: [
      {
        id: 1,
        sectionId,
        view: "run",
        offset: offset(image, "BOOTDESC"),
        length: 40,
      },
      {
        id: 2,
        sectionId,
        view: "run",
        offset: offset(image, "STORDESC"),
        length: 20,
      },
    ],
    images: [
      { sectionId, offset: 0, bytes: image.bytes.slice() },
      { sectionId: 2, offset: 0, bytes: Uint8Array.of(0xc3, 0, 0) },
    ],
    patches: [],
    symbols: [...symbols, ...importSymbols],
    relocations: [
      ...serviceRelocations,
      ...localRelocations,
      {
        siteSectionId: 2,
        siteOffset: 1,
        kind: 1,
        use: 1,
        targetSymbolId: localIds.get("comstart:1")!,
        addend: 0,
      },
    ],
    metadata: [],
    layout: { mode: "module", entrySymbolId: vectorSymbolId },
  });
}

function runtimeObject(
  image: AtomImage,
  region: ReturnType<typeof imageRegion>,
): {
  readonly bytes: Uint8Array;
  readonly services: readonly { key: RuntimeKey; symbolId: number }[];
} {
  const runtimeBase = 0x0103;
  if (image.base !== runtimeBase) {
    throw new Error(
      `ATOM runtime begins at $${image.base.toString(16)}, expected $0103`,
    );
  }
  const localSymbols = runtimeServices.map((service, index) => ({
    id: index + 1,
    binding: "local" as const,
    valueKind: 1 as const,
    sectionId: 1,
    offset: address(image, service.label) - image.base,
  }));
  const objectBytes = encodeNobj1({
    begin: { targetId: 1 },
    contracts: [
      { id: 1, ...runtimeIdentity, data: new Uint8Array(4) },
      { id: 2, ...valueIdentity, data: new Uint8Array() },
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
        runOffset: runtimeBase - region.base,
        loadPlacement: "same",
        loadRegionId: 1,
        loadOffset: 0,
        fill: 0,
      },
    ],
    ranges: [],
    images: [{ sectionId: 1, offset: 0, bytes: image.bytes.slice() }],
    patches: [],
    symbols: localSymbols,
    relocations: [],
    metadata: [],
    layout: { mode: "module", entrySymbolId: 0 },
  });
  return {
    bytes: objectBytes,
    services: runtimeServices.map((service, index) => ({
      key: service.key,
      symbolId: index + 1,
    })),
  };
}

function targetLayout(profile: SkateTpaProfile) {
  return { regions: [targetRegion(profile)], visibility: [] };
}

async function compileMode(
  sourceBytes: Uint8Array,
  sourceName: SourceName,
  mode: CompilerMode,
  requestedHeapCells: number | undefined,
  profile: SkateTpaProfile = DEFAULT_SKATE_TPA_PROFILE,
): Promise<M7CompileResult> {
  validateSkateTpaProfile(profile);
  if (
    requestedHeapCells !== undefined &&
    (!Number.isInteger(requestedHeapCells) || requestedHeapCells < 3 ||
      requestedHeapCells > MAX_HEAP_CELLS)
  ) {
    throw new RangeError(
      `Skate heapCells must be an integer from 3 through ${MAX_HEAP_CELLS}`,
    );
  }
  const planningHeapCells = requestedHeapCells ?? MAX_HEAP_CELLS;
  const expanded = mode === "M10"
    ? expandSyntaxRules(sourceBytes, sourceName)
    : {
      bytes: sourceBytes.slice(),
      sourceName,
    };
  const source = expanded.bytes;
  const effectiveSourceName = expanded.sourceName;
  const services = new ServiceEmitter();
  const references = new LocalReferenceEmitter();
  const reader = new SourceReader(source, effectiveSourceName);
  const globalDefinitionNames = mode === "M10"
    ? scanTopLevelDefinitions(source, effectiveSourceName)
    : [];
  const expressionCompiler = new SchemeExpressionCompiler(
    source,
    effectiveSourceName,
    reader,
    services,
    references,
    mode,
    planningHeapCells,
    globalDefinitionNames,
  );
  const plan = expressionCompiler.compile();
  if (
    (mode === "M9" || mode === "M10") &&
    plan.literalCellCount + 2 > planningHeapCells - 1
  ) {
    throw new RangeError(
      `${mode} heap needs at least ${
        plan.literalCellCount + 3
      } physical cells for literals and startup`,
    );
  }

  await Deno.mkdir(buildRoot, { recursive: true });
  const workRoot = await Deno.makeTempDir({
    dir: buildRoot,
    prefix: mode.toLowerCase() + "-",
  });
  try {
    const originalRuntime = await assemble(
      "tests/m7-packed-runtime.asm",
      0x0103,
    );
    const workspaceBytes = runtimeWorkspaceBytes(originalRuntime);
    const runtimePath = `${workRoot}/runtime.asm`;
    const provisionalRuntimeSource = await runtimeSourceWithoutWorkspace(
      originalRuntime,
      0x8000,
      workRoot,
    );
    await Deno.writeTextFile(runtimePath, provisionalRuntimeSource);
    const runtimeEntry = relative(projectRoot, runtimePath);
    const measuredRuntime = await assemble(runtimeEntry, 0x0103);
    if (
      measuredRuntime.base + measuredRuntime.bytes.length > profile.stackLow
    ) {
      throw new RangeError(
        "Skate runtime exceeds the selected profile's stack guard",
      );
    }
    const region = imageRegion(profile);
    const programBase = align4(measuredRuntime.end);
    const callerPath = `${workRoot}/caller.asm`;
    // A metadata-only emitter pair lets us measure the fixed caller image
    // without consuming the real relocation labels.
    const measureSource = assemblyText(
      plan,
      new ServiceEmitter(services.sites.length),
      new LocalReferenceEmitter(
        references.operandReferences.length,
        references.callReferences.length,
      ),
      workspaceBytes,
      profile,
      programBase,
      planningHeapCells,
    );
    await Deno.writeTextFile(callerPath, measureSource);
    const callerEntry = relative(projectRoot, callerPath);
    const measuredCaller = await assemble(callerEntry, programBase);
    const selectedHeapCells = requestedHeapCells ??
      largestHeapCells(measuredCaller.end, profile, workspaceBytes);
    if (selectedHeapCells < 3) {
      throw new RangeError(
        "Skate caller exceeds the selected profile's stack guard: no room for its roots, activation arena, bitmap and minimum heap",
      );
    }
    if (
      (mode === "M9" || mode === "M10") &&
      plan.literalCellCount + 2 > selectedHeapCells - 1
    ) {
      throw new RangeError(
        `${mode} heap needs at least ${
          plan.literalCellCount + 3
        } physical cells for literals and startup`,
      );
    }
    const callerSource = assemblyText(
      plan,
      services,
      references,
      workspaceBytes,
      profile,
      programBase,
      selectedHeapCells,
    );
    await Deno.writeTextFile(callerPath, callerSource);
    const callerAssembly = await assemble(callerEntry, programBase);
    const bss = callerBssLayout(selectedHeapCells, workspaceBytes);
    const bssBase = align4(callerAssembly.end);
    if (bssBase + bss.bytes > profile.stackLow) {
      throw new RangeError(
        "Skate runtime storage exceeds the selected profile's stack guard",
      );
    }
    const runtimeSource = await runtimeSourceWithoutWorkspace(
      originalRuntime,
      bssBase + bss.runtimeWorkspace.offset,
      workRoot,
    );
    await Deno.writeTextFile(runtimePath, runtimeSource);
    const runtime = await assemble(runtimeEntry, 0x0103);
    if (runtime.end !== measuredRuntime.end) {
      throw new Error("Skate runtime workspace aliases changed code extent");
    }
    const runtimePart = runtimeObject(runtime, region);
    const objectBytes = callerObject(
      callerAssembly,
      services.sites,
      references,
      plan,
      selectedHeapCells,
      runtimeWorkspaceBytes(runtime),
      region,
    );
    const object = parseNobj1(objectBytes);
    const runtimeParsed = parseNobj1(runtimePart.bytes);
    const linked = linkNobj1(
      [
        { id: "skate-program", object },
        { id: "skate-runtime", object: runtimeParsed },
      ],
      {
        mainObjectId: "skate-program",
        target: targetLayout(profile),
        providers: [
          {
            id: "skate-" + mode.toLowerCase() + "-runtime-v2",
            objectId: "skate-runtime",
            supports: [runtimeIdentity, valueIdentity],
            services: runtimePart.services.map(({ key, symbolId }) => ({
              contract: runtimeIdentity,
              key,
              symbolId,
            })),
          },
        ],
      },
    ) as Parameters<typeof validateSkatePlacedContracts>[1];
    validateSkatePlacedContracts(
      [
        { id: "skate-program", object },
        { id: "skate-runtime", object: runtimeParsed },
      ],
      linked,
      [{
        objectId: "skate-program",
        bss: { address: bssBase, bytes: bss.bytes },
        roots: { address: bssBase + bss.roots.offset, bytes: bss.roots.bytes },
        activations: {
          address: bssBase + bss.activations.offset,
          bytes: bss.activations.bytes,
        },
        bitmap: {
          address: bssBase + bss.bitmap.offset,
          bytes: bss.bitmap.bytes,
        },
        heap: {
          address: bssBase + bss.heap.offset,
          bytes: selectedHeapCells * 4,
        },
        workspace: [
          ["HWORK", "HWEND"],
          ["GCWORK", "GCWEND"],
          ["F16WORK", "F16WEND"],
          ["NWORK", "NWEND"],
          ["RTWORK", "RTWEND"],
          ["RTPRFLAG", "RTPRWEND"],
        ]
          .map(([start, end]) => ({
            address: address(runtime, start!),
            bytes: address(runtime, end!) - address(runtime, start!),
          })),
        stack: { address: profile.stackLow, bytes: profile.stackCapacity },
      }],
    );
    const output = linked.regions.find(
      ({ targetRegionId }) => targetRegionId === profile.id,
    );
    if (output === undefined) {
      throw new Error("NOBJ link produced no CP/M image");
    }
    if (linked.entry?.address !== 0x0100) {
      throw new Error(`NOBJ ${mode} entry is not at $0100`);
    }
    const callerPlacement = linked.placements.find(
      ({ objectId, sectionId }) =>
        objectId === "skate-program" && sectionId === 1,
    );
    if (callerPlacement?.runAddress !== programBase) {
      throw new Error(
        `NOBJ did not place the ${mode} program immediately after its runtime`,
      );
    }
    const bssPlacement = linked.placements.find(
      ({ objectId, sectionId }) =>
        objectId === "skate-program" && sectionId === 3,
    );
    if (bssPlacement?.runAddress !== bssBase) {
      throw new Error(
        `NOBJ did not place the ${mode} runtime storage immediately after its image`,
      );
    }
    const runtimePlacement = linked.placements.find(
      ({ objectId, sectionId }) =>
        objectId === "skate-runtime" && sectionId === 1,
    );
    if (runtimePlacement?.runAddress !== 0x0103) {
      throw new Error(`NOBJ did not place the ${mode} runtime at $0103`);
    }
    return {
      objectBytes,
      comBytes: output.bytes.slice(0, output.usedLength),
      resultKind: plan.resultKind,
      entryAddress: linked.entry.address,
      programAddress: callerPlacement.runAddress,
      resultAddress: callerPlacement.runAddress +
        offset(callerAssembly, "RESULT"),
      resultTagAddress: callerPlacement.runAddress +
        offset(callerAssembly, "RESULTAG"),
      heapCells: selectedHeapCells,
      bssBaseAddress: bssBase,
      bssBytes: bss.bytes,
      bssEndAddress: bssBase + bss.bytes,
      rootBaseAddress: bssBase + bss.roots.offset,
      bitmapBaseAddress: bssBase + bss.bitmap.offset,
      rootBytes: bss.roots.bytes,
      activationBytes: bss.activations.bytes,
      runtimeWorkspaceBytes: bss.runtimeWorkspace.bytes,
      bitmapBytes: bss.bitmap.bytes,
      heapBytes: bss.heap.bytes,
      heapBaseAddress: bssBase + bss.heap.offset,
      rootHighWaterAddress: runtimePlacement.runAddress +
        offset(runtime, "RTROOTMX"),
      activationBaseAddress: bssBase + bss.activations.offset,
      activationHighWaterAddress: runtimePlacement.runAddress +
        offset(runtime, "RTACTHI"),
      runtimeBase: runtimePlacement.runAddress,
      runtimeLength: runtime.bytes.length,
      runtimeErrorAddress: runtimePlacement.runAddress +
        offset(runtime, "RTERROR"),
      callerImageBytes: callerAssembly.bytes.length,
      callerCodeBytes: offset(callerAssembly, "TOPDESC") +
        address(callerAssembly, "PRINTFLG") -
        address(callerAssembly, "PRTINT16"),
      stackTopAddress: profile.stackTop,
      stackLowAddress: profile.stackLow,
      object,
    };
  } finally {
    await Deno.remove(workRoot, { recursive: true });
  }
}

export async function compileM7(
  sourceBytes: Uint8Array,
  sourceName = "<input>",
): Promise<M7CompileResult> {
  return await compileMode(sourceBytes, sourceName, "M7", undefined);
}

export async function compileM8(
  sourceBytes: Uint8Array,
  sourceName = "<input>",
  options: M8CompileOptions = {},
): Promise<M8CompileResult> {
  const heapCells = options.heapCells;
  if (
    heapCells !== undefined &&
    (!Number.isInteger(heapCells) || heapCells < 3 ||
      heapCells > MAX_HEAP_CELLS)
  ) {
    throw new RangeError(
      `M8 heapCells must be an integer from 3 through ${MAX_HEAP_CELLS}`,
    );
  }
  const result = await compileMode(sourceBytes, sourceName, "M8", heapCells);
  return { ...result, heapCells: result.heapCells };
}

export async function compileM9(
  sourceBytes: Uint8Array,
  sourceName = "<input>",
  options: M9CompileOptions = {},
): Promise<M9CompileResult> {
  const heapCells = options.heapCells;
  if (
    heapCells !== undefined &&
    (!Number.isInteger(heapCells) || heapCells < 3 ||
      heapCells > MAX_HEAP_CELLS)
  ) {
    throw new RangeError(
      `M9 heapCells must be an integer from 3 through ${MAX_HEAP_CELLS}`,
    );
  }
  const result = await compileMode(sourceBytes, sourceName, "M9", heapCells);
  return { ...result, heapCells: result.heapCells };
}

export async function compileM10(
  sourceBytes: Uint8Array,
  sourceName = "<input>",
  options: M10CompileOptions = {},
): Promise<M10CompileResult> {
  const heapCells = options.heapCells;
  if (
    heapCells !== undefined &&
    (!Number.isInteger(heapCells) || heapCells < 3 ||
      heapCells > MAX_HEAP_CELLS)
  ) {
    throw new RangeError(
      `M10 heapCells must be an integer from 3 through ${MAX_HEAP_CELLS}`,
    );
  }
  const tpaProfile = options.tpaProfile ?? DEFAULT_SKATE_TPA_PROFILE;
  const result = await compileMode(
    sourceBytes,
    sourceName,
    "M10",
    heapCells,
    tpaProfile,
  );
  return { ...result, heapCells: result.heapCells, tpaProfile };
}

/** Compile an ordered source package while retaining part names in diagnostics. */
export async function compileM10Package(
  sourcePackage: SourcePackage,
  options: M10CompileOptions = {},
): Promise<M10CompileResult> {
  const heapCells = options.heapCells;
  if (
    heapCells !== undefined &&
    (!Number.isInteger(heapCells) || heapCells < 3 ||
      heapCells > MAX_HEAP_CELLS)
  ) {
    throw new RangeError(
      `M10 heapCells must be an integer from 3 through ${MAX_HEAP_CELLS}`,
    );
  }
  const tpaProfile = options.tpaProfile ?? DEFAULT_SKATE_TPA_PROFILE;
  const result = await compileMode(
    sourcePackage.bytes,
    sourcePackage,
    "M10",
    heapCells,
    tpaProfile,
  );
  return { ...result, heapCells: result.heapCells, tpaProfile };
}
