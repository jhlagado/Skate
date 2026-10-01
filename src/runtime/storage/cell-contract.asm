; Experimental four-byte value-cell contract.
;
; This file contains constants only.  It emits no bytes and is included before
; runtime code so future storage helpers can share one layout vocabulary without
; changing the current value ABI or argument-packet format.

SRTCELW        EQU 4                ; One value cell occupies four bytes.
SRTPAIRW       EQU 8                ; A pair is two adjacent cells.
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
