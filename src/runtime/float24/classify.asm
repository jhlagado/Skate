; Float24 validation, negation and unpacking.
; Entry points: F24_CHK, F24_NEG, F24_OPEN and F24_BOTH.
; A float is tag 9 with sign and exponent in C and the fraction in HL.

; Validate A:CHL as a float.  Only 7F8000H is a valid NaN.  Success returns
; A=9 with carry clear; failure returns A=1 with carry set.  CHL is kept.
F24_CHK:
    CP 9
    JR NZ,.BAD
    LD A,C
    AND 7FH
    CP 7FH
    JR NZ,.OK               ; Every finite encoding is valid.
    LD A,H
    OR L
    JR Z,.OK                ; A zero fraction is an infinity.
    LD A,C
    CP 7FH                  ; Canonical NaN is positive
    JR NZ,.BAD
    LD A,H                  ; with fraction 8000H.
    CP 80H
    JR NZ,.BAD
    LD A,L
    OR A
    JR NZ,.BAD
.OK:
    LD A,9
    OR A
    RET
.BAD:
    LD A,1
    SCF
    RET

; Negate the float A:CHL; NaN stays the canonical NaN.
F24_NEG:
    CALL F24_CHK
    RET C
    LD A,C
    CP 7FH
    JR NZ,.FLIP
    LD A,H
    OR L
    JR NZ,.SAME             ; NaN has no sign to change.
.FLIP:
    LD A,C
    XOR 80H
    LD C,A
.SAME:
    LD A,9
    OR A
    RET

; Decode the float encoding C:HL.  B returns the class, D the sign (00/80),
; A the exponent biased by +16 and C:HL the significand, with its leading one
; at bit 16 for a finite nonzero value.  Subnormals are normalized, so their
; exponents run below 17.
F24_OPEN:
    LD A,C
    AND 80H
    LD D,A
    LD A,C
    AND 7FH
    CP 7FH
    JR Z,.SPECIAL
    LD C,0
    OR A
    JR Z,.SUBNORM
    INC C                   ; The implicit leading one.
    ADD A,16
    LD B,1
    RET
.SUBNORM:
    LD A,H
    OR L
    JR Z,.ZERO
    LD A,17                 ; A subnormal has exponent 1, biased to 17.
.NORMAL:
    BIT 0,C                 ; Shift until the leading one reaches bit 16.
    JR NZ,.FINITE
    ADD HL,HL
    RL C
    DEC A
    JR .NORMAL
.FINITE:
    LD B,1
    RET
.ZERO:
    LD B,0
    XOR A
    RET
.SPECIAL:
    LD C,0
    LD B,2
    LD A,H
    OR L
    RET Z                   ; Infinity.
    INC B                   ; NaN.
    RET

; Decode the operand cells NUM_X and NUM_Y into the unpacked X and Y fields.
F24_BOTH:
    LD HL,(NUM_X)
    LD A,(NUM_X+2)
    LD C,A
    CALL F24_OPEN
    LD (F24_XU),A
    LD (F24_XM),HL
    LD A,C
    LD (F24_XM+2),A
    LD A,B
    LD (F24_XC),A
    LD A,D
    LD (F24_XS),A
    LD HL,(NUM_Y)
    LD A,(NUM_Y+2)
    LD C,A
    CALL F24_OPEN
    LD (F24_YU),A
    LD (F24_YM),HL
    LD A,C
    LD (F24_YM+2),A
    LD A,B
    LD (F24_YC),A
    LD A,D
    LD (F24_YS),A
    RET
