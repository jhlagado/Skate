;=============================================================================
;  Skate value ABI 2 numeric dispatch
;=============================================================================

;  PURPOSE
;  -------
;  Validate tagged values and dispatch integer or binary16 operations.

;  PUBLIC INTERFACE
;  ----------------
;

;  VALUE REPRESENTATION
;  --------------------
;
;  TAG  REPRESENTATION
;  0    binary16 scalar
;  3    exact signed 16-bit integer

;+---------------------------------------------------------------------------+
;|  UNARY - NCLASS and NNEG; classify or negate one tagged value.            |
;|                                                                           |
;|  CALL                                                                     |
;|    A = tag; HL = payload.                                                 |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  BINARY - NADD, NSUB, NMUL, NDIV and NCMP; operate on two values.         |
;|                                                                           |
;|  CALL                                                                     |
;|    A/B = operand tags; HL/DE = operand payloads.                          |
;+---------------------------------------------------------------------------+

;  RESULTS
;  -------
;
;  ARITHMETIC  A = result tag; HL = result payload; carry clear.
;  COMPARISON  NCMP returns A = 0 and this code in HL:
;                FFFFH  less
;                0000H  equal
;                0001H  greater
;                0002H  unordered
;
;  ERROR       Carry set; A = 1 for type error or A = 2 for exact overflow.
;              HL retains the original left value.

;  REGISTERS AND WORKSPACE
;  -----------------------
;
;  BC/DE/flags are clobbered; IX/IY are preserved; SP is balanced.
;  NOALLOC. Requires binary16.asm.
;  Static workspace makes this module non-reentrant.
;=============================================================================

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

NEND:                      ; Exclusive end of numeric-dispatch instructions.
; Private static operands and scratch. Calls may also use binary16 workspace.
NWORK:
NORIGVAL: DW 0                 ; Original left/unary word returned on failure.
NLEFTWK: DW 0                    ; Working left payload; later its converted float.
NRIGHTWK: DW 0                    ; Original right payload.
NLEFTTG: DB 0                   ; Original left representation tag.
NRIGHTTG: DB 0                   ; Original right representation tag.
; Store BC together so setting operation C does not disturb input A/B.
NOPCODE: DW 0                   ; Low byte: operation 0..3. High byte: saved B, unused.
NPRODSGN: DB 0                 ; Product sign: 00H nonnegative, 80H negative.
NREVORD: DB 0                  ; Mixed-comparison order: 0 normal, 1 reversed.
NINTCMP: DW 0                    ; Exact integer in a mixed comparison.
NFLOATV: DW 0                    ; Original binary16 word in a mixed comparison.
NTRUNCV: DW 0                    ; Float truncated toward zero to a signed word.
NWEND:                     ; Exclusive end of private numeric workspace.
