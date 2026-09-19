/** Measure the unoptimised M10/M12 image and runtime path for M13 baselines. */
import { createZ80Runtime } from "@jhlagado/debug80-runtime";
import { compileM10, type M10CompileResult } from "./m7-compiler.ts";

export interface M13Measurement {
  readonly program: string;
  readonly sourceBytes: number;
  readonly callerImageBytes: number;
  readonly callerCodeBytes: number;
  readonly runtimeImageBytes: number;
  readonly entryVectorBytes: number;
  readonly alignmentBytes: number;
  readonly comBytes: number;
  readonly heapCells: number;
  readonly heapBytes: number;
  readonly bssBase: number;
  readonly bssBytes: number;
  readonly bssEnd: number;
  readonly rootBase: number;
  readonly rootBytes: number;
  readonly activationBase: number;
  readonly activationBytes: number;
  readonly runtimeWorkspaceBytes: number;
  readonly bitmapBase: number;
  readonly bitmapBytes: number;
  readonly heapBase: number;
  readonly heapWrites: number;
  readonly steps: number;
  readonly cycles: number;
  readonly resultTag: number;
  readonly resultPayload: number;
  readonly runtimeErrorCode: number | null;
}

interface MeasureOptions {
  readonly maxSteps?: number;
  readonly input?: readonly number[];
}

const DEFAULT_PROGRAMS = [
  "make-adder.sk8",
  "shared-counter.sk8",
  "mutual-tail.sk8",
  "root.sk8",
] as const;

function wordAt(memory: Uint8Array, address: number): number {
  return memory[address]! | (memory[address + 1]! << 8);
}

function heapBase(compiled: M10CompileResult): number {
  return compiled.heapBaseAddress;
}

/** Execute one compiled image while counting Z80 cycles and heap writes. */
export function measureCompiled(
  program: string,
  compiled: M10CompileResult,
  options: MeasureOptions = {},
): M13Measurement {
  const memory = new Uint8Array(0x10000);
  memory.set(compiled.comBytes, compiled.entryAddress);
  memory.set([0xc3, 0x06, 0xf0], 5);
  const machine = createZ80Runtime({
    memory,
    startAddress: compiled.entryAddress,
  });
  const { cpu } = machine;
  const machineMemory = machine.hardware.memory;
  const heapStart = heapBase(compiled);
  const heapEnd = heapStart + compiled.heapCells * 4;
  let heapWrites = 0;
  const hardware = machine.hardware as typeof machine.hardware & {
    memWrite: (address: number, value: number) => void;
  };
  hardware.memWrite = (address, value) => {
    if (address >= heapStart && address < heapEnd) heapWrites++;
    machineMemory[address] = value;
  };

  cpu.pc = compiled.entryAddress;
  cpu.sp = compiled.stackTopAddress;
  const input = [...(options.input ?? [])];
  const maxSteps = options.maxSteps ?? 1_000_000;
  let runtimeErrorCode: number | null = null;
  let steps = 0;
  let cycles = 0;
  while (cpu.pc !== 0xff00) {
    if (++steps > maxSteps) {
      throw new Error(
        `${program} exceeded ${maxSteps} steps at PC=$${cpu.pc.toString(16)}`,
      );
    }
    if (machine.isHalted()) throw new Error(`${program} halted`);
    if (cpu.pc === compiled.runtimeErrorAddress) runtimeErrorCode = cpu.a;
    if (cpu.pc !== 5) {
      cycles += machine.step().cycles ?? 0;
      continue;
    }
    if (cpu.c === 0) {
      cpu.pc = 0xff00;
      continue;
    }
    if (cpu.c === 1) {
      cpu.a = input.shift() ?? 26;
    } else if (cpu.c === 2) {
      // The baseline is concerned with execution cost; output is discarded.
    } else if (cpu.c === 9) {
      let address = cpu.d * 256 + cpu.e;
      let length = 0;
      while (machineMemory[address] !== 0x24) {
        address = (address + 1) & 0xffff;
        if (++length >= 256) {
          throw new Error(`${program} emitted an unterminated BDOS string`);
        }
      }
    } else {
      throw new Error(
        `${program} requested unsupported BDOS function ${cpu.c}`,
      );
    }
    const returnAddress = wordAt(machineMemory, cpu.sp);
    cpu.sp += 2;
    cpu.pc = returnAddress;
  }

  if (runtimeErrorCode !== null) {
    throw new Error(`${program} reached runtime error ${runtimeErrorCode}`);
  }

  return {
    program,
    sourceBytes: 0,
    callerImageBytes: compiled.callerImageBytes,
    callerCodeBytes: compiled.callerCodeBytes,
    runtimeImageBytes: compiled.runtimeLength,
    entryVectorBytes: 3,
    alignmentBytes: compiled.programAddress - compiled.runtimeBase -
      compiled.runtimeLength,
    comBytes: compiled.comBytes.length,
    heapCells: compiled.heapCells,
    heapBytes: compiled.heapCells * 4,
    bssBase: compiled.bssBaseAddress,
    bssBytes: compiled.bssBytes,
    bssEnd: compiled.bssEndAddress,
    rootBase: compiled.rootBaseAddress,
    rootBytes: compiled.rootBytes,
    activationBase: compiled.activationBaseAddress,
    activationBytes: compiled.activationBytes,
    runtimeWorkspaceBytes: compiled.runtimeWorkspaceBytes,
    bitmapBase: compiled.bitmapBaseAddress,
    bitmapBytes: compiled.bitmapBytes,
    heapBase: heapStart,
    heapWrites,
    steps,
    cycles,
    resultTag: machineMemory[compiled.resultTagAddress]!,
    resultPayload: wordAt(machineMemory, compiled.resultAddress),
    runtimeErrorCode,
  };
}

export async function measureProgram(
  file: string,
  options: MeasureOptions = {},
): Promise<M13Measurement> {
  const source = await Deno.readFile(
    new URL(`../examples/${file}`, import.meta.url),
  );
  const compiled = await compileM10(source, file, { heapCells: 512 });
  const result = measureCompiled(file, compiled, {
    maxSteps: file === "mutual-tail.sk8"
      ? options.maxSteps ?? 120_000_000
      : options.maxSteps,
    input: options.input,
  });
  return { ...result, sourceBytes: source.length };
}

function hex(value: number): string {
  return "$" + value.toString(16).toUpperCase().padStart(4, "0");
}

export function renderM13Report(rows: readonly M13Measurement[]): string {
  const lines = [
    "# M13 current measurements",
    "",
    "These figures measure the current packed generated path. The entry vector",
    "and alignment are counted separately. Heap writes include startup initialisation",
    "and all allocator/collector traffic observed in the Debug80 run.",
    "",
    "| Program | Caller image | Runtime image | COM | BSS extent | Roots | Activations | Workspace | Bitmap | Heap | Heap writes | Steps | Cycles |",
    "| --- | ---: | ---: | ---: | --- | --- | --- | ---: | --- | --- | ---: | ---: | ---: |",
  ];
  for (const row of rows) {
    lines.push(
      `| ${row.program} | ${row.callerImageBytes} B | ${row.runtimeImageBytes} B | ${row.comBytes} B | ` +
        `${hex(row.bssBase)}..${hex(row.bssEnd)} (${row.bssBytes} B) | ` +
        `${hex(row.rootBase)} (${row.rootBytes} B) | ` +
        `${hex(row.activationBase)} (${row.activationBytes} B) | ` +
        `${row.runtimeWorkspaceBytes} B | ${
          hex(row.bitmapBase)
        } (${row.bitmapBytes} B) | ` +
        `${row.heapBytes} B (${row.heapCells} cells) | ${row.heapWrites} | ${row.steps} | ${row.cycles} |`,
    );
  }
  lines.push(
    "",
    "Heap bases: " +
      rows.map((row) => `${row.program} ${hex(row.heapBase)}`).join(", ") + ".",
    "",
  );
  return lines.join("\n");
}

function parseArgs(
  args: readonly string[],
): { files: string[]; output?: string } {
  const files: string[] = [];
  let output: string | undefined;
  for (let index = 0; index < args.length; index++) {
    const argument = args[index]!;
    if (argument === "--output") {
      output = args[++index];
      if (output === undefined) throw new Error("--output needs a path");
    } else {
      files.push(argument);
    }
  }
  return { files: files.length === 0 ? [...DEFAULT_PROGRAMS] : files, output };
}

if (import.meta.main) {
  try {
    const { files, output } = parseArgs(Deno.args);
    const rows: M13Measurement[] = [];
    for (const file of files) rows.push(await measureProgram(file));
    const report = renderM13Report(rows);
    if (output !== undefined) {
      await Deno.writeTextFile(output, report + "\n");
    }
    console.log(report);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exitCode = 1;
  }
}
