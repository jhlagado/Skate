; Compiler application calls and tail-call emission.
; Entry points: CALL_ARG, CALL_RUN and CALL_JP.
; Procedure forms for the compact compiler.
;
; A procedure value is a tagged pointer to a fixed descriptor.  Descriptors
; name the generated body and its formal slots.  The runtime saves ordinary
; formals around a call; slots referenced by an escaping nested lambda remain
; live so the closure and its creator share the same cell.

; Compile a general application.  The operator value has already been emitted
; and each argument is pushed as A:HL, with the callee below the arguments.
CALL_ARG:
        LD A,(ST_TAIL)             ; Save whether the complete call is tail code.
        LD (ST_ATAIL),A            ; Arguments themselves are never tail code.
        XOR A                      ; No argument has been staged yet.
        LD (ST_ARGS),A             ; The runtime receives this bounded count.
.LOOP:
        CALL REC_NEXT              ; Read one argument or the application's close.
        RET C                      ; Preserve a source failure before emission.
        CP 2                       ; A close ends the argument sequence.
        JR Z,CALL_END              ; Zero-argument calls are valid.
        CP 0                       ; EOF cannot terminate an application.
        JP Z,CALL_BAD              ; Report an incomplete call.
        LD (ST_AEV),A              ; Preserve the event kind across CMD_EXPR.
        LD (ST_AVAL),HL            ; Save the reader payload before CMD_EXPR reads it.
        LD A,(RD_TAG)              ; The scalar tag is one byte in the reader state.
        LD (ST_ATAG),A             ; Preserve it while CMD_EXPR reads the argument.
        LD A,(ST_ARGS)             ; The runtime's packet holds ARG_MAX values.
        CP ARG_MAX
        JP NC,ERR_CAP
        XOR A                      ; The argument expression is not tail-position.
        LD (ST_TAIL),A             ; Nested calls therefore retain their return.
        LD A,(ST_ATAG)             ; Restore the reader's scalar tag byte.
        LD (RD_TAG),A              ; Symbol and list events ignore this field.
        LD A,(ST_AEV)              ; Restore the event kind for CMD_EXPR.
        LD HL,(ST_AVAL)            ; Restore its interned ID or numeric payload.
        LD A,(ST_ARGS)             ; Preserve this application's count across recursion.
        PUSH AF                     ; A nested application uses the same scratch byte.
        LD A,(ST_ATAIL)            ; Preserve this application's tail decision as well.
        PUSH AF                     ; The nested parser may replace the shared value.
        LD A,(ST_ROUTE)            ; Preserve this application's marker mode as well.
        PUSH AF                     ; Nested operators may select a different mode.
        LD A,(ST_GCALL)            ; Preserve this application's global slot as well.
        PUSH AF                     ; Nested operators may select a different slot.
        LD A,(ST_ATAG)             ; Restore the reader's scalar tag after saving state.
        LD (RD_TAG),A              ; Symbol and list events ignore this field.
        LD A,(ST_AEV)              ; Restore the event kind for CMD_EXPR.
        LD HL,(ST_AVAL)            ; Restore its interned ID or numeric payload.
        CALL CMD_EXPR              ; Compile the argument expression.
        JP C,CALL_ERR              ; Balance the saved application state on failure.
        POP AF                     ; Restore the enclosing global slot.
        LD (ST_GCALL),A
        POP AF                     ; Restore the enclosing compact-call mode.
        LD (ST_ROUTE),A
        POP AF                     ; Restore the enclosing application's tail decision.
        LD (ST_ATAIL),A            ; Its next argument still belongs to that call.
        POP AF                     ; Restore the enclosing argument count.
        LD (ST_ARGS),A             ; Count the value only after its expression returns.
        CALL EM_PUSH               ; Stage the resulting value below later args.
        RET C                      ; Preserve a generated-output capacity failure.
        LD A,(ST_ARGS)             ; Count the value only after it was emitted.
        INC A                      ; The next packet position follows this one.
        LD (ST_ARGS),A             ; Publish the complete argument count.
        JR .LOOP                   ; Continue in source order.
CALL_END:
        LD A,(ST_ROUTE)            ; A compact global call needs no callee value.
        CP 3
        JR Z,.PRIM                 ; A known primitive is named inline.
        OR A
        JR Z,.GENERAL
        XOR A
        LD (ST_ROUTE),A
        LD A,(ST_ATAIL)            ; Reuse the normal tail decision for the saved value.
        OR A
        JR NZ,.OP_TAIL
        LD HL,INV_OP                ; Dispatch the saved operator value.
        JR CALL_RUN
.OP_TAIL:
        LD A,2                      ; CALL_JP selects the side-stack tail wrapper.
        LD (ST_ROUTE),A
        LD HL,INV_OPTL
        JR CALL_JP
.GENERAL:
        LD A,(ST_ATAIL)            ; Recover the application's tail context.
        OR A                       ; A tail call uses a jump through the runtime.
        JR NZ,.TAIL                ; The target returns directly to our caller.
        LD HL,INV_CALL            ; Ordinary calls preserve the current return.
        JR CALL_RUN                ; Emit the count load and runtime CALL.
.TAIL:
        LD HL,INV_TAIL             ; Tail calls reuse the current return address.
        JR CALL_JP                 ; Emit the count load and runtime JP.

; Emit CALL PRIM_OP, or a patchable CALL PRIM_TL in tail position, then the
; primitive's payload byte and the argument count.
.PRIM:
        LD A,(ST_ATAIL)
        OR A
        JR NZ,.PRIM_TL
        LD (ST_ROUTE),A            ; A is zero: the call is complete.
        LD HL,PRIM_OP
        CALL EM_CALL
        RET C
        JR .PAYLOAD
.PRIM_TL:
        LD A,0CDH                  ; CALL, kept patchable for EM_PLAIN.
        CALL SINK_PUT
        RET C
        LD HL,(ST_PC)
        CALL EM_TAIL               ; Mode three records a primitive candidate.
        RET C
        XOR A
        LD (ST_ROUTE),A
        LD HL,PRIM_TL
        CALL EM_WORD
        RET C
.PAYLOAD:
        LD A,(ST_GCALL)            ; The primitive's one-based kind.
        DEC A
        ADD A,20H                  ; Its value's payload low byte.
        CALL SINK_PUT
        RET C
        LD A,(ST_ARGS)             ; The argument count.
        JP SINK_PUT

; Remove the four compiler-stack words left by a failed nested argument.
CALL_ERR:
        POP AF                     ; Discard the saved global slot.
        POP AF                     ; Discard the saved compact-call mode.
        POP AF                     ; Discard the saved tail decision.
        POP AF                     ; Discard the saved argument count.
        SCF                        ; Preserve the nested expression failure.
        RET                        ; The enclosing application is abandoned.
CALL_BAD:
        LD HL,M_APPLY
        LD (ST_ERROR),HL
        JP ERR_BAD

; Emit A=argument-count followed by CALL or JP HL.  The runtime entry receives
; the callee and arguments from the generated native stack.
CALL_RUN:
        LD (ST_WORD),HL            ; Keep the selected runtime entry address.
        LD A,3EH                   ; LD A,n supplies the packet count.
        CALL SINK_PUT                ; Append the opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD A,(ST_ARGS)             ; Recover the count after the opcode write.
        CALL SINK_PUT                ; Append the count byte.
        RET C                      ; Preserve staged-output exhaustion.
        LD HL,(ST_WORD)            ; Restore the runtime target after SINK_PUT.
        JP EM_CALL                 ; Append CALL nn for an ordinary application.

CALL_JP:
        LD (ST_WORD),HL            ; Keep the selected tail helper address.
        LD A,3EH                   ; LD A,n supplies the packet count.
        CALL SINK_PUT                ; Append the opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD A,(ST_ARGS)             ; Recover the count after the opcode write.
        CALL SINK_PUT                ; Append the count byte.
        RET C                      ; Preserve staged-output exhaustion.
        LD A,0CDH                  ; CALL first gives the body a patchable candidate.
        CALL SINK_PUT                ; Append the tail transfer opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD HL,(ST_PC)              ; The following word names the tail wrapper.
        CALL EM_TAIL               ; Keep it until body finality is known.
        RET C                      ; Preserve tail-record capacity exhaustion.
        LD HL,INV_TC                ; The normal wrapper discards CALL's continuation.
        LD A,(ST_ROUTE)
        CP 2
        JR NZ,.WRAPPER
        LD HL,INV_OPTC             ; Side-stack calls use their matching wrapper.
        XOR A
        LD (ST_ROUTE),A
.WRAPPER:
        JP EM_WORD                 ; Append its absolute address.
