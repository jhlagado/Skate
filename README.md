# Skate

Scheme for Z80 computers running CP/M.

Skate compiles `.sk8` source into NOBJ 1.0 files and runnable `.COM`
programs. It is an ongoing implementation aimed at useful Scheme programs on
a 64K machine, with a native compiler, a compact runtime and CP/M disk tools.

The current release, Skate 0.5.9, supports exact signed integers, binary16
numbers, booleans, byte characters, symbols, strings, quoted data, pairs,
lists and vectors. It provides `cons`, `car`, `cdr`, mutation, lexical `let`,
`let*`, `letrec` and named `let`, `if`, `begin`, `cond`, `and`, `or`, numeric
arithmetic and comparisons, type predicates, fixed-arity procedures, dotted
rest parameters, bounded `apply`, closures, internal definitions, proper tail
calls and one-shot `call/ec`. Console input and output use the CP/M character
interface; Control-Z is reported as EOF. Decimal points and exponents select
binary16 values, and mixed arithmetic retains fractional results.

The compiler and runtime are written in Z80 assembly using the ATOM assembler.
The repository contains the Deno build commands, source-preparation tools and
CP/M checks needed to assemble the compiler, publish an object file and run a
generated program.

The optional provider tools carry terminal, input, video, sound and bounded
file requests over a byte protocol. Ordinary console text remains ordinary
console text; a host supplies the hardware-specific provider.

For source trees using leading `(include "LIB.SK8")` forms, the host can
prepare the same ordered `.SKM` package accepted by the CP/M compiler:

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

Skate deliberately leaves general macros and quasiquote, reusable
continuations, `eval`, Scheme ports and general file procedures outside this
small core. The provider protocol is the planned boundary for richer device
and file services.

See the [0.5.9 release notes](release/v0.5.9/README.md) for the checked image,
measurements and current limitations.
