# Skate

Scheme for Z80 computers running CP/M.

Skate compiles `.sk8` source into runnable `.COM` programs and a checked
publication stream. It is an ongoing implementation aimed at useful Scheme programs on
a 64K machine, with a native compiler, a compact runtime and CP/M disk tools.

The current source supports exact signed integers, binary16
numbers, booleans, byte characters, symbols, strings, quoted data, pairs,
lists and vectors. It provides `cons`, `car`, `cdr`, mutation, lexical `let`,
`let*`, `letrec` and named `let`, `if`, `begin`, `cond`, `and`, `or`, numeric
arithmetic and comparisons, type predicates, fixed-arity procedures, dotted
rest parameters, bounded `apply`, closures, internal definitions, proper tail
calls and one-shot `call/ec`. Standard input, output and error ports support character and datum I/O.
Sequential text and binary file ports use CP/M files, with one input and one
output file open at a time. Text input treats Control-Z as EOF. Decimal points and exponents select
binary16 values, and mixed arithmetic retains fractional results.

The compiler and runtime are written in Z80 assembly using the ATOM assembler.
The repository contains the Deno build commands and CP/M checks needed to assemble the compiler, publish a checked program and run
it on the target.

The optional provider tools carry terminal, input, video, sound and bounded
file requests over a byte protocol. Ordinary console text remains ordinary
console text; a host supplies the hardware-specific provider.

A source file may begin with `(include "LIB.SK8")` forms, each naming one or
more CP/M 8.3 files on the current drive. Included files may begin with their
own include forms. The compiler reads every file's dependencies before the
file itself, includes a file only once however many files name it, and
rejects cycles, missing files, more than 32 files in one program and
include chains more than eight files deep. Include forms must come before
ordinary source; diagnostics report the file, line and column of the error.

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

The compiler writes a checked `.COM` program for use from a CP/M prompt. Any
intermediate publication data is an implementation detail of the build.

Skate deliberately leaves general macros and quasiquote, reusable
continuations and `eval` outside this small core. File names currently use
current-drive CP/M 8.3 spelling; append, seeking and multiple handles per
direction are not implemented. `libraries/io.sk8` provides line input, line
output, prompting and stream copying with explicit ports.

See the [0.5.11 release notes](release/v0.5.11/README.md) for the checked image,
measurements and limitations of that published image. The main branch includes
subsequent compiler and I/O work; its source and tests are the development baseline.

For a guided tour of the source tree, compilation stages and recommended
reading order, see the [codebase guide](docs/codebase.md).

The [I/O reference](docs/ports.md) describes ports, sequential files and source
helpers.
