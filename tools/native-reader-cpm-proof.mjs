import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../tests/z80.ts";
import { assembleTriptychCpuFirmware } from "../../triptych/tools/cpm22-native-image.mjs";
import { installCpm22File } from "../../triptych/tools/lib/cpm22-disk.mjs";

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

const backingLength = Math.ceil(systemDisk.length / 512) * 512;
const backing = new Uint8Array(backingLength);
backing.set(systemDisk);
const { image, address } = await loadAssembly("tests/cpm-reader.asm");
assert.ok(
  address("CREND") <= 0x7000,
  "Reader image stays below reserved stack",
);
const comBytes = image.bytes.slice(0x100 - image.base);
let disk = installCpm22File(backing, {
  name: "SKREAD.COM",
  bytes: comBytes,
  padByte: 0x1a,
});
const cases = [
  ["EMPTY.SK8", "", "READ OK"],
  [
    "LARGE.SK8",
    ";" + "x".repeat(16400) + '\r\n(define x \'(2049 3.5 "hello"))',
    "READ OK",
  ],
  ["BAD.SK8", "(define x", "READ ERROR"],
  ["RANGE.SK8", "32768", "READ ERROR"],
  ["MISSING.SK8", null, "SOURCE I/O ERROR"],
];
for (const [name, source] of cases) {
  if (source !== null) {
    disk = installCpm22File(disk, {
      name,
      bytes: new TextEncoder().encode(source + "\x1a"),
      padByte: 0x1a,
    });
  }
}
const outputPath = Deno.args[0];
if (outputPath) {
  await Deno.mkdir(dirname(outputPath), { recursive: true });
  await Deno.writeFile(outputPath, disk);
  disk = await Deno.readFile(outputPath);
}
const machine = new TriptychCpu(firmware.bootRom);
let transcript = "";
const decoder = new TextDecoder("ascii");
const promptStart = "A>";
function runUntilPrompt(offset, description) {
  for (let slice = 0; slice < 1500; slice += 1) {
    const status = machine.run_slice(50_000, 500_000);
    transcript += decoder.decode(machine.take_serial_output());
    assert.notEqual(status, 0, `CP/M halted while waiting for ${description}`);
    if (transcript.length > offset && transcript.endsWith(promptStart)) return;
  }
  throw new Error(
    `Timed out waiting for ${description}: ${
      JSON.stringify(transcript.slice(-500))
    }`,
  );
}
try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "boot");
  for (let repeat = 0; repeat < 2; repeat++) {
    for (const [name, , expected] of cases) {
      const start = transcript.length;
      assert.ok(
        machine.enqueue_serial_input(
          new TextEncoder().encode("SKREAD " + name + "\r"),
        ),
      );
      runUntilPrompt(start, name);
      const output = transcript.slice(start);
      assert.ok(output.includes(expected + "\r\n"), output);
      if (expected !== "READ OK") {
        assert.ok(!output.includes("READ OK"), output);
      }
    }
  }
  console.log(JSON.stringify(
    {
      status: "passed",
      diskPath: outputPath,
      diskBytes: disk.length,
      diskSha256: createHash("sha256").update(disk).digest("hex"),
      platform: "Triptych WASM with real CP/M 2.2 BDOS",
      imageBytes: comBytes.length,
      imageSha256: createHash("sha256").update(comBytes).digest("hex"),
      sourceWorkspaceBytes: address("CSWEND") - address("CSWORK"),
      cases: cases.length,
      repeats: 2,
      transcript,
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
