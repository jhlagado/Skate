; Numeric negation and integer-to-binary16 conversion.
; Entry points: NNEG and the arithmetic conversion path NTOFLOAT.
; NWORDNEG is the shared modular word helper.
; Public unary negation. The exact range is asymmetric around zero.
NNEG:
    LD (NORIGVAL),HL           ; Save the unary input for an overflow return.
    CALL NCLASS             ; Reject nonnumbers before inspecting representation.
    RET C                   ; Classification preserves HL on failure.
    CP 3                    ; Select integer negation only for tag 3.
    JP NZ,F16NEG            ; A numeric scalar uses binary16 sign rules.
    LD A,H                  ; Check for the unique integer with no positive opposite.
    CP 80H                  ; Its high byte is 80H.
    JP NZ,NNEGWORD              ; Every other high byte permits negation.
    LD A,L                  ; Distinguish 8000H from the other 80xxH words.
    OR A                    ; Only 8000H has zero in the low byte.
    JP Z,NOVERFLW              ; Negating -32768 would exceed +32767.
NNEGWORD:
    CALL NWORDNEG           ; Negate the signed word in place.
    JP NINTGOOD               ; Return it with exact tag 3.
; Private modular word negation. HL changes; BC/DE are preserved.
; The low-byte borrow is propagated explicitly into the high-byte subtraction.
NWORDNEG:
    XOR A                   ; Start a bytewise subtraction from zero.
    SUB L                   ; Compute the low byte of 0-HL.
    LD L,A                  ; Store it while retaining the low-byte borrow.
    SBC A,A                 ; Turn that borrow into 00H or FFH.
    SUB H                   ; Complete the high byte: 0-H-borrow, modulo 256.
    LD H,A                  ; HL now holds the two's-complement opposite.
    RET                     ; DE and BC are unchanged by this helper.

; Round integer inputs only after both original values pass classification.
; The F16 tail calls return directly to the original arithmetic caller.
NTOFLOAT:
    LD HL,(NLEFTWK)              ; Reload the original left payload.
    LD A,(NLEFTTG)              ; Test whether it needs integer-to-float conversion.
    CP 3                    ; Tag 3 selects the raw signed conversion.
    CALL Z,F16FRI           ; Round an exact integer to binary16, ties to even.
    LD (NLEFTWK),HL              ; Save the converted left across the right conversion.
    LD HL,(NRIGHTWK)              ; Load the original right payload.
    LD A,(NRIGHTTG)              ; Test the right representation independently.
    CP 3                    ; Tag 3 again requires conversion.
    CALL Z,F16FRI           ; Leave an existing float unchanged.
    EX DE,HL                ; Place the right float in the binary16 DE register.
    LD HL,(NLEFTWK)              ; Restore the left float in HL.
    LD A,(NOPCODE)              ; Recover the selected arithmetic operation.
    LD C,A                  ; C drives dispatch while A/B become scalar tags.
    LD B,0                  ; The right operand is now tag 0.
    XOR A                   ; The left operand is now tag 0 too.
    DEC C                   ; Operation 0 becomes -1; operation 1 becomes zero.
    JP M,F16ADD             ; The negative selector identifies addition.
    JP Z,F16SUB             ; Zero identifies subtraction.
    DEC C                   ; Operation 2 now becomes zero.
    JP Z,F16MUL             ; Zero identifies multiplication.
    JP F16DIV               ; Operation 3 is division; tail-call the binary16 core.
