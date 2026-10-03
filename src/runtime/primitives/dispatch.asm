; Primitive argument packing and service dispatch.
; Entry points: SRTPACKO, SRTOPUSH/SRTOPPOP and SRTPRIM.
; Included in runtime order by ../primitives.asm.

; Predefined arithmetic procedure values for the scope-control runtime.
;
; Primitive values use tag zero and payloads from FE20H below PRIM_LIM.  The
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
        XOR A
        LD (HL),A                ; The extension byte stays clear.
        INC HL
        LD A,(SRTATMP)
        OR CELL_VAL              ; A live record and its tag.
        LD (HL),A
        DEC C
        DJNZ SRTPKGL
SRTPKGZ:
        CALL SRTOPPOP            ; Recover the value evaluated before arguments.
        LD (SRTATMP),A
        LD A,(SRTARGC)           ; Arguments have been copied out of the native stack.
        LD B,A
        CALL ROOT_CUT
        LD A,(SRTATMP)
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
        LD DE,RT_OPHI
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
        XOR A
        LD (HL),A                 ; The extension byte stays clear.
        INC HL
        LD A,(SRTATMP)
        LD (HL),A                 ; The tag; the cursor, not a flag, marks it live.
        INC HL
        LD (SRTOPS),HL
        RET

; Pop the most recent operator value from the fixed side stack.
SRTOPPOP:
        LD HL,(SRTOPS)
        LD DE,RT_OPLO
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
        INC HL
        LD A,(HL)
        AND 0FH
        EX DE,HL
        RET

; Dispatch a predefined primitive through the checked numeric ABI as either a
; normal application continuation or the current procedure epilogue. Packet
; values are read directly so a primitive call adds no argument stack frame.
SRTPRIM:
        XOR A                       ; Normal primitive calls do not use apply-tail mode.
        LD (APPLY_TL),A
        LD (SRTRET),IX              ; Every packet result returns through the clearer.
        LD IX,SRTPKRET              ; The clearer removes the packet roots first.
        LD A,(SRTPID)              ; Kinds zero through three are numeric primitives.
        CP 4
        JP C,SRTPNUM               ; +, -, *, and zero? share numeric validation.
        CP 14
        JP C,SRTDAT                ; Existing pair, list and output services.
        CP 16
        JP C,SRTPQRM               ; quotient and remainder are integer-only.
        CP 21
        JP C,SRTCMP                ; Five numeric comparisons accept two or more.
        JP Z,SRTNOT                 ; not is the first unary logical predicate.
        CP 29
        JP C,SRTTYPE                ; Type predicates occupy the remaining IDs.
        CP 31
        JP C,SRTIO                   ; Character output and console input follow EOF.
        CP 32
        JP C,SRTPNUM                 ; Division is zero-based runtime kind thirty-one.
        CP 39
        JP C,STR_PRIM                 ; String and character operations follow division.
        CP 45
        JP Z,APPLY                    ; Apply spreads a checked proper list into a call.
        JP C,SRTVEC                   ; Vector operations use the preceding range.
        CP 54
        JP C,SRTPORTS                 ; Standard ports follow the vector services.
        CP 60
        JP C,SRTFILE                   ; File ports use the same provider boundary.
        CP PRIM_LIM-20H
        JP C,STD_DISP                  ; Standard procedures added later.
        JP SRTERROR                ; The reserved range has no other services.

; Primitive paths use PUSH IX/RET, so one common continuation can retire the
; packet after the operation has finished and any constructor GC has returned.
SRTPKRET:
        LD (SRTATMP),A
        LD (SRTVAL),HL
        XOR A
        LD (SRTARGC),A
        LD A,(SRTATMP)
        LD HL,(SRTVAL)
        LD IX,(SRTRET)
        JP (IX)
