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
const backing = makeSystemDisk(firmware, sourceDisk);

const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const provider = await loadAssembly(
  "src/runtime/image.asm",
);
assert.equal(compiler.image.base, 0);
assert.ok(compiler.address("SCMAIN") === 0x0100);
assert.ok(compiler.address("SCEND") < 0x10000);
const runtimeLength = provider.image.bytes.length - 0x0100;
assert.equal(runtimeLength, compiler.address("SRTLEN"));
let disk = installCpm22File(backing, {
  name: "SKATE.COM",
  bytes: compiler.image.bytes.slice(0x0100),
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "SKATE.RT",
  bytes: provider.image.bytes.slice(0x0100),
  padByte: 0x1a,
});

const cases = [
  [
    "NESTMULT.SK8",
    "(define f (lambda (z) (let outer ((a (+ z 1)) (b (let inner ((x (+ z 2))) (+ x z)))) (+ a b z)))) (begin (write (f 3)) (newline))",
    "15",
  ],
  [
    "ESCAPE.SK8",
    "(define f (lambda (x) (let ((y 2)) (define (g) (+ x y)) g))) (begin (write ((f 40))) (newline))",
    "42",
  ],
  [
    "INTCAP.SK8",
    "(define f (lambda (x) (let ((y 2)) (define (g n) (if (= n 0) (+ x y) (g (- n 1)))) g))) (begin (write ((f 40) 200)) (newline))",
    "42",
  ],
  [
    "LSTSHAD.SK8",
    "(begin (write (let* ((x 1) (y x)) (define x 2) x)) (newline))",
    "2",
  ],
];
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
    const generated = readCpm22File(image, name.replace(".SK8", ".COM"));
    const aso = readCpm22File(image, name.replace(".SK8", ".ASO"));
    const { asoBytes } = validateAso(aso, generated, name);
    measurements.push({
      name,
      comBytes: generated.length,
      asoBytes,
    });
    const runOutput = runCommand(
      name.replace(".SK8", ""),
      `${expected}\r\n`,
      `run ${name.replace(".SK8", ".COM")}`,
    );
    assert.equal(
      programOutput(runOutput),
      `${expected}\r\n`,
      `${name}: unexpected program output`,
    );
    runCommand(`ERA ${name.replace(".SK8", ".COM")}`, "A>", `remove ${name}`);
    runCommand(`ERA ${name.replace(".SK8", ".ASO")}`, "A>", `remove ${name}`);
  }
  console.log(JSON.stringify(
    {
      status: "passed",
      compilerBytes: compiler.image.bytes.length - 0x100,
      imageEnd: compiler.image.end,
      runtimeBytes: runtimeLength,
      cases: cases.map(([name]) => name),
      largestComBytes: Math.max(
        ...measurements.map(({ comBytes }) => comBytes),
      ),
      largestAsoBytes: Math.max(
        ...measurements.map(({ asoBytes }) => asoBytes),
      ),
      measurements,
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
