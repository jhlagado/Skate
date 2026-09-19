SWBDOS:
        PUSH IX
        PUSH IY
        CALL 5
        POP IY
        POP IX
        LD (SWSTATUS),A
        RET

SWZFCBS:
        CALL SWZSTAGE
        LD HL,SWPFCB+12
        LD B,24
        XOR A
SWZPOOL:
        LD (HL),A
        INC HL
        DJNZ SWZPOOL
        RET

SWZSTAGE:
        LD HL,RPFCB+12
        LD B,24
        XOR A
SWZLOOP:
        LD (HL),A
        INC HL
        DJNZ SWZLOOP
        RET

SWZFCBR:
        LD HL,SWPFCB+12
        LD B,24
        XOR A
SWZPOOLR:
        LD (HL),A
        INC HL
        DJNZ SWZPOOLR
        RET

SWRESTF:
        LD A,(SWFCB33)
        LD (RPFCB+33),A
        LD A,(SWFCB34)
        LD (RPFCB+34),A
        LD A,(SWFCB35)
        LD (RPFCB+35),A
        RET

; RPATCH leaves RPBUFFER holding the rewritten declaration record.  If the
; staged stream ended part-way through its last physical record, reload that
; record before PATCH/LAYOUT bytes continue at the logical EOF offset.
SWRLOAD:
        LD HL,(SWLEN)
        LD A,L
        AND 127
        LD (SWOUTIDX),A
        XOR A
        LD (SWOUTIDX+1),A
        LD A,(SWOUTIDX)
        OR A
        JP Z,SWRLZERO
        LD HL,(SWLEN)
        LD B,7
SWRLSH:
        SRL H
        RR L
        DJNZ SWRLSH
        LD (RPFCB+33),HL
        XOR A
        LD (RPFCB+35),A
        LD DE,RPBUFFER
        LD C,26
        CALL SWBDOS
        OR A
        JP NZ,SWREADIO
        LD DE,RPFCB
        LD C,33
        CALL SWBDOS
        OR A
        JP NZ,SWREADIO
        XOR A
        RET
SWRLZERO:
        XOR A
        RET

SWEVOK:
        LD A,(SWERR)
        OR A
        RET Z
        SCF
        RET

SWBADST:
        LD A,1
        LD (SWERR),A
        JP SWRETERR
SWCAPERR:
        LD A,1
        LD (SWERR),A
        JP SWRETERR
SWPCAP:
        LD A,5
        LD (SWERR),A
        JP SWRETERR

SWRETERR:
        LD A,(SWERR)
        OR A
        JP NZ,SWRET2
        LD A,1
        LD (SWERR),A
SWRET2:
        SCF
        POP IY
        POP IX
        RET

SWRETOK:
        XOR A
        POP IY
        POP IX
        RET

; ---------------------------------------------------------------------------
; Writer state.  The fixed declaration bytes remain caller-owned fixture data.
; ---------------------------------------------------------------------------

SWCODEND:
SWWORK:
SWSTPTR: DW 0
SWSPPTR: DW 0
SWERR:      DB 0
SWSTATE:    DB 0
SWARG:      DB 0
SWSTATUS:   DB 0
SWDECPOS:  DW 0
SWOUTIDX:   DW 0
SWLEN:      DW 0
SWIMGCNT: DW 0
SWICLEFT: DB 0
SWIMGPTR: DW 0
SWIMGOFF:   DW 0
SWTOTAL:    DW 0
SWSPIDX:    DW 0
SWSLEN:     DW 0
SWPOFF: DW 0
SWPEND: DW 0
SWPSRC: DW 0
SWPLEN: DB 0
SWPLEFT: DB 0
SWPCTS:  DW 0
SWRECS:     DW 0
SWCOUNT:    DW 0
SWFCB33:    DB 0
SWFCB34:    DB 0
SWFCB35:    DB 0
SWDMA: DB 0
SWRIDX:  DW 0
SWRLEFT: DW 0
SWSPLEFT:   DW 0
SWPRIDX: DW 0
SWCRC:      DW 0
SWCRCBY:  DB 0
SWLENS: DS 4
SWIMAGE:    DS SWIMGBY
SWPFCB:     DS 36
SWSPBUF:    DS 128
SWWEND:
