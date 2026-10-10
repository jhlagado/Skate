# Skate

Scheme for Z80 computers running CP/M.

Skate compiles `.sk8` source into runnable `.COM` programs and a checked
publication stream. It is an ongoing implementation aimed at useful Scheme programs on
a 64K machine, with a native compiler, a compact runtime and CP/M disk tools.

The current source supports exact signed 24-bit integers, 24-bit floats
numbers, booleans, byte characters, symbols, strings, quoted data, pairs,
lists and vectors. It provides lexical `let`, `let*`, `letrec` and named
`let`, `do`, `if`, `begin`, `cond`, `case`, `when`, `unless`, `and`, `or`, `set!`,
fixed-arity procedures, dotted rest parameters, bounded `apply`, closures,
internal definitions, proper tail calls and one-shot `call/ec`. Standard input,
output and error ports support character and datum I/O. Sequential text and
binary file ports use CP/M files, with one input and one output file open at a
time. Text input treats Control-Z as EOF. Decimal points and exponents select
24-bit floats (17 significant bits, about 5 decimal digits, range ±1.8E19;
see [docs/float24.md](docs/float24.md)), and mixed arithmetic retains
fractional results.

The built-in procedures are:

| Group | Procedures |
| --- | --- |
| Pairs and lists | `cons` `car` `cdr` `caar` … `cdddr` (two and three levels) `set-car!` `set-cdr!` `list` `list-copy` `length` `append` `reverse` `list-tail` `list-ref` `memq` `memv` `member` `assq` `assv` `assoc` `list?` `pair?` `null?` |
| Equivalence | `eq?` `eqv?` `equal?` |
| Numbers | `+` `-` `*` `/` `quotient` `remainder` `modulo` `abs` `=` `<` `>` `<=` `>=` `zero?` `number?` `number->string` `string->number` `min` `max` `gcd` `lcm` `expt` `sqrt` `floor` `ceiling` `truncate` `round` `exact->inexact` `inexact->exact` `exact` `inexact` `even?` `odd?` `positive?` `negative?` `exact?` `inexact?` `integer?` |
| Characters | `char=?` `char<?` `char>?` `char<=?` `char>=?` `char-upcase` `char-downcase` `char-alphabetic?` `char-numeric?` `char-whitespace?` `char->integer` `integer->char` `char?` |
| Strings and symbols | `string` `make-string` `string-length` `string-ref` `string-set!` `string-copy` `string-append` `substring` `string->list` `list->string` `string=?` `string<?` `string>?` `string<=?` `string>=?` `symbol->string` `string->symbol` `string?` `symbol?` |
| Vectors | `vector` `make-vector` `vector-length` `vector-ref` `vector-set!` `vector-fill!` `vector->list` `list->vector` `vector?` |
| Control and other | `apply` `map` `for-each` `not` `boolean?` `procedure?` `eof-object?` |
| Input and output | `read` `read-char` `write` `display` `newline` `write-char`, the port procedures and the file openers |

[`libraries/STDLIB.SK8`](libraries/STDLIB.SK8) adds
`filter`, `fold-left`, `fold-right`, `reduce`, `last-pair` and `iota` in
Skate itself. Including it adds several kilobytes of code, so a
program that needs only a few of them may be better off copying those.

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
(write (counter)) ; prints 2
(newline)
```

## Building and testing

The build uses [Deno](https://deno.com/) and expects these checkouts beside
this one (the paths in `deno.runtime.json` and the task permissions are
relative to the Skate checkout):

| Sibling | Used for |
| --- | --- |
| `../atom` | The ATOM assembler, with `npm install` run so that `node_modules/@jhlagado/z80-runtime` and `node_modules/@jhlagado/z80-tool-services` resolve |
| `../z80-runtime` | The Z80 emulator used by the unit tests (reached through ATOM's `node_modules` link) |
| `../z80-tool-services` | Assembler services used by ATOM |
| `../triptych` | The CP/M 2.2 machine for the `test:cpm` proofs; its WASM host must be built into `dist/wasm/` |

The main tasks are:

| Task | What it runs |
| --- | --- |
| `deno task check` | Formatting, lint, type checks and the compiler budget |
| `deno task test` | `check` plus the host-side unit tests: effects, the CP/M byte bridge, ASO, ports and the runtime fixtures (`test:runtime`) |
| `deno task test:cpm` | The CP/M proofs: each compiles programs with the native compiler on an emulated CP/M 2.2 machine and runs them |
| `deno task test:cpm:stress` | Capacity, large-source and full 65,280-byte image proofs |
| `deno task test:all` | `test`, `test:cpm` and `test:cpm:stress` |
| `deno task measure` | Compiler and runtime size budget report |
| `deno task census` | Compiler and runtime bytes by directory and file |

`test:cpm` and `test:cpm:stress` take tens of minutes; each `test:cpm:*` task
can be run on its own. The [codebase guide](docs/codebase.md#tests-and-verification)
lists every task.

The compiler writes a checked `.COM` program for use from a CP/M prompt. Any
intermediate publication data is an implementation detail of the build.

Skate deliberately leaves general macros and quasiquote, reusable
continuations and `eval` outside this small core. Vector literals
(`#(1 2 3)`) are self-evaluating constants. File names currently use
current-drive CP/M 8.3 spelling; append, seeking and multiple handles per
direction are not implemented. `libraries/io.sk8` provides line input, line
output, prompting and stream copying with explicit ports.

### Program limits

The compiler works in fixed tables, so a program must stay within these
bounds. Exceeding one stops compilation with `CAP`. The [limits register](docs/limits.md) lists every
limit, its reason and what is planned for it.

| Limit | Value |
| --- | --- |
| Exact integers | -8,388,608 to 8,388,607; an out-of-range literal is a compile error and overflow a runtime error |
| Procedures (`lambda`, procedure `define`, named `let`, `do`) | 255 per program, 26 nested |
| Fixed parameters per procedure, and named `let` or `do` variables | 32, plus an optional rest parameter |
| Arguments in one call, and values spread by `apply` | 32 |
| Global names | 256 |
| Simultaneous local bindings | 128 |
| Address fixups (literals in code and quoted data, top-level `let` locals) | 640 |
| Distinct string literals | 128, 2,048 bytes in all |
| Distinct strings and symbols in quoted data | 128, 2,047 bytes in all |
| Elements in one level of a quoted list or vector | 63 |
| Distinct symbols | 640 |
| A `do` form, a `letrec` binding list, or leading internal definitions | 1,504 reader events (an atom or parenthesis each); a `do` needs room for its rewrite too |
| String length | 255 |
| Vector length | 255 |
| Non-tail recursion | bounded by free memory: about 1,500 levels in a small program, fewer as the heap grows |
| Program size | 45,056 bytes of `.COM`; a larger image is `CAP`. The heap and the stack share what the program and the collector maps leave below `CF00H`, and the maps use the TPA above `E400H` when there is one |

The runtime is loaded in one of four sizes: the core alone, the core and the
standard procedures, those and the numeric procedures (`sqrt`, `expt`,
`round` and the rest added with the 24-bit float), or everything with the
datum reader and file ports. The
compiler reads the source once before compiling it and loads the smallest
runtime that covers the procedures it names, so a program that uses neither
`read` nor files is about 3.6 KB smaller and one that also uses no standard
procedure or `case` about 5.4 KB smaller.

Globals occupy a fixed 1 KB area straight after the runtime, so a reference
to a global needs no fixup. Every symbol inside quoted data still takes one.
The programs in `examples/workloads` are measured against these limits by
`deno task test:cpm:workloads`.

The [0.5.11 release notes](release/v0.5.11/README.md) describe the checked image
and measurements of that published release. Their limitations apply to 0.5.11
only: that image predates Scheme ports and file procedures. The main branch adds
the standard ports, sequential CP/M file ports and later compiler work described
above; its source and tests are the development baseline.

For a guided tour of the source tree, compilation stages and recommended
reading order, see the [codebase guide](docs/codebase.md).

The [I/O reference](docs/ports.md) describes ports, sequential files and source
helpers.
