SWOUTB:
        PUSH AF
        LD HL,(SWLEN)
        INC HL
        LD A,H
        OR L
        JP Z,SWOUTERR
        LD (SWLEN),HL
        LD HL,(SWOUTIDX)
        LD DE,128
        OR A
        SBC HL,DE
        JP C,SWOUTST
        CALL SWFLUSH
        JP C,SWOUTERR
SWOUTST:
        LD HL,(SWOUTIDX)
        LD E,L
        LD D,0
        LD HL,RPBUFFER
        ADD HL,DE
        POP AF
        LD (HL),A
        LD HL,(SWOUTIDX)
        INC HL
        LD (SWOUTIDX),HL
        LD DE,128
        OR A
        SBC HL,DE
        JP NZ,SWOUTOK
        JP SWFLUSH
SWOUTOK:
        OR A
        RET
SWOUTERR:
        POP AF
        LD A,2
        LD (SWERR),A
        SCF
        RET

SWFLUSH:
        LD HL,(SWOUTIDX)
        LD A,H
        OR L
        RET Z
        LD A,H
        OR A
        JP NZ,SWSTGF
        LD A,L
        CP 128
        JP Z,SWSTGF
        LD A,128
        SUB L
        LD B,A
        LD A,1AH
        LD E,L
        LD D,0
        LD HL,RPBUFFER
        ADD HL,DE
SWSTGPAD:
        LD (HL),A
        INC HL
        DJNZ SWSTGPAD
SWSTGF:
        LD DE,RPBUFFER
        LD C,26
        CALL SWBDOS
        OR A
        JP NZ,SWSTGIO
        LD DE,RPFCB
        LD C,21
        CALL SWBDOS
        OR A
        JP NZ,SWSTGIO
        XOR A
        LD (SWOUTIDX),A
        LD (SWOUTIDX+1),A
        RET
SWSTGIO:
        LD A,2
        LD (SWERR),A
        SCF
        RET

SWSPBYTE:
        PUSH AF
        LD HL,(SWSLEN)
        INC HL
        LD A,H
        OR L
        JP Z,SWSPFAIL
        LD (SWSLEN),HL
        LD HL,(SWSPIDX)
        LD DE,128
        OR A
        SBC HL,DE
        JP C,SWSPSTOR
        CALL SWSFLUSH
        JP C,SWSPFAIL
SWSPSTOR:
        LD HL,(SWSPIDX)
        LD E,L
        LD D,0
        LD HL,SWSPBUF
        ADD HL,DE
        POP AF
        LD (HL),A
        LD HL,(SWSPIDX)
        INC HL
        LD (SWSPIDX),HL
        LD DE,128
        OR A
        SBC HL,DE
        JP NZ,SWSPDONE
        JP SWSFLUSH
SWSPDONE:
        OR A
        RET
SWSPFAIL:
        POP AF
        LD A,3
        LD (SWERR),A
        SCF
        RET

SWSFLUSH:
        LD HL,(SWSPIDX)
        LD A,H
        OR L
        RET Z
        LD A,H
        OR A
        JP NZ,SWSPFULL
        LD A,L
        CP 128
        JP Z,SWSPFULL
        LD A,128
        SUB L
        LD B,A
        LD A,1AH
        LD E,L
        LD D,0
        LD HL,SWSPBUF
        ADD HL,DE
SWSPPAD:
        LD (HL),A
        INC HL
        DJNZ SWSPPAD
SWSPFULL:
        LD DE,SWSPBUF
        LD C,26
        CALL SWBDOS
        OR A
        JP NZ,SWSPIO
        LD DE,SWPFCB
        LD C,21
        CALL SWBDOS
        OR A
        JP NZ,SWSPIO
        XOR A
        LD (SWSPIDX),A
        LD (SWSPIDX+1),A
        RET
SWSPIO:
        LD A,3
        LD (SWERR),A
        SCF
        RET

SWEMIT:
        LD HL,(SWIMGCNT)
        LD A,H
        OR L
        RET Z
        LD A,6
        CALL SWOUTB
        RET C
        LD HL,(SWIMGCNT)
        LD A,L
        ADD A,6
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
        LD HL,(SWIMGOFF)
        LD A,L
        CALL SWOUTB
        RET C
        LD HL,(SWIMGOFF)    ; SWOUTB uses HL for its buffered output index.
        LD A,H
        CALL SWOUTB
        RET C
        XOR A
        CALL SWOUTB
        RET C
        XOR A
        CALL SWOUTB
        RET C
        LD HL,(SWIMGCNT)
        LD A,L
        LD (SWICLEFT),A
        LD HL,SWIMAGE
        LD (SWIMGPTR),HL
SWIMGCOP:
        LD HL,(SWIMGPTR)
        LD A,(HL)
        INC HL
        LD (SWIMGPTR),HL
        CALL SWOUTB
        RET C
        LD A,(SWICLEFT)
        DEC A
        LD (SWICLEFT),A
        JP NZ,SWIMGCOP
        LD HL,(SWIMGOFF)
        LD DE,(SWIMGCNT)
        ADD HL,DE
        LD (SWIMGOFF),HL
        XOR A
        LD (SWIMGCNT),A
        LD (SWIMGCNT+1),A
        LD HL,(SWRECS)
        INC HL
        LD (SWRECS),HL
        OR A
        RET

SWCOPYSP:
        CALL SWSFLUSH
        RET C
        LD HL,(SWSLEN)
        LD (SWSPLEFT),HL
        LD A,H
        OR L
        RET Z
        CALL SWZFCBR
        LD A,128
        LD (SWPRIDX),A
        XOR A
        LD (SWPRIDX+1),A
SWSPLOOP:
        CALL SWPRBYTE
        RET C
        CALL SWOUTB
        RET C
        LD HL,(SWSPLEFT)
        DEC HL
        LD (SWSPLEFT),HL
        LD A,H
        OR L
        JP NZ,SWSPLOOP
        LD HL,(SWPCTS)
        LD DE,(SWRECS)
        ADD HL,DE
        LD (SWRECS),HL
        RET

SWLAYOUT:
        LD A,11
        CALL SWOUTB
        RET C
        LD A,4
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
        XOR A
        CALL SWOUTB
        RET C
        LD HL,(SWRECS)
        INC HL
        LD (SWRECS),HL
        RET

; ---------------------------------------------------------------------------
; Final CRC pass and COMMIT.
; ---------------------------------------------------------------------------
