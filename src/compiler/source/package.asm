; CP/M manifest and multi-part source stream handling.
; Entry points: CSPKBYTE and the manifest-part helpers.
; Package stream helpers
;
; A .SKM manifest remains open in CSMANFCB while one named source part is
; streamed through CSFCB.  The manifest parser accepts one bounded 8.3 name per
; line, rejects duplicates, and inserts one LF between parts so a token cannot
; silently join two files.
; ----------------------------------------------------------------------------
CSPKBYTE:
        LD A,(CSINDEX+4)
        OR A
        JR Z,.NEXTP
        XOR A
        LD (CSINDEX+4),A
        LD A,10
        OR A
        RET
.NEXTP:
        LD A,(CSINDEX+3)
        OR A
        JR Z,.NNEED
        CALL .PARTB
        JR NC,.NRET
        LD A,(CSERROR)
        OR A
        JR NZ,.NRET
        XOR A
        LD (CSINDEX+3),A
        LD (CSINDEX+13),A
        LD DE,CSFCB
        LD C,16
        CALL CSBDOS
        CP 255
        JR Z,.PCLSERR
        CALL .NEXT
        JR C,.NRET
        LD A,1
        LD (CSINDEX+4),A
        JR CSPKBYTE
.PCLSERR:
        LD A,3
        JP CSFAIL
.NNEED:
        CALL .NEXT
        JR C,.NRET
        JR CSPKBYTE
.NRET:
        RET

; Read one record from the active source part.  Unlike the flat stream, a
; part's Ctrl-Z is a boundary; CSPKBYTE closes it and advances the manifest.
.PARTB:
        LD A,(CSINDEX+13)
        OR A
        SCF
        RET NZ
        LD A,(CSINDEX+12)
        CP 128
        JR C,.PFETCH
        LD DE,CSBUFFER
        LD C,26
        CALL CSBDOS
        LD DE,CSFCB
        LD C,20
        CALL CSBDOS
        OR A
        JR Z,.PREC
        CP 1
        JR Z,.PEND
        LD A,2
        JP CSFAIL
.PREC: XOR A
.PFETCH:
        LD E,A
        LD D,0
        INC A
        LD (CSINDEX+12),A
        LD HL,CSBUFFER
        ADD HL,DE
        LD A,(HL)
        CP 26
        JR Z,.PEND
        CALL CSMARKB
        OR A
        RET
.PEND: CALL CSMARKI
        LD A,1
        LD (CSINDEX+13),A
        SCF
        RET

; Read one byte from the manifest file.
.MGET:
        LD A,(CSINDEX+5)
        OR A
        SCF
        RET NZ
        LD A,(CSINDEX+7)
        CP 128
        JR C,.MFETCH
        LD DE,CSMANBUF
        LD C,26
        CALL CSBDOS
        LD DE,CSMANFCB
        LD C,20
        CALL CSBDOS
        OR A
        JR Z,.MREC
        CP 1
        JR Z,.MEND
        LD A,6
        JP CSFAIL
.MREC: XOR A
.MFETCH:
        LD E,A
        LD D,0
        INC A
        LD (CSINDEX+7),A
        LD HL,CSMANBUF
        ADD HL,DE
        LD A,(HL)
        CP 26
        JR Z,.MEND
        CALL .MCOUNT
        RET C
        OR A
        RET
.MEND: LD A,1
        LD (CSINDEX+5),A
        SCF
        RET

; Keep the manifest bounded at the host contract's 2048 bytes.  The Ctrl-Z
; terminator is not counted; a byte beyond the limit becomes a read error.
.MCOUNT:
        PUSH AF
        LD HL,CSINDEX+14
        INC (HL)
        JR NZ,.MCCHECK
        INC HL
        INC (HL)
.MCCHECK:
        LD HL,CSINDEX+15
        LD A,(HL)
        CP 8
        JR C,.MCGOOD
        JR NZ,.MCBAD
        DEC HL
        LD A,(HL)
        OR A
        JR Z,.MCGOOD
.MCBAD:
        POP AF
        LD A,6
        JP CSFAIL
.MCGOOD:
        POP AF
        OR A
        RET

; Find and open the next manifest part.  A clean manifest EOF sets CSDONE;
; malformed names, duplicates and missing files become sticky error five.
.NEXT:
        XOR A
        LD (CSINDEX+8),A
.NSKIP:
        CALL .MGET
        JR C,.NLINEE
        CP 13
        JR Z,.NSKIP
        CP 10
        JR Z,.NSKIP
        CP ' '
        JR Z,.NSKIP
        CALL .NBYTE
        JP C,.NFAIL
.NREAD:
        CALL .MGET
        JR C,.NLINEE
        CP 13
        JR Z,.NLINE
        CP 10
        JR Z,.NLINE
        CALL .NBYTE
        JP C,.NFAIL
        JR .NREAD
.NLINEE:
        LD A,(CSERROR)
        OR A
        JR Z,.NLINEV
        SCF
        RET
.NLINEV:
        LD A,(CSINDEX+8)
        OR A
        JR Z,.NENDP
.NLINE:
        CALL .NOPEN
        JP C,.NFAIL
        OR A
        RET
.NENDP:
        LD A,1
        LD (CSDONE),A
        SCF
        RET

; Store one printable manifest character and fold lower case to CP/M upper.
.NBYTE:
        CP '0'
        JR C,.NCHKP
        CP '9'+1
        JR C,.NGOOD
        CP 'A'
        JR C,.NCHKP
        CP 'Z'+1
        JR C,.NGOOD
        CP 'a'
        JR C,.NCHKP
        CP 'z'+1
        JR NC,.NCHKP
        SUB 32
        JR .NGOOD
.NCHKP:
        CP '.'
        JR Z,.NGOOD
        CP '$'
        JR Z,.NGOOD
        CP '%'
        JR Z,.NGOOD
        CP 39
        JR Z,.NGOOD
        CP '-'
        JR Z,.NGOOD
        CP '_'
        JR Z,.NGOOD
        CP '@'
        JR Z,.NGOOD
        CP '~'
        JR Z,.NGOOD
        CP '`'
        JR Z,.NGOOD
        CP '{'
        JR Z,.NGOOD
        CP '}'
        JR Z,.NGOOD
        CP '^'
        JR Z,.NGOOD
        CP '#'
        JR Z,.NGOOD
        CP '&'
        JR Z,.NGOOD
        CP '!'
        JR Z,.NGOOD
        CP '('
        JR Z,.NGOOD
        CP ')'
        JR Z,.NGOOD
        JR .NINV
.NGOOD:
        LD C,A
        LD A,(CSINDEX+8)
        CP 12
        JR NC,.NTOO
        LD L,A
        LD H,0
        INC A
        LD (CSINDEX+8),A
        LD DE,CSPART
        ADD HL,DE
        LD (HL),C
        XOR A
        RET
.NINV: LD A,5
        SCF
        RET
.NTOO: LD A,5
        SCF
        RET

; Build the active FCB, reject duplicate parts and open the named file.
.NOPEN:
        LD HL,CSFCB
        LD B,36
        XOR A
.NCLR: LD (HL),A
        INC HL
        DJNZ .NCLR
        LD A,(CSMANFCB)
        LD (CSFCB),A
        LD HL,CSFCB+1
        LD B,11
        LD A,' '
.NSPC: LD (HL),A
        INC HL
        DJNZ .NSPC
        LD A,0
        LD (CSINDEX+9),A
        LD (CSINDEX+10),A
        LD (CSINDEX+11),A
        LD HL,CSPART
        LD A,(CSINDEX+8)
        LD B,A
.NCHAR:
        LD A,(HL)
        INC HL
        CP '.'
        JR Z,.NDOT
        LD C,A
        LD A,(CSINDEX+9)
        OR A
        JR NZ,.NEXTC
        LD A,(CSINDEX+10)
        INC A
        CP 9
        JP NC,.NFAIL
        LD (CSINDEX+10),A
        PUSH HL
        LD E,A
        DEC E
        LD D,0
        LD HL,CSFCB+1
        ADD HL,DE
        LD A,C
        LD (HL),A
        POP DE
        EX DE,HL
        JR .NCHARX
.NDOT:
        LD A,(CSINDEX+9)
        OR A
        JP NZ,.NFAIL
        LD A,1
        LD (CSINDEX+9),A
        JR .NCHARX
.NEXTC:
        LD A,(CSINDEX+11)
        INC A
        CP 4
        JP NC,.NFAIL
        LD (CSINDEX+11),A
        PUSH HL
        LD E,A
        DEC E
        LD D,0
        LD HL,CSFCB+9
        ADD HL,DE
        LD A,C
        LD (HL),A
        POP DE
        EX DE,HL
.NCHARX:
        DJNZ .NCHAR
        LD A,(CSINDEX+10)
        OR A
        JP Z,.NFAIL
        LD A,(CSINDEX+9)
        OR A
        JR Z,.NODOT
        LD A,(CSINDEX+11)
        OR A
        JP Z,.NFAIL
.NODOT:

        LD A,(CSINDEX+6)
        OR A
        JR Z,.NSAVE
        LD B,A
        LD HL,CSSEEN
.NCMP:
        LD DE,CSFCB
        LD C,12
        PUSH HL
.NCMPL:
        LD A,(DE)
        XOR (HL)
        JR NZ,.NCMIS
        INC DE
        INC HL
        DEC C
        JR NZ,.NCMPL
        POP HL
        LD A,5
        JP .NFAIL
.NCMIS:
        POP HL
        LD DE,12
        ADD HL,DE
        DJNZ .NCMP
.NSAVE:
        LD A,(CSINDEX+6)
        CP 32
        JP NC,.NFAIL
        LD B,A
        LD HL,CSSEEN
        OR A
        JR Z,.NSAVED
.NSKIP2:
        LD DE,12
        ADD HL,DE
        DJNZ .NSKIP2
.NSAVED:
        LD A,(CSINDEX+6)         ; The old count is this part's zero-based ordinal.
        LD (CSPARTNO),A
        LD A,1
        LD (CSPEND),A
        LD DE,CSFCB
        EX DE,HL
        LD BC,12
        LDIR
        LD A,(CSINDEX+6)
        INC A
        LD (CSINDEX+6),A
        LD A,128
        LD (CSINDEX+12),A
        XOR A
        LD (CSINDEX+13),A
        LD DE,CSFCB
        LD C,15
        CALL CSBDOS
        CP 255
        JR NZ,.NOK
        LD A,5
        JP .NFAIL
.NOK:  LD A,1
        LD (CSINDEX+3),A
        OR A
        RET
.NFAIL:
        LD A,(CSERROR)
        OR A
        JR NZ,.NERR
        LD A,5
        LD (CSERROR),A
.NERR:
        LD A,1
        LD (CSDONE),A
        SCF
        RET

; ----------------------------------------------------------------------------
