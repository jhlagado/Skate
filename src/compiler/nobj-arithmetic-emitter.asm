;=============================================================================
;  NOBJ arithmetic-output emitter
;=============================================================================
;
;  The compiler publishes one checked NOBJ object whose image is also the
;  standalone COM program.  The image contains the numeric dispatcher and
;  formatter; this module patches only the operator and two source operands.
;  The generated program therefore produces the answer after compilation.
;=============================================================================

; Stream BC bytes from HL through the CP/M transport.  CTWRITE clobbers BC,
; so the pointer and remaining count live in private words.
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

; Build the final NOBJ and COM FCBs from the command-tail basename.
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

; Patch the generated image with the parsed expression.  Numeric services use
; tag 3 for exact integers and tag 0 for binary16 values.  The operator byte is
; compacted from its source character so the image has no parser dependency.
N4PATCH:
        LD A,(N4OP)
        CP '-'
        JR Z,N4PSUB
        CP '*'
        JR Z,N4PMUL
        CP '/'
        JR Z,N4PDIV
        XOR A
        JR N4POK
N4PSUB:
        LD A,1
        JR N4POK
N4PMUL:
        LD A,2
        JR N4POK
N4PDIV:
        LD A,3
N4POK:
        LD (C1ROPA),A
        LD A,(N4LTAG)
        LD (C1RLTA),A
        LD HL,(N4LVAL)
        LD (C1RLVA),HL
        LD A,(N4RTAG)
        LD (C1RRTA),A
        LD HL,(N4RVAL)
        LD (C1RRVA),HL
        RET

; CRC-16/CCITT-FALSE covers every byte through the COMMIT header and payload,
; excluding only the two checksum bytes at the end of the generated object.
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

; Absolute addresses inside the serialized NOBJ image.  The image offset points at the
; six-byte IMAGE header's payload, so the same bytes stream directly to COM.
C1ROPA EQU N4OBJ+N4IMGOF+C1ROPOF
C1RLTA EQU N4OBJ+N4IMGOF+C1RLTOF
C1RLVA EQU N4OBJ+N4IMGOF+C1RLVOF
C1RRTA EQU N4OBJ+N4IMGOF+C1RRTOF
C1RRVA EQU N4OBJ+N4IMGOF+C1RRVOF

N4CODE:   DB 0
N4OPEN:   DB 0
N4OP:     DB 0
N4LTAG:   DB 0
N4RTAG:   DB 0
N4LVAL:   DW 0
N4RVAL:   DW 0
N4PTR:    DW 0
N4LEFT:   DW 0
N4BITS:   DB 0
N4FCB:    DS 36

; Reader contexts and diagnostics retained by the current command contract.
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
