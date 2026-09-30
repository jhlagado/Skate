# Skate codebase guide

This document is a route through the public Skate source tree. It is written
for a reader who knows Scheme and can read Z80 assembly but has not yet learned
how this repository is put together. It explains the public 0.5.11 compiler,
runtime and proof paths, then shows where to look when one feature needs to be
understood.

The public repository is the curated product tree. It contains the reviewed
language implementation, examples, release notes, provider tools and target
proofs. The private `skate-legacy` repository is a development archive. It
contains design notes, experiments and newer branches such as the ASO work. A
private change becomes part of public Skate only after it has been selected,
reconciled with the public tree and verified as a release increment.

## The reading route

Read the files in this order. Each step introduces the vocabulary needed by the
next one.

1. [`README.md`](../README.md) states the current language surface, build
   commands and public limitations.
2. [`release/v0.5.11/README.md`](../release/v0.5.11/README.md) gives the checked
   release image, measurements and examples.
3. [`docs/public/external-effects.md`](public/external-effects.md) explains the
   optional provider boundary for console, files and devices.
4. [`src/compiler/scope/compiler.asm`](../src/compiler/scope/compiler.asm) is the
   native compiler composition root. Its include order is the first map of the
   target compiler.
5. Read the native input files in this order: `cpm-source.asm`,
   `cpm-transport.asm`, `lexer.asm`, `decimal.asm`, `interner.asm` and
   `reader.asm`.
6. Read the scope compiler in this order: `command.asm`, `definitions.asm`,
   `bindings.asm`, `branches.asm`, `data.asm`, `procedure-forms.asm`,
   `emitter.asm` and `publication.asm`.
7. Read [`src/runtime/image.asm`](../src/runtime/image.asm) as the runtime
   composition root, then follow `core.asm`, storage, primitives, pairs, data,
   roots, numeric code, strings and vectors.
8. Finish with the matching proof in `tools/compiler-checks/`. The procedure
   proof is the best first example because it covers ordinary calls, closures,
   rest parameters, `apply` and one-shot `call/ec`.

The order is deliberate. The compiler emits calls into the runtime, so reading
runtime labels before the emitter gives little context. The proof brings the
compiler image, runtime image, CP/M disk and generated program together.

## Your first hour

Use one small program as a thread through the route. This ties names to a
behaviour instead of turning the tour into a directory listing.

```scheme
(begin
  (display (+ 40 2))
  (newline))
```

Find a matching expression in the procedure or console proof. Read the lexer
only far enough to see how the two numbers and the `+` symbol become tokens.
Read the command and emitter files to see the primitive identity and argument
packet being written. Then read the numeric primitive in `src/runtime/` to see
the packet being checked and folded. Run the smallest proof and compare its
output with the expected console text. Replace the expression with a `let`, a
pair or a small lambda and follow the same boundaries again.

## Reading one assembly module

Do not begin by reading every instruction in a large file. Establish the
module contract first.

1. Read the purpose and public-interface comments. Record input registers,
   returned value, carry or error convention, preserved registers, stack use
   and caller-owned workspace.
2. Find the public label in the composition file. Follow its first call rather
   than searching for every label with the same prefix.
3. At each internal label, write down the register meanings at entry and what
   each branch establishes before it joins another path.
4. Mark reads and writes of workspace, state, root descriptors and stack slots.
   These names identify ownership and lifetime while you trace a collector or a
   call frame.
5. When a routine calls another group, stop and read that group's contract
   before continuing. A packet pointer, tagged value or carry flag may change
   meaning at that boundary.
6. Finish with the smallest proof that invokes the entry point. The proof is
   the executable explanation of the contract.

The assembly comments explain register and flag usage beside the instructions.
The label prefixes also identify ownership. `SC` is the scope compiler, `RT` is
the runtime, `H` is managed storage, `N` is numeric work, `F16` is binary16
arithmetic, `CS` is CP/M source input and `LEX` is tokenisation.

## One program's journey

A source program travels through these boundaries:

```text
.SK8 source
    │
    ├─ optional leading (include "LIB.SK8") preparation
    │
    ▼
CP/M source stream
    │
    ├─ bytes, positions and CR/LF handling
    ├─ lexical tokens and literals
    ├─ decimal and binary16 conversion
    └─ symbols and reader events
    │
    ▼
Scope compiler
    │
    ├─ definitions and lexical scopes
    ├─ branches, calls, closures, pairs and data
    ├─ runtime calls and inline operands
    └─ logical image bytes and forward-reference fixups
    │
    ▼
NOBJ publication
    │
    ├─ object records for the staged image
    ├─ resolved addresses and descriptors
    └─ matching runnable image bytes
    │
    ▼
CP/M .COM program
    │
    ├─ native execution code
    ├─ literal tables and roots
    └─ frames, managed storage, stack and heap
```

The public compiler currently publishes a checked NOBJ object beside the COM
file. ASO is a later private development path in `skate-legacy`, not the output
format of public Skate 0.5.11. That distinction is intentional and should be
made explicit in release notes until the ASO work is promoted.

## The native compiler

`src/compiler/scope/compiler.asm` assembles the compiler in a fixed order. The
order affects addresses and workspace, so a composition change needs a proof.

| File or group | Responsibility |
| --- | --- |
| `src/compiler/cpm-source.asm` and `cpm-transport.asm` | Open the CP/M source file, supply bytes and track source positions |
| `src/compiler/lexer.asm` | Classify characters and produce tokens |
| `src/compiler/decimal.asm` | Parse exact integers and binary16 literals |
| `src/compiler/interner.asm` | Keep permanent symbol and string identities |
| `src/compiler/reader.asm` | Turn tokens into structural datum events |
| `src/compiler/scope/command.asm` | Dispatch top-level forms and maintain body state |
| `src/compiler/scope/definitions.asm` | Compile leading, internal and named definitions |
| `src/compiler/scope/bindings.asm` | Resolve lexical names and local slots |
| `src/compiler/scope/branches.asm` | Emit conditionals and branch fixups |
| `src/compiler/scope/data.asm` | Publish quoted data and literal roots |
| `src/compiler/procedure-forms.asm` | Compile calls, lambdas, captures and descriptors |
| `src/compiler/call-ec.asm` | Compile one-shot escape procedures |
| `src/compiler/scope/emitter.asm` | Emit runtime calls, values and patch sites |
| `src/compiler/scope/publication.asm` | Build NOBJ records, matching COM bytes and CP/M output |

A compiler feature normally crosses the form compiler, the emitter and the
runtime primitive. Read those three boundaries together rather than changing a
single file by itself.

## The runtime

`src/runtime/image.asm` composes the generated-program runtime loaded by the
native compiler. These are the current public runtime modules.

| File or group | Responsibility |
| --- | --- |
| `core.asm` | Startup, invocation and frame coordination |
| `managed.asm`, `page.asm` and `slabs.asm` | Managed storage pages and allocation state |
| `pair-management.asm` and `pairs.asm` | Pair construction, lists and collector-visible links |
| `roots.asm` and `data.asm` | Root descriptors, literal data and collector state |
| `primitives.asm` | Primitive dispatch and shared primitive support |
| `binary16.asm`, `numeric.asm` and `float.asm` | Exact arithmetic, division, conversion and binary16 operations |
| `strings.asm`, `managed-strings.asm` and `vectors.asm` | String and vector storage and operations |
| `output.asm` | Value printing and console output |
| `rest.asm`, `apply.asm` and `escape.asm` | Rest arguments, proper-list application and `call/ec` |
| `external-effects.asm` | Optional provider-facing byte boundary |
| `loader.asm` | Loads the runtime image into the generated program |

A runtime change often crosses three places: the compiler emitter that builds
the call, the primitive that implements it and the storage or root code that
keeps values live. The procedure and managed-storage proofs are the first tests
to read for such a change.

## Following common features

### Arithmetic

Start at `lexer.asm` and `decimal.asm`, then follow literal and call emission
through `scope/emitter.asm`. The runtime primitive dispatches to `numeric.asm`
and `binary16.asm`. Read `float.asm` as well when the expression mixes exact
integers with fractional values.

### Lambdas, closures and tail calls

Start at `procedure-forms.asm`, then read `scope/bindings.asm`. The generated
call enters `core.asm`, creates a frame and captures the required bindings.
Tail calls reuse the current activation after the new packet is checked. The
managed-storage and exact-root tests show why captured values and uncaptured
slots have different lifetimes.

### Vectors, rest parameters and apply

Start at `procedure-forms.asm` for dotted parameter lists and argument packet
construction. Follow `rest.asm` and `apply.asm` for list-backed argument
collection and application. Read `vectors.asm` with `pairs.asm` because vector
contents and list arguments share root and storage rules. The `--vectors` and
`--apply` procedure proof cases exercise these features directly.

### Pairs and quoted data

Start at `scope/data.asm`, then follow `pairs.asm`, `pair-management.asm` and
`data.asm`. The allocator and roots determine whether a pair remains live. A
pair bug is rarely confined to `cons`, `car` or `cdr`, because printing,
equality, argument lists and collection all depend on the same representation.

### Console and external effects

Start at `output.asm` and `external-effects.asm`, then read
`docs/public/external-effects.md` and the host provider tools. Ordinary console
text goes through the CP/M character boundary. Optional terminal, video, sound
and file requests use provider messages. The Scheme program emits bytes and
commands; it does not call a TMS9918 routine directly.

### Publication

Start at `scope/publication.asm`, then read `runtime/loader.asm` and the matching
CP/M proof. The publisher stages NOBJ and COM files, replaces the previous
pair transactionally and checks the generated program after installation.

## Tests and verification

Use the smallest proof that exercises the changed boundary, then run the full
public check before publishing an assembly change.

| Command | What it checks |
| --- | --- |
| `deno task check` | Formatting, lint, types, compiler budget and source inclusion |
| `deno task test:source-inclusion` | Include ordering, path rules and source-package preparation |
| `deno task test:cpm:procedures` | Procedures, closures, tail calls and ordinary application |
| `deno task test:cpm:features` | Vectors, bounded `apply` and one-shot `call/ec` |
| `deno task test:cpm:console` | Console input, output and runtime counters |
| `deno task test:cpm:generated-effects` | Provider-facing generated effect bytes |
| `deno task test:cpm:release` | Release disk, examples and publication checks |
| `deno task test:effects` | Host provider, terminal and bounded file tests |
| `deno task test:effects:cpm` | CP/M byte bridge tests |

The CP/M commands require sibling checkouts of ATOM, Debug80 runtime,
Z80 tool services and Triptych. Host provider tests can run without booting
CP/M, but they do not replace the target proof.

## Public contents and promotion

Public commits should contain the implementation needed to build and run the
reviewed language, its tests, examples, release notes and concise public
contracts. Private roadmaps, abandoned experiments, review transcripts and
unreleased allocator studies belong in `skate-legacy` until a decision promotes
them.

Promotion is a deliberate step. Copy the selected code and tests into the
public tree, update the public README and release notes, run the public checks
from a clean checkout and publish one versioned result. Do not make public
Skate depend on a private working directory or on a private manifest.

## Small glossary

| Term | Meaning in the public tree |
| --- | --- |
| source package | Ordered source parts prepared for the CP/M compiler |
| reader | The datum reader that turns the byte stream into structural events |
| scope compiler | The native compiler that resolves definitions, bindings, control flow and emitted calls |
| runtime image | The assembled provider image loaded by the compiler and used by generated programs |
| NOBJ | The current public object stream containing the staged image and records |
| COM | The runnable CP/M program produced beside the NOBJ file |
| root | A descriptor or live slot that tells the collector where a managed value is found |
| activation | The current call frame, argument packet, bindings and return state |
| heap | Managed storage for pairs, strings, vectors, closures and other values that outlive a stack slot |

When a comment gives a narrower local meaning, follow that contract. The
The glossary gives the common repository meaning so a first reading does not have
to reconstruct it from several modules.
