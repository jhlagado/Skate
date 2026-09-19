/** Measure the C1 compiler image and its explicit native storage account. */

import { loadAssembly } from "../../tests/z80.ts";

export const C1_LOAD = 0x0100;
export const C1_CORE_LIMIT = 16_384;
export const C1_ALLOCATION_LIMIT = 30_720;
export const C1_STACK_TOP = 0x8000;
export const C1_RECORD_BYTES = 128;

export interface C1Span {
  readonly name: string;
  readonly start: number;
  readonly end: number;
  readonly bytes: number;
}

export interface C1Budget {
  readonly entry: number;
  readonly imageEnd: number;
  readonly imageBytes: number;
  readonly coreLimit: number;
  readonly coreRemaining: number;
  readonly allocationLimit: number;
  readonly allocationRemaining: number;
  readonly stackTop: number;
  readonly imageToStackGap: number;
  readonly staticWorkspace: number;
  readonly workspaceRemaining: number;
  readonly writableTotal: number;
  readonly writableBucketRemaining: number;
  readonly template: C1Span;
  readonly spans: readonly C1Span[];
  readonly recordBytes: number;
  readonly sourceRecords: number;
  readonly objectRecords: number;
  readonly comRecords: number;
}

function span(
  address: (label: string) => number,
  name: string,
  startLabel: string,
  end: number | string,
): C1Span {
  const start = address(startLabel);
  const finish = typeof end === "number" ? end : address(end);
  if (finish < start) throw new RangeError(`${name} span is reversed`);
  return { name, start, end: finish, bytes: finish - start };
}

function records(bytes: number): number {
  return Math.ceil(bytes / C1_RECORD_BYTES);
}

/**
 * Build the conservative C1 account from one ATOM image.
 *
 * The image is charged in full against the core gate.  The named writable
 * spans are reported separately so later phases can prove overlays instead of
 * hiding static storage inside a code-only number.
 */
export function measureC1Budget(
  image: { end: number },
  address: (label: string) => number,
  generated: { objectBytes: number; comBytes: number; sourceBytes: number },
): C1Budget {
  const entry = address("ARMAIN");
  if (entry !== C1_LOAD) {
    throw new RangeError(`C1 entry is $${entry.toString(16)}, expected $0100`);
  }
  if (image.end <= entry || image.end >= C1_STACK_TOP) {
    throw new RangeError("C1 image overlaps its guarded native stack");
  }
  const template = span(
    address,
    "generated NOBJ template",
    "AROBJ",
    "AROBJEND",
  );
  const spans = [
    span(address, "compiler state and symbol pools", "ARCODE", "AROKTXT"),
    span(address, "CP/M source adapter", "CSWORK", "CSWEND"),
    span(address, "CP/M transport", "CTREERR", address("CTWBUF") + 128),
    span(address, "lexer workspace", "LEXWORK", "LEXWEND"),
    span(address, "decimal workspace", "DWORK", "DWEND"),
    span(address, "interner workspace", "IWORK", "IWEND"),
    span(address, "reader workspace", "RWORK", "RWEND"),
    span(address, "binary16 workspace", "F16WORK", "F16WEND"),
    span(address, "numeric workspace", "NWORK", "NWEND"),
    span(
      address,
      "publication flags and recovery FCB",
      ".BN",
      address(".F2") + 36,
    ),
  ];
  const staticWorkspace = spans.reduce((total, item) => total + item.bytes, 0);
  const writableTotal = staticWorkspace + template.bytes;
  return {
    entry,
    imageEnd: image.end,
    imageBytes: image.end - entry,
    coreLimit: C1_CORE_LIMIT,
    coreRemaining: C1_CORE_LIMIT - (image.end - entry),
    allocationLimit: C1_ALLOCATION_LIMIT,
    allocationRemaining: C1_ALLOCATION_LIMIT - (image.end - entry),
    stackTop: C1_STACK_TOP,
    imageToStackGap: C1_STACK_TOP - image.end,
    staticWorkspace,
    workspaceRemaining: 4096 - staticWorkspace,
    writableTotal,
    writableBucketRemaining: 4096 - writableTotal,
    template,
    spans,
    recordBytes: C1_RECORD_BYTES,
    sourceRecords: records(generated.sourceBytes),
    objectRecords: records(generated.objectBytes),
    comRecords: records(generated.comBytes),
  };
}

const hex = (value: number) =>
  `$${value.toString(16).toUpperCase().padStart(4, "0")}`;

export function renderC1Budget(budget: C1Budget): string {
  return [
    "# C1 compiler budget",
    "",
    `Image: ${hex(budget.entry)}..${
      hex(budget.imageEnd)
    } exclusive (${budget.imageBytes} B)`,
    `Core gate: ${budget.coreLimit} B; remaining ${budget.coreRemaining} B`,
    `Initial-allocation gate: ${budget.allocationLimit} B; remaining ${budget.allocationRemaining} B`,
    `Native stack: top ${
      hex(budget.stackTop)
    }; image gap ${budget.imageToStackGap} B`,
    `Generated NOBJ template: ${budget.template.bytes} B (mutable output staging charged to the core image)`,
    `Named writable workspace: ${budget.staticWorkspace} B; 4,096-B general bucket remaining ${budget.workspaceRemaining} B`,
    `All fixed writable bytes including staging: ${budget.writableTotal} B; bucket reconciliation ${budget.writableBucketRemaining} B`,
    `CP/M records: ${budget.recordBytes} B; source ${budget.sourceRecords}, NOBJ ${budget.objectRecords}, COM ${budget.comRecords}`,
    "",
    "| Span | Start | End | Bytes |",
    "| --- | ---: | ---: | ---: |",
    `| ${budget.template.name} | ${hex(budget.template.start)} | ${
      hex(budget.template.end)
    } | ${budget.template.bytes} |`,
    ...budget.spans.map((item) =>
      `| ${item.name} | ${hex(item.start)} | ${hex(item.end)} | ${item.bytes} |`
    ),
    "",
  ].join("\n");
}

if (import.meta.main) {
  const assembled = await loadAssembly("src/compiler/arithmetic-compiler.asm");
  const budget = measureC1Budget(assembled.image, assembled.address, {
    sourceBytes: 10,
    objectBytes: assembled.address("AROBLEN"),
    comBytes: assembled.address("ARIMGLN"),
  });
  console.log(renderC1Budget(budget));
}
