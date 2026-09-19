# Skate 0.2.0

Skate 0.2.0 is a work in progress for Z80 computers running CP/M. The
compiler reads a source package and publishes a checked NOBJ file together
with a runnable `.COM` program.

This release adds package definitions, lexical `let` and `let*`, nested name
shadowing, `begin`, conditionals, short-circuit `and` and `or`, and exact
integer arithmetic. Booleans use the standard false value for branch tests.
The compiler reserves 256 package-global slots and 128 simultaneous local
slots. An uninitialized reference reports `UNBOUND` at runtime.

The compiler image is 10,857 bytes loaded at `$0100`, below the 16 KiB core
limit. The CP/M proof generates a 5,888-byte `.COM` for a package containing
256 global definitions and runs it to completion.

Reproduce this release with:

```sh
deno task check:c2
deno task test:cpm:c2
deno task measure:c2
```
