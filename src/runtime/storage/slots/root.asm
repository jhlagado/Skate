; Runtime tracing of active activation slots.
; Entry point: SLOT_GC.
SLOT_GC:
        LD (SLOT_CUR),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SLOT_REP),A
        AND SLOT_PTR
        JR NZ,.HEAP
        LD A,(SLOT_REP)
        AND CELL_VAL
        RET Z
        LD A,(SLOT_REP)
        AND 0FH
        LD HL,(SLOT_CUR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP GC_VALUE
.HEAP:
        LD HL,(SLOT_CUR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        RET Z
        EX DE,HL
        JP GC_VAR
