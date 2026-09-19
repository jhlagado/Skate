# Skate

Scheme for a 64K computer.

Skate is a small native Scheme compiler and runtime for Z80 computers running
CP/M. It turns `.sk8` source into NOBJ 1.0 output and linked `.COM` programs
that can run from the CP/M prompt.

The current public product demonstrates numeric evaluation, literals, pairs,
source packages, closure mutation and direct CP/M publication. It is designed
for machines where every byte matters: the compiler, generated program and
runtime are measured against the available CP/M memory map.

```scheme
(define (make-counter start)
  (lambda ()
    (set! start (+ start 1))
    start))

(define next (make-counter 40))
(write (next))  ; 41
(newline)
(write (next))  ; 42
(newline)
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

The `release/` directory contains the first tested CP/M artifacts and their
checksums.

## Scope

Skate is an early, working product slice. General procedure generation, full
list traversal, broad control flow, larger heaps and self-hosting remain future
work. The public source is organized around the compiler, runtime, examples,
tests and the tools needed to rebuild the released programs.
