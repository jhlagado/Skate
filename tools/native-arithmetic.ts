/**
 * Reader-driven reference for the first native compiler slice.
 *
 * This module deliberately keeps the same boundary as the target producer:
 * it consumes SourceReader events once, retains only the two operand values,
 * and emits a committed NOBJ object plus its COM image.  The Z80 command in
 * compiler/native-compiler.asm uses the same event order and value ABI.
 */
import { encodeNobj1, parseNobj1 } from "@jhlagado/z80-tool-services";
import { binary, formatNumber, type Operation, type Value } from "./numeric.ts";
import { type Position, type ReadEvent, SourceReader } from "./reader.ts";

const REGION = {
  id: 1,
  addressSpaceKey: "z80.cpu",
  storageKey: "cpm.ram",
  base: 0x0100,
  capacity: 0xe300,
  imageFill: 0,
  permissions: 7,
  banked: false,
} as const;

const RUNTIME = {
  key: "org.skate.runtime",
  majorVersion: 2,
  minorVersion: 0,
} as const;

const OPERATION: Record<string, Operation> = {
  "+": "add",
  "-": "sub",
  "*": "mul",
  "/": "div",
};

/** The fixed image layout is also checked by the target template tests. */
export const NATIVE_MESSAGE_BYTES = 12;
export const NATIVE_MESSAGE_OFFSET = 20;

export interface NativeArithmeticResult {
  readonly value: Value;
  readonly message: string;
  readonly comBytes: Uint8Array;
  readonly objectBytes: Uint8Array;
  readonly object: ReturnType<typeof parseNobj1>;
  readonly expressionStateBytes: number;
  readonly sourceBytes: number;
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

class Cursor {
  private next: ReadEvent | null = null;
  private buffered = false;
  constructor(private readonly events: Iterator<ReadEvent>) {}
  peek(): ReadEvent | null {
    if (!this.buffered) {
      const value = this.events.next();
      this.next = value.done ? null : value.value;
      this.buffered = true;
    }
    return this.next;
  }
  take(): ReadEvent | null {
    const value = this.peek();
    this.next = null;
    this.buffered = false;
    return value;
  }
}

function readValue(cursor: Cursor, description: string): Value {
  const event = cursor.take();
  if (event === null) fail(undefined, `Expected ${description}`);
  if (event.kind !== "value") {
    fail(event.at, `${description} must be numeric`);
  }
  if (event.value[0] !== 0 && event.value[0] !== 3) {
    fail(event.at, `${description} must be numeric`);
  }
  return event.value;
}

/** Render a compact, deterministic message for the generated COM image. */
export function nativeMessage(value: Value): string {
  if (value[0] === 3) return `${formatNumber(value)}\r\n`;
  return `F16:${value[1].toString(16).toUpperCase().padStart(4, "0")}\r\n`;
}

function imageFor(value: Value): Uint8Array {
  const message = new TextEncoder().encode(nativeMessage(value) + "$");
  if (message.length > NATIVE_MESSAGE_BYTES) {
    throw new RangeError("native arithmetic message exceeds image slot");
  }
  const image = Uint8Array.from([
    0xc3,
    0x07,
    0x01,
    0xcd,
    0x00,
    0x00,
    0xc9,
    0x11,
    0x14,
    0x01,
    0x0e,
    0x09,
    0xcd,
    0x05,
    0x00,
    0x0e,
    0x00,
    0xcd,
    0x05,
    0x00,
    ...new Uint8Array(NATIVE_MESSAGE_BYTES),
  ]);
  image.set(message, NATIVE_MESSAGE_OFFSET);
  return image;
}

function objectFor(image: Uint8Array): Uint8Array {
  return encodeNobj1({
    begin: { targetId: 1 },
    contracts: [{ id: 1, ...RUNTIME, data: new Uint8Array(4) }],
    regions: [REGION],
    sections: [{
      id: 1,
      storageKind: 1,
      permissions: 7,
      alignment: 1,
      length: image.length,
      runRegionId: 1,
      runPlacement: "fixed",
      runOffset: 0,
      loadPlacement: "same",
      loadRegionId: 1,
      loadOffset: 0,
      fill: 0,
    }],
    ranges: [],
    images: [{ sectionId: 1, offset: 0, bytes: image }],
    patches: [],
    symbols: [
      {
        id: 1,
        binding: "local",
        valueKind: 1,
        sectionId: 1,
        offset: 0,
      },
      {
        id: 2,
        binding: "service-import",
        valueKind: 1,
        contractId: 1,
        serviceKey: "numeric.classify",
      },
    ],
    relocations: [{
      siteSectionId: 1,
      siteOffset: 4,
      kind: 1,
      use: 1,
      targetSymbolId: 2,
      addend: 0,
    }],
    metadata: [],
    layout: { mode: "module", entrySymbolId: 1 },
  });
}

/** Compile one flat arithmetic form without constructing an AST. */
export function compileNativeArithmetic(
  sourceBytes: Uint8Array,
  sourceName = "<input>",
): NativeArithmeticResult {
  const reader = new SourceReader(sourceBytes, sourceName);
  const cursor = new Cursor(reader.events());
  const open = cursor.take();
  if (open === null || open.kind !== "open") {
    fail(open?.at, "Expected one arithmetic list");
  }
  const head = cursor.take();
  if (head === null || head.kind !== "symbol") {
    fail(head?.at ?? open.at, "Expected an arithmetic operator");
  }
  const operator = symbolText(reader, head);
  const operation = OPERATION[operator];
  if (operation === undefined) fail(head.at, `Unsupported form ${operator}`);
  const left = readValue(cursor, "left arithmetic operand");
  const right = readValue(cursor, "right arithmetic operand");
  const close = cursor.take();
  if (close === null || close.kind !== "close") {
    fail(close?.at ?? head.at, "Expected closing ) after arithmetic form");
  }
  const trailing = cursor.peek();
  if (trailing !== null) {
    fail(trailing.at, "Only one top-level expression is supported");
  }
  let value: Value;
  try {
    value = binary(operation, left, right);
  } catch (error) {
    if (error instanceof Error) fail(head.at, error.message);
    throw error;
  }
  const comBytes = imageFor(value);
  const objectBytes = objectFor(comBytes);
  return {
    value,
    message: nativeMessage(value),
    comBytes,
    objectBytes,
    object: parseNobj1(objectBytes),
    expressionStateBytes: 8,
    sourceBytes: sourceBytes.length,
  };
}
