; Binary16 comparison and unordered-result handling.
; Entry point: F16_CMP.
; Raw comparison code: FFFF less, 0 equal, 1 greater, 2 unordered.
F16_CMP:
    CALL F16_LOAD              ; Save and validate both language operands
    RET C                   ; Propagate a type failure
    CALL F16_BOTH           ; Decode signs and special classes
    LD A,(F16_XCAT)          ; Inspect the left class
    CP 3                    ; Check for NaN
    JP Z,.UNORDER             ; NaN makes the comparison unordered
    LD A,(F16_YCAT)          ; Inspect the right class
    CP 3                    ; Check for NaN
    JP Z,.UNORDER             ; NaN makes the comparison unordered
    LD A,(F16_XCAT)          ; Fetch the left zero/nonzero class
    LD B,A                  ; Keep it while loading the right class
    LD A,(F16_YCAT)          ; Fetch the right class
    OR B                    ; Both classes are zero only for two zeros
    JP Z,.SAME                ; Treat positive and negative zero as equal
    LD A,(F16_XNEG)           ; Fetch the left sign
    LD B,A                  ; Keep it while loading the right sign
    LD A,(F16_YNEG)           ; Fetch the right sign
    XOR B                   ; Compare the signs
    JP NZ,.BY_SIGN          ; Use sign ordering after handling the two-zero case
    LD HL,(F16_X)                 ; Load the complete left encoding
    LD DE,(F16_Y)                 ; Load the complete right encoding
    OR A                    ; Clear carry before comparing the unsigned bit patterns
    SBC HL,DE               ; Compare encoded magnitudes for these equal-sign inputs
    JP Z,.SAME                ; Identical encodings denote equal numbers
    JP C,.BELOW             ; Borrow means the left encoding is smaller
    LD A,(F16_XNEG)           ; Fetch the common sign
    OR A                    ; Check whether ordering must be reversed
    JP NZ,.LESS              ; For negatives, a larger encoding means a smaller number
    JP .MORE                 ; For positives, the larger encoding means greater

; Unsigned encoding order reverses when both numbers are negative.
.BELOW:
    LD A,(F16_XNEG)           ; Fetch the common sign
    OR A                    ; Check whether both numbers are negative
    JP NZ,.MORE              ; A smaller negative encoding denotes a greater value
    JP .LESS                 ; A smaller positive encoding denotes a lesser value

; The signs differ and the two-zero case has already been handled.
.BY_SIGN:
    LD A,(F16_XNEG)           ; Fetch the left sign
    OR A                    ; Check whether the left operand is negative
    JP NZ,.LESS              ; A negative left operand is the lesser value

; Raw comparison result for left greater than right.
.MORE:
    LD HL,1                 ; Return code +1
    JP F16_OK                   ; Clear the success status and carry

; Raw comparison result for left less than right.
.LESS:
    LD HL,0FFFFH            ; Return code -1 as a raw word
    JP F16_OK                   ; Clear the success status and carry

; Raw comparison result for equality, including either pairing of zeros.
.SAME:
    LD HL,0                 ; Return code zero
    JP F16_OK                   ; Clear the success status and carry

; Raw comparison result when either operand is numeric NaN.
.UNORDER:
    LD HL,2                 ; Return unordered code two
    JP F16_OK                   ; Clear the success status and carry

; Internal raw integer ingress; no Scheme integer tag is constructed.
