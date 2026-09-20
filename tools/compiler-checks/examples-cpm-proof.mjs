import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../../tests/z80.ts";
import { assembleTriptychCpuFirmware } from "../../../triptych/tools/cpm22-native-image.mjs";
import {
  createBlankCpm22Disk,
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
const sourceRoot = join(skateRoot, "examples", "applications");
function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function makeSystemDisk(firmware) {
  const system = createBlankCpm22Disk();
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

const firmware = await assembleTriptychCpuFirmware(triptychRoot);
const sourceDisk = await Deno.readFile(
  join(triptychRoot, "third_party/cpm22/cpm22.img"),
);
const compiler = await loadAssembly("src/compiler/scope-control-compiler.asm");
const provider = await loadAssembly(
  "src/compiler/scope-control-runtime-image.asm",
);
let disk = makeSystemDisk(firmware);
for (
  const [name, bytes] of [
    ["EDIT.COM", readCpm22File(sourceDisk, "EDIT.COM")],
    ["SKATE.COM", compiler.image.bytes.slice(0x100)],
    ["SKATE.RT", provider.image.bytes.slice(0x100)],
  ]
) disk = installCpm22File(disk, { name, bytes, padByte: 0x1a });
const examples = [
  ["RECEIPT", "Total (cents): 620\r\n"],
  ["ROUTE", "(1 2 5 6)\r\n"],
  ["ACCOUNT", "Combined balance: 6650\r\n"],
];
for (const name of ["README.TXT", ...examples.map(([name]) => name + ".SK8")]) {
  const text = await Deno.readTextFile(join(sourceRoot, name.toLowerCase()));
  const normalized = text.replace(/\r?\n/g, "\r\n");
  assert.equal(text, normalized, name + ": source must use CRLF");
  disk = installCpm22File(disk, {
    name,
    bytes: encoder.encode(normalized + "\x1a"),
    padByte: 0x1a,
  });
}
let machine = newMachine(firmware, disk);
const records = [];
try {
  const terminal = session(machine);
  terminal.boot();
  for (const [name, expected] of examples) {
    const source = await Deno.readTextFile(
      join(sourceRoot, name.toLowerCase() + ".sk8"),
    );
    terminal.command("TYPE " + name + ".SK8", source, "type " + name);
    terminal.command(
      "SKATE " + name + ".SK8",
      "COMPILED\r\n",
      "compile " + name,
    );
    const saved = machine.export_drive(0);
    const com = readCpm22File(saved, name + ".COM");
    validateObject(
      committedObject(readCpm22File(saved, name + ".NOB"), name),
      com,
      name,
    );
    records.push({
      name,
      bytes: com.length,
      run: terminal.command(name, expected, "run " + name),
    });
    // Keep runnable examples and source; intermediate objects can be rebuilt.
    terminal.command(
      "ERA " + name + ".NOB",
      "A>",
      "remove intermediate " + name,
    );
  }
  disk = machine.export_drive(0);
  machine.free();
  machine = newMachine(firmware, disk);
  const reopened = session(machine);
  reopened.boot();
  for (const [name, expected] of examples) {
    reopened.command(name, expected, "reopen " + name);
  }
} finally {
  machine.free();
}
assert.deepEqual(
  [...new Set(directoryFiles(disk).map(({ name }) => name))].sort(),
  [
    "EDIT.COM",
    "SKATE.COM",
    "SKATE.RT",
    "README.TXT",
    ...examples.flatMap(([name]) => [name + ".SK8", name + ".COM"]),
  ].sort(),
  "disk must contain only the Skate tools, documentation and examples",
);
if (imagePath) {
  await Deno.mkdir(dirname(imagePath), { recursive: true });
  await Deno.writeFile(imagePath, disk);
}
console.log(
  JSON.stringify(
    {
      status: "passed",
      imagePath,
      sha256: sha256(disk),
      disk: diskStats(disk),
      records,
    },
    null,
    2,
  ),
);
