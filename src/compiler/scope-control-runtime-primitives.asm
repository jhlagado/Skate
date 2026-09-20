; Predefined arithmetic procedure values for the scope-control runtime.
;
; Primitive values use tag zero and payloads FE20H through FE23H.  The
; dispatcher validates packet arity, pushes values in the numeric ABI order,
; and returns through the continuation supplied in IX.

; Pack arguments, then recover the operator value saved before evaluation.
SRTPACKO:
        POP IX                   ; Save the SRTPACKO helper return address.
        LD B,A                   ; B counts values still on the native stack.
        LD C,A                   ; C is the packet index, starting at count-1.
        LD A,B                   ; A supplies the zero-count test below.
        OR A
        JP Z,SRTPKGZ             ; A nullary call skips directly to the side pop.
        DEC C
SRTPKGL:
        POP HL                   ; Recover one reverse-pushed argument payload.
        POP AF                   ; Recover its tag word.
        LD (SRTATMP),A           ; Preserve the tag while addressing the packet.
        LD (SRTVAL),HL           ; Preserve the payload while multiplying the index.
        LD L,C
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,SRTARGPK
        ADD HL,DE
        LD DE,(SRTVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(SRTATMP)
        LD (HL),A
        INC HL
        LD A,1
        LD (HL),A
        DEC C
        DJNZ SRTPKGL
SRTPKGZ:
        CALL SRTOPPOP            ; Recover the value evaluated before arguments.
        PUSH IX                  ; Restore the SRTPACKO helper return address.
        RET

; Save A:HL on the fixed side stack used for operator values. The area between
; the heap ceiling and native-stack guard does not consume either resource.
SRTOPUSH:
        LD (SRTATMP),A           ; Preserve the value tag while finding the top.
        LD (SRTVAL),HL           ; Preserve the payload across the bounds check.
        LD HL,(SRTOPS)           ; The side cursor grows upward in four-byte steps.
        LD DE,4
        ADD HL,DE
        LD DE,SRTOPEND
        OR A
        SBC HL,DE
        JP NC,SRTERROR            ; Too many nested operators is a runtime error.
        LD (SRTNEXT),HL           ; Retain the checked new cursor.
        LD HL,(SRTOPS)
        LD DE,(SRTVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(SRTATMP)
        LD (HL),A
        INC HL
        XOR A
        LD (HL),A                 ; The fourth byte keeps the record fixed-width.
        INC HL
        LD (SRTOPS),HL
        RET

; Pop the most recent operator value from the fixed side stack.
SRTOPPOP:
        LD HL,(SRTOPS)
        LD DE,SRTHEPEN
        OR A
        SBC HL,DE
        JP Z,SRTERROR             ; A missing operator is a malformed call.
        LD HL,(SRTOPS)
        LD DE,4
        OR A
        SBC HL,DE
        LD (SRTOPS),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        EX DE,HL
        RET

; Dispatch a predefined primitive through the checked numeric ABI as either a
; normal application continuation or the current procedure epilogue. Packet
; values are read directly so a primitive call adds no argument stack frame.
SRTPRIM:
        LD A,(SRTPID)              ; Kinds zero through two are binary operators.
        CP 3
        JR Z,SRTPZERO              ; Kind three is the unary zero? predicate.
        LD A,(SRTARGC)
        CP 2
        JP NZ,SRTERROR             ; Every binary primitive requires two operands.
        LD HL,SRTARGPK             ; Read the left packet payload and tag.
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        LD (SRTTAG),A              ; The numeric ABI expects the left tag in A.
        LD (SRTVAL),DE             ; Preserve the left payload while reading right.
        LD HL,SRTARGPK             ; Advance to the right packet record.
        INC HL
        INC HL
        INC HL
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD B,(HL)                  ; The numeric ABI expects the right tag in B.
        LD HL,(SRTVAL)             ; Restore the left payload for the ABI.
        LD A,(SRTPID)
        OR A
        JR Z,SRTPADD               ; Kind zero is addition.
        CP 1
        JR Z,SRPTSUB               ; Kind one is subtraction.
        JR SRPTMUL                 ; Kind two is multiplication.
SRTPADD:
        LD A,(SRTTAG)              ; Restore the left tag after selecting the op.
        CALL NADD                  ; Checked addition consumes the ABI registers.
        JP C,SRTERROR              ; Type or overflow failure is terminal.
        PUSH IX                    ; Return the checked result to the caller.
        RET
SRPTSUB:
        LD A,(SRTTAG)              ; Restore the left tag after selecting the op.
        CALL NSUB                  ; Checked subtraction consumes the ABI registers.
        JP C,SRTERROR
        PUSH IX
        RET
SRPTMUL:
        LD A,(SRTTAG)              ; Restore the left tag after selecting the op.
        CALL NMUL                  ; Checked multiplication consumes the ABI registers.
        JP C,SRTERROR
        PUSH IX
        RET
SRTPZERO:
        LD A,(SRTARGC)
        CP 1
        JP NZ,SRTERROR             ; zero? accepts one exact-integer operand.
        LD HL,SRTARGPK
        CALL SRTPVAL               ; Recover the packet value in A:HL.
        PUSH IX                    ; The predicate returns to the caller.
        JP SRTZERO

; Read a packet record at HL and return its tag in A and payload in HL.
SRTPVAL:
        LD E,(HL)                  ; Read payload low.
        INC HL
        LD D,(HL)                  ; Read payload high.
        INC HL
        LD A,(HL)                  ; Read the logical value tag.
        EX DE,HL                   ; Return the payload while discarding the cursor.
        RET

; A primitive tail call removes the current epilogue, then returns through it
; after the checked operation has consumed the packet values.
SRTTPRIM:
        CALL SRTIVAL               ; Validate and classify the reserved payload.
        POP IX                     ; The current frame's epilogue is now the return.
        JP SRTPRIM                 ; Evaluate with the reused procedure frame.
