# Skate 0.1.1

Skate 0.1.1 is the C1 checkpoint for a small Scheme system on Z80 CP/M. It
is a work in progress. This release adds a direct compiler command under
`src/compiler/` and the tests needed to assemble it with ATOM and prove it on
CP/M.

The command accepts one arithmetic expression, evaluates exact signed 16-bit
or binary16 operands at runtime, and publishes a checked NOBJ plus runnable
`.COM` image. It reports syntax, numeric-range and source-I/O failures without
leaving a partial generated program.

This is a useful compiler foundation, not a complete Scheme implementation.
Definitions, lexical scope, procedures, collection and general Scheme forms
remain under development. The public source and the [C1 evidence](../../docs/c1/README.md)
state the current boundary and the measured size.

Reproduce the release with:

```sh
deno task check:c1
deno task test:cpm:c1
deno task measure:c1
```
