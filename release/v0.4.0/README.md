# Skate 0.4.0

Skate 0.4.0 is a work in progress for Z80 computers running CP/M. The
compiler reads `.sk8` source and publishes a checked NOBJ 1.0 file together
with a runnable `.COM` program.

This release adds quoted data, dotted lists, strings, symbols, pairs, list
construction and selection, predicates, output procedures and a checked
CP/M runtime provider. It retains exact signed integers, booleans, package
definitions, lexical `let` and `let*`, conditionals, short-circuit boolean
operations, arithmetic, fixed-arity procedures, closures, mutation and proper
tail calls.

The resident compiler image is 12,685 bytes at `$0100`, leaving 3,699 bytes
below the 16 KiB code limit. The complete measured allocation is 44,813 of the
57,088-byte CP/M transient area. The compiler provides 256 package-global
slots, 128 simultaneous local slots, 320 fixups and 320 symbol entries. The
runtime provider is 5,318 bytes, and the largest checked output in the CP/M
proof is 9,216 bytes of `.COM` code and 9,344 bytes of NOBJ data.

Run the checks from the repository root:

```sh
deno task check
deno task test:cpm
deno task measure
```
