import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../../tests/z80.ts";
import { assembleTriptychCpuFirmware } from "../../../triptych/tools/cpm22-native-image.mjs";
import {
  installCpm22File,
  readCpm22File,
} from "../../../triptych/tools/lib/cpm22-disk.mjs";

const skateRoot = fileURLToPath(new URL("../../", import.meta.url));
const imageArgument = Deno.args.find((argument) =>
  argument.startsWith("--image=")
);
const imagePath = imageArgument
  ? resolve(skateRoot, imageArgument.slice("--image=".length))
  : null;
const triptychRoot = fileURLToPath(
  new URL("../../../triptych/", import.meta.url),
);
const require = createRequire(import.meta.url);
const { TriptychCpu } = require(
  join(triptychRoot, "dist", "wasm", "triptych_host_wasm.js"),
);

const encoder = new TextEncoder();
const decoder = new TextDecoder("ascii");
const sourceRoot = join(skateRoot, "examples", "large-package");
const partNames = Array.from(
  { length: 16 },
  (_, index) => `PART${String(index + 1).padStart(2, "0")}.SK8`,
);
const releaseManifest = "RELEASE.SKM";

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function readWord(machine, address) {
  const bytes = machine.read_ram(address, 2);
  return bytes[0] | bytes[1] << 8;
}

function makeSystemDisk(firmware, sourceDisk) {
  const system = Uint8Array.from(sourceDisk);
  system.set(firmware.ccp, 0x0000);
  system.set(firmware.bdos, 0x0800);
  system.set(firmware.bios, 0x1600);
  const disk = new Uint8Array(Math.ceil(system.length / 512) * 512);
  disk.set(system);
  return disk;
}

function committedObject(bytes, name) {
  let cursor = 0;
  while (cursor + 3 <= bytes.length) {
    const kind = bytes[cursor];
    const length = bytes[cursor + 1] | bytes[cursor + 2] << 8;
    const end = cursor + 3 + length;
    if (end > bytes.length) break;
    if (kind === 12) {
      for (const padding of bytes.slice(end)) {
        assert.ok(
          padding === 0 || padding === 0x1a,
          `${name}: non-padding after COMMIT`,
        );
      }
      return bytes.slice(0, end);
    }
    cursor = end;
  }
  throw new Error(`${name}: missing NOBJ COMMIT`);
}

function validateObject(object, com, name) {
  assert.deepEqual(
    [...object.slice(3, 7)],
    [0x4e, 0x4f, 0x42, 0x4a],
    `${name}: wrong NOBJ signature`,
  );
  let cursor = 70;
  let image = null;
  const kinds = [];
  while (cursor + 3 <= object.length) {
    const kind = object[cursor];
    const length = object[cursor + 1] | object[cursor + 2] << 8;
    const end = cursor + 3 + length;
    assert.ok(end <= object.length, `${name}: truncated NOBJ record`);
    kinds.push(kind);
    if (kind === 6) image = object.slice(cursor + 9, end);
    cursor = end;
    if (kind === 12) break;
  }
  assert.ok(kinds.includes(6), `${name}: missing IMAGE record`);
  assert.ok(kinds.includes(8), `${name}: missing symbol record`);
  assert.ok(kinds.includes(11), `${name}: missing relocation record`);
  assert.equal(kinds.at(-1), 12, `${name}: missing COMMIT record`);
  assert.ok(image, `${name}: missing image payload`);
  assert.deepEqual(
    [...image],
    [...com.slice(0, image.length)],
    `${name}: NOBJ image differs from COM`,
  );
  for (const padding of com.slice(image.length)) {
    assert.ok(
      padding === 0 || padding === 0x1a,
      `${name}: non-padding after COM image`,
    );
  }
}

function directoryFiles(image) {
  const directoryOffset = 52 * 128;
  const files = [];
  for (let index = 0; index < 64; index += 1) {
    const offset = directoryOffset + index * 32;
    if (image[offset] !== 0) continue;
    const raw = String.fromCharCode(...image.slice(offset + 1, offset + 12));
    const base = raw.slice(0, 8).trimEnd();
    const extension = raw.slice(8).trimEnd();
    const name = extension ? `${base}.${extension}` : base;
    let blocks = 0;
    for (let byte = 16; byte < 32; byte += 1) {
      if (image[offset + byte] !== 0) blocks += 1;
    }
    files.push({ name, blocks });
  }
  return files;
}

function diskStats(image) {
  const files = directoryFiles(image);
  const usedBlocks = files.reduce((sum, file) => sum + file.blocks, 0);
  return {
    bytes: image.length,
    files: files.length,
    usedBlocks,
    freeBlocks: 241 - usedBlocks,
  };
}

function newMachine(firmware, image) {
  const machine = new TriptychCpu(firmware.bootRom);
  machine.install_drive(0, image, true);
  return machine;
}

function session(machine) {
  let transcript = "";
  let decoderSteps = 0;
  function runUntilPrompt(offset, description) {
    let instructions = 0n;
    let tstates = 0n;
    const limit = description.startsWith("compile") ? 12000 : 8000;
    for (let attempt = 0; attempt < limit; attempt += 1) {
      const status = machine.run_slice(50_000, 500_000);
      instructions += machine.last_steps();
      tstates += machine.last_tstates();
      decoderSteps += 1;
      transcript += decoder.decode(machine.take_serial_output());
      assert.notEqual(status, 0, `CP/M halted during ${description}`);
      if (transcript.length > offset && transcript.endsWith("A>")) {
        return { instructions: Number(instructions), tstates: Number(tstates) };
      }
    }
    throw new Error(
      `Timed out during ${description}: ${
        JSON.stringify(transcript.slice(-500))
      }`,
    );
  }
  function command(command, expected, description) {
    const start = transcript.length;
    assert.ok(machine.enqueue_serial_input(encoder.encode(command + "\r")));
    const metrics = runUntilPrompt(start, description);
    const output = transcript.slice(start);
    assert.ok(
      output.includes(expected),
      `${description}: expected ${JSON.stringify(expected)} in ${
        JSON.stringify(output)
      }`,
    );
    return { output, ...metrics };
  }
  return {
    boot: () => runUntilPrompt(0, "boot"),
    command,
    get decoderSteps() {
      return decoderSteps;
    },
  };
}

async function addSources(disk) {
  let result = installCpm22File(disk, {
    name: releaseManifest,
    bytes: Uint8Array.from([
      ...(await Deno.readFile(join(sourceRoot, "release.skm"))),
      0x1a,
    ]),
    padByte: 0x1a,
  });
  for (const name of partNames) {
    const path = join(sourceRoot, name.toLowerCase());
    const bytes = await Deno.readFile(path);
    result = installCpm22File(result, {
      name,
      bytes: Uint8Array.from([...bytes, 0x1a]),
      padByte: 0x1a,
    });
  }
  return result;
}

const firmware = await assembleTriptychCpuFirmware(triptychRoot);
const sourceDisk = await Deno.readFile(
  join(triptychRoot, "third_party", "cpm22", "cpm22.img"),
);
const compiler = await loadAssembly("src/compiler/scope-control-compiler.asm");
const provider = await loadAssembly(
  "src/compiler/scope-control-runtime-image.asm",
);
const compilerBytes = compiler.image.bytes.slice(0x0100);
const runtimeImage = provider.image.bytes.slice(0x0100);
const runtimeLength = runtimeImage.length;
assert.equal(runtimeLength, compiler.address("SRTLEN"));
assert.ok(
  compilerBytes.length < 0x10000,
  "compiler does not fit the CP/M address space",
);

let disk = makeSystemDisk(firmware, sourceDisk);
disk = installCpm22File(disk, {
  name: "SKATE.COM",
  bytes: compilerBytes,
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "SKATE.RT",
  bytes: runtimeImage,
  padByte: 0x1a,
});
disk = await addSources(disk);

const sourceBytes = await Promise.all(
  partNames.map((name) => Deno.readFile(join(sourceRoot, name.toLowerCase()))),
);
const sourceTotal = sourceBytes.reduce((sum, bytes) => sum + bytes.length, 0);
assert.ok(sourceTotal >= 8192, `release source is only ${sourceTotal} bytes`);

const heapPointerAddress = provider.address("SRTHEAPP");
const lowStackAddress = provider.address("SRTLOWSP");
const records = {};
let stableImage = disk;
let releaseImage = null;
let machine = newMachine(firmware, disk);
try {
  const first = session(machine);
  first.boot();
  const compile = first.command(
    `SKATE ${releaseManifest}`,
    "COMPILED\r\n",
    "compile the release source",
  );
  stableImage = machine.export_drive(0);
  const com = readCpm22File(stableImage, "RELEASE.COM");
  const objectPhysical = readCpm22File(stableImage, "RELEASE.NOB");
  const object = committedObject(objectPhysical, "RELEASE.NOB");
  validateObject(object, com, "RELEASE.NOB");
  assert.equal(com[0], 0x31, "generated program did not set its private stack");
  const run = first.command("RELEASE", "256\r\n", "run the release program");
  const lowSp = readWord(machine, lowStackAddress);
  const heapEnd = readWord(machine, heapPointerAddress);
  assert.ok(lowSp >= 0xd400, "generated program crossed the stack guard");
  assert.ok(heapEnd < lowSp, "heap and native stack collided");
  releaseImage = Uint8Array.from(stableImage);
  records.initial = {
    sourceBytes: sourceTotal,
    comBytes: com.length,
    nobjBytes: objectPhysical.length,
    compile,
    run,
    lowSp,
    heapEnd,
    comSha256: sha256(com),
    nobjSha256: sha256(object),
  };

  machine.free();
  machine = newMachine(firmware, stableImage);
  const remounted = session(machine);
  remounted.boot();
  records.remount = remounted.command(
    "RELEASE",
    "256\r\n",
    "run the release program after remount",
  );

  const stableCom = readCpm22File(stableImage, "RELEASE.COM");
  const stableObject = readCpm22File(stableImage, "RELEASE.NOB");
  const fullDisk = installCpm22File(stableImage, {
    name: "FULL.BIN",
    bytes: new Uint8Array(diskStats(stableImage).freeBlocks * 1024).fill(0x1a),
    padByte: 0x1a,
  });
  const fullMachine = newMachine(firmware, fullDisk);
  try {
    const full = session(fullMachine);
    full.boot();
    records.diskFull = full.command(
      `SKATE ${releaseManifest}`,
      "OUTPUT ERROR\r\n",
      "reject a full-disk publication",
    );
    const afterFull = fullMachine.export_drive(0);
    assert.deepEqual(
      [...readCpm22File(afterFull, "RELEASE.COM")],
      [...stableCom],
      "full-disk failure damaged the previous COM",
    );
    assert.deepEqual(
      [...readCpm22File(afterFull, "RELEASE.NOB")],
      [...stableObject],
      "full-disk failure damaged the previous NOBJ",
    );
  } finally {
    fullMachine.free();
  }

  const failedPart = installCpm22File(stableImage, {
    name: "PART08.SK8",
    bytes: encoder.encode("(let ((value 1 2)) value)\x1a"),
    padByte: 0x1a,
  });
  assert.equal(
    decoder.decode(readCpm22File(failedPart, "PART08.SK8").slice(0, 26)),
    "(let ((value 1 2)) value)\x1a",
    "failed source was not installed",
  );
  machine.free();
  machine = newMachine(firmware, failedPart);
  const failed = session(machine);
  failed.boot();
  records.compileFailure = failed.command(
    `SKATE ${releaseManifest}`,
    "EXPECT\r\n",
    "reject an invalid release source",
  );
  const afterCompileFailure = machine.export_drive(0);
  assert.deepEqual(
    [...readCpm22File(afterCompileFailure, "RELEASE.COM")],
    [...stableCom],
    "compile failure damaged the previous COM",
  );
  assert.deepEqual(
    [...readCpm22File(afterCompileFailure, "RELEASE.NOB")],
    [...stableObject],
    "compile failure damaged the previous NOBJ",
  );

  const reopenedImage = machine.export_drive(0);
  machine.free();
  machine = newMachine(firmware, reopenedImage);
  const reopened = session(machine);
  reopened.boot();
  records.reopened = reopened.command(
    "RELEASE",
    "256\r\n",
    "run the preserved release after remount",
  );
  stableImage = reopenedImage;
} finally {
  machine.free();
}

if (imagePath) {
  assert.ok(releaseImage, "release image was not produced");
  await Deno.mkdir(dirname(imagePath), { recursive: true });
  await Deno.writeFile(imagePath, releaseImage);
}

console.log(JSON.stringify(
  {
    status: "passed",
    compilerBytes: compilerBytes.length,
    runtimeBytes: runtimeLength,
    sourceBytes: sourceTotal,
    outputBytes: records.initial.comBytes,
    objectBytes: records.initial.nobjBytes,
    disk: diskStats(stableImage),
    ...(imagePath
      ? {
        image: {
          path: imagePath,
          bytes: releaseImage.length,
          sha256: sha256(releaseImage),
          disk: diskStats(releaseImage),
        },
      }
      : {}),
    records,
  },
  null,
  2,
));
