; Float24 value printer.
;
; A finite float is an exact dyadic fraction M * 2^s, with a 17-bit
; significand M.  The printer writes M's decimal digits, doubles them once
; for each positive power of two or multiplies them by five once for each
; binary fractional place, and places the decimal point.  The result is the
; exact value, so reading it back gives the same float.  A subnormal needs
; 78 fractional places and at most 61 digits.

; Every character goes through FLT_PUT, a jump that number->string points
; at its own buffer while it formats a float.  It must keep BC, DE and HL.
FLT_PUT:
        JP OUT_CHAR

; Print the float A:CHL in a source-compatible decimal spelling.
FLT_EMIT:
        LD A,C                      ; An all-ones exponent is infinity or NaN.
        AND 7FH
        CP 7FH
        JP Z,.SPECIAL
        LD A,C
        AND 80H
        LD (.SIGN),A
        LD A,C
        AND 7FH
        LD C,0
        LD B,0B2H                   ; A subnormal is M * 2^-78.
        OR A
        JR Z,.SCALE
        INC C                       ; A normal value has the implicit bit:
        SUB 79                      ; M * 2^(e-79).
        LD B,A
.SCALE:
        LD A,B
        LD (.POWER),A
        LD A,C                      ; A zero prints as 0.0 or -0.0.
        OR H
        OR L
        JP Z,.ZERO
        CALL NUM_TEXT               ; The digits of M, most significant first.
        LD A,B
        LD (.COUNT),A
        LD DE,.DIGITS               ; Store them least significant first.
        PUSH BC
        LD C,B
        LD B,0
        EX DE,HL
        ADD HL,BC
        EX DE,HL
        POP BC
.COPY:
        DEC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        DJNZ .COPY
        XOR A
        LD (.PLACES),A
        LD (.DROPPED),A
        LD A,(.POWER)
        OR A
        JP Z,.TRIM
        JP M,.FIVES
; A positive power doubles the digit array that many times.
        LD B,A
.DOUBLE:
        PUSH BC
        LD C,0
        CALL .TIMES2
        POP BC
        DJNZ .DOUBLE
        JP .TRIM
; Each fractional binary place multiplies the digits by five and moves the
; point one decimal place.
.FIVES:
        NEG
        LD (.PLACES),A
        LD B,A
.FIVE:
        PUSH BC
        CALL .TIMES5
        POP BC
        DJNZ .FIVE

; Drop zeroes at the least-significant end while they are fractional places.
.TRIM:
        LD A,(.PLACES)
        OR A
        JP Z,.OUTPUT
        LD HL,.DIGITS
        LD A,(.DROPPED)
        LD E,A
        LD D,0
        ADD HL,DE
        LD A,(HL)
        CP '0'
        JP NZ,.OUTPUT
        LD A,(.DROPPED)
        INC A
        LD (.DROPPED),A
        LD A,(.COUNT)
        DEC A
        LD (.COUNT),A
        LD A,(.PLACES)
        DEC A
        LD (.PLACES),A
        JP .TRIM

; Write the sign, the integer digits, the point and the fraction.
.OUTPUT:
        CALL .MINUS
        LD A,(.PLACES)
        LD C,A
        LD A,(.COUNT)
        SUB C                       ; The number of integer digits.
        JR C,.SMALL
        JR Z,.NO_INT
        LD B,A
        CALL .TOP
        CALL .REVERSE
        JR .POINT
.NO_INT:
        LD A,'0'
        CALL FLT_PUT
        CALL .TOP
.POINT:
        LD A,'.'
        CALL FLT_PUT
        LD A,(.PLACES)
        OR A
        JR Z,.DOT_ZERO
        LD B,A
        JP .REVERSE
.DOT_ZERO:
        LD A,'0'                    ; An integer-valued float ends in .0.
        JP FLT_PUT
.ZERO_PT:
        LD A,'.'
        CALL FLT_PUT
        JR .DOT_ZERO
; A value below one: 0. then the zeroes between the point and the digits.
.SMALL:
        NEG
        LD B,A
        LD A,'0'
        CALL FLT_PUT
        LD A,'.'
        CALL FLT_PUT
.ZEROS:
        LD A,'0'
        CALL FLT_PUT
        DJNZ .ZEROS
        CALL .TOP
        LD A,(.COUNT)
        LD B,A
        JP .REVERSE

.ZERO:
        CALL .MINUS
        LD A,'0'
        CALL FLT_PUT
        JR .ZERO_PT

; Write a minus sign for a negative value.
.MINUS:
        LD A,(.SIGN)
        OR A
        RET Z
        LD A,'-'
        JP FLT_PUT

; Return HL at the most-significant live digit.
.TOP:
        LD HL,.DIGITS
        LD A,(.DROPPED)
        LD E,A
        LD D,0
        ADD HL,DE
        LD A,(.COUNT)
        DEC A
        LD E,A
        ADD HL,DE
        RET

; Write B digits from HL downward.
.REVERSE:
        LD A,(HL)
        CALL FLT_PUT                ; FLT_PUT keeps B and HL.
        DEC HL
        DJNZ .REVERSE
        RET

; Multiply the live digits by two (.TIMES2, C=0) or five (.TIMES5).
.TIMES5:
        LD C,0
        LD A,5
        JR .MULTIPLY
.TIMES2:
        LD A,2
.MULTIPLY:
        LD (.FACTOR),A
        LD A,(.COUNT)
        LD B,A
        LD HL,.DIGITS
.DIGIT:
        LD A,(HL)
        SUB '0'
        LD D,A
        LD A,(.FACTOR)
        LD E,A
        XOR A
.PRODUCT:
        ADD A,D
        DEC E
        JR NZ,.PRODUCT
        ADD A,C                     ; The product plus the carry, at most 49.
        LD C,0
.CARRY:
        CP 10
        JR C,.STORE
        SUB 10
        INC C
        JR .CARRY
.STORE:
        ADD A,'0'
        LD (HL),A
        INC HL
        DJNZ .DIGIT
        LD A,C                      ; A carry extends the digits.
        OR A
        RET Z
        ADD A,'0'
        LD (HL),A
        LD HL,.COUNT
        INC (HL)
        RET

; The named exceptional values.
.SPECIAL:
        LD A,H
        OR L
        LD DE,.NAN_MSG
        JR NZ,.MESSAGE
        BIT 7,C
        LD DE,.POS_MSG
        JR Z,.MESSAGE
        LD DE,.NEG_MSG
.MESSAGE:
        LD A,(DE)                   ; Send a $-terminated spelling.
        CP '$'
        RET Z
        CALL FLT_PUT
        INC DE
        JR .MESSAGE

.NAN_MSG: DB "+nan.0$"
.POS_MSG: DB "+inf.0$"
.NEG_MSG: DB "-inf.0$"

; Private nonreentrant state for the finite decimal conversion.
.SIGN:    DB 0                      ; Sign bit, zero or 80H.
.POWER:   DB 0                      ; The binary scale s, signed.
.PLACES:  DB 0                      ; Decimal fractional-place count.
.DROPPED: DB 0                      ; Discarded low decimal digits.
.COUNT:   DB 0                      ; Live digits, least significant first.
.FACTOR:  DB 0
.DIGITS:  DS 64                     ; ASCII digits, least significant first.
