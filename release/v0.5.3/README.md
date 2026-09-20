# Skate 0.5.3

Skate is a small Scheme compiler for Z80 computers running CP/M. This release
adds checked integer procedures, numeric comparisons, logical negation and the
basic type predicates to the compact compiler.

The compiler accepts exact signed 16-bit integers, booleans, byte characters,
symbols, strings, quoted lists and dotted pairs. Programs can use top-level
definitions, `let`, `let*`, `if`, `begin`, two-operand `and` and `or`, fixed-arity
procedures, closures, shared variable mutation and proper tail calls.

The predefined procedures are `+`, `-`, `*`, `quotient`, `remainder`, `=`, `<`,
`>`, `<=`, `>=`, `zero?`, `not`, `number?`, `boolean?`, `symbol?`,
`procedure?`, `string?`, `char?`, `eof-object?`, `cons`, `car`, `cdr`, `list`,
`pair?`, `null?`, `eq?`, `write`, `display` and `newline`.

`+`, `-` and `*` accept the supported Scheme arities, including their empty
and unary cases. `quotient` and `remainder` require two exact integers and
truncate toward zero. Comparisons accept two or more values and compare each
adjacent pair. Numeric operations reject characters, booleans and other
non-numeric values before changing state. Division by zero and the signed
16-bit overflow case are reported as runtime errors.

Keep `SKATE.COM` and `SKATE.RT` together on the working disk. The compiler
copies the required runtime into generated programs, so those programs can
subsequently run without `SKATE.RT`. Source files use CR/LF line endings for
CP/M `TYPE` and `EDIT`.

## Size and capacity

| Component | Executable/provider bytes | CP/M record-rounded file |
| --- | ---: | ---: |
| `SKATE.COM` | 13,496 | 13,568 |
| `SKATE.RT` | 6,385 | 6,400 |

The compiler image has 2,888 bytes of space below the 16 KiB code gate. Its
measured total allocation, including workspace, is 45,624 bytes against a
57,088-byte budget. The configured tables provide 256 global slots, 128
simultaneous local slots, 320 symbol entries and 320 slot fixups.

## Current limitations

This is an incomplete Scheme implementation. `letrec`, named `let`, `cond`,
internal definitions, full variadic `and` and `or`, character input and output,
floating-point literals and arithmetic, rest parameters, `apply`, vectors,
macros, continuations, `eval`, ports and general file I/O are not yet
available. The current compiler is intended for small CP/M programs and has no
standard library beyond the procedures listed above.

## Verification

The checked CP/M suites cover integer arithmetic and comparisons, predicates,
closures, mutation, tail calls, quoted data, collection during retained
literals, 256 globals and capacity diagnostics. The generated `.NOB` image is
checked against the corresponding `.COM` output. The package can be assembled
with ATOM and measured with `deno task measure`.
