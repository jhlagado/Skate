import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../tests/z80.ts";
import { parseNobj1 } from "@jhlagado/z80-tool-services";
import { assembleTriptychCpuFirmware } from "../../triptych/tools/cpm22-native-image.mjs";
import {
  installCpm22File,
  readCpm22File,
} from "../../triptych/tools/lib/cpm22-disk.mjs";

const skateRoot = fileURLToPath(new URL("../", import.meta.url));
const triptychRoot = fileURLToPath(new URL("../../triptych/", import.meta.url));
const verifyManifest = Deno.args.includes("--verify-manifest");
const outputPath = Deno.args.find((arg) => !arg.startsWith("--")) ??
  join(skateRoot, "build", "skate-cpm.img");
const require = createRequire(import.meta.url);
const { TriptychCpu } = require(
  join(triptychRoot, "dist", "wasm", "triptych_host_wasm.js"),
);

const productSources = [
  ["MAKEADD.SK8", "examples/make-adder.sk8"],
  ["COUNTER.SK8", "examples/shared-counter.sk8"],
  ["RATIONAL.SK8", "examples/rational.sk8"],
  ["LISTS.SK8", "examples/lists.sk8"],
  ["HORDER.SK8", "examples/higher-order-sum.sk8"],
  ["MUTTAIL.SK8", "examples/mutual-tail.sk8"],
  ["ROOT.SK8", "examples/root.sk8"],
  ["PACKAGE.SKM", "examples/package.skm"],
  ["CORE.SK8", "examples/package-core.sk8"],
  ["APP.SK8", "examples/package-app.sk8"],
  ["DIRECT.SK8", "examples/package-direct.sk8"],
];
const helpText = [
  "SKATE - Scheme for the Z80",
  "",
  "  SKATE FILE.SK8  compile a source file",
  "  FILE            run the resulting COM file",
  "",
  "The compiler publishes FILE.COM and FILE.NOB together.",
  "",
].join("\r\n");

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
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
          padding === 0x1a || padding === 0,
          `${name} has non-padding bytes after COMMIT`,
        );
      }
      return bytes.slice(0, end);
    }
    cursor = end;
  }
  throw new Error(`${name} has no complete NOBJ COMMIT record`);
}

function inspectObject(image, name) {
  const physical = readCpm22File(image, name);
  const committed = committedObject(physical, name);
  const object = parseNobj1(committed);
  assert.ok(object.sections.length > 0, `${name} has no sections`);
  return {
    physicalBytes: physical.length,
    committedBytes: committed.length,
    sha256: sha256(committed),
    sections: object.sections.length,
    images: object.images.reduce(
      (total, image) => total + image.bytes.length,
      0,
    ),
  };
}

function inspectEveryGeneratedObject(image) {
  const objects = directoryFiles(image)
    .filter(({ name }) => name.endsWith(".NOB"));
  assert.ok(objects.length > 0, "product generated no NOBJ files");
  for (const { name } of objects) inspectObject(image, name);
  return objects.length;
}

function directoryFiles(image) {
  const directoryOffset = 52 * 128;
  const names = [];
  for (let index = 0; index < 64; index += 1) {
    const offset = directoryOffset + index * 32;
    if (image[offset] !== 0) continue;
    const rawName = String.fromCharCode(
      ...image.slice(offset + 1, offset + 12),
    );
    const base = rawName.slice(0, 8).trimEnd();
    const extension = rawName.slice(8).trimEnd();
    const name = extension === "" ? base : `${base}.${extension}`;
    let blocks = 0;
    for (let byte = 16; byte < 32; byte += 1) {
      if (image[offset + byte] !== 0) blocks += 1;
    }
    names.push({
      name: name.trimEnd(),
      blocks,
      bytes: readCpm22File(image, name).length,
    });
  }
  return names;
}

function diskStats(image) {
  const files = directoryFiles(image);
  const usedBlocks = files.reduce((total, file) => total + file.blocks, 0);
  return {
    bytes: image.length,
    sha256: sha256(image),
    files: files.length,
    usedBlocks,
    freeBlocks: 241 - usedBlocks,
    directory: files,
  };
}

async function createProductImage(compilerBytes) {
  const firmware = await assembleTriptychCpuFirmware(triptychRoot);
  const sourceDisk = await Deno.readFile(
    join(triptychRoot, "third_party", "cpm22", "cpm22.img"),
  );
  const systemDisk = Uint8Array.from(sourceDisk);
  systemDisk.set(firmware.ccp, 0x0000);
  systemDisk.set(firmware.bdos, 0x0800);
  systemDisk.set(firmware.bios, 0x1600);
  const image = new Uint8Array(Math.ceil(systemDisk.length / 512) * 512);
  image.set(systemDisk);
  let product = installCpm22File(image, {
    name: "SKATE.COM",
    bytes: compilerBytes,
    padByte: 0x1a,
  });
  product = installCpm22File(product, {
    name: "README.TXT",
    bytes: new TextEncoder().encode(helpText + "\x1a"),
    padByte: 0x1a,
  });
  for (const [name, relativePath] of productSources) {
    const bytes = await Deno.readFile(join(skateRoot, relativePath));
    product = installCpm22File(product, {
      name,
      bytes: Uint8Array.from([...bytes, 0x1a]),
      padByte: 0x1a,
    });
  }
  return product;
}

function newMachine(firmware, image) {
  const machine = new TriptychCpu(firmware.bootRom);
  machine.install_drive(0, image, true);
  return machine;
}

function session(machine) {
  const decoder = new TextDecoder("ascii");
  let transcript = "";
  function runUntilPrompt(offset, description) {
    let instructions = 0n;
    let tstates = 0n;
    for (let slice = 0; slice < 3000; slice += 1) {
      const status = machine.run_slice(50_000, 500_000);
      instructions += machine.last_steps();
      tstates += machine.last_tstates();
      transcript += decoder.decode(machine.take_serial_output());
      assert.notEqual(
        status,
        0,
        `CP/M halted while waiting for ${description}`,
      );
      if (transcript.length > offset && transcript.endsWith("A>")) {
        return { instructions, tstates };
      }
    }
    throw new Error(
      `Timed out waiting for ${description}: ${transcript.slice(-500)}`,
    );
  }
  function command(command, expected, description) {
    const start = transcript.length;
    assert.ok(
      machine.enqueue_serial_input(new TextEncoder().encode(command + "\r")),
    );
    const metrics = runUntilPrompt(start, description);
    const output = transcript.slice(start);
    assert.ok(output.includes(expected), JSON.stringify(output));
    return {
      output,
      instructions: Number(metrics.instructions),
      tstates: Number(metrics.tstates),
    };
  }
  return {
    boot: () => runUntilPrompt(0, "the boot prompt"),
    command,
  };
}

const compiler = await loadAssembly("compiler/skate.asm");
assert.equal(compiler.image.base, 0);
assert.equal(compiler.address("N6MAIN"), 0x0100);
assert.ok(compiler.address("N4OBJEND") < 0xa000);
const compilerBytes = compiler.image.bytes.slice(0x0100);
const image = await createProductImage(compilerBytes);
await Deno.mkdir(dirname(outputPath), { recursive: true });
await Deno.writeFile(outputPath, image);

const firmware = await assembleTriptychCpuFirmware(triptychRoot);
const records = [];
let machine = newMachine(firmware, image);
try {
  const first = session(machine);
  first.boot();
  const dir = first.command("DIR", "SKATE    COM", "the product directory");
  const help = first.command(
    "TYPE README.TXT",
    "SKATE - Scheme",
    "the usage file",
  );
  const compile = first.command(
    "SKATE MAKEADD.SK8",
    "COMPILED\r\n",
    "the first product compilation",
  );
  const makeaddObject = inspectObject(
    machine.export_drive(0),
    "MAKEADD.NOB",
  );
  const run = first.command("MAKEADD", "12\r\n", "the first generated program");
  const rootCompile = first.command(
    "SKATE ROOT.SK8",
    "COMPILED\r\n",
    "the binary16 product compilation",
  );
  const rootObject = inspectObject(machine.export_drive(0), "ROOT.NOB");
  const rootRun = first.command(
    "ROOT",
    "F16:3DA6\r\n",
    "the binary16 generated program",
  );
  const packageCompile = first.command(
    "SKATE PACKAGE.SKM",
    "COMPILED\r\n",
    "the ordered source package compilation",
  );
  const packageObject = inspectObject(machine.export_drive(0), "PACKAGE.NOB");
  const packageRun = first.command(
    "PACKAGE",
    "42\r\n",
    "the ordered source package execution",
  );
  const packageCom = readCpm22File(machine.export_drive(0), "PACKAGE.COM");
  const packageNob = committedObject(
    readCpm22File(machine.export_drive(0), "PACKAGE.NOB"),
    "PACKAGE.NOB",
  );
  const directCompile = first.command(
    "SKATE DIRECT.SK8",
    "COMPILED\r\n",
    "the direct concatenation compilation",
  );
  const directObject = inspectObject(machine.export_drive(0), "DIRECT.NOB");
  const directRun = first.command(
    "DIRECT",
    "42\r\n",
    "the direct concatenation execution",
  );
  assert.deepEqual(
    [...readCpm22File(machine.export_drive(0), "DIRECT.COM")],
    [...packageCom],
    "ordered and direct source produce the same COM",
  );
  assert.deepEqual(
    [...committedObject(
      readCpm22File(machine.export_drive(0), "DIRECT.NOB"),
      "DIRECT.NOB",
    )],
    [...packageNob],
    "ordered and direct source produce the same NOBJ",
  );
  const packageRemountMachine = newMachine(firmware, machine.export_drive(0));
  const packageRemountSession = session(packageRemountMachine);
  packageRemountSession.boot();
  const packageRepeat = packageRemountSession.command(
    "PACKAGE",
    "42\r\n",
    "the remounted ordered source package",
  );
  packageRemountMachine.free();
  const stableImage = machine.export_drive(0);
  // Parse every generated object before the report is accepted. The selected
  // examples below retain their detailed records for the manifest, while this
  // sweep prevents an uninspected NOBJ from hiding in the product directory.
  inspectEveryGeneratedObject(stableImage);
  const stableCom = readCpm22File(stableImage, "MAKEADD.COM");
  const stableObject = readCpm22File(stableImage, "MAKEADD.NOB");
  const fullDisk = installCpm22File(stableImage, {
    name: "FILL.BIN",
    bytes: new Uint8Array(diskStats(stableImage).freeBlocks * 1024).fill(0x1a),
    padByte: 0x1a,
  });
  const fullMachine = newMachine(firmware, fullDisk);
  const fullSession = session(fullMachine);
  fullSession.boot();
  const outputFailure = fullSession.command(
    "SKATE MAKEADD.SK8",
    "OUTPUT ERROR\r\n",
    "the full-disk publication failure",
  );
  const fullResult = fullMachine.export_drive(0);
  assert.deepEqual(
    [...readCpm22File(fullResult, "MAKEADD.COM")],
    [...stableCom],
    "a failed output preserves the previous COM",
  );
  assert.deepEqual(
    [...readCpm22File(fullResult, "MAKEADD.NOB")],
    [...stableObject],
    "a failed output preserves the previous NOBJ",
  );
  fullMachine.free();
  const changed = installCpm22File(stableImage, {
    name: "MAKEADD.SK8",
    bytes: new TextEncoder().encode("(+ 32767 1)\x1a"),
    padByte: 0x1a,
  });
  machine.free();
  machine = newMachine(firmware, changed);
  const failed = session(machine);
  failed.boot();
  const failure = failed.command(
    "SKATE MAKEADD.SK8",
    "COMPILE ERROR\r\n",
    "the failed product recompilation",
  );
  assert.deepEqual(
    [...readCpm22File(machine.export_drive(0), "MAKEADD.COM")],
    [...stableCom],
    "the failed compile preserves the previous COM",
  );
  assert.deepEqual(
    [...readCpm22File(machine.export_drive(0), "MAKEADD.NOB")],
    [...stableObject],
    "the failed compile preserves the previous NOBJ",
  );
  const reopenedImage = machine.export_drive(0);
  machine.free();
  machine = newMachine(firmware, reopenedImage);
  const reopened = session(machine);
  reopened.boot();
  const repeat = reopened.command(
    "MAKEADD",
    "12\r\n",
    "the remounted generated program",
  );
  records.push({
    directory: dir,
    help,
    compile,
    run,
    rootCompile,
    rootRun,
    packageCompile,
    packageRun,
    packageRepeat,
    directCompile,
    directRun,
    objects: {
      makeadd: makeaddObject,
      root: rootObject,
      package: packageObject,
      direct: directObject,
    },
    outputFailure,
    failure,
    repeat,
    preserved: {
      comSha256: sha256(stableCom),
      objectSha256: sha256(stableObject),
      previousOutputsPreserved: true,
    },
  });
} finally {
  machine.free();
}

const initialFiles = [
  { name: "SKATE.COM", bytes: compilerBytes, kind: "compiler" },
  {
    name: "README.TXT",
    bytes: new TextEncoder().encode(helpText + "\x1a"),
    kind: "help",
  },
  ...await Promise.all(productSources.map(async ([name, relativePath]) => ({
    name,
    bytes: Uint8Array.from([
      ...(await Deno.readFile(join(skateRoot, relativePath))),
      0x1a,
    ]),
    kind: "source",
  }))),
];
const report = {
  status: "passed",
  image: outputPath,
  imageSha256: sha256(image),
  compiler: {
    loadAddress: "0100H",
    physicalBytes: compilerBytes.length,
    codeBytes: compiler.address("N4OBJ") - compiler.address("N6MAIN"),
    evaluatorBytes: compiler.address("N6OP") - compiler.address("N6MAIN"),
    readerBytes: compiler.address("REND") - compiler.address("RINIT"),
    templateBytes: compiler.address("N4OBJEND") - compiler.address("N4OBJ"),
  },
  profile: "Triptych CP/M 2.2 cpm-64k",
  files: initialFiles.map(({ name, bytes, kind }) => ({
    name,
    kind,
    logicalBytes: bytes.length,
    physicalBytes: readCpm22File(image, name).length,
    sha256: sha256(bytes),
    physicalSha256: sha256(readCpm22File(image, name)),
  })),
  disk: diskStats(image),
  records,
};
if (verifyManifest) {
  const expected = JSON.parse(
    await Deno.readTextFile(join(skateRoot, "docs", "n11-manifest.json")),
  );
  assert.deepEqual(
    report,
    expected,
    "generated N11 report differs from manifest",
  );
}
console.log(JSON.stringify(report, null, 2));
