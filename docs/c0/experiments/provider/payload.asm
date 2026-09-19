%INCLUDE "origin-payload.asm"

; C0 generated payload appended to the prepared provider.
;
; PUBLIC ENTRY
;   PAYLOAD_ENTRY  Startup entry.  It initializes the real allocator,
;                  collector and execution services, then adds the two
;                  caller-supplied ABI-2 integer values.
;
; CALL CONTRACT
;   On entry A:HL is the left value and B:DE the right value, as required by
;   NADD.  The values are saved before runtime setup because HINIT, GCSET and
;   RTINIT freely clobber AF/BC/DE/HL.  On success A:HL is the input-dependent
;   exact integer result.  Carry is set only on the real provider error path.
;
; MEMORY
;   The initialized payload section contains startup code, descriptor and
;   result scratch.  The two-entry global table is initialized in this
;   section.  Fixed zero sections in the NOBJ object own roots, activations,
;   bitmap, heap and compiler-selected workspace.
;   STACKLOW..STACKTOP is the guarded descending native stack.
;
; FAILURE / STACK
;   Any provider setup or numeric error jumps to PAYLOAD_FAIL.  Success jumps
;   to the host sentinel at $FF00 after restoring the result in A:HL.  The
;   startup establishes STACKTOP before the first CALL; all runtime calls
;   return with SP balanced and preserve IX/IY where their contracts require.

; This value is the measured PVEND from provider.asm.  The test asserts the
; assembled provider extent before accepting this prepared placement.
PAYORG EQU 02A05H

ROOTBASE       EQU 03000H
ROOTEND        EQU 03040H
ACTBASE        EQU 03100H
ACTEND         EQU 03180H
BMAPBASE       EQU 03200H
BMAPBYT        EQU 0400H
HEAPBASE       EQU 03700H
HEAPCNT        EQU 02000H
WORKBASE       EQU 03600H
WORKEND        EQU 03700H
GLOBCT         EQU 0002H
STACKLOW       EQU 0D400H
STACKTOP       EQU 0E400H

PAYENTRY:
        LD SP,STACKTOP
        LD (INPUTL),HL
        LD (INPUTR),DE
        LD (INPUTLT),A
        LD A,B
        LD (INPUTRT),A

        ; HINIT builds the real free list in HEAPBASE..HEAPEND.
        LD HL,HEAPBASE
        LD BC,HEAPCNT
        CALL 0
        JP C,PAYFAIL

        ; GCSET installs the exact bitmap extent for those physical cells.
        LD HL,BMAPBASE
        LD BC,BMAPBYT
        CALL 0
        JP C,PAYFAIL

        ; RTINIT consumes the checked 14-word region map below.  The final
        ; four words describe empty immutable string tables.
        LD HL,RTCONFIG
        CALL 0
        JP C,PAYFAIL

        ; Restore caller values and use the selected provider service.
        LD HL,(INPUTL)
        LD DE,(INPUTR)
        LD A,(INPUTLT)
        LD C,A
        LD A,(INPUTRT)
        LD B,A
        LD A,C
        CALL 0
        JP C,PAYFAIL
        LD (RESULTV),HL
        LD (RESULTT),A
        JP PAYDONE

PAYFAIL:
        ; Preserve the provider error discriminator for the host proof.
        LD (RESULTV),HL
        LD (RESULTT),A
        SCF
        JP 0FF00H

PAYDONE:
        ; numeric.add returns carry clear on success; preserve that ABI result.
        JP 0FF00H

PAYDATA:
; Forty-byte descriptor required by the real org.skate.runtime ABI 2 validator.
; The top-level descriptor points back to this input-dependent entry.
BOOTDESC:
        DW 1
        DW GLOBBASE,GLOBCT
        DW 0,0
        DW PAYENTRY
        DW TOPDESC
        DW 16
        DW 128
        DW 4096
        DW 256
        DW HEAPCNT
        DW 0,0
        DW 0,0
        DW 0,0
        DW 0,0

TOPDESC:
        DW PAYENTRY,0,0,0

; Ten words consumed by RTINIT, followed by four words for string metadata.
RTCONFIG:
        DW ROOTBASE,ROOTEND
        DW ACTBASE,ACTEND
        DW HEAPBASE
        DW PAYORG,PAYEND
        DW STACKLOW
        DW GLOBBASE,GLOBCT
        DW 0,0
        DW 0,0

GLOBBASE:
        DS 12

INPUTL:  DW 0
INPUTR:  DW 0
INPUTLT: DB 0
INPUTRT: DB 0
RESULTV: DW 0
RESULTT: DB 0
PAYEND:
