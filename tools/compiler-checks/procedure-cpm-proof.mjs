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

const compiler = await loadAssembly("src/compiler/scope-control-compiler.asm");
assert.equal(compiler.image.base, 0);
assert.equal(compiler.address("SCMAIN"), 0x0100);
assert.ok(compiler.address("SCEND") < 0x10000);
const runtimeLength = compiler.address("SRTLEN");
const heapPointerAddress = compiler.address("SRTHEP");
const lowStackAddress = compiler.address("SRTLOW");
let disk = installCpm22File(backing, {
  name: "SKATE.COM",
  bytes: compiler.image.bytes.slice(0x0100),
  padByte: 0x1a,
});

const cases = [
  ["LAMBDA.SK8", "((lambda (x) x) 42)", "42"],
  ["TWOARG.SK8", "((lambda (x y) (+ x y)) 20 22)", "42"],
  ["NPRIM.SK8", "((lambda (x y) (begin (+ x y) 42)) 20 22)", "42"],
  [
    "ZEROIF.SK8",
    "((lambda (x) (if (zero? x) 7 9)) 0) (if (if #f 1) 7 9)",
    "7",
  ],
  ["BEGIN.SK8", "((lambda (x) (begin x)) 41)", "41"],
  [
    "SETONLY.SK8",
    "((lambda (x) (if (set! x (+ x 1)) x 0)) 41)",
    "42",
  ],
  ["MUTATE.SK8", "((lambda (x) (begin (set! x (+ x 1)) x)) 41)", "42"],
  [
    "OPORDER.SK8",
    "(+ (begin (set! + (lambda (x y) (- x y))) 9) 2)",
    "11",
  ],
  [
    "RECURP.SK8",
    "(define + (lambda (n) (if (zero? n) 7 (+ (- n 1))))) (+ 30000)",
    "7",
  ],
  [
    "GLOBAL.SK8",
    "(define id (lambda (x) x)) (id 42) (define f (lambda () (+ 9 2))) (define + (lambda (x y) (- x y))) (f) (+ 9 2)",
    "7",
  ],
  ["NESTED.SK8", "(define id (lambda (x) x)) (id (id 42))", "42"],
  ["NULLARY.SK8", "(define f (lambda () 42)) (f)", "42"],
  [
    "SIDEGEN.SK8",
    "(define g +) (define f (lambda (n) (if (zero? n) (g 1 (g 1 (g 1 (g 1 (g 1 (g 1 (+ 1 2))))))) (+ (f (- n 1)) 1)))) (g 1 (f 254))",
    "264",
  ],
  [
    "LETLOCAL.SK8",
    "(+ (let ((+ (lambda (x y) (- x y)))) (+ 9 2)) (let ((f +)) (f 9 2)))",
    "18",
  ],
  ["NONTAIL.SK8", "(define f (lambda (x) 7)) ((lambda (x) (f x) 42) 1)", "42"],
  [
    "NONARITH.SK8",
    "(define f (lambda (x) 7)) ((lambda (x) (+ (f x) 1)) 1)",
    "8",
  ],
  ["CAPTURE.SK8", "((lambda (x) ((lambda () x))) 42)", "42"],
  ["PKGCAP.SK8", "(define f (let ((x 42)) (lambda () x))) (f)", "42"],
  [
    "TENV.SK8",
    "(define make (lambda (x) (lambda (n) (if (zero? n) x (c 0))))) (define c (make 10)) (define d (make 20)) (d 1)",
    "10",
  ],
  [
    "TAIL.SK8",
    "(define loop (lambda (n) (if (zero? n) 7 (loop (- n 1))))) (loop 30000)",
    "7",
  ],
  [
    "MUTTAIL.SK8",
    "(define f (lambda (n) (if (zero? n) 7 (g (- n 1))))) (define g (lambda (n) (if (zero? n) 7 (f (- n 1))))) (f 30000)",
    "7",
  ],
  [
    "ANDTAIL.SK8",
    "(define loop (lambda (n) (if (zero? n) 7 (loop (- n 1))))) (and #t (loop 30000))",
    "7",
  ],
  [
    "ORTAIL.SK8",
    "(define loop (lambda (n) (if (zero? n) 7 (loop (- n 1))))) (or #f (loop 30000))",
    "7",
  ],
  [
    "DEEPOK.SK8",
    "(define f (lambda (n) (if (zero? n) 0 (+ 1 (f (- n 1)))))) (f 180)",
    "180",
  ],
  [
    "STACKOK.SK8",
    `(define f (lambda (n) (if (zero? n) ${"(+ 1 ".repeat(26)}0${
      ")".repeat(26)
    } (+ 1 (f (- n 1)))))) (f 180)`,
    "206",
    true,
  ],
  [
    "COUNTER.SK8",
    "(define make (lambda (x) (lambda () (begin (set! x (+ x 1)) x)))) (define c (make 0)) (c) (c)",
    "2",
  ],
  [
    "COUNTERS.SK8",
    "(define make (lambda (x) (lambda () (begin (set! x (+ x 1)) x)))) (define c (make 0)) (define d (make 10)) (c) (d) (c)",
    "2",
  ],
  [
    "SETNEST.SK8",
    "(define a 0) (define b 0) (set! a (begin (set! b 1) 2)) a (define x 1) (if (set! x #f) 7 9)",
    "7",
  ],
  [
    "SIBLING.SK8",
    "(define a (let ((x 1)) (lambda () x))) (define b (let ((x 2)) (lambda () x))) (a)",
    "1",
  ],
  [
    "ESCAPED.SK8",
    "(define saved (lambda () 99)) (define loop (lambda (n) (if (zero? n) 0 (begin (set! saved (lambda () n)) (loop (- n 1)))))) (loop 2) (saved)",
    "1",
  ],
  [
    "CELLGRD.SK8",
    "(define saved #f) (define loop (lambda (n) (if (zero? n) 0 (begin (set! saved (lambda () 42)) (loop (- n 1)))))) (loop 1) (saved)",
    "42",
  ],
  [
    "TRANSIT.SK8",
    "(define saved #f) (define loop (lambda (n) (if (zero? n) 0 (begin (set! saved (lambda () (lambda () n))) (loop (- n 1)))))) (loop 2) ((saved))",
    "1",
  ],
  [
    "SIDESTK.SK8",
    "(define f (lambda (n) (if (zero? n) (+ 1 2) (+ (f (- n 1)) 1)))) (let ((g +)) (g 1 (f 254)))",
    "258",
  ],
  ["MUL.SK8", "(* 2 3)", "6"],
  [
    "SLOT127.SK8",
    `((lambda () (let (${
      Array.from({ length: 128 }, (_, index) => `(x${index} ${index})`).join(
        " ",
      )
    }) x127)))`,
    "127",
  ],
  [
    "SLOT8.SK8",
    `((lambda () (let (${
      Array.from({ length: 9 }, (_, index) => `(x${index} ${index})`).join(" ")
    }) x8)))`,
    "8",
  ],
  [
    "GSET.SK8",
    "(define value 1) (set! value 2) value (define + 1) (set! + 8) +",
    "8",
  ],
];
const errorCases = [
  ["BADFORM.SK8", "(let ((value 1 2)) value)", "EXPECT\r\n"],
  ["DUPFORM.SK8", "((lambda (x x) x) 1 2)", "DUP\r\n"],
  ["TOOLONG.SK8", "1 ".repeat(2600), "CAP\r\n"],
];
const runtimeErrorCases = [
  ["ARITY.SK8", "((lambda (x) x) 1 2)", "RUNTIME ERROR\r\n"],
  ["UNBSET.SK8", "(set! missing 42)", "UNBOUND\r\n"],
  [
    "DEEPREC.SK8",
    "(define f (lambda (n) (if (zero? n) 0 (+ 1 (f (- n 1)))))) (f 200)",
    "RUNTIME ERROR\r\n",
  ],
];
for (const [name, source] of [...cases, ...errorCases, ...runtimeErrorCases]) {
  disk = installCpm22File(disk, {
    name,
    bytes: new TextEncoder().encode(source + "\x1a"),
    padByte: 0x1a,
  });
}

const machine = new TriptychCpu(firmware.bootRom);
const decoder = new TextDecoder("ascii");
let transcript = "";

function readWord(address) {
  const bytes = machine.read_ram(address, 2);
  return bytes[0] | bytes[1] << 8;
}

function runUntilPrompt(offset, description) {
  const limit = description.startsWith("run ") ? 8000 : 1800;
  for (let attempt = 0; attempt < limit; attempt += 1) {
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
  assert.ok(
    output.includes(expected),
    `${description}: expected ${JSON.stringify(expected)} in ${
      JSON.stringify(output)
    }`,
  );
  return output;
}

function validateObject(object, com, name) {
  assert.equal(
    object[0],
    1,
    `${name}: missing NOBJ header record (${[...object.slice(0, 12)]})`,
  );
  assert.deepEqual(
    [...object.slice(3, 7)],
    [0x4e, 0x4f, 0x42, 0x4a],
    `${name}: wrong NOBJ signature`,
  );
  let cursor = 70;
  let image = null;
  const kinds = [];
  let commitEnd = -1;
  while (cursor + 3 <= object.length) {
    const kind = object[cursor];
    const length = object[cursor + 1] | object[cursor + 2] << 8;
    const end = cursor + 3 + length;
    assert.ok(
      end <= object.length,
      `${name}: truncated NOBJ record at ${cursor} kind ${kind} length ${length} file ${object.length}`,
    );
    kinds.push(kind);
    if (kind === 6) {
      assert.ok(length >= 6, `${name}: short IMAGE record`);
      image = object.slice(cursor + 9, end);
    }
    cursor = end;
    if (kind === 12) {
      commitEnd = end;
      break;
    }
  }
  assert.ok(kinds.includes(6), `${name}: missing IMAGE record`);
  assert.ok(kinds.includes(8), `${name}: missing symbol record`);
  assert.ok(kinds.includes(11), `${name}: missing relocation record`);
  assert.equal(kinds.at(-1), 12, `${name}: missing COMMIT record`);
  assert.ok(commitEnd > 0, `${name}: missing complete COMMIT record`);
  for (const byte of object.slice(commitEnd)) {
    assert.ok(
      byte === 0x00 || byte === 0x1a,
      `${name}: non-padding after COMMIT`,
    );
  }

  let crc = 0xffff;
  const stream = object.slice(0, commitEnd);
  for (const byte of stream.slice(0, stream.length - 2)) {
    crc ^= byte << 8;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc & 0x8000) ? ((crc << 1) ^ 0x1021) : crc << 1;
      crc &= 0xffff;
    }
  }
  const stored = stream[stream.length - 2] | stream[stream.length - 1] << 8;
  assert.equal(stored, crc, `${name}: NOBJ CRC mismatch`);
  assert.ok(image, `${name}: image payload was not recorded`);
  assert.deepEqual(
    image,
    com.slice(0, image.length),
    `${name}: NOBJ image differs from COM`,
  );
  for (const byte of com.slice(image.length)) {
    assert.ok(
      byte === 0x00 || byte === 0x1a,
      `${name}: non-padding after COM image`,
    );
  }
}

try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  const measurements = [];
  for (const [name, , expected, guard] of cases) {
    const outputName = name.replace(".SK8", ".COM");
    runCommand(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    const image = machine.export_drive(0);
    const generated = readCpm22File(image, outputName);
    const object = readCpm22File(image, name.replace(".SK8", ".NOB"));
    validateObject(object, generated, name);
    assert.equal(generated[0], 0x31, `${outputName} sets its private stack`);
    if (guard) {
      machine.write_ram(0xce00, new Uint8Array(0x100).fill(0xa5));
    }
    runCommand(
      outputName.replace(".COM", ""),
      `${expected}\r\n`,
      `run ${outputName}`,
    );
    if (guard) {
      assert.deepEqual(
        [...machine.read_ram(0xce00, 0x100)],
        [...new Uint8Array(0x100).fill(0xa5)],
        `${name}: generated operands crossed the heap boundary`,
      );
    }
    const nativeLowSp = readWord(lowStackAddress);
    const heapEnd = readWord(heapPointerAddress);
    assert.ok(nativeLowSp >= 0xd400, `${name}: native stack crossed its guard`);
    assert.ok(heapEnd < nativeLowSp, `${name}: heap and stack collided`);
    measurements.push({
      name,
      result: expected,
      comBytes: generated.length,
      nobjBytes: object.length,
      lowSp: nativeLowSp,
      heapEnd,
    });
    runCommand(`ERA ${outputName}`, "A>", `remove ${outputName}`);
    runCommand(`ERA ${name.replace(".SK8", ".NOB")}`, "A>", `remove ${name}`);
  }
  for (const [name, , expected] of errorCases) {
    runCommand(`SKATE ${name}`, expected, `reject ${name}`);
  }
  for (const [name, , expected] of runtimeErrorCases) {
    const outputName = name.replace(".SK8", ".COM");
    runCommand(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    runCommand(
      outputName.replace(".COM", ""),
      expected,
      `reject ${outputName}`,
    );
    runCommand(`ERA ${outputName}`, "A>", `remove ${outputName}`);
    runCommand(`ERA ${name.replace(".SK8", ".NOB")}`, "A>", `remove ${name}`);
  }
  console.log(JSON.stringify(
    {
      status: "passed",
      compilerBytes: compiler.image.bytes.length - 0x100,
      imageEnd: compiler.image.end,
      runtimeBytes: runtimeLength,
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
