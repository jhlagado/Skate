; Standard numeric procedures: exactness, rounding, min and max, numeric
; predicates, gcd and lcm, expt and sqrt.  Part of the optional standard
; module; STD_DISP reaches them for primitive kinds 94 to 112.
;
; Each routine reads the argument packet and returns A:CHL through IX.
;
; This is its own module, loaded after the standard module only by programs
; that name one of these procedures; the generator records NUM_MOD's offset
; as the length of the core and standard modules together.
NUM_MOD:

; exact->inexact: an integer becomes the nearest float.
STD_INEX:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CP 9
        JP Z,STD_RET
        CP 3
        JP NZ,ERROR
        CALL F24_ITOF
        JP STD_RET

; inexact->exact: a float with an integral value becomes that integer.
STD_EXAC:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CP 3
        JP Z,STD_RET
        CP 9
        JP NZ,ERROR
        LD A,4                     ; Truncate, then require no fraction.
        CALL STD_PART
        JP C,ERROR                 ; Infinity or NaN.
        LD A,(STD_FRAC)
        OR A
        JP NZ,ERROR                ; Only an integral float has an exact value.
        CALL STD_INTV             ; The integer, beyond 2^16 included.
        JP C,ERROR
        LD A,3
        JP STD_RET

; floor, ceiling, truncate and round.  An integer is returned unchanged; a
; float becomes the integral float the mode selects, keeping its sign.
STD_FLOR:
        LD A,0
        JR STD_RND
STD_CEIL:
        LD A,1
        JR STD_RND
STD_TRNC:
        LD A,2
        JR STD_RND
STD_ROND:
        LD A,3
STD_RND:
        LD (STD_MODE),A
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CP 3
        JP Z,STD_RET
        CP 9
        JP NZ,ERROR
        LD A,(STD_MODE)
        CALL STD_PART
        JP C,STD_ARG0              ; Infinity and NaN are their own result.
        JP Z,STD_ARG0              ; Already integral: the argument itself.
        LD HL,(STD_N)              ; The rounded magnitude, at most 2^17.
        LD A,(STD_N+2)
        LD C,A
        OR H
        OR L
        JR Z,.ZERO
        LD A,(STD_NEG)
        OR A
        CALL NZ,NUM_INV
        CALL F24_ITOF
        JP STD_RET
.ZERO:
        LD A,(STD_NEG)             ; A zero result keeps the argument's sign.
        LD C,A
        LD A,9
        JP STD_RET

; Split the float A:CHL into the magnitude STD_N rounded by mode A (0 floor,
; 1 ceiling, 2 truncate, 3 round to even, 4 truncate) and its sign STD_NEG.
; STD_FRAC is nonzero when a fraction was dropped.  Z means the float was
; already integral (its magnitude may exceed 2^17, and STD_N is then not
; set); carry means infinity or NaN.  The float itself stays in STD_X.
STD_PART:
        LD (STD_MODE),A
        LD (STD_X),HL
        LD A,C
        LD (STD_X+2),A
        CALL F24_OPEN
        LD E,A                     ; The biased exponent U.
        LD A,D
        LD (STD_NEG),A
        XOR A
        LD (STD_FRAC),A
        LD A,B
        CP 2
        CCF
        RET C                      ; Infinity or NaN.
        OR A
        RET Z                      ; Zero is integral.
        LD A,95                    ; The value is M * 2^(U-95).
        SUB E
        JR Z,.WHOLE
        JR C,.WHOLE
        CP 18                      ; Every shift beyond 18 leaves only sticky.
        JR C,.SHIFT
        LD A,18
.SHIFT:
        LD B,A
        LD D,0                     ; D gathers sticky bits, E the last one out.
        LD E,0
.DROP:
        LD A,E
        OR D
        LD D,A
        LD E,0
        SRL C
        RR H
        RR L
        RL E                       ; E is the bit just shifted out.
        DJNZ .DROP
        LD A,D
        OR E
        LD (STD_FRAC),A
        JR Z,.WHOLE_N              ; No fraction: integral after all.
        LD A,(STD_MODE)
        OR A
        JR Z,.FLOOR
        DEC A
        JR Z,.CEIL
        DEC A
        JR Z,.STORE
        DEC A
        JR NZ,.STORE
        LD A,E                     ; Round: the half bit, then sticky or odd.
        OR A
        JR Z,.STORE
        LD A,D
        OR A
        JR NZ,.UP
        BIT 0,L
        JR NZ,.UP
        JR .STORE
.FLOOR:
        LD A,(STD_NEG)
        OR A
        JR NZ,.UP
        JR .STORE
.CEIL:
        LD A,(STD_NEG)
        OR A
        JR NZ,.STORE
.UP:
        LD DE,1
        ADD HL,DE
        LD A,C
        ADC A,0
        LD C,A
.STORE:
        LD (STD_N),HL
        LD A,C
        LD (STD_N+2),A
        LD A,1                     ; NZ, carry clear: a fraction was handled.
        OR A
        RET
.WHOLE_N:
        LD (STD_N),HL
        LD A,C
        LD (STD_N+2),A
.WHOLE:
        XOR A                      ; Z, carry clear: integral.
        RET

; The integer value of the integral float in STD_X, in C:HL; carry when it
; lies beyond the integer range.
STD_INTV:
        LD HL,(STD_X)
        LD A,(STD_X+2)
        LD C,A
        LD A,9
        JP F24_FTOI

; Return the first argument unchanged.
STD_ARG0:
        CALL PKT_ARG0
; Return A:CHL through the primitive continuation.
STD_RET:
        PUSH IX
        RET

; min and max: one or more numbers; the result is inexact when any argument
; is, and a NaN argument makes the result NaN.
STD_MIN:
        LD A,0FFH                  ; Keep the left value while it is less.
        JR STD_PICK
STD_MAX:
        LD A,1                     ; Keep the left value while it is greater.
STD_PICK:
        LD (STD_MODE),A
        LD A,(ARG_CNT)
        OR A
        JP Z,ERROR
        CALL PKT_NUMS
        LD HL,ARG_PKT              ; The first argument starts the fold.
        LD DE,STD_X
        LD BC,4
        LDIR
        XOR A
        LD (STD_FRAC),A            ; Nonzero once an inexact value is seen.
        LD A,(ARG_CNT)
        LD (STD_CNT),A
        LD HL,ARG_PKT
        LD (STD_PTR),HL
        JR .SEEN
.NEXT:
        LD HL,(STD_PTR)            ; The next argument is the right value.
        LD DE,NUM_Y
        LD BC,4
        LDIR
        LD HL,(STD_X)
        LD A,(STD_X+2)
        LD C,A
        LD A,(STD_X+3)
        AND 0FH
        CALL NUM_CMP
        JP C,ERROR
        LD A,L
        CP 2
        JR Z,.TAKE                 ; NaN on either side wins.
        LD A,(STD_MODE)
        CP L
        JR Z,.SEEN                 ; The kept value already wins.
        LD A,H                     ; Equal values keep the left.
        OR L
        JR Z,.SEEN
.TAKE:
        LD A,(STD_X+3)             ; Keep a NaN on the left.
        AND 0FH
        CP 9
        JR NZ,.REPLACE
        LD A,(STD_X+2)
        AND 7FH
        CP 7FH
        JR NZ,.REPLACE
        LD HL,(STD_X)
        LD A,H
        OR L
        JR NZ,.SEEN
.REPLACE:
        LD HL,(STD_PTR)            ; NUM_CMP may reuse NUM_Y; copy the packet.
        LD DE,STD_X
        LD BC,4
        LDIR
.SEEN:
        LD HL,(STD_PTR)            ; Note an inexact argument.
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        AND 0FH
        CP 9
        JR NZ,.COUNT
        LD (STD_FRAC),A
.COUNT:
        INC HL
        LD (STD_PTR),HL
        LD A,(STD_CNT)
        DEC A
        LD (STD_CNT),A
        JR NZ,.NEXT
        LD HL,(STD_X)
        LD A,(STD_X+2)
        LD C,A
        LD A,(STD_X+3)
        AND 0FH
        CP 3
        JP NZ,STD_RET
        LD A,(STD_FRAC)
        OR A
        LD A,3
        JP Z,STD_RET
        CALL F24_ITOF              ; An exact result becomes inexact.
        JP STD_RET

; even? and odd? take one exact integer.
STD_EVEN:
        LD B,0
        JR STD_PAR
STD_ODD:
        LD B,1
STD_PAR:
        PUSH BC
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        POP BC
        CP 3
        JP NZ,ERROR
        LD A,L
        AND 1
        CP B
        JP Z,STD_YES
        JP STD_NO

; positive? and negative? compare one number with zero; NaN is neither.
STD_POS:
        LD B,1
        JR STD_SIGN
STD_NEGP:
        LD B,0FFH
STD_SIGN:
        PUSH BC
        LD A,1
        CALL PKT_NARG
        LD HL,0                    ; The right value is exact zero.
        LD (NUM_Y),HL
        XOR A
        LD (NUM_Y+2),A
        LD A,3
        LD (NUM_Y+3),A
        CALL PKT_ARG0
        CALL NUM_CMP
        POP BC
        JP C,ERROR
        LD A,L
        CP B
        JP Z,STD_YES
        JP STD_NO

; exact? and inexact? take one number.
STD_EXQ:
        LD B,3
        JR STD_KIND
STD_INXQ:
        LD B,9
STD_KIND:
        PUSH BC
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CALL NUM_CHK
        POP BC
        JP C,ERROR
        CP B
        JP Z,STD_YES
        JP STD_NO

; integer? is true for an exact integer and for a float with no fraction.
STD_INTQ:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CP 3
        JP Z,STD_YES
        CP 9
        JP NZ,STD_NO
        LD A,4
        CALL STD_PART
        JP C,STD_NO
        LD A,(STD_FRAC)
        OR A
        JP Z,STD_YES
        JP STD_NO

; gcd and lcm of any number of exact integers.
STD_GCD:
        XOR A                      ; (gcd) is 0.
        JR STD_GL
STD_LCM:
        LD A,1                     ; (lcm) is 1.
STD_GL:
        LD (STD_MODE),A
        LD L,A
        LD H,0
        LD (STD_X),HL
        XOR A
        LD (STD_X+2),A
        LD A,(ARG_CNT)
        OR A
        JP Z,.DONE
        LD (STD_CNT),A
        LD HL,ARG_PKT
        LD (STD_PTR),HL
        CALL .LOAD                 ; The first argument starts the fold.
        LD (STD_X),HL
        LD A,C
        LD (STD_X+2),A
.NEXT:
        LD A,(STD_CNT)
        DEC A
        LD (STD_CNT),A
        JP Z,.DONE
        CALL .LOAD
        LD (STD_Y),HL
        LD A,C
        LD (STD_Y+2),A
        LD A,(STD_MODE)
        OR A
        JP NZ,.LCM
        CALL STD_EUCL
        JP .NEXT
.LCM:
        LD HL,(STD_X)              ; lcm(a,b) = a / gcd(a,b) * b, or 0.
        LD A,(STD_X+2)
        OR H
        OR L
        JP Z,.NEXT
        LD HL,(STD_Y)
        LD A,(STD_Y+2)
        OR H
        OR L
        JP NZ,.BOTH
        LD (STD_X),HL
        LD (STD_X+2),A
        JP .NEXT
.BOTH:
        LD HL,STD_X                ; Keep a and b while the gcd is found.
        LD DE,STD_T
        LD BC,3
        LDIR
        LD HL,STD_Y
        LD DE,STD_N
        LD BC,3
        LDIR
        CALL STD_EUCL              ; STD_X = gcd.
        LD HL,STD_X                ; a / gcd: dividend a, divisor gcd.
        LD DE,NUM_Y
        LD BC,3
        LDIR
        LD A,3
        LD (NUM_Y+3),A
        LD HL,(STD_T)
        LD A,(STD_T+2)
        LD C,A
        LD A,3
        CALL NUM_QUOT
        JP C,ERROR
        LD (STD_X),HL              ; Multiply by b.
        LD A,C
        LD (STD_X+2),A
        LD HL,STD_N
        LD DE,NUM_Y
        LD BC,3
        LDIR
        LD A,3
        LD (NUM_Y+3),A
        LD HL,(STD_X)
        LD A,(STD_X+2)
        LD C,A
        LD A,3
        CALL NUM_MUL
        JP C,ERROR
        BIT 7,C
        CALL NZ,NUM_INV
        LD (STD_X),HL
        LD A,C
        LD (STD_X+2),A
        JP .NEXT
.DONE:
        LD HL,(STD_X)
        LD A,(STD_X+2)
        LD C,A
        LD A,3
        JP STD_RET
; Read the next packet integer as its magnitude; -8388608 has none.
.LOAD:
        LD HL,(STD_PTR)
        CALL PKT_VAL
        CP 3
        JP NZ,ERROR
        PUSH HL
        LD HL,(STD_PTR)
        LD DE,4
        ADD HL,DE
        LD (STD_PTR),HL
        POP HL
        BIT 7,C
        RET Z
        CALL NUM_INV
        BIT 7,C
        JP NZ,ERROR
        RET

; STD_X := gcd(STD_X, STD_Y) for nonnegative integers, by remainders.
STD_EUCL:
        LD HL,(STD_Y)
        LD A,(STD_Y+2)
        OR H
        OR L
        RET Z
        LD HL,STD_Y                ; X mod Y.
        LD DE,NUM_Y
        LD BC,3
        LDIR
        LD A,3
        LD (NUM_Y+3),A
        LD HL,(STD_X)
        LD A,(STD_X+2)
        LD C,A
        LD A,3
        CALL NUM_REM
        JP C,ERROR
        PUSH HL
        LD HL,STD_Y                ; X := Y, Y := remainder.
        LD DE,STD_X
        LD BC,3
        LDIR
        POP HL
        LD (STD_Y),HL
        LD A,C
        LD (STD_Y+2),A
        JR STD_EUCL

; expt: the exponent is an exact integer.  An exact base with a nonnegative
; exponent gives an exact power, overflowing as multiplication does; any
; other base works in floats, and a negative exponent takes the reciprocal.
STD_EXPT:
        LD A,2
        CALL PKT_NARG
        CALL PKT_ARG1
        CP 3
        JP NZ,ERROR
        LD (STD_N),HL              ; The exponent.
        LD A,C
        LD (STD_N+2),A
        CALL PKT_ARG0
        CALL NUM_CHK
        JP C,ERROR
        LD (STD_X),HL              ; The base.
        LD B,A
        LD A,C
        LD (STD_X+2),A
        LD A,B
        LD (STD_X+3),A
        LD A,(STD_N+2)
        AND 80H
        LD (STD_NEG),A             ; A negative exponent.
        JR Z,.MAG
        LD HL,(STD_N)
        LD A,(STD_N+2)
        LD C,A
        CALL NUM_INV
        LD (STD_N),HL
        LD A,C
        LD (STD_N+2),A
.MAG:
        LD A,(STD_NEG)             ; Floats unless the power is exact.
        OR A
        JR NZ,.FLOAT
        LD A,(STD_X+3)
        CP 3
        JR Z,.READY
.FLOAT:
        LD A,(STD_X+3)
        CP 9
        JR Z,.ONE
        LD HL,(STD_X)
        LD A,(STD_X+2)
        LD C,A
        CALL F24_ITOF
        LD (STD_X),HL
        LD A,C
        LD (STD_X+2),A
        LD A,9
        LD (STD_X+3),A
.ONE:
        LD HL,0                    ; The float 1.0.
        LD C,3FH
        LD A,9
        JR .START
.READY:
        LD HL,1                    ; The integer 1.
        LD C,0
        LD A,3
.START:
        LD (STD_Y),HL              ; STD_Y accumulates the power.
        LD B,A
        LD A,C
        LD (STD_Y+2),A
        LD A,B
        LD (STD_Y+3),A
; Square and multiply, consuming the exponent from its low bit.
.LOOP:
        LD HL,(STD_N)
        LD A,(STD_N+2)
        OR H
        OR L
        JR Z,.DONE
        LD A,(STD_N)
        AND 1
        JR Z,.SQUARE
        LD HL,STD_X                ; Y := Y * X.
        LD DE,NUM_Y
        LD BC,4
        LDIR
        LD HL,STD_Y
        CALL STD_MULC
        LD (STD_Y),HL
        LD A,C
        LD (STD_Y+2),A
.SQUARE:
        LD HL,STD_N+2              ; N := N / 2.
        SRL (HL)
        DEC HL
        RR (HL)
        DEC HL
        RR (HL)
        LD HL,(STD_N)
        LD A,(STD_N+2)
        OR H
        OR L
        JR Z,.DONE
        LD HL,STD_X                ; X := X * X.
        LD DE,NUM_Y
        LD BC,4
        LDIR
        LD HL,STD_X
        CALL STD_MULC
        LD (STD_X),HL
        LD A,C
        LD (STD_X+2),A
        JR .LOOP
.DONE:
        LD A,(STD_NEG)
        OR A
        JR Z,.RESULT
        LD HL,STD_Y                ; 1 / Y for a negative exponent.
        LD DE,NUM_Y
        LD BC,4
        LDIR
        LD HL,0
        LD C,3FH
        LD A,9
        CALL NUM_DIV
        JP C,ERROR
        JP STD_RET
.RESULT:
        LD HL,(STD_Y)
        LD A,(STD_Y+2)
        LD C,A
        LD A,(STD_Y+3)
        JP STD_RET

; Multiply the cell at HL by NUM_Y, failing on exact overflow.
STD_MULC:
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD C,(HL)
        INC HL
        LD A,(HL)
        EX DE,HL
        CALL NUM_MUL
        JP C,ERROR
        RET

; sqrt: an exact perfect square gives its exact root; any other nonnegative
; number gives the correctly rounded float root.  A negative integer is an
; error; a negative float gives NaN, and -0.0 gives -0.0.
STD_SQRT:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CP 3
        JR Z,.INT
        CP 9
        JP NZ,ERROR
        CALL F24_OPEN
        LD E,A                     ; The biased exponent.
        LD A,B
        CP 3
        JP Z,STD_NAN           ; NaN.
        OR A
        JP Z,STD_ARG0              ; Either zero.
        LD A,D
        OR A
        JP NZ,STD_NAN          ; A negative number has no real root.
        LD A,B
        CP 2
        JP Z,STD_ARG0              ; +inf.0.
        LD A,E                     ; value = M * 2^(U-95).
        SUB 95
        JR STD_ROOT
.INT:
        BIT 7,C
        JP NZ,ERROR
        LD A,C
        OR H
        OR L
        JP Z,STD_ARG0              ; The exact root of 0.
        LD (STD_X),HL              ; Exact when isqrt(n * 2^16) is a whole
        LD A,C                     ; multiple of 256 with no remainder.
        LD (STD_X+2),A
        LD (STD_RAD+2),HL
        LD (STD_RAD+4),A
        LD HL,0
        LD (STD_RAD),HL
        CALL STD_ISQ
        JR NZ,.FLOAT
        LD A,(STD_Q)
        OR A
        JR NZ,.FLOAT
        LD HL,(STD_Q+1)
        LD C,0
        LD A,3
        JP STD_RET
.FLOAT:
        LD HL,(STD_X)
        LD A,(STD_X+2)
        LD C,A
        XOR A                      ; value = n * 2^0.
; The correctly rounded float root of C:HL * 2^A, for a nonzero magnitude.
STD_ROOT:
        LD (STD_EXP),A
        LD (STD_RAD),HL              ; Put the magnitude in the 40-bit radicand
        LD A,C                     ; and shift it up to bit 38 or 39, by
        LD (STD_RAD+2),A             ; an even distance once the exponent is.
        XOR A
        LD (STD_RAD+3),A
        LD (STD_RAD+4),A
        LD A,(STD_EXP)
        BIT 0,A
        JR Z,.EVEN
        DEC A
        LD (STD_EXP),A
        CALL .SHL1
.EVEN:
        LD A,(STD_RAD+4)
        AND 0C0H
        JR NZ,.ROOT
        CALL .SHL1
        CALL .SHL1
        LD A,(STD_EXP)
        SUB 2
        LD (STD_EXP),A
        JR .EVEN
.ROOT:
        CALL STD_ISQ               ; A 20-bit root with its leading bit at 19.
        LD HL,(STD_Q)
        LD (F24_M),HL
        LD A,(STD_Q+2)
        LD (F24_M+2),A
        JR Z,.EXACT
        LD HL,F24_M                ; A remainder is sticky.
        SET 0,(HL)
.EXACT:
        LD A,(STD_EXP)             ; value = root * 2^(EXP/2), so the packer's
        SRA A                      ; exponent is EXP/2 + 82.
        LD L,A
        LD H,0
        BIT 7,A
        JR Z,.BIAS
        DEC H
.BIAS:
        LD DE,82
        ADD HL,DE
        LD (F24_EXP),HL
        XOR A
        LD (F24_SIGN),A
        CALL F24_PACK
        JP STD_RET
.SHL1:
        LD HL,STD_RAD
        LD B,5
        OR A
.SHL_LOOP:
        RL (HL)
        INC HL
        DJNZ .SHL_LOOP
        RET

; The 20-bit integer square root of the 40-bit radicand STD_RAD, consumed two
; bits at a time from the top, into STD_Q.  NZ when a remainder is left.
STD_ISQ:
        LD HL,0
        LD (STD_Q),HL
        LD (STD_T),HL
        XOR A
        LD (STD_Q+2),A
        LD (STD_T+2),A
        LD A,20
        LD (STD_CNT),A
.STEP:
        LD B,2                     ; Bring two radicand bits into the remainder.
.BITS:
        LD HL,STD_RAD
        LD C,5
        OR A
.R_SHL:
        RL (HL)
        INC HL
        DEC C
        JR NZ,.R_SHL
        LD HL,STD_T
        RL (HL)
        INC HL
        RL (HL)
        INC HL
        RL (HL)
        DJNZ .BITS
        LD HL,(STD_Q)              ; The trial divisor is 4*root + 1.
        LD A,(STD_Q+2)
        LD C,A
        ADD HL,HL
        RL C
        ADD HL,HL
        RL C
        INC L
        EX DE,HL
        LD B,C                     ; B:DE is the trial.
        LD HL,(STD_T)
        LD A,(STD_T+2)
        LD C,A
        OR A
        SBC HL,DE
        LD A,C
        SBC A,B
        LD C,A
        JR C,.ZERO
        LD (STD_T),HL              ; Keep the reduced remainder and set the
        LD A,C                     ; new root bit.
        LD (STD_T+2),A
        CALL .DOUBLE
        LD HL,STD_Q
        SET 0,(HL)
        JR .NEXT
.ZERO:
        CALL .DOUBLE
.NEXT:
        LD HL,STD_CNT
        DEC (HL)
        JR NZ,.STEP
        LD HL,(STD_T)
        LD A,(STD_T+2)
        OR H
        OR L
        RET
.DOUBLE:
        LD HL,STD_Q                ; root := 2*root.
        SLA (HL)
        INC HL
        RL (HL)
        INC HL
        RL (HL)
        RET

; Return the canonical NaN.
STD_NAN:
        CALL F24_NAN
        JP STD_RET

; ---- State ----------------------------------------------------------------

STD_X:    DS 4                     ; A number cell being folded or split.
STD_Y:    DS 4                     ; A second number cell.
STD_N:    DS 3                     ; A magnitude or exponent.
STD_T:    DS 3                     ; A remainder or saved value.
STD_NEG:  DB 0                     ; Sign, 00 or 80.
STD_FRAC: DB 0                     ; Nonzero when a fraction was dropped.
STD_EXP:  DB 0                     ; Binary exponent of a square root.
STD_Q:    DS 3                     ; A square root.
STD_RAD:    DS 5                     ; The 40-bit radicand.
