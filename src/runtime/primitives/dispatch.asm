; Primitive argument packing and service dispatch.
; Entry points: PKT_PACK, OPS_PUSH/OPS_POP and PRIM_RUN.
; Included in runtime order by ../primitives.asm.

; Predefined arithmetic procedure values for the scope-control runtime.
;
; Primitive values use tag zero and payloads from FE20H below PRIM_LIM.  The
; dispatcher validates packet arity, pushes values in the numeric ABI order,
; and returns through the continuation supplied in IX.

; Pack arguments, then recover the operator value saved before evaluation.
PKT_PACK:
        POP IX                   ; Save the PKT_PACK helper return address.
        LD B,A                   ; B counts values still on the native stack.
        LD C,A                   ; C is the packet index, starting at count-1.
        LD A,B                   ; A supplies the zero-count test below.
        OR A
        JP Z,.OPERATOR           ; A nullary call skips directly to the side pop.
        DEC C
.LOOP:
        LD L,C                   ; Address packet entry C.
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,ARG_PKT
        ADD HL,DE
        POP DE                   ; One reverse-pushed argument's payload.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        POP DE                   ; Its byte 2 in E and tag in D.
        LD (HL),E
        INC HL
        LD A,D
        OR CELL_VAL              ; A live record and its tag.
        LD (HL),A
        DEC C
        DJNZ .LOOP
.OPERATOR:
        CALL OPS_POP             ; Recover the value evaluated before arguments.
        LD (ARG_TAG),A
        LD A,(ARG_CNT)           ; Arguments have been copied out of the native stack.
        LD B,A
        CALL ROOT_CUT
        LD A,(ARG_TAG)
        PUSH IX                  ; Restore the PKT_PACK helper return address.
        RET

; Save A:CHL on the fixed side stack used for operator values. The area between
; the heap ceiling and native-stack guard does not consume either resource.
OPS_PUSH:
%IF PROBE
        CALL PROBE
%ENDIF
        LD (ARG_TAG),A           ; Preserve the value tag while finding the top.
        LD (ARG_VAL),HL          ; Preserve the payload across the bounds check.
        LD HL,(OPS_SP)           ; The side cursor grows upward in four-byte steps.
        LD DE,4
        ADD HL,DE
        LD DE,RT_OPHI
        OR A
        SBC HL,DE
        JP NC,ERROR               ; Too many nested operators is a runtime error.
        LD (DESC_PTR),HL          ; Retain the checked new cursor.
        LD HL,(OPS_SP)
        LD DE,(ARG_VAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (HL),C                 ; Byte 2.
        INC HL
        LD A,(ARG_TAG)
        LD (HL),A                 ; The tag; the cursor, not a flag, marks it live.
        INC HL
        LD (OPS_SP),HL
        RET

; Pop the most recent operator value from the fixed side stack.
OPS_POP:
        LD HL,(OPS_SP)
        LD DE,RT_OPLO
        OR A
        SBC HL,DE
        JP Z,ERROR                ; A missing operator is a malformed call.
        LD HL,(OPS_SP)
        LD DE,4
        OR A
        SBC HL,DE
        LD (OPS_SP),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD C,(HL)                 ; Byte 2.
        INC HL
        LD A,(HL)
        AND 0FH
        EX DE,HL
        RET

; Dispatch a predefined primitive through the checked numeric ABI as either a
; normal application continuation or the current procedure epilogue. Packet
; values are read directly so a primitive call adds no argument stack frame.
PRIM_RUN:
        XOR A                       ; Normal primitive calls do not use apply-tail mode.
        LD (APPLY_TL),A
        LD (FRM_SAVE),IX            ; Every packet result returns through the clearer.
        LD IX,.RETIRE               ; The clearer removes the packet roots first.
        LD A,(PRIM_ID)             ; Kinds zero through three are numeric primitives.
        CP 4
        JP C,PRIM_ALU              ; +, -, *, and zero? share numeric validation.
        CP 14
        JP C,PRIM_DAT              ; Existing pair, list and output services.
        CP 16
        JP C,PRIM_QR               ; quotient and remainder are integer-only.
        CP 21
        JP C,PRIM_CMP              ; Five numeric comparisons accept two or more.
        JP Z,PRIM_NOT               ; not is the first unary logical predicate.
        CP 29
        JP C,PRIM_IS                ; Type predicates occupy the remaining IDs.
        CP 31
        JP C,PRIM_IO                 ; Character output and console input follow EOF.
        CP 32
        JP C,PRIM_ALU                ; Division is zero-based runtime kind thirty-one.
        CP 39
        JP C,STR_PRIM                 ; String and character operations follow division.
        CP 45
        JP Z,APPLY                    ; Apply spreads a checked proper list into a call.
        JP C,VEC_PRIM                 ; Vector operations use the preceding range.
        CP 54
        JP C,PORT_OP                  ; Standard ports follow the vector services.
        CP 60
        JP C,FILE_OP                   ; File ports use the same provider boundary.
        CP PRIM_LIM-20H
        JP C,STD_DISP                  ; Standard procedures added later.
        JP ERROR                   ; The reserved range has no other services.

; Primitive paths use PUSH IX/RET, so one common continuation can retire the
; packet after the operation has finished and any constructor GC has returned.
.RETIRE:
        CALL RT_WIDEN              ; Byte 2 for every sixteen-bit result.
        LD (ARG_TAG),A
        LD (ARG_VAL),HL
        XOR A
        LD (ARG_CNT),A
        LD A,(ARG_TAG)
        LD HL,(ARG_VAL)
        LD IX,(FRM_SAVE)
        JP (IX)
