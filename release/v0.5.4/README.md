# Skate 0.5.4

Skate is a small Scheme compiler for Z80 computers running CP/M. This release
adds the remaining binding and control forms needed for mutually recursive and
structured programs.

The compiler accepts exact signed 16-bit integers, booleans, byte characters,
symbols, strings, quoted lists and dotted pairs. Programs can use top-level
definitions, `let`, `let*`, `letrec`, named `let`, `if`, `begin`, `cond`,
`and`, `or`, fixed-arity procedures, closures, internal definitions, shared
variable mutation and proper tail calls. Procedure definitions may use the
usual `(define (name args ...) body ...)` shorthand, including inside a
procedure or binding body.

The predefined procedures are `+`, `-`, `*`, `quotient`, `remainder`, `=`, `<`,
`>`, `<=`, `>=`, `zero?`, `not`, `number?`, `boolean?`, `symbol?`,
`procedure?`, `string?`, `char?`, `eof-object?`, `cons`, `car`, `cdr`, `list`,
`pair?`, `null?`, `eq?`, `write`, `display` and `newline`.

For example, a recursive local procedure can be written directly:

```scheme
(define sum-to
  (lambda (limit)
    (let loop ((n limit) (total 0))
      (if (= n 0)
          total
          (loop (- n 1) (+ total n))))))

(write (sum-to 10))
(newline)
```

Keep `SKATE.COM` and `SKATE.RT` together on the working disk. The compiler
copies the required runtime into generated programs, so those programs can
subsequently run without `SKATE.RT`. Source files use CR/LF line endings for
CP/M `TYPE` and `EDIT`.

## Size and capacity

| Component | Executable/provider bytes | CP/M record-rounded file |
| --- | ---: | ---: |
| `SKATE.COM` | 17,467 | 17,536 |
| `SKATE.RT` | 6,404 | 6,528 |

The compiler image is 1,083 bytes above the 16 KiB code reference. Its measured
total allocation, including workspace, is 50,107 bytes against a 57,088-byte
budget. The configured tables provide 256 global slots, 128 simultaneous local
slots, 320 symbol entries and 320 slot fixups. The short-name 256-global
workload uses 10,368 bytes; the checked multi-part release program uses 11,776
bytes.

## Current limitations

This is an incomplete Scheme implementation. Character input and output,
floating-point literals and arithmetic, rest parameters, `apply`, vectors,
macros, continuations, `eval`, ports and general file I/O are not yet
available. The compiler is intended for small CP/M programs and has no
standard library beyond the procedures listed above.

## Verification

The checked CP/M suites cover binding forms, mutual recursion, named `let`,
internal definitions, closures that retain captured locations, integer
arithmetic and comparisons, predicates, mutation, tail calls, quoted data,
256 globals and capacity diagnostics. The generated `.NOB` image is checked
against the corresponding `.COM` output. The package can be assembled with
ATOM and measured with `deno task measure`.
