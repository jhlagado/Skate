; Decimal exact-integer results and conversion diagnostics.
; Entry points: DEC_INT, .FITS, DEC_ZERO, DEC_INF and DEC_SIGN.
; Exact decimal integers never pass through floating point. High limbs must
; all be zero, then the low word must fit the sign-dependent signed16 limit.
DEC_INT: LD HL,DEC_NUM+2
        LD B,38
; Any nonzero limb above the low word proves this integer is outside signed16.
.SCAN:  LD A,(HL)
        OR A
        JR NZ,DEC_OVER        ; The exact magnitude exceeds its permitted range.
        INC HL
        DJNZ .SCAN
        LD HL,(DEC_NUM)          ; Recover the exact numerator low word.
        LD A,(DEC_NEG)           ; Recover the saved number sign bit.
        OR A
        JR NZ,.NEGATIVE
        BIT 7,H
        JR NZ,DEC_OVER        ; The exact magnitude exceeds its permitted range.
        LD A,3               ; Return the public exact-integer value tag.
        OR A
        RET
; Negative integers may have magnitude 32768, one more than the positive maximum.
.NEGATIVE:  LD DE,8000H
        OR A
        SBC HL,DE
        JR C,.FITS
        JR NZ,DEC_OVER        ; The exact magnitude exceeds its permitted range.
; The magnitude fits. Form its two’s-complement payload, then clear success carry.
.FITS: LD DE,(DEC_NUM)
        LD HL,0
        OR A
        SBC HL,DE
        LD A,3               ; Return the public exact-integer value tag.
        OR A
        RET
; Underflow and an all-zero mantissa share the signed floating-zero result.
DEC_ZERO:  LD HL,0
        JR DEC_SIGN
; Overflow and an explicit infinity spelling share the signed infinity result.
DEC_INF: LD HL,7C00H
; Apply the saved sign to a nonnegative IEEE encoding and return floating tag zero.
DEC_SIGN:  LD A,(DEC_NEG)           ; Recover the saved number sign bit.
        OR H
        LD H,A
        XOR A               ; Floating tag zero and success carry clear.
        RET
; Reject malformed grammar without publishing a numeric value.
DEC_BAD:  LD A,128
        SCF                  ; Mark this diagnostic as a failed conversion.
        RET
; Reject a token length or input-address extent outside the supported bounds.
DEC_LONG:   LD A,129
        SCF                  ; Mark this diagnostic as a failed conversion.
        RET
; Reject an exact integer outside the public signed16 range.
DEC_OVER: LD A,130
        SCF                  ; Mark this diagnostic as a failed conversion.
        RET
; DEC_BYTE consumes a byte only after the caller has proved one remains.
