; Numeric comparison across exact integers and floats.
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
    LD HL,(NUM_X)           ; The integer in C:HL and the float in B:DE.
    LD A,(NUM_X+2)
    LD C,A
    LD DE,(NUM_Y)
    JP .MIXED               ; Compare the integer against the float.
.FLT_LEFT:
    LD A,(NUM_Y+3)          ; The left operand is a float; inspect the right tag.
    CP 3                    ; An integer right requires reversed mixed comparison.
    JP Z,.SWAP              ; Swap that pair before the mixed algorithm.
    JP F24_CMP              ; Two floats compare directly.
.SWAP:
    LD HL,(NUM_Y)           ; Put the integer in C:HL and the float cell in X.
    LD A,(NUM_Y+2)
    LD C,A
    LD DE,(NUM_X)
    LD A,(NUM_X+2)
    LD B,A
    LD A,1                  ; Record that this is the opposite of caller order.
    LD (NUM_SWAP),A         ; Reverse less/greater at the shared final exit.
    JR .SAVE
; Mixed comparison always starts with integer C:HL and float B:DE. NUM_SWAP
; records whether that order was obtained by swapping the caller's operands.
.MIXED:
    LD A,(NUM_Y+2)
    LD B,A
.SAVE:
    LD (NUM_INT),HL         ; Save the exact integer without rounding it.
    LD A,C
    LD (NUM_INT+2),A
    LD (NUM_FLT),DE         ; Save the float for range and fractional checks.
    LD A,B
    LD (NUM_FLT+2),A
    AND 7FH                 ; NaN is unordered in either operand order.
    CP 7FH
    JR NZ,.TRUNC
    LD A,D
    OR E
    JR Z,.TRUNC
    LD HL,2
    JP NUM_RAW
.TRUNC:
    EX DE,HL                ; Truncate the float toward zero into C:HL.
    LD C,B
    LD A,9
    CALL F24_FTOI
    JP C,.OUTSIDE           ; Only an infinity or a huge float fails.
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
    ; Equal to the truncation: its float conversion is exact, since every
    ; float of magnitude 2^16 or more is already an integer.  Compare it
    ; with the original float to resolve a fraction.
    LD HL,(NUM_CHOP)
    LD A,(NUM_CHOP+2)
    LD C,A
    CALL F24_ITOF
    LD (NUM_X),HL
    LD A,C
    LD (NUM_X+2),A
    LD HL,(NUM_FLT)
    LD (NUM_Y),HL
    LD A,(NUM_FLT+2)
    LD (NUM_Y+2),A
    CALL F24_CMP
    JP .EXIT
; The float is an infinity or beyond the integer range, ordered by its sign.
.OUTSIDE:
    LD A,(NUM_FLT+2)
    BIT 7,A                 ; Its sign places it below or above every integer.
    LD HL,1                 ; Assume integer > negative float.
    JP NZ,.EXIT             ; A negative sign confirms that ordering.
    LD HL,0FFFFH            ; Otherwise integer < positive float.
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
