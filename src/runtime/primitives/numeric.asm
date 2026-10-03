; Primitive numeric validation, folding and comparisons.
; Entry points: PRIM_NUM, PRIM_ALU, .DIVIDE and PRIM_CMP.
; Included in runtime order by ../primitives.asm.

; Validate one logical numeric value. Tag three is exact integer; tag zero is
; binary16 except for the reserved booleans, sentinels and primitive values.
PRIM_NUM:
        LD (SRTNTAG),A
        CP 3
        JR Z,.OK
        OR A
        JR NZ,.FAIL
        LD (SRTNVAL),HL
        LD HL,(SRTNVAL)
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
        LD HL,(SRTNVAL)
        LD A,H
        CP 0FFH
        JR Z,.FAIL                ; FFxx is the reserved byte-character range.
        LD A,(SRTNTAG)
        CALL NCLASS
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
        LD A,(SRTARGC)              ; Walk exactly the values in the packet.
        LD (SRTNLEFT),A             ; The counter is independent of packet contents.
        OR A
        JR Z,.DONE                   ; Empty + and * calls have no values to check.
        LD HL,SRTARGPK              ; Begin at the first four-byte value record.
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
        EX DE,HL                    ; NCLASS receives the payload in HL.
        CALL PRIM_NUM               ; Accept exact integers and valid numeric scalars.
        POP HL                      ; Restore the packet cursor after classification.
        JP C,SRTERROR               ; Every arithmetic argument must be a number.
        LD A,(SRTNLEFT)
        DEC A
        LD (SRTNLEFT),A
        JR NZ,.LOOP
.DONE:
        RET

; Fold +, -, and * with the exact identities and one-argument subtraction.
PRIM_ALU:
        CALL PKT_NUMS               ; Validate the whole packet before arithmetic.
        LD A,(SRTPID)
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
        LD A,(SRTARGC)               ; Read the number of operands in the packet.
        OR A                         ; Division has no identity for an empty call.
        JP Z,SRTERROR                ; Report the invalid zero-argument form.
        CP 1                          ; A unary call computes the reciprocal of its value.
        JR Z,.DIV_ONE                ; Keep the one accumulator identity for that case.
        LD HL,SRTARGPK                ; Read the first operand as the binary16 dividend.
        CALL PKT_VAL                  ; Recover its payload and logical tag.
        LD (SRTNACCV),HL              ; The first operand starts a left fold.
        LD (SRTNACCT),A               ; Preserve its exact or inexact representation.
        LD A,(SRTARGC)                ; The first operand has already been consumed.
        DEC A                         ; Leave the number of divisors to fold.
        LD (SRTNLEFT),A               ; Preserve the remaining operand count.
        LD HL,SRTARGPK+4              ; The next record is the second source operand.
        LD (SRTNPTR),HL               ; Keep the packet cursor across NDIV.
        JR .DIV_LOOP                  ; Fold the remaining operands from left to right.
.DIV_ONE:
        LD (SRTNLEFT),A               ; Unary division consumes its sole operand below.
        XOR A                         ; Tag zero identifies the binary16 accumulator.
        LD (SRTNACCT),A              ; Start with an inexact result representation.
        LD HL,3C00H                  ; Binary16 1.0 is the left-fold identity.
        LD (SRTNACCV),HL             ; Store the initial reciprocal accumulator.
        LD HL,SRTARGPK               ; Begin at the first packed argument.
        LD (SRTNPTR),HL              ; Keep the packet cursor across NDIV.
.DIV_LOOP:
        LD HL,(SRTNPTR)              ; Load the next four-byte argument record.
        CALL PKT_VAL                 ; Recover its payload in HL and tag in A.
        LD (SRTNVAL),HL              ; Preserve the right payload for the ABI.
        LD (SRTNTAG),A               ; Preserve the right tag while loading the left.
        LD HL,(SRTNACCV)             ; Load the current binary16 accumulator.
        LD DE,(SRTNVAL)              ; Load the next operand payload.
        LD A,(SRTNTAG)               ; Put the right operand tag in the ABI's B register.
        LD B,A                       ; Preserve that tag while restoring the left tag.
        LD A,(SRTNACCT)              ; Put the accumulator tag in the ABI's A register.
        CALL NDIV                    ; Divide the accumulator by the next operand.
        JP C,SRTERROR                ; Reject a bad operand or invalid result.
        LD (SRTNACCV),HL             ; Save the binary16 quotient payload.
        LD (SRTNACCT),A              ; Save its successful result tag.
        LD HL,(SRTNPTR)              ; Advance one fixed-width argument record.
        LD DE,4                      ; Each packed value occupies four bytes.
        ADD HL,DE                    ; Point at the next value in the packet.
        LD (SRTNPTR),HL              ; Preserve the advanced cursor.
        LD A,(SRTNLEFT)              ; Decrement the number of values remaining.
        DEC A                        ; One operand has now been folded.
        LD (SRTNLEFT),A              ; Publish the updated count.
        JR NZ,.DIV_LOOP              ; Continue until every operand is consumed.
        JP .RESULT                   ; Return the accumulated binary16 result.
.PLUS:
        LD A,3                      ; Exact integer zero is the empty-sum identity.
        LD (SRTNACCT),A
        XOR A
        LD H,A
        LD L,A
        JR .FOLD
.TIMES:
        LD A,3                      ; Exact integer one is the empty-product identity.
        LD (SRTNACCT),A
        LD HL,1
        JR .FOLD
.MINUS:
        LD A,(SRTARGC)
        OR A
        JP Z,SRTERROR               ; Subtraction requires at least one operand.
        CP 1
        JR NZ,.FOLD                 ; Two or more operands use left subtraction.
        LD HL,SRTARGPK
        CALL PKT_VAL
        CALL NNEG                   ; Unary subtraction is checked negation.
        JP C,SRTERROR
        PUSH IX
        RET
.FOLD:
        LD (SRTNACCV),HL            ; Keep the current folded payload.
        LD A,(SRTARGC)
        OR A
        JR Z,.RESULT                ; + and * return their identities at arity zero.
        LD HL,SRTARGPK
        CALL PKT_VAL
        LD (SRTNACCV),HL            ; First argument replaces the identity.
        LD (SRTNACCT),A
        LD A,(SRTARGC)
        DEC A
        LD (SRTNLEFT),A
        LD HL,SRTARGPK+4
        LD (SRTNPTR),HL
.OP_LOOP:
        LD A,(SRTNLEFT)
        OR A
        JR Z,.RESULT
        LD HL,(SRTNPTR)
        CALL PKT_VAL
        LD (SRTNVAL),HL
        LD (SRTNTAG),A
        LD HL,(SRTNACCV)
        LD DE,(SRTNVAL)
        LD A,(SRTNTAG)
        LD B,A
        LD A,(SRTPID)
        LD C,A
        LD A,C
        OR A
        JR Z,.OP_ADD
        CP 1
        JR Z,.OP_SUB
        LD A,(SRTNACCT)
        CALL NMUL
        JR .OP_CHK
.OP_ADD:
        LD A,(SRTNACCT)
        CALL NADD
        JR .OP_CHK
.OP_SUB:
        LD A,(SRTNACCT)
        CALL NSUB
.OP_CHK:
        JP C,SRTERROR
        LD (SRTNACCV),HL
        LD (SRTNACCT),A
        LD HL,(SRTNPTR)
        LD DE,4
        ADD HL,DE
        LD (SRTNPTR),HL
        LD A,(SRTNLEFT)
        DEC A
        LD (SRTNLEFT),A
        JR .OP_LOOP
.RESULT:
        LD A,(SRTNACCT)
        LD HL,(SRTNACCV)
        PUSH IX
        RET

; zero? accepts exact integers and both signed binary16 zero encodings.
.IS_ZERO:
        LD A,(SRTARGC)
        CP 1
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL PKT_VAL
        LD (SRTNVAL),HL              ; Preserve the payload while validating its tag.
        LD (SRTNTAG),A               ; Keep the tag for the exact/inexact zero tests.
        CALL PRIM_NUM                ; Reject booleans, characters and other sentinels.
        JP C,SRTERROR                ; zero? reports a type error for non-numbers.
        LD A,(SRTNTAG)               ; Select the exact integer or binary16 zero test.
        CP 3
        JR Z,.ZERO_INT               ; Exact zero is the all-zero signed word.
        LD HL,(SRTNVAL)              ; Binary16 zero ignores only its sign bit.
        LD A,H
        AND 7FH                       ; Discard the sign while retaining exponent/fraction.
        OR L
        JP Z,PKT_YES                 ; Both +0.0 and -0.0 compare as zero.
        JP PKT_NO                    ; Every other finite or special number is nonzero.
.ZERO_INT:
        LD HL,(SRTNVAL)              ; Restore the exact integer payload.
        LD A,H
        OR L
        JP Z,PKT_YES                 ; The exact zero payload is 0000H.
        JP PKT_NO                    ; Any nonzero exact integer is false.

; quotient and remainder require exactly two exact-integer arguments.
PRIM_QR:
        LD A,(SRTARGC)
        CP 2
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL PKT_VAL
        LD (SRTNACCV),HL
        LD (SRTNACCT),A
        LD HL,SRTARGPK+4
        CALL PKT_VAL
        LD (SRTNVAL),HL
        LD (SRTNTAG),A
        LD A,(SRTNTAG)
        LD B,A
        LD HL,(SRTNACCV)
        LD DE,(SRTNVAL)
        LD A,(SRTPID)
        LD C,A
        LD A,C
        CP 14
        JR Z,.QUOTIENT
        LD A,(SRTNACCT)
        CALL NREM
        JR .CHECK
.QUOTIENT:
        LD A,(SRTNACCT)
        CALL NQUOT
.CHECK:
        JP C,SRTERROR
        PUSH IX
        RET

; Compare each adjacent numeric pair after validating the complete packet.
PRIM_CMP:
        LD A,(SRTARGC)
        CP 2
        JP C,SRTERROR
        CALL PKT_NUMS
        LD HL,SRTARGPK
        CALL PKT_VAL
        LD (SRTNACCV),HL
        LD (SRTNACCT),A
        LD A,(SRTARGC)
        DEC A
        LD (SRTNLEFT),A
        LD HL,SRTARGPK+4
        LD (SRTNPTR),HL
.LOOP:
        LD A,(SRTNLEFT)
        OR A
        JP Z,PKT_YES
        LD HL,(SRTNPTR)
        CALL PKT_VAL
        LD (SRTNVAL),HL
        LD (SRTNTAG),A
        LD HL,(SRTNACCV)
        LD DE,(SRTNVAL)
        LD A,(SRTNTAG)
        LD B,A
        LD A,(SRTNACCT)
        CALL NCMP
        JP C,SRTERROR
        LD (SRTCCOD),HL
        CALL .RELATION
        OR A
        JP Z,PKT_NO
        LD HL,(SRTNVAL)
        LD (SRTNACCV),HL
        LD A,(SRTNTAG)
        LD (SRTNACCT),A
        LD HL,(SRTNPTR)
        LD DE,4
        ADD HL,DE
        LD (SRTNPTR),HL
        LD A,(SRTNLEFT)
        DEC A
        LD (SRTNLEFT),A
        JR .LOOP

; Turn NCMP's -1, 0, +1 and unordered codes into the selected relation.
.RELATION:
        LD A,(SRTCCOD+1)
        OR A
        JR NZ,.NEGATIVE
        LD A,(SRTCCOD)
        OR A
        JR Z,.ZERO
        CP 1
        JR Z,.POSITIVE
        XOR A                      ; Unordered comparisons are always false.
        RET
.NEGATIVE:
        CP 0FFH
        JR NZ,.BAD
        LD A,(SRTCCOD)
        CP 0FFH
        JR NZ,.BAD
        LD A,(SRTPID)
        CP 17                       ; < accepts the negative code.
        JR Z,.YES
        CP 19                       ; <= also accepts the negative code.
        JR Z,.YES
        JR .NO
.ZERO:
        LD A,(SRTPID)
        CP 16                       ; = accepts equality.
        JR Z,.YES
        CP 19                       ; <= and >= accept equality.
        JR Z,.YES
        CP 20
        JR Z,.YES
        JR .NO
.POSITIVE:
        LD A,(SRTPID)
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
