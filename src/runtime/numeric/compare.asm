; Numeric comparison across exact integers and binary16 values.
; Entry point: NUM_CMP; signed helper: .SIGNED.
; Raw results are -1, 0, +1 or unordered.
; Public comparison preserves mathematical ordering across representations.
; Rounding the integer first would incorrectly make 2049 equal to float 2048.
NUM_CMP:
    CALL NUM_LOAD              ; Validate and save both original values.
    RET C                   ; Preserve the common type-error return.
    LD HL,(NUM_X)                ; Restore the left payload after classification.
    LD DE,(NUM_Y)                 ; Restore the right payload.
    LD A,(NUM_XTAG)             ; Inspect the left representation.
    CP 3                    ; An integer left permits exact or mixed comparison.
    JP NZ,.FLT_LEFT          ; Handle float-left cases separately.
    LD A,(NUM_YTAG)              ; Inspect the right representation.
    CP 3                    ; Two integers can be compared as signed words.
    JP Z,.SIGNED               ; Return the raw signed comparison directly.
    XOR A                   ; For integer-left mixed comparison, preserve ordering.
    LD (NUM_SWAP),A            ; NUM_SWAP=0 means no final reversal.
    JP .MIXED                  ; Compare the integer against the float.
.FLT_LEFT:
    LD A,(NUM_YTAG)              ; The left operand is a float; inspect the right tag.
    CP 3                    ; An integer right requires reversed mixed comparison.
    JP Z,.SWAP                ; Swap that pair before the mixed algorithm.
    LD B,0                  ; Two floats use right tag 0.
    XOR A                   ; Set left tag 0 and clear carry.
    JP F16_CMP              ; Return the binary16 comparison directly.
.SWAP:
    EX DE,HL                ; Put the integer in HL and the float in DE.
    LD A,1                  ; Record that this is the opposite of caller order.
    LD (NUM_SWAP),A            ; Reverse less/greater at the shared final exit.
; Mixed comparison always starts with integer HL and float DE. NUM_SWAP records
; whether that order was obtained by swapping the caller's operands.
.MIXED:
    LD (NUM_INT),HL              ; Save the exact integer without rounding it.
    LD (NUM_FLT),DE              ; Save the float for range and fractional checks.
    EX DE,HL                ; Put the float in HL for raw-bit inspection.
    ; Canonical NaN is the only accepted NaN.
    LD A,H                  ; Check the high byte of canonical NaN, 7E00H.
    CP 7EH                  ; Other high bytes can proceed to truncation.
    JP NZ,.TRUNC              ; Skip the low-byte NaN test when high bytes differ.
    LD A,L                  ; Check the remaining byte of the NaN encoding.
    OR A                    ; Only 7E00H is the accepted NaN bit pattern.
    JP NZ,.TRUNC              ; Other values proceed to truncation.
    LD HL,2                 ; Raw comparison code 2 denotes unordered.
    JP NUM_RAW                ; NaN is unordered in either operand order.
.TRUNC:
    XOR A                   ; Supply scalar tag 0 to the conversion routine.
    CALL F16_FTOI           ; Truncate the float toward zero as a signed word.
    JP C,.OUTSIDE            ; An out-of-range float needs only a sign check.
    LD (NUM_CHOP),HL             ; Save the truncation for a possible fractional tie.
    EX DE,HL                ; DE becomes the truncated signed word.
    LD HL,(NUM_INT)              ; HL becomes the exact integer being compared.
    CALL .SIGNED               ; Compare without first rounding the integer.
    LD A,H                  ; Test whether the raw comparison result is zero.
    OR L                    ; Both bytes must be zero for equality.
    JP NZ,.EXIT                ; Unequal integers already determine the ordering.
    ; Equal to the truncation: its float conversion is exact, since
    ; every finite binary16 number outside +/-2048 already has integer value.
    LD HL,(NUM_CHOP)             ; Recover the truncation, equal to the integer here.
    CALL F16_ITOF           ; Its conversion back to binary16 is exact here.
    LD DE,(NUM_FLT)              ; Compare against the original, possibly fractional float.
    LD B,0                  ; The right value has scalar tag 0.
    XOR A                   ; The converted left also has scalar tag 0.
    CALL F16_CMP            ; Resolve the fractional remainder and signed zeros.
    JP .EXIT                   ; Apply the original operand order to the result.
; NaN was handled before conversion. Every remaining conversion failure is
; a finite out-of-range value or infinity, ordered by its sign alone.
.OUTSIDE:
    LD HL,(NUM_FLT)              ; Inspect the original out-of-range float.
    BIT 7,H                 ; Its sign places it below or above every signed integer.
    LD HL,1                 ; Assume integer > negative out-of-range float.
    JP NZ,.EXIT                ; A negative sign confirms that ordering.
    LD HL,0FFFFH            ; Otherwise integer < positive out-of-range float.
; The mixed result is now -1, 0 or +1; unordered returned before this point.
.EXIT:
    LD A,(NUM_SWAP)            ; Recover whether the caller supplied float on the left.
    OR A                    ; Zero retains the integer-versus-float result.
    CALL NZ,NUM_FLIP        ; Reverse -1/+1; equality stays zero.
    JP NUM_RAW                ; Return raw comparison code with carry clear.

; Raw signed word comparison. Success A=0, HL=-1/0/1.
.SIGNED:
    LD A,H                  ; Compare signs before subtracting.
    XOR D                   ; Bit 7 is set precisely when signs differ.
    JP M,NUM_SIGN             ; Opposite signs determine signed ordering directly.
    OR A                    ; Equal signs: clear borrow before unsigned subtraction.
    SBC HL,DE               ; Within one sign half, unsigned ordering is sufficient.
    JP Z,NUM_SAME            ; A zero difference means equal signed words.
    JP C,NUM_LESS             ; Borrow means the left word is smaller.
NUM_MORE:
    LD HL,1                 ; Raw code +1 denotes left greater than right.
    JP NUM_RAW                ; Return the code with A=0 and carry clear.
NUM_SIGN:
    BIT 7,H                 ; For opposite signs, only the left sign is needed.
    JP Z,NUM_MORE           ; A nonnegative left is greater than a negative right.
NUM_LESS:
    LD HL,0FFFFH            ; Raw code -1 denotes left less than right.
    JP NUM_RAW                ; Return the code with A=0 and carry clear.
NUM_SAME:
    LD HL,0                 ; Raw code 0 denotes equality.
    JP NUM_RAW                ; Return the code with A=0 and carry clear.
