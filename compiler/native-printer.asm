;-------------------------------------------------------------------------
;  Bounded native result printer
;-------------------------------------------------------------------------
;
;  N8PRT writes one Scheme value into the result message.  It is deliberately
;  separate from N4PATCH: the scalar patcher remains the compact N4/N5 path,
;  while this routine owns structural syntax and length-counted output.
;  N8SERDEP bounds nested pair traversal and N4LEFT bounds message bytes.
;-------------------------------------------------------------------------

N8PRT:
        LD HL,N8MSGBUF
        LD (N4PTR),HL
        LD HL,N4MSGLN
        LD (N4LEFT),HL
        LD HL,0
        LD (N8MLEN),HL
        XOR A
        LD (N8SERDEP),A
        LD A,1
        LD (N8PMODE),A
        LD A,(N4RTAG)
        LD HL,(N4RVAL)
        CALL N8PRVAL
        RET C
        LD A,13
        CALL N8MBYTE
        RET C
        LD A,10
        JP N8MBYTE

; Print A:HL as the canonical write representation.
N8PRVAL:
        LD (N8PVAL),HL
        CP 3
        JP Z,N8PINT
        OR A
        JP Z,N8PZERO
        CP 1
        JP Z,N8PREF
        JP N8PMARK

N8PZERO:
        LD A,H
        CP 0FFH
        JP Z,N8PCHAR
        CP 0FEH
        JP NZ,N8PHEX
        LD A,L
        OR A
        JP Z,N8PFALSE
        CP 1
        JP Z,N8PTRUE
        CP 2
        JP Z,N8PNIL
        CP 3
        JP Z,N8PEOF
        CP 4
        JP Z,N8PUNSP
        JP N8PHEX

N8PREF:
        LD A,H
        AND 0E0H
        JR Z,N8PPRT
        CP 20H
        JP Z,N8PSYM
        CP 80H
        JP Z,N8PSTR
        JP N8PMARK

N8PPRT:
        LD A,'('
        CALL N8MBYTE
        RET C
        LD HL,(N8PVAL)
        CALL N8PLIST
        RET C
        LD A,')'
        JP N8MBYTE

N8PLIST:
        LD A,(N8SERDEP)
        INC A
        CP 64
        JP NC,N8PFAIL
        LD (N8SERDEP),A
        CALL N8PAIRAD
        JP C,N8PFAIL
        LD (N8PPREC),HL
        LD A,(HL)
        LD (N8PCART),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (N8PCARV),HL
        LD HL,(N8PPREC)
        LD DE,4
        ADD HL,DE
        LD A,(HL)
        LD (N8PCDRT),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (N8PCDRV),HL
        LD A,(N8PCDRT)
        PUSH AF
        LD HL,(N8PCDRV)
        PUSH HL
        LD A,(N8PCART)
        LD HL,(N8PCARV)
        CALL N8PRVAL
        JR C,N8PLERR
        POP HL
        LD (N8PCDRV),HL
        POP AF
        LD (N8PCDRT),A
        LD A,(N8PCDRT)
        OR A
        JR NZ,N8PREFCD
        LD HL,(N8PCDRV)
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JR Z,N8PLDONE
N8PREFCD:
        LD A,(N8PCDRT)
        CP 1
        JR NZ,N8PDOT
        LD HL,(N8PCDRV)
        LD A,H
        AND 0E0H
        JR NZ,N8PDOT
        LD A,' '
        CALL N8MBYTE
        RET C
        LD HL,(N8PCDRV)
        CALL N8PLIST
        RET C
N8PLDONE:
        LD A,(N8SERDEP)
        DEC A
        LD (N8SERDEP),A
        XOR A
        RET
N8PDOT:
        LD A,' '
        CALL N8MBYTE
        RET C
        LD A,'.'
        CALL N8MBYTE
        RET C
        LD A,' '
        CALL N8MBYTE
        RET C
        LD A,(N8PCDRT)
        LD HL,(N8PCDRV)
        CALL N8PRVAL
        RET C
        JR N8PLDONE
N8PLERR:
        POP HL
        POP AF
N8PFAIL:
        SCF
        RET

N8PSYM:
        CALL N8PIDX
        RET C
        LD IX,(RSYMCTX)
        LD L,(IX+8)
        LD H,(IX+9)
        LD DE,(N8PID)
        OR A
        SBC HL,DE
        JR C,N8PFAIL
        JR Z,N8PFAIL
        LD HL,(N8PID)
        LD DE,(N8PID)
        ADD HL,HL
        ADD HL,DE
        LD E,(IX+0)
        LD D,(IX+1)
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD C,(HL)
        LD B,0
        LD L,(IX+4)
        LD H,(IX+5)
        ADD HL,DE
        JP N8PBYTES

N8PSTR:
        CALL N8PIDX
        RET C
        LD IX,(RSTRCTX)
        LD L,(IX+8)
        LD H,(IX+9)
        LD DE,(N8PID)
        OR A
        SBC HL,DE
        JR C,N8PFAIL
        JR Z,N8PFAIL
        LD HL,(N8PID)
        ADD HL,HL
        ADD HL,HL
        LD E,(IX+0)
        LD D,(IX+1)
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD C,(HL)
        INC HL
        LD B,(HL)
        LD L,(IX+4)
        LD H,(IX+5)
        ADD HL,DE
        LD (N8PPTR),HL
        LD (N8PLEFT),BC
        LD A,(N8PMODE)
        OR A
        JP Z,N8PBYTES
        LD A,'"'
        CALL N8MBYTE
        RET C
N8PSTLP:
        LD BC,(N8PLEFT)
        LD A,B
        OR C
        JR Z,N8PSTEND
        LD HL,(N8PPTR)
        LD A,(HL)
        INC HL
        LD (N8PPTR),HL
        CP '"'
        JR Z,N8PSTESC
        CP 92
        JR NZ,N8PSTBYT
N8PSTESC:
        PUSH AF
        LD A,92
        CALL N8MBYTE
        JR C,N8PSTCF
        POP AF
        JR N8PSTBYT
N8PSTCF:
        POP AF
        SCF
        RET
N8PSTBYT:
        CALL N8MBYTE
        RET C
        LD HL,(N8PLEFT)
        DEC HL
        LD (N8PLEFT),HL
        JR N8PSTLP
N8PSTEND:
        LD A,'"'
        JP N8MBYTE

; Check and decode the thirteen-bit interner identity in N8PVAL.
N8PIDX:
        LD HL,(N8PVAL)
        LD A,H
        AND 01FH
        LD H,A
        LD (N8PID),HL
        XOR A
        RET

; Emit a bounded byte span.  HL is the source and BC its 16-bit length.
N8PBYTES:
        LD (N8PPTR),HL
        LD (N8PLEFT),BC
N8PBYLP:
        LD BC,(N8PLEFT)
        LD A,B
        OR C
        JR Z,N8PBYDN
        LD HL,(N8PPTR)
        LD A,(HL)
        INC HL
        LD (N8PPTR),HL
        CALL N8MBYTE
        RET C
        LD HL,(N8PLEFT)
        DEC HL
        LD (N8PLEFT),HL
        JR N8PBYLP
N8PBYDN:
        XOR A
        RET

N8PINT:
        LD HL,(N8PVAL)
        BIT 7,H
        JR Z,N8IPOS
        LD A,'-'
        CALL N8MBYTE
        RET C
        XOR A
        SUB L
        LD L,A
        XOR A
        SBC A,H
        LD H,A
N8IPOS:
        LD (N8PVAL),HL
        XOR A
        LD (N8PFLAG),A
        LD DE,10000
        CALL N8PLACE
        LD DE,1000
        CALL N8PLACE
        LD DE,100
        CALL N8PLACE
        LD DE,10
        CALL N8PLACE
        LD A,1
        LD (N8PFLAG),A
        LD DE,1
        JP N8PLACE

N8PLACE:
        LD HL,(N8PVAL)
        LD B,0
N8PLP:
        OR A
        SBC HL,DE
        JR C,N8PLD
        INC B
        JR N8PLP
N8PLD:
        ADD HL,DE
        LD (N8PVAL),HL
        LD A,B
        OR A
        JR NZ,N8PLOUT
        LD A,(N8PFLAG)
        OR A
        RET Z
N8PLOUT:
        LD A,1
        LD (N8PFLAG),A
        LD A,B
        ADD A,'0'
        JP N8MBYTE

N8PCHAR:
        LD A,'#'
        CALL N8MBYTE
        RET C
        LD A,92
        CALL N8MBYTE
        RET C
        LD HL,(N8PVAL)
        LD A,L
        JP N8MBYTE
N8PFALSE:
        LD A,'#'
        CALL N8MBYTE
        RET C
        LD A,'f'
        JP N8MBYTE
N8PTRUE:
        LD A,'#'
        CALL N8MBYTE
        RET C
        LD A,'t'
        JP N8MBYTE
N8PNIL:
        LD A,'('
        CALL N8MBYTE
        RET C
        LD A,')'
        JP N8MBYTE
N8PEOF:
        LD HL,N8EOFTXT
        LD BC,6
        JP N8PBYTES
N8PUNSP:
        LD HL,N8UNSTXT
        LD BC,14
        JP N8PBYTES
N8PMARK:
        LD HL,N8MRKTXT
        LD BC,3
        JP N8PBYTES
N8PHEX:
        LD A,'F'
        CALL N8MBYTE
        RET C
        LD A,'1'
        CALL N8MBYTE
        RET C
        LD A,'6'
        CALL N8MBYTE
        RET C
        LD A,':'
        CALL N8MBYTE
        RET C
        LD HL,(N8PVAL)
        LD A,H
        CALL N8PBYTE
        LD HL,(N8PVAL)
        LD A,L
        JP N8PBYTE

N8PBYTE:
        PUSH AF
        SRL A
        SRL A
        SRL A
        SRL A
        CALL N8PNIB
        POP AF
        AND 15
N8PNIB:
        CP 10
        JR C,N8PNDIG
        ADD A,7
N8PNDIG:
        ADD A,'0'
        JP N8MBYTE

; Append one byte and reject a full 128-byte message before writing.
N8MBYTE:
        PUSH AF
        LD HL,(N4LEFT)
        LD A,H
        OR L
        JR Z,N8MBFULL
        DEC HL
        LD (N4LEFT),HL
        LD HL,(N4PTR)
        POP AF
        LD (HL),A
        INC HL
        LD (N4PTR),HL
        LD HL,(N8MLEN)
        INC HL
        LD (N8MLEN),HL
        OR A
        RET
N8MBFULL:
        POP AF
        SCF
        RET
