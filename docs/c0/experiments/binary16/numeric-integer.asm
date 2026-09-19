; Integer-only ABI-2 numeric provider used for the size comparison.
;
; The vector names and call shapes are deliberately the same as the real
; numeric module.  Tag 3 is the exact signed word.  Binary16 tag 0 is rejected
; by NCLASS, and NDIV reports the unsupported floating result as status 2.
; This keeps the provider/link contract visible while making the omission
; explicit: the integer image is not a disguised binary16 implementation.
;
; Entry contract: A/HL is the left value, B/DE is the right value.  NCLASS and
; NNEG are unary.  Successful arithmetic returns A=3, HL=the exact result and
; carry clear.  NCMP returns A=0 and HL=-1, 0 or +1.  Failures return the
; original left value with A=1 (type) or A=2 (exact overflow/unsupported div).
; BC/DE/flags may be clobbered; IX/IY and SP are preserved.

NCLASS:
        CP 3
        JR Z,NINTOK
        LD A,1
        SCF
        RET

NINTOK:
        OR A
        RET

NIGD:
        LD A,3
        OR A
        RET

NNEG:
        LD (NORIGVAL),HL
        CALL NCLASS
        RET C
        LD A,H
        CP 80H
        JR NZ,NNEGDO
        LD A,L
        OR A
        JP Z,NOVERFLW
NNEGDO:
        CALL NWORDNEG
        JP NIGD

NADD:
        LD C,0
        JP NINTBIN
NSUB:
        LD C,1
        JP NINTBIN
NMUL:
        LD C,2
NINTBIN:
        LD (NARGTAG),A
        LD A,C
        LD (NOPCODE),A
        CALL NPREPARE
        RET C
        LD A,(NOPCODE)
        OR A
        JP Z,NINTADD
        CP 1
        JP Z,NINTSUB
        JP NINTMUL

; Save both values before validation so a type or range error restores left.
NPREPARE:
        LD (NORIGVAL),HL
        LD (NLEFTWK),HL
        LD (NRIGHTWK),DE
        LD A,(NARGTAG)
        LD (NLEFTTG),A
        LD A,B
        LD (NRIGHTTG),A
        LD A,(NLEFTTG)
        CALL NCLASS
        JR C,NINTTYPE
        LD A,(NRIGHTTG)
        EX DE,HL
        CALL NCLASS
        EX DE,HL
        JR C,NINTTYPE
        RET

NINTTYPE:
        LD HL,(NORIGVAL)
        LD A,1
        SCF
        RET

NINTADD:
        LD HL,(NLEFTWK)
        LD DE,(NRIGHTWK)
        LD A,H
        XOR D
        AND 80H
        LD (NSIGNDF),A
        ADD HL,DE
        LD A,(NSIGNDF)
        OR A
        JP NZ,NIGD
        LD A,(NLEFTWK+1)
        XOR H
        AND 80H
        JP NZ,NOVERFLW
        JP NIGD

NINTSUB:
        LD HL,(NLEFTWK)
        LD DE,(NRIGHTWK)
        LD A,H
        XOR D
        AND 80H
        LD (NSIGNDF),A
        OR A
        SBC HL,DE
        LD A,(NSIGNDF)
        OR A
        JP Z,NIGD
        LD A,(NLEFTWK+1)
        XOR H
        AND 80H
        JP NZ,NOVERFLW
        JP NIGD

; Unsigned shift/add multiplication of absolute 16-bit operands.  The
; 32-bit product is retained until the signed range check, so overflow is
; rejected rather than silently truncated.
NINTMUL:
        LD HL,(NLEFTWK)
        LD DE,(NRIGHTWK)
        LD A,H
        XOR D
        AND 80H
        LD (NSIGN),A
        LD HL,(NLEFTWK)
        CALL NABS
        LD (NMCAND),HL
        XOR A
        LD (NMCAND+2),A
        LD (NMCAND+3),A
        LD HL,(NRIGHTWK)
        CALL NABS
        LD (NMULT),HL
        XOR A
        LD (NPROD),A
        LD (NPROD+1),A
        LD (NPROD+2),A
        LD (NPROD+3),A
        LD B,16
NMULLOOP:
        LD HL,(NMULT)
        BIT 0,L
        JR Z,NMULNOS
        LD HL,(NPROD)
        LD DE,(NMCAND)
        ADD HL,DE
        LD (NPROD),HL
        JR NC,NMULHIGH
        LD HL,(NPROD+2)
        INC HL
        LD (NPROD+2),HL
NMULHIGH:
        LD HL,(NPROD+2)
        LD DE,(NMCAND+2)
        ADD HL,DE
        LD (NPROD+2),HL
NMULNOS:
        LD HL,(NMCAND)
        ADD HL,HL
        LD (NMCAND),HL
        LD HL,(NMCAND+2)
        RL L
        RL H
        LD (NMCAND+2),HL
        LD HL,(NMULT)
        SRL H
        RR L
        LD (NMULT),HL
        DJNZ NMULLOOP
        LD HL,(NPROD+2)
        LD A,H
        OR L
        JP NZ,NOVERFLW
        LD HL,(NPROD)
        LD A,(NSIGN)
        OR A
        JR Z,NMULPOS
        LD A,H
        CP 80H
        JR C,NMULNEG
        JP NZ,NOVERFLW
        LD A,L
        OR A
        JP NZ,NOVERFLW
NMULNEG:
        CALL NWORDNEG
        JP NIGD
NMULPOS:
        BIT 7,H
        JP NZ,NOVERFLW
        JP NIGD

; The integer image retains the NDIV vector but has no floating result type.
NDIV:
        LD (NARGTAG),A
        CALL NPREPARE
        RET C
        LD HL,(NORIGVAL)
        LD A,2
        SCF
        RET

NCMP:
        LD (NARGTAG),A
        CALL NPREPARE
        RET C
        LD HL,(NLEFTWK)
        LD DE,(NRIGHTWK)
        CALL NSIGNEDC
        XOR A
        RET

NSIGNEDC:
        LD A,H
        XOR D
        JP M,NCMPSIGN
        OR A
        SBC HL,DE
        JR Z,NCMPEQ
        JR C,NCMPL
        LD HL,1
        RET
NCMPSIGN:
        BIT 7,H
        JR Z,NCMPGT
NCMPL:
        LD HL,0FFFFH
        RET
NCMPGT:
        LD HL,1
        RET
NCMPEQ:
        LD HL,0
        RET

NABS:
        BIT 7,H
        RET Z
        CALL NWORDNEG
        RET

NWORDNEG:
        XOR A
        SUB L
        LD L,A
        SBC A,A
        SUB H
        LD H,A
        RET

NOVERFLW:
        LD HL,(NORIGVAL)
        LD A,2
        SCF
        RET

NEND:
NWORK:
NORIGVAL:   DW 0
NLEFTWK:    DW 0
NRIGHTWK:   DW 0
NLEFTTG:    DB 0
NRIGHTTG:   DB 0
NARGTAG:    DB 0
NOPCODE:    DB 0
NSIGNDF:    DB 0
NSIGN:      DB 0
NMCAND:     DS 4
NMULT:      DW 0
NPROD:      DS 4
NWEND:
