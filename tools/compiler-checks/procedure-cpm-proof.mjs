import assert from "node:assert/strict";
import { join } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import {
  applyRuntimeErrorCases,
  runtimeErrorCases,
  vectorRuntimeErrorCases,
} from "./procedure-error-cases.mjs";
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
const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const provider = await loadAssembly(
  "src/runtime/image.asm",
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
  ["LISTCASE.SK8", "(list 1 2 3)", "(1 2 3)"],
  ["EQ.SK8", "(eq? 1 1)", "#t"],
  ["WRITE.SK8", "(begin (write (quote (1 2))) (newline))", "(1 2)"],
  ["DISPLAY.SK8", '(begin (display "hi") (newline))', "hi"],
  ["NEWLINE.SK8", '(begin (display "x") (newline))', "x"],
  ["EMPTYSTR.SK8", '(begin (write "") (newline))', '""'],
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
const vectorCases = [
  [
    "VECTOR.SK8",
    "(begin (write (vector-ref (vector 10 20 30) 1)) (newline))",
    "20",
  ],
  [
    "MAKEV.SK8",
    "(define v (make-vector 4 #f)) (begin (vector-set! v 2 42) (write (vector-length v)) (write (vector? v)) (write (vector-ref v 2)) (newline))",
    "4#t42",
  ],
  [
    "MIXV.SK8",
    "(define v (make-vector 3 0)) (define a v) (begin (vector-set! a 0 (cons 1 2)) (vector-set! v 1 #\\A) (vector-set! v 2 v) (write (pair? (vector-ref v 0))) (write (char? (vector-ref a 1))) (write (vector? (vector-ref a 2))) (newline))",
    "#t#t#t",
  ],
  [
    "VEC64.SK8",
    "(define v (make-vector 64 9)) (begin (write (vector-length v)) (write (vector-ref v 63)) (newline))",
    "649",
  ],
  [
    "VECGC.SK8",
    "(define loop (lambda (n) (if (zero? n) 0 (begin (make-vector 8 0) (loop (- n 1)))))) (begin (loop 1000) (write (vector-ref (make-vector 2 9) 1)) (newline))",
    "9",
  ],
  [
    "VECROOT.SK8",
    "(define v (make-vector 1 #f)) (define loop (lambda (n) (if (zero? n) 0 (begin (cons n 0) (loop (- n 1)))))) (begin (vector-set! v 0 (cons 11 22)) (loop 3000) (write (car (vector-ref v 0))) (newline))",
    "11",
  ],
  [
    "VECSELF.SK8",
    "(define v (make-vector 1 #f)) (define loop (lambda (n) (if (zero? n) 0 (begin (make-vector 4 0) (loop (- n 1)))))) (begin (vector-set! v 0 v) (loop 1000) (write (vector? (vector-ref v 0))) (newline))",
    "#t",
  ],
  [
    "VECADJ.SK8",
    "(define a (make-vector 0)) (define b (make-vector 0)) (set! a #f) (define loop (lambda (n) (if (zero? n) 0 (begin (make-vector 0) (loop (- n 1)))))) (loop 1000) (begin (write (vector? b)) (newline))",
    "#t",
  ],
  [
    "VECRETRY.SK8",
    "(define loop (lambda (n) (if (zero? n) 0 (begin (make-vector 64 7) (loop (- n 1)))))) (loop 20) (begin (write (vector-length (make-vector 3 9))) (newline))",
    "3",
  ],
  [
    "VECOFLOW.SK8",
    `(define root (make-vector 64 #f))
      (define child #f)
      (define fill (lambda (v n) (if (zero? n) 0 (begin (vector-set! v (- 16 n) (cons n 0)) (fill v (- n 1))))))
      (define build (lambda (n) (if (zero? n) 0 (begin (set! child (make-vector 16 #f)) (fill child 16) (vector-set! root (- 64 n) child) (build (- n 1))))))
      (build 64)
      (define churn (lambda (n) (if (zero? n) 0 (begin (make-vector 8 0) (churn (- n 1))))))
      (churn 1000)
      (write (car (vector-ref (vector-ref root 63) 15)))
      (newline)`,
    "1",
  ],
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
    "REST.SK8",
    "(define f (lambda (first . rest) (+ first (car rest)))) (f 40 2)",
    "42",
  ],
  [
    "ALLREST.SK8",
    "(define f (lambda args (+ (car args) (car (cdr args))))) (f 40 2)",
    "42",
  ],
  [
    "RESTEMP.SK8",
    "(define f (lambda (first . rest) (if (null? rest) first 0))) (f 42)",
    "42",
  ],
  [
    "DEFREST.SK8",
    "(define (f first . rest) (+ first (car rest))) (f 40 2)",
    "42",
  ],
  [
    "RESTLIST.SK8",
    "(begin (write ((lambda args args) 1 2 3)) (newline))",
    "(1 2 3)",
  ],
  [
    "RESTGC.SK8",
    "(define f (lambda (n first . rest) (if (zero? n) first (f (- n 1) first 1)))) (f 3000 42)",
    "42",
  ],
  [
    "APPFIX.SK8",
    "(apply + (list 40 2))",
    "42",
  ],
  [
    "APPLEAD.SK8",
    "(apply + 40 (list 2))",
    "42",
  ],
  [
    "APPREST.SK8",
    "(define f (lambda (first . rest) (+ first (car rest)))) (apply f (list 40 2 3))",
    "42",
  ],
  [
    "APPNULL.SK8",
    "(apply (lambda () 42) '())",
    "42",
  ],
  [
    "APPTAIL.SK8",
    "(define loop (lambda (n) (if (zero? n) 7 (apply loop (list (- n 1)))))) (loop 3000)",
    "7",
  ],
  [
    "APPAPP.SK8",
    "(apply apply (list + (list 40 2)))",
    "42",
  ],
  [
    "APPNEST.SK8",
    "(define f (lambda (n) (if (zero? n) 42 (apply apply (list f (list (- n 1))))))) (f 3000)",
    "42",
  ],
  [
    "APPGC.SK8",
    "(define loop (lambda (n) (if (zero? n) (apply + (list 40 2)) (begin (cons n 0) (apply loop (list (- n 1))))))) (loop 3000)",
    "42",
  ],
  [
    "ECRETURN.SK8",
    "(call/ec (lambda (escape) 7))",
    "7",
  ],
  [
    "ECEARLY.SK8",
    "(call/ec (lambda (escape) (escape 42)))",
    "42",
  ],
  [
    "ECNEST.SK8",
    "(call/ec (lambda (outer) (+ 1 (call/ec (lambda (inner) (inner 7))))))",
    "8",
  ],
  [
    "ECTAIL.SK8",
    "(call/ec (lambda (escape) (letrec ((loop (lambda (n) (if (zero? n) (escape 42) (loop (- n 1)))))) (loop 3000))))",
    "42",
  ],
  [
    "ECPAIR.SK8",
    "(call/ec (lambda (escape) ((car (cons escape '())) 42)))",
    "42",
  ],
  [
    "ECPAIR2.SK8",
    "(call/ec (lambda (escape) ((cdr (cons 0 escape)) 42)))",
    "42",
  ],
  [
    "ECREPEAT.SK8",
    "(define loop (lambda (n) (if (zero? n) 0 (begin (call/ec (lambda (escape) (escape 1))) (loop (- n 1)))))) (loop 300)",
    "0",
  ],
  [
    "ECGCMAP.SK8",
    "(let ((root (cons 41 42))) (call/ec (lambda (escape) (letrec ((loop (lambda (n) (if (zero? n) (escape (car root)) (begin (cons n 0) (loop (- n 1))))))) (loop 3000)))))",
    "41",
  ],
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
  ["INCHERR.SK8", "(integer->char 256)", "RUNTIME ERROR\r\n"],
  ["NOTARITY.SK8", "(not #t #f)", "RUNTIME ERROR\r\n"],
  ["MINUS0.SK8", "(-)", "RUNTIME ERROR\r\n"],
  ["CMPARITY.SK8", "(< 1)", "RUNTIME ERROR\r\n"],
];
const integerMode = Deno.args.includes("--integers");
const applyMode = Deno.args.includes("--apply");
const ecMode = Deno.args.includes("--ec");
const runtimeErrorMode = Deno.args.includes("--runtime-errors");
const applyCaseNames = new Set([
  "APPFIX.SK8",
  "APPLEAD.SK8",
  "APPREST.SK8",
  "APPNULL.SK8",
  "APPTAIL.SK8",
  "APPAPP.SK8",
  "APPNEST.SK8",
  "APPGC.SK8",
]);
const ecCaseNames = new Set(
  cases.filter(([name]) => name.startsWith("EC")).map(([name]) => name),
);
const regularCases = cases.filter(([name]) =>
  !applyCaseNames.has(name) && !ecCaseNames.has(name)
);
const selectedCases = runtimeErrorMode
  ? []
  : integerMode
  ? integerCases
  : applyMode
  ? cases.filter(([name]) => applyCaseNames.has(name))
  : ecMode
  ? cases.filter(([name]) => name.startsWith("EC"))
  : Deno.args.includes("--vectors")
  ? vectorCases
  : Deno.args.includes("--data")
  ? dataCases
  : regularCases;

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
  if (/\((?:write|display|newline|write-char|read-char)\b/.test(source)) {
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
  ["ECEMPTY.SK8", "(call/ec)", "COMPILE ERROR\r\n"],
  ["ECEXTRA.SK8", "(call/ec (lambda (x) x) 2)", "EXPECT\r\n"],
  [
    "REVQCAP.SK8",
    "(write (quote (" + "1 ".repeat(64) + ")))",
    "CAP\r\n",
  ],
];
const restErrorCases = [
  [
    "DUPREST.SK8",
    "((lambda args (define args 42) args) 1 2)",
    "DUP\r\n",
  ],
  [
    "DUPNREST.SK8",
    "((lambda (outer) ((lambda args (define args 42) args) outer 2)) 1)",
    "DUP\r\n",
  ],
  [
    "DUPRDEF.SK8",
    "((lambda (first . rest) (define (rest) 42) (rest)) 1 2)",
    "DUP\r\n",
  ],
];
const dataErrorCases = [
  ["BADDOT.SK8", "(quote (1 . 2 3))", "COMPILE ERROR\r\n"],
];
const dataRuntimeErrorCases = [
  ["CARERR.SK8", "(car 1)", "RUNTIME ERROR\r\n"],
  ["CDRERR.SK8", "(cdr 1)", "RUNTIME ERROR\r\n"],
];
const selectedErrorCases = runtimeErrorMode
  ? []
  : applyMode
  ? []
  : integerMode
  ? []
  : ecMode
  ? errorCases.filter(([name]) => name.startsWith("EC"))
  : Deno.args.includes("--data")
  ? dataErrorCases
  : [...errorCases, ...restErrorCases];
const selectedRuntimeErrorCases = runtimeErrorMode
  ? runtimeErrorCases
  : applyMode
  ? applyRuntimeErrorCases
  : integerMode
  ? integerRuntimeErrorCases
  : ecMode
  ? runtimeErrorCases.filter(([name]) => name.startsWith("EC"))
  : Deno.args.includes("--vectors")
  ? vectorRuntimeErrorCases
  : Deno.args.includes("--data")
  ? dataRuntimeErrorCases
  : [];
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
  // Nested tail apply allocates two short-lived argument lists per step.
  // Allow that bounded stress case to finish without changing the stack guard.
  const limit = description.startsWith("run ") ? 16000 : 1800;
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
  return image.length;
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
    const imageLength = validateObject(object, generated, name);
    const imageEndOffset = provider.address("SRTIMGE") - 0x0100;
    const publishedImageEnd = generated[imageEndOffset] |
      generated[imageEndOffset + 1] << 8;
    assert.equal(
      publishedImageEnd,
      0x0100 + imageLength,
      `${name}: runtime image end was not published from the final image length`,
    );
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
    runCommand(`ERA ${name}`, "A>", `remove ${name}`);
  }
  for (const [name, , expected] of selectedErrorCases) {
    runCommand(`SKATE ${name}`, expected, `reject ${name}`);
    runCommand(`ERA ${name}`, "A>", `remove ${name}`);
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
    runCommand(`ERA ${name}`, "A>", `remove ${name}`);
  }
  console.log(JSON.stringify(
    {
      status: "passed",
      compilerBytes: compiler.image.bytes.length - 0x100,
      imageEnd: compiler.image.end,
      runtimeBytes: runtimeLength,
      cases: selectedCases.map(([name]) => name),
      errorCases: selectedErrorCases.map(([name]) => name),
      runtimeErrorCases: selectedRuntimeErrorCases.map(([name]) => name),
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
