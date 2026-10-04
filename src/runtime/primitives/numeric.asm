; Primitive numeric validation, folding and comparisons.
; Entry points: PRIM_NUM, PRIM_ALU, .DIVIDE and PRIM_CMP.
; Included in runtime order by ../primitives.asm.

; Validate one logical numeric value. Tag three is exact integer; tag zero is
; binary16 except for the reserved booleans, sentinels and primitive values.
PRIM_NUM:
        LD (NUM_TAG),A
        CP 3
        JR Z,.OK
        OR A
        JR NZ,.FAIL
        LD (NUM_VAL),HL
        LD HL,(NUM_VAL)
        LD A,H
        CP 0FEH
        JR NZ,.FLOAT
        LD A,L
        CP 2
        JR C,.FAIL
        CP 5
        JR C,.FAIL
        CP 20H
        JR C,.FLOAT
        CP PRIM_LIM
        JR C,.FAIL                ; FE20H upward are reserved primitive values.
.FLOAT:
        LD HL,(NUM_VAL)
        LD A,H
        CP 0FFH
        JR Z,.FAIL                ; FFxx is the reserved byte-character range.
        LD A,(NUM_TAG)
        CALL NUM_CHK
        RET
.OK:
        OR A
        RET
.FAIL:
        SCF
        RET

; Validate every packet value before folding any result.  This preserves the
; language rule that a later type error is not hidden by an earlier overflow.
PKT_NUMS:
        LD A,(ARG_CNT)              ; Walk exactly the values in the packet.
        LD (NUM_LEFT),A             ; The counter is independent of packet contents.
        OR A
        JR Z,.DONE                   ; Empty + and * calls have no values to check.
        LD HL,ARG_PKT               ; Begin at the first four-byte value record.
.LOOP:
        LD E,(HL)                   ; Recover the payload low byte.
        INC HL
        LD D,(HL)                   ; Recover the payload high byte.
        INC HL
        INC HL                      ; Skip the extension byte.
        LD A,(HL)
        AND 0FH                     ; Recover the logical value tag.
        INC HL                      ; Step to the next record.
        PUSH HL                     ; Preserve the next packet address.
        EX DE,HL                    ; NUM_CHK receives the payload in HL.
        CALL PRIM_NUM               ; Accept exact integers and valid numeric scalars.
        POP HL                      ; Restore the packet cursor after classification.
        JP C,ERROR                  ; Every arithmetic argument must be a number.
        LD A,(NUM_LEFT)
        DEC A
        LD (NUM_LEFT),A
        JR NZ,.LOOP
.DONE:
        RET

; Fold +, -, and * with the exact identities and one-argument subtraction.
PRIM_ALU:
        CALL PKT_NUMS               ; Validate the whole packet before arithmetic.
        LD A,(PRIM_ID)
        CP 31
        JP Z,.DIVIDE                 ; Division always produces a binary16 value.
        CP 3
        JP Z,.IS_ZERO               ; Kind three is the unary zero? predicate.
        CP 0
        JP Z,.PLUS                  ; The division implementation widened this dispatch span.
        CP 1
        JP Z,.MINUS                 ; Use an absolute branch for the later subtraction block.
        JP .TIMES                   ; The division block makes the old short jump too far.

; Fold division from the binary16 value one.  This gives unary reciprocal
; semantics and keeps every integer/integer result in the inexact domain.
.DIVIDE:
        LD A,(ARG_CNT)               ; Read the number of operands in the packet.
        OR A                         ; Division has no identity for an empty call.
        JP Z,ERROR                   ; Report the invalid zero-argument form.
        CP 1                          ; A unary call computes the reciprocal of its value.
        JR Z,.DIV_ONE                ; Keep the one accumulator identity for that case.
        LD HL,ARG_PKT                 ; Read the first operand as the binary16 dividend.
        CALL PKT_VAL                  ; Recover its payload and logical tag.
        LD (NUM_ACC),HL               ; The first operand starts a left fold.
        LD (NUM_ATAG),A               ; Preserve its exact or inexact representation.
        LD A,C
        LD (NUM_AEXT),A
        LD A,(ARG_CNT)                ; The first operand has already been consumed.
        DEC A                         ; Leave the number of divisors to fold.
        LD (NUM_LEFT),A               ; Preserve the remaining operand count.
        LD HL,ARG_PKT+4               ; The next record is the second source operand.
        LD (NUM_PTR),HL               ; Keep the packet cursor across NUM_DIV.
        JR .DIV_LOOP                  ; Fold the remaining operands from left to right.
.DIV_ONE:
        LD (NUM_LEFT),A               ; Unary division consumes its sole operand below.
        XOR A                         ; Tag zero identifies the binary16 accumulator.
        LD (NUM_ATAG),A              ; Start with an inexact result representation.
        LD (NUM_AEXT),A
        LD HL,3C00H                  ; Binary16 1.0 is the left-fold identity.
        LD (NUM_ACC),HL              ; Store the initial reciprocal accumulator.
        LD HL,ARG_PKT                ; Begin at the first packed argument.
        LD (NUM_PTR),HL              ; Keep the packet cursor across NUM_DIV.
.DIV_LOOP:
        LD HL,(NUM_PTR)              ; The next argument record is the right operand.
        LD DE,NUM_Y
        LD BC,4
        LDIR
        LD HL,(NUM_ACC)              ; Load the current accumulator.
        LD A,(NUM_AEXT)
        LD C,A
        LD A,(NUM_ATAG)              ; Put the accumulator tag in the ABI's A register.
        CALL NUM_DIV                 ; Divide the accumulator by the next operand.
        JP C,ERROR                   ; Reject a bad operand or invalid result.
        LD (NUM_ACC),HL              ; Save the binary16 quotient payload.
        LD (NUM_ATAG),A              ; Save its successful result tag.
        LD A,C
        LD (NUM_AEXT),A
        LD HL,(NUM_PTR)              ; Advance one fixed-width argument record.
        LD DE,4                      ; Each packed value occupies four bytes.
        ADD HL,DE                    ; Point at the next value in the packet.
        LD (NUM_PTR),HL              ; Preserve the advanced cursor.
        LD A,(NUM_LEFT)              ; Decrement the number of values remaining.
        DEC A                        ; One operand has now been folded.
        LD (NUM_LEFT),A              ; Publish the updated count.
        JR NZ,.DIV_LOOP              ; Continue until every operand is consumed.
        JP .RESULT                   ; Return the accumulated binary16 result.
.PLUS:
        LD A,3                      ; Exact integer zero is the empty-sum identity.
        LD (NUM_ATAG),A
        XOR A
        LD H,A
        LD L,A
        JR .FOLD
.TIMES:
        LD A,3                      ; Exact integer one is the empty-product identity.
        LD (NUM_ATAG),A
        LD HL,1
        JR .FOLD
.MINUS:
        LD A,(ARG_CNT)
        OR A
        JP Z,ERROR                  ; Subtraction requires at least one operand.
        CP 1
        JR NZ,.FOLD                 ; Two or more operands use left subtraction.
        LD HL,ARG_PKT
        CALL PKT_VAL
        CALL NUM_NEG                ; Unary subtraction is checked negation.
        JP C,ERROR
        PUSH IX
        RET
.FOLD:
        LD (NUM_ACC),HL             ; Keep the current folded payload.
        XOR A
        LD (NUM_AEXT),A             ; Both identities have byte 2 zero.
        LD A,(ARG_CNT)
        OR A
        JR Z,.RESULT                ; + and * return their identities at arity zero.
        LD HL,ARG_PKT
        CALL PKT_VAL
        LD (NUM_ACC),HL             ; First argument replaces the identity.
        LD (NUM_ATAG),A
        LD A,C
        LD (NUM_AEXT),A
        LD A,(ARG_CNT)
        DEC A
        LD (NUM_LEFT),A
        LD HL,ARG_PKT+4
        LD (NUM_PTR),HL
.OP_LOOP:
        LD A,(NUM_LEFT)
        OR A
        JR Z,.RESULT
        LD HL,(NUM_PTR)             ; The next packet record is the right operand.
        LD DE,NUM_Y
        LD BC,4
        LDIR
        LD HL,(NUM_ACC)
        LD A,(NUM_AEXT)
        LD C,A
        LD A,(PRIM_ID)
        OR A
        JR Z,.OP_ADD
        CP 1
        JR Z,.OP_SUB
        LD A,(NUM_ATAG)
        CALL NUM_MUL
        JR .OP_CHK
.OP_ADD:
        LD A,(NUM_ATAG)
        CALL NUM_ADD
        JR .OP_CHK
.OP_SUB:
        LD A,(NUM_ATAG)
        CALL NUM_SUB
.OP_CHK:
        JP C,ERROR
        LD (NUM_ACC),HL
        LD (NUM_ATAG),A
        LD A,C
        LD (NUM_AEXT),A
        LD HL,(NUM_PTR)
        LD DE,4
        ADD HL,DE
        LD (NUM_PTR),HL
        LD A,(NUM_LEFT)
        DEC A
        LD (NUM_LEFT),A
        JR .OP_LOOP
.RESULT:
        LD A,(NUM_AEXT)
        LD C,A
        LD A,(NUM_ATAG)
        LD HL,(NUM_ACC)
        PUSH IX
        RET

; zero? accepts exact integers and both signed binary16 zero encodings.
.IS_ZERO:
        LD A,(ARG_CNT)
        CP 1
        JP NZ,ERROR
        LD HL,ARG_PKT
        CALL PKT_VAL
        LD (NUM_VAL),HL              ; Preserve the payload while validating its tag.
        LD (NUM_TAG),A               ; Keep the tag for the exact/inexact zero tests.
        LD A,C
        LD (NUM_VEXT),A
        LD A,(NUM_TAG)
        CALL PRIM_NUM                ; Reject booleans, characters and other sentinels.
        JP C,ERROR                   ; zero? reports a type error for non-numbers.
        LD A,(NUM_TAG)               ; Select the exact integer or binary16 zero test.
        CP 3
        JR Z,.ZERO_INT               ; Exact zero is the all-zero signed word.
        LD HL,(NUM_VAL)              ; Binary16 zero ignores only its sign bit.
        LD A,H
        AND 7FH                       ; Discard the sign while retaining exponent/fraction.
        OR L
        JP Z,PKT_YES                 ; Both +0.0 and -0.0 compare as zero.
        JP PKT_NO                    ; Every other finite or special number is nonzero.
.ZERO_INT:
        LD HL,(NUM_VAL)              ; Restore the exact integer payload.
        LD A,(NUM_VEXT)
        OR H
        OR L
        JP Z,PKT_YES                 ; Exact zero has every payload byte clear.
        JP PKT_NO                    ; Any nonzero exact integer is false.

; quotient and remainder require exactly two exact-integer arguments.
PRIM_QR:
        LD A,(ARG_CNT)
        CP 2
        JP NZ,ERROR
        LD HL,ARG_PKT+4             ; The divisor is the ABI's right cell.
        LD DE,NUM_Y
        LD BC,4
        LDIR
        LD HL,ARG_PKT
        CALL PKT_VAL                ; The dividend is the left value.
        LD B,A
        LD A,(PRIM_ID)
        CP 14
        LD A,B
        JR Z,.QUOTIENT
        CALL NUM_REM
        JR .CHECK
.QUOTIENT:
        CALL NUM_QUOT
.CHECK:
        JP C,ERROR
        PUSH IX
        RET

; Compare each adjacent numeric pair after validating the complete packet.
PRIM_CMP:
        LD A,(ARG_CNT)
        CP 2
        JP C,ERROR
        CALL PKT_NUMS
        LD HL,ARG_PKT
        CALL PKT_VAL
        LD (NUM_ACC),HL
        LD (NUM_ATAG),A
        LD A,C
        LD (NUM_AEXT),A
        LD A,(ARG_CNT)
        DEC A
        LD (NUM_LEFT),A
        LD HL,ARG_PKT+4
        LD (NUM_PTR),HL
.LOOP:
        LD A,(NUM_LEFT)
        OR A
        JP Z,PKT_YES
        LD HL,(NUM_PTR)             ; The next packet record is the right operand.
        LD DE,NUM_Y
        LD BC,4
        LDIR
        LD HL,(NUM_ACC)
        LD A,(NUM_AEXT)
        LD C,A
        LD A,(NUM_ATAG)
        CALL NUM_CMP
        JP C,ERROR
        LD (NUM_REL),HL
        CALL .RELATION
        OR A
        JP Z,PKT_NO
        LD HL,(NUM_Y)               ; The right value becomes the next left.
        LD (NUM_ACC),HL
        LD A,(NUM_Y+2)
        LD (NUM_AEXT),A
        LD A,(NUM_Y+3)
        LD (NUM_ATAG),A
        LD HL,(NUM_PTR)
        LD DE,4
        ADD HL,DE
        LD (NUM_PTR),HL
        LD A,(NUM_LEFT)
        DEC A
        LD (NUM_LEFT),A
        JR .LOOP

; Turn NUM_CMP's -1, 0, +1 and unordered codes into the selected relation.
.RELATION:
        LD A,(NUM_REL+1)
        OR A
        JR NZ,.NEGATIVE
        LD A,(NUM_REL)
        OR A
        JR Z,.ZERO
        CP 1
        JR Z,.POSITIVE
        XOR A                      ; Unordered comparisons are always false.
        RET
.NEGATIVE:
        CP 0FFH
        JR NZ,.BAD
        LD A,(NUM_REL)
        CP 0FFH
        JR NZ,.BAD
        LD A,(PRIM_ID)
        CP 17                       ; < accepts the negative code.
        JR Z,.YES
        CP 19                       ; <= also accepts the negative code.
        JR Z,.YES
        JR .NO
.ZERO:
        LD A,(PRIM_ID)
        CP 16                       ; = accepts equality.
        JR Z,.YES
        CP 19                       ; <= and >= accept equality.
        JR Z,.YES
        CP 20
        JR Z,.YES
        JR .NO
.POSITIVE:
        LD A,(PRIM_ID)
        CP 18                       ; > accepts a positive code.
        JR Z,.YES
        CP 20                       ; >= accepts a positive code.
        JR Z,.YES
        JR .NO
.BAD:
        XOR A
        RET
.YES:
        LD A,1
        RET
.NO:
        XOR A
        RET
