# Skate 0.3.0

Skate 0.3.0 is a work in progress for Z80 computers running CP/M. The
compiler reads `.sk8` source and publishes a checked NOBJ 1.0 file together
with a runnable `.COM` program.

This release includes exact signed integers, booleans, package definitions,
lexical `let` and `let*`, conditionals, `begin`, short-circuit `and` and `or`,
arithmetic, fixed-arity procedures, closures, mutation and proper tail calls.

The compiler image is 15,264 bytes at `$0100`, leaving 1,120 bytes below the
16 KiB code limit. The complete compiler account uses 39,648 of the 57,088
bytes between `$0100` and `$E000`. It provides 256 package-global slots, 128
simultaneous local slots, 320 fixups and 320 symbol entries. The largest
checked output in the CP/M proof is 5,760 bytes of `.COM` code and 5,888 bytes
of NOBJ data.

The runtime leaves room for nested procedure calls and saved operator values
inside the CP/M transient area while retaining a guarded native stack.

Run the checks from the repository root:

```sh
deno task check
deno task test:cpm
deno task measure
```
