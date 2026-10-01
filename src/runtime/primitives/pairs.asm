; Primitive pair, list, equality and packet helpers.
; Entry points: SRTPCONS, SRTPCAR, SRTPCDR, SRTLIST and SRTPEQ.
; Included in runtime order by ../primitives.asm.

; Read one packet argument and leave its value in A:HL.
SRTONE:
        LD A,(SRTARGC)
        CP 1
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        JP SRTPVAL

; Build one pair from the two packet values.
SRTPCONS:
        LD A,(SRTARGC)
        CP 2
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        LD (SRTQCAR),HL
        LD (SRTQCTAG),A
        LD HL,SRTARGPK+4
        CALL SRTPVAL
        LD (SRTQCDR),HL
        LD (SRTQDTAG),A
        CALL SRTMAKEP
        PUSH IX
        RET

; Apply a selector to the one packet argument.
SRTPCAR:
        CALL SRTONE
        CALL SRTCARV
        JP C,SRTERROR
        PUSH IX
        RET
SRTPCDR:
        CALL SRTONE
        CALL SRTCDRV
        JP C,SRTERROR
        PUSH IX
        RET

; pair? returns false for every non-pair value.
SRTPPAR:
        CALL SRTONE
        CALL SRTPCHK
        JP C,SRTFPALS
        XOR A
        LD HL,0FE01H
        PUSH IX
        RET

; null? recognises the canonical empty-list value and nothing else.
SRTNPRED:
        CALL SRTONE
        OR A
        JP NZ,SRTFPALS
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JP NZ,SRTFPALS
        XOR A
        LD HL,0FE01H
        PUSH IX
        RET

; list consumes the bounded packet in source order and folds it into pairs.
SRTLIST:
        LD A,(SRTARGC)
        CP 8
        JP NC,SRTERROR
        LD (SRTLCN),A
        LD HL,SRTARGPK
        LD (SRTLCP),HL
SRTLLP:
        LD A,(SRTLCN)
        OR A
        JR Z,SRTLDONE
        LD HL,(SRTLCP)
        CALL SRTPVAL
        CALL SRTQPUT
        LD HL,(SRTLCP)
        LD DE,4
        ADD HL,DE
        LD (SRTLCP),HL
        LD A,(SRTLCN)
        DEC A
        LD (SRTLCN),A
        JR SRTLLP
SRTLDONE:
        LD A,(SRTARGC)
        LD B,0
        CALL SRTQBLD
        PUSH IX
        RET

; eq? compares both logical tags and payloads.
SRTPEQ:
        LD A,(SRTARGC)
        CP 2
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        LD (SRTQCAR),HL
        LD (SRTQCTAG),A
        LD HL,SRTARGPK+4
        CALL SRTPVAL
        LD (SRTQCDR),HL
        LD (SRTQDTAG),A
        LD A,(SRTQCTAG)
        LD B,A
        LD A,(SRTQDTAG)
        CP B
        JP NZ,SRTFPALS
        LD HL,(SRTQCAR)
        LD DE,(SRTQCDR)
        OR A
        SBC HL,DE
        JP NZ,SRTFPALS
        XOR A
        LD HL,0FE01H
        PUSH IX
        RET
