
; CTWRITE clobbers BC, so pointer and count live in private words.
N4STREAM:
        LD (N4PTR),HL
        LD (N4LEFT),BC
N4STLOOP:
        LD BC,(N4LEFT)
        LD A,B
        OR C
        JR Z,N4STDONE
        LD HL,(N4PTR)
        LD A,(HL)
        INC HL
        LD (N4PTR),HL
        CALL CTWRITE
        RET C
        LD HL,(N4LEFT)
        DEC HL
        LD (N4LEFT),HL
        JR N4STLOOP
N4STDONE:
        XOR A
        RET

; The CP/M command FCB supplies drive and eight-character basename.  Keep the
; prefix and replace only the three-character extension for each output.
N4FCBN:
        LD HL,005CH
        LD DE,N4FCB
        LD BC,9
        LDIR
        LD HL,N4FCB+9
        LD (HL),'N'
        INC HL
        LD (HL),'O'
        INC HL
        LD (HL),'B'
        RET
N4FCBC:
        LD HL,N4FCB+9
        LD (HL),'C'
        INC HL
        LD (HL),'O'
        INC HL
        LD (HL),'M'
        RET

;-------------------------------------------------------------------------
;  Result message and object checksum
;-------------------------------------------------------------------------

N4PATCH:
        LD HL,N4OBJ
        LD DE,N4MSGOF
        ADD HL,DE
        LD B,N4MSGLN
        XOR A
N4CLRMSG:
        LD (HL),A
        INC HL
        DJNZ N4CLRMSG
        LD A,(N4RTAG)
        CP 3
        JP Z,N4INT
        JP N4F16

; Signed16 decimal output, using the same bounded subtraction policy as the
; runtime printer but writing into the object image rather than BDOS.
N4INT:
        LD HL,(N4RVAL)
        PUSH HL
        LD DE,N4OBJ
        LD HL,N4MSGOF
        ADD HL,DE
        EX DE,HL
        POP HL
        BIT 7,H
        JR Z,N4IPOS
        LD A,'-'
        LD (DE),A
        INC DE
        XOR A
        SUB L
        LD L,A
        XOR A
        SBC A,H
        LD H,A
N4IPOS:
        LD (N4PTR),DE
        XOR A
        LD (N4START),A
        LD DE,10000
        CALL N4PLACE
        LD DE,1000
        CALL N4PLACE
        LD DE,100
        CALL N4PLACE
        LD DE,10
        CALL N4PLACE
        LD A,1
        LD (N4START),A
        LD DE,1
        CALL N4PLACE
        JP N4MSGEND

N4PLACE:
        LD B,0
N4PLLOOP:
        OR A
        SBC HL,DE
        JR C,N4PLDONE
        INC B
        JR N4PLLOOP
N4PLDONE:
        ADD HL,DE
        LD A,B
        OR A
        JR NZ,N4PLOUT
        LD A,(N4START)
        OR A
        RET Z
N4PLOUT:
        LD A,1
        LD (N4START),A
        LD A,B
        ADD A,'0'
        PUSH HL
        LD HL,(N4PTR)
        LD (HL),A
        INC HL
        LD (N4PTR),HL
        POP HL
        RET

; Binary16 values use a four-digit hexadecimal payload.  This is deliberately
; lossless and keeps N4's result printer independent of a decimal formatter.
N4F16:
        LD DE,N4OBJ
        LD HL,N4MSGOF
        ADD HL,DE
        EX DE,HL
        LD A,'F'
        LD (DE),A
        INC DE
        LD A,'1'
        LD (DE),A
        INC DE
        LD A,'6'
        LD (DE),A
        INC DE
        LD A,':'
        LD (DE),A
        INC DE
        LD (N4PTR),DE
        LD HL,(N4RVAL)
        LD A,H
        CALL N4BYTE
        LD HL,(N4RVAL)
        LD A,L
        CALL N4BYTE
N4MSGEND:
        LD HL,(N4PTR)
        LD (HL),13
        INC HL
        LD (HL),10
        INC HL
        LD (HL),'$'
        RET

N4BYTE:
        PUSH AF
        SRL A
        SRL A
        SRL A
        SRL A
        CALL N4NIB
        POP AF
        AND 15
        JP N4NIB
N4NIB:
        CP 10
        JR C,N4DIG
        ADD A,7
N4DIG:
        ADD A,'0'
        LD HL,(N4PTR)
        LD (HL),A
        INC HL
        LD (N4PTR),HL
        RET

; CRC-16/CCITT-FALSE covers every byte through the COMMIT header and payload,
; excluding only the two checksum bytes at the end of the template.
N4CRC:
        LD HL,N4OBJ
        LD DE,0FFFFH
        LD BC,N4CRCLN
        CALL N4CRSEG
        PUSH DE
        LD HL,N4OBJ
        LD BC,N4CRCOF
        ADD HL,BC
        POP DE
        LD (HL),E
        INC HL
        LD (HL),D
        RET

; Shared CRC segment loop.  DE is the running CRC, HL the input and BC the
; remaining byte count; N8 uses the same primitive for its split object.
N4CRSEG:
N4CRBY:
        LD A,B
        OR C
        RET Z
        LD A,(HL)
        INC HL
        XOR D
        LD D,A
        LD A,8
        LD (N4BITS),A
N4CRCBIT:
        SLA E
        RL D
        JR NC,N4CRCNOX
        LD A,D
        XOR 10H
        LD D,A
        LD A,E
        XOR 21H
        LD E,A
N4CRCNOX:
        LD A,(N4BITS)
        DEC A
        LD (N4BITS),A
        JR NZ,N4CRCBIT
        DEC BC
        JR N4CRBY

;-------------------------------------------------------------------------
;  Compiler state and fixed input tables
;-------------------------------------------------------------------------

N4CODE:   DB 0
N4OPEN:   DB 0
N4OP:     DB 0
N4LTAG:   DB 0
N4RTAG:   DB 0
N4LVAL:   DW 0
N4RVAL:   DW 0
N4PTR:    DW 0
N4LEFT:   DW 0
N4START:  DB 0
N4BITS:   DB 0
N4FCB:    DS 36

N4SYMCXT:
          DW N4SYMS,16,N4SYMPL,512,0,0
          DB 0,0
N4STRCXT:
          DW N4STRS,16,N4STRPL,512,0,0
          DB 1,0
N4SYMS:   DS 48
N4STRS:   DS 64
N4SYMPL:  DS 512
N4STRPL:  DS 512

N4OKTXT:  DB "COMPILED",13,10,"$"
N4BADTXT: DB "COMPILE ERROR",13,10,"$"
N4IOTXT:  DB "SOURCE I/O ERROR",13,10,"$"
N4OUTTXT: DB "OUTPUT ERROR",13,10,"$"
N4MEMTXT: DB "INSUFFICIENT MEMORY",13,10,"$"
