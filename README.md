# Skate

Scheme for a 64K computer.

Skate is a small native Scheme compiler and runtime for Z80 computers running
CP/M. It turns `.sk8` source into NOBJ 1.0 output and linked `.COM` programs
that can run from the CP/M prompt.

The current public release is Skate 0.2.1, a work-in-progress compiler for
small Scheme programs. It reads CP/M source, resolves package definitions and
lexical bindings, emits native Z80 code for integer and boolean expressions,
and publishes checked NOBJ and `.COM` files.

```scheme
(define base 40)
(let* ((step 2)
       (answer (+ base step)))
  (if #t answer 0))
```

## Build

Skate uses Deno and the ATOM assembler adapter. Make the packages listed in
`deno.runtime.json` available beside the checkout, then compile a program with:

```sh
deno task compile examples/make-adder.sk8 build/make-adder.com cpm-64k
```

Run the host and runtime checks with:

```sh
deno task test
```

Run the scope compiler proof and size checks with:

```sh
deno task check:c2
deno task test:cpm:c2
deno task measure:c2
```

The [scope compiler notes](docs/scope-compiler/README.md) describe the current
language subset and its memory limits.

The `release/` directory contains the first tested CP/M artifacts and their
checksums.

## Scope

Skate is a work in progress under active development. The current compiler
supports exact integers, booleans, package definitions, lexical `let` and
`let*`, conditionals, `begin`, `and`, `or`, and the basic arithmetic forms.
Procedures, mutation, pairs, strings and collection are planned parts of the
language. The compiler is written for a 64K CP/M machine and keeps its tables,
generated code and stack within the available transient program area.
