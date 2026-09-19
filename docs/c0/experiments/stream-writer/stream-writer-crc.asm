SWCRCRD:
        LD A,(RPFCB+33)
        LD (SWFCB33),A
        LD A,(RPFCB+34)
        LD (SWFCB34),A
        LD A,(RPFCB+35)
        LD (SWFCB35),A
        CALL SWZSTAGE
        LD HL,(SWLEN)
        LD (SWRLEFT),HL
        LD A,128
        LD (SWRIDX),A
        XOR A
        LD (SWRIDX+1),A
        LD A,0FFH
        LD (SWCRC),A
        LD (SWCRC+1),A
SWCRCLP:
        LD HL,(SWRLEFT)
        LD A,H
        OR L
        JP Z,SWCRCPFX
        CALL SWRDBYTE
        RET C
        CALL SWCRCUP
        LD HL,(SWRLEFT)
        DEC HL
        LD (SWRLEFT),HL
        JP SWCRCLP
SWCRCPFX:
        LD A,12
        CALL SWCRCUP
        LD A,9
        CALL SWCRCUP
        XOR A
        CALL SWCRCUP
        LD HL,(SWRECS)
        INC HL
        LD (SWCOUNT),HL
        LD A,L
        CALL SWCRCUP
        LD HL,(SWCOUNT)
        LD A,H
        CALL SWCRCUP
        XOR A
        CALL SWCRCUP
        XOR A
        CALL SWCRCUP
        LD A,1
        CALL SWCRCUP
        XOR A
        CALL SWCRCUP
        XOR A
        CALL SWCRCUP
        CALL SWRESTF
        RET

SWRDBYTE:
        LD HL,(SWRIDX)
        LD DE,128
        OR A
        SBC HL,DE
        JP C,SWRREADY
        LD DE,RPBUFFER
        LD C,26
        CALL SWBDOS
        OR A
        JP NZ,SWREADIO
        LD DE,RPFCB
        LD C,20
        CALL SWBDOS
        OR A
        JP NZ,SWREADIO
        XOR A
        LD (SWRIDX),A
        LD (SWRIDX+1),A
SWRREADY:
        LD HL,(SWRIDX)
        LD E,L
        LD D,0
        LD HL,RPBUFFER
        ADD HL,DE
        LD A,(HL)
        LD HL,(SWRIDX)
        INC HL
        LD (SWRIDX),HL
        OR A
        RET
SWREADIO:
        LD A,4
        LD (SWERR),A
        SCF
        RET

SWPRBYTE:
        LD HL,(SWPRIDX)
        LD DE,128
        OR A
        SBC HL,DE
        JP C,SWPRDY
        LD DE,SWSPBUF
        LD C,26
        CALL SWBDOS
        OR A
        JP NZ,SWPRIO
        LD DE,SWPFCB
        LD C,20
        CALL SWBDOS
        OR A
        JP NZ,SWPRIO
        XOR A
        LD (SWPRIDX),A
        LD (SWPRIDX+1),A
SWPRDY:
        LD HL,(SWPRIDX)
        LD E,L
        LD D,0
        LD HL,SWSPBUF
        ADD HL,DE
        LD A,(HL)
        LD HL,(SWPRIDX)
        INC HL
        LD (SWPRIDX),HL
        OR A
        RET
SWPRIO:
        LD A,4
        LD (SWERR),A
        SCF
        RET

SWCRCUP:
        LD (SWCRCBY),A
        LD A,(SWCRCBY)
        LD HL,SWCRC+1
        XOR (HL)
        LD (HL),A
        LD B,8
SWCRCBIT:
        LD HL,(SWCRC)
        ADD HL,HL
        JP NC,SWCRCNX
        LD DE,1021H
        LD A,L
        XOR E
        LD L,A
        LD A,H
        XOR D
        LD H,A
        LD (SWCRC),HL
        JP SWCRCNXT
SWCRCNX:
        LD (SWCRC),HL
SWCRCNXT:
        DJNZ SWCRCBIT
        RET

SWCOMMIT:
        LD A,12
        CALL SWOUTB
        RET C
        LD A,9
        CALL SWOUTB
        RET C
        XOR A
        CALL SWOUTB
        RET C
        LD HL,(SWRECS)
        INC HL
        LD (SWCOUNT),HL
        LD A,L
        CALL SWOUTB
        RET C
        LD HL,(SWCOUNT)
        LD A,H
        CALL SWOUTB
        RET C
        XOR A
        CALL SWOUTB
        RET C
        XOR A
        CALL SWOUTB
        RET C
        LD A,1
        CALL SWOUTB
        RET C
        XOR A
        CALL SWOUTB
        RET C
        XOR A
        CALL SWOUTB
        RET C
        LD A,(SWCRC)
        CALL SWOUTB
        RET C
        LD A,(SWCRC+1)
        CALL SWOUTB
        RET C
        JP SWFLUSH

; ---------------------------------------------------------------------------
; BDOS, FCB and event helpers.
; ---------------------------------------------------------------------------
