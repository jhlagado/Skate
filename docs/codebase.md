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
   target compiler, and it fixes the compiler's addresses.
5. The scope compiler comes first in that order: `command.asm`,
   `command-support.asm`, `replay.asm`, `definitions.asm`, `data.asm`,
   `../procedure-forms.asm`, `../call-ec.asm`, `bindings.asm`,
   `binding-primitives.asm`, `branches.asm` and `emitter.asm`.
6. Output and publication follow: `output-sink.asm`, `aso-writer.asm`,
   `publication.asm`, `aso-materializer.asm` and `publication-recovery.asm`.
7. The CP/M input path is assembled last: `../cpm-source.asm`,
   `../cpm-transport.asm`, the runtime loader `../../runtime/loader.asm`,
   `../lexer.asm`, `../decimal.asm`, `../interner.asm` and `../reader.asm`.
   Reading this path before the scope compiler is usually easier, even though
   it is assembled after it.
8. [`src/runtime/image.asm`](../src/runtime/image.asm) is the runtime
   composition root. It starts with the cell contract and `core.asm`, then
   storage, primitives, ports, the datum reader, pairs, output, roots, data,
   numeric code, strings, vectors, rest arguments, `apply` and `call/ec`.
9. The corresponding proofs are in `tools/compiler-checks/`. The procedure
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
workspace. These contracts connect routines across file boundaries. In the
refactored modules, a short purpose and entry contract comes first; detailed
register and branch comments stay beside the routine they explain.

Within a routine, register meanings depend on the current operation. Branches
establish conditions that subsequent instructions rely on. Workspace, root
descriptors and stack slots record state whose lifetime may extend beyond a
single call. A packet pointer or tagged value can therefore require both the
local instruction sequence and the called routine's contract to interpret it.

The focused proofs exercise these interfaces with concrete inputs and expected
results. They provide a second description of each contract alongside the
assembly comments.

The assembly comments explain register and flag usage beside the instructions.
Label names follow [docs/labels.md](labels.md): a global is `AREA_WHAT`
(`PAIR_NEW`, `LX_NEXT`, `PUB_UNDO`), and the prefix tables there map each
area to its files. Labels used only inside one routine are private (`.LOOP`).

## One program's journey

A source program travels through these boundaries:

```text
.SK8 source
    │
    ├─ leading (include "LIB.SK8") forms, resolved depth first
    │
    ▼
CP/M source stream
    │
    ├─ bytes, positions and CR/LF handling
    ├─ lexical tokens and literals
    ├─ decimal and float24 conversion
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
    ├─ runtime image
    ├─ fixed 1 KB global area
    ├─ native execution code and procedure descriptors
    ├─ static locals, quoted-list caches and literal tables
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

The table follows that include order. Paths are relative to `src/compiler/`
unless they start with `src/runtime/`.

| File or group | Responsibility |
| --- | --- |
| `scope/command.asm` and `scope/command/` | Drive the top level and dispatch forms, conditionals and bodies |
| `scope/command-support.asm` | Errors, compiler state, diagnostics and accepted primitive names (`scope/command/`) |
| `scope/replay.asm` and `scope/replay/` | Capture and replay binding-list events, symbol spellings and deferred declarations |
| `scope/definitions.asm` and `scope/definitions/` | Compile leading, internal and named definitions |
| `scope/data.asm` and `scope/data/` | Publish quoted data and literal roots |
| `procedure-forms.asm` and `procedures/` | Compile calls, lambdas, captures and descriptors |
| `call-ec.asm` | Compile one-shot escape procedures |
| `scope/bindings.asm` and `scope/bindings/` | Resolve lexical names, local slots, globals and initializers |
| `scope/binding-primitives.asm` | Recognise predefined procedure names |
| `scope/branches.asm` | Emit conditionals and branch fixups |
| `scope/emitter.asm` | Emit runtime calls, values and patch sites |
| `scope/output-sink.asm` and `scope/aso-writer.asm` | Record emitted bytes and patches using logical image addresses |
| `scope/publication.asm` and `scope/publication/` | Lay out the image, patch descriptors and write the publication stream |
| `scope/aso-materializer.asm` | Replay the stream through bounded windows into the COM file |
| `scope/publication-recovery.asm` | Recover an interrupted replacement |
| `cpm-source.asm`, `cpm-source-include-parser.asm` and `source/` | Resolve the include tree, stream the ordered source files and track source positions |
| `cpm-transport.asm` | CP/M binary record transport for compiler stages; the runtime image also includes it for file ports |
| `src/runtime/loader.asm` | Load the checked `SKATE.RT` runtime into the staged output image; part of the compiler, not the runtime image |
| `lexer.asm` and `lexer/` | Classify characters and produce tokens |
| `decimal.asm` and `decimal/` | Parse exact integers and float24 literals |
| `interner.asm` | Keep permanent symbol and string identities |
| `reader.asm` | Turn tokens into structural datum events |

A compiler feature normally crosses the form compiler, the emitter and the
runtime primitive. Changes to a form can therefore affect all three interfaces.

## The runtime

`src/runtime/image.asm` composes the generated-program runtime loaded by the
native compiler. The table follows its include order; paths are relative to
`src/runtime/`.

| File or group | Responsibility |
| --- | --- |
| `storage/cell-contract.asm` | Four-byte value-cell layout constants; emits no bytes |
| `core/entry.asm` and the `*/state.asm` files | The entry at 0100H, then the runtime's state ahead of its code |
| `core.asm` and `core/` | Startup, environment, invocation and frame coordination |
| `storage/stack-slots.asm` and `storage/slots/` | Inline local bindings and promotion of captured bindings |
| `storage/managed.asm` | Managed closure and four-byte binding storage |
| `storage/page.asm` and `storage/page/` | Page initialisation, allocation and release |
| `primitives.asm` and `primitives/` | Primitive dispatch and numeric, predicate, I/O, data, pair and output primitives |
| `ports.asm`, `cpm-ports.asm`, `../compiler/cpm-transport.asm` and `file-ports.asm` | Scheme port values, console byte services and CP/M sequential files |
| `datum-reader.asm`, `datum-strings.asm`, `datum-symbols.asm`, `datum-lists.asm` and `datum-vectors.asm` | Read Scheme data from an input port |
| `storage/pair-management.asm` and `storage/pairs.asm` | Eight-byte pair cells, lists and collector-visible links |
| `output.asm` and `output/state.asm` | Value printing, port output and shared runtime state |
| `roots.asm` and `roots/` | Root scanning, managed roots and binding roots |
| `data.asm` and `data/` | Quoted data, the collector, the data writer and collector state |
| `float.asm` | Exact decimal printing of floats |
| `storage/slabs.asm` | Closure pages within the runtime pool |
| `float24.asm` and `float24/` | Float24 classification, arithmetic, rounding, comparison and conversion |
| `numeric.asm` and `numeric/` | Exact arithmetic, division, conversion and comparison |
| `strings.asm`, `managed-strings.asm` and `strings/` | String and character primitives and managed string storage |
| `vectors.asm` and `vectors/` | Vector operations, storage and tracing |
| `rest.asm`, `apply.asm` and `escape.asm` | Rest arguments, proper-list application and `call/ec` |
| `primitives/standard.asm` | Standard procedures added after the original set: pair mutation, `equal?`, comparisons, conversions, list operations and `case` key matching |
| `quoted.asm` | Decodes the compact encoding of quoted lists into pairs on first use |

Two runtime files are not part of `image.asm`. `loader.asm` is assembled into
the compiler, and `external-effects.asm`, the optional provider-facing CP/M
byte bridge, is assembled only by the test fixture `tests/cpm-effects.asm`.

A runtime change often crosses three places: the compiler emitter that builds
the call, the primitive that implements it and the storage or root code that
keeps values live. The procedure and managed-storage proofs are the first tests
to read for such a change.

Heap bindings, pairs and vector elements use four-byte value cells. The
representation, its capacity consequences and the design record behind it are
in [`four-byte-cells.md`](four-byte-cells.md). The layout constants live in
`storage/cell-contract.asm`.

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

## Generated code

Generated code is mostly calls into the runtime, so its size is dominated by
how those calls are encoded.

* **RST vectors.** Startup installs `JP` instructions at `RST 08H` to `30H`
  (`RST_SET` in `core/invocation.asm`). The compiler's `EM_CALL` emits a
  one-byte `RST` instead of a three-byte `CALL` for the six helpers in its
  `.VECTORS` table in `EM_CALL`: `ARG_PUSH`, `L_LOAD`, `PRIM_OP`, `QT_PUSH`, `G_OPSH` and
  `INV_OP`. The two tables must list the same helpers in the same order.
  `RST 38H` is left for a debugger.
* **Inline operands.** Helpers that name a slot or a primitive read one byte
  after the call and return past it: `L_LOAD`, `L_STORE` and `L_SET` take a
  procedure-local slot, `G_LOAD`, `G_STORE`, `G_SET` and `G_OPSH` a global
  slot, and `PRIM_OP` and `PRIM_TL` a primitive's payload byte. Globals sit
  in a fixed 1 KB area after the runtime, so the slot number is enough.
* **Arguments.** Each argument is pushed with `ARG_PUSH`, which records an
  exact root and pushes the value below the return address.
* **Descriptors.** Each procedure's descriptor follows its body: body
  address, arity, the shared slot extent (patched at the end), four formal
  fields, a mask width `W`, then `W` bytes of owned-slot mask and `W` bytes of
  capture mask.
* **Quoted lists.** A quoted list is `CALL QT_BUILD`, a cache-cell word, the
  address after the data and a compact encoding of the list, decoded into
  pairs on first use by `quoted.asm`. The encoding is described there.

## Runtime variants

The runtime image is ordered core first, then the standard-procedure module
(`primitives/standard.asm`, from `STD_MOD`) and then the I/O module (the
datum reader, file ports and CP/M transport, from `IO_START`). Before
compiling, `CMD_INIT` reads the whole source once. A standard procedure or
`case` selects the core and standard module; `read` or a file opener selects
the whole runtime; anything else loads the core alone. The compiler loads
that prefix of `SKATE.RT` and places the global area and code straight after
it, so a program pays only for the modules it can reach.

The core must never read a module's state or run its code except through a
primitive the scan detects. Variables the core shares with the I/O module
live in `io-state.asm`; the exit and error paths close a file only when
`OUT_FILE` says one is open.

## Following common features

### Arithmetic

Literal parsing is in `lexer.asm` and `decimal.asm`. Literal and call emission
is in `scope/emitter.asm`. The runtime primitive dispatches to `numeric.asm`
and `float24.asm`. `float.asm` prints floats.

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

`deno task test` runs the host-side suite; `deno task test:cpm` runs the CP/M
proofs; `deno task test:all` runs both plus `test:cpm:stress`.

| Command | What it checks |
| --- | --- |
| `deno task check` | Formatting, lint, types, compiler budget and freshness of the generated runtime files |
| `deno task test` | `check`, `test:effects`, `test:effects:cpm`, `test:aso`, `test:ports` and `test:runtime` |
| `deno task test:all` | `test`, `test:cpm` and `test:cpm:stress` |
| `deno task measure` | Compiler and runtime size budget report |
| `deno task census` | Compiler and runtime bytes by directory and file |
| `deno task runtime` | Reassemble `src/runtime/image.asm` and rewrite `src/runtime/values.inc` and `template.inc`; run after any runtime change |
| `deno task test:effects` | Host provider, terminal and bounded file tests |
| `deno task test:effects:cpm` | CP/M byte bridge tests (`tests/cpm-effects.asm`) |
| `deno task test:aso` | Stream validation and window-boundary patches |
| `deno task test:ports` | Effect-port qualification and runtime port fixtures |
| `deno task test:runtime` | Runtime unit fixtures: heap, pages, roots, datum reader, strings, symbols, vectors and cell metrics |
| `deno task test:cpm` | Every `test:cpm:*` proof below except the stress group |
| `deno task test:cpm:core` | Core forms, the compile-error corpus (`--errors`) and the no-implicit-output check (`--no-output`) |
| `deno task test:cpm:procedures` | Procedures, closures, tail calls and ordinary application |
| `deno task test:cpm:runtime-errors` | Arity, rest-arity, unbound `set!`, deep recursion and stale escape errors at run time |
| `deno task test:cpm:data` | Pairs, lists, strings, quoted data and the list libraries |
| `deno task test:cpm:features` | Vectors, bounded `apply` and one-shot `call/ec` in one run |
| `deno task test:cpm:integers` | Exact integer arithmetic and its runtime errors |
| `deno task test:cpm:regressions` | Regression cases for fixed compiler defects |
| `deno task test:cpm:edge` | Named `let`, captures and internal-definition edge cases |
| `deno task test:cpm:console` | Standard and file ports, datum input and source I/O helpers |
| `deno task test:cpm:examples` | The terminal demo with its included library and the house adventure |
| `deno task test:cpm:generated-effects` | Provider-facing generated effect bytes |
| `deno task test:cpm:float` | Float literals, arithmetic and printing |
| `deno task test:cpm:includes` | Nested, import-once, cyclic, missing and bounded include trees |
| `deno task test:cpm:release` | Release disk, examples and publication checks |
| `deno task test:cpm:recovery` | Replacement failure and preservation of prior output |
| `deno task test:cpm:workloads` | Larger programs in `examples/workloads`: output, COM size, heap use and collections |
| `deno task test:cpm:stress` | `test:cpm:capacity`, `test:cpm:large` and `test:cpm:full-image` |
| `deno task test:cpm:capacity` | Compiler capacity: 256 globals with short, long and string-valued definitions, and a 256-form `begin` |
| `deno task test:cpm:large` | Compilation of a 6,200-form source file |
| `deno task test:cpm:full-image` | Materialization of a 65,280-byte image; does not execute that image |

The procedure proof accepts several mode flags in one run (for example
`--vectors --apply --ec`), so related groups share one assembly of the
compiler and runtime. `scope-cpm-proof.mjs` needs a separate boot per mode
because each corpus fills the CP/M directory. The CP/M proofs share the disk
and console helpers in `tools/compiler-checks/cpm-harness.mjs`.

The CP/M commands require sibling checkouts of ATOM (including its Z80 runtime dependency),
Z80 tool services and Triptych. Host provider tests can run without booting
CP/M, but they do not replace the target proof.

## Small glossary

| Term | Meaning in the public tree |
| --- | --- |
| source part | One file of a program; included parts precede the files that include them |
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
