; Decimal exact-integer results and conversion diagnostics.
; Entry points: DINTEGER, DINTGOOD, DZERORES, DINFRES and DSIGNRES.
; Exact decimal integers never pass through floating point. High limbs must
; all be zero, then the low word must fit the sign-dependent signed16 limit.
DINTEGER: LD HL,DNUMERAT+2
        LD B,38
; Any nonzero limb above the low word proves this integer is outside signed16.
DINTSCAN:  LD A,(HL)
        OR A
        JR NZ,DINTRANG        ; The exact magnitude exceeds its permitted range.
        INC HL
        DJNZ DINTSCAN
        LD HL,(DNUMERAT)         ; Recover the exact numerator low word.
        LD A,(DNUMSIGN)          ; Recover the saved number sign bit.
        OR A
        JR NZ,DINTNEG
        BIT 7,H
        JR NZ,DINTRANG        ; The exact magnitude exceeds its permitted range.
        LD A,3               ; Return the public exact-integer value tag.
        OR A
        RET
; Negative integers may have magnitude 32768, one more than the positive maximum.
DINTNEG:  LD DE,8000H
        OR A
        SBC HL,DE
        JR C,DINTGOOD
        JR NZ,DINTRANG        ; The exact magnitude exceeds its permitted range.
; The magnitude fits. Form its two’s-complement payload, then clear success carry.
DINTGOOD: LD DE,(DNUMERAT)
        LD HL,0
        OR A
        SBC HL,DE
        LD A,3               ; Return the public exact-integer value tag.
        OR A
        RET
; Underflow and an all-zero mantissa share the signed floating-zero result.
DZERORES:  LD HL,0
        JR DSIGNRES
; Overflow and an explicit infinity spelling share the signed infinity result.
DINFRES: LD HL,7C00H
; Apply the saved sign to a nonnegative IEEE encoding and return floating tag zero.
DSIGNRES:  LD A,(DNUMSIGN)          ; Recover the saved number sign bit.
        OR H
        LD H,A
        XOR A               ; Floating tag zero and success carry clear.
        RET
; Reject malformed grammar without publishing a numeric value.
DSYNTAX:  LD A,128
        SCF                  ; Mark this diagnostic as a failed conversion.
        RET
; Reject a token length or input-address extent outside the supported bounds.
DCAPERR:   LD A,129
        SCF                  ; Mark this diagnostic as a failed conversion.
        RET
; Reject an exact integer outside the public signed16 range.
DINTRANG: LD A,130
        SCF                  ; Mark this diagnostic as a failed conversion.
        RET
; DGETBYTE consumes a byte only after the caller has proved one remains.
