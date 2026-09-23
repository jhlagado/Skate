# Skate 0.5.8

Skate is a small Scheme compiler for Z80 computers running CP/M. This release
adds the provider protocol used to carry optional terminal, input, video,
sound and bounded file operations beside ordinary console text.

The language and native compiler remain the 0.5.7 contract. Programs still
use the existing text and character procedures, fixed-arity procedures,
closures, pairs, lists, mutation, tail calls, exact signed integers and
binary16 numbers. The provider protocol is implemented by the host tools and
the small CP/M console bridge; it does not add device registers, file handles
or a general port system to Scheme.

The release includes provider-neutral TypeScript modules, deterministic tests,
the ANSI terminal source library and a terminal example. Triptych video and
sound handles are logical capabilities; a host supplies the backend that gives
them physical meaning.

It also includes a host source-preparation command for leading forms such as
`(include "LIBRARY.SK8")`. The resolver orders dependencies, imports shared
files once, preserves source locations while masking the directives, and
rejects cycles, root escapes and names that do not fit CP/M file rules. The
prepared output is the existing ordered `.SKM` package format; no resident
compiler include mechanism is added.

## Size

The provider work does not change the native compiler or runtime image:

| Component | Logical bytes |
| --- | ---: |
| `SKATE.COM` compiler | 17,732 |
| `SKATE.RT` runtime payload | 13,725 |
| Checked release `.COM` example | 15,763 |

The CP/M bridge remains a separate ATOM source module. Full raw and mixed
effect framing is a provider responsibility, so a target that carries it must
account for its own buffers and resident code.

## Verification

With ATOM and the Z80 support packages beside the checkout:

```sh
deno task check
deno task test:effects
deno task test:effects:cpm
```

The host checks cover frame encoding, split streams, terminal controls, input
events, Triptych routing, bounded files and CP/M text/raw/mixed modes. The
source-inclusion checks cover ordering, masking, cycles, path confinement and
CP/M manifest preparation. The CP/M checks assemble and exercise both the
direct byte bridge and an included source package.

## Limits

Rest parameters, `apply`, vectors, quasiquote, general macros, reusable
continuations, `eval`, Scheme ports and general file procedures remain outside
the language. A provider can expose services through the byte protocol without
turning those services into native Scheme primitives.
