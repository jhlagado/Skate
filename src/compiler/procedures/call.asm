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
        LD A,(SCTCTX)              ; Save whether the complete call is tail code.
        LD (SCTLSAV),A             ; Arguments themselves are never tail code.
        XOR A                      ; No argument has been staged yet.
        LD (SCARGN),A              ; The runtime receives this bounded count.
SCAPLOOP:
        CALL SCNEXT                ; Read one argument or the application's close.
        RET C                      ; Preserve a source failure before emission.
        CP 2                       ; A close ends the argument sequence.
        JR Z,SCAPDONE              ; Zero-argument calls are valid.
        CP 0                       ; EOF cannot terminate an application.
        JP Z,SCAPSY                ; Report an incomplete call.
        LD (SCAPEV),A              ; Preserve the event kind across SCEXPE.
        LD (SCAPVAL),HL            ; Save the reader payload before SCEXPE reads it.
        LD A,(RTAG)                ; The scalar tag is one byte in the reader state.
        LD (SCAPTAG),A             ; Preserve it while SCEXPE reads the argument.
        LD A,(SCARGN)              ; The packet has a deliberately small bound.
        CP 8                       ; Eight values cover the first procedure tests.
        JP NC,SCCAP                ; A larger call would overrun the runtime packet.
        XOR A                      ; The argument expression is not tail-position.
        LD (SCTCTX),A              ; Nested calls therefore retain their return.
        LD A,(SCAPTAG)             ; Restore the reader's scalar tag byte.
        LD (RTAG),A                ; Symbol and list events ignore this field.
        LD A,(SCAPEV)              ; Restore the event kind for SCEXPE.
        LD HL,(SCAPVAL)            ; Restore its interned ID or numeric payload.
        LD A,(SCARGN)              ; Preserve this application's count across recursion.
        PUSH AF                     ; A nested application uses the same scratch byte.
        LD A,(SCTLSAV)             ; Preserve this application's tail decision as well.
        PUSH AF                     ; The nested parser may replace the shared value.
        LD A,(SCAPMODE)            ; Preserve this application's marker mode as well.
        PUSH AF                     ; Nested operators may select a different mode.
        LD A,(SCAPGSL)             ; Preserve this application's global slot as well.
        PUSH AF                     ; Nested operators may select a different slot.
        LD A,(SCAPTAG)             ; Restore the reader's scalar tag after saving state.
        LD (RTAG),A                ; Symbol and list events ignore this field.
        LD A,(SCAPEV)              ; Restore the event kind for SCEXPE.
        LD HL,(SCAPVAL)            ; Restore its interned ID or numeric payload.
        CALL SCEXPE                ; Compile the argument expression.
        JR C,SCAPERR               ; Balance the saved application state on failure.
        POP AF                     ; Restore the enclosing global slot.
        LD (SCAPGSL),A
        POP AF                     ; Restore the enclosing compact-call mode.
        LD (SCAPMODE),A
        POP AF                     ; Restore the enclosing application's tail decision.
        LD (SCTLSAV),A             ; Its next argument still belongs to that call.
        POP AF                     ; Restore the enclosing argument count.
        LD (SCARGN),A              ; Count the value only after its expression returns.
        CALL SCPUSH                ; Stage the resulting value below later args.
        RET C                      ; Preserve a generated-output capacity failure.
        LD A,(SCARGN)              ; Count the value only after it was emitted.
        INC A                      ; The next packet position follows this one.
        LD (SCARGN),A              ; Publish the complete argument count.
        JR SCAPLOOP                ; Continue in source order.
SCAPDONE:
        LD A,(SCAPMODE)            ; A compact global call needs no callee value.
        CP 3
        JR Z,SCAPPRIM              ; A known primitive is named inline.
        OR A
        JR Z,SCAPGEND
        XOR A
        LD (SCAPMODE),A
        LD A,(SCTLSAV)             ; Reuse the normal tail decision for the saved value.
        OR A
        JR NZ,SCAPOTL
        LD HL,SRTOPINV              ; Dispatch the saved operator value.
        JP SCINVOKE
SCAPOTL:
        LD A,2                      ; SCITAIL selects the side-stack tail wrapper.
        LD (SCAPMODE),A
        LD HL,SRTOTAIL
        JP SCITAIL
SCAPGEND:
        LD A,(SCTLSAV)             ; Recover the application's tail context.
        OR A                       ; A tail call uses a jump through the runtime.
        JR NZ,SCAPTAIL             ; The target returns directly to our caller.
        LD HL,SRTINVOK            ; Ordinary calls preserve the current return.
        JP SCINVOKE                ; Emit the count load and runtime CALL.
SCAPTAIL:
        LD HL,SRTTAIL              ; Tail calls reuse the current return address.
        JP SCITAIL                 ; Emit the count load and runtime JP.

; Emit LD A,count, CALL PRIM_OP or PRIM_TL, then the primitive's payload byte.
SCAPPRIM:
        LD A,(SCTLSAV)
        OR A
        JR NZ,SCAPPTL
        LD (SCAPMODE),A            ; A is zero: the call is complete.
        LD HL,PRIM_OP
        CALL SCINVOKE
        RET C
        JR SCAPPKB
SCAPPTL:
        LD HL,PRIM_TL              ; SCITAIL records the candidate as mode three.
        CALL SCITAIL
        RET C
SCAPPKB:
        LD A,(SCAPGSL)             ; The primitive's one-based kind.
        DEC A
        ADD A,20H                  ; Its value's payload low byte.
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
        LD HL,SCAPTXT
        LD (SCERRPTR),HL
        JP SCSYN

; Emit A=argument-count followed by CALL or JP HL.  The runtime entry receives
; the callee and arguments from the generated native stack.
SCINVOKE:
        LD (SCWTMP),HL             ; Keep the selected runtime entry address.
        LD A,3EH                   ; LD A,n supplies the packet count.
        CALL SINKBYTE                ; Append the opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD A,(SCARGN)              ; Recover the count after the opcode write.
        CALL SINKBYTE                ; Append the count byte.
        RET C                      ; Preserve staged-output exhaustion.
        LD HL,(SCWTMP)             ; Restore the runtime target after SCBYTE.
        JP SCCALL                  ; Append CALL nn for an ordinary application.

SCITAIL:
        LD (SCWTMP),HL             ; Keep the selected tail helper address.
        LD A,3EH                   ; LD A,n supplies the packet count.
        CALL SINKBYTE                ; Append the opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD A,(SCARGN)              ; Recover the count after the opcode write.
        CALL SINKBYTE                ; Append the count byte.
        RET C                      ; Preserve staged-output exhaustion.
        LD A,0CDH                  ; CALL first gives the body a patchable candidate.
        CALL SINKBYTE                ; Append the tail transfer opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD HL,(SCPC)               ; The following word names the tail wrapper.
        CALL SCTSAVE               ; Keep it until body finality is known.
        RET C                      ; Preserve tail-record capacity exhaustion.
        LD HL,SRTTCALL              ; The normal wrapper discards CALL's continuation.
        LD A,(SCAPMODE)
        CP 3
        JR NZ,SCITSIDE
        LD HL,PRIM_TL              ; A direct primitive tail call.
        XOR A
        LD (SCAPMODE),A
        JR SCITWR
SCITSIDE:
        CP 2
        JR NZ,SCITWR
        LD HL,SRTOTCL              ; Side-stack calls use their matching wrapper.
        XOR A
        LD (SCAPMODE),A
SCITWR:
        JP SCWORD                  ; Append its absolute address.
