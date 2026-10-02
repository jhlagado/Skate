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
  TriptychCpu,
} from "./cpm-harness.mjs";

const { firmware, sourceDisk } = await loadCpmSystem();
// Capacity cases need a fresh directory, independent of bundled disk contents.
const backing = makeSystemDisk(firmware, sourceDisk);

const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const provider = await loadAssembly(
  "src/runtime/image.asm",
);
const compilerBytes = compiler.image.bytes.slice(0x0100);
const runtimeBytes = provider.image.bytes.slice(0x0100);
assert.equal(runtimeBytes.length, compiler.address("SRTLEN"));
const globalDefinitions = Array.from(
  { length: 256 },
  (_, index) => `(define g${String(index).padStart(3, "0")} ${index})`,
).join("");
const longGlobalDefinitions = Array.from(
  { length: 256 },
  (_, index) => `(define state${String(index).padStart(11, "0")} ${index})`,
).join("");
const stringGlobalDefinitions = Array.from(
  { length: 256 },
  (_, index) => {
    const name = `state${String(index).padStart(11, "0")}`;
    const value = index < 16
      ? `"message${String(index).padStart(2, "0")}_"`
      : String(index);
    return `(define ${name} ${value})`;
  },
).join("");
const cases = [
  [
    "GLOB256.SK8",
    `${globalDefinitions}(begin (write (+ g255 1)) (newline))`,
    "256",
  ],
  [
    "GLOB16.SK8",
    `${longGlobalDefinitions}(begin (write (+ state00000000255 1)) (newline))`,
    "256",
  ],
  [
    "GLOBSTR.SK8",
    `${stringGlobalDefinitions}(begin (write (+ state00000000255 1)) (newline))`,
    "256",
  ],
  [
    "FORM256.SK8",
    `(begin ${
      Array.from({ length: 254 }, () => "1").join(" ")
    } (write 1) (newline))`,
    "1",
  ],
];
let disk = installCpm22File(backing, {
  name: "SKATE.COM",
  bytes: compilerBytes,
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "SKATE.RT",
  bytes: runtimeBytes,
  padByte: 0x1a,
});
for (const [name, source] of cases) {
  disk = installCpm22File(disk, {
    name,
    bytes: new TextEncoder().encode(source + "\x1a"),
    padByte: 0x1a,
  });
}

const machine = new TriptychCpu(firmware.bootRom);
const cpm = createCpmSession(machine);
const { runUntilPrompt, runCommand } = cpm;
try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  const measurements = [];
  for (const [name, , expected] of cases) {
    runCommand(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    const image = machine.export_drive(0);
    const outputName = name.replace(".SK8", ".COM");
    const generated = readCpm22File(image, outputName);
    const aso = readCpm22File(image, name.replace(".SK8", ".ASO"));
    const { asoBytes } = validateAso(aso, generated, name);
    measurements.push({
      name,
      comBytes: generated.length,
      asoBytes,
    });
    assert.equal(generated[0], 0x31, `${outputName} sets its private stack`);
    runCommand(
      outputName.replace(".COM", ""),
      `${expected}\r\n`,
      `run ${outputName}`,
    );
    runCommand(`ERA ${outputName}`, "A>", `remove ${outputName}`);
    runCommand(
      `ERA ${name.replace(".SK8", ".ASO")}`,
      "A>",
      `remove ${name.replace(".SK8", ".ASO")}`,
    );
  }
  console.log(JSON.stringify(
    {
      status: "passed",
      compilerBytes: compilerBytes.length,
      runtimeBytes: runtimeBytes.length,
      imageEnd: compiler.image.end,
      cases: cases.map(([name]) => name),
      largestComBytes: Math.max(
        ...measurements.map(({ comBytes }) => comBytes),
      ),
      largestAsoBytes: Math.max(
        ...measurements.map(({ asoBytes }) => asoBytes),
      ),
      measurements,
      transcript: cpm.transcript,
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
