# Skate 0.5.5

Skate is a small Scheme compiler for Z80 computers running CP/M. This release
adds console character input and output for interactive programs.

The compiler accepts exact signed 16-bit integers, booleans, byte characters,
symbols, strings, quoted lists and dotted pairs. Programs can use top-level
definitions, `let`, `let*`, `letrec`, named `let`, `if`, `begin`, `cond`,
`and`, `or`, fixed-arity procedures, closures, internal definitions, shared
variable mutation and proper tail calls. Procedure definitions use the usual
`(define (name args ...) body ...)` shorthand, including inside a procedure or
binding body.

The predefined procedures include arithmetic and comparisons, type predicates,
pair and list operations, `write`, `display`, `newline`, `write-char` and
`read-char`. `read-char` returns a byte character from the CP/M console and
maps Control-Z to the EOF value. `write-char` sends one byte directly to the
console. `write` prints characters as `#\\xHH` with two lower-case hexadecimal
digits; a top-level `display` sends the character byte directly, while nested
values use the readable `write` form.

The [adventure example](../../examples/applications/adventur.sk8) reads a
choice and selects one of two paths:

```scheme
(begin
  (display "You are at a fork. Choose left or right: ")
  (let ((choice (read-char)))
    (newline)
    (if (eq? choice #\l)
        (display "You take the left path.")
        (if (eq? choice #\r)
            (display "You take the right path.")
            (display "You wait at the fork.")))))
```

Keep `SKATE.COM` and `SKATE.RT` together on the working disk. The compiler
copies the required runtime into generated programs, so those programs can
subsequently run without `SKATE.RT`. Source files use CR/LF line endings for
CP/M `TYPE` and `EDIT`.

## Size and capacity

| Component | Executable/provider bytes | CP/M record-rounded file |
| --- | ---: | ---: |
| `SKATE.COM` | 17,512 | 17,536 |
| `SKATE.RT` | 6,633 | 6,656 |

The compiler image is 1,128 bytes above the 16 KiB code reference. Its measured
total allocation, including workspace, is 50,152 bytes against a 57,088-byte
budget. The configured tables provide 256 global slots, 128 simultaneous local
slots, 320 symbol entries and 320 slot fixups. The checked release program
uses a 12,032-byte `.COM` file and a 12,160-byte `.NOBJ` file.

## Current limitations

This is an incomplete Scheme implementation. Floating-point literals and
arithmetic, rest parameters, `apply`, vectors, macros, continuations, `eval`,
ports and general file I/O are not yet available. The compiler is intended for
small CP/M programs and has no standard library beyond the procedures listed
above.

## Verification

The checked CP/M suites cover console input and output, EOF handling, binding
forms, mutual recursion, named `let`, internal definitions, closures that
retain captured locations, integer arithmetic and comparisons, predicates,
mutation, tail calls, quoted data, 256 globals and capacity diagnostics. The
generated `.NOB` image is checked against the corresponding `.COM` output.
The package can be assembled with ATOM and measured with `deno task measure`.
