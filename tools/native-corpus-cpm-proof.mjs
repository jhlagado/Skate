import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../tests/z80.ts";
import { parseNobj1 } from "@jhlagado/z80-tool-services";
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

const corpus = [
  {
    id: "make-adder",
    sourcePath: "examples/make-adder.sk8",
    sourceName: "MAKEADD.SK8",
    outputName: "MAKEADD.COM",
    objectName: "MAKEADD.NOB",
    expected: "12\r\n",
    representation: "exact signed16 closure result",
    limits: {
      model: "static-result-template",
      heapCells: 0,
      rootBytes: 0,
      activationBytes: 0,
      stackBytes: 0,
    },
  },
  {
    id: "shared-counter",
    sourcePath: "examples/shared-counter.sk8",
    sourceName: "COUNTER.SK8",
    outputName: "COUNTER.COM",
    objectName: "COUNTER.NOB",
    expected: "2\r\n",
    representation: "exact signed16 shared mutation",
    limits: {
      model: "static-result-template",
      heapCells: 0,
      rootBytes: 0,
      activationBytes: 0,
      stackBytes: 0,
    },
  },
  {
    id: "rational",
    sourcePath: "examples/rational.sk8",
    sourceName: "RATIONAL.SK8",
    outputName: "RATIONAL.COM",
    objectName: "RATIONAL.NOB",
    expected: "3\r\n",
    representation: "exact signed16 escaped CDR pair",
    limits: {
      model: "static-result-template",
      heapCells: 0,
      rootBytes: 0,
      activationBytes: 0,
      stackBytes: 0,
    },
  },
  {
    id: "lists",
    sourcePath: "examples/lists.sk8",
    sourceName: "LISTS.SK8",
    outputName: "LISTS.COM",
    objectName: "LISTS.NOB",
    expected: "84\r\n",
    representation: "exact signed16 proper and improper pairs",
    limits: {
      model: "static-result-template",
      heapCells: 0,
      rootBytes: 0,
      activationBytes: 0,
      stackBytes: 0,
    },
  },
  {
    id: "higher-order-sum",
    sourcePath: "examples/higher-order-sum.sk8",
    sourceName: "HORDER.SK8",
    outputName: "HORDER.COM",
    objectName: "HORDER.NOB",
    expected: "55\r\n",
    representation: "exact signed16 higher-order recursion",
    limits: {
      model: "static-result-template",
      heapCells: 0,
      rootBytes: 0,
      activationBytes: 0,
      stackBytes: 0,
    },
  },
  {
    id: "mutual-tail",
    sourcePath: "examples/mutual-tail.sk8",
    sourceName: "MUTTAIL.SK8",
    outputName: "MUTTAIL.COM",
    objectName: "MUTTAIL.NOB",
    expected: "42\r\n",
    representation: "exact signed16 30000-step tail counter",
    limits: {
      model: "static-result-template",
      heapCells: 0,
      rootBytes: 0,
      activationBytes: 0,
      stackBytes: 0,
    },
  },
  {
    id: "root",
    sourcePath: "examples/root.sk8",
    sourceName: "ROOT.SK8",
    outputName: "ROOT.COM",
    objectName: "ROOT.NOB",
    expected: null,
    representation: "binary16 bisection",
    limits: {
      model: "static-result-template",
      heapCells: 0,
      rootBytes: 0,
      activationBytes: 0,
      stackBytes: 0,
    },
  },
  {
    id: "signed16-overflow",
    sourcePath: null,
    sourceName: "OVERFLOW.SK8",
    outputName: "OVERFLOW.COM",
    objectName: "OVERFLOW.NOB",
    source: "(+ 32767 1)",
    error: "COMPILE ERROR\r\n",
    representation: "exact signed16 overflow",
    limits: {
      model: "static-result-template",
      heapCells: 0,
      rootBytes: 0,
      activationBytes: 0,
      stackBytes: 0,
    },
  },
];

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

const compiler = await loadAssembly("compiler/skate.asm");
assert.equal(compiler.image.base, 0);
assert.equal(compiler.address("N6MAIN"), 0x0100);
assert.ok(compiler.address("N4OBJEND") < 0xa000);
const compilerBytes = compiler.image.bytes.slice(0x0100);

let disk = installCpm22File(backing, {
  name: "SKATE.COM",
  bytes: compilerBytes,
  padByte: 0x1a,
});
for (const item of corpus) {
  const source = item.sourcePath === null
    ? item.source
    : new TextDecoder().decode(
      await Deno.readFile(new URL(`../${item.sourcePath}`, import.meta.url)),
    );
  item.sourceBytes = new TextEncoder().encode(source + "\x1a");
  disk = installCpm22File(disk, {
    name: item.sourceName,
    bytes: item.sourceBytes,
    padByte: 0x1a,
  });
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
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

function canonicalName(name) {
  const [base, extension = ""] = name.toUpperCase().split(".");
  return `${base.padEnd(8, " ")}${extension.padEnd(3, " ")}`;
}

function fileStats(image, name) {
  const wanted = canonicalName(name);
  const directoryOffset = 52 * 128;
  let blocks = 0;
  for (let index = 0; index < 64; index += 1) {
    const offset = directoryOffset + index * 32;
    if (image[offset] !== 0) continue;
    let same = true;
    for (let byte = 0; byte < 11; byte += 1) {
      if (image[offset + 1 + byte] !== wanted.charCodeAt(byte)) {
        same = false;
        break;
      }
    }
    if (!same) continue;
    for (let byte = 16; byte < 32; byte += 1) {
      if (image[offset + byte] !== 0) blocks += 1;
    }
  }
  assert.ok(blocks > 0, `${name} has no allocated blocks`);
  return { blocks, bytes: readCpm22File(image, name).length };
}

function diskStats(image) {
  const directoryOffset = 52 * 128;
  const used = new Set();
  let files = 0;
  for (let index = 0; index < 64; index += 1) {
    const offset = directoryOffset + index * 32;
    if (image[offset] !== 0) continue;
    files += 1;
    for (let byte = 16; byte < 32; byte += 1) {
      if (image[offset + byte] !== 0) used.add(image[offset + byte]);
    }
  }
  return {
    files,
    usedBlocks: used.size,
    freeBlocks: 241 - used.size,
  };
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
    get transcript() {
      return transcript;
    },
  };
}

function newMachine(image) {
  const machine = new TriptychCpu(firmware.bootRom);
  machine.install_drive(0, image, true);
  return machine;
}

const records = [];
let machine = newMachine(disk);
try {
  const first = session(machine);
  first.boot();
  for (const item of corpus) {
    const compile = first.command(
      `SKATE ${item.sourceName}`,
      item.error ?? "COMPILED\r\n",
      `${item.id} compilation`,
    );
    const image = machine.export_drive(0);
    const sourceFile = readCpm22File(image, item.sourceName);
    const result = {
      id: item.id,
      source: item.sourcePath ?? "inline",
      sourceName: item.sourceName,
      outputName: item.outputName,
      objectName: item.objectName,
      sourceSha256: sha256(item.sourceBytes),
      representation: item.representation,
      profile: "cpm-64k",
      compile,
      limits: item.limits,
      sourceBytes: {
        logical: item.sourceBytes.length,
        physical: sourceFile.length,
      },
      disk: fileStats(image, item.sourceName),
    };
    assert.equal(
      result.sourceSha256,
      sha256(sourceFile.slice(0, item.sourceBytes.length)),
    );
    if (item.error) {
      assert.throws(() => readCpm22File(image, item.outputName), /is absent/);
      assert.throws(() => readCpm22File(image, item.objectName), /is absent/);
      result.error = item.error.trim();
      records.push(result);
      continue;
    }

    const objectPhysical = readCpm22File(image, item.objectName);
    const objectBytes = committed(objectPhysical);
    const object = parseNobj1(objectBytes);
    const comPhysical = readCpm22File(image, item.outputName);
    const run = first.command(
      item.outputName.slice(0, -4),
      item.expected ?? "",
      `${item.id} generated program`,
    );
    if (item.expected === null) {
      item.expected = run.output.match(/F16:[0-9A-F]{4}\r\n/)?.[0] ?? null;
    }
    assert.ok(item.expected, `${item.id} did not produce a recorded result`);
    assert.ok(run.output.includes(item.expected), run.output);
    result.expected = item.expected.trim();
    result.object = {
      physicalBytes: objectPhysical.length,
      committedBytes: objectBytes.length,
      sha256: sha256(objectBytes),
      sections: object.sections.length,
      images: object.images.reduce(
        (total, image) => total + image.bytes.length,
        0,
      ),
    };
    result.com = {
      physicalBytes: comPhysical.length,
      sha256: sha256(comPhysical),
    };
    result.run = run;
    result.disk.output = fileStats(image, item.outputName);
    result.disk.object = fileStats(image, item.objectName);
    records.push(result);
  }

  const stableImage = machine.export_drive(0);
  const stableCom = readCpm22File(stableImage, "MAKEADD.COM");
  const stableObject = readCpm22File(stableImage, "MAKEADD.NOB");
  const stableComSha256 = sha256(stableCom);
  const stableObjectSha256 = sha256(stableObject);
  const changedDisk = installCpm22File(stableImage, {
    name: "MAKEADD.SK8",
    bytes: new TextEncoder().encode("(+ 32767 1)\x1a"),
    padByte: 0x1a,
  });
  machine.free();
  machine = newMachine(changedDisk);
  const remounted = session(machine);
  remounted.boot();
  remounted.command(
    "SKATE MAKEADD.SK8",
    "COMPILE ERROR\r\n",
    "preservation failure",
  );
  assert.deepEqual(
    [...readCpm22File(machine.export_drive(0), "MAKEADD.COM")],
    [...stableCom],
    "previous COM survives a failed recompilation",
  );
  assert.deepEqual(
    [...readCpm22File(machine.export_drive(0), "MAKEADD.NOB")],
    [...stableObject],
    "previous NOBJ survives a failed recompilation",
  );
  const preserved = records.find((record) => record.id === "make-adder");
  assert.ok(preserved);
  preserved.preservation = {
    failedSource: "(+ 32767 1)",
    previousComSha256: stableComSha256,
    previousObjectSha256: stableObjectSha256,
    previousOutputsPreserved: true,
  };

  const remountImage = machine.export_drive(0);
  machine.free();
  machine = newMachine(remountImage);
  const rebooted = session(machine);
  rebooted.boot();
  const repeat = rebooted.command("MAKEADD", "12\r\n", "reopened COM");
  records.find((record) => record.id === "make-adder").repeat = repeat;

  console.log(JSON.stringify(
    {
      status: "passed",
      compiler: {
        loadAddress: "0100H",
        physicalBytes: compilerBytes.length,
        codeBytes: compiler.address("N4OBJ") - compiler.address("N6MAIN"),
        evaluatorBytes: compiler.address("N6OP") - compiler.address("N6MAIN"),
        readerBytes: compiler.address("REND") - compiler.address("RINIT"),
        templateBytes: compiler.address("N4OBJEND") - compiler.address("N4OBJ"),
      },
      disk: diskStats(remountImage),
      records,
      platform: "Triptych WASM with CP/M 2.2",
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
