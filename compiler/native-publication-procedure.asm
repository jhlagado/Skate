;=============================================================================
;  Recoverable CP/M publication for N8/N9
;=============================================================================
;
;  The emitter stages the NOBJ and COM files under temporary names, then
;  replaces the previous pair through CP/M rename operations.  Every BDOS
;  failure rolls back the pair and removes stale stage files.
;=============================================================================

N8EMIT:
        CALL .S
        JP C,.E
        CALL N8PATCH
        JP C,.E
        CALL N8PRT
        JP C,.E
        CALL N8MSET
        JP C,.E
        CALL N8VALID
        JP C,.E
        CALL N8CRC
        CALL N8RSTR
        JP C,.E
        CALL .NS
        LD HL,N4FCB
        CALL CTOPENW
        JP C,.E
        CALL N8STOBJ
        JP C,.E
        CALL CTCLOSEW
        JP C,.E
        CALL .CS
        LD HL,N4FCB
        CALL CTOPENW
        JP C,.E
        ; The standalone COM remains a static-result compatibility image.
        ; Its message printer is kept separate from the provider-linked NOBJ
        ; section, whose entry now runs the descriptor-driven startup.
        LD HL,N4COM
        LD BC,N4COMLEN
        CALL N4STREAM
        JP C,.E
        LD HL,N8MSGBUF
        LD BC,(N8MLEN)
        CALL N4STREAM
        JP C,.E
        CALL CTCLOSEW
        JP C,.E
        CALL .P
        JP C,.E
        XOR A
        RET

; N8 has the same transaction, with private labels in its own scope.
.S:
        CALL .R
        JP C,.SE
        XOR A
        LD (.BN),A
        LD (.BC),A
        LD (.NI),A
        LD (.CI),A
        CALL .NS
        LD HL,N4FCB
        CALL CTDELETE
        JR C,.SE
        CALL .CS
        LD HL,N4FCB
        CALL CTDELETE
        JR C,.SE
        XOR A
        RET
.SE:
        SCF
        RET

; Restore any pair left in the recovery names by an interrupted publication.
; A missing recovery file is normal; an open/close failure leaves it in place
; for the next invocation instead of deleting a valid final file.
.R:
        CALL N4FCBN
        CALL .PR
        LD HL,.F2
        CALL CTOPENR
        JR C,.RN
        CALL CTCLOSER
        JR C,.RF
        CALL N4FCBN
        LD HL,N4FCB
        CALL CTDELETE
        JP C,.RF
        CALL .PR
        LD HL,.F2
        LD DE,N4FCB
        CALL CTRENAME
        JP C,.RF
.RN:
        CALL N4FCBC
        CALL .PC
        LD HL,.F2
        CALL CTOPENR
        JR C,.RC
        CALL CTCLOSER
        JR C,.RF
        CALL N4FCBC
        LD HL,N4FCB
        CALL CTDELETE
        JP C,.RF
        CALL .PC
        LD HL,.F2
        LD DE,N4FCB
        CALL CTRENAME
.RC:
        XOR A
        RET
.RF:
        SCF
        RET
.P:
        XOR A
        LD (.BN),A
        LD (.BC),A
        LD (.NI),A
        LD (.CI),A
        CALL N4FCBN
        CALL .PR
        LD HL,N4FCB
        LD DE,.F2
        CALL CTRENAME
        JR C,.NO
        LD A,1
        LD (.BN),A
.NO:
        CALL N4FCBC
        CALL .PC
        LD HL,N4FCB
        LD DE,.F2
        CALL CTRENAME
        JR C,.NC
        LD A,1
        LD (.BC),A
.NC:
        CALL .NS
        CALL .FN
        LD HL,N4FCB
        LD DE,.F2
        CALL CTRENAME
        JP C,.F
        LD A,1
        LD (.NI),A
        CALL .CS
        CALL .FC
        LD HL,N4FCB
        LD DE,.F2
        CALL CTRENAME
        JP C,.F
        LD A,1
        LD (.CI),A
        CALL .PR
        LD HL,.F2
        CALL CTDELETE
        CALL .PC
        LD HL,.F2
        CALL CTDELETE
        CALL .S
        RET
.F:
        CALL .B
        SCF
        RET
.B:
        LD A,(.CI)
        OR A
        JR Z,.BNC
        CALL N4FCBC
        LD HL,N4FCB
        CALL CTDELETE
.BNC:
        LD A,(.NI)
        OR A
        JR Z,.BNB
        CALL N4FCBN
        LD HL,N4FCB
        CALL CTDELETE
.BNB:
        LD A,(.BC)
        OR A
        JR Z,.BNC2
        CALL .PC
        CALL N4FCBC
        LD HL,.F2
        LD DE,N4FCB
        CALL CTRENAME
.BNC2:
        LD A,(.BN)
        OR A
        JP Z,.BST
        CALL .PR
        CALL N4FCBN
        LD HL,.F2
        LD DE,N4FCB
        CALL CTRENAME
.BST:
        CALL .S
        RET
.NS:
        CALL .X
        LD HL,N4FCB+9
        LD (HL),'N'
        INC HL
        LD (HL),'B'
        INC HL
        LD (HL),'S'
        RET
.CS:
        CALL .X
        LD HL,N4FCB+9
        LD (HL),'C'
        INC HL
        LD (HL),'B'
        INC HL
        LD (HL),'S'
        RET
.PR:
        CALL .Y
        LD HL,.F2+9
        LD (HL),'N'
        INC HL
        LD (HL),'P'
        INC HL
        LD (HL),'R'
        RET
.PC:
        CALL .Y
        LD HL,.F2+9
        LD (HL),'C'
        INC HL
        LD (HL),'P'
        INC HL
        LD (HL),'R'
        RET
.FN:
        CALL .Y
        LD HL,.F2+9
        LD (HL),'N'
        INC HL
        LD (HL),'O'
        INC HL
        LD (HL),'B'
        RET
.FC:
        CALL .Y
        LD HL,.F2+9
        LD (HL),'C'
        INC HL
        LD (HL),'O'
        INC HL
        LD (HL),'M'
        RET
.X:
        LD HL,005CH
        LD DE,N4FCB
        LD BC,9
        LDIR
        RET
.Y:
        LD HL,N4FCB
        LD DE,.F2
        LD BC,12
        LDIR
        RET
.E:
        CALL .B
        LD A,4
        LD (N4CODE),A
        SCF
        RET
.BN: DB 0
.BC: DB 0
.NI: DB 0
.CI: DB 0
.F2: DS 36
