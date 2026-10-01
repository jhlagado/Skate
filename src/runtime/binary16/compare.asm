; Binary16 comparison and unordered-result handling.
; Entry point: F16CMP.
; Raw comparison code: FFFF less, 0 equal, 1 greater, 2 unordered.
F16CMP:
    CALL FPREPARE              ; Save and validate both language operands
    RET C                   ; Propagate a type failure
    CALL FUNPBOTH           ; Decode signs and special classes
    LD A,(FLEFTCLS)          ; Inspect the left class
    CP 3                    ; Check for NaN
    JP Z,FCMPUNOR             ; NaN makes the comparison unordered
    LD A,(FRIGHTCL)          ; Inspect the right class
    CP 3                    ; Check for NaN
    JP Z,FCMPUNOR             ; NaN makes the comparison unordered
    LD A,(FLEFTCLS)          ; Fetch the left zero/nonzero class
    LD B,A                  ; Keep it while loading the right class
    LD A,(FRIGHTCL)          ; Fetch the right class
    OR B                    ; Both classes are zero only for two zeros
    JP Z,FCMPEQOK             ; Treat positive and negative zero as equal
    LD A,(FLEFTSGN)           ; Fetch the left sign
    LD B,A                  ; Keep it while loading the right sign
    LD A,(FRIGHTSG)           ; Fetch the right sign
    XOR B                   ; Compare the signs
    JP NZ,FCMPSGN           ; Use sign ordering after handling the two-zero case
    LD HL,(FLEFTVAL)              ; Load the complete left encoding
    LD DE,(FRIGHTVL)              ; Load the complete right encoding
    OR A                    ; Clear carry before comparing the unsigned bit patterns
    SBC HL,DE               ; Compare encoded magnitudes for these equal-sign inputs
    JP Z,FCMPEQOK             ; Identical encodings denote equal numbers
    JP C,FCMPBITL           ; Borrow means the left encoding is smaller
    LD A,(FLEFTSGN)           ; Fetch the common sign
    OR A                    ; Check whether ordering must be reversed
    JP NZ,FCMPLTR            ; For negatives, a larger encoding means a smaller number
    JP FCMPGTR               ; For positives, the larger encoding means greater

; Unsigned encoding order reverses when both numbers are negative.
FCMPBITL:
    LD A,(FLEFTSGN)           ; Fetch the common sign
    OR A                    ; Check whether both numbers are negative
    JP NZ,FCMPGTR            ; A smaller negative encoding denotes a greater value
    JP FCMPLTR               ; A smaller positive encoding denotes a lesser value

; The signs differ and the two-zero case has already been handled.
FCMPSGN:
    LD A,(FLEFTSGN)           ; Fetch the left sign
    OR A                    ; Check whether the left operand is negative
    JP NZ,FCMPLTR            ; A negative left operand is the lesser value

; Raw comparison result for left greater than right.
FCMPGTR:
    LD HL,1                 ; Return code +1
    JP F16OKAY                  ; Clear the success status and carry

; Raw comparison result for left less than right.
FCMPLTR:
    LD HL,0FFFFH            ; Return code -1 as a raw word
    JP F16OKAY                  ; Clear the success status and carry

; Raw comparison result for equality, including either pairing of zeros.
FCMPEQOK:
    LD HL,0                 ; Return code zero
    JP F16OKAY                  ; Clear the success status and carry

; Raw comparison result when either operand is numeric NaN.
FCMPUNOR:
    LD HL,2                 ; Return unordered code two
    JP F16OKAY                  ; Clear the success status and carry

; Internal raw integer ingress; no Scheme integer tag is constructed.
