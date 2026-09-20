# Compiler and runtime

The current compiler reads one CP/M source package and writes a checked NOBJ
file together with a native Z80 `.COM` program. The language currently
includes exact signed integers, booleans, package definitions, lexical `let`
and `let*`, `if`, `begin`, `and`, `or`, `+`, `-`, `*`, fixed-arity procedures,
closures, mutation and proper tail calls.

Each value slot stores a two-byte payload, a tag and an initialization flag.
Lexical procedures use shared cells for captured bindings, and tail calls reuse
the active activation map. An uninitialized reference or mutation reports
`UNBOUND`; an invalid call reports `RUNTIME ERROR`.

The compiler image is loaded at `$0100` and remains below the 16 KiB code
limit. The current image is 15,264 bytes, leaving 1,120 bytes in that limit.
Generated output is staged below `$7B80` in a 7,040-byte region. The complete
compiler account, including fixed tables and a guarded 2,048-byte native
stack, is measured against the `$0100` to `$E000` transient area: 57,088 bytes
are available and the current account uses 39,648 bytes.

The fixed tables provide 256 package-global slots, 128 simultaneous local
slots, 320 address fixups and 320 symbol entries. The runtime keeps the heap
below `$C000`, stores saved operator values in the following `$C000` to
`$C800` band, and rejects a procedure call before moving the native stack below
`$D400`. The side stack holds 511 usable four-byte operator records, leaving
3 KiB for transient native operands and helper calls before the guard.

The CP/M proof covers ordinary and nested calls, closure capture and mutation,
tail recursion, operator evaluation order, malformed source, unbound names,
duplicate parameters, NOBJ records and CRCs, and the relationship between the
published NOBJ image and its `.COM` program.
