; Numeric negation and integer-to-binary16 conversion.
; Entry points: NUM_NEG and the arithmetic conversion path NUM_REAL.
; NUM_FLIP is the shared modular word helper.
; Public unary negation. The exact range is asymmetric around zero.
NUM_NEG:
    LD (NUM_ORIG),HL           ; Save the unary input for an overflow return.
    CALL NUM_CHK            ; Reject nonnumbers before inspecting representation.
    RET C                   ; Classification preserves HL on failure.
    CP 3                    ; Select integer negation only for tag 3.
    JP NZ,F16_NEG           ; A numeric scalar uses binary16 sign rules.
    LD A,H                  ; Check for the unique integer with no positive opposite.
    CP 80H                  ; Its high byte is 80H.
    JP NZ,.INT                  ; Every other high byte permits negation.
    LD A,L                  ; Distinguish 8000H from the other 80xxH words.
    OR A                    ; Only 8000H has zero in the low byte.
    JP Z,NUM_OVER              ; Negating -32768 would exceed +32767.
.INT:
    CALL NUM_FLIP           ; Negate the signed word in place.
    JP NUM_GOOD               ; Return it with exact tag 3.
; Private modular word negation. HL changes; BC/DE are preserved.
; The low-byte borrow is propagated explicitly into the high-byte subtraction.
NUM_FLIP:
    XOR A                   ; Start a bytewise subtraction from zero.
    SUB L                   ; Compute the low byte of 0-HL.
    LD L,A                  ; Store it while retaining the low-byte borrow.
    SBC A,A                 ; Turn that borrow into 00H or FFH.
    SUB H                   ; Complete the high byte: 0-H-borrow, modulo 256.
    LD H,A                  ; HL now holds the two's-complement opposite.
    RET                     ; DE and BC are unchanged by this helper.

; Round integer inputs only after both original values pass classification.
; The F16 tail calls return directly to the original arithmetic caller.
NUM_REAL:
    LD HL,(NUM_X)                ; Reload the original left payload.
    LD A,(NUM_XTAG)             ; Test whether it needs integer-to-float conversion.
    CP 3                    ; Tag 3 selects the raw signed conversion.
    CALL Z,F16_ITOF         ; Round an exact integer to binary16, ties to even.
    LD (NUM_X),HL                ; Save the converted left across the right conversion.
    LD HL,(NUM_Y)                 ; Load the original right payload.
    LD A,(NUM_YTAG)              ; Test the right representation independently.
    CP 3                    ; Tag 3 again requires conversion.
    CALL Z,F16_ITOF         ; Leave an existing float unchanged.
    EX DE,HL                ; Place the right float in the binary16 DE register.
    LD HL,(NUM_X)                ; Restore the left float in HL.
    LD A,(NUM_OP)               ; Recover the selected arithmetic operation.
    LD C,A                  ; C drives dispatch while A/B become scalar tags.
    LD B,0                  ; The right operand is now tag 0.
    XOR A                   ; The left operand is now tag 0 too.
    DEC C                   ; Operation 0 becomes -1; operation 1 becomes zero.
    JP M,F16_ADD            ; The negative selector identifies addition.
    JP Z,F16_SUB            ; Zero identifies subtraction.
    DEC C                   ; Operation 2 now becomes zero.
    JP Z,F16_MUL            ; Zero identifies multiplication.
    JP F16_DIV              ; Operation 3 is division; tail-call the binary16 core.
