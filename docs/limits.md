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

Skate does not yet meet the rule. Section 7 lists the places where it fails
silently, and section 8 the places where its diagnostics mislead.

## 2. Summary: the limits that matter

These are the limits a programmer is likely to meet first, in the order in
which they should be dealt with.

| Limit | Today | Verdict | Proposal |
| --- | --- | --- | --- |
| Runnable program size | about 36 KB of `.COM`; the compiler accepts 65,280 B | Rework | The compiler must refuse an image the runtime will refuse (now). Then compute the runtime memory map from the TPA instead of fixed bands (§6.2) |
| Non-tail recursion depth | about 210 levels, and far fewer in a program with one large procedure | Rework | Size each frame by its own procedure's slots, not the program's largest (§5.2). Then give the stack the memory a computed map frees |
| Fixed formals per procedure | 4 | Rework | The descriptor has four formal fields. Named `let` and `do` inherit the limit, so a five-variable loop is a `COMPILE ERROR`. Make the formal list variable length; target 32 |
| Arguments per call, `apply`, `list`, `vector` | 8 | Raise | The argument packet is 32 bytes. 32 arguments cost 96 more runtime bytes and one compiler constant |
| Size of a `do`, a `letrec` binding list, or leading internal definitions | 200 reader events in all; a `do` body of about 10 short forms | Rework / Raise | They are buffered in an 800-byte replay area. Move it into the idle staging window (§6.1) for 4 KB or more, or stream these forms |
| Distinct quoted symbols and strings copied to output | 64, and 1,023 bytes | Raise | Double in the staging window |
| String literals | 64 distinct, 1,024 bytes | Raise | Double; text-heavy programs hit this first |
| Elements per level of a quoted list or vector | 63 | Raise | Tied to the 255-record runtime quote stack; raise to 255 with a nesting check |
| Vector length | 64 | Rework | `make-vector` uses one closure-slab class; longer vectors need page runs |
| Active `call/ec` escapes | 8 | Raise | 21 bytes a slot; 16 slots cost 168 bytes |
| Open file ports | 1 input and 1 output | Raise | One FCB and one 128-byte record buffer a port |
| `cond`/`case` clauses, `and`/`or` operands, tail calls pending in one expression | 64 each | Raise | The tables are already twice the size used; doubling is free |
| Procedures per program | 128 | Raise | 255 costs 384 workspace bytes; beyond needs a wider index |
| String length | 255 | Keep | One length byte; a Language limit, like Basie's 253 |
| Global names | 256 | Keep for now | One-byte slot operands in generated code; a Rework if programs grow past it |

## 3. Language limits

| Limit | Value | Reason | When exceeded |
| --- | --- | --- | --- |
| Exact integers | −8,388,608 to 8,388,607 | 24-bit cell payload ([value contract](value-contract.md)) | A literal out of range is a `COMPILE ERROR`; arithmetic overflow, including `(- min)`, `(abs min)`, `(quotient min -1)` and `gcd`, `lcm` or `expt` overflow, is a `RUNTIME ERROR` |
| Inexact numbers | float24: 17 significant bits, exponent bias 63, largest about 1.8 × 10^19, smallest normal 2^−62, subnormals to 2^−78 | [float24](float24.md) | Overflow gives ±inf and underflow ±0, at compile time and run time, as IEEE arithmetic does. Converting inf, NaN or a value of magnitude 2^23 or more to an exact integer is a `RUNTIME ERROR` |
| `/` | Always returns an inexact number | float24 has no rationals | `(/ 6 3)` is `2.0`; integers above 2^17 lose precision |
| Characters | 8 bits | One-byte characters | `integer->char` outside 0–255 is a `RUNTIME ERROR` |
| String length | 255 bytes | One length byte in the string record | A longer literal is a `COMPILE ERROR`; a longer runtime result is a `RUNTIME ERROR` |
| Symbol and identifier length | 31 bytes | Lexer token check and the runtime reader | `COMPILE ERROR` (measured: 31 compiles, 32 fails). Raise to 63 cheaply in the compiler, but `read` and `string->symbol` must change with it |
| Fixed formals | 4, plus an optional rest formal | Four formal fields in the 12-byte procedure descriptor, in both compiler and runtime | `COMPILE ERROR` (measured). Also limits named `let` and `do` to 4 variables. Rework (§2) |
| Arguments in one call | 8 | The runtime's 32-byte argument packet | `CAP`. Raise (§2) |
| `apply` | The leading arguments and the list's elements together at most 8 | The same packet | `RUNTIME ERROR` |
| `vector`, `string`, `list` | At most 8 arguments | The packet | `CAP` at compile time |
| `string-append` | Exactly 2 arguments | Implementation | `RUNTIME ERROR`; should accept any number |
| Vector length | 64 elements | The largest closure-slab class | `RUNTIME ERROR`. Rework |
| `call/ec` | One-shot escapes only, 8 active at once | `EC_TABLE`, 8 × 21 bytes | `RUNTIME ERROR` |
| Character names | `#\space`, `#\newline`, `#\xHH`, or one printable byte | Lexer | `COMPILE ERROR`. `#\tab`, `#\return`, `#\null` and the other R7RS names are missing |
| `#` syntax | `#(`, `#t`, `#f`, `#\` | Lexer | `COMPILE ERROR`. No `#true`/`#false`, `#x` and other radix or exactness prefixes, `#|…|#` or `#;` |
| String escapes | `\"` `\\` `\n` `\r` `\t` `\xHH;` | Lexer | A raw tab or line break inside a string is a `COMPILE ERROR`, so a string cannot span lines |
| Number syntax | Decimal integers and decimals with exponents, `+inf.0`, `-inf.0`, `+nan.0` | Lexer | No rationals, radix prefixes or exactness prefixes |
| Quasiquote | Not supported | Design | `` ` `` and `,` are a `COMPILE ERROR` |
| `include` | Only leading `(include "…")` forms | The include pre-pass reads only the head of a file | A later `include` is compiled as a call to an unbound name and fails at run time. It should be a `COMPILE ERROR` |

Procedures still missing from the standard set: `string->number`,
`make-string`, `string-set!`, `string->list`, `list->string`,
`list->vector`, `vector->list`, `vector-fill!`, `list-copy`, and a radix for
`number->string`. Some are in `libraries/STDLIB.SK8`.

## 4. Format and CP/M limits

| Limit | Value | Reason | When exceeded |
| --- | --- | --- | --- |
| Compiled image | `0100H` to `FFFFH` (65,280 bytes) | 16-bit addresses | `CAP`. But see the runnable size, §5.2: the compiler accepts images the runtime refuses |
| Source file | 65,535 bytes, lines and columns | 16-bit positions; the source is streamed, not buffered | `COMPILE ERROR`; split the program with includes |
| Lexer token | 64 bytes; string literals 255 | `LX_BUF` | `COMPILE ERROR` |
| Decimal literal | 64 significant digits held exactly, correctly rounded; the exponent saturates at 1000 | `decimal/parse.asm` | Harmless: any such exponent overflows or underflows anyway |
| Reader nesting | 64 open lists, vectors and quote prefixes | `RD_STACK` | `COMPILE ERROR` (measured) |
| Compiler TPA | BDOS entry at `E020H` or above | The compiler's stack top | `INSUFFICIENT MEMORY` |
| Runtime TPA | BDOS entry at `E400H` or above | The runtime's stack top | `NOT ENOUGH MEMORY`. A machine with its BDOS between these two addresses can compile but not run |
| Source name | The command-tail FCB, used as given | `source/open.asm` | No default `.SK8` type. A wildcard is not refused (§7) |
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
| Procedures (`lambda`, procedure `define`, named `let`, `do`) | 128 | `W_PDESC`, `W_PARITY`, 3 bytes each | `CAP` | Raise to 255 (+384 bytes); beyond that the procedure index must widen |
| Procedures open at once | 13 | `W_PRECS`, 44 bytes each | `CAP` | Raise (+572 bytes for 26) |
| Local bindings in scope | 128 slots, counting every enclosing procedure's locals | `W_LKEYS`, `W_BKEYS`, `W_LOWNER` and others; the runtime's 16-byte slot masks | `CAP` | Keep the count. The cost is in the runtime (§5.2) |
| Address fixups | 320 | `W_FIXUPS`, 4 bytes each | `CAP` | Raise (+1,280 bytes for 640). Each use of a string or symbol literal, each quoted constant and each reference to a top-level `let` local takes one |
| Distinct symbols | 320 names; 4,800 bytes of spelling | `W_SYMTAB`, `W_SYMBUF` | `COMPILE ERROR` | Raise. Keywords and every identifier count; `STDLIB.SK8` alone uses about 61 |
| Distinct string literals | 64; 1,024 bytes | `W_STRTAB`, `W_STRBUF` | `COMPILE ERROR` (measured) | Raise. The first limit a text-heavy program meets |
| Literals copied to the output (symbols and strings in quoted data) | 64; 1,023 bytes | `W_LITREC`, `W_LITBUF`, `W_LITOUT` | `CAP` (measured: two quoted lists of 40 symbols) | Raise |
| Elements in one level of a quoted list or vector | 63 | `quoted.asm` | `CAP` | Raise, with a check on the runtime quote stack (255 records shared by every nesting level) |
| Quoted constants in a program | 255 | One-byte cache index | `CAP` | Rework if met |
| Replay events | 800 bytes, 200 events | `REC_BUF` to `W_REPEND` | `CAP` | Rework or Raise. Bounds `letrec` binding lists, leading internal definitions with the first body form, and whole `do` forms (about 85 events once the rewrite is appended). Measured: a `do` body of 8 `(write (+ i 0))` compiles and 12 does not; an internal `define` of 30 short forms compiles and 45 does not |
| Nested replay scopes | 16 | `W_REPLAY` | `CAP` | Keep |
| `do` variables | 8 in the `do` rewrite; 4 in practice | The named let it becomes | 5 to 8 give `COMPILE ERROR`, 9 `CAP` | Follows the formals Rework |
| Pending `and`/`or` operands, `case` datums and quoted-list ends | 64 | `W_BRANCH` (half used) | `CAP` | Raise, free |
| Nested `if`, `when`, `unless` | 32 | `W_IFALSE`, `W_IFEND` (half used) | `CAP` | Raise, free, once the stack is guarded |
| `cond`/`case` nesting | 32 | `W_CBASES`, `W_CTOPS` | `CAP` | Raise (+64 bytes) |
| `cond`/`case` clauses pending | 64 across all open forms | `W_CONDS` (half used) | `CAP` (measured: 65 clauses) | Raise, free |
| Tail calls pending in one body expression | 64 | `W_TCALLS`, `W_TAILOP` | `CAP` (measured: a `cond` of 65 clauses ending in calls) | Raise (+192 bytes, needs a new place) |
| Compiler stack | 2,048 bytes | `D820H`–`E020H` | **Not checked** (§7) | Rework: add a depth guard |
| Includes | Depth 8, 32 files | In the compiler image | `INCLUDE ERROR` | Keep; each file costs image bytes |

### 5.2 Runtime

The runtime's memory map is fixed at assembly time (§6.2). Nothing in it
grows with a larger TPA.

| Capacity | Value | Where | When exceeded | Verdict |
| --- | --- | --- | --- | --- |
| Runnable image | Ends below `9000H`, less one or two page-metadata pages: about 36 KB of `.COM` with the full runtime | `RT_LOEND`, `page/init.asm` | `RUNTIME ERROR` before the first form; the compiler has already printed `COMPILED` (measured: a 49,536-byte program) | Rework. The compiler must check this; `test:cpm:full-image` compiles a 65,280-byte image but never runs it |
| Runtime size | Core 18,410 bytes, with standard procedures 20,849, with numeric procedures 22,479, full 26,145 | `RT_CORE`, `RT_STD`, `RT_NUMS`, `RT_SIZE` | — | Each 256 bytes of runtime or program costs one heap page (32 pairs) |
| Live pairs | 2,720 with the core runtime and a small program | 8 bytes a pair; low pages up to `9000H` and 21 high pages | `RUNTIME ERROR` after a collection | Rework with the computed map. Pinned by `PAIR2720` and `PAIR2721` |
| Native stack | 3,840 bytes, `D500H`–`E400H` | `RT_GUARD`, `RT_TOP` | `RUNTIME ERROR` | Rework |
| Non-tail recursion | About 210 levels of `(+ 1 (f (- n 1)))` (measured: 200 passes, 215 fails) | Each frame holds a pointer array sized by `ST_LMAX`, the largest slot count anywhere in the program | `RUNTIME ERROR` | Rework. Adding one unrelated procedure with 30 `let` locals cut the same recursion to under 40 levels (measured). Closures are sized the same way, 2 × LMAX + 2 bytes. Recording each procedure's own extent in its descriptor fixes both |
| Pending operand roots | 255 | `ROOT_TAB`, 1,020 bytes | `RUNTIME ERROR` | Keep |
| Operator side stack | 255 records | `C000H`–`C400H` | `RUNTIME ERROR` | Keep; bounds nesting through computed-operator calls, `case` and `map` |
| Quote, `list`, rest and `apply` stack | 255 records shared across nesting | `C800H`–`CC00H` | `RUNTIME ERROR` | Keep, but the compiler should check deep quoted data against it |
| GC mark worklist | 512 entries | `D000H`–`D400H` | Never fails: collection rescans and slows down | Keep |
| Runtime symbols (`read`, `string->symbol`) | 512 bytes, never freed | `CE00H`–`D000H` | `RUNTIME ERROR` after about 60 new seven-character symbols | Raise |
| `read`: pending list elements | 64 across all open lists | `datum-lists.asm` | `RUNTIME ERROR`; `read` cannot read a list longer than 64 | Rework: fold as it reads |
| `read`: nesting and tokens | 32 open lists; symbols 31, integers 64, strings 255, vectors 64 | `datum-*.asm` | `RUNTIME ERROR` | Keep. `read` does not accept floats, `'x` or bytes of `80H` and above |
| `write` and `display` nesting | Guarded | `WR_GUARD` | `RUNTIME ERROR` (pinned by `DEEPNEST`) | Keep |

## 6. Memory maps

### 6.1 Compiler

| Range | Bytes | Contents |
| --- | ---: | --- |
| `0100H`–`55A8H` | 21,672 | Code and module workspaces |
| `55A8H`–`5800H` | 600 | Headroom; the budget test requires 256 |
| `5800H`–`9980H` | 16,768 | `W_STAGE`: the window in which publication assembles the image. While the source is compiled only its first 128 bytes, the sink's image run, appear to be used |
| `9980H`–`9F80H` | 1,536 | Globals, locals and pending bindings |
| `9F80H`–`A480H` | 1,280 | Fixups |
| `A480H`–`BB00H` | 5,760 | Symbol table and spellings |
| `BB00H`–`C000H` | 1,280 | String table and bytes |
| `C000H`–`C700H` | 1,792 | Procedure descriptors, open procedures, per-slot tables |
| `C700H`–`CE00H` | 1,792 | Lambda frames, primitive kinds, branch, `if`, tail and `cond` stacks; `CD40H`–`CE00H` (192 bytes) free |
| `CE00H`–`D500H` | 1,792 | Replay scopes and the literal tables |
| `D500H`–`D820H` | 800 | Replay events |
| `D820H`–`E020H` | 2,048 | Stack, unguarded |

**Where room can come from.** The compiler image has 600 bytes of headroom,
so a Raise must find its memory in the workspace, not in code.

1. The staging window is about 16 KB that compilation barely touches. Tables
   used only while compiling can live there: replay events and scopes,
   locals and bindings, and the branch, `if`, `cond` and tail stacks.
   Tables that publication reads cannot: fixups, procedure descriptors,
   primitive kinds and the literal tables. Whether the interner can move
   depends on whether publication still reads it; that needs checking.
2. The window can also shrink: each 8 KB less costs one more pass over the
   image during publication, which is disk time only.
3. The branch, `if`, `cond` and tail tables already have twice the room they
   use.

### 6.2 Runtime

| Range | Contents |
| --- | --- |
| `0100H` | Runtime (by tier), the 1 KB global area, generated code, descriptors, quoted data, literals |
| Image end, rounded to a page (at least `3000H`) to `9000H` | Low heap pages; the first one or two hold page metadata |
| `9000H`–`AB00H` | Closure map, GC marks, `ROOT_TAB`, binding map |
| `AB00H`–`C000H` | High heap, 21 pages |
| `C000H`–`D000H` | Operator side stack, page tables, quote stack, datum reader, runtime symbols |
| `D000H`–`D500H` | GC worklist and a spare band |
| `D500H`–`E400H` | Native stack |

Every band is placed at assembly time and nothing scales with the TPA, so
raising one runtime limit takes memory from another. Computing the layout
at start-up, from the image end and the BDOS entry, is the structural fix
for the program size, the stack and the heap together.

## 7. Silent failures

The rule forbids these. Each needs fixing.

1. **The compiler accepts images the runtime refuses.** An image ending at or
   above about `9000H` compiles, then stops with `RUNTIME ERROR` at start-up.
   The fix is a check when publication ends.
2. **`string-ref` checks only the high byte of the index's low 16 bits, not
   byte 2.** `(string-ref "abc" 65536)` returns `#\a` (measured). The fix is
   the check `VEC_IDX` already makes.
3. **`equal?`, `member` and `assoc` recurse on the native stack without a
   guard** (`STD_DEEP`). A deep enough structure runs the stack down through
   the GC worklist and the runtime bands. The fix is the writer's guard.
4. **The compiler stack has no guard.** Overflow would corrupt the replay
   events and the literal tables.
5. **The argument packet is not bounds-checked at run time.** Only the
   compiler's `CAP` keeps a call within eight arguments.
6. **Circular lists:** `length`, `list?`, `memq`, `member`, `assq` and
   `assoc` with no match never return, and `display` of a list circular in
   its cdrs never ends.
7. **`call/ec` token generations wrap after 512 reopenings,** so a stale
   escape can be accepted again; a stale file-port token reaches the file
   opened after it.
8. **A wildcard source name** such as `SKATE *.SK8`, or a source whose type is
   one of the compiler's own output types, reaches BDOS delete and rename
   unchecked (read from `publication/stream.asm`, not run).

Losses that are intended, and are not failures under the rule: float
overflow and underflow, precision lost in `/` and `exact->inexact`, the
decimal exponent saturating, and runtime symbols that are never freed.

## 8. Diagnostics

- Most front-end capacity overflows print `COMPILE ERROR`, not `CAP`: symbols,
  string literals, token and identifier length, string length, reader depth,
  and a fifth formal. The reader's capacity codes (129–132) are not mapped
  to `M_CAP`.
- Every runtime failure, whether capacity or type, prints `RUNTIME ERROR`.
- An include failure prints `INCLUDE ERROR` with no file, position or reason.

The README describes overflows as `CAP`; it should match whatever the
diagnostics become.

## 9. Tests

Limits pinned by a test: 256 globals (`GLOB256`), 33 nested `if`s
(`IF33`), a 64-element quoted list (`REVQCAP`), 2,720 live pairs, recursion
(`DEEPOK`, `DEEPREC`), `apply` of 9 values (`APPCOUNT`), `(make-vector 65)`
(`VLONGERR`), stale escapes (`ECSTALE`, `ECREUSE`), 11,000 top-level forms
(`TOOLONG`), deep `write` (`DEEPNEST`), 255- and 256-byte strings, and an
out-of-range integer literal.

Not pinned: 129 procedures, 14 open procedures, 9 arguments, 5 formals, 320
fixups, 320 symbols, 65 strings or literals, the replay buffer, 64 tail
calls, `cond` clauses and branches, 255 quoted constants, the runnable image
size, 8 escapes, the file ports, the runtime symbol area, the `read` limits,
`string-ref` with a large index and `equal?` depth. Each limit that is kept
should get a test at its boundary, and each that is raised a test at the new
one.

## 10. Plan

In order of value to a programmer:

1. **Close the silent failures** (§7), starting with the compile-time image
   check, `string-ref` and the `equal?` guard. Make capacity overflows say
   `CAP`.
2. **Per-procedure frame size.** Small, and it lifts the recursion depth of
   every program with one large procedure.
3. **Variable-length formals** (target 32) and **32-argument calls**, which
   together remove the 4/8 limits from procedures, named `let`, `do`,
   `apply`, `list` and `vector`.
4. **Move compile-only tables into the staging window,** then raise the
   replay buffer, literals, strings, symbols and fixups to at least twice
   their size, and the half-used stacks to their full tables.
5. **A computed runtime memory map,** giving the stack and heap whatever the
   TPA holds and the program does not use.
6. Long vectors, more file ports and escapes, `read` of long lists and
   floats, and the missing standard procedures.
