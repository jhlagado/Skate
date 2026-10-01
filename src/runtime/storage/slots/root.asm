; Runtime tracing of active activation slots.
; Entry point: SRTSROOT.
SRTSROOT:
        LD (SRTSADR),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTSFLG),A
        AND SRTSPROM
        JR NZ,SRTSRTP
        LD A,(SRTSFLG)
        AND 1
        RET Z
        LD HL,(SRTSADR)
        INC HL
        INC HL
        LD A,(HL)
        LD HL,(SRTSADR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP SRTMVALU
SRTSRTP:
        LD HL,(SRTSADR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        RET Z
        EX DE,HL
        JP SRTBMARK
