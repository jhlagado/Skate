; Four-byte value-cell contract used by heap bindings, pairs and vector elements.
;
; This file contains constants only.  It emits no bytes and is included before
; runtime code so the storage modules share one layout vocabulary.  The value
; ABI and argument-packet format are unchanged; see docs/four-byte-cells.md.

SRTCELW        EQU 4                ; One value cell occupies four bytes.
SRTPAIRW       EQU 8                ; A pair is two adjacent cells.
SRTBCAP        EQU 64               ; A 256-byte binding page holds 64 cells.
SRTCP0         EQU 0                ; Payload low byte.
SRTCP1         EQU 1                ; Payload high byte.
SRTCEX         EQU 2                ; Reserved payload extension byte.
SRTCMET        EQU 3                ; Tag and storage metadata byte.
SRTCTSH        EQU 4                ; The provisional tag nibble shift.
SRTCTMSK       EQU 0F0H             ; Metadata bits 7..4 carry the tag.
SRTCFMSK       EQU 00FH             ; Metadata bits 3..0 stay reserved.

; Current logical tag values.  Tag zero is the scalar family; tag eight is the
; shared escape/port family.  These constants document the current ABI only.
SRTCTAG0       EQU 0
SRTCTAG1       EQU 1
SRTCTAG2       EQU 2
SRTCTAG3       EQU 3
SRTCTAG4       EQU 4
SRTCTAG5       EQU 5
SRTCTAG6       EQU 6
SRTCTAG7       EQU 7
SRTCTAG8       EQU 8

; Pair cells use the same four-byte extent.  The first cell carries the
; pair-level allocation and mark bits in its legacy packed state byte; the
; second cell carries only the CDR tag.  These offsets keep the pair changes
; explicit while the public value ABI remains A:HL plus a logical tag.
SRTPW          EQU 8
SRPPCAP        EQU 32
SRPCCAR0       EQU 0
SRPCCAR1       EQU 1
SRPCCARM      EQU 3
SRPCDDR0       EQU 4
SRPCDDR1       EQU 5
SRPCDDRM       EQU 7

; Vector elements are four-byte cells without pair allocation state. Their
; current compatibility metadata stores the raw logical tag at byte three;
; byte two remains the reserved extension until tag/flag packing changes.
SRTVCP0        EQU 0
SRTVCP1        EQU 1
SRTVCEX        EQU 2
SRTVCMET       EQU 3
