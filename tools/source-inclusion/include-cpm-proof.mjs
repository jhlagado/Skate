import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../../tests/z80.ts";
import { assembleTriptychCpuFirmware } from "../../../triptych/tools/cpm22-native-image.mjs";
import {
  installCpm22File,
  readCpm22File,
} from "../../../triptych/tools/lib/cpm22-disk.mjs";
import {
  createSkmManifest,
  resolveSkateSource,
} from "./skate-source-profile.mjs";

const triptychRoot = fileURLToPath(
  new URL("../../../triptych/", import.meta.url),
);
const fixtureRoot = fileURLToPath(
  new URL("../../tests/source-inclusion/fixtures/", import.meta.url),
);
const require = createRequire(import.meta.url);
const { TriptychCpu } = require(
  join(triptychRoot, "dist", "wasm", "triptych_host_wasm.js"),
);

const project = await resolveSkateSource({
  root: fixtureRoot,
  entry: "MAIN.SK8",
});
assert.deepEqual(project.parts.map((part) => part.logicalIdentity), [
  "LIB.SK8",
  "MAIN.SK8",
]);
const firmware = await assembleTriptychCpuFirmware(triptychRoot);
const sourceDisk = await Deno.readFile(
  join(triptychRoot, "third_party", "cpm22", "cpm22.img"),
);
const systemDisk = Uint8Array.from(sourceDisk);
systemDisk.set(firmware.ccp, 0);
systemDisk.set(firmware.bdos, 0x0800);
systemDisk.set(firmware.bios, 0x1600);
const backing = new Uint8Array(Math.ceil(systemDisk.length / 512) * 512);
backing.set(systemDisk);
backing.fill(0xe5, 52 * 128, 52 * 128 + 64 * 32);

const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const runtime = await loadAssembly(
  "src/runtime/image.asm",
);
let disk = installCpm22File(backing, {
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
  name: "MAIN.SKM",
  bytes: createSkmManifest(project.parts),
  padByte: 0x1a,
});
for (const part of project.parts) {
  disk = installCpm22File(disk, {
    name: part.logicalIdentity,
    bytes: part.compilerBytes,
    padByte: 0x1a,
  });
}

const machine = new TriptychCpu(firmware.bootRom);
const decoder = new TextDecoder("ascii");
const encoder = new TextEncoder();
let transcript = "";
function untilPrompt(description) {
  const start = transcript.length;
  for (let attempt = 0; attempt < 1800; attempt += 1) {
    const status = machine.run_slice(50_000, 500_000);
    transcript += decoder.decode(machine.take_serial_output());
    assert.notEqual(status, 0, `CP/M halted during ${description}`);
    if (transcript.length > start && transcript.endsWith("A>")) {
      return transcript.slice(start);
    }
  }
  throw new Error(`timed out during ${description}: ${transcript.slice(-300)}`);
}
function command(input, expected) {
  assert.ok(machine.enqueue_serial_input(encoder.encode(`${input}\r`)));
  const output = untilPrompt(input);
  assert.ok(output.includes(expected), `${input}: ${JSON.stringify(output)}`);
}

try {
  machine.install_drive(0, disk, true);
  untilPrompt("boot");
  command("SKATE MAIN.SKM", "COMPILED\r\n");
  assert.ok(readCpm22File(machine.export_drive(0), "MAIN.COM").length > 0);
  command("MAIN", "42\r\n");
  console.log(
    "Skate include source prepared by shared resolver compiled and ran under CP/M",
  );
} finally {
  machine.free();
}
