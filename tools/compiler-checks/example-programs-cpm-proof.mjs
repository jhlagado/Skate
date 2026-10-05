// Compile and run example programs that the other CP/M proofs do not cover:
// the terminal demo with its included library, and the house adventure driven
// through to its winning ending.
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
  TriptychCpu,
} from "./cpm-harness.mjs";

const { firmware, sourceDisk } = await loadCpmSystem();
const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const provider = await loadAssembly("src/runtime/image.asm");
assert.equal(provider.image.bytes.length - 0x100, compiler.address("RT_SIZE"));

const files = [
  ["SKATE.COM", compiler.image.bytes.slice(0x100)],
  ["SKATE.RT", provider.image.bytes.slice(0x100)],
  ["TERMINAL.SK8", await Deno.readFile("libraries/terminal.sk8")],
  ["TERMDEMO.SK8", await Deno.readFile("examples/terminal-demo.sk8")],
  ["HOUSE.SK8", await Deno.readFile("examples/applications/house.sk8")],
];
let disk = makeSystemDisk(firmware, sourceDisk);
for (const [name, bytes] of files) {
  disk = installCpm22File(disk, { name, bytes, padByte: 0x1a });
}

const escape = "\x1b";
const cases = [
  {
    name: "TERMDEMO",
    input: [],
    // The library writes ANSI sequences through the ordinary console path.
    expected: `${escape}[2J${escape}[H${escape}[31mHello from Skate\r\n` +
      `${escape}[0m`,
    exact: true,
  },
  {
    name: "HOUSE",
    // Open the window, climb in, go to the cellar and lift the trapdoor.
    // The last key exercises the #\t character literal.
    input: ["o", "c", "d", "t"],
    expected: "The trapdoor opens. You win.\r\n",
    exact: false,
  },
];

const machine = new TriptychCpu(firmware.bootRom);
const cpm = createCpmSession(machine);

function runProgram(name, input) {
  const start = cpm.transcript.length;
  cpm.send(`${name}\r`);
  for (const chunk of input) {
    // Let the program reach its blocking console read before each key.
    for (let attempt = 0; attempt < 8; attempt += 1) {
      cpm.slice(50_000, 500_000, `CP/M halted before input for ${name}`);
    }
    cpm.send(chunk);
  }
  cpm.runUntilPrompt(start, `run ${name}`);
  return programOutput(cpm.transcript.slice(start));
}

try {
  machine.install_drive(0, disk, true);
  cpm.runUntilPrompt(0, "the boot prompt");
  const measurements = [];
  for (const { name, input, expected, exact } of cases) {
    cpm.runCommand(`SKATE ${name}.SK8`, "COMPILED\r\n", `compile ${name}`);
    const image = machine.export_drive(0);
    const com = readCpm22File(image, `${name}.COM`);
    const aso = readCpm22File(image, `${name}.ASO`);
    const { asoBytes } = validateAso(aso, com, name);
    const output = runProgram(name, input);
    if (exact) {
      assert.equal(output, expected, `${name}: unexpected program output`);
    } else {
      assert.ok(
        output.endsWith(expected),
        `${name}: expected output to end with ${JSON.stringify(expected)}, ` +
          `got ${JSON.stringify(output)}`,
      );
    }
    measurements.push({ name, comBytes: com.length, asoBytes });
  }
  console.log(JSON.stringify({ status: "passed", measurements }, null, 2));
} finally {
  machine.free();
}
