; Primitive pair, list, equality and packet helpers.
; Entry points: PKT_CONS, PKT_CAR, PKT_CDR, PKT_LIST and PKT_EQ.
; Included in runtime order by ../primitives.asm.

; Read one packet argument and leave its value in A:HL.
PKT_ONE:
        LD A,(SRTARGC)
        CP 1
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        JP PKT_VAL

; Build one pair from the two packet values.
PKT_CONS:
        LD A,(SRTARGC)
        CP 2
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL PKT_VAL
        LD (SRTQCAR),HL
        LD (SRTQCTAG),A
        LD HL,SRTARGPK+4
        CALL PKT_VAL
        LD (SRTQCDR),HL
        LD (SRTQDTAG),A
        CALL PAIR_NEW
        PUSH IX
        RET

; Apply a selector to the one packet argument.
PKT_CAR:
        CALL PKT_ONE
        CALL PAIR_CAR
        JP C,SRTERROR
        PUSH IX
        RET
PKT_CDR:
        CALL PKT_ONE
        CALL PAIR_CDR
        JP C,SRTERROR
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
        LD A,(SRTARGC)             ; The packet holds zero through eight values.
        CP 9                       ; Eight is the full packet, not an overflow.
        JP NC,SRTERROR             ; Reject only a count beyond the eight records.
        LD (SRTLCN),A
        LD HL,SRTARGPK
        LD (SRTLCP),HL
.LOOP:
        LD A,(SRTLCN)
        OR A
        JR Z,.DONE
        LD HL,(SRTLCP)
        CALL PKT_VAL
        CALL QT_PUSH
        LD HL,(SRTLCP)
        LD DE,4
        ADD HL,DE
        LD (SRTLCP),HL
        LD A,(SRTLCN)
        DEC A
        LD (SRTLCN),A
        JR .LOOP
.DONE:
        LD A,(SRTARGC)
        LD B,0
        CALL QT_FOLD
        PUSH IX
        RET

; eq? compares both logical tags and payloads.
PKT_EQ:
        LD A,(SRTARGC)
        CP 2
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL PKT_VAL
        LD (SRTQCAR),HL
        LD (SRTQCTAG),A
        LD HL,SRTARGPK+4
        CALL PKT_VAL
        LD (SRTQCDR),HL
        LD (SRTQDTAG),A
        LD A,(SRTQCTAG)
        LD B,A
        LD A,(SRTQDTAG)
        CP B
        JP NZ,PAIR_NO
        LD HL,(SRTQCAR)
        LD DE,(SRTQCDR)
        OR A
        SBC HL,DE
        JP NZ,PAIR_NO
        XOR A
        LD HL,0FE01H
        PUSH IX
        RET
