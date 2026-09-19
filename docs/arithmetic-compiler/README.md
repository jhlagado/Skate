# Skate 0.1.4 arithmetic compiler

Skate 0.1.4 is a work in progress for Z80 computers running CP/M. The current
compiler includes a small direct command under `src/`. It reads one arithmetic expression
from a CP/M source file and writes a checked NOBJ file together with a runnable
`.COM` program.

The accepted form is one list with `+`, `-`, `*` or `/` and two numeric
operands. Exact signed 16-bit integers and binary16 values are preserved. The
compiler validates the form and operands; the generated program contains the
numeric dispatcher and computes the result when it runs. The NOBJ image and
standalone COM file contain the same executable bytes.

The compiler reports malformed input, numeric overflow and source-I/O errors. It uses
staged publication and only commits a complete output pair; the proof checks
that rejected input leaves no partial files. Definitions, lexical scope,
procedures, collection and general Scheme compilation remain under development.

The ATOM compiler image is 12,514 bytes loaded at `$0100`, leaving 3,870 bytes
under the 16 KiB compiler-core target. The mutable NOBJ staging template is
2,353 bytes. Named writable workspace is 2,846 bytes, leaving 1,250 bytes in
the 4,096-byte general workspace bucket. The CP/M proof covers all four
operators, integer and binary16 results, overflow, syntax, source-I/O,
standalone execution, NOBJ linking and execution, and a post-compilation
operand mutation check.

Reproduce the checkpoint with:

```sh
deno task check:c1
deno task test:cpm:c1
deno task measure:c1
```
