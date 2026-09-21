# Skate

Scheme for Z80 computers running CP/M.

Skate compiles `.sk8` source into NOBJ 1.0 files and runnable `.COM`
programs. It is a work in progress aimed at useful Scheme programs on a 64K
machine, with a small native compiler, a compact runtime and checked CP/M
publication.

Skate 0.5.5 supports exact signed integers, booleans, byte characters, symbols,
strings, quoted data, pairs, lists, `cons`, `car`, `cdr`, `pair?`, `null?`,
`eq?`, `write`, `display`, `newline`, `write-char`, `read-char`, package definitions, lexical `let`,
`let*`, `letrec` and named `let`, `if`, `begin`, `cond`, `and`, `or`, `+`, `-`,
`*`, `quotient`, `remainder`, numeric comparisons, `not`, type predicates,
fixed-arity procedures, closures, internal definitions, shared mutation and
proper tail calls. Character input uses the CP/M console, with Control-Z
reported as EOF. The checked release package includes a reproducible CP/M disk
run with remount and output-recovery checks.

The compiler and runtime are written in Z80 assembly using the ATOM assembler.
The repository also contains the Deno build commands and CP/M checks needed to
assemble the compiler, publish an object file and run the generated program.

```scheme
(define make-counter
  (lambda (start)
    (lambda ()
      (begin (set! start (+ start 1)) start))))

(define counter (make-counter 0))
(counter)
```

## Build

Make the packages listed in `deno.runtime.json` available beside the checkout,
then run:

```sh
deno task check
deno task test:cpm
deno task measure
```

The compiler writes checked NOBJ and `.COM` output for use from a CP/M prompt.

See the [release notes](release/v0.5.5/README.md) for examples, sizes and current limitations.
