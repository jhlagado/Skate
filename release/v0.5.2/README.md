# Skate 0.5.2

Skate is a small Scheme compiler for Z80 computers running CP/M. This release
corrects the compact compiler's handling of quoted data, generated procedure
calls and explicit output, and adds checks for the corrected behavior.

## Supported language

The compiler supports signed 16-bit integers, booleans, strings, symbols,
quoted lists and dotted pairs. Programs can use top-level definitions, lexical
`let` and `let*`, `if`, `begin`, two-operand `and` and `or`, fixed-arity
procedures, closures, shared variable mutation and proper tail calls.

Predefined procedures are `+`, `-`, `*`, `zero?`, `cons`, `car`, `cdr`, `list`,
`pair?`, `null?`, `eq?`, `write`, `display` and `newline`. Arithmetic currently
requires two operands. Source packages can span ordered `.SK8` files named in a
`.SKM` manifest. Compilation produces a `.COM` executable and a `.NOB` object
file. Programs print only what their source sends to `write`, `display` or
`newline`.

## Try the examples

[Launch Skate in Triptych](https://jhlagado.github.io/Skate/). The image boots
automatically and requires no local installation.

Keep `SKATE.COM` and `SKATE.RT` together on the working disk. The compiler
copies the required runtime into generated programs, so those programs can
subsequently run without `SKATE.RT`. Source files use CR/LF line endings for
CP/M `TYPE` and `EDIT`.

## Size and capacity

| Component | Executable/provider bytes | CP/M record-rounded file |
| --- | ---: | ---: |
| `SKATE.COM` | 13,185 | 13,312 |
| `SKATE.RT` | 5,354 | 5,376 |

The compiler is 3,199 bytes below the 16 KiB code gate. Its measured total
allocation, including workspace, is 45,313 bytes against a 57,088-byte budget.
The current limits include 256 global slots, 128 simultaneous local slots, 320
symbol entries and 320 fixups.

## Current limitations

This is an incomplete Scheme implementation. Numeric comparisons,
quotient/remainder, most type predicates, keyboard input, `letrec`, named `let`,
`cond`, internal definitions, rest parameters, floating point, macros,
continuations, `eval`, vectors, ports and general file I/O are not yet
available. Arithmetic and boolean forms do not yet accept their full Scheme
argument counts.

## Verification

The CP/M procedure and data suites cover closures, mutation, tail calls, quoted
data identity, nested quotation, collection during retained literals, 256
globals and capacity diagnostics. The generated `.NOB` image is checked against
the corresponding `.COM` output. The package can be assembled with ATOM and
measured with `deno task measure`.
