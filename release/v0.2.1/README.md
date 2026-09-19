# Skate 0.2.1

Skate 0.2.1 is a work in progress for Z80 computers running CP/M. The
compiler reads a source package and publishes a checked NOBJ file together
with a runnable `.COM` program.

This release adds package definitions, lexical `let` and `let*`, nested name
shadowing, `begin`, conditionals, short-circuit `and` and `or`, and exact
integer arithmetic. Boolean tags survive storage and retrieval, and nested
initializers retain their own binding slots. An uninitialized reference
reports `UNBOUND` at runtime.

The compiler reserves 256 package-global slots, 128 simultaneous local slots,
320 address fixups and 320 symbol entries. The compiler image is 11,080 bytes
loaded at `$0100`, below the 16 KiB core limit. Live compiler allocation is
30,664 bytes against a 30,720-byte gate, including the guarded native stack
and fixed tables. Generated output is staged in a 7,040-byte area below
`$7B80`.

The CP/M proofs generate and run a package with 256 global definitions and a
source package containing 256 top-level forms. The largest generated output in
these checks is 6,144 bytes of `.COM` code and 6,272 bytes of NOBJ data.

Reproduce this release with:

```sh
deno task check:c2
deno task test:cpm:c2
deno task measure:c2
```
