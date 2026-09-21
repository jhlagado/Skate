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
// Keep CP/M system tracks and start the application disk with a free directory.
backing.fill(0xe5, 52 * 128, 52 * 128 + 64 * 32);
const compiler = await loadAssembly("src/compiler/scope-control-compiler.asm");
const provider = await loadAssembly(
  "src/compiler/scope-control-runtime-image.asm",
);
assert.equal(compiler.image.base, 0);
assert.equal(compiler.address("SCMAIN"), 0x0100);
assert.ok(compiler.address("SCEND") < 0x10000);
const runtimeLength = provider.image.bytes.length - 0x0100;
assert.equal(runtimeLength, compiler.address("SRTLEN"));
const heapPointerAddress = provider.address("SRTHEAPP");
const lowStackAddress = provider.address("SRTLOWSP");
let disk = installCpm22File(backing, {
  name: "SKATE.COM",
  bytes: compiler.image.bytes.slice(0x0100),
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "SKATE.RT",
  bytes: provider.image.bytes.slice(0x0100),
  padByte: 0x1a,
});

const dataCases = [
  [
    "DIGITS.SK8",
    '(begin (display 45) (display " ") (display -123) (write 7) (newline))',
    "45 -1237",
  ],
  [
    "LETINIT.SK8",
    "(define f (lambda (xs) (let ((x (car xs))) (+ x 1)))) (f (quote (41)))",
    "42",
  ],
  [
    "LETSINIT.SK8",
    "(define f (lambda (xs) (let* ((x (car xs)) (y (+ x 1))) (+ y 1)))) (f (quote (40)))",
    "42",
  ],
  ["QUOTE0.SK8", "(quote ())", "()"],
  ["QUOTE1.SK8", "(quote (1 2))", "(1 2)"],
  ["DOT.SK8", "(quote (1 2 . 3))", "(1 2 . 3)"],
  ["QSTR.SK8", '(quote "hi")', '"hi"'],
  ["QSYM.SK8", "(quote foo)", "foo"],
  ["CONS.SK8", "(cons 1 (cons 2 (quote ())))", "(1 2)"],
  ["CARSTR.SK8", '(car (cons "x" 1))', '"x"'],
  ["CAR.SK8", "(car (cons 1 (quote ())))", "1"],
  ["CDRSTR.SK8", '(cdr (cons #t "x"))', '"x"'],
  ["CDR.SK8", "(cdr (cons 1 (cons 2 (quote ()))))", "(2)"],
  ["PAIRP.SK8", "(pair? (cons 1 2))", "#t"],
  ["NULLP.SK8", "(null? (quote ()))", "#t"],
  ["LIST.SK8", "(list 1 2 3)", "(1 2 3)"],
  ["EQ.SK8", "(eq? 1 1)", "#t"],
  ["WRITE.SK8", "(begin (write (quote (1 2))) (newline))", "(1 2)"],
  ["DISPLAY.SK8", '(begin (display "hi") (newline))', "hi"],
  ["NEWLINE.SK8", '(begin (display "x") (newline))', "x"],
  ["EMPTYSTR.SK8", '(begin (write "") (newline))', '""'],
  ["SAMESTR.SK8", '(begin (write (eq? "x" "x")) (newline))', "#t"],
  ["SAMESYM.SK8", "(begin (write (eq? 'x 'x)) (newline))", "#t"],
  [
    "NESTQ.SK8",
    "(write ''x) (newline) (write (quote (a (quote x)))) (newline) (write '''x) (newline) (write (quote 'x)) (newline) (write '(a 'x)) (newline)",
    "(quote x)\r\n(a (quote x))\r\n(quote (quote x))\r\n(quote x)\r\n(a (quote x))",
  ],
  [
    "STABLE.SK8",
    "(define f (lambda () (quote (x)))) (write (eq? (f) (f))) (newline)",
    "#t",
  ],
  [
    "STNEST.SK8",
    "(define f (lambda () ''x)) (write (eq? (f) (f))) (newline)",
    "#t",
  ],
  [
    "GCFREE.SK8",
    "(define f (lambda () (quote ((1) 2 3)))) (define old (f)) (define loop (lambda (n) (if (zero? n) 0 (begin (cons n 0) (loop (- n 1)))))) (loop 3000) (write (list (eq? old (f)) old)) (newline)",
    "(#t ((1) 2 3))",
  ],
  [
    "GSET.SK8",
    "(define value 1) (set! value 2) value (define + 1) (set! + 8) +",
    "8",
  ],
  ["PRIMVAL.SK8", "(define p +) (p 2 3)", "5"],
  ["LAMBDAW.SK8", "(begin (write ((lambda (x) x) 42)))", "42"],
];
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
];
const integerCases = [
  [
    "INTARITH.SK8",
    `(begin
      (write (+)) (newline)
      (write (*)) (newline)
      (write (- 5)) (newline)
      (write (+ 1 2 3 4)) (newline)
      (write (* 2 3 4)) (newline)
      (write (- 10 3 2)) (newline)
      (write (quotient 7 3)) (newline)
      (write (quotient -7 3)) (newline)
      (write (remainder 7 3)) (newline)
      (write (remainder -7 3)) (newline)
      (write (remainder 7 -3)) (newline)
      (write (remainder -7 -3)) (newline))`,
    "0\r\n1\r\n-5\r\n10\r\n24\r\n5\r\n2\r\n-2\r\n1\r\n-1\r\n1\r\n-1",
  ],
  [
    "INTCMP.SK8",
    `(begin
      (write (= 4 4 4)) (newline)
      (write (= 4 5)) (newline)
      (write (< 1 2 3)) (newline)
      (write (< 1 3 2)) (newline)
      (write (> 3 2 1)) (newline)
      (write (> 3 4)) (newline)
      (write (<= 2 2 3)) (newline)
      (write (<= 3 2)) (newline)
      (write (>= 3 3 2)) (newline)
      (write (>= 2 3)) (newline)
      (write (< -2 -1)) (newline)
      (write (> -1 -2)) (newline))`,
    "#t\r\n#f\r\n#t\r\n#f\r\n#t\r\n#f\r\n#t\r\n#f\r\n#t\r\n#f\r\n#t\r\n#t",
  ],
  [
    "INTPRED.SK8",
    `(begin
      (write (not #f)) (newline)
      (write (not #t)) (newline)
      (write (not 0)) (newline)
      (write (number? 1)) (newline)
      (write (number? #t)) (newline)
      (write (number? #\\A)) (newline)
      (write (boolean? #t)) (newline)
      (write (boolean? 1)) (newline)
      (write (symbol? (quote foo))) (newline)
      (write (symbol? "foo")) (newline)
      (write (string? "foo")) (newline)
      (write (string? (quote foo))) (newline)
      (write (procedure? (lambda (x) x))) (newline)
      (write (procedure? +)) (newline)
      (write (procedure? 1)) (newline)
      (write (char? #\\A)) (newline)
      (write (char? 1)) (newline)
      (write (eof-object? 1)) (newline))`,
    "#t\r\n#f\r\n#f\r\n#t\r\n#f\r\n#f\r\n#t\r\n#f\r\n#t\r\n#f\r\n#t\r\n#f\r\n#t\r\n#t\r\n#f\r\n#t\r\n#f\r\n#f",
  ],
];
const integerRuntimeErrorCases = [
  ["INTDIV0.SK8", "(quotient 7 0)", "RUNTIME ERROR\r\n"],
  ["INTREM0.SK8", "(remainder 7 0)", "RUNTIME ERROR\r\n"],
  ["INTTYPE.SK8", "(+ 1 #t)", "RUNTIME ERROR\r\n"],
  ["CMPBAD.SK8", "(< 1 #t)", "RUNTIME ERROR\r\n"],
  ["INTOVF.SK8", "(+ 32767 1)", "RUNTIME ERROR\r\n"],
  ["INTQOVF.SK8", "(quotient -32768 -1)", "RUNTIME ERROR\r\n"],
  ["NOTARITY.SK8", "(not #t #f)", "RUNTIME ERROR\r\n"],
  ["MINUS0.SK8", "(-)", "RUNTIME ERROR\r\n"],
  ["CMPARITY.SK8", "(< 1)", "RUNTIME ERROR\r\n"],
];
const integerMode = Deno.args.includes("--integers");
const selectedCases = integerMode
  ? integerCases
  : Deno.args.includes("--data")
  ? dataCases
  : cases;

// Programs historically relied on the compiler printing the last value.  The
// language now leaves output to explicit procedures, so keep these proofs
// readable by writing the final top-level expression and ending its line.
function splitTopLevelForms(source) {
  const forms = [];
  let index = 0;
  while (index < source.length) {
    while (index < source.length && /\s/.test(source[index])) index += 1;
    if (index >= source.length) break;
    const start = index;
    if (source[index] !== "(") {
      if (source[index] === '"') {
        index += 1;
        let escaped = false;
        while (index < source.length) {
          const character = source[index++];
          if (escaped) escaped = false;
          else if (character === "\\") escaped = true;
          else if (character === '"') break;
        }
      } else {
        while (index < source.length && !/\s/.test(source[index])) index += 1;
      }
      forms.push(source.slice(start, index));
      continue;
    }
    let depth = 0;
    let string = false;
    let escaped = false;
    while (index < source.length) {
      const character = source[index++];
      if (string) {
        if (escaped) escaped = false;
        else if (character === "\\") escaped = true;
        else if (character === '"') string = false;
        continue;
      }
      if (character === '"') string = true;
      else if (character === "(") depth += 1;
      else if (character === ")" && --depth === 0) break;
    }
    forms.push(source.slice(start, index));
  }
  return forms;
}

function explicitResultSource(source) {
  const forms = splitTopLevelForms(source);
  if (forms.length === 0) return source;
  if (
    /^\(begin\b/.test(source) &&
    /\((?:write|display|newline|write-char|read-char)\b/.test(source)
  ) {
    return source;
  }
  const last = forms.at(-1);
  if (/^\((?:write|display|newline|write-char|read-char)\b/.test(last)) {
    return source;
  }
  forms[forms.length - 1] = `(begin (write ${last}) (newline))`;
  return forms.join(" ");
}
const errorCases = [
  ["BADFORM.SK8", "(let ((value 1 2)) value)", "EXPECT\r\n"],
  ["DUPFORM.SK8", "((lambda (x x) x) 1 2)", "DUP\r\n"],
  [
    "REVQCAP.SK8",
    "(write (quote (" + "1 ".repeat(64) + ")))",
    "CAP\r\n",
  ],
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
const dataErrorCases = [
  ["BADDOT.SK8", "(quote (1 . 2 3))", "COMPILE ERROR\r\n"],
];
const dataRuntimeErrorCases = [
  ["CARERR.SK8", "(car 1)", "RUNTIME ERROR\r\n"],
  ["CDRERR.SK8", "(cdr 1)", "RUNTIME ERROR\r\n"],
];
const selectedErrorCases = integerMode
  ? []
  : Deno.args.includes("--data")
  ? [...errorCases, ...dataErrorCases]
  : errorCases;
const selectedRuntimeErrorCases = integerMode
  ? integerRuntimeErrorCases
  : Deno.args.includes("--data")
  ? [...runtimeErrorCases, ...dataRuntimeErrorCases]
  : runtimeErrorCases;
for (
  const [name, source] of [
    ...selectedCases,
    ...selectedErrorCases,
    ...selectedRuntimeErrorCases,
  ]
) {
  const isProgramCase = selectedCases.some(([caseName]) => caseName === name);
  disk = installCpm22File(disk, {
    name,
    bytes: new TextEncoder().encode(
      (isProgramCase ? explicitResultSource(source) : source) + "\x1a",
    ),
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
function programOutput(output) {
  const commandEnd = output.indexOf("\r\r\n");
  const prompt = output.lastIndexOf("\r\nA>");
  assert.ok(commandEnd >= 0 && prompt > commandEnd, JSON.stringify(output));
  return output.slice(commandEnd + 3, prompt);
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
  for (const [name, source, expected, guard] of selectedCases) {
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
    const output = runCommand(
      outputName.replace(".COM", ""),
      explicitResultSource(source).includes("(newline)")
        ? `${expected}\r\n`
        : expected,
      `run ${outputName}`,
    );
    const expectedOutput = explicitResultSource(source).includes("(newline)")
      ? `${expected}\r\n`
      : expected;
    assert.equal(
      programOutput(output),
      expectedOutput,
      `${name}: unexpected program output`,
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
  for (const [name, , expected] of selectedErrorCases) {
    runCommand(`SKATE ${name}`, expected, `reject ${name}`);
  }
  for (const [name, , expected] of selectedRuntimeErrorCases) {
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
      cases: selectedCases.map(([name]) => name),
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
