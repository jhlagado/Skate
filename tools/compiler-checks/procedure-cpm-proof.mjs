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
  ["IF33.SK8", "(if #t ".repeat(33) + "1" + " 2)".repeat(33), "CAP\r\n"],
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
