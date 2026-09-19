; Standalone runtime for one arithmetic expression.
;
; The compiler patches C1ROP, C1RLT, C1RLV, C1RRT, and C1RRV before it writes
; the object.  At run time the dispatcher selects the numeric operation,
; formats either a signed integer or a binary16 result, and returns to CP/M.
; The fixed stack limit is shared with the compiler's guarded memory map.
;
; Numeric ABI on entry to NADD/NSUB/NMUL/NDIV:
;   A = left value tag, B = right value tag, HL = left payload, DE = right.
; The service returns A = result tag and HL = result payload, with carry set
; for overflow, invalid input, or division by zero.
ORG 0100H

C1RSTART:
        LD SP,8000H               ; Private runtime stack below the CP/M TPA ceiling.
        ; C1ROP is the compact operation code written by the emitter:
        ; 0 add, 1 subtract, 2 multiply, 3 divide.
        LD A,(C1ROP)
        CP 0
        JP Z,C1RADD
        CP 1
        JP Z,C1RSUB
        CP 2
        JP Z,C1RMUL
        CP 3
        JP Z,C1RDIV
        JP C1RERR

; Each operation reloads the patched operands because the numeric routines may
; change their working registers while computing the result.
C1RADD:
        LD A,(C1RRT)
        LD B,A
        LD A,(C1RLT)
        LD HL,(C1RLV)
        LD DE,(C1RRV)
        CALL NADD
        JP C,C1RERR
        JP C1RPRINT
C1RSUB:
        LD A,(C1RRT)
        LD B,A
        LD A,(C1RLT)
        LD HL,(C1RLV)
        LD DE,(C1RRV)
        CALL NSUB
        JP C,C1RERR
        JP C1RPRINT
C1RMUL:
        LD A,(C1RRT)
        LD B,A
        LD A,(C1RLT)
        LD HL,(C1RLV)
        LD DE,(C1RRV)
        CALL NMUL
        JP C,C1RERR
        JP C1RPRINT
C1RDIV:
        LD A,(C1RRT)
        LD B,A
        LD A,(C1RLT)
        LD HL,(C1RLV)
        LD DE,(C1RRV)
        CALL NDIV
        JP C,C1RERR

; Store the numeric result before choosing its text representation.  Tag 3 is
; an exact signed integer; every other successful tag in this product is the
; two-byte binary16 representation.
C1RPRINT:
        LD (C1RRES),HL
        LD (C1RREST),A
        CP 3
        JP Z,C1RINT
        JP C1RF16

C1RINT:
        ; Convert the signed payload to magnitude, retaining the minus sign.
        LD HL,(C1RRES)
        LD DE,C1RMSG
        BIT 7,H
        JR Z,C1RIPOS
        LD A,'-'
        LD (DE),A
        INC DE
        XOR A
        SUB L
        LD L,A
        XOR A
        SBC A,H
        LD H,A
C1RIPOS:
        LD (C1RPTR),DE
        XOR A
        LD (C1RBEG),A
        LD DE,10000
        CALL C1RPLACE
        LD DE,1000
        CALL C1RPLACE
        LD DE,100
        CALL C1RPLACE
        LD DE,10
        CALL C1RPLACE
        LD A,1
        LD (C1RBEG),A
        LD DE,1
        CALL C1RPLACE
        JP C1RMSGED

C1RPLACE:
        ; Subtract one decimal place until the digit would become negative.
        ; C1RBEG suppresses leading zeroes but always permits the units digit.
        LD B,0
C1RPLP:
        OR A
        SBC HL,DE
        JR C,C1RPLDN
        INC B
        JR C1RPLP
C1RPLDN:
        ADD HL,DE
        LD A,B
        OR A
        JR NZ,C1RPLOUT
        LD A,(C1RBEG)
        OR A
        RET Z
C1RPLOUT:
        LD A,1
        LD (C1RBEG),A
        LD A,B
        ADD A,'0'
        PUSH HL
        LD HL,(C1RPTR)
        LD (HL),A
        INC HL
        LD (C1RPTR),HL
        POP HL
        RET

C1RF16:
        ; Binary16 output is intentionally diagnostic hexadecimal (F16:hhhh),
        ; so formatting it never needs a floating-point conversion routine.
        LD DE,C1RMSG
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
        LD (C1RPTR),DE
        LD HL,(C1RRES)
        LD A,H
        CALL C1RBYTE
        LD HL,(C1RRES)
        LD A,L
        CALL C1RBYTE
C1RMSGED:
        LD HL,(C1RPTR)
        LD (HL),13
        INC HL
        LD (HL),10
        INC HL
        LD (HL),'$'
        LD DE,C1RMSG
        LD C,9
        CALL 5
        JP 0

C1RBYTE:
        ; Emit the high nibble first, then the low nibble.
        PUSH AF
        SRL A
        SRL A
        SRL A
        SRL A
        CALL C1RNIB
        POP AF
        AND 15
        JP C1RNIB
C1RNIB:
        CP 10
        JR C,C1RDIG
        ADD A,7
C1RDIG:
        ADD A,'0'
        LD HL,(C1RPTR)
        LD (HL),A
        INC HL
        LD (C1RPTR),HL
        RET

C1RERR:
        ; All runtime arithmetic failures share a short CP/M console message.
        LD DE,C1RERRM
        LD C,9
        CALL 5
        JP 0

; The compiler patches these five fields in the checked payload.  The remaining
; words are runtime scratch and the CP/M function-9 message buffer.
C1ROP:  DB 0
C1RLT:  DB 3
C1RLV:  DW 0
C1RRT:  DB 3
C1RRV:  DW 0
C1RRES: DW 0
C1RREST: DB 0
C1RPTR: DW 0
C1RBEG: DB 0
C1RMSG: DS 16
C1RERRM: DB "RUNTIME ERROR",13,10,"$"
