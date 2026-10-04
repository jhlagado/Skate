# Label names

ATOM allows a global label of one to eight characters and a private label
of a `.` followed by one to eight more. Matching ignores case. A private
label is visible only until the next global label. Skate uses that budget so
that a routine can be read from its label names alone.

## Convention

**Globals are `AREA_WHAT`.** A short area prefix, an underscore, then a
word: `STR_COPY`, `PAIR_NEW`, `LX_NEXT`, `PUB_UNDO`. Routines are verbs or
operations; variables are nouns; a trailing `P` marks a moving byte cursor
(`STR_SRCP`). The runtime and compiler assemble into separate images, so no
image prefix is needed.

**Only what other routines use is global.** Loop heads, join points, error
exits and single-caller helpers are private to the routine that owns them:
`.LOOP`, `.DONE`, `.BAD`, `.ALIGN`. Where one scope holds two loops, the
names say which (`.REF_LOOP`, `.LEN_LOOP`), never `.LOOP1`.

**Words, not consonant strings.** Spell words out. The short forms in use
are COPY JOIN NEXT FAIL DONE MARK LEN PTR IDX TMP ARG CHK NEW, plus CAR CDR
ENV SYM STR VEC NUM INT BUF POS CNT MSG ERR SRC DST LO HI. When a name will
not fit in eight characters, choose a different word rather than dropping
vowels.

**A few famous operations are bare.** `CONS`, `CAR`, `CDR`, `GC`, `APPLY`,
`START` and `ERROR` in the runtime. Add others sparingly.

**Upper case.** Labels are written in upper case like the rest of the
source. ATOM ignores case, so a later move to lower-case labels is a
mechanical pass with the tools below.

## Runtime prefixes

| Prefix | Area |
| --- | --- |
| `RT_` | Startup, memory map, image bounds, generated-code services |
| `FRM_`, `ENV_`, `DESC_`, `MASK_` | Frames, environments, procedure descriptors and their slot masks |
| `INV_`, `ARG_`, `G_`, `L_`, `RST_`, `APPLY_`, `REST_` | Invocation, inline operand helpers, restart vectors, `apply`, rest arguments |
| `CELL_`, `TAG_`, `META_`, `ELEM_` | The four-byte cell contract and its tags |
| `PAGE_`, `SLAB_`, `PAIR_`, `PS_`, `CAR_`, `CDR_` | Page manager, closure slabs, pairs and pair slabs |
| `HEAP_`, `BND_`, `CL_`, `SLOT_`, `MAP_` | Heap bindings, binding pages, closure heap, inline slots, slot-map copying |
| `ROOT_`, `GC_`, `CNT_` | Roots, collector, allocation counters |
| `PRIM_`, `PKT_`, `OPS_` | Primitive dispatch, argument packets, operator side stack |
| `STD_` | Standard procedures (`primitives/standard.asm`), one per Scheme procedure |
| `NUM_`, `F24_`, `FLT_` | Integer arithmetic, float24 internals, float printing |
| `STR_`, `VEC_` | Strings and vectors |
| `QT_`, `QUO_` | Quoted-data building and its encoding codes |
| `WR_`, `OUT_`, `TX_` | Writer, output adapters, runtime message text |
| `DR_`, `IO_` | Datum reader and the I/O module start |
| `PORT_`, `IN_`, `CON_`, `FILE_`, `CPM_` | Ports, input sources, CP/M console, files, CP/M transport |
| `EC_` | Escape continuations |

## Compiler prefixes

| Prefix | Area |
| --- | --- |
| `CPM_`, `SRC_`, `INC_` | CP/M transport (shared with the runtime), source files, includes |
| `LX_`, `DEC_`, `SYM_`, `RD_` | Lexer, decimal conversion, interner, reader |
| `CMD_`, `ST_`, `W_`, `DIAG_`, `ERR_`, `M_` | Command driver, state variables, layout equates, diagnostics, errors, message text |
| `K_`, `NAME_` | Form keyword spellings and the built-in name table |
| `EM_`, `BR_`, `IF_` | Emitter, branch patching, conditionals |
| `BIND_`, `LET_`, `GLB_`, `DEF_` | Bindings, `let` forms, globals, definitions |
| `PROC_`, `LAM_`, `CAP_`, `CALL_` | Procedures, lambdas, captures, calls |
| `LIT_`, `QUO_` | Literals and quoted data |
| `PUB_`, `REC_`, `ASO_`, `SINK_` | Publication, replay records, the ASO stream, the output sink |

`ST_` names group with one letter after the prefix: `R` recursive/letrec,
`B` body, `K` kept during retention, `L`/`G` local/global, `NL` named let,
`E` error position. A `_N` suffix marks a fixed limit (`W_PROC_N`).

The compiler also sees runtime names through the generated
`src/runtime/values.inc`. A mirrored equate keeps the runtime label's name,
so `CONS` and `QT_PUSH` mean the same routine in both images.

## Renaming tools

`tools/labels/` holds the tools used for the rename, and they work for any
later one:

| Script | Purpose |
| --- | --- |
| `list.ts <repo> <file>...` | Each definition with its status: stays global, may become private (and under which owner), or is pinned by a tool or test |
| `demote.ts <repo>` | Counts the globals that could still become private |
| `apply.ts <repo> <maps-dir> [--dry]` | Applies `{ "globals": {OLD: NEW or .NEW}, "privates": {OWNER: {.OLD: .NEW}} }` maps to the sources, tools, tests and docs. It rejects a name used twice in an image or a private scope, and keeps trailing comments in their column |
| `fingerprint.ts`, `verify.ts <repo> <baseline> <maps-dir>` | Take a baseline, then require byte-identical images and preserved symbol values after a rename |

For a rename: take a baseline (`cp tools/labels/fingerprint.ts
tools/.fingerprint.ts && deno run --config deno.runtime.json -A
tools/.fingerprint.ts $PWD > build/baseline.json`), write a map, run
`apply.ts`, then `verify.ts` must print `VERIFIED`. A rename that changes a
single output byte is a mistake.

The full rename went through these maps in October 2026, one commit per
area, each byte-identical to the image before it. The commits that
introduced the names are the record of what each old name became.

The few labels `demote.ts` still reports are kept global on purpose:
`CPM_REN` and `CPM_WIPE` are private in the runtime image but called across
files in the compiler image; the `INC_` routines are separate routines with
their own headers; `FRM_CELL` is currently unreferenced.
