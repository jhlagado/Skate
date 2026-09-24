# Skate 0.5.9

Skate is a Scheme compiler and runtime for Z80 computers running CP/M. This
release brings the language closer to a useful small-system implementation:
vectors, dotted rest parameters, bounded `apply` and one-shot `call/ec` are
now part of the compiled language, alongside the earlier numeric, list,
closure, mutation and console facilities.

The compiler accepts fixed-prefix procedures such as
`(lambda (first . rest) ...)` as well as procedures whose entire argument list
is collected with `(lambda args ...)`. `apply` takes a procedure, zero or more
leading arguments and a final proper list; the compiled argument packet is
bounded at eight values. Vectors provide `vector`, `make-vector`, `vector-ref`,
`vector-set!`, `vector-length` and `vector?`, with a checked limit of 64
elements. `call/ec` supplies a one-shot escape procedure for early returns.

The provider tools and source-preparation command remain available. A leading
form such as `(include "LIBRARY.SK8")` is expanded by the host into the ordered
`.SKM` package used by the CP/M compiler. Terminal, input, video, sound and
bounded file requests remain host services carried by the optional byte
protocol; they are not direct device operations in Scheme.

## Measurements

The compiler and runtime were assembled with ATOM and exercised through the
Triptych CP/M host. The logical sizes are:

| Component | Bytes |
| --- | ---: |
| `SKATE.COM` compiler | 18,383 |
| `SKATE.RT` runtime payload | 17,003 |
| Checked release `RELEASE.COM` | 18,560 |
| Checked release `RELEASE.NOB` | 18,688 |
| Included source package | 8,361 |

The release program uses 49,152 bytes as its managed-heap ceiling and reached
the CP/M stack guard without a collision. The release proof's 256 KiB CP/M
working image contains 43 files, uses 218 disk blocks and leaves 23 blocks
free. The hosted 2 MiB Triptych image contains the 25 Skate files and leaves
1,961,984 bytes and 997 directory entries free.

## Verification

From a checkout with ATOM, the Z80 runtime and the Triptych tools available:

```sh
deno task check
deno task test:cpm
deno task test:effects
deno task test:effects:cpm
```

The CP/M release proof compiles the included source package, runs it after a
remount, rejects a full-disk publication without damaging the previous output,
and preserves the previous output after a source error. The feature proofs
exercise rest parameters, `apply`, vectors, vector collection and one-shot
escapes, including their error paths.

The matching Triptych disk image is in
[`site/releases/0.5.9/skate.img`](../../site/releases/0.5.9/skate.img), with
the loader description in
[`site/releases/0.5.9/system.json`](../../site/releases/0.5.9/system.json).

## Limits

This release does not include a general macro system or quasiquote, reusable
`call/cc`, `eval`, Scheme ports or general file procedures. Direct port I/O is
left to the provider boundary. The native argument packet, vector length and
other workspace limits are checked at compile or run time rather than allowed
to overwrite CP/M memory.
