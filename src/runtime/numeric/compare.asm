; Numeric comparison across exact integers and binary16 values.
; Entry point: NCMP; signed helper: NSIGNEDC.
; Raw results are -1, 0, +1 or unordered.
; Public comparison preserves mathematical ordering across representations.
; Rounding the integer first would incorrectly make 2049 equal to float 2048.
NCMP:
    CALL NPREPARE              ; Validate and save both original values.
    RET C                   ; Preserve the common type-error return.
    LD HL,(NLEFTWK)              ; Restore the left payload after classification.
    LD DE,(NRIGHTWK)              ; Restore the right payload.
    LD A,(NLEFTTG)              ; Inspect the left representation.
    CP 3                    ; An integer left permits exact or mixed comparison.
    JP NZ,NCMPLEFT           ; Handle float-left cases separately.
    LD A,(NRIGHTTG)              ; Inspect the right representation.
    CP 3                    ; Two integers can be compared as signed words.
    JP Z,NSIGNEDC              ; Return the raw signed comparison directly.
    XOR A                   ; For integer-left mixed comparison, preserve ordering.
    LD (NREVORD),A             ; NREVORD=0 means no final reversal.
    JP NCMPMIXD                ; Compare the integer against the float.
NCMPLEFT:
    LD A,(NRIGHTTG)              ; The left operand is a float; inspect the right tag.
    CP 3                    ; An integer right requires reversed mixed comparison.
    JP Z,NCMPSWAP             ; Swap that pair before the mixed algorithm.
    LD B,0                  ; Two floats use right tag 0.
    XOR A                   ; Set left tag 0 and clear carry.
    JP F16CMP               ; Return the binary16 comparison directly.
NCMPSWAP:
    EX DE,HL                ; Put the integer in HL and the float in DE.
    LD A,1                  ; Record that this is the opposite of caller order.
    LD (NREVORD),A             ; Reverse less/greater at the shared final exit.
; Mixed comparison always starts with integer HL and float DE. NREVORD records
; whether that order was obtained by swapping the caller's operands.
NCMPMIXD:
    LD (NINTCMP),HL              ; Save the exact integer without rounding it.
    LD (NFLOATV),DE              ; Save the float for range and fractional checks.
    EX DE,HL                ; Put the float in HL for raw-bit inspection.
    ; Canonical NaN is the only accepted NaN.
    LD A,H                  ; Check the high byte of canonical NaN, 7E00H.
    CP 7EH                  ; Other high bytes can proceed to truncation.
    JP NZ,NCMPTOI             ; Skip the low-byte NaN test when high bytes differ.
    LD A,L                  ; Check the remaining byte of the NaN encoding.
    OR A                    ; Only 7E00H is the accepted NaN bit pattern.
    JP NZ,NCMPTOI             ; Other values proceed to truncation.
    LD HL,2                 ; Raw comparison code 2 denotes unordered.
    JP NRAWGOOD               ; NaN is unordered in either operand order.
NCMPTOI:
    XOR A                   ; Supply scalar tag 0 to the conversion routine.
    CALL F16TOI             ; Truncate the float toward zero as a signed word.
    JP C,NCOUTRNG            ; An out-of-range float needs only a sign check.
    LD (NTRUNCV),HL              ; Save the truncation for a possible fractional tie.
    EX DE,HL                ; DE becomes the truncated signed word.
    LD HL,(NINTCMP)              ; HL becomes the exact integer being compared.
    CALL NSIGNEDC              ; Compare without first rounding the integer.
    LD A,H                  ; Test whether the raw comparison result is zero.
    OR L                    ; Both bytes must be zero for equality.
    JP NZ,NCMPEXIT             ; Unequal integers already determine the ordering.
    ; Equal to the truncation: its float conversion is exact, since
    ; every finite binary16 number outside +/-2048 already has integer value.
    LD HL,(NTRUNCV)              ; Recover the truncation, equal to the integer here.
    CALL F16FRI             ; Its conversion back to binary16 is exact here.
    LD DE,(NFLOATV)              ; Compare against the original, possibly fractional float.
    LD B,0                  ; The right value has scalar tag 0.
    XOR A                   ; The converted left also has scalar tag 0.
    CALL F16CMP             ; Resolve the fractional remainder and signed zeros.
    JP NCMPEXIT                ; Apply the original operand order to the result.
; NaN was handled before conversion. Every remaining conversion failure is
; a finite out-of-range value or infinity, ordered by its sign alone.
NCOUTRNG:
    LD HL,(NFLOATV)              ; Inspect the original out-of-range float.
    BIT 7,H                 ; Its sign places it below or above every signed integer.
    LD HL,1                 ; Assume integer > negative out-of-range float.
    JP NZ,NCMPEXIT             ; A negative sign confirms that ordering.
    LD HL,0FFFFH            ; Otherwise integer < positive out-of-range float.
; The mixed result is now -1, 0 or +1; unordered returned before this point.
NCMPEXIT:
    LD A,(NREVORD)             ; Recover whether the caller supplied float on the left.
    OR A                    ; Zero retains the integer-versus-float result.
    CALL NZ,NWORDNEG        ; Reverse -1/+1; equality stays zero.
    JP NRAWGOOD               ; Return raw comparison code with carry clear.

; Raw signed word comparison. Success A=0, HL=-1/0/1.
NSIGNEDC:
    LD A,H                  ; Compare signs before subtracting.
    XOR D                   ; Bit 7 is set precisely when signs differ.
    JP M,NCMPSIGN             ; Opposite signs determine signed ordering directly.
    OR A                    ; Equal signs: clear borrow before unsigned subtraction.
    SBC HL,DE               ; Within one sign half, unsigned ordering is sufficient.
    JP Z,NCMPEQOK            ; A zero difference means equal signed words.
    JP C,NCMPLESS             ; Borrow means the left word is smaller.
NCGREAT:
    LD HL,1                 ; Raw code +1 denotes left greater than right.
    JP NRAWGOOD               ; Return the code with A=0 and carry clear.
NCMPSIGN:
    BIT 7,H                 ; For opposite signs, only the left sign is needed.
    JP Z,NCGREAT            ; A nonnegative left is greater than a negative right.
NCMPLESS:
    LD HL,0FFFFH            ; Raw code -1 denotes left less than right.
    JP NRAWGOOD               ; Return the code with A=0 and carry clear.
NCMPEQOK:
    LD HL,0                 ; Raw code 0 denotes equality.
    JP NRAWGOOD               ; Return the code with A=0 and carry clear.
