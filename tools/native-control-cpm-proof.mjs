import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../tests/z80.ts";
import { assembleTriptychCpuFirmware } from "../../triptych/tools/cpm22-native-image.mjs";
import {
  installCpm22File,
  readCpm22File,
} from "../../triptych/tools/lib/cpm22-disk.mjs";

const triptychRoot = fileURLToPath(new URL("../../triptych/", import.meta.url));
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

const compiler = await loadAssembly("tests/native-control-compiler.asm");
assert.equal(compiler.image.base, 0);
assert.equal(compiler.address("N5MAIN"), 0x0100);
assert.ok(compiler.address("N4OBJEND") < 0x8000);
const compilerBytes = compiler.image.bytes.slice(0x0100);
let disk = installCpm22File(backing, {
  name: "SKATE.COM",
  bytes: compilerBytes,
  padByte: 0x1a,
});
for (
  const [name, text] of [
    ["ADD.SK8", "(+ 40 2)"],
    ["NEST.SK8", "(+ 10 (* 2 16))"],
    ["IF.SK8", "(if #f (+ 32767 1) (+ 40 2))"],
    ["BEGIN.SK8", "(begin (+ 1 2) (+ 20 22))"],
    ["IFNEST.SK8", "(if #t (if #f 1 42) (+ 3 4))"],
    ["EMPTY.SK8", "(begin)"],
    ["NOT.SK8", "(not #f)"],
    ["NUMBER.SK8", "(number? 42)"],
    ["BOOLEAN.SK8", "(boolean? #t)"],
    ["ZERO.SK8", "(zero? 0)"],
    ["IFDEF.SK8", "(if #t 42)"],
    ["OVER.SK8", "(+ 32767 1)"],
    ["BAD.SK8", "(+ 1"],
    ["DIVONE.SK8", "(/ 40)"],
    ["MINUS0.SK8", "(-)"],
  ]
) {
  disk = installCpm22File(disk, {
    name,
    bytes: new TextEncoder().encode(text + "\x1a"),
    padByte: 0x1a,
  });
}

const machine = new TriptychCpu(firmware.bootRom);
let transcript = "";
const decoder = new TextDecoder("ascii");
function runUntilPrompt(offset, description) {
  for (let slice = 0; slice < 1800; slice += 1) {
    const status = machine.run_slice(50_000, 500_000);
    transcript += decoder.decode(machine.take_serial_output());
    assert.notEqual(status, 0, `CP/M halted while waiting for ${description}`);
    if (transcript.length > offset && transcript.endsWith("A>")) return;
  }
  throw new Error(
    `Timed out waiting for ${description}: ${transcript.slice(-500)}`,
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
function assertAbsent(image, name) {
  assert.throws(() => readCpm22File(image, name), /is absent/);
}

try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  runCommand("SKATE ADD.SK8", "COMPILED\r\n", "SKATE compilation");
  for (
    const [sourceName, outputName, expected] of [
      ["NEST.SK8", "NEST.COM", "42\r\n"],
      ["IF.SK8", "IF.COM", "42\r\n"],
      ["BEGIN.SK8", "BEGIN.COM", "42\r\n"],
      ["IFNEST.SK8", "IFNEST.COM", "42\r\n"],
      ["EMPTY.SK8", "EMPTY.COM", "F16:FE04\r\n"],
      ["NOT.SK8", "NOT.COM", "F16:FE01\r\n"],
      ["NUMBER.SK8", "NUMBER.COM", "F16:FE01\r\n"],
      ["BOOLEAN.SK8", "BOOLEAN.COM", "F16:FE01\r\n"],
      ["ZERO.SK8", "ZERO.COM", "F16:FE01\r\n"],
      ["IFDEF.SK8", "IFDEF.COM", "42\r\n"],
    ]
  ) {
    runCommand("SKATE " + sourceName, "COMPILED\r\n", sourceName);
    const image = machine.export_drive(0);
    const generated = readCpm22File(image, outputName);
    const text = new TextDecoder("ascii").decode(generated);
    assert.ok(
      text.includes(expected),
      `${outputName}: ${JSON.stringify(text)}`,
    );
  }
  runCommand("SKATE OVER.SK8", "COMPILE ERROR\r\n", "overflow rejection");
  assertAbsent(machine.export_drive(0), "OVER.COM");
  assertAbsent(machine.export_drive(0), "OVER.NOB");
  runCommand("SKATE BAD.SK8", "COMPILE ERROR\r\n", "malformed rejection");
  assertAbsent(machine.export_drive(0), "BAD.COM");
  assertAbsent(machine.export_drive(0), "BAD.NOB");
  for (const name of ["DIVONE", "MINUS0"]) {
    runCommand("SKATE " + name + ".SK8", "COMPILE ERROR\r\n", name);
    assertAbsent(machine.export_drive(0), name + ".COM");
    assertAbsent(machine.export_drive(0), name + ".NOB");
  }
  runCommand("ADD", "42\r\n", "generated ADD.COM");
  console.log(JSON.stringify(
    {
      status: "passed",
      compilerBytes: compilerBytes.length,
      compilerCode: compiler.address("N4OBJ") - compiler.address("N5MAIN"),
      evaluatorCode: compiler.address("N5OP") - compiler.address("N5MAIN"),
      readerCode: compiler.address("REND") - compiler.address("RINIT"),
      templateBytes: compiler.address("N4OBJEND") - compiler.address("N4OBJ"),
      transcript,
      platform: "Triptych WASM with CP/M 2.2",
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
