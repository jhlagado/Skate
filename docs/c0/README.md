# Skate C0 checkpoint

C0 is the first public checkpoint for the compact Skate compiler. It records
the language contract and the measured building blocks for a small Scheme
system on Z80 CP/M. Skate remains a work in progress; C0 does not claim that
the compact compiler is complete.

The evidence in this directory covers:

- the integer and value contract, including boundary arithmetic;
- two equivalent ATOM parser candidates and their size, workspace and stack
  measurements;
- bounded names, scopes and pending fixups against a representative source
  package;
- streamed NOBJ output, late record patches and provider placement;
- separate binary16 cost measurements; and
- source-file size checks for readable, modular implementation work.

C0 measures the compact compiler against a 16,384-byte code and immutable-data
limit and a 30,720-byte initial allocation. Those are implementation targets,
not a claim that the integrated compiler already fits them. The current public
release retains the tested native prototype and its CP/M artifacts while the
compact implementation is developed.

Run the evidence checks with:

```sh
deno task check:c0
```

The ATOM adapter and its sibling runtime packages must be available beside the
checkout, as they are for the main build and runtime tests.
