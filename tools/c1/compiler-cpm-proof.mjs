import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../../tests/z80.ts";
import { parseNobj1 } from "@jhlagado/z80-tool-services";
import { linkTargetStreams, toPhysicalNobjRecords } from "../target-linker.ts";
import { SKATE_TPA_PROFILES } from "../m7-compiler.ts";
import { measureC1Budget } from "./compiler-budget.ts";
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

const compiler = await loadAssembly("src/compiler/arithmetic-compiler.asm");
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
    ["SUB.SK8", "(- 40 2)"],
    ["MUL.SK8", "(* 6 7)"],
    ["DIV.SK8", "(/ 84 2)"],
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
      ["SUB.SK8", "SUB.COM", "38\r\n"],
      ["MUL.SK8", "MUL.COM", "42\r\n"],
      ["DIV.SK8", "DIV.COM", "F16:5140\r\n"],
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
    assert.ok(generated.length > 2000, `${outputName} runtime image`);
    assert.equal(generated[0], 0x31, `${outputName} sets its private stack`);
    assert.equal(generated[1], 0x00, `${outputName} stack low byte`);
    assert.equal(generated[2], 0x80, `${outputName} stack high byte`);
    const command = outputName.slice(0, -4);
    runCommand(command, expected, `${command}.COM runtime execution`);
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
  // CP/M canonicalizes the three-character NOBJ extension as ADD.NOB.
  const objectBytes = committed(objectPhysical);
  const object = parseNobj1(objectBytes);
  assert.equal(object.layout.entrySymbolId, 1);
  assert.equal(object.contracts.length, 0);
  assert.equal(object.relocations.length, 0);
  const addCom = readCpm22File(disk, "ADD.COM");
  const addImage = addCom.slice(0, object.images[0].bytes.length);
  assert.deepEqual([...addImage], [...object.images[0].bytes]);

  // Link the checked NOBJ through the same CP/M TPA linker and execute the
  // materialized image.  No provider is needed: C1's generated image carries
  // its numeric services, so a linked COM cannot hide a dead service call.
  const linked = linkTargetStreams(
    [{ id: "native", records: toPhysicalNobjRecords(objectBytes) }],
    {
      mainObjectId: "native",
      profile: SKATE_TPA_PROFILES["cpm-64k"],
      providers: [],
    },
  );
  assert.equal(linked.objects.length, 1);
  assert.equal(linked.linked.entry?.address, 0x0100);
  assert.deepEqual([...linked.comBytes], [...addImage]);

  // Change only the embedded left operand.  Re-running the same generated
  // machine code must change 40+2 to 41+2, proving the arithmetic is runtime
  // work rather than a compiler-preformatted answer.
  const mutated = Uint8Array.from(addImage);
  // C1RLV is generated at payload offset 344; changing it proves runtime work.
  mutated[344] = 41;
  mutated[345] = 0;
  const mutatedDisk = installCpm22File(disk, {
    name: "MUTATE.COM",
    bytes: mutated,
    padByte: 0x1a,
  });
  const mutateMachine = new TriptychCpu(firmware.bootRom);
  try {
    mutateMachine.install_drive(0, mutatedDisk, true);
    const stackSentinel = new Uint8Array(0x1000).fill(0xa5);
    mutateMachine.write_ram(0x7000, stackSentinel);
    let output = "";
    for (let attempt = 0; attempt < 1800; attempt += 1) {
      const status = mutateMachine.run_slice(50_000, 500_000);
      output += decoder.decode(mutateMachine.take_serial_output());
      assert.notEqual(status, 0);
      if (output.endsWith("A>")) break;
    }
    const start = output.length;
    assert.ok(
      mutateMachine.enqueue_serial_input(new TextEncoder().encode("MUTATE\r")),
    );
    for (let attempt = 0; attempt < 1800; attempt += 1) {
      const status = mutateMachine.run_slice(50_000, 500_000);
      output += decoder.decode(mutateMachine.take_serial_output());
      assert.notEqual(status, 0);
      if (output.length > start && output.endsWith("A>")) break;
    }
    assert.ok(output.slice(start).includes("43\r\n"), output);
    // The runtime stack is capped at $8000. Leave a 256-byte live-stack band
    // and require the lower $7000..$7EFF guard to remain untouched.
    assert.ok(
      mutateMachine.read_ram(0x7000, 0x0f00).every((byte) => byte === 0xa5),
      "generated runtime stayed above the stack guard",
    );
  } finally {
    mutateMachine.free();
  }

  const linkedDisk = installCpm22File(disk, {
    name: "LINKED.COM",
    bytes: linked.comBytes,
    padByte: 0x1a,
  });
  const linkedMachine = new TriptychCpu(firmware.bootRom);
  try {
    linkedMachine.install_drive(0, linkedDisk, true);
    let output = "";
    for (let attempt = 0; attempt < 1800; attempt += 1) {
      const status = linkedMachine.run_slice(50_000, 500_000);
      output += decoder.decode(linkedMachine.take_serial_output());
      assert.notEqual(status, 0);
      if (output.endsWith("A>")) break;
    }
    const start = output.length;
    assert.ok(
      linkedMachine.enqueue_serial_input(new TextEncoder().encode("LINKED\r")),
    );
    for (let attempt = 0; attempt < 1800; attempt += 1) {
      const status = linkedMachine.run_slice(50_000, 500_000);
      output += decoder.decode(linkedMachine.take_serial_output());
      assert.notEqual(status, 0);
      if (output.length > start && output.endsWith("A>")) break;
    }
    assert.ok(output.slice(start).includes("42\r\n"), output);
  } finally {
    linkedMachine.free();
  }
  const budget = measureC1Budget(compiler.image, compiler.address, {
    sourceBytes: sourceBytes.length,
    objectBytes: objectBytes.length,
    comBytes: addImage.length,
  });
  console.log(JSON.stringify(
    {
      status: "passed",
      compilerBytes: compilerBytes.length,
      compilerCode: compiler.address("N4OBJ") - compiler.address("C1MAIN"),
      readerCode: compiler.address("REND") - compiler.address("RINIT"),
      compilerWorkspace: compiler.address("N4OBJEND") -
        compiler.address("N4OBJ"),
      coreRemaining: budget.coreRemaining,
      allocationRemaining: budget.allocationRemaining,
      staticWorkspace: budget.staticWorkspace,
      imageToStackGap: budget.imageToStackGap,
      recordBytes: budget.recordBytes,
      sourceRecords: budget.sourceRecords,
      objectRecords: budget.objectRecords,
      comRecords: budget.comRecords,
      objectBytes: objectBytes.length,
      objectSha256: createHash("sha256").update(objectBytes).digest("hex"),
      comBytes: addImage.length,
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
