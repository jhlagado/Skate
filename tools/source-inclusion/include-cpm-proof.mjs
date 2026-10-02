import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../../tests/z80.ts";
import { assembleTriptychCpuFirmware } from "../../../triptych/tools/cpm22-native-image.mjs";
import {
  installCpm22File,
  readCpm22File,
} from "../../../triptych/tools/lib/cpm22-disk.mjs";

const triptychRoot = fileURLToPath(
  new URL("../../../triptych/", import.meta.url),
);
const fixtureRoot = fileURLToPath(
  new URL("../../tests/source-inclusion/fixtures/", import.meta.url),
);
const require = createRequire(import.meta.url);
const { TriptychCpu } = require(
  join(triptychRoot, "dist", "wasm", "triptych_host_wasm.js"),
);

const encoder = new TextEncoder();
const decoder = new TextDecoder("ascii");
const fixture = async (name) =>
  decoder.decode(await Deno.readFile(join(fixtureRoot, name)));

const chain = (prefix, count, last) =>
  Array.from({ length: count }, (_, index) => [
    `${prefix}${index + 1}.SK8`,
    index + 1 < count
      ? `(include "${prefix}${
        index + 2
      }.SK8")\r\n(define ${prefix.toLowerCase()}${index + 1} ${index + 1})`
      : last,
  ]);
const parts = (count) =>
  Array.from({ length: count }, (_, index) => {
    const name = `P${String(index + 1).padStart(2, "0")}`;
    return [`${name}.SK8`, `(define ${name.toLowerCase()} ${index + 1})`];
  });
const includeAll = (count) =>
  parts(count).map(([name]) => `(include "${name}")`).join("\r\n");

// Each boot installs its own files so the 64-entry CP/M directory is enough;
// outputs are erased after each run to keep the small disk from filling.
const boots = [
  {
    description: "nested, import-once and rejected include trees",
    files: [
      ["MAIN.SK8", await fixture("MAIN.SK8")],
      ["LIB.SK8", await fixture("LIB.SK8")],
      // Nested: each part's own leading includes precede it.
      [
        "NEST.SK8",
        '; root header\r\n(include "NA.SK8")\r\n(display (na))\r\n(newline)',
      ],
      ["NA.SK8", '(include "NB.SK8")\r\n(define (na) (+ (nb) 1))'],
      ["NB.SK8", "(define (nb) 41)"],
      // Diamond: the shared base is streamed once, before both users.
      [
        "DIAMOND.SK8",
        '(include "LEFT.SK8" "RIGHT.SK8")\r\n(display "m")\r\n(newline)',
      ],
      ["LEFT.SK8", '(include "BASE.SK8")\r\n(display "l")'],
      ["RIGHT.SK8", '(include "BASE.SK8")\r\n(display "r")'],
      ["BASE.SK8", '(display "b")'],
      // Eight files on the include path are accepted; nine are not.
      ["DEPTH.SK8", '(include "D1.SK8")\r\n(display d1)\r\n(newline)'],
      ...chain("D", 7, "(define d7 7)"),
      ["DEEP.SK8", '(include "DEPTH.SK8")\r\n(newline)'],
      // Cycles, including a part that includes itself.
      ["CYCLE.SK8", '(include "CA.SK8")\r\n1'],
      ["CA.SK8", '(include "CB.SK8")\r\n(define ca 1)'],
      ["CB.SK8", '(include "CA.SK8")\r\n(define cb 2)'],
      ["SELF.SK8", '(include "SELF.SK8")\r\n1'],
      ["MISSING.SK8", '(include "NB.SK8" "ABSENT.SK8")\r\n1'],
      ["NESTMISS.SK8", '(include "NM.SK8")\r\n1'],
      ["NM.SK8", '(include "ABSENT.SK8")\r\n(define nm 1)'],
    ],
    commands: [
      ["SKATE MAIN.SK8", "COMPILED\r\n", "MAIN.COM"],
      ["MAIN", "42\r\n"],
      ["ERA MAIN.COM", "A>"],
      ["ERA MAIN.ASO", "A>"],
      ["SKATE NEST.SK8", "COMPILED\r\n", "NEST.COM"],
      ["NEST", "42\r\n"],
      ["ERA NEST.COM", "A>"],
      ["ERA NEST.ASO", "A>"],
      ["SKATE DIAMOND.SK8", "COMPILED\r\n", "DIAMOND.COM"],
      ["DIAMOND", "blrm\r\n"],
      ["ERA DIAMOND.COM", "A>"],
      ["ERA DIAMOND.ASO", "A>"],
      ["SKATE DEPTH.SK8", "COMPILED\r\n", "DEPTH.COM"],
      ["DEPTH", "1\r\n"],
      ["ERA DEPTH.COM", "A>"],
      ["ERA DEPTH.ASO", "A>"],
      ["SKATE DEEP.SK8", "INCLUDE ERROR\r\n", null, "DEEP.COM"],
      ["SKATE CYCLE.SK8", "INCLUDE ERROR\r\n", null, "CYCLE.COM"],
      ["SKATE SELF.SK8", "INCLUDE ERROR\r\n", null, "SELF.COM"],
      ["SKATE MISSING.SK8", "INCLUDE ERROR\r\n", null, "MISSING.COM"],
      ["SKATE NESTMISS.SK8", "INCLUDE ERROR\r\n", null, "NESTMISS.COM"],
    ],
  },
  {
    description: "the 32-part source table bound",
    files: [
      ...parts(32),
      ["FULL.SK8", `${includeAll(31)}\r\n(display p31)\r\n(newline)`],
      ["OVER.SK8", `${includeAll(32)}\r\n(display p32)\r\n(newline)`],
    ],
    commands: [
      ["SKATE FULL.SK8", "COMPILED\r\n", "FULL.COM"],
      ["FULL", "31\r\n"],
      ["ERA FULL.COM", "A>"],
      ["ERA FULL.ASO", "A>"],
      ["SKATE OVER.SK8", "INCLUDE ERROR\r\n", null, "OVER.COM"],
    ],
  },
];

const firmware = await assembleTriptychCpuFirmware(triptychRoot);
const sourceDisk = await Deno.readFile(
  join(triptychRoot, "third_party", "cpm22", "cpm22.img"),
);
const systemDisk = Uint8Array.from(sourceDisk);
systemDisk.set(firmware.ccp, 0);
systemDisk.set(firmware.bdos, 0x0800);
systemDisk.set(firmware.bios, 0x1600);
const backing = new Uint8Array(Math.ceil(systemDisk.length / 512) * 512);
backing.set(systemDisk);
backing.fill(0xe5, 52 * 128, 52 * 128 + 64 * 32);

const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const runtime = await loadAssembly("src/runtime/image.asm");

function hasFile(image, name) {
  try {
    return readCpm22File(image, name).length >= 0;
  } catch {
    return false;
  }
}

for (const boot of boots) {
  let disk = installCpm22File(backing, {
    name: "SKATE.COM",
    bytes: compiler.image.bytes.slice(0x0100),
    padByte: 0x1a,
  });
  disk = installCpm22File(disk, {
    name: "SKATE.RT",
    bytes: runtime.image.bytes.slice(0x0100),
    padByte: 0x1a,
  });
  for (const [name, source] of boot.files) {
    disk = installCpm22File(disk, {
      name,
      bytes: encoder.encode(source + "\x1a"),
      padByte: 0x1a,
    });
  }
  const machine = new TriptychCpu(firmware.bootRom);
  let transcript = "";
  const untilPrompt = (description) => {
    const start = transcript.length;
    for (let attempt = 0; attempt < 1800; attempt += 1) {
      const status = machine.run_slice(50_000, 500_000);
      transcript += decoder.decode(machine.take_serial_output());
      assert.notEqual(status, 0, `CP/M halted during ${description}`);
      if (transcript.length > start && transcript.endsWith("A>")) {
        return transcript.slice(start);
      }
    }
    throw new Error(
      `timed out during ${description}: ${transcript.slice(-300)}`,
    );
  };
  try {
    machine.install_drive(0, disk, true);
    untilPrompt("boot");
    for (const [input, expected, produced, absent] of boot.commands) {
      assert.ok(machine.enqueue_serial_input(encoder.encode(`${input}\r`)));
      const output = untilPrompt(input);
      assert.ok(
        output.includes(expected),
        `${input}: ${JSON.stringify(output)}`,
      );
      const image = machine.export_drive(0);
      if (produced) {
        assert.ok(hasFile(image, produced), `${input}: no ${produced}`);
      }
      if (absent) {
        assert.ok(!hasFile(image, absent), `${input}: published ${absent}`);
      }
    }
  } finally {
    machine.free();
  }
  console.log(`Native include proof passed: ${boot.description}`);
}
