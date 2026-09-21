# Compiler and runtime

The compiler reads one CP/M source package and writes a checked NOBJ file
together with a native Z80 `.COM` program. The language includes exact signed
integers, binary16 numbers, booleans, symbols, strings, quoted data, pairs,
lists, `cons`, `car`, `cdr`, `pair?`, `null?`, `eq?`, `write`, `display`,
`newline`, `write-char`, `read-char`, package definitions, lexical `let` and
`let*`, `if`, `begin`, `and`, `or`, `+`, `-`, `*`, `/`, `quotient`, `remainder`,
numeric comparisons, `zero?`, fixed-arity procedures, closures, `letrec`, named
`let`, `cond`, internal definitions, mutation and proper tail calls.

Each value slot stores a two-byte payload, a tag and an initialization flag.
Lexical procedures use shared cells for captured bindings, and tail calls reuse
the active activation map. An uninitialized reference or mutation reports
`UNBOUND`; an invalid call reports `RUNTIME ERROR`.

The compiler image is loaded at `$0100`. The current image is 17,602 bytes
origin-relative, which is 1,218 bytes above the 16 KiB code reference.
Generated output is staged at `$5800` in a 14,336-byte region ending before the
compiler tables at `$9000`. The complete compiler account, including fixed
tables and a guarded 2,048-byte native stack, is measured against the `$0100`
to `$E000` transient area: 57,088 bytes are available and the current account
uses 52,418 bytes.

The runtime provider is currently 7,413 bytes origin-relative. The fixed tables
provide 256 package-global slots, 128 simultaneous local
slots, 320 address fixups and 320 symbol entries. The runtime keeps the pair
arena below `$C000`, stores saved operator values in the following `$C000` to
`$C800` band, and rejects a procedure call before moving the native stack below
`$D400`. A checked CP/M runtime provider supplies the pair collector and value
printer to each generated program.

The CP/M proof covers quoted and dotted data, strings, symbols, pair
construction and selection, output, collection pressure, ordinary and nested
calls, closure capture and mutation, tail recursion, operator evaluation order,
malformed source, unbound names, duplicate parameters, exact and binary16
arithmetic, division, predicates, NOBJ records and CRCs, and the relationship
between the published NOBJ image and its `.COM` program.
