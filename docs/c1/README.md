# Skate 0.1.1 — C1 checkpoint

Skate 0.1.1 is a work in progress for Z80 computers running CP/M. C1 adds the
first direct compiler command in the public `src/` tree. It reads a source
file, evaluates one arithmetic expression with exact signed 16-bit integers
or binary16 values, and writes a checked NOBJ file plus a runnable `.COM`
program.

The C1 command is deliberately small while the rest of the language is being
built. It accepts one list with an operator (`+`, `-`, `*` or `/`) and two
numeric operands. It reports malformed input, numeric overflow and source or
output errors, and it does not publish partial files. Definitions, lexical
scope, procedures, collection and general Scheme compilation are later work;
the release does not present this command as a complete Scheme system.

The ATOM image is 10,557 bytes loaded at `$0100`, leaving 5,827 bytes under
the 16 KiB compiler-core target. Its named static workspace is 2,981 bytes,
and the command reserves the upper half of the CP/M transient area for its
native stack. The CP/M proof exercises integer, binary16, overflow, syntax,
source-I/O, relocation, publication and remount execution paths.

Use the source and tests in this repository to reproduce the checkpoint:

```sh
deno task check:c1
deno task test:cpm:c1
deno task measure:c1
```
