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
The repository contains the Deno build commands, source-preparation tools and
CP/M checks needed to assemble the compiler, publish a checked program and run
it on the target.

The optional provider tools carry terminal, input, video, sound and bounded
file requests over a byte protocol. Ordinary console text remains ordinary
console text; a host supplies the hardware-specific provider.

The native compiler accepts leading `(include "LIB.SK8")` forms with up to
31 direct includes on the current drive. For nested source trees, the host
resolver prepares an ordered `.SKM` package accepted by the CP/M compiler:

```sh
deno task prepare:source path/to/sources MAIN.SK8 path/to/staged-sources
```

The output contains the included source parts and a manifest. Include forms
must come before ordinary source, and the resolver rejects cycles, paths outside
the source tree and names that cannot be represented on a CP/M disk.

```scheme
(define make-counter
  (lambda (start)
    (lambda ()
      (begin (set! start (+ start 1)) start))))

(define counter (make-counter 0))
(counter)
(write (counter)) ; prints 2
(newline)
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

The [0.5.11 release notes](release/v0.5.11/README.md) describe the checked image
and measurements of that published release. Their limitations apply to 0.5.11
only: that image predates Scheme ports and file procedures. The main branch adds
the standard ports, sequential CP/M file ports and later compiler work described
above; its source and tests are the development baseline.

For a guided tour of the source tree, compilation stages and recommended
reading order, see the [codebase guide](docs/codebase.md).

The [I/O reference](docs/ports.md) describes ports, sequential files and source
helpers.
