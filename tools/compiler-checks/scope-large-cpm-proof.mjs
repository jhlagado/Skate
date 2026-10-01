import assert from "node:assert/strict";
import { join } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../../tests/z80.ts";
import { validateAso } from "./aso-proof.mjs";
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
backing.fill(0xe5, 52 * 128, 52 * 128 + 64 * 32);

const countArgument = Deno.args.find((argument) =>
  argument.startsWith("--count=")
);
const count = countArgument === undefined
  ? 3000
  : Number.parseInt(countArgument.slice("--count=".length), 10);
const tailArgument = Deno.args.find((argument) =>
  argument.startsWith("--tail=")
);
const tail = tailArgument === undefined
  ? ""
  : decodeURIComponent(tailArgument.slice("--tail=".length));
const tailLengthArgument = Deno.args.find((argument) =>
  argument.startsWith("--tail-length=")
);
const tailLength = tailLengthArgument === undefined
  ? undefined
  : Number.parseInt(tailLengthArgument.slice("--tail-length=".length), 10);
if (tailLength !== undefined) {
  assert.ok(
    Number.isInteger(tailLength) && tailLength >= 0 && tailLength <= 1000,
    "tail length must be an integer from 0 through 1000",
  );
}
const expectedImageArgument = Deno.args.find((argument) =>
  argument.startsWith("--expect-image=")
);
const expectedImage = expectedImageArgument === undefined
  ? undefined
  : Number.parseInt(expectedImageArgument.slice("--expect-image=".length), 10);
const expectedComArgument = Deno.args.find((argument) =>
  argument.startsWith("--expect-com=")
);
const expectedCom = expectedComArgument === undefined
  ? undefined
  : Number.parseInt(expectedComArgument.slice("--expect-com=".length), 10);
assert.ok(
  Number.isInteger(count) && count > 0 && count <= 10000,
  "count must be an integer from 1 through 10000",
);

const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const provider = await loadAssembly("src/runtime/image.asm");
const compilerBytes = compiler.image.bytes.slice(0x0100);
const runtimeBytes = provider.image.bytes.slice(0x0100);
assert.equal(runtimeBytes.length, compiler.address("SRTLEN"));
const source = [
  Array.from({ length: count }, () => "1").join(" "),
  tailLength === undefined ? "" : `"${"a".repeat(tailLength)}"`,
  tail,
].filter((part) => part.length !== 0).join(" ");
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
disk = installCpm22File(disk, {
  name: "LARGE.SK8",
  bytes: new TextEncoder().encode(`${source}\x1a`),
  padByte: 0x1a,
});

const machine = new TriptychCpu(firmware.bootRom);
const decoder = new TextDecoder("ascii");
let transcript = "";
function runUntilPrompt(offset, description) {
  for (let attempt = 0; attempt < 2400; attempt += 1) {
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
    machine.enqueue_serial_input(new TextEncoder().encode(`${command}\r`)),
  );
  runUntilPrompt(start, description);
  const output = transcript.slice(start);
  assert.ok(output.includes(expected), JSON.stringify(output));
  return output;
}

try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  runCommand("SKATE LARGE.SK8", "COMPILED\r\n", "compile LARGE.SK8");
  const image = machine.export_drive(0);
  const com = readCpm22File(image, "LARGE.COM");
  const aso = readCpm22File(image, "LARGE.ASO");
  const measurement = validateAso(aso, com, "LARGE.COM");
  if (expectedImage !== undefined) {
    assert.equal(measurement.imageBytes, expectedImage);
  }
  if (expectedCom !== undefined) {
    assert.equal(com.length, expectedCom);
  }
  runCommand("ERA LARGE.COM", "A>", "remove LARGE.COM");
  runCommand("ERA LARGE.ASO", "A>", "remove LARGE.ASO");
  runCommand("ERA LARGE.SK8", "A>", "remove LARGE.SK8");
  console.log(JSON.stringify(
    {
      status: "passed",
      forms: count,
      tailLength: tailLength ?? 0,
      compilerBytes: compilerBytes.length,
      runtimeBytes: runtimeBytes.length,
      imageEnd: compiler.image.end,
      comBytes: com.length,
      imageBytes: measurement.imageBytes,
      asoBytes: measurement.asoBytes,
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
