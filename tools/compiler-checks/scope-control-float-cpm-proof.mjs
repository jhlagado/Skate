import assert from "node:assert/strict";
import { join } from "node:path";
import { createRequire } from "node:module";
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

const compiler = await loadAssembly("src/compiler/scope-control-compiler.asm");
const provider = await loadAssembly(
  "src/compiler/scope-control-runtime-image.asm",
);
assert.equal(compiler.image.base, 0);
assert.equal(provider.image.bytes.length - 0x100, compiler.address("SRTLEN"));
let disk = installCpm22File(backing, {
  name: "SKATE.COM",
  bytes: compiler.image.bytes.slice(0x100),
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "SKATE.RT",
  bytes: provider.image.bytes.slice(0x100),
  padByte: 0x1a,
});

const cases = [
  ["FLOATLIT.SK8", "(begin (display 1.5) (newline))", "1.5\r\n"],
  ["DIVINT.SK8", "(begin (display (/ 1 2)) (newline))", "0.5\r\n"],
  ["DIVUNARY.SK8", "(begin (display (/ 2)) (newline))", "0.5\r\n"],
  ["DIVFOLD.SK8", "(begin (display (/ 8 2)) (newline))", "4.0\r\n"],
  ["DIVTHREE.SK8", "(begin (display (/ 8 2 2)) (newline))", "2.0\r\n"],
  ["MIXADD.SK8", "(begin (display (+ 1 0.5)) (newline))", "1.5\r\n"],
  ["MIXSUB.SK8", "(begin (display (- 3.0 1)) (newline))", "2.0\r\n"],
  ["MIXMUL.SK8", "(begin (display (* 2.0 3)) (newline))", "6.0\r\n"],
  ["NEGATIVE.SK8", "(begin (display -1.5) (newline))", "-1.5\r\n"],
  ["SIGNZER0.SK8", "(begin (display -0.0) (newline))", "-0.0\r\n"],
  [
    "SUBNORM.SK8",
    "(begin (display 0.000000059604644775390625) (newline))",
    "0.000000059604644775390625\r\n",
  ],
  ["MAXFLT.SK8", "(begin (display 65504.0) (newline))", "65504.0\r\n"],
  ["EXP25.SK8", "(begin (display 1024.0) (newline))", "1024.0\r\n"],
  [
    "COMPARIS.SK8",
    "(begin (write (= 2048 2048.0)) (write (< 2048 2050.0)) (write (> +nan.0 1.0)) (newline))",
    "#t#t#f\r\n",
  ],
  [
    "NUMPRED.SK8",
    "(begin (write (number? 1.5)) (write (boolean? 1.5)) (newline))",
    "#t#f\r\n",
  ],
  [
    "BOOLFLT.SK8",
    "(begin (write #f) (write #t) (write (number? 0.0)) (write (boolean? 0.0)) (newline))",
    "#f#t#t#f\r\n",
  ],
  [
    "ZEROFLT.SK8",
    "(begin (write 0.0) (newline) (write 1.0) (newline) (write (if 0.0 7 8)) (newline))",
    "0.0\r\n1.0\r\n7\r\n",
  ],
  [
    "SPECIALS.SK8",
    "(begin (write +inf.0) (newline) (write -inf.0) (newline) (write +nan.0) (newline))",
    "+inf.0\r\n-inf.0\r\n+nan.0\r\n",
  ],
  ["EXACTINT.SK8", "(begin (write (+ 1 2)) (newline))", "3\r\n"],
  ["ROUNDING.SK8", "(begin (display 2049.0) (newline))", "2048.0\r\n"],
  [
    "ZEROPRED.SK8",
    "(begin (write (zero? 0.0)) (write (zero? -0.0)) (write (zero? 1.5)) (newline))",
    "#t#t#f\r\n",
  ],
  [
    "NESTED.SK8",
    "(begin (write (list 1.5 2.0)) (newline))",
    "(1.5 2.0)\r\n",
  ],
  [
    "ADJACENT.SK8",
    "(begin (display 1.5) (display 2.0) (newline))",
    "1.52.0\r\n",
  ],
];
const errorCases = [
  ["NODIV.SK8", "(/)"],
  ["BADDIV.SK8", "(/ #t 2)"],
];
for (const [name, source] of [...cases, ...errorCases]) {
  disk = installCpm22File(disk, {
    name,
    bytes: new TextEncoder().encode(source + "\x1a"),
    padByte: 0x1a,
  });
}

const machine = new TriptychCpu(firmware.bootRom);
const decoder = new TextDecoder("ascii");
let transcript = "";
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
function command(commandText, expected, description) {
  const start = transcript.length;
  assert.ok(
    machine.enqueue_serial_input(new TextEncoder().encode(commandText + "\r")),
  );
  runUntilPrompt(start, description);
  const output = transcript.slice(start);
  assert.ok(output.includes(expected), JSON.stringify(output));
  return output;
}
function runProgram(name, expected) {
  const start = transcript.length;
  const stem = name.replace(".SK8", "");
  assert.ok(
    machine.enqueue_serial_input(new TextEncoder().encode(stem + "\r")),
  );
  const commandEcho = `${stem}\r\r\n`;
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const status = machine.run_slice(50_000, 500_000);
    transcript += decoder.decode(machine.take_serial_output());
    assert.notEqual(status, 0, `CP/M halted while starting ${name}`);
    if (transcript.slice(start).includes(commandEcho)) break;
  }
  assert.ok(transcript.slice(start).includes(commandEcho));
  runUntilPrompt(start, `run ${name}`);
  const output = transcript.slice(start);
  assert.ok(output.includes(expected), JSON.stringify(output));
  const commandEnd = output.indexOf("\r\r\n");
  const prompt = output.lastIndexOf("\r\nA>");
  assert.ok(commandEnd >= 0 && prompt > commandEnd, JSON.stringify(output));
  assert.equal(
    output.slice(commandEnd + 3, prompt),
    expected,
    `${name}: unexpected program output`,
  );
  return output;
}

try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  const measurements = [];
  for (const [name, , expected] of cases) {
    command(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    const image = machine.export_drive(0);
    measurements.push({
      name,
      comBytes: readCpm22File(image, name.replace(".SK8", ".COM")).length,
      nobjBytes: readCpm22File(image, name.replace(".SK8", ".NOB")).length,
    });
    runProgram(name, expected);
    command(`ERA ${name.replace(".SK8", ".COM")}`, "A>", `remove ${name}`);
    command(`ERA ${name.replace(".SK8", ".NOB")}`, "A>", `remove ${name}`);
  }
  for (const [name] of errorCases) {
    command(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    runProgram(name, "RUNTIME ERROR\r\n");
    command(`ERA ${name.replace(".SK8", ".COM")}`, "A>", `remove ${name}`);
    command(`ERA ${name.replace(".SK8", ".NOB")}`, "A>", `remove ${name}`);
  }
  console.log(JSON.stringify(
    {
      status: "passed",
      compilerBytes: compiler.image.bytes.length - 0x100,
      runtimeBytes: provider.image.bytes.length - 0x100,
      cases: cases.map(([name]) => name),
      largestComBytes: Math.max(
        ...measurements.map(({ comBytes }) => comBytes),
      ),
      largestNobjBytes: Math.max(
        ...measurements.map(({ nobjBytes }) => nobjBytes),
      ),
      measurements,
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
