import assert from "node:assert/strict";
import {
  DEFAULT_SYNTAX_RULES_LIMITS,
  expandSyntaxRules,
  SyntaxRulesError,
} from "./syntax-rules.ts";
import { createSourcePackage } from "./source-package.ts";

const bytes = (source: string) => new TextEncoder().encode(source);
const text = (source: string) =>
  new TextDecoder().decode(expandSyntaxRules(bytes(source), "macro.sk8").bytes);

Deno.test("syntax-rules expands ellipses and preserves introduced hygiene", () => {
  const expanded = text(
    `(define-syntax capture
       (syntax-rules () ((_ value) (let ((tmp 1)) value))))
     (define-syntax sum
       (syntax-rules () ((_ value ...) (+ value ...))))
     (let ((tmp 40)) (+ (capture tmp) (sum 1 2 3)))`,
  );
  assert.match(
    expanded,
    /\(let \(\(tmp 40\)\) \(\+ \(let \(\(\$m0_0 1\)\) tmp\) \(\+ 1 2 3\)\)\)/,
  );
});

Deno.test("syntax-rules definitions are ordered through top-level begin", () => {
  const expanded = text(
    `(begin
       (define-syntax inc
         (syntax-rules () ((_ value) (+ value 1))))
       (inc 41))`,
  );
  assert.equal(expanded, "(begin (+ 41 1))");
});

Deno.test("syntax-rules rejects recursive expansion at the published limit", () => {
  const source =
    `(define-syntax loop (syntax-rules () ((_ value) (loop value)))) (loop 1)`;
  assert.throws(
    () => expandSyntaxRules(bytes(source), "recursive.sk8"),
    (error) =>
      error instanceof SyntaxRulesError &&
      error.code === "capacity" &&
      /depth 128/.test(error.message),
  );
});

Deno.test("syntax-rules rejects compile-time definitions in expression phase", () => {
  const source =
    `(lambda () (define-syntax bad (syntax-rules () ((_ x) x))) 1)`;
  assert.throws(
    () => expandSyntaxRules(bytes(source), "phase.sk8"),
    (error) =>
      error instanceof SyntaxRulesError &&
      error.code === "phase" &&
      /only valid at top level/.test(error.message),
  );
});

Deno.test("syntax-rules limits are validated and can be lowered for tests", () => {
  const source =
    `(define-syntax many (syntax-rules () ((_ value ...) (list value ...)))) (many 1 2)`;
  assert.throws(
    () => expandSyntaxRules(bytes(source), "limit.sk8", { maxRepetitions: 1 }),
    (error) => error instanceof SyntaxRulesError && error.code === "capacity",
  );
  assert.equal(DEFAULT_SYNTAX_RULES_LIMITS.maxRepetitions, 510);
});

Deno.test("syntax-rules preserves ordered definition and authored diagnostics", () => {
  const beforeDefinition = text(
    `(inc 1)
     (define-syntax inc (syntax-rules () ((_ value) (+ value 1))))`,
  );
  assert.equal(
    beforeDefinition,
    "(inc 1)",
  );

  const sourcePackage = createSourcePackage([
    {
      name: "prelude.sk8",
      bytes: bytes(
        "(define-syntax inc (syntax-rules () ((_ value) (+ value 1))))",
      ),
    },
    { name: "app.sk8", bytes: bytes("(inc 1 2)") },
  ]);
  assert.throws(
    () => expandSyntaxRules(sourcePackage.bytes, sourcePackage),
    (error) =>
      error instanceof SyntaxRulesError &&
      error.at.source === "app.sk8" &&
      /no syntax-rules pattern/.test(error.message),
  );
});

Deno.test("syntax-rules preserves free references and avoids use-site capture", () => {
  const expanded = text(
    `(define helper (lambda (value) (+ value 2)))
     (define-syntax call-helper
       (syntax-rules () ((_ value) (helper value))))
     (define-syntax capture
       (syntax-rules () ((_ value) (let ((tmp 1)) value))))
     (let (($m0_0 40)) (capture $m0_0))
     (call-helper 2)`,
  );
  assert.match(expanded, /\(let \(\(\$m0_1 1\)\) \$m0_0\)/);
  assert.match(expanded, /\(helper 2\)/);
});

Deno.test("syntax-rules keeps a definition-site helper outside a use-site binding", () => {
  const expanded = text(
    `(define helper (lambda (value) (+ value 2)))
     (define-syntax call-helper
       (syntax-rules () ((_ value) (helper value))))
     (let ((helper (lambda (value) 99))) (call-helper 2))`,
  );
  assert.match(
    expanded,
    /\(let \(\(\$u0 \(lambda \(value\) 99\)\)\) \(helper 2\)\)/,
  );
});

Deno.test("syntax-rules protects quoted data and lexically bound macro names", () => {
  const expanded = text(
    `(define-syntax inc
       (syntax-rules () ((_ value) (+ value 1))))
     (quote (inc 2))
     (let ((inc (lambda (value) value))) (inc 2))`,
  );
  assert.equal(
    expanded,
    "(quote (inc 2))\n(let ((inc (lambda (value) value))) (inc 2))",
  );
});

Deno.test("syntax-rules preserves symbols used as quoted template data", () => {
  const expanded = text(
    `(define-syntax tag (syntax-rules () ((_ ) (quote hello)))) (tag)`,
  );
  assert.equal(expanded, "(quote hello)");
});

Deno.test("syntax-rules substitutes pattern variables inside shorthand quote", () => {
  const expanded = text(
    `(define-syntax quote-value
       (syntax-rules () ((_ value) 'value)))
     (quote-value hello)`,
  );
  assert.equal(expanded, "'hello");
});

Deno.test("syntax-rules supports empty ellipses and dotted rest patterns", () => {
  const expanded = text(
    `(define-syntax sum
       (syntax-rules () ((_ value ...) (+ value ...))))
     (define-syntax all
       (syntax-rules () ((_ . args) (list . args))))
     (sum)
     (all 1 2)`,
  );
  assert.equal(expanded, "(+)\n(list . (1 2))");
});

Deno.test("syntax-rules preserves nested repetition shape", () => {
  const expanded = text(
    `(define-syntax nested
       (syntax-rules ()
         ((_ ((value ...) ...)) (list (list value ...) ...))))
     (nested ((1 2) () (3)))`,
  );
  assert.equal(expanded, "(list (list 1 2) (list) (list 3))");
});

Deno.test("syntax-rules preserves repeated bindings in dotted tails", () => {
  const expanded = text(
    `(define-syntax tail
       (syntax-rules ()
         ((tail value ... . rest) (list . value))))
     (tail 1 2 . 3)`,
  );
  assert.equal(expanded, "(list . (1 2))");
  assert.throws(
    () =>
      expandSyntaxRules(
        bytes(
          `(define-syntax tail
           (syntax-rules ()
             ((tail value ... . rest) (list . value))))
         (tail 1 2)`,
        ),
        "tail-proper.sk8",
      ),
    (error) =>
      error instanceof SyntaxRulesError &&
      /no syntax-rules pattern/.test(error.message),
  );
});
