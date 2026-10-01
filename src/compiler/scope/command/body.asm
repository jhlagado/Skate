; Scope compiler body and tail-context management.
;
; Body frames preserve definition, recursion and tail-call state while
; nested expressions are read and emitted.

; Compile each body expression immediately, then use the following reader
; event to decide whether its recorded tail calls need ordinary continuations.
SCBODY:
        POP DE                     ; Move the caller return below the body frame.
        LD A,(SCTMARK)             ; Nested bodies share this expression cursor.
        PUSH AF                    ; Restore it before the enclosing body resumes.
        LD A,(SCTCTX)              ; Save the caller's tail context.
        PUSH AF                    ; Frame word seven: previous tail context.
        LD A,(SCTTOP)              ; Save pending tail-call records from an outer body.
        PUSH AF                    ; Frame word six: previous tail-record top.
        LD A,(SCBMODE)             ; Save the enclosing body's candidate mode.
        PUSH AF                    ; Frame word five: previous candidate mode.
        LD A,(SCBISOL)             ; Save whether this body is isolated.
        PUSH AF                    ; Frame word four: requested isolation state.
        LD A,(SCBODYN)             ; Preserve the previous expression count.
        PUSH AF                    ; Frame word three: previous body count.
        LD A,(SCBTAIL)             ; Preserve the previous body tail flag.
        PUSH AF                    ; Frame word two: previous body tail flag.
        LD A,(SCBEV)               ; Preserve the previous current event.
        PUSH AF                    ; Frame word one: previous event kind.
        LD A,(SCBTAG)              ; Preserve the previous current tag.
        PUSH AF                    ; Frame word zero: previous scalar tag.
        LD HL,(SCBVAL)             ; Preserve the previous current payload.
        PUSH HL                    ; Body payload completes the saved frame.
        LD A,(SCRECST)             ; Preserve any enclosing recursive slot range.
        PUSH AF
        LD A,(SCRECLIM)            ; Preserve its recursive range limit.
        PUSH AF
        LD A,(SCRECPR)             ; Preserve its owning procedure.
        PUSH AF
        LD A,(SCRECPND)            ; Preserve its deferred-record marker.
        PUSH AF
        LD A,(SCRECPHS)            ; Preserve its initializer phase.
        PUSH AF
        LD A,(SCRECMOD)            ; Preserve its recursive-scope mode.
        PUSH AF
        LD A,(SCBDEFIN)            ; Preserve the enclosing definition permission.
        PUSH AF
        PUSH DE                    ; Restore the caller return above the frame.
        LD A,(SCTCTX)              ; The incoming context belongs to this body.
        LD (SCBTAIL),A             ; Only a final expression keeps this flag.
        LD A,(SCBISOL)             ; Record whether this body owns a private list.
        LD (SCBMODE),A
        XOR A                      ; Nested begin and let bodies share their list.
        LD (SCBISOL),A
        LD A,(SCRECMOD)             ; Keep a recursive initializer phase through lambdas.
        OR A
        JR NZ,SCBKEEPR              ; letrec/internal-definition lambdas need forwards.
        XOR A                      ; Ordinary bodies close the outer initializer phase.
        LD (SCRECPHS),A             ; No forward cells are created after initialization.
SCBKEEPR:
        LD A,(SCBMODE)              ; Only a procedure-owned body accepts defines.
        LD (SCBDEFIN),A             ; Nested begin and cond bodies leave it clear.
        LD A,(SCBMODE)
        CP 1
        JR NZ,SCBKEEP              ; Shared and let bodies retain outer candidates.
        XOR A                      ; A procedure body starts a private candidate list.
        LD (SCTTOP),A
SCBKEEP:
        XOR A                      ; Start with no expressions in this body.
        LD (SCBODYN),A             ; Empty bodies remain a syntax error.
        LD A,(SCBMODE)             ; Procedure bodies may begin with definitions.
        OR A
        JR Z,SCBDEFNO
        CALL SCDEFCAP              ; Install the leading names before replay.
        JP C,SCBFAIL
SCBDEFNO:
SCBREAD:
        CALL SCNEXT                ; Read one body expression or its closing parenthesis.
        JR NC,SCBRDOK
        JP SCBFAIL                 ; Restore the frame after a reader failure.
SCBRDOK:
        CP 2                       ; A close before an expression is invalid.
        JR NZ,SCBRNCL
        JP SCBFAIL                 ; Report an empty body after balanced cleanup.
SCBRNCL:
        OR A                       ; EOF cannot close an open body.
        JR NZ,SCBRNEOF
        JP SCBFAIL                 ; Report an incomplete body after cleanup.
SCBRNEOF:
        LD (SCBEV),A               ; Preserve the event until SCEXPE dispatches it.
        LD (SCBVAL),HL             ; Preserve the event payload.
        LD A,(RTAG)                ; Preserve its scalar tag.
        LD (SCBTAG),A              ; Structural events ignore this field.
SCBEXPR:
        XOR A                      ; A definition marker belongs only to SCIDEF.
        LD (SCISDEF),A
        LD A,(SCTTOP)              ; Remember tail records made by this expression.
        LD (SCTMARK),A             ; Non-final expressions will rewrite those calls.
        LD A,(SCBTAIL)             ; Give the expression the body's incoming context.
        LD (SCTCTX),A              ; Tail candidates use a wrapper until finality is known.
        LD A,(SCBTAG)              ; Restore the event's reader tag.
        LD (RTAG),A
        LD A,(SCBEV)               ; Restore the event kind for SCEXPE.
        LD HL,(SCBVAL)             ; Restore its payload for SCEXPE.
        CALL SCEXPE                ; Compile this complete expression immediately.
        JR NC,SCBEXPOK             ; Continue after a successful body expression.
        JP SCBFAIL                 ; No later event is consumed on expression failure.
SCBEXPOK:
        LD A,(SCISDEF)              ; Definitions do not count as body expressions.
        OR A
        JP NZ,SCBDEFOK
        XOR A                      ; The first ordinary expression seals definitions.
        LD (SCBDEFIN),A
        LD (SCRESV),HL             ; Save the expression result before reading ahead.
        LD (SCREST),A              ; Preserve its tag across the reader call.
        LD A,(SCBODYN)             ; Count the completed body expression.
        INC A
        LD (SCBODYN),A
        CALL SCNEXT                ; The next event distinguishes final from non-final.
        JR NC,SCBNXOK
        JP SCBFAIL                 ; The expression result is discarded on source failure.
SCBNXOK:
        CP 2                       ; A close leaves the preceding expression final.
        JP Z,SCBFINAL              ; Leave tail wrappers intact for the final value.
        OR A                       ; EOF cannot terminate a body.
        JR NZ,SCBNXEOF
        JP SCBFAIL                 ; Reject an incomplete body.
SCBNXEOF:
        LD (SCBEV),A               ; Save the next expression while rewriting candidates.
        LD (SCBVAL),HL             ; Preserve its payload across SCTFIX.
        LD A,(RTAG)                ; Preserve its logical scalar tag.
        LD (SCBTAG),A
        CALL SCTFIX                ; Non-final tail calls become ordinary calls.
        JR NC,SCBTFOK
        JP SCBFAIL
SCBTFOK:
        JP SCBEXPR                ; Compile the saved next event without rereading.
SCBDEFOK:
        JP SCBREAD                 ; Continue through the leading definition region.
SCBFINAL:
        LD HL,(SCRESV)             ; Recover the final expression payload.
        LD A,(SCREST)              ; Recover its final expression tag.
        CALL SCBREST               ; Restore caller scratch and the continuation.
        LD HL,(SCRESV)             ; Restore the body value after frame cleanup.
        LD A,(SCREST)              ; Restore the body tag after frame cleanup.
        OR A                       ; Return carry clear with the final value.
        RET
SCBFAIL:
        LD A,(SCRECAUT)             ; An unfinished definition replay owns a frame.
        OR A
        JR Z,SCBFAILR
        CALL SCRECPOP
SCBFAILR:
        CALL SCBREST               ; Restore all body fields and the continuation.
        SCF                        ; Preserve the reader or expression failure.
        RET                        ; No partially compiled body is accepted.

; Restore one saved body frame.  The helper is called with its frame on top.
SCBREST:
        POP BC                     ; Save the continuation after this helper call.
        POP DE                     ; Recover the caller continuation below the frame.
        POP AF                     ; Restore leading-definition permission.
        LD (SCBDEFIN),A
        POP AF                     ; Restore the enclosing recursive mode.
        LD (SCRECMOD),A
        POP AF                     ; Restore the enclosing recursive phase.
        LD (SCRECPHS),A
        POP AF                     ; Restore the enclosing deferred-record marker.
        LD (SCRECPND),A
        POP AF                     ; Restore the enclosing owning procedure.
        LD (SCRECPR),A
        POP AF                     ; Restore the enclosing recursive range limit.
        LD (SCRECLIM),A
        POP AF                     ; Restore the enclosing recursive-range start.
        LD (SCRECST),A
        POP HL                     ; Restore the previous body payload.
        LD (SCBVAL),HL             ; Publish it before returning to the caller.
        POP AF                     ; Restore the previous scalar tag.
        LD (SCBTAG),A              ; Preserve it for another nested body.
        POP AF                     ; Restore the previous event kind.
        LD (SCBEV),A               ; Publish the old current event.
        POP AF                     ; Restore the previous incoming tail flag.
        LD (SCBTAIL),A             ; Publish the old body context.
        POP AF                     ; Restore the previous body count.
        LD (SCBODYN),A             ; Publish the old expression count.
        POP AF                     ; Restore the caller's isolation request.
        LD (SCBISOL),A
        LD A,(SCBMODE)             ; Private bodies restore their candidate top.
        CP 1
        JR NZ,SCBKEEPT
        POP AF                     ; Restore the enclosing body's candidate mode.
        LD (SCBMODE),A
        POP AF                     ; Restore the enclosing candidate top.
        LD (SCTTOP),A
        JR SCBMODDN
SCBKEEPT:
        POP AF                     ; Restore the enclosing body's candidate mode.
        LD (SCBMODE),A
        POP AF                     ; Discard the shared body's saved candidate top.
SCBMODDN:
        POP AF                     ; Restore the caller's tail context.
        LD (SCTCTX),A              ; Nested forms see their original context again.
        POP AF                     ; Restore the enclosing expression's tail cursor.
        LD (SCTMARK),A             ; A nested body must not change its caller's mark.
        PUSH DE                    ; Restore the caller continuation below the helper.
        PUSH BC                    ; Return to the success or failure continuation.
        RET                        ; The frame is balanced on every exit path.
