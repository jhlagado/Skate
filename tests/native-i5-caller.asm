; I5 caller template source.  The native compiler publishes the same shape
; as an NOBJ initialized section; the generated code slot is patched later.
; The provider symbols are deliberately placeholders.  NOBJ service imports
; replace their CALL operands after the runtime provider is placed.

ORG 0100H

CODEBASE EQU 0100H
CODEEND EQU 0300H
STACKLOW EQU 0D400H
STACKTOP EQU 0E400H
BSSBASE EQU 1100H
BSSNEXT EQU 1101H
BSSEND EQU 1188H
ROOTBASE EQU 1100H
ROOTEND EQU 1120H
ACTBASE EQU 1120H
ACTEND EQU 1130H
BMAPBASE EQU 1140H
BMAPBYT EQU 2
HEAPBASE EQU 1148H
HEAPCNT EQU 16

; Placeholders replaced by NOBJ service relocations.
HINIT EQU 4200H
GCSET EQU 4200H
RTINIT EQU 4200H
RTPKNEW EQU 4200H
RTINVOKE EQU 4200H
RTLIT EQU 4200H

COMSTART:
        LD SP,STACKTOP
        CALL BOOTINIT
        CALL GENCALL
        JP PRNRES

BOOTINIT:
        ; Check the descriptor revision and the addresses consumed below
        ; before clearing or handing any storage to the provider.
        LD A,(BOOTDESC)
        CP 1
        JP NZ,BOOTFAIL
        LD HL,(BOOTDESC+12)
        LD DE,TOPDESC
        OR A
        SBC HL,DE
        JP NZ,BOOTFAIL
        LD HL,(TOPDESC)
        LD A,H
        OR L
        JP Z,BOOTFAIL
        LD HL,(STORDESC)
        LD DE,BSSBASE
        OR A
        SBC HL,DE
        JP NZ,BOOTFAIL
        LD HL,(STORDESC+2)
        LD DE,BSSEND
        OR A
        SBC HL,DE
        JP NZ,BOOTFAIL
        LD HL,(STORDESC+12)
        LD DE,BMAPBASE
        OR A
        SBC HL,DE
        JP NZ,BOOTFAIL
        LD HL,(STORDESC+16)
        LD DE,HEAPBASE
        OR A
        SBC HL,DE
        JP NZ,BOOTFAIL
        ; Clear exactly the linked zero-initialized storage envelope before
        ; any allocator, collector or execution state is published.
        LD HL,BSSBASE
        LD DE,BSSNEXT
        LD BC,135
        LD (HL),0
        LDIR

HICALL:
        LD HL,(STORDESC+16)
        LD BC,(STORDESC+18)
HISVC:
        CALL HINIT
        JP C,BOOTFAIL

GCCALL:
        LD HL,(STORDESC+12)
        LD BC,(STORDESC+14)
GCSVC:
        CALL GCSET
        JP C,BOOTFAIL

RTCALL:
        LD HL,RTCONFIG
RTSVC:
        CALL RTINIT
        JP C,BOOTFAIL

        CALL LITINIT
        JP C,BOOTFAIL
        RET

BOOTFAIL:
        LD C,0
        CALL 5
        JP 0

; N8CODE replaces the bounded generated-code slot.  Numeric forms use the
; short service shapes; the first pair shape uses the same slot to stage a
; rooted packet before calling the provider's constructor.
        ORG 01C0H
GENCODE:
        DS 64

        ORG 0200H
GENCALL:
        LD HL,(TOPDESC)
        JP (HL)

        ORG 0208H
PRNRES:
        ; The generated slot returns one ABI-2 value in A:HL.  Preserve it
        ; while a fresh rooted packet is allocated for the runtime's ordinary
        ; `write` primitive; the caller never interprets the value itself.
        LD (RESULT),HL
        LD (RESTAG),A
        LD BC,1
PACKSVC:
        CALL RTPKNEW
        JP C,BOOTFAIL
        LD (OUTPACK),DE
        ; Slot one is the primitive callee.  FE38 is the stable value for
        ; primitive id 24, `write`, in the execution ABI.
        LD HL,4
        ADD HL,DE
        XOR A
        LD (HL),A
        INC HL
        LD (HL),38H
        INC HL
        LD (HL),0FEH
        INC HL
        LD (HL),0
        ; Slot two is the value returned by the generated code.
        LD HL,8
        ADD HL,DE
        LD A,(RESTAG)
        LD (HL),A
        INC HL
        LD DE,(RESULT)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (HL),0
        LD DE,(OUTPACK)
        LD BC,1
INVSVC:
        CALL RTINVOKE
        JP C,BOOTFAIL
        LD C,0
        CALL 5
        JP 0

ORG 0280H
LITINIT:
        ; The NOBJ recipe section follows the code image at run offset 0300H.
        ; RTCONFIG+10 carries the linked code base, so the recipe remains
        ; addressable when the caller is placed at another target address.
        LD HL,(RTCONFIG+10)
        LD DE,0300H
        ADD HL,DE
        LD C,(HL)
        INC HL
        LD B,(HL)
        INC HL
LITSVC:
        CALL RTLIT
        RET

BOOTDESC:
        DW 1
        DW 0,0
        DW 0,0
        DW LITINIT
        DW TOPDESC
        DW 8
        DW 16
        DW 4096
        DW 16
        DW HEAPCNT
        DW 0,0
        DW 0,0
        DW 0,0
        DW 0,0

STORDESC:
        DW BSSBASE,BSSEND
        DW ROOTBASE,ROOTEND
        DW ACTBASE,ACTEND
        DW BMAPBASE,BMAPBYT
        DW HEAPBASE,HEAPCNT

TOPDESC:
        DW GENCODE,0,0,0

RTCONFIG:
        DW ROOTBASE,ROOTEND
        DW ACTBASE,ACTEND
        DW HEAPBASE
        DW CODEBASE,CODEEND
        DW STACKLOW
        DW 0,0
        DW 0,0
        DW 0,0

RESULT:     DW 0
RESTAG:     DB 0
OUTPACK:    DW 0
