; Decimal exact-integer results and conversion diagnostics.
; Entry points: DEC_INT, .FITS, DEC_ZERO, DEC_INF and DEC_SIGN.
; Exact decimal integers never pass through floating point. Limbs above the
; low three bytes must all be zero, then the magnitude must fit the
; sign-dependent signed twenty-four-bit limit.  The value returns in C:HL.
DEC_INT: LD HL,DEC_NUM+3
        LD B,37
; Any nonzero limb above the low three bytes proves this integer is too wide.
.SCAN:  LD A,(HL)
        OR A
        JR NZ,DEC_OVER        ; The exact magnitude exceeds its permitted range.
        INC HL
        DJNZ .SCAN
        LD HL,(DEC_NUM)          ; Recover the exact magnitude's low word
        LD A,(DEC_NUM+2)         ; and its third byte.
        LD C,A
        LD A,(DEC_NEG)           ; Recover the saved number sign bit.
        OR A
        JR NZ,.NEGATIVE
        BIT 7,C
        JR NZ,DEC_OVER        ; Positive values stay below 800000H.
        LD A,3               ; Return the public exact-integer value tag.
        OR A
        RET
; Negative integers may have magnitude 800000H, one more than the positive maximum.
.NEGATIVE:  LD A,C
        CP 80H
        JR C,.FITS
        JR NZ,DEC_OVER        ; The exact magnitude exceeds its permitted range.
        LD A,H
        OR L
        JR NZ,DEC_OVER
; The magnitude fits. Form its two’s-complement payload, then clear success carry.
.FITS:  XOR A
        SUB L
        LD L,A
        LD A,0
        SBC A,H
        LD H,A
        LD A,0
        SBC A,C
        LD C,A
        LD A,3               ; Return the public exact-integer value tag.
        OR A
        RET
; Underflow and an all-zero mantissa share the signed floating-zero result.
DEC_ZERO:  LD HL,0
        LD C,L
        JR DEC_SIGN
; Overflow and an explicit infinity spelling share the signed infinity result.
DEC_INF: LD HL,0
        LD C,7FH
; Apply the saved sign to the float24 encoding C:HL and return tag 9.
DEC_SIGN:  LD A,(DEC_NEG)           ; Recover the saved number sign bit.
        OR C
        LD C,A
        LD A,9              ; Float tag nine and success carry clear.
        OR A
        RET
; Reject malformed grammar without publishing a numeric value.
DEC_BAD:  LD A,128
        SCF                  ; Mark this diagnostic as a failed conversion.
        RET
; Reject a token length or input-address extent outside the supported bounds.
DEC_LONG:   LD A,129
        SCF                  ; Mark this diagnostic as a failed conversion.
        RET
; Reject an exact integer outside the signed twenty-four-bit range.
DEC_OVER: LD A,130
        SCF                  ; Mark this diagnostic as a failed conversion.
        RET
; DEC_BYTE consumes a byte only after the caller has proved one remains.
