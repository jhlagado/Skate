# Skate 0.1.2

Skate 0.1.2 is the reviewed C1 work-in-progress release for Z80 CP/M. It
contains the direct arithmetic compiler, its ATOM source, and the tests used
to assemble and execute the generated programs.

The compiler accepts one arithmetic list with two exact integer or binary16
operands. It publishes a checked NOBJ and a runnable COM image. Both contain
the same runtime arithmetic program, so the result is computed after
compilation. Syntax, overflow, source-I/O and rejected-input behaviour are tested.

The public repository is an ongoing development of a compact Scheme system;
this release is a tested compiler checkpoint rather than a complete language.
See [the C1 evidence](../../docs/c1/README.md) for the current boundary and
measurements.

```sh
deno task check:c1
deno task test:cpm:c1
deno task measure:c1
```
