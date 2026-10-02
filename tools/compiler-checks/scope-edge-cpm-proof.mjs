import assert from "node:assert/strict";
import { join } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../../tests/z80.ts";
import { validateAso } from "./aso-proof.mjs";
import { assembleTriptychCpuFirmware } from "../../../triptych/tools/cpm22-native-image.mjs";
import {
  installCpm22File,
  readCpm22File,
} from "../../../triptych/tools/lib/cpm22-disk.mjs";

const triptychRoot = fileURLToPath(
  new URL("../../../triptych/", import.meta.url),
);
const require = createRequire(import.meta.url);
const { TriptychCpu } = require(
  join(triptychRoot, "dist", "wasm", "triptych_host_wasm.js"),
);
const firmware = await assembleTriptychCpuFirmware(triptychRoot);
const sourceDisk = await Deno.readFile(
  join(triptychRoot, "third_party", "cpm22", "cpm22.img"),
);
const systemDisk = Uint8Array.from(sourceDisk);
systemDisk.set(firmware.ccp, 0x0000);
systemDisk.set(firmware.bdos, 0x0800);
systemDisk.set(firmware.bios, 0x1600);
const backing = new Uint8Array(Math.ceil(systemDisk.length / 512) * 512);
backing.set(systemDisk);
backing.fill(0xe5, 52 * 128, 52 * 128 + 64 * 32);

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
// The runtime needs a TPA reaching its E400H stack ceiling.  This program is
// run once with a lowered BDOS base and must refuse cleanly before using it.
const smallTpaCase = ["SMALLTPA.SK8", "(begin (write 1) (newline))", "1"];
for (const [name, source] of [...cases, smallTpaCase]) {
  disk = installCpm22File(disk, {
    name,
    bytes: new TextEncoder().encode(source + "\x1a"),
    padByte: 0x1a,
  });
}

const machine = new TriptychCpu(firmware.bootRom);
const decoder = new TextDecoder("ascii");
let transcript = "";
function runUntilPrompt(offset, description) {
  for (let attempt = 0; attempt < 1800; attempt += 1) {
    const status = machine.run_slice(50_000, 500_000);
    transcript += decoder.decode(machine.take_serial_output());
    assert.notEqual(status, 0, `CP/M halted while waiting for ${description}`);
    if (transcript.length > offset && transcript.endsWith("A>")) return;
  }
  throw new Error(
    `Timed out waiting for ${description}: ${
      JSON.stringify(transcript.slice(-500))
    }`,
  );
}
function runCommand(command, expected, description) {
  const start = transcript.length;
  assert.ok(
    machine.enqueue_serial_input(new TextEncoder().encode(command + "\r")),
  );
  runUntilPrompt(start, description);
  const output = transcript.slice(start);
  assert.ok(output.includes(expected), JSON.stringify(output));
  return output;
}
function programOutput(output) {
  const commandEnd = output.indexOf("\r\r\n");
  const prompt = output.lastIndexOf("\r\nA>");
  assert.ok(commandEnd >= 0 && prompt > commandEnd, JSON.stringify(output));
  return output.slice(commandEnd + 3, prompt);
}

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
  {
    const [name, , expected] = smallTpaCase;
    const command = name.replace(".SK8", "");
    runCommand(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    const realBase = machine.read_ram(0x0006, 2);
    const loweredBase = 0xd000;
    // Keep BDOS callable through a trampoline at the lowered base address.
    machine.write_ram(
      loweredBase,
      new Uint8Array([0xc3, realBase[0], realBase[1]]),
    );
    machine.write_ram(
      0x0006,
      new Uint8Array([loweredBase & 255, loweredBase >> 8]),
    );
    const refused = runCommand(command, "NOT ENOUGH MEMORY\r\n", "small TPA");
    assert.equal(programOutput(refused), "NOT ENOUGH MEMORY\r\n");
    assert.deepEqual(
      [...machine.read_ram(0x0006, 2)],
      [...realBase],
      "warm start restores the BDOS vector",
    );
    const normal = runCommand(command, `${expected}\r\n`, "full TPA");
    assert.equal(programOutput(normal), `${expected}\r\n`);
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
