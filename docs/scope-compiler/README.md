# Scope compiler

The current compiler reads one CP/M source package and writes a native Z80
program. It supports exact signed integers, booleans, package definitions,
lexical `let` and `let*`, `begin`, `if`, `and`, `or`, and the two-operand
arithmetic forms `+`, `-` and `*`.

Global references use three-byte slots with an initialized flag. The compiler
reserves 256 package-global slots, 128 simultaneous local slots and 320
address fixups. A reference to an uninitialized slot produces `UNBOUND` when
the generated program runs. Nested bindings resolve to the innermost name.

The compiler image is loaded at `$0100`. Generated code and its runtime are
staged below `$9000`; the remaining TPA is available to the output image and
its data. The size check reports the image, the staged-output guard and the
space left below the guarded native stack.

The CP/M proof compiles and runs small expressions, nested shadowing, both
branches of `if`, short-circuit forms, an unbound reference, and a package
with 256 distinct global definitions.
