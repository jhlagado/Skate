import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../../tests/z80.ts";
import { validateAso } from "./aso-proof.mjs";
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
const { CpmDisk, TriptychCpu } = require(
  join(triptychRoot, "dist", "wasm", "triptych_host_wasm.js"),
);

const encoder = new TextEncoder();
const decoder = new TextDecoder("ascii");
const sourceRoot = join(skateRoot, "tests", "fixtures", "release-source");
const partNames = Array.from(
  { length: 16 },
  (_, index) => `PART${String(index + 1).padStart(2, "0")}.SK8`,
);
const releaseRoot = "RELEASE.SK8";

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
  // Qualification installs its own files; bundled examples consume spool space.
  disk.fill(0xe5, 52 * 128, 52 * 128 + 64 * 32);
  return disk;
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
    name: releaseRoot,
    bytes: Uint8Array.from([
      ...(await Deno.readFile(join(sourceRoot, "release.sk8"))),
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

async function cpmText(path) {
  const text = await Deno.readTextFile(path);
  return encoder.encode(text.replace(/\r?\n/g, "\r\n"));
}

/** Build and mount the exact two-MiB filesystem used by the Triptych profile. */
async function buildHostedReleaseImage(
  sourceDisk,
  compilerBytes,
  runtimeImage,
) {
  const qualified = {
    system: await Deno.readFile(
      join(
        triptychRoot,
        "dist",
        "wasm-browser",
        "system-triptych-cpm-2m-n04-v1.bin",
      ),
    ),
    bootstrap: await Deno.readFile(
      join(
        triptychRoot,
        "dist",
        "wasm-browser",
        "bootstrap-triptych-cpm-2m-n04-v1.bin",
      ),
    ),
    descriptor: { residentProfile: "triptych-cpu-v0.1-2m-n04" },
  };
  assert.equal(qualified.system.length, 16384);
  assert.equal(qualified.bootstrap.length, 256);
  assert.equal(
    sha256(qualified.system),
    "61dd21e3f89be888e3530ec3b414691c343f7ad2c29aa15fac4ff2510c3a5a3e",
  );
  assert.equal(
    sha256(qualified.bootstrap),
    "54c6bfd356b4b42f8c51f3b85777a9d2be7aa680945335783c4dd7a6dae8921e",
  );
  const files = [
    { name: "SKATE.COM", bytes: Uint8Array.from(compilerBytes) },
    { name: "SKATE.RT", bytes: Uint8Array.from(runtimeImage) },
    { name: "EDIT.COM", bytes: readCpm22File(sourceDisk, "EDIT.COM") },
    {
      name: "README.TXT",
      bytes: await cpmText(
        join(skateRoot, "examples", "applications", "readme.txt"),
      ),
    },
  ];
  for (
    const name of [
      "account.sk8",
      "advent.sk8",
      "house.sk8",
      "receipt.sk8",
      "route.sk8",
    ]
  ) {
    files.push({
      name: name.toUpperCase(),
      bytes: await cpmText(join(skateRoot, "examples", "applications", name)),
    });
  }
  // The multi-file source package belongs to the qualification run above.
  // The published disk carries the useful examples instead of test fixtures.

  const disk = CpmDisk.create_two_mib();
  try {
    for (const file of files) disk.add_import(file.name, file.bytes);
    const image = Uint8Array.from(disk.export_candidate());
    assert.equal(image.length, 2 * 1024 * 1024);
    image.set(qualified.system, 0);
    const mounted = new CpmDisk(image);
    try {
      assert.equal(mounted.geometry_id(), "triptych-cpm-2m-v1");
      assert.deepEqual(
        mounted.file_names().sort(),
        files.map(({ name }) => CpmDisk.canonical_name(name)).sort(),
      );
      return {
        image,
        qualified,
        files,
        freeBytes: mounted.free_bytes(),
        freeDirectoryEntries: mounted.free_directory_entries(),
      };
    } finally {
      mounted.free();
    }
  } finally {
    disk.free();
  }
}

const firmware = await assembleTriptychCpuFirmware(triptychRoot);
const sourceDisk = await Deno.readFile(
  join(triptychRoot, "third_party", "cpm22", "cpm22.img"),
);
const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const provider = await loadAssembly(
  "src/runtime/image.asm",
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
    `SKATE ${releaseRoot}`,
    "COMPILED\r\n",
    "compile the release source",
  );
  stableImage = machine.export_drive(0);
  const com = readCpm22File(stableImage, "RELEASE.COM");
  const aso = readCpm22File(stableImage, "RELEASE.ASO");
  const asoLengths = validateAso(aso, com, "RELEASE");
  assert.equal(com[0], 0x31, "generated program did not set its private stack");
  const run = first.command("RELEASE", "95\r\n", "run the release program");
  const lowSp = readWord(machine, lowStackAddress);
  const heapEnd = readWord(machine, heapPointerAddress);
  assert.ok(lowSp >= 0xd400, "generated program crossed the stack guard");
  assert.ok(heapEnd < lowSp, "heap and native stack collided");
  releaseImage = Uint8Array.from(stableImage);
  records.initial = {
    sourceBytes: sourceTotal,
    comBytes: com.length,
    comImageBytes: asoLengths.imageBytes,
    asoBytes: asoLengths.asoBytes,
    compile,
    run,
    lowSp,
    heapEnd,
    comSha256: sha256(com),
    asoSha256: sha256(aso),
  };

  machine.free();
  machine = newMachine(firmware, stableImage);
  const remounted = session(machine);
  remounted.boot();
  records.remount = remounted.command(
    "RELEASE",
    "95\r\n",
    "run the release program after remount",
  );

  const stableCom = readCpm22File(stableImage, "RELEASE.COM");
  const stableAso = readCpm22File(stableImage, "RELEASE.ASO");
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
      `SKATE ${releaseRoot}`,
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
      [...readCpm22File(afterFull, "RELEASE.ASO")],
      [...stableAso],
      "full-disk failure damaged the previous ASO",
    );
  } finally {
    fullMachine.free();
  }

  assert.ok(
    diskStats(stableImage).freeBlocks >=
      Math.ceil(stableCom.length / 1024) + Math.ceil(stableAso.length / 1024),
    "syntax-error fixture needs space for a replacement COM and ASO",
  );
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
    `SKATE ${releaseRoot}`,
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
    [...readCpm22File(afterCompileFailure, "RELEASE.ASO")],
    [...stableAso],
    "compile failure damaged the previous ASO",
  );

  const reopenedImage = machine.export_drive(0);
  machine.free();
  machine = newMachine(firmware, reopenedImage);
  const reopened = session(machine);
  reopened.boot();
  records.reopened = reopened.command(
    "RELEASE",
    "95\r\n",
    "run the preserved release after remount",
  );
  stableImage = reopenedImage;
} finally {
  machine.free();
}

let publishedImage = null;
let hostedRecords = null;
if (imagePath) {
  assert.ok(releaseImage, "release image was not produced");
  await Deno.mkdir(dirname(imagePath), { recursive: true });
  const hosted = await buildHostedReleaseImage(
    sourceDisk,
    compilerBytes,
    runtimeImage,
  );
  const hostedMachine = newMachine(
    { bootRom: hosted.qualified.bootstrap },
    hosted.image,
  );
  try {
    const hostedSession = session(hostedMachine);
    hostedSession.boot();
    const compile = hostedSession.command(
      "SKATE RECEIPT.SK8",
      "COMPILED\r\n",
      "compile the hosted example",
    );
    const run = hostedSession.command(
      "RECEIPT",
      "Total (cents): 620\r\n",
      "run the hosted example",
    );
    hostedRecords = {
      profile: hosted.qualified.descriptor.residentProfile,
      geometry: "triptych-cpm-2m-v1",
      files: hosted.files.map(({ name }) => name),
      freeBytes: hosted.freeBytes,
      freeDirectoryEntries: hosted.freeDirectoryEntries,
      compile,
      run,
    };
  } finally {
    hostedMachine.free();
  }
  publishedImage = hosted.image;
  await Deno.writeFile(imagePath, publishedImage);
}

console.log(JSON.stringify(
  {
    status: "passed",
    compilerBytes: compilerBytes.length,
    runtimeBytes: runtimeLength,
    sourceBytes: sourceTotal,
    outputBytes: records.initial.comBytes,
    outputImageBytes: records.initial.comImageBytes,
    asoBytes: records.initial.asoBytes,
    disk: diskStats(stableImage),
    ...(imagePath
      ? {
        image: {
          path: imagePath,
          bytes: publishedImage.length,
          sha256: sha256(publishedImage),
          guestRecords: hostedRecords,
        },
      }
      : {}),
    records,
  },
  null,
  2,
));
