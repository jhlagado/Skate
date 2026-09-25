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

const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const provider = await loadAssembly(
  "src/compiler/scope/runtime/image.asm",
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
  [
    "CHAROUT.SK8",
    "(begin (write-char #\\A) (write-char #\\space) (write-char #\\B) (newline))",
    "A B\r\n",
  ],
  [
    "CHARPRNT.SK8",
    "(begin (write #\\A) (display #\\B) (newline))",
    "#\\x41B\r\n",
  ],
  [
    "CHARCTL.SK8",
    "(begin (write #\\newline) (write #\\x00) (write #\\x7f) (newline))",
    "#\\x0a#\\x00#\\x7f\r\n",
  ],
  [
    "DISPLAYP.SK8",
    "(display (list #\\A #\\B))",
    "(#\\x41 #\\x42)",
  ],
  [
    "DISPZERO.SK8",
    "(begin (display #t) (display '()) (newline))",
    "#t()\r\n",
  ],
  [
    "CHARPRED.SK8",
    "(begin (write (char? #\\A)) (write (char? 1)) (write (procedure? read-char)) (write (procedure? write-char)) (newline))",
    "#t#f#t#t\r\n",
  ],
  [
    "READCHAR.SK8",
    "(begin (display (read-char)) (newline))",
    "QQ\r\n",
    "Q",
  ],
  [
    "EOFCHAR.SK8",
    "(begin (write (eof-object? (read-char))) (newline))",
    "\x1a#t\r\n",
    "\x1a",
  ],
  [
    "EOFWRITE.SK8",
    "(begin (write (read-char)) (newline))",
    "\x1a#<eof>\r\n",
    "\x1a",
  ],
  [
    "EOFDSPLY.SK8",
    "(begin (display (read-char)) (newline))",
    "\x1a#<eof>\r\n",
    "\x1a",
  ],
  [
    "ADVENT.SK8",
    await Deno.readTextFile("examples/applications/advent.sk8"),
    "You are at a fork. Choose left or right: l\r\nYou take the left path.",
    "l",
  ],
  [
    "HOUSE.SK8",
    await Deno.readTextFile("examples/applications/house.sk8"),
    [
      "THE HOUSE IN THE CLEARING\r\n",
      "Use one key at a time; q quits.\r\n",
      "Clearing, window shut: o=open.\r\n",
      "Command (o c u d t q): o\r\n",
      "Clearing, window open: c=climb.\r\n",
      "Command (o c u d t q): c\r\n",
      "Hall: u=upstairs, d=cellar.\r\n",
      "Command (o c u d t q): u\r\n",
      "Upstairs: d=hall.\r\n",
      "Command (o c u d t q): d\r\n",
      "Hall: u=upstairs, d=cellar.\r\n",
      "Command (o c u d t q): d\r\n",
      "Cellar: u=hall, t=trapdoor.\r\n",
      "Command (o c u d t q): t\r\n",
      "The trapdoor opens. You win.\r\n",
    ].join(""),
    "ocuddt",
  ],
];
const errorCases = [
  ["BADWCHAR.SK8", "(write-char 1)"],
  ["BADRCHAR.SK8", "(read-char 1)"],
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
function command(command, expected, description) {
  const start = transcript.length;
  assert.ok(
    machine.enqueue_serial_input(new TextEncoder().encode(command + "\r")),
  );
  runUntilPrompt(start, description);
  const output = transcript.slice(start);
  assert.ok(output.includes(expected), JSON.stringify(output));
  return output;
}
function runProgram(name, input, expected) {
  const start = transcript.length;
  const commandBytes = new TextEncoder().encode(
    name.replace(".SK8", "") + "\r",
  );
  assert.ok(machine.enqueue_serial_input(commandBytes));
  const commandEcho = `${name.replace(".SK8", "")}\r\r\n`;
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const status = machine.run_slice(50_000, 500_000);
    transcript += decoder.decode(machine.take_serial_output());
    assert.notEqual(status, 0, `CP/M halted while starting ${name}`);
    if (transcript.slice(start).includes(commandEcho)) break;
  }
  assert.ok(transcript.slice(start).includes(commandEcho));
  if (input.length > 0) {
    // Let the running program reach its blocking console read before sending
    // the byte.  This keeps the proof independent of execution speed.
    for (let attempt = 0; attempt < 8; attempt += 1) {
      const status = machine.run_slice(50_000, 500_000);
      transcript += decoder.decode(machine.take_serial_output());
      assert.notEqual(status, 0, `CP/M halted before input for ${name}`);
    }
    assert.ok(machine.enqueue_serial_input(new TextEncoder().encode(input)));
  }
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
function runInteractiveProgram(name, keys, expected) {
  const start = transcript.length;
  const commandBytes = new TextEncoder().encode(
    name.replace(".SK8", "") + "\r",
  );
  assert.ok(machine.enqueue_serial_input(commandBytes));
  const commandEcho = `${name.replace(".SK8", "")}\r\r\n`;
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const status = machine.run_slice(50_000, 500_000);
    transcript += decoder.decode(machine.take_serial_output());
    assert.notEqual(status, 0, `CP/M halted while starting ${name}`);
    if (transcript.slice(start).includes(commandEcho)) break;
  }
  assert.ok(transcript.slice(start).includes(commandEcho));
  const gamePrompt = "Command (o c u d t q): ";
  let readyAt = start;
  for (const key of keys) {
    for (let attempt = 0; attempt < 1800; attempt += 1) {
      if (transcript.lastIndexOf(gamePrompt) >= readyAt) break;
      const status = machine.run_slice(50_000, 500_000);
      transcript += decoder.decode(machine.take_serial_output());
      assert.notEqual(status, 0, `CP/M halted before ${key} for ${name}`);
    }
    assert.ok(
      transcript.lastIndexOf(gamePrompt) >= readyAt,
      JSON.stringify(transcript.slice(start)),
    );
    const before = transcript.length;
    assert.ok(machine.enqueue_serial_input(new TextEncoder().encode(key)));
    readyAt = before;
    for (let attempt = 0; attempt < 1800; attempt += 1) {
      const status = machine.run_slice(50_000, 500_000);
      transcript += decoder.decode(machine.take_serial_output());
      assert.notEqual(status, 0, `CP/M halted after ${key} for ${name}`);
      if (
        transcript.lastIndexOf(gamePrompt) >= before ||
        transcript.endsWith("\r\nA>")
      ) break;
    }
  }
  runUntilPrompt(start, `run ${name}`);
  const output = transcript.slice(start);
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
  for (const [name, , expected, input = ""] of cases) {
    command(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    const image = machine.export_drive(0);
    measurements.push({
      name,
      comBytes: readCpm22File(image, name.replace(".SK8", ".COM")).length,
      nobjBytes: readCpm22File(image, name.replace(".SK8", ".NOB")).length,
    });
    if (name === "HOUSE.SK8") {
      runInteractiveProgram(name, input, expected);
    } else {
      runProgram(name, input, expected);
    }
    command(`ERA ${name.replace(".SK8", ".COM")}`, "A>", `remove ${name}`);
    command(`ERA ${name.replace(".SK8", ".NOB")}`, "A>", `remove ${name}`);
  }
  for (const [name] of errorCases) {
    command(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    runProgram(name, "", "RUNTIME ERROR\r\n");
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
