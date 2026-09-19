; Integer-only payload with the same entry and service-vector contract.
%INCLUDE "../provider/origin-payload.asm"

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
        LD HL,HEAPBASE
        LD BC,HEAPCNT
        CALL 0
        JP C,PAYFAIL
        LD HL,BMAPBASE
        LD BC,BMAPBYT
        CALL 0
        JP C,PAYFAIL
        LD HL,RTCONFIG
        CALL 0
        JP C,PAYFAIL
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
        LD (RESULTV),HL
        LD (RESULTT),A
        SCF
        JP 0FF00H
PAYDONE:
        JP 0FF00H

PAYDATA:
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
ORG 0100H
ORG 02A05H
