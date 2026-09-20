# Skate 0.5.1

Skate is a small Scheme compiler for Z80 computers running CP/M. It compiles
source on the target machine into native Z80 executables. This release includes
three editable examples and a Triptych browser disk for trying them without
installing a local development environment.

## Supported language

The compiler supports signed 16-bit integers, booleans, strings, symbols,
quoted lists and dotted pairs. Programs can use top-level definitions, lexical
`let` and `let*`, `if`, `begin`, two-operand `and` and `or`, fixed-arity
procedures, closures, shared variable mutation and proper tail calls.

Predefined procedures are `+`, `-`, `*`, `zero?`, `cons`, `car`, `cdr`, `list`,
`pair?`, `null?`, `eq?`, `write`, `display` and `newline`. Arithmetic currently
requires two operands. Source packages can span ordered `.SK8` files named
in a `.SKM` manifest. Compilation produces a `.COM` executable and a `.NOB`
object file. Each program's final value is printed automatically.

## Try the examples

The Triptych library package provides a protected reference disk on A and a
personal writable copy on B. Select B before editing or compiling:

```text
B:
TYPE README.TXT
RECEIPT
ROUTE
ACCOUNT
EDIT RECEIPT.SK8
SKATE RECEIPT.SK8
RECEIPT
```

RECEIPT prints an itemised shop bill totalling 620 cents. ROUTE searches an
adventure map and prints the path `(1 2 5 6)`. ACCOUNT uses closures to maintain
two separate balances with a combined result of 6650 dollars. Change the data,
save the source and recompile to see different results. These are noninteractive
examples: this version has no keyboard-input procedure.

Keep SKATE.COM and SKATE.RT together on your working disk. The compiler copies
the required runtime into generated programs; those programs can subsequently
run without SKATE.RT. Source files use CR/LF line endings for CP/M TYPE and EDIT.
Browser storage belongs to that browser profile and site. Download a disk backup
before clearing site data or moving to another browser or computer.

## Size and capacity

| Component | Executable/provider bytes | CP/M record-rounded file |
| --- | ---: | ---: |
| SKATE.COM | 12,726 | 12,800 |
| SKATE.RT | 5,337 | 5,376 |

The compiler is 3,658 bytes below its 16 KiB code limit. Its measured total
allocation, including workspace, is 44,854 bytes against a 57,088-byte budget.
The current limits include 256 global slots, 128 simultaneous local slots,
320 symbol entries and 320 fixups. These are separate limits, not a promise
that arbitrary combinations of maximum-sized inputs fit at once.

Generated example files occupy 6,144 bytes (RECEIPT), 6,656 bytes (ROUTE) and
6,272 bytes (ACCOUNT), including their runtime. Application data, heap and
stack consume additional memory during execution.

## Current limitations and next work

This is an incomplete Scheme implementation. It does not yet provide numeric
comparisons, quotient/remainder, floating point, most type predicates, keyboard
input, `letrec`, named `let`, `cond`, internal definitions or rest parameters.
Empty `let` binding groups are rejected. Arithmetic and boolean forms do not
yet accept their full Scheme argument counts. Symbol identity across separate
quoted occurrences needs further verification; do not rely on it for lookup.
Macros, continuations, `eval`, vectors, ports and general file I/O are absent.

As a rough feature-coverage estimate, this release implements about half to
two-thirds of the intended small-language scope. This is not a percentage of
standard Scheme, a test-coverage figure or an estimate of remaining effort.
The next work completes integer operations, bindings and control forms,
console input and binary16 floating point.

Planning estimates for that completed scope are 15–17 KiB for the compiler
and 8–11 KiB for the runtime provider. The compiler's 16 KiB limit remains in
force; the upper estimate requires further compaction or an explicit design
review. These estimates exclude optional later extensions.

## Changes and verification

This release corrects premature tail returns from `let` and `let*`
initialisers, preservation of numeric output state across CP/M calls and
negative integer formatting. It adds the three examples, CP/M line endings
and a focused disk containing Skate, EDIT and the examples.

The example disk checks compile each source, compare generated object and COM
content, run the programs, export the disk and run them again after remounting.
TYPE output is checked against the original CR/LF source. Procedure, data and
release-publication checks also passed on the CP/M emulator. Physical ESP32
hardware operation is not established by these checks.
