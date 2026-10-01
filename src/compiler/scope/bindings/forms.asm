; Binding forms for let, let*, letrec and named let.
;
; The entry points parse each form and share the scope-save, body and
; cleanup helpers below. Local and global table operations live beside
; their own data structures in the neighbouring binding modules.

; Parallel let: initializers see the outer locals; the body sees all new slots.
SCLETF:
        LD A,1                     ; Parallel let also accepts a named procedure form.
        LD (SCLETMOD),A
        CALL SCLETSET              ; Save local cursors and open the binding list.
        RET C                      ; Preserve a local-capacity failure.
SCLETB:
        CALL SCNEXT                ; Read another binding list or the list close.
        JP C,SCLETERR              ; Unwind the saved scope cursors on source failure.
        CP 2                       ; A close ends the parallel binding list.
        JR Z,SCLETBD               ; Add the pending entries to the active scope.
        CP 1                       ; Every binding is itself a two-element list.
        JP NZ,SCLETERR             ; A bare name or scalar is not a binding.
        CALL SCNEXT                ; Read the binding name.
        JP C,SCLETERR              ; Unwind the saved scope cursors on source failure.
        CP 5                       ; Names are interned symbols.
        JP NZ,SCLETERR             ; Reject literal or list binding names.
        LD (SCID),HL               ; The pending entry receives this full identity.
        CALL SCNSLOT             ; Allocate a reusable local data slot.
        JP C,SCLETERR              ; Reject the first slot beyond the local bound.
        LD (SCSLOT),A              ; Save the selected slot for the pending entry.
        CALL SCPEND                ; Record the name and slot before recursive code.
        JP C,SCLETERR              ; Pending-binding capacity is explicit.
        CALL SCINIT                ; Initializer sees only the outer local scope.
        JP C,SCLETERR              ; Preserve its syntax or capacity error.
        CALL SCPREV                ; Restore this binding's slot after nested forms.
        JP C,SCLETERR              ; The pending record must still be present.
        LD A,(SCSLOT)              ; Recover the pending slot number.
        LD L,A                     ; Pass it to the runtime store.
        LD A,1                     ; Kind one denotes a local slot.
        CALL SCSTORE               ; Emit the initialized flag update.
        JP C,SCLETERR              ; A fixup failure is terminal.
        CALL SCEXPECT              ; Close the individual binding list.
        JP C,SCLETERR              ; Reject a missing or extra binding expression.
        JR SCLETB                  ; Read the next binding or the outer close.
SCLETBD:
        CALL SCBIND                 ; Publish pending IDs in the active local scope.
        JP C,SCLETERR              ; Reject a scope-stack overflow before body code.
        CALL SCLEBODY              ; Compile the body, then consume its close.
        JP C,SCLETERR              ; Preserve body failure before restoring cursors.
        JP SCLETEND                 ; Restore old local cursors and return its value.

; let* is the same syntax, but each binding becomes visible before the next one.
SCLETSF:
        XOR A                      ; let* has no named-procedure spelling.
        LD (SCLETMOD),A
        CALL SCLETSET              ; Save local cursors and open the binding list.
        RET C                      ; Preserve a local-capacity failure.
SCLETSB:
        CALL SCNEXT                ; Read another binding or the list close.
        JP C,SCLETERR              ; Unwind the saved scope cursors on source failure.
        CP 2                       ; A close ends the sequential binding list.
        JR Z,SCLETSBD              ; The body follows the final binding.
        CP 1                       ; Every binding is a two-element list.
        JP NZ,SCLETERR             ; Reject a malformed binding list.
        CALL SCNEXT                ; Read this binding's name.
        JP C,SCLETERR              ; Unwind the saved scope cursors on source failure.
        CP 5                       ; Names are interned symbols.
        JP NZ,SCLETERR             ; Reject literal or list binding names.
        LD (SCID),HL               ; The active local receives this full identity.
        LD A,(SCLOCTOP)            ; The body shares only the final let* scope.
        LD (SCLEBASE),A            ; Keep later definitions at this boundary.
        CALL SCNSLOT             ; Allocate a local slot before its initializer.
        JP C,SCLETERR              ; Reject the first slot beyond the local bound.
        LD (SCSLOT),A              ; Save the selected slot for the store.
        CALL SCPEND                ; Record the name and slot before recursive code.
        JP C,SCLETERR              ; Pending-binding capacity is explicit.
        CALL SCINIT                ; The initializer sees earlier let* bindings.
        JP C,SCLETERR              ; Preserve initializer failure.
        CALL SCPREV                ; Restore this binding's slot after nested forms.
        JP C,SCLETERR              ; The pending record must still be present.
        LD A,(SCSLOT)              ; Recover the selected slot number.
        LD L,A                     ; Pass it to the runtime store.
        LD A,1                     ; Kind one denotes a local slot.
        CALL SCSTORE               ; Emit the initialized flag update.
        JP C,SCLETERR              ; A fixup failure is terminal.
        CALL SCEXPECT              ; Close the individual binding list.
        JP C,SCLETERR              ; Reject a missing or extra initializer.
        CALL SCADDLOC              ; Its name and slot are saved in the pending record.
        JP C,SCLETERR              ; Reject a local-directory overflow.
        JR SCLETSB                 ; Read the next sequential binding.
SCLETSBD:
        CALL SCLEBODY              ; Compile and close the sequential body.
        JP C,SCLETERR              ; Preserve body failure before cursor restore.
        JP SCLETEND                 ; Restore outer bindings and return the value.

; letrec binds every name while its initializers are compiled.  A reference to
; a later name reserves a local slot immediately; the later declaration claims
; that slot, so mutually recursive procedures share one cell.
SCLETRF:
        XOR A                      ; letrec has its own binding-list grammar.
        LD (SCLETMOD),A
        CALL SCLETSET              ; Save the enclosing local scope and cursors.
        RET C                      ; Preserve a local-capacity failure.
        LD A,(SCBNDTOP)            ; Deferred slots start after outer pending records.
        LD (SCRECPND),A
        LD A,(SCLNEXT)             ; The recursive range starts at the next slot.
        LD (SCRECST),A             ; Forward references stay inside this range.
        LD (SCRECLIM),A            ; The checked range grows with recursive cells.
        LD A,(SCCURPR)             ; Forward cells belong to the enclosing owner.
        LD (SCRECPR),A
        LD A,1
        LD (SCRECMOD),A            ; Unresolved names may become letrec slots.
        LD (SCRECPHS),A             ; Initializers see the complete recursive scope.
        CALL SCRECOPN               ; Save an enclosing replay before buffering.
        JP C,SCLETERR               ; The replay-frame bound is explicit.
        CALL SCRECBUF              ; Retain the list while all names are installed.
        JP C,SCRECFL
        CALL SCRECPRE              ; Make every recursive name visible to every initializer.
        JP C,SCRECFL
SCRECB:
        CALL SCNEXT                ; Read a binding or the container close.
        JP C,SCRECFL
        CP 2
        JR Z,SCRECBD
        CP 1
        JP NZ,SCRECFL
        CALL SCNEXT                ; Every binding starts with one identifier.
        JP C,SCRECFL
        CP 5
        JP NZ,SCRECFL
        LD (SCID),HL               ; Preserve the complete name identity.
        CALL SCRECUSE              ; The replay prepass already installed this name.
        JP C,SCRECFL
        LD (SCSLOT),A              ; The initializer store uses this slot.
        LD A,(SCSLOT)
        PUSH AF
        CALL SCINIT                ; All recursive names are visible here.
        JP C,SCLETINI
        POP AF
        LD (SCSLOT),A
        CALL SCPUSH                ; Keep the value uninstalled until all initializers finish.
        JP C,SCRECFL
        CALL SCEXPECT              ; Close this binding pair.
        JP C,SCRECFL
        JR SCRECB
SCRECBD:
        CALL SCRECCHK              ; Reject names referenced but never declared.
        JP C,SCRECFL
        CALL SCRECSTO              ; Install deferred values in reverse declaration order.
        JP C,SCRECFL
        CALL SCRECPOP               ; Resume the enclosing stream at the body.
        JP C,SCLETERR               ; A missing replay frame is compiler corruption.
        CALL SCLEBODY              ; Compile the body with all cells active.
        JP C,SCLETERR
        JP SCLETEND

SCLETINI:
        POP AF
        LD (SCSLOT),A
        JP SCRECFL

; A letrec failure must release its replay frame before the normal scope unwind.
SCRECFL:
        CALL SCRECPOP
        JP SCLETERR

; Save the active local cursors and consume the opening binding-list event.
SCLETSET:
        POP DE                     ; Move the caller return below saved scope data.
        LD A,(SCLOCTOP)            ; Definitions in this body share the let scope.
        LD (SCLEBASE),A            ; Keep the outer active count as its base.
        LD A,(SCRECMOD)            ; Preserve any enclosing recursive scope mode.
        LD C,A
        LD B,0
        PUSH BC
        LD A,(SCRECPHS)            ; Preserve whether its initializers are active.
        LD C,A
        LD B,0
        PUSH BC
        LD A,(SCRECST)             ; Preserve its forward-slot range start.
        LD C,A
        LD B,0
        PUSH BC
        LD A,(SCRECLIM)            ; Preserve its recursive high-water bound.
        LD C,A
        LD B,0
        PUSH BC
        LD A,(SCRECPND)            ; Preserve the enclosing deferred-list marker.
        LD C,A
        LD B,0
        PUSH BC
        LD A,(SCLOCTOP)            ; B stores the old active-binding count.
        LD B,A                     ; Preserve it below the parser's return frames.
        LD A,(SCLNEXT)             ; C stores the next reusable local slot.
        LD C,A                     ; The two bytes restore the outer scope exactly.
        PUSH BC                    ; Nested lets therefore have independent cursors.
        LD A,(SCBNDTOP)           ; Save the pending-record top for this let.
        LD C,A                     ; The high byte is unused for the bounded stack.
        LD B,0                     ; Keep the marker in a normal stack word.
        PUSH BC                    ; A nested let can now append its own records.
        PUSH DE                    ; Restore the caller return above both markers.
        CALL SCNEXT                ; The next event must open the binding list.
        JR NC,SCLETOP               ; Continue with the first binding when present.
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
SCLETOP:
        CP 1                       ; Kind one is an opening parenthesis.
        JR Z,SCLETOK               ; The caller now reads individual bindings.
        CP 5                       ; A symbol selects the named-let grammar.
        JR NZ,SCLETBAD             ; Other events are malformed binding lists.
        LD A,(SCLETMOD)
        OR A
        JR Z,SCLETBAD              ; let* and letrec reject a named binding.
        LD (SCNAMID),HL             ; Keep the name while the list is consumed.
        JP SCNAMED                  ; The named form owns the saved let frame.
SCLETOK:
        RET
SCLETBAD:
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
SCLEBODY:
        LD A,(SCBISOL)
        PUSH AF
        LD A,2                      ; Let bodies share candidates but admit definitions.
        LD (SCBISOL),A
        CALL SCBODY
        JR C,SCLEBERR
        POP AF
        LD (SCBISOL),A
        RET
SCLEBERR:
        POP AF
        LD (SCBISOL),A
        SCF
        RET

; Remove a let's saved marker and cursor words before returning a compile error.
SCLETERR:
        XOR A                      ; Any failed binding aborts the active replay.
        LD (SCREP),A
        POP BC                     ; Discard the pending-record marker.
        POP BC                     ; Restore neither cursor on the terminal path.
        POP BC                     ; Restore the enclosing deferred-list marker.
        LD A,C
        LD (SCRECPND),A
        POP BC                     ; Restore the enclosing recursive high-water bound.
        LD A,C
        LD (SCRECLIM),A
        POP BC                     ; Restore the enclosing recursive-range start.
        LD A,C
        LD (SCRECST),A
        POP BC                     ; Restore the enclosing recursive phase.
        LD A,C
        LD (SCRECPHS),A
        POP BC                     ; Restore the enclosing recursive mode.
        LD A,C
        LD (SCRECMOD),A
        SCF                       ; Carry identifies the syntax or capacity error.
        RET                        ; The original SCFORM continuation remains below.

; Restore old local cursors and the pending-record top after a let body.
SCLETEND:
        POP BC                     ; Recover this let's pending-record marker.
        LD A,C                     ; Discard any pending records from the body.
        LD (SCBNDTOP),A           ; Outer scopes may reuse the released records.
        POP BC                     ; Recover the old active count and next slot.
        LD A,B                     ; Restore the outer active local count.
        LD (SCLOCTOP),A            ; The generated code still owns inner slots.
        LD A,C                     ; Keep the old slot cursor across recursive state.
        LD (SCLOCSAV),A
        POP BC                     ; Restore the enclosing deferred-list marker.
        LD A,C
        LD (SCRECPND),A
        POP BC                     ; Restore the enclosing recursive high-water bound.
        LD A,C
        LD (SCRECLIM),A
        POP BC                     ; Restore the enclosing recursive-range start.
        LD A,C
        LD (SCRECST),A
        POP BC                     ; Restore the enclosing recursive phase.
        LD A,C
        LD (SCRECPHS),A
        POP BC                     ; Restore the enclosing recursive mode.
        LD A,C
        LD (SCRECMOD),A
        LD A,(SCLOCSAV)             ; Reconstruct SCESCAN's old cursor argument.
        LD C,A
        LD B,0
        CALL SCESCAN               ; Retain slots whose cells escaped in a closure.
        JR NZ,SCLETKEP              ; An escaped slot must not be reused by a sibling.
        LD A,C                     ; Restore the outer slot-allocation cursor.
        LD (SCLNEXT),A             ; Uncaptured slots can be reused safely.
SCLETKEP:
        XOR A                      ; Return carry clear with the body value intact.
        RET                        ; The caller's A/HL result is not touched.
