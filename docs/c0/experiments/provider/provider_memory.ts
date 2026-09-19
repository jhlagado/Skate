import assert from "node:assert/strict";
// @deno-types="../../../../../atom/node_modules/@jhlagado/debug80-runtime/dist/index.d.ts"
import { createZ80Runtime } from "@jhlagado/debug80-runtime";

export interface LinkedRegionImage {
  readonly base: number;
  readonly bytes: Uint8Array;
}

export interface WritableSpan {
  readonly name: string;
  readonly start: number;
  readonly end: number;
}

export interface ObservedRun {
  readonly cpu: ReturnType<typeof createZ80Runtime>["cpu"];
  readonly memory: Uint8Array;
  readonly steps: number;
  readonly writeCount: number;
  readonly violations: readonly string[];
  readonly writesBySpan: ReadonlyMap<string, number>;
  readonly stackWrites: number;
  readonly stackLowWater: number;
  readonly canariesIntact: boolean;
}

interface Canary {
  readonly start: number;
  readonly end: number;
  readonly value: number;
}

function spanFor(
  spans: readonly WritableSpan[],
  address: number,
): WritableSpan | undefined {
  return spans.find(({ start, end }) => address >= start && address < end);
}

export function runObserved(
  region: LinkedRegionImage,
  options: {
    readonly entry: number;
    readonly left: number;
    readonly right: number;
    readonly stackLow: number;
    readonly stackTop: number;
    readonly allowedSpans: readonly WritableSpan[];
  },
): ObservedRun {
  const memory = new Uint8Array(0x10000);
  memory.set(region.bytes, region.base);
  const machine = createZ80Runtime({ memory, startAddress: options.entry });
  const { cpu } = machine;
  const hardware = machine.hardware as typeof machine.hardware & {
    memWrite?: (address: number, value: number) => void;
  };
  const canaries: readonly Canary[] = [
    {
      start: options.stackLow - 16,
      end: options.stackLow,
      value: 0xa5,
    },
    {
      start: options.stackTop,
      end: options.stackTop + 16,
      value: 0x5a,
    },
  ];
  for (const canary of canaries) {
    hardware.memory.fill(canary.value, canary.start, canary.end);
  }

  const writable = [
    ...options.allowedSpans,
    { name: "guarded stack", start: options.stackLow, end: options.stackTop },
  ];
  const violations: string[] = [];
  const writesBySpan = new Map<string, number>();
  let writeCount = 0;
  let stackWrites = 0;
  let stackLowWater = options.stackTop;
  hardware.memWrite = (address, value) => {
    const masked = address & 0xffff;
    const span = spanFor(writable, masked);
    writeCount += 1;
    if (span === undefined) {
      violations.push(
        "write $" + masked.toString(16) + " at PC $" + cpu.pc.toString(16),
      );
    } else {
      writesBySpan.set(span.name, (writesBySpan.get(span.name) ?? 0) + 1);
    }
    if (masked >= options.stackLow && masked < options.stackTop) {
      stackWrites += 1;
      stackLowWater = Math.min(stackLowWater, masked);
    }
    hardware.memory[masked] = value & 0xff;
  };

  cpu.pc = options.entry;
  cpu.sp = options.stackTop;
  cpu.a = 3;
  cpu.b = 3;
  cpu.h = options.left >>> 8;
  cpu.l = options.left & 255;
  cpu.d = options.right >>> 8;
  cpu.e = options.right & 255;
  cpu.ix = 0x1357;
  cpu.iy = 0x2468;
  let steps = 0;
  while (cpu.pc !== 0xff00) {
    assert.ok(++steps < 1_000_000, "prepared provider did not terminate");
    assert.ok(!machine.isHalted(), "prepared provider halted");
    machine.step();
  }

  const canariesIntact = canaries.every((canary) => {
    for (let address = canary.start; address < canary.end; address += 1) {
      if (hardware.memory[address] !== canary.value) return false;
    }
    return true;
  });
  return {
    cpu,
    memory: machine.hardware.memory,
    steps,
    writeCount,
    violations,
    writesBySpan,
    stackWrites,
    stackLowWater,
    canariesIntact,
  };
}
