; Scope compiler body and tail-context management.
;
; Body frames preserve definition, recursion and tail-call state while
; nested expressions are read and emitted.

; Compile each body expression immediately, then use the following reader
; event to decide whether its recorded tail calls need ordinary continuations.
CMD_BODY:
        POP DE                     ; Move the caller return below the body frame.
        LD A,(ST_MARK)             ; Nested bodies share this expression cursor.
        PUSH AF                    ; Restore it before the enclosing body resumes.
        LD A,(ST_TAIL)             ; Save the caller's tail context.
        PUSH AF                    ; Frame word seven: previous tail context.
        LD A,(ST_TAILS)            ; Save pending tail-call records from an outer body.
        PUSH AF                    ; Frame word six: previous tail-record top.
        LD A,(ST_BMODE)            ; Save the enclosing body's candidate mode.
        PUSH AF                    ; Frame word five: previous candidate mode.
        LD A,(ST_ALONE)            ; Save whether this body is isolated.
        PUSH AF                    ; Frame word four: requested isolation state.
        LD A,(ST_EXPRS)            ; Preserve the previous expression count.
        PUSH AF                    ; Frame word three: previous body count.
        LD A,(ST_BTAIL)            ; Preserve the previous body tail flag.
        PUSH AF                    ; Frame word two: previous body tail flag.
        LD A,(ST_EVENT)            ; Preserve the previous current event.
        PUSH AF                    ; Frame word one: previous event kind.
        LD A,(ST_EVTAG)            ; Preserve the previous current tag.
        PUSH AF                    ; Frame word zero: previous scalar tag.
        LD HL,(ST_EVVAL)           ; Preserve the previous current payload.
        PUSH HL                    ; Body payload completes the saved frame.
        LD A,(ST_RBASE)            ; Preserve any enclosing recursive slot range.
        PUSH AF
        LD A,(ST_RTOP)             ; Preserve its recursive range limit.
        PUSH AF
        LD A,(ST_RPROC)            ; Preserve its owning procedure.
        PUSH AF
        LD A,(ST_RPEND)            ; Preserve its deferred-record marker.
        PUSH AF
        LD A,(ST_RINIT)            ; Preserve its initializer phase.
        PUSH AF
        LD A,(ST_RMODE)            ; Preserve its recursive-scope mode.
        PUSH AF
        LD A,(ST_BDEF)             ; Preserve the enclosing definition permission.
        PUSH AF
        PUSH DE                    ; Restore the caller return above the frame.
        LD A,(ST_TAIL)             ; The incoming context belongs to this body.
        LD (ST_BTAIL),A            ; Only a final expression keeps this flag.
        LD A,(ST_ALONE)            ; Record whether this body owns a private list.
        LD (ST_BMODE),A
        XOR A                      ; Nested begin and let bodies share their list.
        LD (ST_ALONE),A
        LD A,(ST_RMODE)             ; Keep a recursive initializer phase through lambdas.
        OR A
        JR NZ,.KEEP_REC             ; letrec/internal-definition lambdas need forwards.
        XOR A                      ; Ordinary bodies close the outer initializer phase.
        LD (ST_RINIT),A             ; No forward cells are created after initialization.
.KEEP_REC:
        LD A,(ST_BMODE)             ; Only a procedure-owned body accepts defines.
        LD (ST_BDEF),A              ; Nested begin and cond bodies leave it clear.
        ; A procedure body's tail records stack above the enclosing body's
        ; pending records rather than restarting at zero.  The enclosing
        ; expression may still have to rewrite its own records once its
        ; finality is known, so they must survive the nested body.  .RESTORE
        ; discards this body's records by restoring the saved top.
.START:
        XOR A                      ; Start with no expressions in this body.
        LD (ST_EXPRS),A            ; Empty bodies remain a syntax error.
        LD A,(ST_BMODE)            ; Procedure bodies may begin with definitions.
        OR A
        JR Z,.NO_DEFS
        CALL DEF_LEAD              ; Install the leading names before replay.
        JP C,.FAIL
.NO_DEFS:
.READ:
        CALL REC_NEXT              ; Read one body expression or its closing parenthesis.
        JR NC,.READ_OK
        JP .FAIL                   ; Restore the frame after a reader failure.
.READ_OK:
        CP 2                       ; A close before an expression is invalid.
        JR NZ,.NO_CLOSE
        JP .FAIL                   ; Report an empty body after balanced cleanup.
.NO_CLOSE:
        OR A                       ; EOF cannot close an open body.
        JR NZ,.NO_EOF
        JP .FAIL                   ; Report an incomplete body after cleanup.
.NO_EOF:
        LD (ST_EVENT),A            ; Preserve the event until CMD_EXPR dispatches it.
        LD (ST_EVVAL),HL           ; Preserve the event payload.
        LD A,(RD_TAG)              ; Preserve its scalar tag.
        LD (ST_EVTAG),A            ; Structural events ignore this field.
.EXPR:
        XOR A                      ; A definition marker belongs only to DEF_BODY.
        LD (ST_ISDEF),A
        LD A,(ST_TAILS)            ; Remember tail records made by this expression.
        LD (ST_MARK),A             ; Non-final expressions will rewrite those calls.
        LD A,(ST_BTAIL)            ; Give the expression the body's incoming context.
        LD (ST_TAIL),A             ; Tail candidates use a wrapper until finality is known.
        LD A,(ST_EVTAG)            ; Restore the event's reader tag.
        LD (RD_TAG),A
        LD A,(ST_EVENT)            ; Restore the event kind for CMD_EXPR.
        LD HL,(ST_EVVAL)           ; Restore its payload for CMD_EXPR.
        CALL CMD_EXPR              ; Compile this complete expression immediately.
        JR NC,.EXPR_OK             ; Continue after a successful body expression.
        JP .FAIL                   ; No later event is consumed on expression failure.
.EXPR_OK:
        LD A,(ST_ISDEF)             ; Definitions do not count as body expressions.
        OR A
        JP NZ,.WAS_DEF
        XOR A                      ; The first ordinary expression seals definitions.
        LD (ST_BDEF),A
        LD (ST_VALUE),HL           ; Save the expression result before reading ahead.
        LD (ST_VTAG),A             ; Preserve its tag across the reader call.
        LD A,(ST_EXPRS)            ; Count the completed body expression.
        INC A
        LD (ST_EXPRS),A
        CALL REC_NEXT              ; The next event distinguishes final from non-final.
        JR NC,.NEXT_OK
        JP .FAIL                   ; The expression result is discarded on source failure.
.NEXT_OK:
        CP 2                       ; A close leaves the preceding expression final.
        JP Z,.FINAL                ; Leave tail wrappers intact for the final value.
        OR A                       ; EOF cannot terminate a body.
        JR NZ,.MORE
        JP .FAIL                   ; Reject an incomplete body.
.MORE:
        LD (ST_EVENT),A            ; Save the next expression while rewriting candidates.
        LD (ST_EVVAL),HL           ; Preserve its payload across EM_PLAIN.
        LD A,(RD_TAG)              ; Preserve its logical scalar tag.
        LD (ST_EVTAG),A
        CALL EM_PLAIN              ; Non-final tail calls become ordinary calls.
        JR NC,.FIXED
        JP .FAIL
.FIXED:
        JP .EXPR                  ; Compile the saved next event without rereading.
.WAS_DEF:
        JP .READ                   ; Continue through the leading definition region.
.FINAL:
        LD HL,(ST_VALUE)           ; Recover the final expression payload.
        LD A,(ST_VTAG)             ; Recover its final expression tag.
        CALL .RESTORE              ; Restore caller scratch and the continuation.
        LD HL,(ST_VALUE)           ; Restore the body value after frame cleanup.
        LD A,(ST_VTAG)             ; Restore the body tag after frame cleanup.
        OR A                       ; Return carry clear with the final value.
        RET
.FAIL:
        LD A,(ST_BACK)              ; An unfinished definition replay owns a frame.
        OR A
        JR Z,.FAIL_END
        CALL REC_POP
.FAIL_END:
        CALL .RESTORE              ; Restore all body fields and the continuation.
        SCF                        ; Preserve the reader or expression failure.
        RET                        ; No partially compiled body is accepted.

; Restore one saved body frame.  The helper is called with its frame on top.
.RESTORE:
        POP BC                     ; Save the continuation after this helper call.
        POP DE                     ; Recover the caller continuation below the frame.
        POP AF                     ; Restore leading-definition permission.
        LD (ST_BDEF),A
        POP AF                     ; Restore the enclosing recursive mode.
        LD (ST_RMODE),A
        POP AF                     ; Restore the enclosing recursive phase.
        LD (ST_RINIT),A
        POP AF                     ; Restore the enclosing deferred-record marker.
        LD (ST_RPEND),A
        POP AF                     ; Restore the enclosing owning procedure.
        LD (ST_RPROC),A
        POP AF                     ; Restore the enclosing recursive range limit.
        LD (ST_RTOP),A
        POP AF                     ; Restore the enclosing recursive-range start.
        LD (ST_RBASE),A
        POP HL                     ; Restore the previous body payload.
        LD (ST_EVVAL),HL           ; Publish it before returning to the caller.
        POP AF                     ; Restore the previous scalar tag.
        LD (ST_EVTAG),A            ; Preserve it for another nested body.
        POP AF                     ; Restore the previous event kind.
        LD (ST_EVENT),A            ; Publish the old current event.
        POP AF                     ; Restore the previous incoming tail flag.
        LD (ST_BTAIL),A            ; Publish the old body context.
        POP AF                     ; Restore the previous body count.
        LD (ST_EXPRS),A            ; Publish the old expression count.
        POP AF                     ; Restore the caller's isolation request.
        LD (ST_ALONE),A
        LD A,(ST_BMODE)            ; Private bodies restore their candidate top.
        CP 1
        JR NZ,.SHARED
        POP AF                     ; Restore the enclosing body's candidate mode.
        LD (ST_BMODE),A
        POP AF                     ; Restore the enclosing candidate top.
        LD (ST_TAILS),A
        JR .CONTEXT
.SHARED:
        POP AF                     ; Restore the enclosing body's candidate mode.
        LD (ST_BMODE),A
        POP AF                     ; Discard the shared body's saved candidate top.
.CONTEXT:
        POP AF                     ; Restore the caller's tail context.
        LD (ST_TAIL),A             ; Nested forms see their original context again.
        POP AF                     ; Restore the enclosing expression's tail cursor.
        LD (ST_MARK),A             ; A nested body must not change its caller's mark.
        PUSH DE                    ; Restore the caller continuation below the helper.
        PUSH BC                    ; Return to the success or failure continuation.
        RET                        ; The frame is balanced on every exit path.
