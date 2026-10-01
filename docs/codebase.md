# Skate codebase guide

This document is a route through the public Skate source tree. It is written
for a reader who knows Scheme and can read Z80 assembly but has not yet learned
how this repository is put together. It explains the current native compiler,
runtime and proof paths, then shows where to look when one feature needs to be
understood.

The public repository is the development home for Skate. It contains the
compiler, runtime, examples and tests needed to build and run the language.
Release directories preserve published snapshots; the source tree may contain
changes made since the latest release.

## The reading route

[Following a local binding](tutorial/bindings.md). It traces a small `let`
expression through scope tables, instruction emission and runtime storage,
using excerpts from this checkout. The file map below is a reference to use
alongside that account.

The following order follows the dependencies between the main subsystems.

1. [`README.md`](../README.md) states the current language surface, build
   commands and public limitations.
2. [`release/v0.5.11/README.md`](../release/v0.5.11/README.md) gives the checked
   release image, measurements and examples.
3. [`docs/public/external-effects.md`](public/external-effects.md) explains the
   optional provider boundary for console, files and devices.
4. [`src/compiler/scope/compiler.asm`](../src/compiler/scope/compiler.asm) is the
   native compiler composition root. Its include order is the first map of the
   target compiler.
5. The native input sequence consists of `cpm-source.asm`,
   `cpm-transport.asm`, `lexer.asm`, `decimal.asm`, `interner.asm` and
   `reader.asm`.
6. The scope compiler sequence consists of `command.asm`, `definitions.asm`,
   `bindings.asm`, `branches.asm`, `data.asm`, `procedure-forms.asm`,
   `emitter.asm` and `publication.asm`.
7. [`src/runtime/image.asm`](../src/runtime/image.asm) is the runtime
   composition root, including `core.asm`, storage, primitives, pairs, data,
   roots, numeric code, strings and vectors.
8. The corresponding proofs are in `tools/compiler-checks/`. The procedure
   proof covers ordinary calls, closures,
   rest parameters, `apply` and one-shot `call/ec`.

The order is deliberate. The compiler emits calls into the runtime, so reading
runtime labels before the emitter gives little context. The proof brings the
compiler image, runtime image, CP/M disk and generated program together.

## An expression through the compiler

A small arithmetic expression crosses the input, emission and runtime layers:

```scheme
(begin
  (display (+ 40 2))
  (newline))
```

The lexer produces tokens for the numbers and the `+` symbol. The command and
emitter routines generate the primitive call and its argument packet. At
runtime, the numeric primitive checks the packet and folds the operands into
a result. Console output then prints that result. Bindings, pairs and lambdas
add scope or storage requirements to this same compilation path.

## Assembly module contracts

A module's public interface describes its input registers, returned value,
carry or error convention, preserved registers, stack use and caller-owned
workspace. These contracts connect routines across file boundaries.

Within a routine, register meanings depend on the current operation. Branches
establish conditions that subsequent instructions rely on. Workspace, root
descriptors and stack slots record state whose lifetime may extend beyond a
single call. A packet pointer or tagged value can therefore require both the
local instruction sequence and the called routine's contract to interpret it.

The focused proofs exercise these interfaces with concrete inputs and expected
results. They provide a second description of each contract alongside the
assembly comments.

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
Publication stream
    │
    ├─ ASO byte, reservation and patch records
    ├─ bounded replay windows and resolved addresses
    └─ matching runnable image bytes
    │
    ▼
CP/M .COM program
    │
    ├─ native execution code
    ├─ literal tables and roots
    └─ frames, managed storage, stack and heap
```

The compiler records emitted bytes and address patches in an ASO stream on
disk. The materializer replays it through a bounded memory window, writing the
COM in sections. The complete output need not fit inside the compiler's
workspace. The intermediate stream is a build detail; the runnable COM is the
program the user starts.

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
| `src/compiler/scope/output-sink.asm` and `aso-writer.asm` | Record emitted bytes and patches using logical image addresses |
| `src/compiler/scope/aso-materializer.asm` | Replay the stream through bounded windows into the COM file |
| `src/compiler/scope/publication.asm` and `publication-recovery.asm` | Publish files and recover interrupted replacement |

A compiler feature normally crosses the form compiler, the emitter and the
runtime primitive. Changes to a form can therefore affect all three interfaces.

## The runtime

`src/runtime/image.asm` composes the generated-program runtime loaded by the
native compiler. These are the current public runtime modules.

| File or group | Responsibility |
| --- | --- |
| `core.asm` | Startup, invocation and frame coordination |
| `storage/managed.asm`, `storage/page.asm` and `storage/slabs.asm` | Managed storage pages and allocation state |
| `storage/pair-management.asm` and `storage/pairs.asm` | Pair construction, lists and collector-visible links |
| `roots.asm` and `data.asm` | Root descriptors, literal data and collector state |
| `primitives.asm` | Primitive dispatch and shared primitive support |
| `binary16.asm`, `numeric.asm` and `float.asm` | Exact arithmetic, division, conversion and binary16 operations |
| `strings.asm`, `managed-strings.asm` and `vectors.asm` | String and vector storage and operations |
| `storage/stack-slots.asm` | Inline local bindings and promotion of captured bindings |
| `ports.asm`, `cpm-ports.asm` and `file-ports.asm` | Scheme port values and CP/M byte/file services |
| `datum-*.asm` | Read Scheme data from an input port |
| `output.asm` and `output/state.asm` | Value printing, port output and shared runtime state |
| `rest.asm`, `apply.asm` and `escape.asm` | Rest arguments, proper-list application and `call/ec` |
| `external-effects.asm` | Optional provider-facing byte boundary |
| `loader.asm` | Loads the runtime image into the generated program |

A runtime change often crosses three places: the compiler emitter that builds
the call, the primitive that implements it and the storage or root code that
keeps values live. The procedure and managed-storage proofs are the first tests
to read for such a change.

The vector implementation separates three parts of one value.
[`vectors/ops.asm`](../src/runtime/vectors/ops.asm) contains the Scheme
operations, [`vectors/storage.asm`](../src/runtime/vectors/storage.asm) allocates
and validates blocks, and [`vectors/trace.asm`](../src/runtime/vectors/trace.asm)
marks and traverses their elements. `vectors/state.asm` holds shared scratch.
Managed strings use the same separation between operations and storage in
[`strings/ops.asm`](../src/runtime/strings/ops.asm) and
[`strings/storage.asm`](../src/runtime/strings/storage.asm), with scratch in
`strings/state.asm`. Strings contain bytes rather than managed references, so
their collector support only marks a leaf. The composition files retain the
original emitted order.

## Following common features

### Arithmetic

Literal parsing is in `lexer.asm` and `decimal.asm`. Literal and call emission
is in `scope/emitter.asm`. The runtime primitive dispatches to `numeric.asm`
and `binary16.asm`. `float.asm` handles the associated floating-point support.

### Lambdas, closures and tail calls

Procedure compilation is in `procedure-forms.asm`, with binding resolution in
`scope/bindings.asm`. The generated
call enters `core.asm`, creates a frame and captures the required bindings.
Tail calls reuse the current activation after the new packet is checked. The
managed-storage and exact-root tests show why captured values and uncaptured
slots have different lifetimes.

### Vectors, rest parameters and apply

`procedure-forms.asm` handles dotted parameter lists and argument packet
construction. `rest.asm` and `apply.asm` implement list-backed argument
collection and application. Vector contents and list arguments also depend on
the root and storage rules in `vectors.asm` and `pairs.asm`. The `--vectors` and
`--apply` procedure proof cases exercise these features directly.

### Pairs and quoted data

Quoted-data compilation is in `scope/data.asm`. Runtime support is in
`pairs.asm`, `pair-management.asm` and `data.asm`. The allocator and roots determine whether a pair remains live. A
pair bug is rarely confined to `cons`, `car` or `cdr`, because printing,
equality, argument lists and collection all depend on the same representation.

### Console and external effects

`ports.asm` implements Scheme stream operations. `cpm-ports.asm` supplies
replaceable byte services for the console; `file-ports.asm` uses CP/M file
services for sequential files. Host provider tools can instead carry file and
device requests in messages. The byte-service boundary and command protocol
are described separately in `docs/public/external-effects.md`. The Scheme program emits bytes and
commands; it does not call a TMS9918 routine directly.

### Publication

Publication is implemented in `scope/publication.asm` and `runtime/loader.asm`,
with windowed replay in `scope/aso-materializer.asm`. The publisher prepares
the stream and COM files, replaces the previous
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
| `deno task test:cpm:console` | Standard and file ports, datum input and source I/O helpers |
| `deno task test:cpm:recovery` | Replacement failure and preservation of prior output |
| `deno task test:cpm:full-image` | Materialization of a 65,280-byte image; does not execute that image |
| `deno task test:aso` | Stream validation and window-boundary patches |
| `deno task test:cpm:generated-effects` | Provider-facing generated effect bytes |
| `deno task test:cpm:release` | Release disk, examples and publication checks |
| `deno task test:effects` | Host provider, terminal and bounded file tests |
| `deno task test:effects:cpm` | CP/M byte bridge tests |

The CP/M commands require sibling checkouts of ATOM (including its Z80 runtime dependency),
Z80 tool services and Triptych. Host provider tests can run without booting
CP/M, but they do not replace the target proof.

## Small glossary

| Term | Meaning in the public tree |
| --- | --- |
| source package | Ordered source parts prepared for the CP/M compiler |
| reader | The datum reader that turns the byte stream into structural events |
| scope compiler | The native compiler that resolves definitions, bindings, control flow and emitted calls |
| runtime image | The assembled provider image loaded by the compiler and used by generated programs |
| publication stream | Intermediate records used while building and checking the COM image |
| COM | The runnable CP/M program produced for CP/M |
| root | A descriptor or live slot that tells the collector where a managed value is found |
| activation | The current call frame, argument packet, bindings and return state |
| heap | Managed storage for pairs, strings, vectors, closures and other values that outlive a stack slot |

Individual module contracts may define these terms more narrowly. The glossary
gives their common repository meanings.
