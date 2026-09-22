# Skate 0.5.7

Skate is a small Scheme compiler for Z80 computers running CP/M. This release
adds reclaimable runtime storage for pairs, bindings and closures. A running
program can reuse 256-byte pages after collection instead of consuming a fixed
pair area and a monotonic closure area.

The compiler accepts exact signed 16-bit integers and decimal floating-point
literals. A decimal point or exponent selects a binary16 value; for example,
`1.5`, `-0.0` and `2e3`. Integer `+`, `-` and `*` stay exact when all their
operands are exact. Mixed arithmetic uses binary16, and `/` returns a binary16
result. Comparisons preserve represented mathematical values without first
rounding an exact integer. The runtime handles signed zero, infinities,
canonical NaN, `number?` and `zero?`.

The rest of the language includes booleans, byte characters, symbols, strings,
quoted data, pairs, lists, `cons`, `car`, `cdr`, `pair?`, `null?`, `eq?`,
`write`, `display`, `newline`, `write-char`, `read-char`, package definitions,
lexical `let`, `let*`, `letrec` and named `let`, `if`, `begin`, `cond`, `and`,
`or`, numeric comparisons, fixed-arity procedures, closures, internal
definitions, shared mutation and proper tail calls.

Finite floating-point output is written with a decimal point and enough digits
to reproduce the binary16 value. Exceptional values use `+inf.0`, `-inf.0` and
`+nan.0`. `read-char` maps CP/M Control-Z to EOF. Source files in the release
use CR/LF line endings for CP/M `TYPE` and `EDIT`.

## Example

```scheme
(begin
  (display "half = ")
  (display (/ 1 2))
  (newline))
```

## Size and capacity

| Component | Logical bytes | CP/M record-rounded file |
| --- | ---: | ---: |
| `SKATE.COM` | 17,732 | 17,792 |
| `SKATE.RT` | 13,725 | 13,824 |
| Checked release `.COM` | 15,763 | 15,872 |
| Checked release `.NOBJ` | 15,874 | 16,000 |

The compiler image ends at `$4644`. The managed runtime uses a `$C000` ceiling,
reserves 10,240 bytes for its maps and work band, and retains an 8,192-byte
transient and stack allowance. The compiler-linked account provides 80 object
pages. Five-byte pairs provide 51 records per page; the actual heap available
to a program depends on its loaded image and live bindings and closures.

The checked package contains 8,684 bytes of Scheme source across 16 parts and
compiles and runs after a remount. The compiler tables provide 256 package
global slots, 128 simultaneous local slots, 320 symbol entries and 320 pending
slot fixups. Generated output remains subject to the available staging space.

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
data, collection and reclamation, console input and output, exact arithmetic,
binary16 arithmetic, division, comparison, predicates, storage accounting,
remounting and failed publication. The generated NOBJ image is checked against
its `.COM` program.
