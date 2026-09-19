# Scope compiler

The current compiler reads one CP/M source package and writes a native Z80
program. It supports exact signed integers, booleans, package definitions,
lexical `let` and `let*`, `begin`, `if`, `and`, `or`, and the two-operand
arithmetic forms `+`, `-` and `*`.

Global and local bindings use four-byte slots containing a value, a type tag and
an initialization flag. The compiler reserves 256 package-global slots, 128
simultaneous local slots and 320 address fixups. A reference to an
uninitialized slot produces `UNBOUND` when the generated program runs. Nested
bindings resolve to the innermost name, including while an initializer is
being compiled.

The compiler image is loaded at `$0100`. Generated code and its runtime are
staged below `$7B80`, leaving a 7,040-byte staging area. The size check also
accounts for the fixed compiler tables and a guarded 2,048-byte native stack.
The current live allocation is 30,664 bytes against a 30,720-byte gate.

This release does not yet implement procedures, mutation, pairs, strings,
`cond` or `letrec`.

The CP/M proof compiles and runs small expressions, nested shadowing, both
branches of `if`, short-circuit forms, an unbound reference, a package with
256 distinct global definitions and a source package containing 256 top-level
forms. It also checks malformed bindings and staged-output overflow.
