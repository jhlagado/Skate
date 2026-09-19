%INCLUDE "origin.asm"
%INCLUDE "../src/compiler/lexer.asm"
; Memory-backed callback deliberately destroys every allowed register pair.
LSOURCE:
        LD HL,(LSPTR)
        LD DE,(LSEND)
        OR A
        SBC HL,DE
        SCF
        RET Z
        LD HL,(LSPTR)
        LD A,(HL)
        INC HL
        LD (LSPTR),HL
        LD HL,0A55AH
        LD BC,03CC3H
        LD DE,06996H
        OR A
        RET
LSPTR: DW 0
LSEND: DW 0
