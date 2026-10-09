; Binding forms for let, let*, letrec and named let.
;
; The entry points parse each form and share the scope-save, body and
; cleanup helpers below. Local and global table operations live beside
; their own data structures in the neighbouring binding modules.

; Parallel let: initializers see the outer locals; the body sees all new slots.
LET_FORM:
        LD A,1                     ; Parallel let also accepts a named procedure form.
        LD (ST_NLOK),A
        CALL LET_OPEN              ; Save local cursors and open the binding list.
        RET C                      ; Preserve a local-capacity failure.
.BINDING:
        CALL REC_NEXT              ; Read another binding list or the list close.
        JP C,LET_FAIL              ; Unwind the saved scope cursors on source failure.
        CP 2                       ; A close ends the parallel binding list.
        JR Z,.BODY                 ; Add the pending entries to the active scope.
        CP 1                       ; Every binding is itself a two-element list.
        JP NZ,LET_FAIL             ; A bare name or scalar is not a binding.
        CALL REC_NEXT              ; Read the binding name.
        JP C,LET_FAIL              ; Unwind the saved scope cursors on source failure.
        CP 5                       ; Names are interned symbols.
        JP NZ,LET_FAIL             ; Reject literal or list binding names.
        LD (ST_SYMID),HL           ; The pending entry receives this full identity.
        CALL BIND_NEW            ; Allocate a reusable local data slot.
        JP C,LET_FAIL              ; Reject the first slot beyond the local bound.
        LD (ST_SLOT),A             ; Save the selected slot for the pending entry.
        CALL LET_PUSH              ; Record the name and slot before recursive code.
        JP C,LET_FAIL              ; Pending-binding capacity is explicit.
        CALL LET_INIT              ; Initializer sees only the outer local scope.
        JP C,LET_FAIL              ; Preserve its syntax or capacity error.
        CALL LET_PEEK              ; Restore this binding's slot after nested forms.
        JP C,LET_FAIL              ; The pending record must still be present.
        LD A,(ST_SLOT)             ; Recover the pending slot number.
        LD L,A                     ; Pass it to the runtime store.
        LD A,1                     ; Kind one denotes a local slot.
        CALL EM_STORE              ; Emit the initialized flag update.
        JP C,LET_FAIL              ; A fixup failure is terminal.
        CALL CMD_END               ; Close the individual binding list.
        JP C,LET_FAIL              ; Reject a missing or extra binding expression.
        JR .BINDING                ; Read the next binding or the outer close.
.BODY:
        CALL BIND_ALL               ; Publish pending IDs in the active local scope.
        JP C,LET_FAIL              ; Reject a scope-stack overflow before body code.
        CALL LET_BODY              ; Compile the body, then consume its close.
        JP C,LET_FAIL              ; Preserve body failure before restoring cursors.
        JP LET_DONE                 ; Restore old local cursors and return its value.

; let* is the same syntax, but each binding becomes visible before the next one.
LET_STAR:
        XOR A                      ; let* has no named-procedure spelling.
        LD (ST_NLOK),A
        CALL LET_OPEN              ; Save local cursors and open the binding list.
        RET C                      ; Preserve a local-capacity failure.
.BINDING:
        CALL REC_NEXT              ; Read another binding or the list close.
        JP C,LET_FAIL              ; Unwind the saved scope cursors on source failure.
        CP 2                       ; A close ends the sequential binding list.
        JR Z,.BODY                 ; The body follows the final binding.
        CP 1                       ; Every binding is a two-element list.
        JP NZ,LET_FAIL             ; Reject a malformed binding list.
        CALL REC_NEXT              ; Read this binding's name.
        JP C,LET_FAIL              ; Unwind the saved scope cursors on source failure.
        CP 5                       ; Names are interned symbols.
        JP NZ,LET_FAIL             ; Reject literal or list binding names.
        LD (ST_SYMID),HL           ; The active local receives this full identity.
        LD A,(ST_LTOP)             ; The body shares only the final let* scope.
        LD (ST_LETLO),A            ; Keep later definitions at this boundary.
        CALL BIND_NEW            ; Allocate a local slot before its initializer.
        JP C,LET_FAIL              ; Reject the first slot beyond the local bound.
        LD (ST_SLOT),A             ; Save the selected slot for the store.
        CALL LET_PUSH              ; Record the name and slot before recursive code.
        JP C,LET_FAIL              ; Pending-binding capacity is explicit.
        CALL LET_INIT              ; The initializer sees earlier let* bindings.
        JP C,LET_FAIL              ; Preserve initializer failure.
        CALL LET_PEEK              ; Restore this binding's slot after nested forms.
        JP C,LET_FAIL              ; The pending record must still be present.
        LD A,(ST_SLOT)             ; Recover the selected slot number.
        LD L,A                     ; Pass it to the runtime store.
        LD A,1                     ; Kind one denotes a local slot.
        CALL EM_STORE              ; Emit the initialized flag update.
        JP C,LET_FAIL              ; A fixup failure is terminal.
        CALL CMD_END               ; Close the individual binding list.
        JP C,LET_FAIL              ; Reject a missing or extra initializer.
        CALL BIND_ADD              ; Its name and slot are saved in the pending record.
        JP C,LET_FAIL              ; Reject a local-directory overflow.
        JR .BINDING                ; Read the next sequential binding.
.BODY:
        CALL LET_BODY              ; Compile and close the sequential body.
        JP C,LET_FAIL              ; Preserve body failure before cursor restore.
        JP LET_DONE                 ; Restore outer bindings and return the value.

; letrec binds every name while its initializers are compiled.  A reference to
; a later name reserves a local slot immediately; the later declaration claims
; that slot, so mutually recursive procedures share one cell.
LET_REC:
        XOR A                      ; letrec has its own binding-list grammar.
        LD (ST_NLOK),A
        CALL LET_OPEN              ; Save the enclosing local scope and cursors.
        RET C                      ; Preserve a local-capacity failure.
        LD A,(ST_BINDS)            ; Deferred slots start after outer pending records.
        LD (ST_RPEND),A
        LD A,(ST_LNEXT)            ; The recursive range starts at the next slot.
        LD (ST_RBASE),A            ; Forward references stay inside this range.
        LD (ST_RTOP),A             ; The checked range grows with recursive cells.
        LD A,(ST_PROC)             ; Forward cells belong to the enclosing owner.
        LD (ST_RPROC),A
        LD A,1
        LD (ST_RMODE),A            ; Unresolved names may become letrec slots.
        LD (ST_RINIT),A             ; Initializers see the complete recursive scope.
        CALL REC_OPEN               ; Save an enclosing replay before buffering.
        JP C,LET_FAIL               ; The replay-frame bound is explicit.
        CALL REC_KEEP              ; Retain the list while all names are installed.
        JR C,.FAIL
        CALL REC_DECL              ; Make every recursive name visible to every initializer.
        JR C,.FAIL
.BINDING:
        CALL REC_NEXT              ; Read a binding or the container close.
        JR C,.FAIL
        CP 2
        JR Z,.BODY
        CP 1
        JR NZ,.FAIL
        CALL REC_NEXT              ; Every binding starts with one identifier.
        JR C,.FAIL
        CP 5
        JR NZ,.FAIL
        LD (ST_SYMID),HL           ; Preserve the complete name identity.
        CALL REC_SLOT              ; The replay prepass already installed this name.
        JR C,.FAIL
        LD (ST_SLOT),A             ; The initializer store uses this slot.
        LD A,(ST_SLOT)
        PUSH AF
        CALL LET_INIT              ; All recursive names are visible here.
        JR C,.INIT_BAD
        POP AF
        LD (ST_SLOT),A
        CALL EM_PUSH               ; Keep the value uninstalled until all initializers finish.
        JR C,.FAIL
        CALL CMD_END               ; Close this binding pair.
        JR C,.FAIL
        JR .BINDING
.BODY:
        CALL BIND_CHK              ; Reject names referenced but never declared.
        JR C,.FAIL
        CALL REC_FILL              ; Install deferred values in reverse declaration order.
        JR C,.FAIL
        CALL REC_POP                ; Resume the enclosing stream at the body.
        JP C,LET_FAIL               ; A missing replay frame is compiler corruption.
        CALL LET_BODY              ; Compile the body with all cells active.
        JP C,LET_FAIL
        JP LET_DONE

.INIT_BAD:
        POP AF
        LD (ST_SLOT),A

; A letrec failure must release its replay frame before the normal scope unwind.
.FAIL:
        CALL REC_POP
        JP LET_FAIL

; Save the active local cursors and consume the opening binding-list event.
LET_OPEN:
        POP DE                     ; Move the caller return below saved scope data.
        LD A,(ST_LTOP)             ; Definitions in this body share the let scope.
        LD (ST_LETLO),A            ; Keep the outer active count as its base.
        LD A,(ST_RMODE)            ; Preserve any enclosing recursive scope mode.
        LD C,A
        LD B,0
        PUSH BC
        LD A,(ST_RINIT)            ; Preserve whether its initializers are active.
        LD C,A
        LD B,0
        PUSH BC
        LD A,(ST_RBASE)            ; Preserve its forward-slot range start.
        LD C,A
        LD B,0
        PUSH BC
        LD A,(ST_RTOP)             ; Preserve its recursive high-water bound.
        LD C,A
        LD B,0
        PUSH BC
        LD A,(ST_RPEND)            ; Preserve the enclosing deferred-list marker.
        LD C,A
        LD B,0
        PUSH BC
        LD A,(ST_LTOP)             ; B stores the old active-binding count.
        LD B,A                     ; Preserve it below the parser's return frames.
        LD A,(ST_LNEXT)            ; C stores the next reusable local slot.
        LD C,A                     ; The two bytes restore the outer scope exactly.
        PUSH BC                    ; Nested lets therefore have independent cursors.
        LD A,(ST_BINDS)           ; Save the pending-record top for this let.
        LD C,A                     ; The high byte is unused for the bounded stack.
        LD B,0                     ; Keep the marker in a normal stack word.
        PUSH BC                    ; A nested let can now append its own records.
        PUSH DE                    ; Restore the caller return above both markers.
        CALL REC_NEXT              ; The next event must open the binding list.
        JR NC,.EVENT                ; Continue with the first binding when present.
        POP DE                     ; Remove the saved continuation before cleanup.
        POP BC                     ; Discard the pending-record marker.
        POP BC                     ; Discard the saved local cursors.
        POP BC                     ; Discard the enclosing deferred-list marker.
        POP BC                     ; Discard the saved recursive high-water bound.
        POP BC                     ; Discard the saved recursive-range start.
        POP BC                     ; Discard the saved recursive phase.
        POP BC                     ; Discard the saved recursive mode.
        PUSH DE                    ; Restore the caller continuation for the error return.
        SCF                       ; Preserve the reader failure after balanced cleanup.
        RET
.EVENT:
        CP 1                       ; Kind one is an opening parenthesis.
        JR Z,.OPENED               ; The caller now reads individual bindings.
        CP 5                       ; A symbol selects the named-let grammar.
        JR NZ,.BAD                 ; Other events are malformed binding lists.
        LD A,(ST_NLOK)
        OR A
        JR Z,.BAD                  ; let* and letrec reject a named binding.
        LD (ST_NLID),HL             ; Keep the name while the list is consumed.
        JP LET_NAME                 ; The named form owns the saved let frame.
.OPENED:
        RET
.BAD:
        POP DE                      ; Remove the caller return before cleanup.
        POP BC                      ; Discard the pending-record marker.
        POP BC                      ; Discard the saved local cursors.
        POP BC                      ; Restore the enclosing deferred marker.
        POP BC                      ; Restore the recursive range limit.
        POP BC                      ; Restore the recursive range start.
        POP BC                      ; Restore the recursive phase.
        POP BC                      ; Restore the recursive mode.
        PUSH DE                     ; Return through the original caller frame.
        SCF
        RET

; Let and let* bodies share the internal-definition grammar with procedures.
; The helper keeps their private tail-candidate list balanced on both paths.
LET_BODY:
        LD A,(ST_ALONE)
        PUSH AF
        LD A,2                      ; Let bodies share candidates but admit definitions.
        LD (ST_ALONE),A
        CALL CMD_BODY
        JR C,.FAIL
        POP AF
        LD (ST_ALONE),A
        RET
.FAIL:
        POP AF
        LD (ST_ALONE),A
        SCF
        RET

; Remove a let's saved marker and cursor words before returning a compile error.
LET_FAIL:
        XOR A                      ; Any failed binding aborts the active replay.
        LD (ST_PLAY),A
        POP BC                     ; Discard the pending-record marker.
        POP BC                     ; Restore neither cursor on the terminal path.
        POP BC                     ; Restore the enclosing deferred-list marker.
        LD A,C
        LD (ST_RPEND),A
        POP BC                     ; Restore the enclosing recursive high-water bound.
        LD A,C
        LD (ST_RTOP),A
        POP BC                     ; Restore the enclosing recursive-range start.
        LD A,C
        LD (ST_RBASE),A
        POP BC                     ; Restore the enclosing recursive phase.
        LD A,C
        LD (ST_RINIT),A
        POP BC                     ; Restore the enclosing recursive mode.
        LD A,C
        LD (ST_RMODE),A
        SCF                       ; Carry identifies the syntax or capacity error.
        RET                        ; The original CMD_FORM continuation remains below.

; Restore old local cursors and the pending-record top after a let body.
LET_DONE:
        POP BC                     ; Recover this let's pending-record marker.
        LD A,C                     ; Discard any pending records from the body.
        LD (ST_BINDS),A           ; Outer scopes may reuse the released records.
        POP BC                     ; Recover the old active count and next slot.
        LD A,B                     ; Restore the outer active local count.
        LD (ST_LTOP),A             ; The generated code still owns inner slots.
        LD A,C                     ; Keep the old slot cursor across recursive state.
        LD (ST_LSAVE),A
        POP BC                     ; Restore the enclosing deferred-list marker.
        LD A,C
        LD (ST_RPEND),A
        POP BC                     ; Restore the enclosing recursive high-water bound.
        LD A,C
        LD (ST_RTOP),A
        POP BC                     ; Restore the enclosing recursive-range start.
        LD A,C
        LD (ST_RBASE),A
        POP BC                     ; Restore the enclosing recursive phase.
        LD A,C
        LD (ST_RINIT),A
        POP BC                     ; Restore the enclosing recursive mode.
        LD A,C
        LD (ST_RMODE),A
        LD A,(ST_LSAVE)             ; Reconstruct BIND_ESC's old cursor argument.
        LD C,A
        LD B,0
        CALL BIND_ESC              ; Retain slots whose cells escaped in a closure.
        JR NZ,.RETURN               ; An escaped slot must not be reused by a sibling.
        LD A,C                     ; Restore the outer slot-allocation cursor.
        LD (ST_LNEXT),A            ; Uncaptured slots can be reused safely.
.RETURN:
        XOR A                      ; Return carry clear with the body value intact.
        RET                        ; The caller's A/HL result is not touched.
