; Four-byte value-cell contract used by heap bindings, pairs and vector elements.
;
; This file contains constants only.  It emits no bytes and is included before
; runtime code so the storage modules share one layout vocabulary.  The value
; ABI and argument-packet format are unchanged; see docs/four-byte-cells.md.

CELL_SZ        EQU 4                ; One value cell occupies four bytes.

; Static slots, argument packets, operand roots and the operator, quoted-data
; and reader stacks use the cell layout: payload bytes 0 and 1, byte 2 clear
; (the future third payload byte) and byte 3 holding the tag in its low nibble
; and the record's flags in its high nibble.  Bit 4 marks a live or
; initialized record; static slots keep their escape mark in bit 7.
CELL_VAL       EQU 10H              ; Live or initialized record.

; Heap binding cells keep their tag in the low nibble too, with these flags.
BND_INIT       EQU 10H              ; The binding holds a value.
BND_ESC        EQU 20H              ; A closure has captured it.
BND_USED       EQU 40H              ; The cell is allocated.
BND_MARK       EQU 80H              ; The collector has marked it.
PAIR_LEN       EQU 8                ; A pair is two adjacent cells.
HEAP_CAP        EQU 64              ; A 256-byte binding page holds 64 cells.
CELL_LO         EQU 0               ; Payload low byte.
CELL_HI         EQU 1               ; Payload high byte.
CELL_EXT         EQU 2              ; Reserved payload extension byte.
CELL_TAG        EQU 3               ; Tag and storage metadata byte.
TAG_POS        EQU 4                ; The provisional tag nibble shift.
TAG_MASK       EQU 0F0H             ; Metadata bits 7..4 carry the tag.
META_LO       EQU 00FH              ; Metadata bits 3..0 stay reserved.

; Tag-zero payloads FE20H up to FE00H+PRIM_LIM (exclusive) are primitive
; procedures; the low byte less 20H is the zero-based primitive kind.
PRIM_LIM       EQU 9FH
ARG_MAX        EQU 32                ; Records in the argument packet, ARG_PKT.

; Current logical tag values.  Tag zero is the scalar family; tag eight is the
; shared escape/port family.  These constants document the current ABI only.
TAG_IMM       EQU 0
TAG_PAIR       EQU 1
TAG_CLOS       EQU 2
TAG_INT       EQU 3
TAG_SYM       EQU 4
TAG_LIT       EQU 5
TAG_STR       EQU 6
TAG_VEC       EQU 7
TAG_ESC       EQU 8

; Pair cells use the same four-byte extent.  The first cell carries the
; pair-level allocation and mark bits in its legacy packed state byte; the
; second cell carries only the CDR tag.  These offsets keep the pair changes
; explicit while the public value ABI remains A:HL plus a logical tag.
PAIR_SZ          EQU 8
PAIR_CAP        EQU 32
CAR_LO       EQU 0
CAR_HI       EQU 1
CAR_TAG      EQU 3
CDR_LO       EQU 4
CDR_HI       EQU 5
CDR_TAG       EQU 7

; Vector elements are four-byte cells without pair allocation state. Their
; current compatibility metadata stores the raw logical tag at byte three;
; byte two remains the reserved extension until tag/flag packing changes.
ELEM_LO        EQU 0
ELEM_HI        EQU 1
ELEM_EXT        EQU 2
ELEM_TAG       EQU 3
