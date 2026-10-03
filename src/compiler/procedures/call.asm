; Compiler application calls and tail-call emission.
; Entry points: SCAPARGS, SCINVOKE and SCITAIL.
; Procedure forms for the compact compiler.
;
; A procedure value is a tagged pointer to a fixed descriptor.  Descriptors
; name the generated body and its formal slots.  The runtime saves ordinary
; formals around a call; slots referenced by an escaping nested lambda remain
; live so the closure and its creator share the same cell.

; Compile a general application.  The operator value has already been emitted
; and each argument is pushed as A:HL, with the callee below the arguments.
SCAPARGS:
        LD A,(ST_TAIL)             ; Save whether the complete call is tail code.
        LD (ST_ATAIL),A            ; Arguments themselves are never tail code.
        XOR A                      ; No argument has been staged yet.
        LD (ST_ARGS),A             ; The runtime receives this bounded count.
SCAPLOOP:
        CALL SCNEXT                ; Read one argument or the application's close.
        RET C                      ; Preserve a source failure before emission.
        CP 2                       ; A close ends the argument sequence.
        JR Z,SCAPDONE              ; Zero-argument calls are valid.
        CP 0                       ; EOF cannot terminate an application.
        JP Z,SCAPSY                ; Report an incomplete call.
        LD (ST_AEV),A              ; Preserve the event kind across CMD_EXPR.
        LD (ST_AVAL),HL            ; Save the reader payload before CMD_EXPR reads it.
        LD A,(RD_TAG)              ; The scalar tag is one byte in the reader state.
        LD (ST_ATAG),A             ; Preserve it while CMD_EXPR reads the argument.
        LD A,(ST_ARGS)             ; The packet has a deliberately small bound.
        CP 8                       ; Eight values cover the first procedure tests.
        JP NC,ERR_CAP              ; A larger call would overrun the runtime packet.
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
        JP C,SCAPERR               ; Balance the saved application state on failure.
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
        JR SCAPLOOP                ; Continue in source order.
SCAPDONE:
        LD A,(ST_ROUTE)            ; A compact global call needs no callee value.
        CP 3
        JR Z,SCAPPRIM              ; A known primitive is named inline.
        OR A
        JR Z,SCAPGEND
        XOR A
        LD (ST_ROUTE),A
        LD A,(ST_ATAIL)            ; Reuse the normal tail decision for the saved value.
        OR A
        JR NZ,SCAPOTL
        LD HL,INV_OP                ; Dispatch the saved operator value.
        JP SCINVOKE
SCAPOTL:
        LD A,2                      ; SCITAIL selects the side-stack tail wrapper.
        LD (ST_ROUTE),A
        LD HL,INV_OPTL
        JP SCITAIL
SCAPGEND:
        LD A,(ST_ATAIL)            ; Recover the application's tail context.
        OR A                       ; A tail call uses a jump through the runtime.
        JR NZ,SCAPTAIL             ; The target returns directly to our caller.
        LD HL,INV_CALL            ; Ordinary calls preserve the current return.
        JP SCINVOKE                ; Emit the count load and runtime CALL.
SCAPTAIL:
        LD HL,INV_TAIL             ; Tail calls reuse the current return address.
        JP SCITAIL                 ; Emit the count load and runtime JP.

; Emit CALL PRIM_OP, or a patchable CALL PRIM_TL in tail position, then the
; primitive's payload byte and the argument count.
SCAPPRIM:
        LD A,(ST_ATAIL)
        OR A
        JR NZ,SCAPPTL
        LD (ST_ROUTE),A            ; A is zero: the call is complete.
        LD HL,PRIM_OP
        CALL EM_CALL
        RET C
        JR SCAPPKB
SCAPPTL:
        LD A,0CDH                  ; CALL, kept patchable for EM_PLAIN.
        CALL SINKBYTE
        RET C
        LD HL,(ST_PC)
        CALL EM_TAIL               ; Mode three records a primitive candidate.
        RET C
        XOR A
        LD (ST_ROUTE),A
        LD HL,PRIM_TL
        CALL EM_WORD
        RET C
SCAPPKB:
        LD A,(ST_GCALL)            ; The primitive's one-based kind.
        DEC A
        ADD A,20H                  ; Its value's payload low byte.
        CALL SINKBYTE
        RET C
        LD A,(ST_ARGS)             ; The argument count.
        JP SINKBYTE

; Remove the four compiler-stack words left by a failed nested argument.
SCAPERR:
        POP AF                     ; Discard the saved global slot.
        POP AF                     ; Discard the saved compact-call mode.
        POP AF                     ; Discard the saved tail decision.
        POP AF                     ; Discard the saved argument count.
        SCF                        ; Preserve the nested expression failure.
        RET                        ; The enclosing application is abandoned.
SCAPSY:
        LD HL,M_APPLY
        LD (ST_ERROR),HL
        JP ERR_BAD

; Emit A=argument-count followed by CALL or JP HL.  The runtime entry receives
; the callee and arguments from the generated native stack.
SCINVOKE:
        LD (ST_WORD),HL            ; Keep the selected runtime entry address.
        LD A,3EH                   ; LD A,n supplies the packet count.
        CALL SINKBYTE                ; Append the opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD A,(ST_ARGS)             ; Recover the count after the opcode write.
        CALL SINKBYTE                ; Append the count byte.
        RET C                      ; Preserve staged-output exhaustion.
        LD HL,(ST_WORD)            ; Restore the runtime target after SCBYTE.
        JP EM_CALL                 ; Append CALL nn for an ordinary application.

SCITAIL:
        LD (ST_WORD),HL            ; Keep the selected tail helper address.
        LD A,3EH                   ; LD A,n supplies the packet count.
        CALL SINKBYTE                ; Append the opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD A,(ST_ARGS)             ; Recover the count after the opcode write.
        CALL SINKBYTE                ; Append the count byte.
        RET C                      ; Preserve staged-output exhaustion.
        LD A,0CDH                  ; CALL first gives the body a patchable candidate.
        CALL SINKBYTE                ; Append the tail transfer opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD HL,(ST_PC)              ; The following word names the tail wrapper.
        CALL EM_TAIL               ; Keep it until body finality is known.
        RET C                      ; Preserve tail-record capacity exhaustion.
        LD HL,INV_TC                ; The normal wrapper discards CALL's continuation.
        LD A,(ST_ROUTE)
        CP 2
        JR NZ,SCITWR
        LD HL,INV_OPTC             ; Side-stack calls use their matching wrapper.
        XOR A
        LD (ST_ROUTE),A
SCITWR:
        JP EM_WORD                 ; Append its absolute address.
