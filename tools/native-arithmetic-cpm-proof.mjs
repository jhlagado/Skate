import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../tests/z80.ts";
import { encodeNobj1, parseNobj1 } from "@jhlagado/z80-tool-services";
import { linkTargetStreams, toPhysicalNobjRecords } from "./target-linker.ts";
import { SKATE_TPA_PROFILES } from "./m7-compiler.ts";
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

const compiler = await loadAssembly("tests/native-compiler.asm");
assert.equal(compiler.image.base, 0);
assert.ok(compiler.address("N4OBJEND") < 0x8000);
const compilerBytes = compiler.image.bytes.slice(0x0100);
let disk = installCpm22File(backing, {
  name: "SKATE.COM",
  bytes: compilerBytes,
  padByte: 0x1a,
});
const sourceBytes = new TextEncoder().encode("(+ 40 2)\x1a");
disk = installCpm22File(disk, {
  name: "ADD.SK8",
  bytes: sourceBytes,
  padByte: 0x1a,
});
for (
  const [name, text] of [
    ["EXACT.SK8", "(+ 2048 1)"],
    ["MIXED.SK8", "(+ 2049 0.0)"],
    ["LARGE.SK8", "(+ 30000 0)"],
    ["OVER.SK8", "(+ 32767 1)"],
    ["BAD.SK8", "(+ 1"],
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

function assertAbsent(image, name) {
  assert.throws(() => readCpm22File(image, name), /is absent/);
}

try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  runCommand("SKATE ADD.SK8", "COMPILED\r\n", "SKATE compilation");
  for (
    const [sourceName, outputName, expected] of [
      ["EXACT.SK8", "EXACT.COM", "2049\r\n"],
      ["MIXED.SK8", "MIXED.COM", "F16:6800\r\n"],
      ["LARGE.SK8", "LARGE.COM", "30000\r\n"],
    ]
  ) {
    runCommand(
      "SKATE " + sourceName,
      "COMPILED\r\n",
      "SKATE " + sourceName,
    );
    const image = machine.export_drive(0);
    const generated = readCpm22File(image, outputName);
    assert.ok(generated.includes(0x24), outputName);
    const marker = new TextDecoder("ascii").decode(generated);
    assert.ok(marker.includes(expected), marker);
  }
  runCommand("SKATE OVER.SK8", "COMPILE ERROR\r\n", "overflow rejection");
  assertAbsent(machine.export_drive(0), "OVER.COM");
  assertAbsent(machine.export_drive(0), "OVER.NOB");
  runCommand("SKATE BAD.SK8", "COMPILE ERROR\r\n", "malformed rejection");
  assertAbsent(machine.export_drive(0), "BAD.COM");
  assertAbsent(machine.export_drive(0), "BAD.NOB");
  runCommand(
    "SKATE MISSING.SK8",
    "SOURCE I/O ERROR\r\n",
    "source I/O rejection",
  );
  const objectPhysical = readCpm22File(
    disk = machine.export_drive(0),
    "ADD.NOB",
  );
  // The command uses the three-character NOBJ extension; the CP/M helper
  // canonicalizes it as ADD.NOB because CP/M permits only three letters.
  const objectBytes = committed(objectPhysical);
  const object = parseNobj1(objectBytes);
  assert.equal(object.layout.entrySymbolId, 1);
  assert.equal(object.relocations.length, 1);
  const providerBytes = encodeNobj1({
    begin: { targetId: 1 },
    contracts: [{
      id: 1,
      key: "org.skate.runtime",
      majorVersion: 2,
      minorVersion: 0,
      data: new Uint8Array(4),
    }],
    regions: [{
      id: 1,
      addressSpaceKey: "z80.cpu",
      storageKey: "cpm.ram",
      base: 0x0100,
      capacity: 0xe300,
      imageFill: 0,
      permissions: 7,
      banked: false,
    }],
    sections: [{
      id: 1,
      storageKind: 1,
      permissions: 7,
      alignment: 1,
      length: 1,
      runRegionId: 1,
      runPlacement: "fixed",
      runOffset: 0x300,
      loadPlacement: "same",
      loadRegionId: 1,
      loadOffset: 0,
      fill: 0,
    }],
    ranges: [],
    images: [{ sectionId: 1, offset: 0, bytes: Uint8Array.of(0xc9) }],
    patches: [],
    symbols: [{
      id: 1,
      binding: "local",
      valueKind: 1,
      sectionId: 1,
      offset: 0,
    }],
    relocations: [],
    metadata: [],
    layout: { mode: "module", entrySymbolId: 0 },
  });
  const linked = linkTargetStreams(
    [
      { id: "native", records: toPhysicalNobjRecords(objectBytes) },
      { id: "provider", records: toPhysicalNobjRecords(providerBytes) },
    ],
    {
      mainObjectId: "native",
      profile: SKATE_TPA_PROFILES["cpm-64k"],
      providers: [{
        id: "native-provider",
        objectId: "provider",
        supports: [{
          key: "org.skate.runtime",
          majorVersion: 2,
          minorVersion: 0,
        }],
        services: [{
          contract: {
            key: "org.skate.runtime",
            majorVersion: 2,
            minorVersion: 0,
          },
          key: "numeric.classify",
          symbolId: 1,
        }],
      }],
    },
  );
  assert.equal(linked.objects.length, 2);
  assert.equal(linked.linked.entry?.address, 0x0100);
  assert.equal(linked.comBytes[4], 0x00);
  assert.equal(linked.comBytes[5], 0x04);
  assert.deepEqual(
    [...linked.comBytes.slice(7, 32)],
    [...object.images[0].bytes.slice(7, 32)],
  );
  runCommand("ADD", "42\r\n", "generated ADD.COM");
  const remounted = machine.export_drive(0);
  const firstRun = readCpm22File(remounted, "ADD.COM");
  const remount = new TriptychCpu(firmware.bootRom);
  try {
    remount.install_drive(0, remounted, true);
    let second = "";
    for (let slice = 0; slice < 1800; slice += 1) {
      const status = remount.run_slice(50_000, 500_000);
      second += decoder.decode(remount.take_serial_output());
      assert.notEqual(status, 0);
      if (second.endsWith("A>")) break;
    }
    const start = second.length;
    assert.ok(remount.enqueue_serial_input(new TextEncoder().encode("ADD\r")));
    for (let slice = 0; slice < 1800; slice += 1) {
      const status = remount.run_slice(50_000, 500_000);
      second += decoder.decode(remount.take_serial_output());
      assert.notEqual(status, 0);
      if (second.length > start && second.endsWith("A>")) break;
    }
    assert.ok(second.slice(start).includes("42\r\n"), second);
  } finally {
    remount.free();
  }
  console.log(JSON.stringify(
    {
      status: "passed",
      compilerBytes: compilerBytes.length,
      compilerCode: compiler.address("N4OBJ") - compiler.address("N4MAIN"),
      readerCode: compiler.address("REND") - compiler.address("RINIT"),
      compilerWorkspace: compiler.address("N4OBJEND") -
        compiler.address("N4OBJ"),
      objectBytes: objectBytes.length,
      objectSha256: createHash("sha256").update(objectBytes).digest("hex"),
      comBytes: firstRun.length,
      transcript,
      platform: "Triptych WASM with CP/M 2.2",
    },
    null,
    2,
  ));
} finally {
  machine.free();
}

function committed(bytes) {
  let cursor = 0;
  while (cursor + 3 <= bytes.length) {
    const kind = bytes[cursor];
    const length = bytes[cursor + 1] | bytes[cursor + 2] << 8;
    const end = cursor + 3 + length;
    if (end > bytes.length) break;
    if (kind === 12) return bytes.slice(0, end);
    cursor = end;
  }
  throw new Error("generated NOBJ has no complete COMMIT");
}
