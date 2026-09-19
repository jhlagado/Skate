/** Native ATOM/Debug80 execution harness for both parser candidates. */
import assert from "node:assert/strict";
import { loadAssembly } from "../../../../tests/z80.ts";

export type Candidate = "handwritten" | "table";

export interface RunOptions {
  readonly outputBase?: number;
  readonly outputCapacity?: number;
  readonly discardActions?: boolean;
  readonly injectSinkFailure?: boolean;
  readonly maxSteps?: number;
}

export interface NativeResult {
  readonly candidate: Candidate;
  readonly ok: boolean;
  readonly status: number;
  readonly carry: number;
  readonly trace: readonly number[];
  readonly consumed: number;
  readonly tokenFetches: number;
  readonly lookaheadFetches: number;
  readonly currentIndex: number;
  readonly outputUsed: number;
  readonly outputWrites: number;
  readonly steps: number;
  readonly cycles: number;
  readonly stackBytes: number;
  readonly predictionBytes: number;
  readonly nativeWrites: number;
  readonly writeHash: number;
  readonly returnPc: number;
  readonly finalSp: number;
  readonly ix: number;
  readonly iy: number;
  readonly canariesIntact: boolean;
  readonly inputReads: number;
}

const INPUT_BASE = 0x6000;
const INPUT_GUARD = 4;
const DEFAULT_OUTPUT_BASE = 0x8000;
const STACK_LOW = 0xd800;
const STACK_TOP = 0xe000;
const RETURN_PC = 0xff00;
const IX_SENTINEL = 0x1357;
const IY_SENTINEL = 0x2468;
const INPUT_LIMIT = 0x1000;

function word(memory: Uint8Array, address: number): number {
  return memory[address]! | memory[address + 1]! << 8;
}

function putWord(memory: Uint8Array, address: number, value: number): void {
  memory[address] = value & 255;
  memory[address + 1] = value >>> 8;
}

function sameBytes(
  memory: Uint8Array,
  start: number,
  end: number,
  value: number,
): boolean {
  for (let address = start; address < end; address++) {
    if (memory[address] !== value) return false;
  }
  return true;
}

function range(start: number, end: number): readonly [number, number] {
  return [start, Math.min(end, 0x10000)];
}

export class ParserMachine {
  readonly candidate: Candidate;
  readonly memory: Uint8Array;
  readonly runtime: Awaited<ReturnType<typeof loadAssembly>>["runtime"];
  readonly address: (name: string) => number;
  readonly imageBytes: number;

  private constructor(
    candidate: Candidate,
    loaded: Awaited<ReturnType<typeof loadAssembly>>,
  ) {
    this.candidate = candidate;
    this.memory = loaded.runtime.hardware.memory;
    this.runtime = loaded.runtime;
    this.address = loaded.address;
    this.imageBytes = loaded.image.bytes.length;
  }

  static async open(
    candidate: Candidate,
    entry = `docs/c0/experiments/parser/${candidate}.asm`,
  ): Promise<ParserMachine> {
    const loaded = await loadAssembly(entry);
    return new ParserMachine(candidate, loaded);
  }

  symbol(name: string): number {
    return this.address(name);
  }

  account(): {
    readonly candidateCode: number;
    readonly tableBytes: number;
    readonly candidateImmutable: number;
    readonly candidateWorkspace: number;
    readonly explicitStack: number;
    readonly commonCodeAndImmutable: number;
    readonly commonWorkspace: number;
  } {
    const candidateStart = this.symbol(
      this.candidate === "handwritten" ? "HSTART" : "TSTART",
    );
    const tableBytes = this.candidate === "table"
      ? this.symbol("TCODEEND") - this.symbol("TTABST")
      : 0;
    const candidateImmutable = this.candidate === "table"
      ? this.symbol("TCODEEND") - this.symbol("TSTART")
      : this.symbol("HCODEEND") - this.symbol("HSTART");
    const workspaceStart = this.symbol(
      this.candidate === "handwritten" ? "HWORK" : "TWORK",
    );
    const workspaceEnd = this.symbol(
      this.candidate === "handwritten" ? "HWEND" : "TWEND",
    );
    return {
      candidateCode:
        (this.candidate === "handwritten"
          ? this.symbol("HCODEEND")
          : this.symbol("TTABST")) - candidateStart,
      tableBytes,
      candidateImmutable,
      candidateWorkspace: workspaceEnd - workspaceStart,
      explicitStack: this.candidate === "table" ? 256 : 0,
      commonCodeAndImmutable: this.symbol("CCODEEND") - this.symbol("CSTART"),
      commonWorkspace: this.symbol("ADWEND") - this.symbol("ADWORK") +
        this.symbol("SKWEND") - this.symbol("SKWORK"),
    };
  }

  run(tokens: readonly number[], options: RunOptions = {}): NativeResult {
    assert(
      tokens.length <= INPUT_LIMIT,
      "fixture input exceeds bounded region",
    );
    assert(
      tokens.every((token) =>
        Number.isInteger(token) && token >= 0 && token <= 255
      ),
    );
    const outputBase = options.outputBase ?? DEFAULT_OUTPUT_BASE;
    const outputCapacity = options.outputCapacity ?? 0x1800;
    assert(outputBase >= 0x2000 && outputBase <= 0xffff);
    assert(outputCapacity >= 0 && outputCapacity <= 0x1c00);
    assert(outputBase + outputCapacity <= 0xffff);
    assert(
      outputBase >= INPUT_BASE + INPUT_LIMIT ||
        outputBase + outputCapacity <= INPUT_BASE,
    );
    const memory = this.memory;
    const address = this.address;
    const candidateWorkspace = this.candidate === "handwritten"
      ? range(address("HWORK"), address("HWEND"))
      : range(address("TWORK"), address("TWEND"));
    const writable = [
      range(address("ADWORK"), address("ADWEND")),
      range(address("SKWORK"), address("SKWEND")),
      candidateWorkspace,
      range(outputBase, outputBase + outputCapacity),
      range(STACK_LOW, STACK_TOP),
    ];
    const overlaps = (
      left: readonly [number, number],
      right: readonly [number, number],
    ) => left[0] < right[1] && right[0] < left[1];
    const outputRange = range(outputBase, outputBase + outputCapacity);
    const outputCanaryRanges = [
      range(outputBase - INPUT_GUARD, outputBase),
      range(
        outputBase + outputCapacity,
        outputBase + outputCapacity + INPUT_GUARD,
      ),
    ];
    const inputCanaryRanges = [
      range(INPUT_BASE - INPUT_GUARD, INPUT_BASE),
      range(
        INPUT_BASE + tokens.length,
        INPUT_BASE + tokens.length + INPUT_GUARD,
      ),
    ];
    const callerProtectedRanges = [
      range(STACK_LOW - INPUT_GUARD, STACK_LOW),
      range(STACK_TOP, STACK_TOP + 2),
      range(STACK_TOP + 2, STACK_TOP + 2 + INPUT_GUARD),
    ];
    const protectedRanges = [
      range(0, this.imageBytes),
      range(INPUT_BASE, INPUT_BASE + INPUT_LIMIT),
      ...inputCanaryRanges,
      range(address("ADWORK"), address("ADWEND")),
      range(address("SKWORK"), address("SKWEND")),
      candidateWorkspace,
      range(STACK_LOW, STACK_TOP),
      ...callerProtectedRanges,
    ];
    assert(
      [...protectedRanges, ...outputCanaryRanges].every((protectedRange) =>
        !overlaps(outputRange, protectedRange)
      ) &&
        outputCanaryRanges.every((canaryRange) =>
          protectedRanges.every((protectedRange) =>
            !overlaps(canaryRange, protectedRange)
          )
        ),
      "output or its canaries overlap code, state, input or caller stack",
    );
    const canaryRegions = [
      ...outputCanaryRanges,
      ...inputCanaryRanges,
      range(address("ADGUARD"), address("ADWORK")),
      range(address("ADWEND"), address("ADTAIL") + 4),
      range(address("SKGUARD"), address("SKWORK")),
      range(address("SKWEND"), address("SKTAIL") + 4),
      this.candidate === "handwritten"
        ? range(address("HGUARD"), address("HWORK"))
        : range(address("TGUARD"), address("TWORK")),
      this.candidate === "handwritten"
        ? range(address("HWEND"), address("HTAIL") + 4)
        : range(address("TWEND"), address("TTAIL") + 4),
      ...callerProtectedRanges.filter(([start, end]) =>
        !(start === STACK_TOP && end === STACK_TOP + 2)
      ),
    ];
    const canaryValue = 0xa5;
    memory.fill(0xcc, INPUT_BASE, INPUT_BASE + INPUT_LIMIT);
    memory.set(tokens, INPUT_BASE);
    for (const [start, end] of canaryRegions) {
      memory.fill(canaryValue, start, end);
    }
    memory.fill(canaryValue, INPUT_BASE - INPUT_GUARD, INPUT_BASE);
    memory.fill(
      canaryValue,
      INPUT_BASE + tokens.length,
      INPUT_BASE + tokens.length + INPUT_GUARD,
    );
    memory.fill(0x5a, outputBase, outputBase + outputCapacity);
    memory.fill(0x3c, STACK_LOW, STACK_TOP);

    putWord(memory, address("ADBASE"), INPUT_BASE);
    putWord(memory, address("ADLIM"), INPUT_BASE + tokens.length);
    putWord(memory, address("SKBASE"), outputBase);
    putWord(memory, address("SKLIM"), outputBase + outputCapacity);
    memory[address("SKINJ")] = options.injectSinkFailure ? 1 : 0;
    memory[address("SKDISC")] = options.discardActions ? 1 : 0;
    putWord(memory, STACK_TOP, RETURN_PC);
    memory[STACK_TOP + 2] = canaryValue;
    memory[STACK_TOP + 3] = canaryValue;
    memory[STACK_TOP + 4] = canaryValue;
    memory[STACK_TOP + 5] = canaryValue;

    let lowestStack = STACK_TOP;
    let nativeWrites = 0;
    let outputWrites = 0;
    let writeHash = 0;
    const inputReads: number[] = [];
    (this.runtime.hardware as typeof this.runtime.hardware & {
      memRead: (address: number) => number;
    }).memRead = (readAddress) => {
      if (readAddress >= INPUT_BASE && readAddress < INPUT_BASE + INPUT_LIMIT) {
        assert(
          readAddress < INPUT_BASE + tokens.length,
          `native input read crossed exclusive extent at ${
            readAddress.toString(16)
          }`,
        );
        inputReads.push(readAddress);
      }
      return memory[readAddress]!;
    };
    (this.runtime.hardware as typeof this.runtime.hardware & {
      memWrite: (address: number, value: number) => void;
    }).memWrite = (writeAddress, value) => {
      const inside = writable.some(([start, end]) =>
        writeAddress >= start && writeAddress < end
      );
      assert(
        inside,
        `native write escaped guarded regions at ${writeAddress.toString(16)}`,
      );
      nativeWrites++;
      if (
        writeAddress >= outputBase && writeAddress < outputBase + outputCapacity
      ) {
        outputWrites++;
      }
      writeHash = (Math.imul(writeHash ^ writeAddress, 16777619) ^ value) >>> 0;
      if (writeAddress >= STACK_LOW && writeAddress < STACK_TOP) {
        lowestStack = Math.min(lowestStack, writeAddress);
      }
      memory[writeAddress] = value & 255;
    };

    const cpu = this.runtime.cpu;
    cpu.pc = address("PPARSE");
    cpu.sp = STACK_TOP;
    cpu.ix = IX_SENTINEL;
    cpu.iy = IY_SENTINEL;
    cpu.a = 0x5a;
    cpu.b = 0xa5;
    cpu.c = 0x39;
    cpu.d = 0x73;
    cpu.e = 0x16;
    cpu.h = 0x42;
    cpu.l = 0x81;
    cpu.flags.C = 1;
    let steps = 0, cycles = 0;
    const maxSteps = options.maxSteps ?? 20_000_000;
    while (cpu.pc !== RETURN_PC) {
      assert(
        ++steps <= maxSteps,
        `${this.candidate} parser exceeded step limit at ${
          cpu.pc.toString(16)
        }`,
      );
      assert(
        !this.runtime.isHalted(),
        `${this.candidate} parser halted at ${cpu.pc.toString(16)}`,
      );
      cycles += this.runtime.step().cycles ?? 0;
    }

    assert.equal(
      word(memory, STACK_TOP),
      RETURN_PC,
      "caller return PC changed",
    );
    const brokenCanaries = canaryRegions.filter(([start, end]) =>
      !sameBytes(memory, start, end, canaryValue)
    );
    const canariesIntact = brokenCanaries.length === 0;
    assert(
      canariesIntact,
      `${this.candidate} canary changed: ${
        brokenCanaries.map(([s, e]) => `${s.toString(16)}-${e.toString(16)}`)
          .join(",")
      }`,
    );
    assert.equal(cpu.sp, STACK_TOP + 2, "stack pointer not restored");
    assert.equal(cpu.ix, IX_SENTINEL, "IX not preserved");
    assert.equal(cpu.iy, IY_SENTINEL, "IY not preserved");
    assert.equal(inputReads.length, word(memory, address("ADFETCH")));
    inputReads.forEach((readAddress, index) => {
      assert.equal(
        readAddress,
        INPUT_BASE + index,
        "input token fetched out of order",
      );
    });
    const used = word(memory, address("SKUSED"));
    const trace = options.discardActions
      ? []
      : [...memory.slice(outputBase, outputBase + used)];
    const predictionBytes = this.candidate === "table"
      ? word(memory, address("TMAX"))
      : 0;
    return {
      candidate: this.candidate,
      ok: cpu.flags.C === 0 && cpu.a === 0,
      status: cpu.a,
      carry: cpu.flags.C,
      trace,
      consumed: word(memory, address("ADCONS")),
      tokenFetches: word(memory, address("ADFETCH")),
      lookaheadFetches: word(memory, address("ADLOOK")),
      currentIndex: word(memory, address("ADTOKIX")),
      outputUsed: used,
      outputWrites,
      steps,
      cycles,
      stackBytes: STACK_TOP - lowestStack,
      predictionBytes,
      nativeWrites,
      writeHash,
      inputReads: inputReads.length,
      returnPc: word(memory, STACK_TOP),
      finalSp: cpu.sp,
      ix: cpu.ix,
      iy: cpu.iy,
      canariesIntact,
    };
  }
}
