/**
 * Host-side machine for the native streamed-NOBJ experiment.
 *
 * The BDOS callback is deliberately the only disk oracle.  It implements the
 * record transfers used by the writer and RPATCH, destroys scratch registers
 * at every boundary, and rejects writes outside the writer's owned storage.
 */
import assert from "node:assert/strict";
import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";
import { createZ80Runtime } from "@jhlagado/debug80-runtime";
import { fileURLToPath } from "node:url";

export interface FailureInjection {
  /** One-based transfer number across all sequential reads from this run. */
  readonly sequentialRead?: number;
  /** One-based transfer number across all sequential writes from this run. */
  readonly sequentialWrite?: number;
  /** One-based transfer number across all random reads from this run. */
  readonly randomRead?: number;
  /** One-based transfer number across all random writes from this run. */
  readonly randomWrite?: number;
}

export interface Transfer {
  readonly operation: "read" | "write";
  readonly mode: "sequential" | "random";
  readonly file: "stage" | "spool";
  readonly record: number;
}

export interface CallResult {
  readonly status: number;
  readonly carry: number;
  readonly steps: number;
  readonly cycles: number;
}

const ROOT = fileURLToPath(new URL("../../../../", import.meta.url));
const ENTRY = "docs/c0/experiments/stream-writer/stream-writer.asm";
export const STACK = 0xf000;
export const RETURN = 0xff00;
export const STAGE_PREFIX = 0x8000;
export const SPOOL_PREFIX = 0x8040;
export const PATCH_SOURCE = 0x9000;
const STAGE_BYTES = 0x10000;
const SPOOL_BYTES = 0x2000;

const word = (memory: Uint8Array, address: number): number =>
  memory[address]! | memory[address + 1]! << 8;

const setRecord = (memory: Uint8Array, fcb: number, record: number): void => {
  memory[fcb + 33] = record & 255;
  memory[fcb + 34] = record >>> 8 & 255;
  memory[fcb + 35] = record >>> 16 & 255;
};

const sourcePrefix = (tag: number): Uint8Array => {
  const prefix = new Uint8Array(36);
  for (let index = 0; index < 12; index++) prefix[index] = tag + index;
  return prefix;
};

export async function createStreamMachine() {
  const result = await assembleAtomProject({
    root: ROOT,
    entry: ENTRY,
    assembler: undefined,
    target: undefined,
    maxInstructions: 1_000_000_000,
    maxCycles: 10_000_000_000,
    sink: undefined,
  });
  const image = materializeAtomGeneration(result.generation);
  if (!image) throw new Error("ATOM produced no image");
  const symbols = new Map<string, number>(result.generation.symbols.map(
    (
      symbol: { name: string; value: number },
    ) => [symbol.name.toLowerCase(), symbol.value],
  ));
  const address = (name: string): number => {
    const value = symbols.get(name.toLowerCase());
    if (value === undefined) throw new Error(`missing symbol ${name}`);
    return value;
  };

  const initialMemory = new Uint8Array(65536);
  initialMemory.set(image.bytes, image.base);
  initialMemory[5] = 0xc9;
  const runtime = createZ80Runtime({
    memory: initialMemory,
    startAddress: address("SWINIT"),
  });
  const memory = runtime.hardware.memory;
  const cpu = runtime.cpu;
  const hardware = runtime.hardware as typeof runtime.hardware & {
    memWrite: (address: number, value: number) => void;
  };
  const stage = new Uint8Array(STAGE_BYTES);
  const spool = new Uint8Array(SPOOL_BYTES);
  let dma = 0;
  let stackLowWater = STACK;
  let injection: FailureInjection = {};
  let sequentialReads = 0;
  let sequentialWrites = 0;
  let randomReads = 0;
  let randomWrites = 0;
  let dmaSelections = 0;
  let bdosCalls = 0;
  const transfers: Transfer[] = [];

  const inRange = (value: number, start: number, length: number): boolean =>
    value >= start && value < start + length;
  const writerWork = (value: number): boolean =>
    inRange(value, address("RPWORK"), address("RPWEND") - address("RPWORK")) ||
    inRange(value, address("SWWORK"), address("SWWEND") - address("SWWORK"));
  const stackWrite = (value: number): boolean =>
    value >= STACK - 1024 && value < STACK;

  hardware.memWrite = (location: number, value: number): void => {
    assert.ok(
      writerWork(location) || stackWrite(location),
      `native write escaped owned storage at ${location.toString(16)}`,
    );
    if (stackWrite(location)) stackLowWater = Math.min(stackLowWater, location);
    memory[location] = value & 255;
  };

  const diskFor = (
    fcb: number,
  ): { disk: Uint8Array; file: "stage" | "spool" } => {
    if (fcb === address("RPFCB")) return { disk: stage, file: "stage" };
    if (fcb === address("SWPFCB")) return { disk: spool, file: "spool" };
    throw new Error(`BDOS FCB outside native ownership: ${fcb.toString(16)}`);
  };

  const resetCounters = (): void => {
    dma = 0;
    stackLowWater = STACK;
    sequentialReads = 0;
    sequentialWrites = 0;
    randomReads = 0;
    randomWrites = 0;
    dmaSelections = 0;
    bdosCalls = 0;
    transfers.length = 0;
  };

  const bdos = (): void => {
    bdosCalls++;
    const fn = cpu.c;
    const fcb = cpu.d * 256 + cpu.e;
    let status = 0;
    if (fn === 26) {
      dmaSelections++;
      dma = fcb;
      assert.ok(
        dma === address("RPBUFFER") || dma === address("SWSPBUF"),
        `DMA outside native buffers: ${dma.toString(16)}`,
      );
    } else {
      const { disk, file } = diskFor(fcb);
      const record = memory[fcb + 33]! +
        (memory[fcb + 34]! << 8) +
        (memory[fcb + 35]! << 16);
      const offset = record * 128;
      assert.ok(
        offset + 128 <= disk.length,
        "BDOS transfer outside disk oracle",
      );
      if (fn === 20 || fn === 21) {
        const mode = "sequential" as const;
        if (fn === 20) {
          sequentialReads++;
          transfers.push({ operation: "read", mode, file, record });
          if (sequentialReads === injection.sequentialRead) status = 6;
          else {
            for (let index = 0; index < 128; index++) {
              hardware.memWrite(dma + index, disk[offset + index]!);
            }
            setRecord(memory, fcb, record + 1);
          }
        } else {
          sequentialWrites++;
          transfers.push({ operation: "write", mode, file, record });
          if (sequentialWrites === injection.sequentialWrite) status = 2;
          else {
            disk.set(memory.subarray(dma, dma + 128), offset);
            setRecord(memory, fcb, record + 1);
          }
        }
      } else if (fn === 33 || fn === 34) {
        const mode = "random" as const;
        if (fn === 33) {
          randomReads++;
          transfers.push({ operation: "read", mode, file, record });
          if (randomReads === injection.randomRead) status = 6;
          else {
            assert.equal(file, "stage");
            for (let index = 0; index < 128; index++) {
              hardware.memWrite(dma + index, disk[offset + index]!);
            }
          }
        } else {
          randomWrites++;
          transfers.push({ operation: "write", mode, file, record });
          if (randomWrites === injection.randomWrite) status = 2;
          else {
            assert.equal(file, "stage");
            disk.set(memory.subarray(dma, dma + 128), offset);
          }
        }
      } else {
        throw new Error(`unexpected BDOS function ${fn}`);
      }
    }
    cpu.a = status;
    // Every boundary is hostile to scratch registers.  IX/IY are deliberately
    // destroyed too; SWBDOS and RPATCH must preserve those around the call.
    cpu.b =
      cpu.c =
      cpu.d =
      cpu.e =
      cpu.h =
      cpu.l =
        0xcc;
    cpu.ix = cpu.iy = 0xdddd;
    cpu.flags.C = 1;
  };

  const call = (name: string, options: {
    readonly a?: number;
    readonly b?: number;
    readonly c?: number;
    readonly hl?: number;
    readonly de?: number;
    readonly maxSteps?: number;
  } = {}): CallResult => {
    const maxSteps = options.maxSteps ?? 20_000_000;
    memory[STACK] = RETURN & 255;
    memory[STACK + 1] = RETURN >>> 8;
    cpu.pc = address(name);
    cpu.sp = STACK;
    cpu.a = options.a ?? 0;
    cpu.b = options.b ?? 0;
    cpu.c = options.c ?? 0x5a;
    cpu.h = (options.hl ?? 0) >>> 8;
    cpu.l = (options.hl ?? 0) & 255;
    cpu.d = (options.de ?? 0) >>> 8;
    cpu.e = (options.de ?? 0) & 255;
    cpu.ix = 0x1357;
    cpu.iy = 0x2468;
    cpu.flags.C = 1;
    let steps = 0;
    let cycles = 0;
    while (cpu.pc !== RETURN) {
      assert.ok(++steps < maxSteps, `${name} exceeded step budget`);
      assert.ok(!runtime.isHalted(), `${name} halted`);
      if (cpu.pc === 5) bdos();
      cycles += runtime.step().cycles ?? 0;
    }
    assert.equal(cpu.sp, STACK + 2, `${name} leaves SP balanced`);
    assert.equal(cpu.ix, 0x1357, `${name} preserves IX`);
    assert.equal(cpu.iy, 0x2468, `${name} preserves IY`);
    return { status: cpu.a, carry: cpu.flags.C ? 1 : 0, steps, cycles };
  };

  const reset = (nextInjection: FailureInjection = {}): void => {
    memory.fill(0);
    memory.set(image.bytes, image.base);
    memory[5] = 0xc9;
    memory.set(sourcePrefix(0x21), STAGE_PREFIX);
    memory.set(sourcePrefix(0x61), SPOOL_PREFIX);
    stage.fill(0x1a);
    spool.fill(0x1a);
    injection = nextInjection;
    resetCounters();
  };

  const writeSource = (slot: number, bytes: Uint8Array): number => {
    const location = PATCH_SOURCE + slot * 8;
    memory.set(bytes, location);
    return location;
  };

  const logicalStage = (): Uint8Array =>
    stage.slice(0, word(memory, address("SWLEN")));
  const stats = (): Readonly<Record<string, number>> => ({
    sequentialReads,
    sequentialWrites,
    randomReads,
    randomWrites,
    dmaSelections,
    bdosCalls,
    stackBytes: STACK - stackLowWater,
    stageLength: word(memory, address("SWLEN")),
    imageBytes: word(memory, address("SWTOTAL")),
    spoolLength: word(memory, address("SWSLEN")),
    preCommitRecordCount: word(memory, address("SWRECS")),
    recordCount: word(memory, address("SWCOUNT")),
  });

  reset();
  return {
    address,
    call,
    cpu,
    image,
    logicalStage,
    memory,
    reset,
    runtime,
    stats,
    stage,
    spool,
    transfers,
    writeSource,
    codeBytes: address("RPEND") - address("RPATCH"),
    helperWorkspaceBytes: address("RPWEND") - address("RPWORK"),
    writerWorkspaceBytes: address("SWWEND") - address("SWWORK"),
  };
}
