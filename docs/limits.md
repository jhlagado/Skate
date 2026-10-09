# Skate limits register

- Status: working record, first full survey
- Date: 2026-10-08
- Related: [value contract](value-contract.md), [float24](float24.md),
  [four-byte cells](four-byte-cells.md), [codebase guide](codebase.md),
  README "Program limits"

This register lists every limit a Skate programmer can meet, why it has its
value, what happens when it is exceeded, and what should be done about it.
The figures come from the source and were checked by compiling and running
probe programs on the CP/M harness (`tools/compiler-checks/cpm-harness.mjs`).
A figure marked *measured* was found that way rather than read from an
equate.

## 1. The rule

Skate adopts the rule of the Basie register:

**No limit is smaller than memory allows, unless the image format, CP/M or a
measured cost requires it.** Every limit is listed here with its reason and
is reported by a diagnostic or a runtime error when reached. No limit may be
enforced by wrapping, truncating or silently corrupting anything.

Limits fall into four kinds:

| Kind | Meaning |
| --- | --- |
| **Language** | Part of what Skate is: the same on any implementation |
| **Format** | Set by the `.COM` image, the source format or an internal encoding |
| **CP/M** | Set by CP/M 2.2 itself |
| **Capacity** | Set by a fixed table or memory band in this implementation |

Each capacity limit gets one of three verdicts:

| Verdict | Meaning |
| --- | --- |
| **Keep** | Justified at this size; document it and move on |
| **Raise** | Arbitrary: can be doubled or more for a known number of bytes, with no change of design |
| **Rework** | Needs a structural change (a wider field, a computed layout, streaming) before it can grow |

Skate does not yet fully meet the rule. Section 7 lists the silent failures,
those fixed and those that remain, and section 8 the diagnostics.

## 2. Summary: the limits that matter

These are the limits a programmer is likely to meet first, in the order in
which they should be dealt with.

| Limit | Today | Verdict | Proposal |
| --- | --- | --- | --- |
| Runnable program size | 45,056 bytes of `.COM` (an image ending at `B100H`); a larger image is `CAP` | Keep | The heap and the stack share what the program leaves below `B800H`. Sizing the collector maps to the heap, not to `3000H`–`C000H`, would add about 5 KB more (§6.2) |
| Non-tail recursion depth | Bounded by the memory the heap is not using: about 15 bytes a level for a one-argument procedure, so 1,500 levels in a small program (measured); each 8 KB of heap in use costs about 550 levels | Keep | The stack and the heap share one region (§6.2) |
| Size of a `do` | 1,504 reader events for the form and its rewrite: a body of about 140 short forms | Keep | The replay buffer now lives in the staging window (§6.1) |
| Elements per level of a quoted list or vector | 63 | Raise | Tied to the 255-record runtime quote stack; raise to 255 with a nesting check |
| Active `call/ec` escapes | 8 | Raise | 21 bytes a slot; 16 slots cost 168 bytes |
| Open file ports | 1 input and 1 output | Raise | One FCB and one 128-byte record buffer a port |
| String length | 255 | Keep | One length byte; a Language limit, like Basie's 253 |
| Global names | 256 | Keep for now | One-byte slot operands in generated code; a Rework if programs grow past it |

## 3. Language limits

| Limit | Value | Reason | When exceeded |
| --- | --- | --- | --- |
| Exact integers | −8,388,608 to 8,388,607 | 24-bit cell payload ([value contract](value-contract.md)) | A literal out of range is a `COMPILE ERROR`; arithmetic overflow, including `(- min)`, `(abs min)`, `(quotient min -1)` and `gcd`, `lcm` or `expt` overflow, is a `RUNTIME ERROR` |
| Inexact numbers | float24: 17 significant bits, exponent bias 63, largest about 1.8 × 10^19, smallest normal 2^−62, subnormals to 2^−78 | [float24](float24.md) | Overflow gives ±inf and underflow ±0, at compile time and run time, as IEEE arithmetic does. Converting inf, NaN or a value of magnitude 2^23 or more to an exact integer is a `RUNTIME ERROR` |
| `/` | Always returns an inexact number | float24 has no rationals | `(/ 6 3)` is `2.0`; integers above 2^17 lose precision |
| Characters | 8 bits | One-byte characters | `integer->char` outside 0–255 is a `RUNTIME ERROR` |
| String length | 255 bytes | One length byte in the string record | A longer literal is `CAP`; a longer runtime result is a `RUNTIME ERROR` |
| Symbol and identifier length | 31 bytes | Lexer token check and the runtime reader | `CAP` (pinned by `LONGSYM`). Raise to 63 cheaply in the compiler, but `read` and `string->symbol` must change with it |
| Fixed formals | 32, plus an optional rest formal; also the variables of a named `let` or `do` | A call passes at most 32 values. Formals take consecutive slots, so a descriptor records only the first | `CAP` (pinned by `FORMAL33`) |
| Arguments in one call | 32 (`ARG_MAX`) | The runtime's 128-byte argument packet | `CAP` (pinned by `ARGS33`); the runtime also refuses a larger packet |
| `apply` | The leading arguments and the list's elements together at most 32 | The same packet | `RUNTIME ERROR` (pinned by `APPCOUNT`) |
| `vector`, `string`, `list` | At most 32 arguments | The packet | `CAP` at compile time |
| Vector length | 255 elements | One count byte; a vector above 63 elements owns a run of two to four pages | `RUNTIME ERROR` (pinned by `VLONGERR`, `LONGVEC`, `RDVEC256`) |
| `call/ec` | One-shot escapes only, 8 active at once | `EC_TABLE`, 8 × 21 bytes | `RUNTIME ERROR` |
| Character names | The R7RS names (`#\alarm`, `#\backspace`, `#\delete`, `#\escape`, `#\newline`, `#\null`, `#\return`, `#\space`, `#\tab`), `#\xHH`, or one printable byte | Lexer (`LX_NAMES`); runtime `CH_NAMES` for `write` and `read` | `COMPILE ERROR` for another name; `write` prints these names and `read` reads them |
| `#` syntax | `#(`, `#t`, `#true`, `#f`, `#false`, `#\`, and the radix prefixes `#b`, `#o`, `#d`, `#x` | Lexer | `COMPILE ERROR`. No exactness prefixes, `#|…|#` or `#;` |
| String escapes | `\"` `\\` `\n` `\r` `\t` `\xHH;` | Lexer | A string may span lines: a raw line feed or tab is kept and a carriage return dropped. Other raw control bytes are a `COMPILE ERROR` |
| Number syntax | Decimal integers and decimals with exponents, `+inf.0`, `-inf.0`, `+nan.0`; exact integers in radix 2, 8 and 16 after `#b`, `#o` or `#x` (pinned by `RADIX`, `HEXWIDE`) | Lexer and `DEC_READ` | No rationals or exactness prefixes |
| Quasiquote | Not supported | Design | `` ` `` and `,` are a `COMPILE ERROR` |
| `include` | Only leading `(include "…")` forms | The include pre-pass reads only the head of a file | A later `include` is a `COMPILE ERROR` (pinned by `LATEINC`) |

`string->number` reads text in radix 10 with the compiler's own decimal
parser, so it gives exactly the value the same literal would: an exact
integer, or a float correctly rounded (`S2NDEC`). Radix 2, 8 and 16, given
as the second argument or as a `#b`, `#o` or `#x` prefix, read exact
integers through the same parser.  Literals, `read` and `string->number`
therefore accept exactly the same number syntax. Text that is not a number gives `#f`; an exact integer out of
range is a `RUNTIME ERROR`, as it is a `COMPILE ERROR` for a literal.
`read` uses the same parser for numbers.
`string-set!` refuses a literal string (`SSETLIT`). `list-copy` needs a proper
list. `number->string` has no radix argument yet.

## 4. Format and CP/M limits

| Limit | Value | Reason | When exceeded |
| --- | --- | --- | --- |
| Compiled image | Must leave a metadata page, a heap page, a page between heap and stack, and 1 KB of stack below `RT_LOEND`, `B800H` (§5.2) | The runtime's memory map | `CAP` |
| Source file | 65,535 bytes, lines and columns | 16-bit positions; the source is streamed, not buffered | `COMPILE ERROR`; split the program with includes |
| Lexer token | 64 bytes; string literals 255 | `LX_BUF` | `CAP` |
| Decimal literal | 64 significant digits held exactly, correctly rounded; the exponent saturates at 1000 | `decimal/parse.asm` | Harmless: any such exponent overflows or underflows anyway |
| Reader nesting | 64 open lists, vectors and quote prefixes | `RD_STACK` | `CAP` |
| Compiler TPA | BDOS entry at `E020H` or above | The compiler's stack top | `INSUFFICIENT MEMORY` |
| Runtime TPA | BDOS entry at `E400H` or above | The runtime's stack top | `NOT ENOUGH MEMORY`. A machine with its BDOS between these two addresses can compile but not run |
| Source name | The command-tail FCB, used as given; no default `.SK8` type | `CMD_NAME` | A wildcard, or a type the compiler writes (`COM`, `NOB`, `ASO`, `CBS`, `NBS`, `SPL`, `NPR`, `CPR`, `APR`), is `SOURCE ERROR` before any file is touched |
| Include files | Depth 8, 32 files in one program, 8.3 names of `A-Z 0-9 - _`, read from the drive of the root source | `INC_MAX`, `SRC_MAX` | `INCLUDE ERROR`, with no position (§8) |
| Runtime file names | Current drive, 8.3, 1–12 bytes, CP/M's reserved characters refused | `file-ports.asm` | `RUNTIME ERROR` |
| File size | CP/M's 8 MB | 128-byte sequential records; ^Z ends text | — |

## 5. Capacity limits

### 5.1 Compiler

The compiler works in fixed tables between `W_STAGE` (`5800H`) and its stack
(`D820H`–`E020H`). The memory map is in §6.1.

| Capacity | Value | Table | When exceeded | Verdict |
| --- | --- | --- | --- | --- |
| Global names | 256 | `W_GKEYS`, `W_GSLOTS`, `W_GPRIM` (4 bytes a name) and a 1 KB runtime area | `CAP` | Keep. Generated code names a global with a one-byte operand. Built-in procedures that are not redefined take no slot |
| Procedures (`lambda`, procedure `define`, named `let`, `do`) | 255 | `W_PDESC`, 2 bytes each; a one-byte index | `CAP` (pinned by `PROC256`) | Keep; more needs a wider index |
| Procedures open at once | 26 | `W_PRECS`, 37 bytes each | `CAP` (pinned by `OPEN27`) | Keep |
| Local bindings in scope | 128 slots, counting every enclosing procedure's locals | `W_LKEYS`, `W_BKEYS`, `W_LOWNER` and others; the runtime's 16-byte slot masks | `CAP` | Keep the count. The cost is in the runtime (§5.2) |
| Address fixups | 640 | `W_FIXUPS`, 4 bytes each | `CAP` | Keep. Each use of a string or symbol literal, each quoted constant and each reference to a top-level `let` local takes one |
| Distinct symbols | 640 names; 6,144 bytes of spelling | `W_SYMTAB`, `W_SYMBUF`, in the staging window | `CAP` (pinned by `SYM650`; `SYMS600` compiles) | Keep. Keywords and every identifier count; `STDLIB.SK8` alone uses about 61 |
| Distinct string literals | 128; 2,048 bytes | `W_STRTAB`, `W_STRBUF`, in the staging window | `CAP` (pinned by `STR129`) | Keep |
| Literals copied to the output (symbols and strings in quoted data) | 128; 2,047 bytes | `W_LITREC`, `W_LITBUF`, `W_LITOUT` | `CAP` (pinned by `LIT129`; `TABLES` uses 128) | Keep |
| Elements in one level of a quoted list or vector | 63 | `quoted.asm` | `CAP` | Raise, with a check on the runtime quote stack (255 records shared by every nesting level) |
| Quoted constants in a program | 255 | One-byte cache index | `CAP` | Rework if met |
| Replay events | 6,016 bytes, 1,504 events | `REC_BUF` (`W_RECBUF` to `W_RECEND`), in the staging window | `CAP` | Keep. Bounds `letrec` binding lists, leading internal definitions with the first body form, and whole `do` forms with their rewrite. Measured: a `do` body of 140 short forms compiles and 150 does not; internal definitions and `letrec` lambdas of 250 forms compile |
| Nested replay scopes | 16 | `W_REPLAY` | `CAP` | Keep |
| `do` variables | 32 | The named let it becomes; step ranges in `W_DOSTEP` | `CAP` | Keep |
| Pending `and`/`or` operands, `case` datums and quoted-list ends | 128 | `W_BRANCH` | `CAP` | Keep |
| Nested `if`, `when`, `unless` | 64 | `W_IFALSE`, `W_IFEND` | `CAP` | Keep |
| `cond`/`case` nesting | 32 | `W_CBASES`, `W_CTOPS` | `CAP` | Raise (+64 bytes) |
| `cond`/`case` clauses pending | 128 across all open forms | `W_CONDS` | `CAP` (`TABLES` has 120) | Keep |
| Tail calls pending in one body expression | 128 | `W_TCALLS`, `W_TAILOP` | `CAP` | Keep. A body's earlier expressions no longer hold records, so a body may have any number of calls |
| Compiler stack | 2,048 bytes | `D820H`–`E020H` | `CAP` when a form starts with less than 256 bytes left | Keep |
| Includes | Depth 8, 32 files | In the compiler image | `INCLUDE ERROR` | Keep; each file costs image bytes |

### 5.2 Runtime

The runtime's memory map is fixed at assembly time (§6.2). Nothing in it
grows with a larger TPA.

| Capacity | Value | Where | When exceeded | Verdict |
| --- | --- | --- | --- | --- |
| Runnable image | Ends at `B100H` at most: 45,056 bytes of `.COM` | `RT_LOEND`, `page/init.asm`; the compiler applies the same rule | `CAP` at compile time (pinned by `test:cpm:full-image`, which runs a 45,056-byte image and refuses one byte more) | Keep. Such a program has one heap page and 1 KB of stack |
| Runtime size | Core 18,410 bytes, with standard procedures 20,849, with numeric procedures 22,479, full 26,145 | `RT_CORE`, `RT_STD`, `RT_NUMS`, `RT_SIZE` | — | Each 256 bytes of runtime or program costs one heap page (32 pairs) |
| Live pairs | 3,232 with the core runtime and a small program that recurses only shallowly | 8 bytes a pair, 32 a page; pages from the image end up towards the stack | `RUNTIME ERROR` after a collection | Raise by sizing the maps to the heap. Pinned by `PAIR3232` and `PAIR3233`. The heap stays 4 KB below the stack's start until a collection has run; after one, a page may come up to a page below the stack pointer |
| Native stack | From `B800H` down to a page above the highest heap page | `RT_STK`, `STK_FLR`; `PAGE_NEW` keeps each new page a page below the stack pointer | `RUNTIME ERROR` | Keep |
| Non-tail recursion | About 15 bytes a level for `(+ 1 (f (- n 1)))`: 1,500 levels measured in a small program | A frame is 6 bytes (the caller's return, environment and descriptor) plus 4 for each slot, and each pending operand 6; a body ends with `JP FRM_RET`, which finds the frame's boundary from its map | `RUNTIME ERROR` | Keep. Pinned by `DEEPOK`, `DEEPREC` and `FRAMES` |
| Pending operand roots | No fixed limit | `ARG_PUSH` links each pending operand's record through the native stack (`ROOT_TOP`); the collector follows the links | — | Keep |
| Operator side stack | 255 records | `CF00H`–`D300H` | `RUNTIME ERROR` | Keep; bounds nesting through computed-operator calls, `case` and `map` |
| Quote, `list`, rest and `apply` stack | 255 records shared across nesting | `D700H`–`DB00H` | `RUNTIME ERROR` | Keep, but the compiler should check deep quoted data against it |
| GC mark worklist | 512 entries | `DF00H`–`E300H` | Never fails: collection rescans and slows down | Keep |
| Runtime symbols (`read`, `string->symbol`) | 512 bytes, never freed | `DD00H`–`DF00H` | `RUNTIME ERROR` after about 60 new seven-character symbols | Raise |
| `read`: list length | No fixed limit | Each open list or vector keeps one reader slot, its elements so far consed in reverse; the close relinks them in place (`datum-lists.asm`) | — | Done. Pinned by `RDLIST` (300 elements) |
| `read`: nesting and tokens | 32 open lists; symbols 31, numbers 64, strings 255, vectors 255 | `datum-*.asm` | `RUNTIME ERROR` | Keep. Numbers are read as the compiler reads them. `read` does not accept `'x` or bytes of `80H` and above |
| `write` and `display` nesting | Guarded | `WR_GUARD` | `RUNTIME ERROR` (pinned by `DEEPNEST`) | Keep |

## 6. Memory maps

### 6.1 Compiler

| Range | Bytes | Contents |
| --- | ---: | --- |
| `0100H`–`55C5H` | 21,701 | Code and module workspaces |
| `55C5H`–`5800H` | 571 | Headroom; the budget test requires 256 |
| `5800H`–`9980H` | 16,768 | `W_STAGE`: the window in which publication assembles the image. While the source is compiled it holds the sink's 128-byte image run, then the replay events (`5880H`), the symbol table and spellings (`7000H`) and the string table and bytes (`8F80H`), none of which publication reads |
| `9980H`–`9F80H` | 1,536 | Globals, locals and pending bindings |
| `9F80H`–`A980H` | 2,560 | Fixups |
| `A980H`–`B480H` | 2,816 | Literal records, spellings and output addresses |
| `B480H`–`BA87H` | 1,543 | Procedure descriptors and open procedure records |
| `C000H`–`C100H` | 256 | Tail-call candidates |
| `C400H`–`C700H` | 768 | Per-slot tables |
| `C700H`–`CE00H` | 1,792 | Lambda frames, primitive kinds, branch, `if`, tail flags, `cond` stacks, `do` steps |
| `CE00H`–`CF00H` | 256 | Replay scopes |
| `D820H`–`E020H` | 2,048 | Stack, guarded by `CMD_FORM` |

Free: `BA87H`–`C000H`, `C100H`–`C400H` and `CF00H`–`D820H`, about 3.8 KB in
all. The compiler image has 571 bytes of headroom, so a Raise must find its
memory in the workspace, not in code.

### 6.2 Runtime

| Range | Contents |
| --- | --- |
| `0100H` | Runtime (by tier), the 1 KB global area, generated code, descriptors, quoted data, literals |
| Image end, rounded to a page (at least `3000H`), up to `B800H` | Shared: heap pages grow up from the image (the first holds page metadata) and the native stack grows down from `B800H` |
| `B800H`–`CF00H` | Closure map, GC marks and binding map |
| `CF00H`–`DF00H` | Operator side stack, page tables, argument packet, quote stack, datum reader, runtime symbols |
| `DF00H`–`E400H` | GC worklist and a spare page |

The heap and the stack meet wherever the program needs.  The heap grows
only to `RT_SOFT` (`A800H`), 4 KB below the stack's start, until a collection has run;
the allocation retried after a collection may take a page past it, up to a
page below the stack pointer.  So garbage is collected before the heap takes
memory the stack may want, and a program that keeps more live data than the
soft line allows still gets it.  Every frame and nested runtime call checks
the stack against `STK_FLR`, a page above the highest heap page.  A page, once
used, is rarely returned, so stack space the heap has taken stays taken.  A program trades code for heap and stack byte
for byte up to the 45,056-byte limit.  Sizing the collector maps to the
actual heap rather than to all of `3000H`–`C000H` (they take 5.8 KB, about 5
KB more than a small heap needs) would give still more room, as would
placing the bands from the BDOS entry down on a larger TPA.

## 7. Silent failures

The rule forbids these.

Fixed:

1. **Images the runtime would refuse** are now `CAP` at compile time, instead
   of compiling and then stopping with `RUNTIME ERROR` at start-up.
2. **`string-ref`** now checks byte 2 of its index: `(string-ref "abc" 65536)`
   is a `RUNTIME ERROR` (`STRREFW`).
3. **`equal?`, `member` and `assoc`** check the stack at each level of
   nesting, as the writer does, so a deep structure is a `RUNTIME ERROR`
   (`DEEPEQ`) instead of running the stack into the runtime's tables.
4. **The compiler stack** is checked at the start of every form.
5. **The argument packet** is bounded at run time in `FRM_PACK` and
   `PKT_PACK`, not only by the compiler.
6. **A wildcard source name**, or a source whose type is one of the
   compiler's own output types, is refused before publication deletes or
   renames anything.
7. **Circular lists:** `list?` is false for one, and `length`, `memq`,
   `member`, `assq` and `assoc` stop with a `RUNTIME ERROR` after more cells
   than the heap can hold (`CIRCLE`, `CIRCLEN`, `CIRCMEM`).

8. **`display` and `write`** stop a list circular in its cdrs with a
   `RUNTIME ERROR` after as many elements (`CIRCDISP`).

Remaining:

9. **`call/ec` token generations wrap after 512 reopenings,** so a stale
   escape can be accepted again; a stale file-port token reaches the file
   opened after it.

Losses that are intended, and are not failures under the rule: float
overflow and underflow, precision lost in `/` and `exact->inexact`, the
decimal exponent saturating, and runtime symbols that are never freed.

## 8. Diagnostics

- A full compiler table, an over-long token and a fifth formal report `CAP`.
  An out-of-range integer literal and malformed source report `COMPILE
  ERROR`.
- Every runtime failure, whether capacity or type, prints `RUNTIME ERROR`.
- An include failure prints `INCLUDE ERROR` with no file, position or reason.

## 9. Tests

Limits pinned by a test: 256 globals (`GLOB256`), 65 nested `if`s
(`IF65`), a 64-element quoted list (`REVQCAP`), 3,232 live pairs, recursion
(`DEEPOK`, `DEEPREC`), `apply` of 33 values (`APPCOUNT`), `(make-vector 256)`
(`VLONGERR`), stale escapes (`ECSTALE`, `ECREUSE`), 11,000 top-level forms
(`TOOLONG`), deep `write` (`DEEPNEST`), 255- and 256-byte strings, and an
out-of-range integer literal.

Also pinned: the runnable image size (`test:cpm:full-image`), a 33rd
formal (`FORMAL33`) and argument (`ARGS33`), 32 of each (`ARGS32`), frames
of different sizes (`FRAMES`), a 32-byte identifier (`LONGSYM`), a 129th string
(`STR129`), a 641st symbol (`SYM650`), a 129th quoted literal (`LIT129`), a
256th procedure (`PROC256`), a 27th nested lambda (`OPEN27`), the raised
tables in use (`TABLES`, `SYMS600`), a late `include` (`LATEINC`), `string-ref` with a large index
(`STRREFW`), `equal?` depth (`DEEPEQ`, `EQDEPTH`) and refused source names.

Not pinned: 640 fixups, the replay buffer, 128 tail calls, `cond` clauses
and branches, 255 quoted constants, 8 escapes, the file
ports, the runtime symbol area and the `read` limits. Each limit that is kept
should get a test at its boundary, and each that is raised a test at the new
one.

## 10. Plan

In order of value to a programmer:

1. **Close the silent failures** (§7) and make capacity overflows say `CAP`.
   Done, except for circular lists and token generations.
2. **Per-procedure frame size.** Done.
3. **32 formals and 32-argument calls,** for procedures, named `let`, `do`,
   `apply`, `list`, `vector` and `string`. Done.
4. **Compile-only tables in the staging window.** Done: the replay buffer,
   symbols, strings, literals, fixups, procedures and the branch, `if`,
   `cond` and tail stacks are all at least twice their former size.
5. **One region for heap and stack.** Done: frames are 6 bytes, pending
   operands are linked through the stack instead of a 255-entry table, and the
   heap and stack share the memory below `B800H`, so recursion is bounded by
   free memory and programs can be 45,056 bytes. Still to do: sizing the maps
   to the heap, and using a larger TPA.
6. **Missing standard procedures.** Done: `list->vector`, `vector->list`,
   `string->list`, `list->string`, `make-string`, `string-set!`,
   `vector-fill!`, `list-copy`, `string->number` (integers) and
   `string-append` of any number of strings, vectors of 255 elements, and
   the R7RS character names in `write` and `read`. Still to do:
   more file ports and escapes.  The radix prefixes `#b`, `#o`, `#d` and
   `#x` are done.  Decimal `string->number`, `read` of floats, and `read` of lists of any
   length and vectors of 255 are done.  Character names, `#true` and
   `#false`, and strings that span lines are done.
