import assert from "node:assert/strict";

import { loadAssembly } from "../../tests/z80.ts";
import { readAsoOperations } from "../../tools/aso.ts";
import { validateAso } from "./aso-proof.mjs";
import {
  installCpm22File,
  readCpm22File,
} from "../../../triptych/tools/lib/cpm22-disk.mjs";
import {
  createCpmSession,
  loadCpmSystem,
  makeSystemDisk,
  TriptychCpu,
} from "./cpm-harness.mjs";

const { firmware, sourceDisk } = await loadCpmSystem();
// Keep the CP/M system tracks, but leave the data directory free for this proof.
const backing = makeSystemDisk(firmware, sourceDisk);

const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const provider = await loadAssembly(
  "src/runtime/image.asm",
);
const ceilingArgument = Deno.args.find((argument) =>
  argument.startsWith("--ceiling=")
);
// The heap and the stack share memory up to RT_HIEND; a lower ceiling is
// not supported.
const managedCeiling = ceilingArgument === undefined
  ? provider.address("RT_HIEND")
  : Number.parseInt(ceilingArgument.slice("--ceiling=".length), 16);
assert.ok(
  managedCeiling === provider.address("RT_HIEND"),
  "the managed ceiling must be RT_HIEND",
);
assert.equal(compiler.image.base, 0);
assert.ok(compiler.address("CMD_MAIN") === 0x0100);
assert.ok(compiler.address("W_IMGEND") < 0x10000);
const runtimeLength = provider.image.bytes.length - 0x0100;
assert.equal(runtimeLength, compiler.address("RT_SIZE"));
const runtimeImage = Uint8Array.from(provider.image.bytes);
const ceilingAddress = provider.address("HEAP_LIM");
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
  [
    "BADFORM.SK8",
    "(let ((value 1 2)) value)",
    "EXPECT\r\n",
    "BADFORM.SK8:1:16: EXPECT\r\n",
  ],
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
  ["TOOLONG.SK8", "1 ".repeat(11000), "CAP\r\n"],
  // Front-end tables report CAP: a 33rd formal or argument, an over-long identifier,
  // a 129th string, a 641st symbol, a 129th quoted literal, a 256th
  // procedure and a 27th nested lambda.
  [
    "FORMAL33.SK8",
    "(define (f a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16 a17 a18 a19 a20 a21 a22 a23 a24 a25 a26 a27 a28 a29 a30 a31 a32 a33) a1)",
    "CAP\r\n",
  ],
  [
    "ARGS33.SK8",
    "(list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33)",
    "CAP\r\n",
  ],
  ["LONGSYM.SK8", `(define ${"a".repeat(32)} 1)`, "CAP\r\n"],
  [
    "STR129.SK8",
    Array.from({ length: 129 }, (_, i) => `(display "s${i}")`).join(" "),
    "CAP\r\n",
  ],
  [
    "SYM650.SK8",
    `(define (m) ${
      Array.from({ length: 650 }, (_, i) => `(let ((a${i} 0)) a${i})`).join(" ")
    })`,
    "CAP\r\n",
  ],
  [
    "LIT129.SK8",
    `(list ${
      ["q", "r", "t"].map((p) =>
        `'(${Array.from({ length: 43 }, (_, i) => `${p}${i}`).join(" ")})`
      ).join(" ")
    })`,
    "CAP\r\n",
  ],
  [
    "PROC256.SK8",
    `(define (g) ${
      Array.from({ length: 256 }, (_, i) => `(lambda () ${i})`).join(" ")
    })`,
    "CAP\r\n",
  ],
  ["OPEN27.SK8", `${"(lambda () ".repeat(27)}7${")".repeat(27)}`, "CAP\r\n"],
  ["LATEINC.SK8", '(display 1) (include "LIST.SK8")', "COMPILE ERROR\r\n"],
  [
    "INCBAD.SK8",
    '(include "BROKEN.SK8")\r\n',
    "EXPECT\r\n",
    "BROKEN.SK8:2:16: EXPECT\r\n",
  ],
  [
    "COL105.SK8",
    " ".repeat(89) + "(let ((value 1 2)) value)",
    "EXPECT\r\n",
    "COL105.SK8:1:105: EXPECT\r\n",
  ],
  [
    "INCPOS.SK8",
    '; header\r\n(include "INCLIB.SK8")\r\n(let ((value 1 2)) value)',
    "EXPECT\r\n",
    "INCPOS.SK8:3:16: EXPECT\r\n",
  ],
  [
    "INCLINE.SK8",
    '(include "INCLIB.SK8") (let ((value 1 2)) value)',
    "EXPECT\r\n",
    "INCLINE.SK8:1:39: EXPECT\r\n",
  ],
  [
    "INCNEST.SK8",
    '(include "INCMID.SK8")\r\n1',
    "EXPECT\r\n",
    "INCMID.SK8:3:16: EXPECT\r\n",
  ],
  ["INCMISS.SK8", '(include "ABSENT.SK8")\r\n1', "INCLUDE ERROR\r\n"],
];
const includeErrorFiles = [
  ["BROKEN.SK8", "(begin\r\n(let ((value 1 2)) value))\r\n"],
  ["INCLIB.SK8", "(define inclib 1)"],
  [
    "INCMID.SK8",
    '(include\r\n "INCLIB.SK8")\r\n(let ((value 1 2)) value)',
  ],
];
const noOutputCases = [["NOAUTO.SK8", "42"]];
// The CP/M 2.2 disk has 64 directory entries.  The valid and error corpora
// are installed in separate boots so the three output files can be staged
// alongside the compiler and all source files without changing the disk model.
const noOutputMode = Deno.args.includes("--no-output");
const errorMode = Deno.args.includes("--errors");
const onlyArgument = Deno.args.find((argument) =>
  argument.startsWith("--only=")
);
const onlyName = onlyArgument?.slice("--only=".length).toUpperCase();
const knownNames = new Set([
  ...cases.map(([name]) => name),
  ...errorCases.map(([name]) => name),
  ...noOutputCases.map(([name]) => name),
]);
if (onlyName !== undefined && !knownNames.has(onlyName)) {
  throw new Error(`unknown --only case: ${onlyName}`);
}
if (noOutputMode && errorMode) {
  throw new Error("--no-output and --errors cannot be combined");
}
const modeCases = noOutputMode ? noOutputCases : errorMode ? errorCases : cases;
if (
  onlyName !== undefined &&
  !modeCases.some(([name]) => name === onlyName)
) {
  throw new Error(`--only case is not available in this mode: ${onlyName}`);
}
const selectedCases = noOutputMode || errorMode
  ? []
  : onlyName === undefined
  ? cases
  : cases.filter(([name]) => name === onlyName);
const selectedErrorCases = noOutputMode || !errorMode
  ? []
  : onlyName === undefined
  ? errorCases
  : errorCases.filter(([name]) => name === onlyName);
const selectedNoOutputCases = noOutputMode ? noOutputCases : [];
for (const [name, source] of selectedCases) {
  disk = installCpm22File(disk, {
    name,
    bytes: new TextEncoder().encode(source + "\x1a"),
    padByte: 0x1a,
  });
}
for (const [name, source] of selectedErrorCases) {
  disk = installCpm22File(disk, {
    name,
    bytes: new TextEncoder().encode(source + "\x1a"),
    padByte: 0x1a,
  });
}
// A source named by a wildcard, or with a type the compiler writes, is
// refused before publication can delete or rename it.
const outputTypeSource = new TextEncoder().encode("(display 1)\x1a");
if (errorMode && onlyName === undefined) {
  disk = installCpm22File(disk, {
    name: "NAMED.COM",
    bytes: outputTypeSource,
    padByte: 0x1a,
  });
}
if (errorMode) {
  for (const [name, source] of includeErrorFiles) {
    disk = installCpm22File(disk, {
      name,
      bytes: new TextEncoder().encode(source + "\x1a"),
      padByte: 0x1a,
    });
  }
}
for (const [name, source] of selectedNoOutputCases) {
  disk = installCpm22File(disk, {
    name,
    bytes: new TextEncoder().encode(source + "\x1a"),
    padByte: 0x1a,
  });
}
const machine = new TriptychCpu(firmware.bootRom);
const cpm = createCpmSession(machine);
const { runUntilPrompt, runCommand } = cpm;
try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  const measurements = [];
  for (const [name, , expected] of selectedCases) {
    runCommand(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    const image = machine.export_drive(0);
    const outputName = name.replace(".SK8", ".COM");
    const generated = readCpm22File(image, outputName);
    const aso = readCpm22File(image, name.replace(".SK8", ".ASO"));
    const operations = readAsoOperations([aso]);
    const patchCount = operations.filter(({ kind }) => kind === "patch").length;
    if (name === "GLOBAL.SK8") {
      assert.ok(patchCount > 0, `${outputName}: ASO has no PATCH records`);
    }
    const { asoBytes } = validateAso(aso, generated, outputName);
    measurements.push({
      name,
      comBytes: generated.length,
      asoBytes,
      patchCount,
    });
    assert.equal(generated[0], 0x31, `${outputName} sets its private stack`);
    const runName = outputName.replace(".COM", "");
    runCommand(runName, `${expected}\r\n`, `run ${outputName}`);
    runCommand(`ERA ${outputName}`, "A>", `remove ${outputName}`);
    runCommand(`ERA ${name.replace(".SK8", ".ASO")}`, "A>", `remove ${name}`);
  }
  for (const [name, , expected, location] of selectedErrorCases) {
    const output = runCommand(`SKATE ${name}`, expected, `reject ${name}`);
    if (location !== undefined) {
      assert.ok(output.includes(location), JSON.stringify(output));
    }
    runCommand(`ERA ${name}`, "A>", `remove ${name}`);
  }
  if (errorMode && onlyName === undefined) {
    runCommand("SKATE *.SK8", "SOURCE ERROR\r\n", "refuse a wildcard");
    runCommand("SKATE NAMED.COM", "SOURCE ERROR\r\n", "refuse a COM source");
    const kept = readCpm22File(machine.export_drive(0), "NAMED.COM");
    assert.deepEqual(
      kept.slice(0, outputTypeSource.length),
      outputTypeSource,
      "NAMED.COM must be left unchanged",
    );
    runCommand("ERA NAMED.COM", "A>", "remove NAMED.COM");
  }
  for (const [name] of selectedNoOutputCases) {
    runCommand(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    const output = runCommand(
      name.replace(".SK8", ""),
      "A>",
      `run ${name.replace(".SK8", ".COM")}`,
    );
    const commandEnd = output.indexOf("\r\r\n");
    const prompt = output.lastIndexOf("\r\nA>");
    assert.ok(commandEnd >= 0 && prompt > commandEnd, JSON.stringify(output));
    assert.equal(
      output.slice(commandEnd + 3, prompt),
      "",
      `${name}: implicit output remains`,
    );
    runCommand(`ERA ${name.replace(".SK8", ".COM")}`, "A>", `remove ${name}`);
    runCommand(`ERA ${name.replace(".SK8", ".ASO")}`, "A>", `remove ${name}`);
    runCommand(`ERA ${name}`, "A>", `remove ${name}`);
  }
  console.log(JSON.stringify(
    {
      status: "passed",
      compilerBytes: compiler.image.bytes.length - 0x100,
      imageEnd: compiler.image.end,
      runtimeBytes: runtimeLength,
      managedCeiling,
      cases: selectedCases.map(([name]) => name),
      largestComBytes: Math.max(
        ...measurements.map(({ comBytes }) => comBytes),
      ),
      largestAsoBytes: Math.max(
        ...measurements.map(({ asoBytes }) => asoBytes),
      ),
      measurements,
      transcript: cpm.transcript,
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
