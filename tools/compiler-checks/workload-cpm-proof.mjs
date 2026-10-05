// Compile and run the workload programs in examples/workloads on CP/M and
// report what each one costs: COM and ASO bytes, heap and stack use,
// allocation counts, collections and instructions.
//
// Each NAME.SK8 may have a NAME.OUT beside it holding the exact expected
// output; without one the output is printed instead of checked.  Pass file
// paths to run other programs, for example while writing a new workload, and
// --save=DIR (with write permission) to keep the compiled COM files.
import assert from "node:assert/strict";

import { loadAssembly } from "../../tests/z80.ts";
import { validateAso } from "./aso-proof.mjs";
import {
  installCpm22File,
  readCpm22File,
} from "../../../triptych/tools/lib/cpm22-disk.mjs";
import {
  createCpmSession,
  loadCpmSystem,
  makeSystemDisk,
  programOutput,
  readWord,
  TriptychCpu,
} from "./cpm-harness.mjs";

const workloadRoot = "examples/workloads";
const paths = Deno.args.filter((argument) => !argument.startsWith("--"));
// --save=DIR keeps each compiled COM file there for inspection.
const saveDirectory = Deno.args.find((argument) =>
  argument.startsWith("--save=")
)?.slice("--save=".length);
if (paths.length === 0) {
  for await (const entry of Deno.readDir(workloadRoot)) {
    if (entry.isFile && /\.sk8$/i.test(entry.name)) {
      paths.push(`${workloadRoot}/${entry.name}`);
    }
  }
  paths.sort();
}
assert.ok(paths.length > 0, "no workload programs found");

const { firmware, sourceDisk } = await loadCpmSystem();
const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const provider = await loadAssembly("src/runtime/image.asm");
assert.equal(provider.image.bytes.length - 0x100, compiler.address("RT_SIZE"));

const counters = {
  lowSp: provider.address("RT_LOWSP"),
  heapEnd: provider.address("HEAP_LIM"),
  bindingAllocations: provider.address("CNT_BIND"),
  closureAllocations: provider.address("CNT_CLOS"),
  pairAllocations: provider.address("CNT_PAIR"),
  collections: provider.address("CNT_GC"),
  activations: provider.address("CNT_MAPS"),
};

const programs = [];
for (const path of paths) {
  const base = path.replace(/^.*\//, "").replace(/\.sk8$/i, "").toUpperCase();
  assert.ok(/^[A-Z0-9]{1,8}$/.test(base), `${path}: not a CP/M 8.3 name`);
  let expected;
  try {
    expected = await Deno.readTextFile(path.replace(/\.sk8$/i, ".out"));
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  programs.push({ base, source: await Deno.readFile(path), expected });
}

// Every library is on the disk so that a workload can include it.
const libraries = [];
for await (const entry of Deno.readDir("libraries")) {
  if (entry.isFile && /\.sk8$/i.test(entry.name)) {
    libraries.push([
      entry.name.toUpperCase(),
      await Deno.readFile(`libraries/${entry.name}`),
    ]);
  }
}

for (const { base } of programs) {
  assert.ok(
    !libraries.some(([name]) => name === `${base}.SK8`),
    `${base}.SK8 has the same name as a library`,
  );
}

let disk = makeSystemDisk(firmware, sourceDisk);
for (
  const [name, bytes] of [
    ["SKATE.COM", compiler.image.bytes.slice(0x100)],
    ["SKATE.RT", provider.image.bytes.slice(0x100)],
    ...programs.map(({ base, source }) => [`${base}.SK8`, source]),
    ...libraries,
  ]
) {
  disk = installCpm22File(disk, { name, bytes, padByte: 0x1a });
}

const machine = new TriptychCpu(firmware.bootRom);
// Workloads run for longer than the focused proofs.
const cpm = createCpmSession(machine, { promptAttempts: 40_000 });
const results = [];
let failed = false;

try {
  machine.install_drive(0, disk, true);
  cpm.runUntilPrompt(0, "the boot prompt");
  for (const { base, expected } of programs) {
    const compileOutput = cpm.runCommand(
      `SKATE ${base}.SK8`,
      "A>",
      `compile ${base}`,
    );
    if (!compileOutput.includes("COMPILED\r\n")) {
      failed = true;
      results.push({ name: base, compile: programOutput(compileOutput) });
      continue;
    }
    const image = machine.export_drive(0);
    const com = readCpm22File(image, `${base}.COM`);
    const aso = readCpm22File(image, `${base}.ASO`);
    const { imageBytes, asoBytes } = validateAso(aso, com, base);
    if (saveDirectory !== undefined) {
      await Deno.writeFile(`${saveDirectory}/${base}.COM`, com);
    }
    const run = cpm.runCommandMeasured(base, "A>", `run ${base}`);
    const output = programOutput(run.output);
    const result = {
      name: base,
      comBytes: com.length,
      imageBytes,
      asoBytes,
      instructions: run.instructions,
    };
    for (const [key, address] of Object.entries(counters)) {
      result[key] = readWord(machine, address);
    }
    if (expected === undefined) {
      result.output = output;
    } else if (output !== expected.replaceAll(/\r?\n/g, "\r\n")) {
      failed = true;
      result.output = output;
      result.mismatch = true;
    }
    results.push(result);
    cpm.runCommand(`ERA ${base}.COM`, "A>", `remove ${base}.COM`);
    cpm.runCommand(`ERA ${base}.ASO`, "A>", `remove ${base}.ASO`);
  }
} finally {
  machine.free();
}

console.log(JSON.stringify(
  { status: failed ? "failed" : "passed", results },
  null,
  2,
));
if (failed) Deno.exit(1);
