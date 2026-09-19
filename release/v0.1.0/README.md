# Skate 0.1.0

This is the first public Skate product snapshot. It contains the current
native compiler and runtime for a small, tested Scheme subset on Z80 CP/M.

The package includes two ready-to-run CP/M programs, their NOBJ inputs, and the
source and tools needed to rebuild them. Both programs were compiled for the
`cpm-64k` target and executed successfully in the Triptych CP/M 2.2 proof
environment.

## Included programs

- `make-adder.com` builds a closure and reports `12` for the tested call.
- `shared-counter.com` preserves mutable procedure state and reports `2` for
  the tested sequence.

The `.nobj` files are the compiler's checked NOBJ 1.0 output. The `.com` files
are the linked CP/M images loaded at `$0100`.

## Rebuild

The public source uses Deno and the ATOM assembler adapter. The toolchain
packages used by the build are listed in `deno.runtime.json`; install or make
them available beside the checkout before running the commands below.

```sh
deno task compile examples/make-adder.sk8 build/make-adder.com cpm-64k
deno task compile examples/shared-counter.sk8 build/shared-counter.com cpm-64k
```

Run the host and runtime tests with:

```sh
deno task test
```

The release artifacts and the rebuild inputs are listed in `SHA256SUMS`.

## Current scope

This release demonstrates native numeric evaluation, literals, pairs, bounded
source packages, closure mutation and CP/M publication. It is an early product
slice: general procedure generation, full list traversal, broad control flow,
large heaps and self-hosting are still under development.
