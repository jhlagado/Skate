; Numeric comparison across exact integers and binary16 values.
; Entry point: NUM_CMP; signed helper: .SIGNED.
; Raw results are -1, 0, +1 or unordered.
; Public comparison preserves mathematical ordering across representations.
; Rounding the integer first would incorrectly make 2049 equal to float 2048.
NUM_CMP:
    CALL NUM_LOAD           ; Validate and save both original values.
    RET C                   ; Preserve the common type-error return.
    LD A,(NUM_X+3)          ; Inspect the left representation.
    CP 3                    ; An integer left permits exact or mixed comparison.
    JP NZ,.FLT_LEFT         ; Handle float-left cases separately.
    LD A,(NUM_Y+3)          ; Inspect the right representation.
    CP 3                    ; Two integers can be compared as signed values.
    JP Z,.BOTH
    XOR A                   ; For integer-left mixed comparison, preserve ordering.
    LD (NUM_SWAP),A         ; NUM_SWAP=0 means no final reversal.
    LD HL,(NUM_X)           ; The integer in C:HL and the float in DE.
    LD A,(NUM_X+2)
    LD C,A
    LD DE,(NUM_Y)
    JP .MIXED               ; Compare the integer against the float.
.FLT_LEFT:
    LD A,(NUM_Y+3)          ; The left operand is a float; inspect the right tag.
    CP 3                    ; An integer right requires reversed mixed comparison.
    JP Z,.SWAP              ; Swap that pair before the mixed algorithm.
    LD HL,(NUM_X)           ; Two floats use the binary16 comparison directly.
    LD DE,(NUM_Y)
    LD B,0
    XOR A                   ; Set both tags to 0 and clear carry.
    JP F16_CMP
.SWAP:
    LD HL,(NUM_Y)           ; Put the integer in C:HL and the float in DE.
    LD A,(NUM_Y+2)
    LD C,A
    LD DE,(NUM_X)
    LD A,1                  ; Record that this is the opposite of caller order.
    LD (NUM_SWAP),A         ; Reverse less/greater at the shared final exit.
; Mixed comparison always starts with integer C:HL and float DE. NUM_SWAP
; records whether that order was obtained by swapping the caller's operands.
.MIXED:
    LD (NUM_INT),HL         ; Save the exact integer without rounding it.
    LD A,C
    LD (NUM_INT+2),A
    LD (NUM_FLT),DE         ; Save the float for range and fractional checks.
    EX DE,HL                ; Put the float in HL for raw-bit inspection.
    ; Canonical NaN is the only accepted NaN.
    LD A,H                  ; Check the high byte of canonical NaN, 7E00H.
    CP 7EH                  ; Other high bytes can proceed to truncation.
    JP NZ,.TRUNC            ; Skip the low-byte NaN test when high bytes differ.
    LD A,L                  ; Check the remaining byte of the NaN encoding.
    OR A                    ; Only 7E00H is the accepted NaN bit pattern.
    JP NZ,.TRUNC            ; Other values proceed to truncation.
    LD HL,2                 ; Raw comparison code 2 denotes unordered.
    JP NUM_RAW              ; NaN is unordered in either operand order.
.TRUNC:
    XOR A                   ; Supply scalar tag 0 to the conversion routine.
    CALL F16_FTOI           ; Truncate the float toward zero into C:HL.
    JP C,.OUTSIDE           ; Only an infinity fails; its sign decides.
    LD (NUM_CHOP),HL        ; Save the truncation for a possible fractional tie.
    LD A,C
    LD (NUM_CHOP+2),A
    LD B,C                  ; B:DE becomes the truncated value.
    EX DE,HL
    LD HL,(NUM_INT)         ; C:HL becomes the exact integer being compared.
    LD A,(NUM_INT+2)
    LD C,A
    CALL .SIGNED            ; Compare without first rounding the integer.
    LD A,H                  ; Test whether the raw comparison result is zero.
    OR L                    ; Both bytes must be zero for equality.
    JP NZ,.EXIT             ; Unequal integers already determine the ordering.
    ; Equal to the truncation: its float conversion is exact, since
    ; every finite binary16 number outside +/-2048 already has integer value.
    LD HL,(NUM_CHOP)        ; Recover the truncation, equal to the integer here.
    LD A,(NUM_CHOP+2)
    LD C,A
    CALL F16_ITOF           ; Its conversion back to binary16 is exact here.
    LD DE,(NUM_FLT)         ; Compare against the original, possibly fractional float.
    LD B,0                  ; The right value has scalar tag 0.
    XOR A                   ; The converted left also has scalar tag 0.
    CALL F16_CMP            ; Resolve the fractional remainder and signed zeros.
    JP .EXIT                ; Apply the original operand order to the result.
; NaN was handled before conversion; every finite float fits twenty-four
; bits, so the remaining failure is an infinity, ordered by its sign alone.
.OUTSIDE:
    LD HL,(NUM_FLT)         ; Inspect the original infinity.
    BIT 7,H                 ; Its sign places it below or above every integer.
    LD HL,1                 ; Assume integer > negative infinity.
    JP NZ,.EXIT             ; A negative sign confirms that ordering.
    LD HL,0FFFFH            ; Otherwise integer < positive infinity.
; The mixed result is now -1, 0 or +1; unordered returned before this point.
.EXIT:
    LD A,(NUM_SWAP)         ; Recover whether the caller supplied float on the left.
    OR A                    ; Zero retains the integer-versus-float result.
    CALL NZ,NUM_FLIP        ; Reverse -1/+1; equality stays zero.
    JP NUM_RAW              ; Return raw comparison code with carry clear.

.BOTH:
    LD HL,(NUM_X)           ; Left C:HL and right B:DE.
    LD A,(NUM_X+2)
    LD C,A
    LD DE,(NUM_Y)
    LD A,(NUM_Y+2)
    LD B,A
; Raw signed comparison of C:HL with B:DE. Success A=0, HL=-1/0/1.
.SIGNED:
    LD A,C                  ; Compare signs before subtracting.
    XOR B                   ; Bit 7 is set precisely when signs differ.
    JP M,NUM_SIGN           ; Opposite signs determine signed ordering directly.
    OR A                    ; Equal signs: clear borrow before unsigned subtraction.
    SBC HL,DE               ; Within one sign half, unsigned ordering is sufficient.
    LD A,C
    SBC A,B
    JP C,NUM_LESS           ; Borrow means the left value is smaller.
    JP NZ,NUM_MORE          ; A nonzero top difference means greater.
    LD A,H
    OR L
    JP NZ,NUM_MORE
    JP NUM_SAME             ; A zero difference means equal values.
NUM_MORE:
    LD HL,1                 ; Raw code +1 denotes left greater than right.
    JP NUM_RAW              ; Return the code with A=0 and carry clear.
NUM_SIGN:
    BIT 7,C                 ; For opposite signs, only the left sign is needed.
    JP Z,NUM_MORE           ; A nonnegative left is greater than a negative right.
NUM_LESS:
    LD HL,0FFFFH            ; Raw code -1 denotes left less than right.
    JP NUM_RAW              ; Return the code with A=0 and carry clear.
NUM_SAME:
    LD HL,0                 ; Raw code 0 denotes equality.
    JP NUM_RAW              ; Return the code with A=0 and carry clear.
