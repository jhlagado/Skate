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
// Keep the CP/M system tracks, but leave the data directory free for this proof.
backing.fill(0xe5, 52 * 128, 52 * 128 + 64 * 32);

const compiler = await loadAssembly("src/compiler/scope-control-compiler.asm");
const provider = await loadAssembly(
  "src/compiler/scope-control-runtime-image.asm",
);
const ceilingArgument = Deno.args.find((argument) =>
  argument.startsWith("--ceiling=")
);
const managedCeiling = ceilingArgument === undefined
  ? 0xc000
  : Number.parseInt(ceilingArgument.slice("--ceiling=".length), 16);
assert.ok(
  Number.isInteger(managedCeiling) && managedCeiling >= 0xb800 &&
    managedCeiling <= 0xc000 && (managedCeiling & 0xff) === 0,
  "managed ceiling must be a page-aligned B800H..C000H value",
);
assert.equal(compiler.image.base, 0);
assert.ok(compiler.address("SCMAIN") === 0x0100);
assert.ok(compiler.address("SCEND") < 0x10000);
const runtimeLength = provider.image.bytes.length - 0x0100;
assert.equal(runtimeLength, compiler.address("SRTLEN"));
const runtimeImage = Uint8Array.from(provider.image.bytes);
const ceilingAddress = provider.address("SRTHEAPP");
runtimeImage[ceilingAddress] = managedCeiling & 0xff;
runtimeImage[ceilingAddress + 1] = managedCeiling >>> 8;
let disk = installCpm22File(backing, {
  name: "SKATE.COM",
  bytes: compiler.image.bytes.slice(0x0100),
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "SKATE.RT",
  bytes: runtimeImage.slice(0x0100),
  padByte: 0x1a,
});
const cases = [
  ["ADD.SK8", "(begin (write (+ 40 2)) (newline))", "42"],
  ["GLOBAL.SK8", "(define base 40) (write (+ base 2)) (newline)", "42"],
  [
    "LET.SK8",
    "(begin (write (let ((base 40) (delta 2)) (+ base delta))) (newline))",
    "42",
  ],
  [
    "LETSTAR.SK8",
    "(begin (write (let* ((base 40) (delta (+ base 2))) delta)) (newline))",
    "42",
  ],
  [
    "SHADOW.SK8",
    "(begin (write (let ((value 1)) (let ((value 2)) value))) (newline))",
    "2",
  ],
  [
    "BOOL-LET.SK8",
    "(begin (write (let ((value #f)) (if value 1 2))) (newline))",
    "2",
  ],
  [
    "NESTLET.SK8",
    "(begin (write (let ((value (let ((inner 1)) inner)) (other 2)) value)) (newline))",
    "1",
  ],
  [
    "NESTSTAR.SK8",
    "(begin (write (let* ((value (let ((inner 1)) inner)) (other 2)) value)) (newline))",
    "1",
  ],
  ["IF.SK8", "(begin (write (if #t 42 0)) (newline))", "42"],
  ["IF-FALSE.SK8", "(begin (write (if #f 1 42)) (newline))", "42"],
  ["AND.SK8", "(begin (write (and #t 42)) (newline))", "42"],
  ["OR.SK8", "(begin (write (or #f 42)) (newline))", "42"],
  [
    "COND.SK8",
    "(begin (write (cond ((= 1 2) 1) ((= 2 2) 42) (else 7))) (newline))",
    "42",
  ],
  [
    "CONDNO.SK8",
    "(begin (write (cond (#f 1))) (newline))",
    "#<unspecified>",
  ],
  [
    "LETREC.SK8",
    "(begin (write (letrec () 7)) (newline))",
    "7",
  ],
  [
    "LETEMPTY.SK8",
    "(begin (write (let () 7)) (newline))",
    "7",
  ],
  [
    "LETSTEMP.SK8",
    "(begin (write (let* () 7)) (newline))",
    "7",
  ],
  [
    "LETREC1.SK8",
    "(begin (write (letrec ((one 42)) one)) (newline))",
    "42",
  ],
  [
    "FWDCALL.SK8",
    "(begin (write (letrec ((first (lambda () (second))) (second (lambda () 42))) (first))) (newline))",
    "42",
  ],
  [
    "UNINITR.SK8",
    "(begin (write (letrec ((x 1) (y x)) y)) (newline))",
    "UNBOUND",
  ],
  [
    "SHADREC.SK8",
    "(begin (write (let ((x 9)) (letrec ((f (lambda () x)) (x 2)) (f)))) (newline))",
    "2",
  ],
  [
    "NESTREC.SK8",
    "(begin (write (letrec ((x (letrec ((y 7)) y))) x)) (newline))",
    "7",
  ],
  [
    "NESTFW.SK8",
    "(begin (write (letrec ((a (letrec ((x 1) (y x)) y)) (x 2)) (+ a x))) (newline))",
    "UNBOUND",
  ],
  [
    "GLFWD.SK8",
    "(define first (lambda () (second))) (define second (lambda () 7)) (begin (write (first)) (newline))",
    "7",
  ],
  [
    "GDEF.SK8",
    "(define (double x) (+ x x)) (begin (write (double 7)) (newline))",
    "14",
  ],
  [
    "NCOND.SK8",
    "(begin (write (cond (#t 7) (else (cond (#t 8))))) (newline))",
    "7",
  ],
  [
    "INTDEF.SK8",
    "(begin (write ((lambda () (define (f x) x) (f 7)))) (newline))",
    "7",
  ],
  [
    "INTFWD.SK8",
    "(begin (write ((lambda () (define f (lambda () g)) (define g 7) (f)))) (newline))",
    "7",
  ],
  [
    "INTSHAD.SK8",
    "(begin (write (let ((x 9)) ((lambda () (define f (lambda () x)) (define x 2) (f))))) (newline))",
    "2",
  ],
  [
    "MUTONE.SK8",
    "(begin (write (letrec ((first (lambda (n) (if (zero? n) 42 (second (- n 1))))) (second (lambda (n) (if (zero? n) 42 (first (- n 1)))))) (first 1))) (newline))",
    "42",
  ],
  [
    "SELFREC.SK8",
    "(begin (write (letrec ((count (lambda (n) (if (zero? n) 42 (count (- n 1)))))) (count 3))) (newline))",
    "42",
  ],
  [
    "NAMEDLET.SK8",
    "(begin (write (let loop ((n 3)) (if (zero? n) 42 (loop (- n 1))))) (newline))",
    "42",
  ],
  [
    "NAMZERO.SK8",
    "(begin (write (let loop () 7)) (newline))",
    "7",
  ],
  [
    "NESTNAME.SK8",
    "(begin (write (let outer () (let inner () 9))) (newline))",
    "9",
  ],
  [
    "NINIT.SK8",
    "(begin (write (let loop ((n (+ 1 2))) n)) (newline))",
    "3",
  ],
  [
    "NNINIT.SK8",
    "(begin (write (let outer ((x (let inner ((y 7)) y))) x)) (newline))",
    "7",
  ],
  [
    "NPROC.SK8",
    "(define f (lambda () (let loop ((n 3)) n))) (begin (write (f)) (newline))",
    "3",
  ],
  [
    "LTAIL.SK8",
    "(define f (lambda () (let () (+ 1 2)) 9)) (begin (write (f)) (newline))",
    "9",
  ],
  [
    "LSHADDEF.SK8",
    "(begin (write ((lambda (x) (let () (define x 2) x)) 1)) (newline))",
    "2",
  ],
  [
    "LETDEF.SK8",
    "(begin (write (let ((x 1)) (define y 2) (+ x y))) (newline))",
    "3",
  ],
  [
    "LSTARDEF.SK8",
    "(begin (write (let* ((x 1)) (define y 2) (+ x y))) (newline))",
    "3",
  ],
  [
    "CAPUNIN.SK8",
    "(begin (write ((lambda () (define f (lambda () x)) (define x x) x))) (newline))",
    "UNBOUND",
  ],
  ["UNBOUND.SK8", "unbound-name", "UNBOUND"],
];
const errorCases = [
  ["BADFORM.SK8", "(let ((value 1 2)) value)", "EXPECT\r\n"],
  ["DUPREC.SK8", "(letrec ((value 1) (value 2)) value)", "DUP\r\n"],
  [
    "LDDUP.SK8",
    "(let ((x 1)) (define x 2) x)",
    "DUP\r\n",
  ],
  [
    "LSDUP.SK8",
    "(let* ((x 1) (y x)) (define y 2) y)",
    "DUP\r\n",
  ],
  [
    "DUPIDEF.SK8",
    "((lambda () (define value 1) (define value 2) value))",
    "DUP\r\n",
  ],
  ["LATEDEF.SK8", "((lambda () 1 (define value 2)))", "DEF\r\n"],
  ["NESTDEF.SK8", "((lambda () (begin (define value 2) value)))", "DEF\r\n"],
  ["CONDDEF.SK8", "((lambda () (cond (#t (define value 2)))))", "DEF\r\n"],
  ["PARM2.SK8", "(lambda (value) (define value 2) value)", "DUP\r\n"],
  ["PARAMDEF.SK8", "((lambda (value) (define value 2) value) 1)", "DUP\r\n"],
  ["NAMEDBAD.SK8", "(let loop ((value 1 2)) value)", "EXPECT\r\n"],
  [
    "NESTBAD.SK8",
    "((lambda () (let outer () (let inner ((value 1 2)) value))))",
    "EXPECT\r\n",
  ],
  ["TOOLONG.SK8", "1 ".repeat(2600), "CAP\r\n"],
];
const noOutputCases = [["NOAUTO.SK8", "42"]];
for (const [name, source] of cases) {
  disk = installCpm22File(disk, {
    name,
    bytes: new TextEncoder().encode(source + "\x1a"),
    padByte: 0x1a,
  });
}
for (const [name, source] of errorCases) {
  disk = installCpm22File(disk, {
    name,
    bytes: new TextEncoder().encode(source + "\x1a"),
    padByte: 0x1a,
  });
}
for (const [name, source] of noOutputCases) {
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
function programOutput(output) {
  const commandEnd = output.indexOf("\r\r\n");
  const prompt = output.lastIndexOf("\r\nA>");
  assert.ok(commandEnd >= 0 && prompt > commandEnd, JSON.stringify(output));
  return output.slice(commandEnd + 3, prompt);
}
try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  const measurements = [];
  for (const [name, , expected] of cases) {
    runCommand(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    const image = machine.export_drive(0);
    const outputName = name.replace(".SK8", ".COM");
    const generated = readCpm22File(image, outputName);
    const object = readCpm22File(image, name.replace(".SK8", ".NOB"));
    measurements.push({
      name,
      comBytes: generated.length,
      nobjBytes: object.length,
    });
    assert.equal(generated[0], 0x31, `${outputName} sets its private stack`);
    const runName = outputName.replace(".COM", "");
    runCommand(runName, `${expected}\r\n`, `run ${outputName}`);
    runCommand(`ERA ${outputName}`, "A>", `remove ${outputName}`);
    runCommand(`ERA ${name.replace(".SK8", ".NOB")}`, "A>", `remove ${name}`);
  }
  for (const [name, , expected] of errorCases) {
    runCommand(`SKATE ${name}`, expected, `reject ${name}`);
  }
  for (const [name] of noOutputCases) {
    runCommand(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    const output = runCommand(
      name.replace(".SK8", ""),
      "A>",
      `run ${name.replace(".SK8", ".COM")}`,
    );
    assert.equal(programOutput(output), "", `${name}: implicit output remains`);
    runCommand(`ERA ${name.replace(".SK8", ".COM")}`, "A>", `remove ${name}`);
    runCommand(`ERA ${name.replace(".SK8", ".NOB")}`, "A>", `remove ${name}`);
  }
  console.log(JSON.stringify(
    {
      status: "passed",
      compilerBytes: compiler.image.bytes.length - 0x100,
      imageEnd: compiler.image.end,
      runtimeBytes: runtimeLength,
      managedCeiling,
      cases: cases.map(([name]) => name),
      largestComBytes: Math.max(
        ...measurements.map(({ comBytes }) => comBytes),
      ),
      largestNobjBytes: Math.max(
        ...measurements.map(({ nobjBytes }) => nobjBytes),
      ),
      measurements,
      transcript,
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
