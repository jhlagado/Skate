import assert from "node:assert/strict";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../../tests/z80.ts";
import { validateAso } from "./aso-proof.mjs";
import {
  createBlankCpm22Disk,
  installCpm22File,
  readCpm22File,
} from "../../../triptych/tools/lib/cpm22-disk.mjs";
import {
  createCpmSession,
  directoryFiles,
  diskStats,
  loadCpmSystem,
  sha256,
  TriptychCpu,
} from "./cpm-harness.mjs";

const skateRoot = fileURLToPath(new URL("../../", import.meta.url));
const imageArgument = Deno.args.find((argument) =>
  argument.startsWith("--image=")
);
const imagePath = imageArgument
  ? resolve(skateRoot, imageArgument.slice("--image=".length))
  : null;
const encoder = new TextEncoder();
const sourceRoot = join(skateRoot, "examples", "applications");
function makeSystemDisk(firmware) {
  const system = createBlankCpm22Disk();
  system.set(firmware.ccp, 0x0000);
  system.set(firmware.bdos, 0x0800);
  system.set(firmware.bios, 0x1600);
  const disk = new Uint8Array(Math.ceil(system.length / 512) * 512);
  disk.set(system);
  return disk;
}

function newMachine(firmware, image) {
  const machine = new TriptychCpu(firmware.bootRom);
  machine.install_drive(0, image, true);
  return machine;
}

function session(machine) {
  const cpm = createCpmSession(machine, {
    promptAttempts: (description) =>
      description.startsWith("compile") ? 12000 : 8000,
  });
  return {
    boot: () => cpm.runUntilPrompt(0, "boot"),
    command: cpm.runCommandMeasured,
  };
}

const { firmware, sourceDisk } = await loadCpmSystem();
const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const provider = await loadAssembly(
  "src/runtime/image.asm",
);
let disk = makeSystemDisk(firmware);
for (
  const [name, bytes] of [
    ["EDIT.COM", readCpm22File(sourceDisk, "EDIT.COM")],
    ["SKATE.COM", compiler.image.bytes.slice(0x100)],
    ["SKATE.RT", provider.image.bytes.slice(0x100)],
  ]
) disk = installCpm22File(disk, { name, bytes, padByte: 0x1a });
const examples = [
  ["RECEIPT", "Total (cents): 620\r\n"],
  ["ROUTE", "(1 2 5 6)\r\n"],
  ["ACCOUNT", "Combined balance: 6650\r\n"],
];
for (const name of ["README.TXT", ...examples.map(([name]) => name + ".SK8")]) {
  const text = await Deno.readTextFile(join(sourceRoot, name.toLowerCase()));
  const normalized = text.replace(/\r?\n/g, "\r\n");
  assert.equal(text, normalized, name + ": source must use CRLF");
  disk = installCpm22File(disk, {
    name,
    bytes: encoder.encode(normalized + "\x1a"),
    padByte: 0x1a,
  });
}
let machine = newMachine(firmware, disk);
const records = [];
try {
  const terminal = session(machine);
  terminal.boot();
  for (const [name, expected] of examples) {
    const source = await Deno.readTextFile(
      join(sourceRoot, name.toLowerCase() + ".sk8"),
    );
    terminal.command("TYPE " + name + ".SK8", source, "type " + name);
    terminal.command(
      "SKATE " + name + ".SK8",
      "COMPILED\r\n",
      "compile " + name,
    );
    const saved = machine.export_drive(0);
    const com = readCpm22File(saved, name + ".COM");
    const aso = readCpm22File(saved, name + ".ASO");
    validateAso(aso, com, name);
    records.push({
      name,
      bytes: com.length,
      run: terminal.command(name, expected, "run " + name),
    });
    // Keep runnable examples and source; intermediate objects can be rebuilt.
    terminal.command(
      "ERA " + name + ".ASO",
      "A>",
      "remove ASO intermediate " + name,
    );
  }
  disk = machine.export_drive(0);
  machine.free();
  machine = newMachine(firmware, disk);
  const reopened = session(machine);
  reopened.boot();
  for (const [name, expected] of examples) {
    reopened.command(name, expected, "reopen " + name);
  }
} finally {
  machine.free();
}
assert.deepEqual(
  [...new Set(directoryFiles(disk).map(({ name }) => name))].sort(),
  [
    "EDIT.COM",
    "SKATE.COM",
    "SKATE.RT",
    "README.TXT",
    ...examples.flatMap(([name]) => [name + ".SK8", name + ".COM"]),
  ].sort(),
  "disk must contain only the Skate tools, documentation and examples",
);
if (imagePath) {
  await Deno.mkdir(dirname(imagePath), { recursive: true });
  await Deno.writeFile(imagePath, disk);
}
console.log(
  JSON.stringify(
    {
      status: "passed",
      imagePath,
      sha256: sha256(disk),
      disk: diskStats(disk),
      records,
    },
    null,
    2,
  ),
);
