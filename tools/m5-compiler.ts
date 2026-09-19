/** Compile Skate's M5/M6 subset to NOBJ and a linked CP/M executable. */
import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";
import {
  encodeNobj1,
  linkNobj1,
  parseNobj1,
} from "@jhlagado/z80-tool-services";
import { relative } from "node:path";
import { fileURLToPath } from "node:url";
import { isNumber, type Value } from "./numeric.ts";
import {
  DEFAULT_READER_LIMITS,
  type Position,
  type ReadEvent,
  SourceReader,
} from "./reader.ts";

const projectRoot = fileURLToPath(new URL("../", import.meta.url));
const buildRoot = `${projectRoot}build`;
const objectRegion = {
  id: 1,
  addressSpaceKey: "z80.cpu",
  storageKey: "cpm.ram",
  base: 0x0100,
  capacity: 0xe300,
  imageFill: 0,
  permissions: 7,
  banked: false,
} as const;
const targetRegion = {
  id: "cpm-tpa",
  addressSpaceKey: objectRegion.addressSpaceKey,
  storageKey: objectRegion.storageKey,
  base: objectRegion.base,
  capacity: objectRegion.capacity,
  imageFill: objectRegion.imageFill,
  permissions: objectRegion.permissions,
  banked: objectRegion.banked,
} as const;
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
  { key: "numeric.add", label: "NADD" },
  { key: "numeric.sub", label: "NSUB" },
  { key: "numeric.mul", label: "NMUL" },
  { key: "numeric.div", label: "NDIV" },
  { key: "numeric.negate", label: "NNEG" },
  { key: "numeric.classify", label: "NCLASS" },
] as const;
type RuntimeService = typeof runtimeServices[number];
type ArithmeticOperator = "+" | "-" | "*" | "/";
type ResultKind = "integer" | "binary16" | "immediate" | "dynamic";
const runtimeServiceByOperator = {
  "+": runtimeServices[0],
  "-": runtimeServices[1],
  "*": runtimeServices[2],
  "/": runtimeServices[3],
} satisfies Record<ArithmeticOperator, RuntimeService>;

export interface M5CompileResult {
  /** Canonical NOBJ 1.0 input object, before runtime placement. */
  readonly objectBytes: Uint8Array;
  /** CP/M transient bytes, loaded at $0100. */
  readonly comBytes: Uint8Array;
  readonly entryAddress: number;
  readonly resultAddress: number;
  readonly resultTagAddress: number;
  readonly resultKind: ResultKind;
  readonly runtimeBase: number;
  readonly runtimeLength: number;
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

interface CompilePlan {
  readonly instructions: readonly string[];
  readonly serviceCalls: readonly RuntimeService[];
  readonly temporarySlots: number;
  readonly resultKind: ResultKind;
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

function valueResultKind(value: Value): ResultKind {
  if (!isNumber(value)) return "immediate";
  return value[0] === 3 ? "integer" : "binary16";
}

function mergeResultKinds(left: ResultKind, right: ResultKind): ResultKind {
  return left === right ? left : "dynamic";
}

class ExpressionCompiler {
  private readonly cursor: EventCursor;
  private readonly instructions: string[] = [];
  private readonly serviceCalls: RuntimeService[] = [];
  private tempDepth = 0;
  private temporarySlots = 0;
  private labelIndex = 0;

  constructor(private readonly reader: SourceReader) {
    this.cursor = new EventCursor(reader.events());
  }

  compile(): CompilePlan {
    const resultKind = this.readExpression();
    const trailing = this.cursor.peek();
    if (trailing !== null) {
      fail(trailing.at, "Only one top-level expression is supported");
    }
    return {
      instructions: this.instructions,
      serviceCalls: this.serviceCalls,
      temporarySlots: this.temporarySlots,
      resultKind,
    };
  }

  private readExpression(): ResultKind {
    const event = this.cursor.take();
    if (event === null) fail(undefined, "Expected one Scheme expression");
    switch (event.kind) {
      case "value":
        this.emitValue(event.value);
        return valueResultKind(event.value);
      case "open":
        return this.readList(event.at);
      case "symbol":
        return fail(event.at, "Identifiers are not compiled in this milestone");
      case "string":
        return fail(
          event.at,
          "String literals are not emitted in this milestone",
        );
      case "quote":
        return fail(event.at, "Quoted data is not compiled in this milestone");
      case "dot":
        return fail(event.at, "A dot is not valid in an expression");
      case "close":
        return fail(event.at, "Unexpected closing parenthesis");
    }
  }

  private readList(at: Position): ResultKind {
    const head = this.cursor.take();
    if (head === null) fail(at, "Expected a form name after (");
    if (head.kind !== "symbol") {
      fail(head.at, "A list in this milestone must start with a form name");
    }
    const name = symbolText(this.reader, head);
    if (name === "if") return this.readIf(head.at);
    if (name === "begin") return this.readBegin(head.at);
    if (name === "+" || name === "-" || name === "*" || name === "/") {
      return this.readArithmetic(name, head.at);
    }
    fail(head.at, "Unsupported form " + JSON.stringify(name));
  }

  private readIf(at: Position): ResultKind {
    this.readRequiredExpression(at, "if test");
    const id = this.labelIndex.toString(36).toUpperCase().padStart(4, "0");
    this.labelIndex++;
    const trueLabel = "IFTR" + id;
    const falseLabel = "IFFL" + id;
    const endLabel = "IFEN" + id;

    this.instructions.push(
      "        CP 0",
      "        JP NZ," + trueLabel,
      "        LD DE,$FE00",
      "        OR A",
      "        SBC HL,DE",
      "        JP Z," + falseLabel,
      trueLabel + ":",
    );

    const consequentKind = this.readRequiredExpression(at, "if consequent");
    const following = this.cursor.peek();
    if (following === null) fail(at, "Expected closing ) after if");
    this.instructions.push("        JP " + endLabel, falseLabel + ":");

    let alternativeKind: ResultKind;
    if (following.kind === "close") {
      this.emitValue([0, 0xfe04]);
      alternativeKind = "immediate";
    } else {
      alternativeKind = this.readRequiredExpression(at, "if alternative");
    }
    this.expectClose(at, "if");
    this.instructions.push(endLabel + ":");
    return mergeResultKinds(consequentKind, alternativeKind);
  }

  private readBegin(at: Position): ResultKind {
    const first = this.cursor.peek();
    if (first === null) fail(at, "Expected closing ) after begin");
    if (first.kind === "close") {
      this.cursor.take();
      this.emitValue([0, 0xfe04]);
      return "immediate";
    }

    let resultKind: ResultKind | null = null;
    for (;;) {
      const next = this.cursor.peek();
      if (next === null) fail(at, "Expected closing ) after begin");
      if (next.kind === "close") break;
      resultKind = this.readExpression();
    }
    this.expectClose(at, "begin");
    return resultKind ?? "immediate";
  }

  private readArithmetic(
    operator: ArithmeticOperator,
    at: Position,
  ): ResultKind {
    const first = this.cursor.peek();
    if (first === null) fail(at, "Expected closing ) after " + operator);
    if (first.kind === "close") {
      this.cursor.take();
      if (operator === "-" || operator === "/") {
        fail(at, operator + " has too few operands in this milestone");
      }
      this.emitValue(operator === "+" ? [3, 0] : [3, 1]);
      return "integer";
    }

    const firstAt = first.at;
    const firstKind = this.readRequiredExpression(at, "arithmetic operand");
    this.requireNumber(firstKind, firstAt);

    const next = this.cursor.peek();
    if (next === null) fail(at, "Expected closing ) after " + operator);
    if (next.kind === "close") {
      this.cursor.take();
      if (operator === "-") {
        this.emitService(runtimeServices[4]);
      } else if (
        (operator === "+" || operator === "*") && firstKind === "dynamic"
      ) {
        this.emitService(runtimeServices[5]);
      } else if (operator === "/") {
        fail(at, "/ has too few operands in this milestone");
      }
      return firstKind;
    }

    let sawDynamic = firstKind === "dynamic";
    let sawBinary16 = firstKind === "binary16";
    const service = runtimeServiceByOperator[operator];
    for (;;) {
      const operand = this.cursor.peek();
      if (operand === null) {
        fail(at, "Expected closing ) after " + operator);
      }
      if (operand.kind === "close") break;

      let rightKind: ResultKind;
      if (operand.kind === "value") {
        this.cursor.take();
        if (!isNumber(operand.value)) {
          fail(operand.at, "Arithmetic operands must be numeric");
        }
        rightKind = valueResultKind(operand.value);
        this.instructions.push(
          "        LD B," + operand.value[0],
          "        LD DE," + numberLiteral(operand.value),
        );
      } else {
        const slot = this.spillLeft(operand.at);
        rightKind = this.readRequiredExpression(at, "arithmetic operand");
        this.requireNumber(rightKind, operand.at);
        this.tempDepth--;
        this.instructions.push(
          "        LD B,A",
          "        LD D,H",
          "        LD E,L",
          "        LD A,(TMP" + slot + "TAG)",
          "        LD HL,(TMP" + slot + ")",
        );
      }
      this.emitService(service);
      sawDynamic ||= rightKind === "dynamic";
      sawBinary16 ||= rightKind === "binary16";
    }

    this.expectClose(at, operator);
    if (operator === "/") return "binary16";
    if (sawDynamic) return "dynamic";
    return sawBinary16 ? "binary16" : "integer";
  }

  private readRequiredExpression(
    at: Position,
    description: string,
  ): ResultKind {
    const next = this.cursor.peek();
    if (next === null || next.kind === "close") {
      fail(next?.at ?? at, "Expected " + description);
    }
    return this.readExpression();
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

  private emitValue(value: Value): void {
    this.instructions.push(
      "        LD A," + value[0],
      "        LD HL," + numberLiteral(value),
    );
  }

  private emitService(service: RuntimeService): void {
    const call = this.serviceCalls.length;
    this.serviceCalls.push(service);
    this.instructions.push(
      "SVCALL" + call + ":",
      "        CALL $0000",
      "        JP C,RTERROR",
    );
  }

  private spillLeft(at: Position): number {
    const slot = this.tempDepth;
    if (slot >= DEFAULT_READER_LIMITS.nesting) {
      fail(at, "Nested arithmetic exceeds temporary-slot capacity");
    }
    this.tempDepth++;
    this.temporarySlots = Math.max(this.temporarySlots, this.tempDepth);
    this.instructions.push(
      "        LD (TMP" + slot + "),HL",
      "        LD (TMP" + slot + "TAG),A",
    );
    return slot;
  }
}

function numberLiteral(value: Value): string {
  return "$" + value[1].toString(16).toUpperCase().padStart(4, "0");
}

function compileExpression(bytes: Uint8Array, source: string): CompilePlan {
  return new ExpressionCompiler(new SourceReader(bytes, source)).compile();
}

function m5Assembly(
  plan: CompilePlan,
  runtimeWorkspace: number,
): string {
  const lines = [
    "        ORG $0100",
    "START:",
    "        CALL LITINIT",
    "        CALL TOPLEVEL",
    "        LD C,0",
    "        CALL $0005",
    "        JP START",
    "",
    "LITINIT:",
    "        RET",
    "",
    "TOPLEVEL:",
    ...plan.instructions,
    "        LD (RESULT),HL",
    "        LD (RTAG),A",
  ];
  if (plan.resultKind === "integer") {
    lines.push("        CALL PRINT16");
  } else if (plan.resultKind === "dynamic") {
    lines.push(
      "        LD A,(RTAG)",
      "        CP 3",
      "        JP NZ,PRTSKIP",
      "        CALL PRINT16",
      "PRTSKIP:",
    );
  }
  lines.push("        RET");
  lines.push("");
  lines.push("RTERROR:");
  lines.push("        LD DE,ERRTXT");
  lines.push("        LD C,9");
  lines.push("        CALL $0005");
  lines.push("        RET");

  if (plan.resultKind === "integer" || plan.resultKind === "dynamic") {
    lines.push(...integerPrinter());
  }

  lines.push("");
  lines.push("RESULT:");
  lines.push("        DW 0");
  lines.push("RTAG:");
  lines.push("        DB 0");
  lines.push("ERRTXT:");
  lines.push('        DB "NUMERIC ERROR",13,10,"$"');
  lines.push("");
  lines.push("BOOTDESC:");
  lines.push("        DW 1");
  lines.push("        DW 0,0");
  lines.push("        DW 0,0");
  lines.push("        DW 0");
  lines.push("        DW 0");
  lines.push("        DW 0");
  lines.push("        DW 0");
  lines.push("        DW 0");
  lines.push("        DW " + runtimeWorkspace);
  lines.push("        DW 0");
  lines.push("        DW 0,0");
  lines.push("        DW 0,0");
  lines.push("        DW 0,0");
  lines.push("        DW 0,0");
  lines.push("TOPPROC:");
  lines.push("        DW 0,0,0");
  lines.push("");

  if (plan.resultKind === "integer" || plan.resultKind === "dynamic") {
    lines.push(...integerPrinterData());
  }
  for (let slot = 0; slot < plan.temporarySlots; slot++) {
    lines.push(
      "TMP" + slot + ":",
      "        DW 0",
      "TMP" + slot + "TAG:",
      "        DB 0",
    );
  }
  return lines.join("\n") + "\n";
}

function integerPrinter(): string[] {
  return [
    "",
    "PRINT16:",
    "        LD A,0",
    "        LD (PSTART),A",
    "        BIT 7,H",
    "        JP Z,P16POS",
    "        LD A,45",
    "        CALL PUTCHAR",
    "        LD A,0",
    "        SUB L",
    "        LD L,A",
    "        LD A,0",
    "        SBC A,H",
    "        LD H,A",
    "P16POS:",
    "        LD DE,10000",
    "        CALL PPLACE",
    "        LD DE,1000",
    "        CALL PPLACE",
    "        LD DE,100",
    "        CALL PPLACE",
    "        LD DE,10",
    "        CALL PPLACE",
    "        LD A,1",
    "        LD (PSTART),A",
    "        LD DE,1",
    "        CALL PPLACE",
    "        LD A,13",
    "        CALL PUTCHAR",
    "        LD A,10",
    "        CALL PUTCHAR",
    "        RET",
    "PPLACE:",
    "        LD B,0",
    "PPL:",
    "        OR A",
    "        SBC HL,DE",
    "        JP C,PPDONE",
    "        INC B",
    "        JP PPL",
    "PPDONE:",
    "        ADD HL,DE",
    "        LD A,B",
    "        OR A",
    "        JP NZ,PPDIG",
    "        LD A,(PSTART)",
    "        OR A",
    "        RET Z",
    "PPDIG:",
    "        LD A,1",
    "        LD (PSTART),A",
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
  return ["PSTART:", "        DB 0"];
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

function parseAssemblyImage(image: AtomImage, name: string, base: number) {
  if (image.base !== base) {
    throw new Error(
      `${name} begins at $${image.base.toString(16)}, expected $${
        base.toString(16)
      }`,
    );
  }
  return image;
}

function callerObject(
  image: AtomImage,
  serviceCalls: readonly RuntimeService[],
): Uint8Array {
  const sectionId = 1;
  const contractId = 1;
  const symbolIds = {
    start: 1,
    topLevel: 2,
    literalInit: 3,
    bootDescriptor: 4,
    topProcedure: 5,
    result: 6,
    topLevelAddress: 7,
    literalInitAddress: 8,
  };
  const servicesUsed: RuntimeService[] = [];
  for (const service of serviceCalls) {
    if (!servicesUsed.some((used) => used.key === service.key)) {
      servicesUsed.push(service);
    }
  }
  const importIds = new Map<string, number>();
  servicesUsed.forEach((service, index) =>
    importIds.set(service.key, 10 + index)
  );
  const serviceSymbols = servicesUsed.map((service) => ({
    id: importIds.get(service.key)!,
    binding: "service-import" as const,
    valueKind: 1 as const,
    contractId,
    serviceKey: service.key,
  }));
  const symbols = [
    {
      id: symbolIds.start,
      binding: "local" as const,
      valueKind: 1 as const,
      sectionId,
      offset: offset(image, "START"),
    },
    {
      id: symbolIds.topLevel,
      binding: "local" as const,
      valueKind: 1 as const,
      sectionId,
      offset: offset(image, "TOPLEVEL"),
    },
    {
      id: symbolIds.topLevelAddress,
      binding: "local" as const,
      valueKind: 2 as const,
      sectionId,
      offset: offset(image, "TOPLEVEL"),
    },
    {
      id: symbolIds.literalInit,
      binding: "local" as const,
      valueKind: 1 as const,
      sectionId,
      offset: offset(image, "LITINIT"),
    },
    {
      id: symbolIds.literalInitAddress,
      binding: "local" as const,
      valueKind: 2 as const,
      sectionId,
      offset: offset(image, "LITINIT"),
    },
    {
      id: symbolIds.bootDescriptor,
      binding: "local" as const,
      valueKind: 2 as const,
      sectionId,
      offset: offset(image, "BOOTDESC"),
    },
    {
      id: symbolIds.topProcedure,
      binding: "local" as const,
      valueKind: 2 as const,
      sectionId,
      offset: offset(image, "TOPPROC"),
    },
    {
      id: symbolIds.result,
      binding: "local" as const,
      valueKind: 2 as const,
      sectionId,
      offset: offset(image, "RESULT"),
    },
    ...serviceSymbols,
  ];
  const serviceRelocations = serviceCalls.map((service, index) => {
    const callAddress = image.symbols.get("svcall" + index);
    if (callAddress === undefined) {
      throw new Error("Compiler service-call census mismatch");
    }
    const targetSymbolId = importIds.get(service.key);
    if (targetSymbolId === undefined) {
      throw new Error("Compiler service import is missing");
    }
    return {
      siteSectionId: sectionId,
      siteOffset: callAddress - image.base + 1,
      kind: 1 as const,
      use: 1 as const,
      targetSymbolId,
      addend: 0,
    };
  });
  const relocations = [
    ...serviceRelocations,
    {
      siteSectionId: sectionId,
      siteOffset: offset(image, "BOOTDESC") + 10,
      kind: 1 as const,
      use: 2 as const,
      targetSymbolId: symbolIds.literalInitAddress,
      addend: 0,
    },
    {
      siteSectionId: sectionId,
      siteOffset: offset(image, "BOOTDESC") + 12,
      kind: 1 as const,
      use: 2 as const,
      targetSymbolId: symbolIds.topProcedure,
      addend: 0,
    },
    {
      siteSectionId: sectionId,
      siteOffset: offset(image, "TOPPROC"),
      kind: 1 as const,
      use: 2 as const,
      targetSymbolId: symbolIds.topLevelAddress,
      addend: 0,
    },
  ];
  const section = {
    id: sectionId,
    storageKind: 1 as const,
    permissions: 5,
    alignment: 1,
    length: image.bytes.length,
    runRegionId: 1,
    runPlacement: "allocate" as const,
    runOffset: 0,
    loadPlacement: "same" as const,
    loadRegionId: 1,
    loadOffset: 0,
    fill: 0,
  };
  if (image.bytes.length > 0x0700) {
    throw new RangeError(
      "Compiler caller exceeds the $0100..$07FF code window",
    );
  }
  return encodeNobj1({
    begin: { targetId: 1 },
    contracts: [
      {
        id: contractId,
        ...runtimeIdentity,
        data: Uint8Array.of(1, 0, symbolIds.topLevel, 0),
      },
      {
        id: 2,
        ...valueIdentity,
        data: new Uint8Array(),
      },
    ],
    regions: [objectRegion],
    sections: [section],
    ranges: [
      {
        id: 1,
        sectionId,
        view: "run",
        offset: offset(image, "BOOTDESC"),
        length: 40,
      },
    ],
    images: [{ sectionId, offset: 0, bytes: image.bytes.slice() }],
    patches: [],
    symbols,
    relocations,
    metadata: [],
    layout: { mode: "module", entrySymbolId: symbolIds.start },
  });
}

function runtimeObject(image: AtomImage): {
  bytes: Uint8Array;
  services: readonly { key: string; symbolId: number }[];
} {
  if (image.base !== 0x0800) {
    throw new Error(
      `ATOM runtime begins at $${image.base.toString(16)}, expected $0800`,
    );
  }
  const services = runtimeServices.map((service, index) => ({
    ...service,
    symbolId: index + 1,
  }));
  const symbols = services.map((service) => ({
    id: service.symbolId,
    binding: "local" as const,
    valueKind: 1 as const,
    sectionId: 1,
    offset: address(image, service.label) - image.base,
  }));
  const objectBytes = encodeNobj1({
    begin: { targetId: 1 },
    contracts: [
      {
        id: 1,
        ...runtimeIdentity,
        data: new Uint8Array(4),
      },
      {
        id: 2,
        ...valueIdentity,
        data: new Uint8Array(),
      },
    ],
    regions: [objectRegion],
    sections: [
      {
        id: 1,
        storageKind: 1,
        permissions: 7,
        alignment: 1,
        length: image.bytes.length,
        runRegionId: 1,
        runPlacement: "fixed",
        runOffset: 0x0700,
        loadPlacement: "same",
        loadRegionId: 1,
        loadOffset: 0,
        fill: 0,
      },
    ],
    ranges: [],
    images: [{ sectionId: 1, offset: 0, bytes: image.bytes.slice() }],
    patches: [],
    symbols,
    relocations: [],
    metadata: [],
    layout: { mode: "module", entrySymbolId: 0 },
  });
  return {
    bytes: objectBytes,
    services: services.map(({ key, symbolId }) => ({ key, symbolId })),
  };
}

function runtimeWorkspaceBytes(image: AtomImage): number {
  const ranges = [
    ["F16WORK", "F16WEND"],
    ["NWORK", "NWEND"],
  ] as const;
  return ranges.reduce((total, [start, end]) => {
    const length = address(image, end) - address(image, start);
    if (length < 0) throw new Error(`${end} precedes ${start}`);
    return total + length;
  }, 0);
}

function targetLayout() {
  return {
    regions: [targetRegion],
    visibility: [],
  };
}

export async function compileM5(
  sourceBytes: Uint8Array,
  sourceName = "<input>",
): Promise<
  M5CompileResult & { readonly object: ReturnType<typeof parseNobj1> }
> {
  const plan = compileExpression(sourceBytes, sourceName);
  await Deno.mkdir(buildRoot, { recursive: true });
  const workRoot = await Deno.makeTempDir({ dir: buildRoot, prefix: "m5-" });
  try {
    const runtime = await assemble("tests/m5-runtime.asm", 0x0800);
    const runtimePart = runtimeObject(runtime);
    const callerPath = `${workRoot}/caller.asm`;
    const callerSource = m5Assembly(plan, runtimeWorkspaceBytes(runtime));
    await Deno.writeTextFile(callerPath, callerSource);
    const callerEntry = relative(projectRoot, callerPath);
    const callerAssembly = parseAssemblyImage(
      await assemble(callerEntry, 0x0100),
      callerEntry,
      0x0100,
    );
    const objectBytes = callerObject(callerAssembly, plan.serviceCalls);
    const object = parseNobj1(objectBytes);
    const runtimeParsed = parseNobj1(runtimePart.bytes);
    const linked: {
      placements: readonly {
        objectId: string;
        sectionId: number;
        runAddress: number;
      }[];
      regions: readonly {
        targetRegionId: string;
        bytes: Uint8Array;
        usedLength: number;
      }[];
      entry?: { address: number };
    } = linkNobj1(
      [
        { id: "skate-program", object },
        { id: "skate-runtime", object: runtimeParsed },
      ],
      {
        mainObjectId: "skate-program",
        target: targetLayout(),
        providers: [
          {
            id: "skate-numeric-runtime-v2",
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
    );
    const output = linked.regions.find(
      ({ targetRegionId }) => targetRegionId === targetRegion.id,
    );
    if (output === undefined) {
      throw new Error("NOBJ link produced no CP/M TPA image");
    }
    if (linked.entry?.address !== targetRegion.base) {
      throw new Error(
        `NOBJ startup entry is $${
          linked.entry?.address.toString(16)
        }, expected $0100`,
      );
    }
    const callerPlacement = linked.placements.find(
      ({ objectId, sectionId }) =>
        objectId === "skate-program" && sectionId === 1,
    );
    if (
      callerPlacement === undefined || callerPlacement.runAddress !== 0x0100
    ) {
      throw new Error("NOBJ did not place the CP/M startup at $0100");
    }
    const resultAddress = callerPlacement.runAddress +
      offset(callerAssembly, "RESULT");
    const resultTagAddress = callerPlacement.runAddress +
      offset(callerAssembly, "RTAG");
    return {
      objectBytes,
      comBytes: output.bytes.slice(0, output.usedLength),
      entryAddress: linked.entry.address,
      resultAddress,
      resultTagAddress,
      resultKind: plan.resultKind,
      runtimeBase: 0x0800,
      runtimeLength: runtime.bytes.length,
      object,
    };
  } finally {
    await Deno.remove(workRoot, { recursive: true });
  }
}
