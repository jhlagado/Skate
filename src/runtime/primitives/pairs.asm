; Primitive pair, list, equality and packet helpers.
; Entry points: PKT_CONS, PKT_CAR, PKT_CDR, PKT_LIST and PKT_EQ.
; Included in runtime order by ../primitives.asm.

; Read one packet argument and leave its value in A:HL.
PKT_ONE:
        LD A,(ARG_CNT)
        CP 1
        JP NZ,ERROR
        LD HL,ARG_PKT
        JP PKT_VAL

; Build one pair from the two packet values.
PKT_CONS:
        LD A,(ARG_CNT)
        CP 2
        JP NZ,ERROR
        LD HL,ARG_PKT
        CALL PKT_VAL
        LD (QT_CAR),HL
        LD (QT_CTAG),A
        LD A,C
        LD (QT_CEXT),A
        LD HL,ARG_PKT+4
        CALL PKT_VAL
        LD (QT_CDR),HL
        LD (QT_DTAG),A
        LD A,C
        LD (QT_DEXT),A
        CALL PAIR_NEW
        PUSH IX
        RET

; Apply a selector to the one packet argument.
PKT_CAR:
        CALL PKT_ONE
        CALL PAIR_CAR
        JP C,ERROR
        PUSH IX
        RET
PKT_CDR:
        CALL PKT_ONE
        CALL PAIR_CDR
        JP C,ERROR
        PUSH IX
        RET

; pair? returns false for every non-pair value.
PKT_PAIR:
        CALL PKT_ONE
        CALL PAIR_CHK
        JP C,PAIR_NO
        XOR A
        LD HL,0FE01H
        PUSH IX
        RET

; null? recognises the canonical empty-list value and nothing else.
PKT_NULL:
        CALL PKT_ONE
        OR A
        JP NZ,PAIR_NO
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JP NZ,PAIR_NO
        XOR A
        LD HL,0FE01H
        PUSH IX
        RET

; list consumes the bounded packet in source order and folds it into pairs.
PKT_LIST:
        LD A,(ARG_CNT)             ; The packet holds zero through ARG_MAX values.
        CP ARG_MAX+1
        JP NC,ERROR
        LD (PKT_LEFT),A
        LD HL,ARG_PKT
        LD (PKT_PTR),HL
.LOOP:
        LD A,(PKT_LEFT)
        OR A
        JR Z,.DONE
        LD HL,(PKT_PTR)
        CALL PKT_VAL
        CALL QT_PUSH
        LD HL,(PKT_PTR)
        LD DE,4
        ADD HL,DE
        LD (PKT_PTR),HL
        LD A,(PKT_LEFT)
        DEC A
        LD (PKT_LEFT),A
        JR .LOOP
.DONE:
        LD A,(ARG_CNT)
        LD B,0
        CALL QT_FOLD
        PUSH IX
        RET

; eq? compares both logical tags and payloads.
PKT_EQ:
        LD A,(ARG_CNT)
        CP 2
        JP NZ,ERROR
        LD HL,ARG_PKT
        CALL PKT_VAL
        LD (QT_CAR),HL
        LD (QT_CTAG),A
        LD A,C
        LD (QT_CEXT),A
        LD HL,ARG_PKT+4
        CALL PKT_VAL
        LD (QT_CDR),HL
        LD (QT_DTAG),A
        LD A,C
        LD (QT_DEXT),A
        LD A,(QT_CTAG)
        LD B,A
        LD A,(QT_DTAG)
        CP B
        JP NZ,PAIR_NO
        LD A,(QT_CEXT)
        LD B,A
        LD A,(QT_DEXT)
        CP B
        JP NZ,PAIR_NO
        LD HL,(QT_CAR)
        LD DE,(QT_CDR)
        OR A
        SBC HL,DE
        JP NZ,PAIR_NO
        XOR A
        LD HL,0FE01H
        PUSH IX
        RET
