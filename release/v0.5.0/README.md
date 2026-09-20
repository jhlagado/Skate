# Skate 0.5.0

Skate 0.5.0 is a work in progress for Z80 computers running CP/M. The
compiler reads `.sk8` source and ordered `.skm` source packages, publishing a
checked NOBJ 1.0 file together with a runnable `.COM` program.

The language includes exact signed integers, booleans, symbols, strings,
quoted data, pairs, lists, `cons`, `car`, `cdr`, `pair?`, `null?`, `eq?`,
`write`, `display`, `newline`, package definitions, lexical `let` and `let*`,
conditionals, short-circuit boolean operations, arithmetic, fixed-arity
procedures, closures, mutation and proper tail calls.

The resident compiler image is 12,706 bytes at `$0100`, leaving 3,678 bytes
below the 16 KiB code limit. The complete measured allocation is 44,834 of the
57,088-byte CP/M transient area. The compiler provides 256 package-global
slots, 128 simultaneous local slots, 320 fixups and 320 symbol entries. The
runtime provider is 5,318 bytes.

The release proof compiles and runs an 8,335-byte source package, repeats the
run after remounting the disk, and checks that full-disk and malformed-source
failures preserve the previous output pair.

Run the checks from the repository root:

```sh
deno task check
deno task test:cpm
deno task test:cpm:release
deno task measure
```
