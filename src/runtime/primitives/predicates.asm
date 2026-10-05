; Primitive logical and type predicates.
; Entry points: PRIM_NOT, PRIM_IS and canonical boolean results.
; Included in runtime order by ../primitives.asm.

; not and the type predicates return canonical boolean values.
PRIM_NOT:
        LD A,(ARG_CNT)
        CP 1
        JP NZ,ERROR
        LD HL,ARG_PKT
        CALL PKT_VAL
        CALL RT_TEST
        JP Z,PKT_YES
        JP PKT_NO
PRIM_IS:
        LD A,(ARG_CNT)
        CP 1
        JP NZ,ERROR
        LD HL,ARG_PKT
        CALL PKT_VAL
        LD (NUM_VAL),HL
        LD (NUM_TAG),A
        LD A,(PRIM_ID)
        CP 22
        JP Z,.NUMBER
        CP 23
        JP Z,.BOOLEAN
        CP 24
        JP Z,.SYMBOL
        CP 25
        JP Z,.PROC
        CP 26
        JP Z,.STRING
        CP 27
        JP Z,.CHAR
        JP .EOF
.NUMBER:
        LD A,(NUM_TAG)
        LD HL,(NUM_VAL)
        CALL PRIM_NUM
        JP C,PKT_NO
        JP PKT_YES
.BOOLEAN:
        LD A,(NUM_TAG)
        OR A
        JP NZ,PKT_NO
        LD HL,(NUM_VAL)
        LD DE,0FE00H
        OR A
        SBC HL,DE
        JP Z,PKT_YES
        LD HL,(NUM_VAL)
        LD DE,0FE01H
        OR A
        SBC HL,DE
        JP Z,PKT_YES
        JP PKT_NO
.SYMBOL:
        LD A,(NUM_TAG)
        CP 4
        JP Z,PKT_YES
        JP PKT_NO
.PROC:
        LD A,(NUM_TAG)
        CP 8
        JR NZ,.PROC_TAG
        LD HL,(NUM_VAL)
        LD A,H
        CP 0F0H
        JP NC,PKT_NO                ; Port tokens are opaque, not procedures.
        JP PKT_YES
.PROC_TAG:
        CP 2
        JP Z,PKT_YES
        OR A
        JP NZ,PKT_NO
        LD HL,(NUM_VAL)
        LD A,H
        CP 0FEH
        JP NZ,PKT_NO
        LD A,L
        CP 20H
        JP C,PKT_NO
        CP PRIM_LIM
        JP C,PKT_YES
        JP PKT_NO
.STRING:
        LD A,(NUM_TAG)
        CP 5
        JP Z,PKT_YES
        CP 6
        JP NZ,PKT_NO
        LD HL,(NUM_VAL)
        CALL STR_CHK
        JP C,PKT_NO
        JP PKT_YES
.CHAR:
        LD A,(NUM_TAG)
        OR A
        JP NZ,PKT_NO
        LD HL,(NUM_VAL)
        LD A,H
        CP 0FFH
        JP Z,PKT_YES
        JP PKT_NO
.EOF:
        LD A,(NUM_TAG)
        OR A
        JP NZ,PKT_NO
        LD HL,(NUM_VAL)
        LD DE,0FE03H
        OR A
        SBC HL,DE
        JP NZ,PKT_NO
PKT_YES:
        LD A,1
PKT_BOOL:
        OR A
        JR Z,.FALSE
        XOR A
        LD HL,0FE01H
        PUSH IX
        RET
.FALSE:
        XOR A
        LD HL,0FE00H
        PUSH IX
        RET
PKT_NO:
        XOR A
        JR PKT_BOOL
