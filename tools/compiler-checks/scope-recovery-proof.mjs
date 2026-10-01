import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

import { loadAssembly } from "../../tests/z80.ts";
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
const diskImage = new Uint8Array(Math.ceil(systemDisk.length / 512) * 512);
diskImage.set(systemDisk);
diskImage.fill(0xe5, 52 * 128, 52 * 128 + 64 * 32);

const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const runtime = await loadAssembly("src/runtime/image.asm");
let disk = installCpm22File(diskImage, {
  name: "SKATE.COM",
  bytes: compiler.image.bytes.slice(0x0100),
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "SKATE.RT",
  bytes: runtime.image.bytes.slice(0x0100),
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "REPEAT.SK8",
  bytes: new TextEncoder().encode(
    "(begin (write (+ 40 2)) (newline))\x1a",
  ),
  padByte: 0x1a,
});

let machine = new TriptychCpu(firmware.bootRom);
machine.install_drive(0, disk, true);
const decoder = new TextDecoder("ascii");
const encoder = new TextEncoder();
let transcript = "";

function waitPrompt(offset, description) {
  for (let attempt = 0; attempt < 1800; attempt += 1) {
    const status = machine.run_slice(50_000, 500_000);
    transcript += decoder.decode(machine.take_serial_output());
    assert.notEqual(status, 0, `${description}: CP/M halted`);
    if (transcript.length > offset && transcript.endsWith("A>")) return;
  }
  throw new Error(`Timed out during ${description}`);
}

function command(command, expected) {
  const offset = transcript.length;
  assert.ok(machine.enqueue_serial_input(encoder.encode(`${command}\r`)));
  waitPrompt(offset, command);
  const output = transcript.slice(offset);
  assert.ok(output.includes(expected), `${command}: ${JSON.stringify(output)}`);
}

function readOutputs(image) {
  return Object.fromEntries(
    ["REPEAT.COM", "REPEAT.ASO"].map((name) => [
      name,
      readCpm22File(image, name),
    ]),
  );
}

function installFaultBridge(target) {
  const vector = target.read_ram(5, 3);
  assert.equal(vector[0], 0xc3, "CP/M BDOS vector must be a JP");
  const original = vector[1] | vector[2] << 8;
  // Keep the bridge above Skate's guarded stack at E020 and below the resident
  // CCP at E400.  The patched page-zero BDOS address also passes Skate's
  // transient-memory guard during this proof.
  const base = 0xe200;
  const renameCount = base + 0x80;
  const deleteCount = base + 0x82;
  const code = new Uint8Array(0x70);
  const put = (offset, bytes) => code.set(bytes, offset);
  const word = (value) => [value & 0xff, value >>> 8];
  put(0x00, [
    0xf5, // PUSH AF: preserve the caller's accumulator for delegated calls.
    0x79, // LD A,C: inspect the BDOS function number.
    0xfe,
    23, // CP 23: rename.
    0xc2,
    ...word(base + 0x20), // JP NZ,bridge+20: test delete functions next.
    0x3a,
    ...word(renameCount), // LD A,(renameCount).
    0x3c, // INC A: count this rename call.
    0x32,
    ...word(renameCount), // LD (renameCount),A.
    0xfe,
    4, // CP 4: fail the ASO installation rename.
    0xca,
    ...word(base + 0x60), // JP Z,bridge+60: return the CP/M error status.
    0xc3,
    ...word(base + 0x40), // JP bridge+40: delegate other renames.
  ]);
  // The first five deletes belong to recovery's stale-stage cleanup and stage
  // creation.  The sixth delete is the rollback of the newly installed COM.
  // A nonzero, non-FF result exercises CTDELETE's transport-error branch once
  // rollback begins while leaving the recovery evidence in place for the next
  // run.
  put(0x20, [
    0x79, // LD A,C: inspect the delete function.
    0xfe,
    19, // CP 19: delete.
    0xc2,
    ...word(base + 0x40), // JP NZ,bridge+40: delegate all other BDOS calls.
    0x3a,
    ...word(deleteCount), // LD A,(deleteCount).
    0x3c, // INC A: count this delete call.
    0x32,
    ...word(deleteCount), // LD (deleteCount),A.
    0xfe,
    6, // CP 6: fail the first delete in rollback after five setup deletes.
    0xd2,
    ...word(base + 0x64), // JP NC,bridge+64: retain the recovery evidence.
    0xc3,
    ...word(base + 0x40), // JP bridge+40: delegate other deletes.
  ]);
  put(0x40, [0xf1, 0xc3, ...word(original)]); // POP AF; JP original BDOS entry.
  put(0x60, [0xf1, 0x3e, 0xff, 0xc9]); // POP AF; LD A,FF; RET: return a CP/M failure.
  put(0x64, [0xf1, 0x3e, 0x01, 0xc9]); // POP AF; LD A,1; RET: fail a delete distinctly.
  target.write_ram(base, code);
  target.write_ram(5, Uint8Array.from([0xc3, base & 0xff, base >>> 8]));
  target.write_ram(renameCount, Uint8Array.of(0, 0));
  target.write_ram(deleteCount, Uint8Array.of(0, 0));
  return { renameCount, deleteCount };
}

waitPrompt(0, "boot");
command("SKATE REPEAT.SK8", "COMPILED\r\n");
const firstDisk = machine.export_drive(0);
const first = readOutputs(firstDisk);
assert.throws(
  () => readCpm22File(firstDisk, "REPEAT.NOB"),
  "the target publication created a new NOBJ file",
);

// Reboot from the first generation with a changed source and inject one
// failed installation plus a rollback delete failure.
const changedDisk = installCpm22File(machine.export_drive(0), {
  name: "REPEAT.SK8",
  bytes: new TextEncoder().encode(
    "(begin (write (+ 40 3)) (newline))\x1a",
  ),
  padByte: 0x1a,
});
machine.free();
machine = new TriptychCpu(firmware.bootRom);
machine.install_drive(0, changedDisk, true);
transcript = "";
waitPrompt(0, "faulted boot");
const faults = installFaultBridge(machine);
command("SKATE REPEAT.SK8", "OUTPUT ERROR\r\n");
assert.ok(machine.read_ram(faults.renameCount, 1)[0] >= 4);
assert.ok(machine.read_ram(faults.deleteCount, 1)[0] >= 6);
const failed = machine.export_drive(0);
assert.deepEqual(
  [...readCpm22File(failed, "REPEAT.CPR")],
  [...first["REPEAT.COM"]],
  "rollback failure did not retain the previous COM recovery",
);
assert.deepEqual(
  [...readCpm22File(failed, "REPEAT.APR")],
  [...first["REPEAT.ASO"]],
  "rollback failure did not retain the previous ASO recovery",
);
assert.throws(
  () => readCpm22File(failed, "REPEAT.NOB"),
  "the target publication created a new NOBJ file",
);

// A fresh compiler process must recover the retained files and stages before
// compiling the changed source, proving that the failed transaction is retryable.
machine.free();
machine = new TriptychCpu(firmware.bootRom);
machine.install_drive(0, failed, true);
transcript = "";
waitPrompt(0, "recovery boot");
command("SKATE REPEAT.SK8", "COMPILED\r\n");
const second = readOutputs(machine.export_drive(0));
for (const name of Object.keys(first)) {
  assert.notDeepEqual(
    [...second[name]],
    [...first[name]],
    `${name}: changed source did not produce a new generation`,
  );
}
for (
  const name of [
    "REPEAT.NOB",
    "REPEAT.NPR",
    "REPEAT.CPR",
    "REPEAT.APR",
    "REPEAT.NBS",
    "REPEAT.CBS",
    "REPEAT.SPL",
  ]
) {
  assert.throws(
    () => readCpm22File(machine.export_drive(0), name),
    `${name} remains after recovery`,
  );
}

console.log(JSON.stringify({
  status: "passed",
  files: Object.fromEntries(
    Object.entries(first).map(([name, bytes]) => [name, bytes.length]),
  ),
}));
machine.free();
