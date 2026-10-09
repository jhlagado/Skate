import assert from "node:assert/strict";
import {
  applyRuntimeErrorCases,
  runtimeErrorCases,
  vectorRuntimeErrorCases,
} from "./procedure-error-cases.mjs";
import { loadAssembly } from "../../tests/z80.ts";
import {
  installCpm22File,
  readCpm22File,
} from "../../../triptych/tools/lib/cpm22-disk.mjs";
import { validateAso } from "./aso-proof.mjs";
import { summarizeCellMeasurements } from "./cell-metrics.mjs";
import {
  createCpmSession,
  loadCpmSystem,
  makeSystemDisk,
  programOutput,
  readWord,
  TriptychCpu,
} from "./cpm-harness.mjs";

const { firmware, sourceDisk } = await loadCpmSystem();
// Keep CP/M system tracks and start the application disk with a free directory.
const backing = makeSystemDisk(firmware, sourceDisk);
const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const provider = await loadAssembly(
  "src/runtime/image.asm",
);
assert.equal(compiler.image.base, 0);
assert.equal(compiler.address("CMD_MAIN"), 0x0100);
assert.ok(compiler.address("W_IMGEND") < 0x10000);
const runtimeLength = provider.image.bytes.length - 0x0100;
assert.equal(runtimeLength, compiler.address("RT_SIZE"));
const heapPointerAddress = provider.address("HEAP_LIM");
const lowStackAddress = provider.address("RT_LOWSP");
const bindingAllocationAddress = provider.address("CNT_BIND");
const closureAllocationAddress = provider.address("CNT_CLOS");
const pairAllocationAddress = provider.address("CNT_PAIR");
const collectionCountAddress = provider.address("CNT_GC");
const frameCountAddress = provider.address("CNT_MAPS");
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
if (Deno.args.includes("--data")) {
  disk = installCpm22File(disk, {
    name: "LIST.SK8",
    bytes: await Deno.readFile("libraries/LIST.SK8"),
    padByte: 0x1a,
  });
  disk = installCpm22File(disk, {
    name: "ASSOC.SK8",
    bytes: await Deno.readFile("libraries/ASSOC.SK8"),
    padByte: 0x1a,
  });
}

// Pin the live-pair ceiling of four-byte pair cells.  This program loads only
// the core runtime and keeps 2,720 pairs (85 full 32-record pair pages) live;
// one more pair must stop with RUNTIME ERROR rather than corrupt the heap.
const livePairCeiling = 2720;
function livePairSource(count) {
  return `(define build (lambda (n acc) (if (zero? n) acc (build (- n 1) (cons n acc))))) (define len (lambda (l n) (if (null? l) n (len (cdr l) (+ n 1))))) (define keep (build ${count} '())) (begin (write (len keep 0)) (newline))`;
}
// The data group's disk directory is nearly full, so the ceiling cases run with
// the ordinary procedure group.  A probe build (deno task probe:on) has a
// larger runtime and fewer pair pages, so it skips the pin.
const probeBuild = (() => {
  try {
    Deno.statSync("build/PROBE");
    return true;
  } catch {
    return false;
  }
})();
const capacityCases = probeBuild ? [] : [
  [
    `PAIR${livePairCeiling}.SK8`,
    livePairSource(livePairCeiling),
    String(livePairCeiling),
  ],
];
const capacityRuntimeErrorCases = probeBuild ? [] : [
  [
    `PAIR${livePairCeiling + 1}.SK8`,
    livePairSource(livePairCeiling + 1),
    "RUNTIME ERROR\r\n",
  ],
];
const longA = `"${"a".repeat(200)}"`;
const longB = `"${"b".repeat(100)}"`;
const boundary = `"${"c".repeat(254)}"`;
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
  ["LIST8.SK8", "(list 1 2 3 4 5 6 7 8)", "(1 2 3 4 5 6 7 8)"],
  [
    "STRING8.SK8",
    "(string #\\a #\\b #\\c #\\d #\\e #\\f #\\g #\\h)",
    '"abcdefgh"',
  ],
  ["EQ.SK8", "(eq? 1 1)", "#t"],
  ["WRITE.SK8", "(begin (write (quote (1 2))) (newline))", "(1 2)"],
  ["DISPLAY.SK8", '(begin (display "hi") (newline))', "hi"],
  ["NEWLINE.SK8", '(begin (display "x") (newline))', "x"],
  ["EMPTYSTR.SK8", '(begin (write "") (newline))', '""'],
  [
    "STRLEN.SK8",
    '(begin (write (string-length "hello")) (newline))',
    "5",
  ],
  [
    "STRREF.SK8",
    '(begin (write (string-ref "hello" 1)) (newline))',
    "#\\e",
  ],
  [
    "CHARINT.SK8",
    "(begin (write (char->integer #\\A)) (newline))",
    "65",
  ],
  [
    "INTCHAR.SK8",
    "(begin (write (integer->char 65)) (newline))",
    "#\\A",
  ],
  [
    "PRIMSTR.SK8",
    "(begin (write (procedure? string-length)) (write (number? string-length)) (newline))",
    "#t#f",
  ],
  [
    "QCALL.SK8",
    "(define f (lambda () (quote (x)))) (begin (write (f)) (newline))",
    "(x)",
  ],
  [
    "LISTLIB.SK8",
    '(include "LIST.SK8") (begin (write (list-length (list 1 2 3))) (write (list-reverse (list 1 2 3))) (write (list-append (list 1) (list 2 3))) (write (list-map (lambda (x) (+ x 1)) (list 1 2))) (list-for-each (lambda (x) (write x)) (list 4 5)) (newline))',
    "3(3 2 1)(1 2 3)(2 3)45",
  ],
  [
    "LISTEDGE.SK8",
    "(include \"LIST.SK8\") (begin (write (list-length '())) (write (list-reverse '())) (write (list-append '() (list 9))) (write (list-length '(1 2 3 4 5 6 7 8))) (write (list-map (lambda (x) x) '(1 2 3 4 5 6 7 8))) (newline))",
    "0()(9)8(1 2 3 4 5 6 7 8)",
  ],
  [
    "ASSOCLIB.SK8",
    "(include \"ASSOC.SK8\") (define entries (list (cons 'a #f) (cons 'b 7))) (begin (write (member-eq? 'a (list 'a 'b))) (write (member-eq? 'c (list 'a 'b))) (write (assoc-eq 'a entries)) (write (assoc-eq 'b entries)) (write (assoc-eq 'c entries)) (newline))",
    "#t#f(a . #f)(b . 7)#f",
  ],
  [
    "ASORT.SK8",
    "(include \"ASSOC.SK8\") (begin (write (member-eq? 'a (cons 'a 2))) (write (assoc-eq 'a (cons (cons 'a #f) 2))) (newline))",
    "#t(a . #f)",
  ],
  [
    "STRLIB.SK8",
    `(define source (string #\\a #\\b)) (define copy (string-copy source)) (define loop (lambda (n) (if (zero? n) 0 (begin (string-copy "discard") (loop (- n 1)))))) (define build (lambda (n acc) (if (zero? n) acc (build (- n 1) (cons n acc))))) (define tail (lambda (p n) (if (zero? n) p (tail (cdr p) (- n 1))))) (define root (build 600 (string #\\z))) (loop 1200) (begin (write (string #\\A #\\B)) (write (string-length (string #\\x #\\y))) (write (string-ref (string #\\a #\\b) 1)) (write (string? (string #\\z))) (write (eq? "x" "x")) (write (eq? 'x 'x)) (write copy) (write (eq? source copy)) (write (string-append "ab" (string #\\c #\\d))) (write (string-length (string-copy ${boundary}))) (write (string? (tail root 600))) (newline) (write 0) (newline))`,
    '"AB"2#\\b#t#t#t"ab"#f"abcd"254#t\r\n0',
  ],
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
    "VECTOR8.SK8",
    "(define v (vector 1 2 3 4 5 6 7 8)) (begin (write (vector-length v)) (write (vector-ref v 0)) (write (vector-ref v 7)) (newline))",
    "818",
  ],
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
    "ECMANY.SK8",
    "(define loop (lambda (n) (if (zero? n) 0 (begin (call/ec (lambda (escape) (escape 1))) (loop (- n 1)))))) (loop 20000)",
    "0",
  ],
  [
    "GCLOCAL.SK8",
    "(define churn (lambda (n) (if (zero? n) 0 (begin (cons n 0) (churn (- n 1)))))) (let ((root (cons 41 42))) (begin (churn 5000) (car root)))",
    "41",
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
  [
    "CAPTURE2.SK8",
    "((lambda (a b) ((lambda () b))) 1 42)",
    "42",
  ],
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
// Twenty-four-bit exact integers: both endpoints, products and quotients at
// the bounds, printing, identity and equality, quoted and vector storage,
// case dispatch and mixed comparison with floats.
const int24Case = [
  "INT24.SK8",
  `(begin
    (write 8388607) (newline)
    (write -8388608) (newline)
    (write (+ 8388606 1)) (newline)
    (write (- -8388607 1)) (newline)
    (write (* 2896 2896)) (newline)
    (write (* -2048 4096)) (newline)
    (write (quotient 8388607 -1)) (newline)
    (write (quotient -8388608 2)) (newline)
    (write (remainder 8388607 1000)) (newline)
    (write (modulo -70000 7)) (newline)
    (write (modulo 100001 -7)) (newline)
    (write (abs -8388607)) (newline)
    (write (< 32767 32768)) (newline)
    (write (= 65536 65536)) (newline)
    (write (> -32769 -32768)) (newline)
    (write (eqv? 70000 70000)) (newline)
    (write (eq? 70000 70001)) (newline)
    (write (zero? 65536)) (newline)
    (write (number->string -8388608)) (newline)
    (write (quote (100000 -70000 255 256))) (newline)
    (write (vector-ref (vector 1000000 2) 0)) (newline)
    (write (case 70000 ((70000) 1) (else 2))) (newline)
    (write (equal? (list 70000) (list 70000))) (newline)
    (write (member 70000 (quote (1 70000 3)))) (newline)
    (write (+ 32768 0.5)) (write (+ 65536 0.5)) (newline)
    (write (< 40000 50000.0)) (newline)
    (write (= 32768 32768.0)) (newline)
    (write (> 65505 65504.0)) (newline))`,
  [
    "8388607",
    "-8388608",
    "8388607",
    "-8388608",
    "8386816",
    "-8388608",
    "-8388607",
    "-4194304",
    "607",
    "0",
    "-1",
    "8388607",
    "#t",
    "#t",
    "#f",
    "#t",
    "#f",
    "#f",
    '"-8388608"',
    "(100000 -70000 255 256)",
    "1000000",
    "1",
    "#t",
    "(70000 3)",
    "32768.565536.0",
    "#t",
    "#t",
    "#t",
  ].join("\r\n"),
];
integerCases.push(int24Case);
// A wide literal in every syntactic position the compiler reads ahead of:
// its third byte must survive each compile-time stash.
integerCases.push([
  "INT24POS.SK8",
  `(define g 100001)
   (define (f x) (+ x 100002))
   (define v (vector 100003 (if #t 100004 0) (cond (#f 0) (else 100005))))
   (define (h) 100006)
   (write (list g (f 1) (vector-ref v 0) (vector-ref v 1) (vector-ref v 2) (h)))
   (newline)
   (write (list (let ((a 100007) (b (+ 1 100008))) (list a b))
                (let* ((a 100009)) a)
                (letrec ((a (lambda () 100010))) (a))
                (let loop ((i 100011)) (if (> i 100011) 0 i))))
   (newline)
   (write (list (case 3 ((3) 100012) (else 0)) (when #t 100013)
                (unless #f 100014) (and 1 100015) (or #f 100016)
                (begin 100017)))
   (newline)
   (write (list ((lambda (x) x) 100018) ((lambda () 100019))
                (apply + (list 100020 1)) (begin (set! g 100021) g)
                (if #f 0 100022) (cond ((= 1 1) 100023))))
   (newline)
   (write (list (quote 100024) '(100025 . 100026) (car '((100027) 100028))
                (- 100029) (* -1 100030) (vector-ref (vector 100031) 0)))
   (newline)`,
  [
    "(100001 100003 100003 100004 100005 100006)",
    "((100007 100009) 100009 100010 100011)",
    "(100012 100013 100014 100015 100016 100017)",
    "(100018 100019 100021 100021 100022 100023)",
    "(100024 (100025 . 100026) (100027) -100029 -100030 100031)",
  ].join("\r\n"),
]);
const integerRuntimeErrorCases = [
  ["CXRBAD.SK8", "(cadr '(1))", "RUNTIME ERROR\r\n"],
  ["MAPBAD.SK8", "(map car 5)", "RUNTIME ERROR\r\n"],
  ["STRREFW.SK8", '(string-ref "abc" 65536)', "RUNTIME ERROR\r\n"],
  ["SSETLIT.SK8", '(string-set! "abc" 0 #\\x)', "RUNTIME ERROR\r\n"],
  ["S2NDEC.SK8", '(string->number "1.5")', "RUNTIME ERROR\r\n"],
  ["S2NBIG.SK8", '(string->number "8388608")', "RUNTIME ERROR\r\n"],
  ["L2SBAD.SK8", "(list->string '(1 2))", "RUNTIME ERROR\r\n"],
  [
    "DEEPEQ.SK8",
    "(define (nest n acc) (if (zero? n) acc (nest (- n 1) (cons acc '())))) (equal? (nest 900 '()) (nest 900 '()))",
    "RUNTIME ERROR\r\n",
  ],
  ["MAPNONE.SK8", "(for-each car)", "RUNTIME ERROR\r\n"],
  ["INTDIV0.SK8", "(quotient 7 0)", "RUNTIME ERROR\r\n"],
  ["INTREM0.SK8", "(remainder 7 0)", "RUNTIME ERROR\r\n"],
  ["INTTYPE.SK8", "(+ 1 #t)", "RUNTIME ERROR\r\n"],
  ["CMPBAD.SK8", "(< 1 #t)", "RUNTIME ERROR\r\n"],
  ["INTOVF.SK8", "(+ 8388607 1)", "RUNTIME ERROR\r\n"],
  ["INTQOVF.SK8", "(quotient -8388608 -1)", "RUNTIME ERROR\r\n"],
  ["INTMOVF.SK8", "(* 2897 2897)", "RUNTIME ERROR\r\n"],
  ["INTNOVF.SK8", "(- -8388608)", "RUNTIME ERROR\r\n"],
  ["INTAOVF.SK8", "(abs -8388608)", "RUNTIME ERROR\r\n"],
  ["INTVIDX.SK8", "(vector-ref (vector 1) 65536)", "RUNTIME ERROR\r\n"],
  ["INTLIDX.SK8", "(list-tail (list 1) 65536)", "RUNTIME ERROR\r\n"],
  ["INTWCHR.SK8", "(integer->char 65536)", "RUNTIME ERROR\r\n"],
  ["INCHERR.SK8", "(integer->char 256)", "RUNTIME ERROR\r\n"],
  ["NOTARITY.SK8", "(not #t #f)", "RUNTIME ERROR\r\n"],
  ["MINUS0.SK8", "(-)", "RUNTIME ERROR\r\n"],
  ["CMPARITY.SK8", "(< 1)", "RUNTIME ERROR\r\n"],
];
// Compiler regressions: tail context across nested ifs, forward global
// references from procedures, formal shadowing, if nesting capacity and
// control bytes inside tokens.
const regressionCases = [
  // caar through cdddr, and memv and assv as the eqv? forms of memq and assq.
  [
    "CXR.SK8",
    `(define x '((1 2) (3 4 5) 6 7))
(write (list (caar x) (cadr x) (cdar x) (cddr x)))
(newline)
(write (list (caadr x) (caddr x) (cdadr x) (cdddr x)))
(newline)
(write (list (caaar '(((a)))) (cadar '((a b))) (cdaar '(((a b)))) (cddar '((a b c)))))
(newline)
(write (list (memv 70000 '(1 70000 3)) (assv 2 '((1 . a) (2 . b))) (memv 9 '(1))))
(newline)`,
    "(1 (3 4 5) (2) (6 7))\r\n(3 6 (4 5) (7))\r\n(a b (b) (c))\r\n((70000 3) (2 . b) #f)",
  ],
  // Vector literals are self-evaluating quoted data, alone, quoted, nested
  // in lists and vectors, empty, at the 63-element quoted-datum limit, as
  // case results and under equal?.
  [
    "VECLIT.SK8",
    `(write #(1 2 3))
(newline)
(write '#(a "b" #\\c 1.5 -70000))
(newline)
(write '(1 #(2 (3)) #()))
(newline)
(write (vector-ref #(#(1 2) #(3 4)) 1))
(newline)
(write (vector-length '#(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62)))
(newline)
(define (f) #(9 8))
(write (eq? (f) (f)))
(write (equal? #(1 (2)) (vector 1 (list 2))))
(newline)
(write (case 2 ((1) #(one)) ((2) #(two))))
(newline)`,
    '#(1 2 3)\r\n#(a "b" #\\c 1.5 -70000)\r\n(1 #(2 (3)) #())\r\n#(3 4)\r\n63\r\n#t#t\r\n#(two)',
  ],
  // do loops are rewritten to named lets: results, missing steps and
  // results, nesting, a do as a body's first form, and constant-stack loops.
  [
    "DOLOOPS.SK8",
    `(write (do ((i 0 (+ i 1)) (acc '() (cons i acc))) ((= i 5) acc)))
(newline)
(write (do ((vec (make-vector 5)) (i 0 (+ i 1))) ((= i 5) vec) (vector-set! vec i i)))
(newline)
(write (let ((x '(1 3 5 7 9))) (do ((x x (cdr x)) (sum 0 (+ sum (car x)))) ((null? x) sum))))
(newline)
(define (count n) (do ((i 0 (+ i 1))) ((= i n)) (display i)))
(count 3)
(newline)
(write (do ((i 0 (+ i 1))) ((= i 3) (display "done") 'end)))
(newline)
(write (do ((i 0 (+ i 1)) (j 10)) ((= i 2) (list i j)) (do ((k 0 (+ k 1))) ((= k 2)) (display k))))
(newline)
(write (do ((i 0 (+ i 1)) (s 0 (+ s i))) ((= i 3000) s)))
(newline)`,
    "(4 3 2 1 0)\r\n#(0 1 2 3 4)\r\n25\r\n012\r\ndoneend\r\n0101(2 10)\r\n4498500",
  ],
  // map and for-each call procedures from the runtime: several lists, the
  // shortest list ending the walk, nesting, an escape out of the procedure,
  // apply, tail position and collections while the result is being built.
  [
    "MAPEACH.SK8",
    `(write (map car '((1 2) (3 4))))
(write (map + '(1 2 3) '(10 20 30)))
(write (map + '(1 2 3) '(1 2)))
(write (map (lambda (x) x) '()))
(newline)
(for-each (lambda (x y) (display (+ x y))) '(1 2) '(3 4))
(newline)
(write (map (lambda (l) (map (lambda (x) (+ x 1)) l)) '((1 2) (3))))
(write (call/ec (lambda (k) (map (lambda (x) (if (= x 3) (k 'out) x)) '(1 2 3 4)))))
(write (map - '(5 6)))
(newline)
(write (apply map list '((1 2) (3 4))))
(define (double l) (map (lambda (x) (* 2 x)) l))
(write (double '(1 2 3)))
(newline)
(define (iota n acc) (if (= n 0) acc (iota (- n 1) (cons n acc))))
(define big (iota 300 '()))
(define (sum l acc) (if (null? l) acc (sum (cdr l) (+ acc (car l)))))
(write (do ((i 0 (+ i 1)) (r big (map (lambda (x) (+ x 1)) big))) ((= i 6) (sum r 0))))
(newline)`,
    "(1 3)(11 22 33)(2 4)()\r\n46\r\n((2 3) (4))out(-5 -6)\r\n((1 3) (2 4))(2 4 6)\r\n45450",
  ],
  // equal? recurses on the native stack; a shallow structure still compares.
  [
    "EQDEPTH.SK8",
    "(define (nest n acc) (if (zero? n) acc (nest (- n 1) (cons acc '())))) (write (equal? (nest 100 '(1)) (nest 100 '(1)))) (write (equal? (nest 100 '(1)) (nest 100 '(2))))",
    "#t#f",
  ],
  // Each procedure's frame holds only its own slots: a procedure with many
  // locals no longer shrinks every other procedure's recursion depth, tail
  // calls move between small and large frames in constant stack, closures
  // nest across frame sizes, and a frame can grow while collections run.
  [
    "FRAMES.SK8",
    `(define (wide) (let* ((v0 0) (v1 1) (v2 2) (v3 3) (v4 4) (v5 5) (v6 6) (v7 7) (v8 8) (v9 9) (v10 10) (v11 11) (v12 12) (v13 13) (v14 14) (v15 15) (v16 16) (v17 17) (v18 18) (v19 19) (v20 20) (v21 21) (v22 22) (v23 23) (v24 24) (v25 25) (v26 26) (v27 27) (v28 28) (v29 29)) (+ v0 v29)))
(define (depth n) (if (= n 0) 0 (+ 1 (depth (- n 1)))))
(write (depth 180))
(write (wide))
(newline)
(define (small n) (if (= n 0) 'done (large n)))
(define (large n) (let* ((a 1) (b 2) (c 3) (d 4) (e 5) (f 6)) (small (- n (- a 0)))))
(write (small 5000))
(newline)
(define (mk x) (let ((y (+ x 1))) (lambda (z) (let ((w (* z 2))) (+ x y z w)))))
(write ((mk 1) 3))
(newline)
(define (thin n acc) (if (= n 0) (length acc) (thick n acc)))
(define (thick n acc) (let ((a (cons n acc)) (b 2) (c 3) (d 4)) (let ((g (lambda () a))) (thin (- n 1) (g)))))
(write (thin 1500 '()))
(newline)`,
    "18029\r\ndone\r\n12\r\n1500",
  ],
  // Calls pass up to 32 arguments and procedures take up to 32 formals, so
  // named let and do loops are no longer limited to four variables.
  [
    "ARGS32.SK8",
    `(define (ten a b c d e f g h i j) (list a b c d e f g h i j))
(write (ten 1 2 3 4 5 6 7 8 9 10))
(write (list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32))
(define (iota n acc) (if (= n 0) acc (iota (- n 1) (cons n acc))))
(write (apply + (iota 32 '())))
(newline)
(define (rst a b c d e . r) (list e r))
(write (rst 1 2 3 4 5 6 7))
(define (mk a b c d e f) (lambda () (+ a f)))
(write ((mk 1 2 3 4 5 6)))
(write (let loop ((a 0) (b 1) (c 2) (d 3) (e 4) (n 5)) (if (= n 0) (list a b c d e) (loop b c d e a (- n 1)))))
(write (do ((i 0 (+ i 1)) (a 1) (b 2) (c 3) (d 4) (e 5) (s 0 (+ s i))) ((= i 4) (list s a e))))
(define (all . r) (length r))
(write (apply all (iota 32 '())))
(define (f32 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16 a17 a18 a19 a20 a21 a22 a23 a24 a25 a26 a27 a28 a29 a30 a31 a32) (+ a1 a32))
(write (f32 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32))
(newline)`,
    "(1 2 3 4 5 6 7 8 9 10)(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32)528\r\n(5 (6 7))7(0 1 2 3 4)(6 1 5)3233",
  ],
  // The compiler's tables: a body of 150 calls, a do of 100 forms, 100
  // procedures, 26 nested lambdas, a cond of 120 clauses ending in calls,
  // 128 quoted symbols, and 600 distinct local names.
  [
    "TABLES.SK8",
    `(define (f i) (+ i 0) (+ i 1) (+ i 2) (+ i 3) (+ i 4) (+ i 5) (+ i 6) (+ i 7) (+ i 8) (+ i 9) (+ i 10) (+ i 11) (+ i 12) (+ i 13) (+ i 14) (+ i 15) (+ i 16) (+ i 17) (+ i 18) (+ i 19) (+ i 20) (+ i 21) (+ i 22) (+ i 23) (+ i 24) (+ i 25) (+ i 26) (+ i 27) (+ i 28) (+ i 29) (+ i 30) (+ i 31) (+ i 32) (+ i 33) (+ i 34) (+ i 35) (+ i 36) (+ i 37) (+ i 38) (+ i 39) (+ i 40) (+ i 41) (+ i 42) (+ i 43) (+ i 44) (+ i 45) (+ i 46) (+ i 47) (+ i 48) (+ i 49) (+ i 50) (+ i 51) (+ i 52) (+ i 53) (+ i 54) (+ i 55) (+ i 56) (+ i 57) (+ i 58) (+ i 59) (+ i 60) (+ i 61) (+ i 62) (+ i 63) (+ i 64) (+ i 65) (+ i 66) (+ i 67) (+ i 68) (+ i 69) (+ i 70) (+ i 71) (+ i 72) (+ i 73) (+ i 74) (+ i 75) (+ i 76) (+ i 77) (+ i 78) (+ i 79) (+ i 80) (+ i 81) (+ i 82) (+ i 83) (+ i 84) (+ i 85) (+ i 86) (+ i 87) (+ i 88) (+ i 89) (+ i 90) (+ i 91) (+ i 92) (+ i 93) (+ i 94) (+ i 95) (+ i 96) (+ i 97) (+ i 98) (+ i 99) (+ i 100) (+ i 101) (+ i 102) (+ i 103) (+ i 104) (+ i 105) (+ i 106) (+ i 107) (+ i 108) (+ i 109) (+ i 110) (+ i 111) (+ i 112) (+ i 113) (+ i 114) (+ i 115) (+ i 116) (+ i 117) (+ i 118) (+ i 119) (+ i 120) (+ i 121) (+ i 122) (+ i 123) (+ i 124) (+ i 125) (+ i 126) (+ i 127) (+ i 128) (+ i 129) (+ i 130) (+ i 131) (+ i 132) (+ i 133) (+ i 134) (+ i 135) (+ i 136) (+ i 137) (+ i 138) (+ i 139) (+ i 140) (+ i 141) (+ i 142) (+ i 143) (+ i 144) (+ i 145) (+ i 146) (+ i 147) (+ i 148) (+ i 149))
(write (f 1))
(write (do ((i 0 (+ i 1))) ((= i 2) 'ok) (+ i 0) (+ i 1) (+ i 2) (+ i 3) (+ i 4) (+ i 5) (+ i 6) (+ i 7) (+ i 8) (+ i 9) (+ i 10) (+ i 11) (+ i 12) (+ i 13) (+ i 14) (+ i 15) (+ i 16) (+ i 17) (+ i 18) (+ i 19) (+ i 20) (+ i 21) (+ i 22) (+ i 23) (+ i 24) (+ i 25) (+ i 26) (+ i 27) (+ i 28) (+ i 29) (+ i 30) (+ i 31) (+ i 32) (+ i 33) (+ i 34) (+ i 35) (+ i 36) (+ i 37) (+ i 38) (+ i 39) (+ i 40) (+ i 41) (+ i 42) (+ i 43) (+ i 44) (+ i 45) (+ i 46) (+ i 47) (+ i 48) (+ i 49) (+ i 50) (+ i 51) (+ i 52) (+ i 53) (+ i 54) (+ i 55) (+ i 56) (+ i 57) (+ i 58) (+ i 59) (+ i 60) (+ i 61) (+ i 62) (+ i 63) (+ i 64) (+ i 65) (+ i 66) (+ i 67) (+ i 68) (+ i 69) (+ i 70) (+ i 71) (+ i 72) (+ i 73) (+ i 74) (+ i 75) (+ i 76) (+ i 77) (+ i 78) (+ i 79) (+ i 80) (+ i 81) (+ i 82) (+ i 83) (+ i 84) (+ i 85) (+ i 86) (+ i 87) (+ i 88) (+ i 89) (+ i 90) (+ i 91) (+ i 92) (+ i 93) (+ i 94) (+ i 95) (+ i 96) (+ i 97) (+ i 98) (+ i 99)))
(define (g) (lambda () 0) (lambda () 1) (lambda () 2) (lambda () 3) (lambda () 4) (lambda () 5) (lambda () 6) (lambda () 7) (lambda () 8) (lambda () 9) (lambda () 10) (lambda () 11) (lambda () 12) (lambda () 13) (lambda () 14) (lambda () 15) (lambda () 16) (lambda () 17) (lambda () 18) (lambda () 19) (lambda () 20) (lambda () 21) (lambda () 22) (lambda () 23) (lambda () 24) (lambda () 25) (lambda () 26) (lambda () 27) (lambda () 28) (lambda () 29) (lambda () 30) (lambda () 31) (lambda () 32) (lambda () 33) (lambda () 34) (lambda () 35) (lambda () 36) (lambda () 37) (lambda () 38) (lambda () 39) (lambda () 40) (lambda () 41) (lambda () 42) (lambda () 43) (lambda () 44) (lambda () 45) (lambda () 46) (lambda () 47) (lambda () 48) (lambda () 49) (lambda () 50) (lambda () 51) (lambda () 52) (lambda () 53) (lambda () 54) (lambda () 55) (lambda () 56) (lambda () 57) (lambda () 58) (lambda () 59) (lambda () 60) (lambda () 61) (lambda () 62) (lambda () 63) (lambda () 64) (lambda () 65) (lambda () 66) (lambda () 67) (lambda () 68) (lambda () 69) (lambda () 70) (lambda () 71) (lambda () 72) (lambda () 73) (lambda () 74) (lambda () 75) (lambda () 76) (lambda () 77) (lambda () 78) (lambda () 79) (lambda () 80) (lambda () 81) (lambda () 82) (lambda () 83) (lambda () 84) (lambda () 85) (lambda () 86) (lambda () 87) (lambda () 88) (lambda () 89) (lambda () 90) (lambda () 91) (lambda () 92) (lambda () 93) (lambda () 94) (lambda () 95) (lambda () 96) (lambda () 97) (lambda () 98) (lambda () 99) 7)
(write (g))
(write (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () (lambda () 7)))))))))))))))))))))))))))
(define (id y) y)
(define (h x) (cond ((= x 0) (id 0)) ((= x 1) (id 1)) ((= x 2) (id 2)) ((= x 3) (id 3)) ((= x 4) (id 4)) ((= x 5) (id 5)) ((= x 6) (id 6)) ((= x 7) (id 7)) ((= x 8) (id 8)) ((= x 9) (id 9)) ((= x 10) (id 10)) ((= x 11) (id 11)) ((= x 12) (id 12)) ((= x 13) (id 13)) ((= x 14) (id 14)) ((= x 15) (id 15)) ((= x 16) (id 16)) ((= x 17) (id 17)) ((= x 18) (id 18)) ((= x 19) (id 19)) ((= x 20) (id 20)) ((= x 21) (id 21)) ((= x 22) (id 22)) ((= x 23) (id 23)) ((= x 24) (id 24)) ((= x 25) (id 25)) ((= x 26) (id 26)) ((= x 27) (id 27)) ((= x 28) (id 28)) ((= x 29) (id 29)) ((= x 30) (id 30)) ((= x 31) (id 31)) ((= x 32) (id 32)) ((= x 33) (id 33)) ((= x 34) (id 34)) ((= x 35) (id 35)) ((= x 36) (id 36)) ((= x 37) (id 37)) ((= x 38) (id 38)) ((= x 39) (id 39)) ((= x 40) (id 40)) ((= x 41) (id 41)) ((= x 42) (id 42)) ((= x 43) (id 43)) ((= x 44) (id 44)) ((= x 45) (id 45)) ((= x 46) (id 46)) ((= x 47) (id 47)) ((= x 48) (id 48)) ((= x 49) (id 49)) ((= x 50) (id 50)) ((= x 51) (id 51)) ((= x 52) (id 52)) ((= x 53) (id 53)) ((= x 54) (id 54)) ((= x 55) (id 55)) ((= x 56) (id 56)) ((= x 57) (id 57)) ((= x 58) (id 58)) ((= x 59) (id 59)) ((= x 60) (id 60)) ((= x 61) (id 61)) ((= x 62) (id 62)) ((= x 63) (id 63)) ((= x 64) (id 64)) ((= x 65) (id 65)) ((= x 66) (id 66)) ((= x 67) (id 67)) ((= x 68) (id 68)) ((= x 69) (id 69)) ((= x 70) (id 70)) ((= x 71) (id 71)) ((= x 72) (id 72)) ((= x 73) (id 73)) ((= x 74) (id 74)) ((= x 75) (id 75)) ((= x 76) (id 76)) ((= x 77) (id 77)) ((= x 78) (id 78)) ((= x 79) (id 79)) ((= x 80) (id 80)) ((= x 81) (id 81)) ((= x 82) (id 82)) ((= x 83) (id 83)) ((= x 84) (id 84)) ((= x 85) (id 85)) ((= x 86) (id 86)) ((= x 87) (id 87)) ((= x 88) (id 88)) ((= x 89) (id 89)) ((= x 90) (id 90)) ((= x 91) (id 91)) ((= x 92) (id 92)) ((= x 93) (id 93)) ((= x 94) (id 94)) ((= x 95) (id 95)) ((= x 96) (id 96)) ((= x 97) (id 97)) ((= x 98) (id 98)) ((= x 99) (id 99)) ((= x 100) (id 100)) ((= x 101) (id 101)) ((= x 102) (id 102)) ((= x 103) (id 103)) ((= x 104) (id 104)) ((= x 105) (id 105)) ((= x 106) (id 106)) ((= x 107) (id 107)) ((= x 108) (id 108)) ((= x 109) (id 109)) ((= x 110) (id 110)) ((= x 111) (id 111)) ((= x 112) (id 112)) ((= x 113) (id 113)) ((= x 114) (id 114)) ((= x 115) (id 115)) ((= x 116) (id 116)) ((= x 117) (id 117)) ((= x 118) (id 118)) ((= x 119) (id 119))))
(write (h 119))
(write (length (list '(q0 q1 q2 q3 q4 q5 q6 q7 q8 q9 q10 q11 q12 q13 q14 q15 q16 q17 q18 q19 q20 q21 q22 q23 q24 q25 q26 q27 q28 q29 q30 q31 q32 q33 q34 q35 q36 q37 q38 q39 q40 q41 q42) '(r0 r1 r2 r3 r4 r5 r6 r7 r8 r9 r10 r11 r12 r13 r14 r15 r16 r17 r18 r19 r20 r21 r22 r23 r24 r25 r26 r27 r28 r29 r30 r31 r32 r33 r34 r35 r36 r37 r38 r39 r40 r41 r42) '(t0 t1 t2 t3 t4 t5 t6 t7 t8 t9 t10 t11 t12 t13 t14 t15 t16 t17 t18 t19 t20 t21 t22 t23 t24 t25 t26 t27 t28 t29 t30 t31 t32 t33 t34 t35 t36 t37 t38 t39 t40))))
(newline)`,
    "150ok7#<procedure>1193",
  ],
  [
    "SYMS600.SK8",
    "(define (m) (let ((a0 0)) a0) (let ((a1 0)) a1) (let ((a2 0)) a2) (let ((a3 0)) a3) (let ((a4 0)) a4) (let ((a5 0)) a5) (let ((a6 0)) a6) (let ((a7 0)) a7) (let ((a8 0)) a8) (let ((a9 0)) a9) (let ((a10 0)) a10) (let ((a11 0)) a11) (let ((a12 0)) a12) (let ((a13 0)) a13) (let ((a14 0)) a14) (let ((a15 0)) a15) (let ((a16 0)) a16) (let ((a17 0)) a17) (let ((a18 0)) a18) (let ((a19 0)) a19) (let ((a20 0)) a20) (let ((a21 0)) a21) (let ((a22 0)) a22) (let ((a23 0)) a23) (let ((a24 0)) a24) (let ((a25 0)) a25) (let ((a26 0)) a26) (let ((a27 0)) a27) (let ((a28 0)) a28) (let ((a29 0)) a29) (let ((a30 0)) a30) (let ((a31 0)) a31) (let ((a32 0)) a32) (let ((a33 0)) a33) (let ((a34 0)) a34) (let ((a35 0)) a35) (let ((a36 0)) a36) (let ((a37 0)) a37) (let ((a38 0)) a38) (let ((a39 0)) a39) (let ((a40 0)) a40) (let ((a41 0)) a41) (let ((a42 0)) a42) (let ((a43 0)) a43) (let ((a44 0)) a44) (let ((a45 0)) a45) (let ((a46 0)) a46) (let ((a47 0)) a47) (let ((a48 0)) a48) (let ((a49 0)) a49) (let ((a50 0)) a50) (let ((a51 0)) a51) (let ((a52 0)) a52) (let ((a53 0)) a53) (let ((a54 0)) a54) (let ((a55 0)) a55) (let ((a56 0)) a56) (let ((a57 0)) a57) (let ((a58 0)) a58) (let ((a59 0)) a59) (let ((a60 0)) a60) (let ((a61 0)) a61) (let ((a62 0)) a62) (let ((a63 0)) a63) (let ((a64 0)) a64) (let ((a65 0)) a65) (let ((a66 0)) a66) (let ((a67 0)) a67) (let ((a68 0)) a68) (let ((a69 0)) a69) (let ((a70 0)) a70) (let ((a71 0)) a71) (let ((a72 0)) a72) (let ((a73 0)) a73) (let ((a74 0)) a74) (let ((a75 0)) a75) (let ((a76 0)) a76) (let ((a77 0)) a77) (let ((a78 0)) a78) (let ((a79 0)) a79) (let ((a80 0)) a80) (let ((a81 0)) a81) (let ((a82 0)) a82) (let ((a83 0)) a83) (let ((a84 0)) a84) (let ((a85 0)) a85) (let ((a86 0)) a86) (let ((a87 0)) a87) (let ((a88 0)) a88) (let ((a89 0)) a89) (let ((a90 0)) a90) (let ((a91 0)) a91) (let ((a92 0)) a92) (let ((a93 0)) a93) (let ((a94 0)) a94) (let ((a95 0)) a95) (let ((a96 0)) a96) (let ((a97 0)) a97) (let ((a98 0)) a98) (let ((a99 0)) a99) (let ((a100 0)) a100) (let ((a101 0)) a101) (let ((a102 0)) a102) (let ((a103 0)) a103) (let ((a104 0)) a104) (let ((a105 0)) a105) (let ((a106 0)) a106) (let ((a107 0)) a107) (let ((a108 0)) a108) (let ((a109 0)) a109) (let ((a110 0)) a110) (let ((a111 0)) a111) (let ((a112 0)) a112) (let ((a113 0)) a113) (let ((a114 0)) a114) (let ((a115 0)) a115) (let ((a116 0)) a116) (let ((a117 0)) a117) (let ((a118 0)) a118) (let ((a119 0)) a119) (let ((a120 0)) a120) (let ((a121 0)) a121) (let ((a122 0)) a122) (let ((a123 0)) a123) (let ((a124 0)) a124) (let ((a125 0)) a125) (let ((a126 0)) a126) (let ((a127 0)) a127) (let ((a128 0)) a128) (let ((a129 0)) a129) (let ((a130 0)) a130) (let ((a131 0)) a131) (let ((a132 0)) a132) (let ((a133 0)) a133) (let ((a134 0)) a134) (let ((a135 0)) a135) (let ((a136 0)) a136) (let ((a137 0)) a137) (let ((a138 0)) a138) (let ((a139 0)) a139) (let ((a140 0)) a140) (let ((a141 0)) a141) (let ((a142 0)) a142) (let ((a143 0)) a143) (let ((a144 0)) a144) (let ((a145 0)) a145) (let ((a146 0)) a146) (let ((a147 0)) a147) (let ((a148 0)) a148) (let ((a149 0)) a149) (let ((a150 0)) a150) (let ((a151 0)) a151) (let ((a152 0)) a152) (let ((a153 0)) a153) (let ((a154 0)) a154) (let ((a155 0)) a155) (let ((a156 0)) a156) (let ((a157 0)) a157) (let ((a158 0)) a158) (let ((a159 0)) a159) (let ((a160 0)) a160) (let ((a161 0)) a161) (let ((a162 0)) a162) (let ((a163 0)) a163) (let ((a164 0)) a164) (let ((a165 0)) a165) (let ((a166 0)) a166) (let ((a167 0)) a167) (let ((a168 0)) a168) (let ((a169 0)) a169) (let ((a170 0)) a170) (let ((a171 0)) a171) (let ((a172 0)) a172) (let ((a173 0)) a173) (let ((a174 0)) a174) (let ((a175 0)) a175) (let ((a176 0)) a176) (let ((a177 0)) a177) (let ((a178 0)) a178) (let ((a179 0)) a179) (let ((a180 0)) a180) (let ((a181 0)) a181) (let ((a182 0)) a182) (let ((a183 0)) a183) (let ((a184 0)) a184) (let ((a185 0)) a185) (let ((a186 0)) a186) (let ((a187 0)) a187) (let ((a188 0)) a188) (let ((a189 0)) a189) (let ((a190 0)) a190) (let ((a191 0)) a191) (let ((a192 0)) a192) (let ((a193 0)) a193) (let ((a194 0)) a194) (let ((a195 0)) a195) (let ((a196 0)) a196) (let ((a197 0)) a197) (let ((a198 0)) a198) (let ((a199 0)) a199) (let ((a200 0)) a200) (let ((a201 0)) a201) (let ((a202 0)) a202) (let ((a203 0)) a203) (let ((a204 0)) a204) (let ((a205 0)) a205) (let ((a206 0)) a206) (let ((a207 0)) a207) (let ((a208 0)) a208) (let ((a209 0)) a209) (let ((a210 0)) a210) (let ((a211 0)) a211) (let ((a212 0)) a212) (let ((a213 0)) a213) (let ((a214 0)) a214) (let ((a215 0)) a215) (let ((a216 0)) a216) (let ((a217 0)) a217) (let ((a218 0)) a218) (let ((a219 0)) a219) (let ((a220 0)) a220) (let ((a221 0)) a221) (let ((a222 0)) a222) (let ((a223 0)) a223) (let ((a224 0)) a224) (let ((a225 0)) a225) (let ((a226 0)) a226) (let ((a227 0)) a227) (let ((a228 0)) a228) (let ((a229 0)) a229) (let ((a230 0)) a230) (let ((a231 0)) a231) (let ((a232 0)) a232) (let ((a233 0)) a233) (let ((a234 0)) a234) (let ((a235 0)) a235) (let ((a236 0)) a236) (let ((a237 0)) a237) (let ((a238 0)) a238) (let ((a239 0)) a239) (let ((a240 0)) a240) (let ((a241 0)) a241) (let ((a242 0)) a242) (let ((a243 0)) a243) (let ((a244 0)) a244) (let ((a245 0)) a245) (let ((a246 0)) a246) (let ((a247 0)) a247) (let ((a248 0)) a248) (let ((a249 0)) a249) (let ((a250 0)) a250) (let ((a251 0)) a251) (let ((a252 0)) a252) (let ((a253 0)) a253) (let ((a254 0)) a254) (let ((a255 0)) a255) (let ((a256 0)) a256) (let ((a257 0)) a257) (let ((a258 0)) a258) (let ((a259 0)) a259) (let ((a260 0)) a260) (let ((a261 0)) a261) (let ((a262 0)) a262) (let ((a263 0)) a263) (let ((a264 0)) a264) (let ((a265 0)) a265) (let ((a266 0)) a266) (let ((a267 0)) a267) (let ((a268 0)) a268) (let ((a269 0)) a269) (let ((a270 0)) a270) (let ((a271 0)) a271) (let ((a272 0)) a272) (let ((a273 0)) a273) (let ((a274 0)) a274) (let ((a275 0)) a275) (let ((a276 0)) a276) (let ((a277 0)) a277) (let ((a278 0)) a278) (let ((a279 0)) a279) (let ((a280 0)) a280) (let ((a281 0)) a281) (let ((a282 0)) a282) (let ((a283 0)) a283) (let ((a284 0)) a284) (let ((a285 0)) a285) (let ((a286 0)) a286) (let ((a287 0)) a287) (let ((a288 0)) a288) (let ((a289 0)) a289) (let ((a290 0)) a290) (let ((a291 0)) a291) (let ((a292 0)) a292) (let ((a293 0)) a293) (let ((a294 0)) a294) (let ((a295 0)) a295) (let ((a296 0)) a296) (let ((a297 0)) a297) (let ((a298 0)) a298) (let ((a299 0)) a299) (let ((a300 0)) a300) (let ((a301 0)) a301) (let ((a302 0)) a302) (let ((a303 0)) a303) (let ((a304 0)) a304) (let ((a305 0)) a305) (let ((a306 0)) a306) (let ((a307 0)) a307) (let ((a308 0)) a308) (let ((a309 0)) a309) (let ((a310 0)) a310) (let ((a311 0)) a311) (let ((a312 0)) a312) (let ((a313 0)) a313) (let ((a314 0)) a314) (let ((a315 0)) a315) (let ((a316 0)) a316) (let ((a317 0)) a317) (let ((a318 0)) a318) (let ((a319 0)) a319) (let ((a320 0)) a320) (let ((a321 0)) a321) (let ((a322 0)) a322) (let ((a323 0)) a323) (let ((a324 0)) a324) (let ((a325 0)) a325) (let ((a326 0)) a326) (let ((a327 0)) a327) (let ((a328 0)) a328) (let ((a329 0)) a329) (let ((a330 0)) a330) (let ((a331 0)) a331) (let ((a332 0)) a332) (let ((a333 0)) a333) (let ((a334 0)) a334) (let ((a335 0)) a335) (let ((a336 0)) a336) (let ((a337 0)) a337) (let ((a338 0)) a338) (let ((a339 0)) a339) (let ((a340 0)) a340) (let ((a341 0)) a341) (let ((a342 0)) a342) (let ((a343 0)) a343) (let ((a344 0)) a344) (let ((a345 0)) a345) (let ((a346 0)) a346) (let ((a347 0)) a347) (let ((a348 0)) a348) (let ((a349 0)) a349) (let ((a350 0)) a350) (let ((a351 0)) a351) (let ((a352 0)) a352) (let ((a353 0)) a353) (let ((a354 0)) a354) (let ((a355 0)) a355) (let ((a356 0)) a356) (let ((a357 0)) a357) (let ((a358 0)) a358) (let ((a359 0)) a359) (let ((a360 0)) a360) (let ((a361 0)) a361) (let ((a362 0)) a362) (let ((a363 0)) a363) (let ((a364 0)) a364) (let ((a365 0)) a365) (let ((a366 0)) a366) (let ((a367 0)) a367) (let ((a368 0)) a368) (let ((a369 0)) a369) (let ((a370 0)) a370) (let ((a371 0)) a371) (let ((a372 0)) a372) (let ((a373 0)) a373) (let ((a374 0)) a374) (let ((a375 0)) a375) (let ((a376 0)) a376) (let ((a377 0)) a377) (let ((a378 0)) a378) (let ((a379 0)) a379) (let ((a380 0)) a380) (let ((a381 0)) a381) (let ((a382 0)) a382) (let ((a383 0)) a383) (let ((a384 0)) a384) (let ((a385 0)) a385) (let ((a386 0)) a386) (let ((a387 0)) a387) (let ((a388 0)) a388) (let ((a389 0)) a389) (let ((a390 0)) a390) (let ((a391 0)) a391) (let ((a392 0)) a392) (let ((a393 0)) a393) (let ((a394 0)) a394) (let ((a395 0)) a395) (let ((a396 0)) a396) (let ((a397 0)) a397) (let ((a398 0)) a398) (let ((a399 0)) a399) (let ((a400 0)) a400) (let ((a401 0)) a401) (let ((a402 0)) a402) (let ((a403 0)) a403) (let ((a404 0)) a404) (let ((a405 0)) a405) (let ((a406 0)) a406) (let ((a407 0)) a407) (let ((a408 0)) a408) (let ((a409 0)) a409) (let ((a410 0)) a410) (let ((a411 0)) a411) (let ((a412 0)) a412) (let ((a413 0)) a413) (let ((a414 0)) a414) (let ((a415 0)) a415) (let ((a416 0)) a416) (let ((a417 0)) a417) (let ((a418 0)) a418) (let ((a419 0)) a419) (let ((a420 0)) a420) (let ((a421 0)) a421) (let ((a422 0)) a422) (let ((a423 0)) a423) (let ((a424 0)) a424) (let ((a425 0)) a425) (let ((a426 0)) a426) (let ((a427 0)) a427) (let ((a428 0)) a428) (let ((a429 0)) a429) (let ((a430 0)) a430) (let ((a431 0)) a431) (let ((a432 0)) a432) (let ((a433 0)) a433) (let ((a434 0)) a434) (let ((a435 0)) a435) (let ((a436 0)) a436) (let ((a437 0)) a437) (let ((a438 0)) a438) (let ((a439 0)) a439) (let ((a440 0)) a440) (let ((a441 0)) a441) (let ((a442 0)) a442) (let ((a443 0)) a443) (let ((a444 0)) a444) (let ((a445 0)) a445) (let ((a446 0)) a446) (let ((a447 0)) a447) (let ((a448 0)) a448) (let ((a449 0)) a449) (let ((a450 0)) a450) (let ((a451 0)) a451) (let ((a452 0)) a452) (let ((a453 0)) a453) (let ((a454 0)) a454) (let ((a455 0)) a455) (let ((a456 0)) a456) (let ((a457 0)) a457) (let ((a458 0)) a458) (let ((a459 0)) a459) (let ((a460 0)) a460) (let ((a461 0)) a461) (let ((a462 0)) a462) (let ((a463 0)) a463) (let ((a464 0)) a464) (let ((a465 0)) a465) (let ((a466 0)) a466) (let ((a467 0)) a467) (let ((a468 0)) a468) (let ((a469 0)) a469) (let ((a470 0)) a470) (let ((a471 0)) a471) (let ((a472 0)) a472) (let ((a473 0)) a473) (let ((a474 0)) a474) (let ((a475 0)) a475) (let ((a476 0)) a476) (let ((a477 0)) a477) (let ((a478 0)) a478) (let ((a479 0)) a479) (let ((a480 0)) a480) (let ((a481 0)) a481) (let ((a482 0)) a482) (let ((a483 0)) a483) (let ((a484 0)) a484) (let ((a485 0)) a485) (let ((a486 0)) a486) (let ((a487 0)) a487) (let ((a488 0)) a488) (let ((a489 0)) a489) (let ((a490 0)) a490) (let ((a491 0)) a491) (let ((a492 0)) a492) (let ((a493 0)) a493) (let ((a494 0)) a494) (let ((a495 0)) a495) (let ((a496 0)) a496) (let ((a497 0)) a497) (let ((a498 0)) a498) (let ((a499 0)) a499) (let ((a500 0)) a500) (let ((a501 0)) a501) (let ((a502 0)) a502) (let ((a503 0)) a503) (let ((a504 0)) a504) (let ((a505 0)) a505) (let ((a506 0)) a506) (let ((a507 0)) a507) (let ((a508 0)) a508) (let ((a509 0)) a509) (let ((a510 0)) a510) (let ((a511 0)) a511) (let ((a512 0)) a512) (let ((a513 0)) a513) (let ((a514 0)) a514) (let ((a515 0)) a515) (let ((a516 0)) a516) (let ((a517 0)) a517) (let ((a518 0)) a518) (let ((a519 0)) a519) (let ((a520 0)) a520) (let ((a521 0)) a521) (let ((a522 0)) a522) (let ((a523 0)) a523) (let ((a524 0)) a524) (let ((a525 0)) a525) (let ((a526 0)) a526) (let ((a527 0)) a527) (let ((a528 0)) a528) (let ((a529 0)) a529) (let ((a530 0)) a530) (let ((a531 0)) a531) (let ((a532 0)) a532) (let ((a533 0)) a533) (let ((a534 0)) a534) (let ((a535 0)) a535) (let ((a536 0)) a536) (let ((a537 0)) a537) (let ((a538 0)) a538) (let ((a539 0)) a539) (let ((a540 0)) a540) (let ((a541 0)) a541) (let ((a542 0)) a542) (let ((a543 0)) a543) (let ((a544 0)) a544) (let ((a545 0)) a545) (let ((a546 0)) a546) (let ((a547 0)) a547) (let ((a548 0)) a548) (let ((a549 0)) a549) (let ((a550 0)) a550) (let ((a551 0)) a551) (let ((a552 0)) a552) (let ((a553 0)) a553) (let ((a554 0)) a554) (let ((a555 0)) a555) (let ((a556 0)) a556) (let ((a557 0)) a557) (let ((a558 0)) a558) (let ((a559 0)) a559) (let ((a560 0)) a560) (let ((a561 0)) a561) (let ((a562 0)) a562) (let ((a563 0)) a563) (let ((a564 0)) a564) (let ((a565 0)) a565) (let ((a566 0)) a566) (let ((a567 0)) a567) (let ((a568 0)) a568) (let ((a569 0)) a569) (let ((a570 0)) a570) (let ((a571 0)) a571) (let ((a572 0)) a572) (let ((a573 0)) a573) (let ((a574 0)) a574) (let ((a575 0)) a575) (let ((a576 0)) a576) (let ((a577 0)) a577) (let ((a578 0)) a578) (let ((a579 0)) a579) (let ((a580 0)) a580) (let ((a581 0)) a581) (let ((a582 0)) a582) (let ((a583 0)) a583) (let ((a584 0)) a584) (let ((a585 0)) a585) (let ((a586 0)) a586) (let ((a587 0)) a587) (let ((a588 0)) a588) (let ((a589 0)) a589) (let ((a590 0)) a590) (let ((a591 0)) a591) (let ((a592 0)) a592) (let ((a593 0)) a593) (let ((a594 0)) a594) (let ((a595 0)) a595) (let ((a596 0)) a596) (let ((a597 0)) a597) (let ((a598 0)) a598) (let ((a599 0)) a599) 5) (write (m))",
    "5",
  ],
  // Conversions between lists, vectors and strings, string and vector
  // mutation, list-copy, string->number and string-append of any length.
  [
    "CONVERT.SK8",
    `(write (list->vector '(1 2 3)))
(write (vector->list #(a "b" 3)))
(write (string->list "abc"))
(write (list->string (list #\\x #\\y)))
(newline)
(write (make-string 3 #\\z))
(write (string-length (make-string 2)))
(define s (make-string 3 #\\a))
(string-set! s 1 #\\b)
(write s)
(define v (make-vector 3 0))
(vector-fill! v 7)
(write v)
(newline)
(define l '(1 2 3))
(define c (list-copy l))
(write (list c (eq? l c) (equal? l c)))
(newline)
(write (list (string->number "42") (string->number "-17") (string->number "ff" 16) (string->number "101" 2) (string->number "abc") (string->number "") (string->number "-") (string->number "8388607") (string->number "-8388608")))
(newline)
(write (string-append))
(write (string-append "a" "bc" "" "def"))
(write (vector->list (list->vector (string->list "hi"))))
(newline)`,
    '#(1 2 3)(a "b" 3)(#\\a #\\b #\\c)"xy"\r\n"zzz"2"aba"#(7 7 7)\r\n((1 2 3) #f #t)\r\n(42 -17 255 5 #f #f #f 8388607 -8388608)\r\n"""abcdef"(#\\h #\\i)',
  ],
  // A nested procedure body must not overwrite the enclosing body's pending
  // tail-call records: a non-final named let or a lambda after a tail call
  // once returned from the enclosing procedure.
  [
    "TAILNLET.SK8",
    "(define (g) (let loop ((i 0)) (if (< i 3) (loop (+ i 1)) i)) 7) (g)",
    "7",
  ],
  // Descriptors are emitted as procedures close, so a program is no longer
  // limited to the 21 records the compiler once held until the end.
  [
    "PROCS40.SK8",
    Array.from(
      { length: 40 },
      (_, index) =>
        index === 0
          ? "(define (p0) 0)"
          : `(define (p${index}) (+ (p${index - 1}) 1))`,
    ).join(" ") + " (p39)",
    "39",
  ],
  // Globals live at fixed addresses, so references to them take no entries
  // in the 320-record fixup table: this program makes 400.
  [
    "GREFS.SK8",
    "(define x 0) " + "(set! x (+ x 1)) ".repeat(200) + "x",
    "200",
  ],
  [
    "TAILLAM.SK8",
    "(define (k) 1) (define (f c) (if c (k) (lambda () (k))) 2) (f #t)",
    "2",
  ],
  [
    "TAILIFIF.SK8",
    "(define (loop n) (if (if (= n 0) #f #t) (loop (- n 1)) 0)) (loop 4000)",
    "0",
  ],
  [
    "TAILIFLM.SK8",
    "(define (g) 10) (+ 1 (if ((lambda () (if #t #t #f))) (g) 0))",
    "11",
  ],
  [
    "FWDREC.SK8",
    "(define (f) (letrec ((a (lambda () (g)))) (a))) (define (g) 5) (f)",
    "5",
  ],
  [
    "SHADOWQ.SK8",
    "(define (f q) (let ((a 1)) (lambda () a)) ((lambda (x) (define q 3) (+ q x)) 1)) (f 9)",
    "4",
  ],
  [
    "FWDLET.SK8",
    "(define (f) (letrec ((a (let ((t 1)) (+ t (g))))) a)) (define (g) 5) (f)",
    "6",
  ],
];
const regressionErrorCases = [
  ["VECDOT.SK8", "(write '#(1 . 2))", "COMPILE ERROR\r\n"],
  ["IF65.SK8", "(if #t ".repeat(65) + "1" + " 2)".repeat(65), "CAP\r\n"],
  ["CTLTOKEN.SK8", "(quote ab\x01c)", "COMPILE ERROR\r\n"],
  ["NULTOKEN.SK8", "(write +inf.0\x00-inf.0)", "COMPILE ERROR\r\n"],
];
// Each mode flag selects one proof group.  Several flags may be combined so a
// single run (and a single assembly of the compiler and runtime) covers them.
const modeFlags = [
  "runtime-errors",
  "regressions",
  "integers",
  "apply",
  "ec",
  "vectors",
  "data",
];
const modes = modeFlags.filter((mode) => Deno.args.includes(`--${mode}`));
if (modes.length === 0) modes.push("regular");
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
const regularCases = [
  ...cases.filter(([name]) =>
    !applyCaseNames.has(name) && !ecCaseNames.has(name)
  ),
  ...capacityCases,
];
function programCasesFor(mode) {
  switch (mode) {
    case "runtime-errors":
      return [];
    case "regressions":
      return regressionCases;
    case "integers":
      return integerCases;
    case "apply":
      return cases.filter(([name]) => applyCaseNames.has(name));
    case "ec":
      return cases.filter(([name]) => name.startsWith("EC"));
    case "vectors":
      return vectorCases;
    case "data":
      return dataCases;
    default:
      return regularCases;
  }
}
function uniqueCases(groups) {
  const seen = new Set();
  return groups.flat().filter(([name]) => {
    if (seen.has(name)) return false;
    seen.add(name);
    return true;
  });
}
const selectedCases = uniqueCases(modes.map(programCasesFor));

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
  [
    "LISTBAD.SK8",
    '(include "LIST.SK8") (list-length (cons 1 2))',
    "RUNTIME ERROR\r\n",
  ],
  [
    "LAPPERR.SK8",
    '(include "LIST.SK8") (list-append \'() (cons 1 2))',
    "RUNTIME ERROR\r\n",
  ],
  [
    "ASSOCBAD.SK8",
    "(include \"ASSOC.SK8\") (member-eq? 'missing (cons 'present 2))",
    "RUNTIME ERROR\r\n",
  ],
  ["STCHERR.SK8", "(string 65)", "RUNTIME ERROR\r\n"],
  [
    "SRFDYN.SK8",
    "(string-ref (string #\\a) 1)",
    "RUNTIME ERROR\r\n",
  ],
  [
    "STRLONG.SK8",
    `(string-append ${longA} ${longB})`,
    "RUNTIME ERROR\r\n",
  ],
  ["STRREFER.SK8", '(string-ref "x" 1)', "RUNTIME ERROR\r\n"],
  ["STRTYPE.SK8", '(string-ref "x" #\\A)', "RUNTIME ERROR\r\n"],
  ["CHINTERR.SK8", "(char->integer 65)", "RUNTIME ERROR\r\n"],
];
function errorCasesFor(mode) {
  switch (mode) {
    case "regressions":
      return regressionErrorCases;
    case "runtime-errors":
    case "apply":
    case "integers":
      return [["INTWIDE.SK8", "(write 8388608)", "COMPILE ERROR\r\n"]];
    case "ec":
      return errorCases.filter(([name]) => name.startsWith("EC"));
    case "data":
      return dataErrorCases;
    default:
      return [...errorCases, ...restErrorCases];
  }
}
function runtimeErrorCasesFor(mode) {
  switch (mode) {
    case "regressions":
      return [];
    case "runtime-errors":
      // The call/ec runtime errors belong to the --ec group.
      return runtimeErrorCases.filter(([name]) => !name.startsWith("EC"));
    case "apply":
      return applyRuntimeErrorCases;
    case "integers":
      return integerRuntimeErrorCases;
    case "ec":
      return runtimeErrorCases.filter(([name]) => name.startsWith("EC"));
    case "vectors":
      return vectorRuntimeErrorCases;
    case "data":
      return dataRuntimeErrorCases;
    default:
      return capacityRuntimeErrorCases;
  }
}
const selectedErrorCases = uniqueCases(modes.map(errorCasesFor));
const selectedRuntimeErrorCases = uniqueCases(modes.map(runtimeErrorCasesFor));
const caseArgument = Deno.args.find((argument) =>
  argument.startsWith("--case=")
);
if (caseArgument !== undefined) {
  const requestedName = caseArgument.slice("--case=".length).toUpperCase();
  const groups = [selectedCases, selectedErrorCases, selectedRuntimeErrorCases];
  assert.ok(
    groups.some((group) => group.some(([name]) => name === requestedName)),
    `No case ${requestedName} in the selected proof group`,
  );
  for (const group of groups) {
    const matching = group.filter(([name]) => name === requestedName);
    group.splice(0, group.length, ...matching);
  }
}

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
// Nested tail apply allocates two short-lived argument lists per step.
// Allow that bounded stress case to finish without changing the stack guard.
const { runUntilPrompt, runCommand } = createCpmSession(machine, {
  promptAttempts: (description) =>
    description.startsWith("run ") ? 16000 : 1800,
});

try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  const measurements = [];
  for (const [name, source, expected, guard] of selectedCases) {
    const outputName = name.replace(".SK8", ".COM");
    runCommand(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    const image = machine.export_drive(0);
    const generated = readCpm22File(image, outputName);
    const aso = readCpm22File(image, name.replace(".SK8", ".ASO"));
    const { imageBytes: imageLength, asoBytes } = validateAso(
      aso,
      generated,
      name,
    );
    const imageEndOffset = provider.address("RT_LIMIT") - 0x0100;
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
    if (name === "GCLOCAL.SK8" || name === "ECGCMAP.SK8") {
      assert.ok(
        readWord(machine, collectionCountAddress) > 0,
        `${name}: did not exercise GC`,
      );
    }
    const nativeLowSp = readWord(machine, lowStackAddress);
    const heapEnd = readWord(machine, heapPointerAddress);
    assert.ok(nativeLowSp >= 0xd400, `${name}: native stack crossed its guard`);
    assert.ok(heapEnd < nativeLowSp, `${name}: heap and stack collided`);
    measurements.push({
      name,
      result: expected,
      imageBytes: imageLength,
      comBytes: generated.length,
      asoBytes,
      lowSp: nativeLowSp,
      heapEnd,
      bindingAllocations: readWord(machine, bindingAllocationAddress),
      closureAllocations: readWord(machine, closureAllocationAddress),
      pairAllocations: readWord(machine, pairAllocationAddress),
      collections: readWord(machine, collectionCountAddress),
      activations: readWord(machine, frameCountAddress),
    });
    runCommand(`ERA ${outputName}`, "A>", `remove ${outputName}`);
    runCommand(
      `ERA ${name.replace(".SK8", ".ASO")}`,
      "A>",
      `remove ${name.replace(".SK8", ".ASO")}`,
    );
    runCommand(`ERA ${name}`, "A>", `remove ${name}`);
  }
  for (const [name, , expected] of selectedErrorCases) {
    runCommand(`SKATE ${name}`, expected, `reject ${name}`);
    runCommand(`ERA ${name}`, "A>", `remove ${name}`);
  }
  for (const [name, , expected] of selectedRuntimeErrorCases) {
    const outputName = name.replace(".SK8", ".COM");
    runCommand(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    const rejected = runCommand(
      outputName.replace(".COM", ""),
      expected,
      `reject ${outputName}`,
    );
    assert.equal(
      programOutput(rejected),
      expected,
      `${name}: runtime failure printed more than its diagnostic`,
    );
    runCommand(`ERA ${outputName}`, "A>", `remove ${outputName}`);
    runCommand(
      `ERA ${name.replace(".SK8", ".ASO")}`,
      "A>",
      `remove ${name.replace(".SK8", ".ASO")}`,
    );
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
      largestAsoBytes: Math.max(
        ...measurements.map(({ asoBytes }) => asoBytes),
      ),
      cellMetrics: measurements.length === 0
        ? null
        : summarizeCellMeasurements(measurements),
      measurements,
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
