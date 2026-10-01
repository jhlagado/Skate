; Numeric dispatch and exact arithmetic.
; Entry points: NCLASS, NADD, NSUB, NMUL, NDIV and NINT*.
; Validates tagged values, selects binary16 paths, and checks exact results.
; Validate A/HL without changing HL. Integer payloads need no bit check.
NCLASS:
    CP 3                    ; Tag 3 accepts every signed 16-bit payload.
    JP NZ,F16CLASS          ; Other tags use the binary16 scalar checks.
    OR A                    ; Preserve the integer tag and clear failure carry.
    RET                     ; HL still contains the original payload.

NADD:
    LD C,0                  ; Operation 0 selects addition.
    JP NARITHOP               ; Share validation and representation dispatch.
NSUB:
    LD C,1                  ; Operation 1 selects subtraction.
    JP NARITHOP               ; Share validation and representation dispatch.
NMUL:
    LD C,2                  ; Operation 2 selects multiplication.
    JP NARITHOP               ; Share validation and representation dispatch.
NDIV:
    LD C,3                  ; Operation 3 always selects floating division.
; Select exact arithmetic only for integer/integer +, - and *.
NARITHOP:
    LD (NOPCODE),BC             ; Save C (operation) without disturbing A/B input tags.
    CALL NPREPARE              ; Save both values and reject nonnumbers first.
    RET C                   ; Return the original left payload on type failure.
    LD A,(NOPCODE)              ; Recover the operation after classification.
    CP 3                    ; Division has no exact-integer result path.
    JP Z,NTOFLOAT             ; Convert integer operands before floating division.
    LD A,(NLEFTTG)              ; Inspect the saved left tag.
    CP 3                    ; Exact arithmetic requires tag 3 on both sides.
    JP NZ,NTOFLOAT            ; A floating left operand selects floating arithmetic.
    LD A,(NRIGHTTG)              ; Inspect the saved right tag.
    CP 3                    ; Check the second half of the exact/exact case.
    JP NZ,NTOFLOAT            ; A floating right operand also selects that path.
    LD HL,(NLEFTWK)              ; Restore the exact left word.
    LD DE,(NRIGHTWK)              ; Restore the exact right word.
    LD A,(NOPCODE)              ; Select the checked integer operation.
    OR A                    ; Operation 0 sets zero here.
    JP Z,NINTADD              ; Add two signed words.
    DEC A                   ; Operation 1 becomes zero here.
    JP Z,NINTSUB              ; Subtract the right word from the left.
    JP NINTMUL                ; The remaining exact operation is multiplication.

; Capture the original left before any conversion and classify both inputs.
NPREPARE:
    LD (NORIGVAL),HL           ; Retain the failure result before any conversion.
    LD (NLEFTWK),HL              ; Save the working left payload.
    LD (NRIGHTWK),DE              ; Save the working right payload.
    LD (NLEFTTG),A              ; Save the left representation tag.
    LD A,B                  ; Move the right tag into the classifier register.
    LD (NRIGHTTG),A              ; Save it before classification clobbers registers.
    LD A,(NLEFTTG)              ; Classify the left with its original tag.
    CALL NCLASS             ; Accept an integer or a numeric scalar.
    JP C,NTYPEERR              ; Translate classification failure to the shared exit.
    LD HL,(NRIGHTWK)              ; Load the original right payload.
    LD A,(NRIGHTTG)              ; Pair it with its saved tag.
    CALL NCLASS             ; Validate the right before converting either value.
    JP C,NTYPEERR              ; A bad right operand still returns the original left.
    OR A                    ; Both values are valid; clear failure carry.
    RET                     ; The saved operands now drive either arithmetic path.
NTYPEERR:
    LD A,1                  ; Error 1 denotes a nonnumeric input.
    JP NERRRET               ; Restore the original left through the common exit.
NOVERFLW:
    LD A,2                  ; Error 2 denotes an unrepresentable exact result.
NERRRET:
    LD HL,(NORIGVAL)           ; Failures expose the original left, not a partial result.
    SCF                     ; Carry distinguishes the error code from a result tag.
    RET                     ; Return through the incoming continuation.
; Shared exact-success exit; NRAWGOOD below is for machine comparison codes.
NINTGOOD:
    LD A,3                  ; Tag the checked word as an exact integer.
    OR A                    ; Clear carry without changing the result tag.
    RET                     ; HL is the signed result.
NRAWGOOD:
    XOR A                   ; Return A=0 and clear carry for a comparison code.
    RET                     ; HL is an internal code, not an encoded float.

; Checked signed addition and subtraction use P/V, not unsigned carry.
NINTADD:
    OR A                    ; ADC must start with no carry-in.
    ADC HL,DE               ; Compute the sum and set signed-overflow P/V.
    JP PE,NOVERFLW             ; PE tests P/V=1: here it means signed overflow.
    JP NINTGOOD               ; The signed result fits in 16 bits.
NINTSUB:
    OR A                    ; SBC must start with no borrow-in.
    SBC HL,DE               ; Compute the difference and set signed-overflow P/V.
    JP PE,NOVERFLW             ; PE tests overflow from this subtraction.
    JP NINTGOOD               ; The signed result fits in 16 bits.

; Magnitude multiply. A shifted-out multiplicand bit is overflow only
; after the remaining multiplier has been shown nonzero.
; Unsigned shift/add product: HL=sum, DE=shifted left magnitude, BC=remaining
; right magnitude. Each selected bit contributes DE to HL before the next shift.
NINTMUL:
    LD A,H                  ; Extract the left sign from its high byte.
    XOR D                   ; A differing right sign makes the product negative.
    AND 80H                 ; Retain only the product sign bit.
    LD (NPRODSGN),A            ; Save the sign while multiplying unsigned magnitudes.
    BIT 7,H                 ; A negative left word needs two's-complement negation.
    CALL NZ,NWORDNEG        ; 8000H remains the unsigned magnitude 32768.
    EX DE,HL                ; DE becomes the left magnitude; HL becomes the right.
    BIT 7,H                 ; Check the right operand sign.
    CALL NZ,NWORDNEG        ; Convert it to an unsigned magnitude too.
    LD B,H                  ; BC is the remaining multiplier.
    LD C,L                  ; Copy its low byte without changing DE.
    LD HL,0                 ; HL accumulates the unsigned product from zero.
NMULLOOP:
    LD A,B                  ; Test both bytes of the remaining multiplier.
    OR C                    ; Zero means no further partial products remain.
    JP Z,NMULDONE             ; Finish even when the multiplicand is large.
    BIT 0,C                 ; The low multiplier bit selects this partial product.
    JP Z,NMULSHFT            ; A zero bit contributes nothing to the sum.
    ADD HL,DE               ; Add the current shifted multiplicand to the product.
    JP C,NOVERFLW              ; An unsigned 16-bit carry already exceeds either bound.
NMULSHFT:
    SRL B                   ; Shift the multiplier right, high byte first.
    RR C                    ; Carry transfers the old B bit 0 into C bit 7.
    LD A,B                  ; Check whether another multiplier bit remains.
    OR C                    ; Combine both remaining bytes for the zero test.
    JP Z,NMULDONE             ; Avoid rejecting a shift that would never be used.
    SLA E                   ; Double the multiplicand, low byte first.
    RL D                    ; Carry joins the bytes and reports bit 15 leaving DE.
    JP C,NOVERFLW              ; A lost high bit with more multiplier bits means overflow.
    JP NMULLOOP               ; Accumulate the next selected partial product.
NMULDONE:
    LD A,(NPRODSGN)            ; Recover the sign of the mathematical product.
    OR A                    ; Zero selects the nonnegative result bound.
    JP Z,NMULPOS              ; Positive magnitudes must be at most 32767.
    LD A,H                  ; Negative magnitudes may reach exactly 32768.
    CP 80H                  ; Compare the high byte against that boundary.
    JP C,NMULNEG              ; Anything below 8000H fits after negation.
    JP NZ,NOVERFLW             ; Anything above the boundary high byte overflows.
    LD A,L                  ; At high byte 80H, only a zero low byte fits.
    OR A                    ; Check for the one permitted boundary value 8000H.
    JP NZ,NOVERFLW             ; Reject magnitudes 8001H through 80FFH.
NMULNEG:
    CALL NWORDNEG           ; Apply the negative sign, including 8000H -> 8000H.
    JP NINTGOOD               ; Return the checked exact product.
NMULPOS:
    BIT 7,H                 ; A set high bit exceeds the positive signed limit.
    JP NZ,NOVERFLW             ; Reject positive magnitudes of 32768 or greater.
    JP NINTGOOD               ; Return the nonnegative exact product.
