/** Development-only adapter: ATOM assembly and portable Z80 execution under Deno. */
import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";
// @deno-types="../../atom/node_modules/@jhlagado/z80-runtime/dist/index.d.ts"
import { createZ80Runtime } from "@jhlagado/z80-runtime";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

type AssemblyLimits = { maxInstructions?: number; maxCycles?: number };
type AssembledEntry = {
  image: NonNullable<ReturnType<typeof materializeAtomGeneration>>;
  symbols: ReadonlyArray<readonly [string, number]>;
};

// Assembling the compiler or runtime image takes seconds, and the unit tests
// ask for the same entry many times.  Assemble each entry once per process and
// hand every caller its own memory, runtime and symbol map so tests stay
// isolated from one another.
const assemblyCache = new Map<string, Promise<AssembledEntry>>();

async function assembleEntry(
  entry: string,
  limits: AssemblyLimits,
): Promise<AssembledEntry> {
  const root = fileURLToPath(new URL("../", import.meta.url));
  const result = await assembleAtomProject({
    root,
    entry,
    assembler: undefined,
    target: undefined,
    // The native compiler includes the macro phase and lowerer handoff.  Its
    // assembly remains bounded, but the production image crosses the smaller
    // development guard used by the individual module fixtures.
    maxInstructions: limits.maxInstructions ?? 1_000_000_000,
    maxCycles: limits.maxCycles ?? 10_000_000_000,
    sink: undefined,
  });
  const image = materializeAtomGeneration(result.generation);
  if (!image) throw new Error("ATOM produced no image");
  const symbols = result.generation.symbols.map(
    (s: { name: string; value: number }) =>
      [s.name.toLowerCase(), s.value] as const,
  );
  return { image, symbols };
}

function cachedAssembly(entry: string, limits: AssemblyLimits) {
  const key = `${entry}\0${limits.maxInstructions ?? ""}\0${
    limits.maxCycles ?? ""
  }`;
  let pending = assemblyCache.get(key);
  if (!pending) {
    pending = assembleEntry(entry, limits);
    assemblyCache.set(key, pending);
    pending.catch(() => assemblyCache.delete(key));
  }
  return pending;
}

export async function loadAssembly(
  entry: string,
  limits: AssemblyLimits = {},
) {
  const cached = await cachedAssembly(entry, limits);
  const image = { ...cached.image, bytes: Uint8Array.from(cached.image.bytes) };
  const memory = new Uint8Array(65536);
  memory.set(image.bytes, image.base);
  const symbols = new Map<string, number>(cached.symbols);
  const runtime = createZ80Runtime({ memory, startAddress: image.base });
  function address(name: string): number {
    const found = symbols.get(name.toLowerCase());
    if (found === undefined) throw new Error(`Missing symbol ${name}`);
    return found;
  }
  return { runtime, image, symbols, address };
}

export async function assemble(entry: string) {
  const { runtime, image, symbols, address } = await loadAssembly(entry);
  const cpu = runtime.cpu, mem = runtime.hardware.memory;
  const stats = new Map<
    string,
    { calls: number; minCycles: number; maxCycles: number; stackBytes: number }
  >();
  let lowestStack = 0xf000;
  (runtime.hardware as typeof runtime.hardware & {
    memWrite: (address: number, value: number) => void;
  }).memWrite = (address, value) => {
    const scratch = address >= symbols.get("f16work")! &&
      address < symbols.get("f16wend")!;
    const stack = address >= 0xefe0 && address < 0xf000;
    if (!scratch && !stack) {
      throw new Error(`Unexpected write at ${address.toString(16)}`);
    }
    if (stack) lowestStack = Math.min(lowestStack, address);
    mem[address] = value;
  };
  function call(name: string, left: number, right = 0, tag = 0, rightTag = 0) {
    lowestStack = 0xf000;
    mem.fill((left ^ right) & 255, address("F16_WORK"), address("F16_LIM"));
    cpu.flags.C = (left ^ right) & 1;
    cpu.pc = address(name);
    cpu.sp = 0xf000;
    cpu.a = tag;
    cpu.b = rightTag;
    cpu.c = 0x5a;
    cpu.h = left >>> 8;
    cpu.l = left & 255;
    cpu.d = right >>> 8;
    cpu.e = right & 255;
    cpu.ix = 0x1357;
    cpu.iy = 0x2468;
    mem[0xf000] = 0;
    mem[0xf001] = 0xff;
    let cycles = 0, steps = 0;
    while (cpu.pc !== 0xff00) {
      if (++steps > 20000 || runtime.isHalted()) {
        throw new Error(`${name} failed to return`);
      }
      cycles += runtime.step().cycles ?? 0;
    }
    assert.equal(cpu.sp, 0xf002, `${name} stack`);
    assert.equal(cpu.ix, 0x1357, `${name} IX`);
    assert.equal(cpu.iy, 0x2468, `${name} IY`);
    const stat = stats.get(name) ??
      { calls: 0, minCycles: Infinity, maxCycles: 0, stackBytes: 0 };
    stat.calls++;
    stat.minCycles = Math.min(stat.minCycles, cycles);
    stat.maxCycles = Math.max(stat.maxCycles, cycles);
    stat.stackBytes = Math.max(stat.stackBytes, 0xf000 - lowestStack);
    stats.set(name, stat);
    return {
      bits: cpu.h * 256 + cpu.l,
      status: cpu.a,
      carry: cpu.flags.C,
      cycles,
      steps,
    };
  }
  return { call, address, stats, memory: mem, image, symbols };
}
