import assert from "node:assert/strict";
import { join } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../../tests/z80.ts";
import {
  installCpm22File,
  readCpm22File,
} from "../../../triptych/tools/lib/cpm22-disk.mjs";
import { assembleTriptychCpuFirmware } from "../../../triptych/tools/cpm22-native-image.mjs";

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

const compiler = await loadAssembly("src/compiler/scope-control-compiler.asm");
const provider = await loadAssembly(
  "src/compiler/scope-control-runtime-image.asm",
);
const compilerBytes = compiler.image.bytes.slice(0x0100);
const runtimeBytes = provider.image.bytes.slice(0x0100);
assert.equal(runtimeBytes.length, compiler.address("SRTLEN"));
const globalDefinitions = Array.from(
  { length: 256 },
  (_, index) => `(define g${String(index).padStart(3, "0")} ${index})`,
).join("");
const cases = [
  ["GLOB256.SK8", `${globalDefinitions}(+ g255 1)`, "256"],
  ["FORM256.SK8", Array.from({ length: 256 }, () => "1").join(" "), "1"],
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
}

try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  const measurements = [];
  for (const [name, , expected] of cases) {
    runCommand(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    const image = machine.export_drive(0);
    const outputName = name.replace(".SK8", ".COM");
    const generated = readCpm22File(image, outputName);
    const object = readCpm22File(image, name.replace(".SK8", ".NOB"));
    measurements.push({
      name,
      comBytes: generated.length,
      nobjBytes: object.length,
    });
    assert.equal(generated[0], 0x31, `${outputName} sets its private stack`);
    runCommand(
      outputName.replace(".COM", ""),
      `${expected}\r\n`,
      `run ${outputName}`,
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
      largestNobjBytes: Math.max(
        ...measurements.map(({ nobjBytes }) => nobjBytes),
      ),
      measurements,
      transcript,
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
