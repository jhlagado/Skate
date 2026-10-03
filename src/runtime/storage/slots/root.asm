; Runtime tracing of active activation slots.
; Entry point: SLOT_GC.
SLOT_GC:
        LD (SRTSADR),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTSFLG),A
        AND SLOT_PTR
        JR NZ,.HEAP
        LD A,(SRTSFLG)
        AND CELL_VAL
        RET Z
        LD A,(SRTSFLG)
        AND 0FH
        LD HL,(SRTSADR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP GC_VALUE
.HEAP:
        LD HL,(SRTSADR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        RET Z
        EX DE,HL
        JP GC_VAR
