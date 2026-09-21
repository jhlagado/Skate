# Skate 0.5.6

Skate is a small Scheme compiler for Z80 computers running CP/M. This release
adds binary16 numbers and completes the numeric part of the compact language.
It retains the console input and output from Skate 0.5.5.

The compiler accepts exact signed 16-bit integers and decimal floating-point
literals. A decimal point or exponent selects a binary16 value; for example,
`1.5`, `-0.0` and `2e3`. Integer `+`, `-` and `*` stay exact when all their
operands are exact. Mixed arithmetic uses binary16, and `/` always returns a
binary16 result, so `(/ 1 2)` is `0.5`. Comparisons preserve the represented
mathematical values without first rounding an exact integer. The runtime also
handles signed zero, infinities, canonical NaN, `number?` and `zero?`.

The rest of the language includes booleans, byte characters, symbols, strings,
quoted data, pairs, lists, `cons`, `car`, `cdr`, `pair?`, `null?`, `eq?`,
`write`, `display`, `newline`, `write-char`, `read-char`, package definitions,
lexical `let`, `let*`, `letrec` and named `let`, `if`, `begin`, `cond`, `and`,
`or`, numeric comparisons, fixed-arity procedures, closures, internal
definitions, shared mutation and proper tail calls.

Finite floating-point output is written with a decimal point and enough digits
to reproduce the binary16 value. Exceptional values use `+inf.0`, `-inf.0` and
`+nan.0`. `read-char` maps CP/M Control-Z to EOF, and source files in the
release use CR/LF line endings for CP/M `TYPE` and `EDIT`.

## Example

```scheme
(begin
  (display "half = ")
  (display (/ 1 2))
  (newline))
```

## Size and capacity

| Component | Executable/provider bytes | CP/M record-rounded file |
| --- | ---: | ---: |
| `SKATE.COM` | 17,602 | 17,664 |
| `SKATE.RT` | 7,413 | 7,424 |
| Checked release `.COM` | 12,672 | 12,672 |
| Checked release `.NOBJ` | 12,800 | 12,800 |

The compiler image is 1,218 bytes above the 16 KiB code reference. Its complete
allocation, including fixed tables, staging space and a guarded 2,048-byte
native stack, is 52,418 of the 57,088-byte CP/M TPA account. The remaining
4,670 bytes are available for growth. The tables provide 256 package-global
slots, 128 simultaneous local slots, 320 symbol entries and 320 pending slot
fixups.

The checked release package contains 8,194 bytes of source across 16 parts.
The compiler stages up to 14,336 bytes of generated output before the fixed
tables. The largest checked run leaves the native stack at `$E000` and the heap
ending at `$6000`.

## Limits

User procedures have fixed arity. Rest parameters, `apply`, vectors,
quasiquote, general macros in the compiler, pair and string mutation,
continuations, `eval`, ports and general file I/O are outside this release.
The language has no standard library beyond the procedures listed above.

## Verification

From a checkout with ATOM and the Triptych verification tools beside it:

```sh
deno task check
deno task test:cpm
deno task measure
```

The CP/M checks cover bindings, closures, mutation, proper tail calls, quoted
data, collection, console input and output, exact arithmetic, binary16
arithmetic, division, comparison, predicates, special values, 256 globals,
capacity errors, remounting and failed publication. The generated NOBJ image is
checked against its `.COM` program.
