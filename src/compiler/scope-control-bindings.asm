; Scope and control binding support.
; This file contains local and package binding tables.

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

; Return NZ when an escape flag is set between C and the current slot cursor.
SCESCAN:
        PUSH BC                    ; Preserve the old scope cursors for SCLETEND.
        LD A,(SCLNEXT)             ; The current cursor bounds the newly allocated range.
        SUB C                      ; A is the number of slots in this let.
        JR Z,SCESNONE              ; No new slots means no captured storage.
        LD B,A                     ; B counts the escape flags to inspect.
        LD L,C                     ; Start at the old cursor value.
        LD H,0
        LD DE,SCLOCEV              ; One flag byte belongs to each compiler slot.
        ADD HL,DE
SCESLOOP:
        LD A,(HL)                  ; A nonzero flag keeps this slot live.
        OR A
        JR NZ,SCESCYES
        INC HL
        DJNZ SCESLOOP
SCESNONE:
        POP BC
        XOR A                      ; No captured slot was found.
        RET
SCESCYES:
        POP BC
        LD A,1                     ; Return NZ while preserving the old cursors.
        OR A
        RET

; Allocate a new local slot and track the maximum data extent observed.
SCNSLOT:
        LD A,(SCLNEXT)             ; Slot numbers are one byte and stop at 127.
        CP 128                     ; Keep the local area bounded for the runtime.
        JP NC,SCCAP                ; A 129th simultaneous local is rejected.
        LD B,A                     ; B keeps the zero-based slot returned to caller.
        LD L,A                     ; Clear a stale escape mark before reuse.
        LD H,0
        LD DE,SCLOCEV
        ADD HL,DE
        XOR A
        LD (HL),A
        LD A,B                     ; Restore the selected slot before advancing.
        INC A                      ; The next binding uses the following slot.
        LD (SCLNEXT),A             ; Publish the updated reusable cursor.
        LD C,A                     ; C is the new simultaneous slot count.
        LD A,(SCLOCMAX)            ; Track the high-water slot count separately.
        CP C                       ; Existing maximum already covers this count?
        JR NC,SCNSDONE             ; No update is needed when the maximum is higher.
        LD A,C                     ; Publish the new high-water count.
        LD (SCLOCMAX),A            ; Finalisation sizes the local data area from it.
SCNSDONE:
        LD A,B                     ; Record the owner before returning the slot.
        CALL SCOWNSET               ; Procedure bodies receive cell-backed slots.
        LD A,(SCRECMOD)             ; Recursive checking ignores ordinary lambda locals.
        OR A
        JR Z,SCRNOFL
        LD L,B
        LD H,0
        LD DE,SCRECBND
        ADD HL,DE
        LD A,1
        LD (HL),A
SCRNOFL:
        XOR A                      ; Clear carry after the capacity comparisons.
        LD A,(SCMSLOT)              ; SCBITSET uses B for its shift count.
        RET                        ; Carry remains clear on a successful allocation.

; Append the current SCID/SCSLOT pair to the pending binding stack.
SCPEND:
        LD A,(SCBNDTOP)           ; The pending stack uses one byte of index.
        CP 128                     ; Keep nested binding records below the guard.
        JP NC,SCCAP                ; A malformed source cannot overwrite the table.
        LD L,A                     ; Widen the index before doubling it for the ID.
        LD H,0                     ; Two bytes store every full interner identity.
        ADD HL,HL                  ; Convert the record index to a byte offset.
        LD DE,SCBINDID             ; Locate the pending ID slot.
        ADD HL,DE                  ; HL points to the next pending record.
        LD DE,(SCID)               ; Store the complete interned name identity.
        LD (HL),E                  ; Publish the ID low byte first.
        INC HL                     ; Advance to the identity high byte.
        LD (HL),D                  ; Complete the pending identity.
        LD A,(SCBNDTOP)           ; Repeat the index for the slot array.
        LD L,A                     ; Widen the index again.
        LD H,0                     ; The slot array uses one byte per record.
        LD DE,SCBINDSL             ; Locate the pending slot region.
        ADD HL,DE                  ; HL points to the matching slot record.
        LD A,(SCSLOT)              ; Store the local slot number.
        LD (HL),A                  ; Complete the pending binding record.
        LD A,(SCBNDTOP)           ; Advance the pending-record top.
        INC A                      ; One more binding is now pending.
        LD (SCBNDTOP),A           ; Publish the complete record.
        XOR A                      ; Carry clear reports success.
        RET                        ; Return to the binding-list parser.

; Recover the most recent pending name and slot without changing an expression value.
SCPREV:
        PUSH AF                    ; Preserve the initializer's value tag and flags.
        PUSH HL                    ; Preserve the initializer's payload.
        LD A,(SCBNDTOP)            ; At least the current binding must be pending.
        OR A                       ; A zero top would indicate corrupted scope state.
        JR NZ,SCPREVGO             ; Read the last pending record when present.
        POP HL                     ; Restore the expression payload before failing.
        POP AF                     ; Restore the expression tag before failing.
        SCF                       ; Report the missing pending record.
        RET
SCPREVGO:
        DEC A                      ; The current record is at top minus one.
        LD C,A                     ; Keep the record index for both table lookups.
        LD B,0                     ; Widen the bounded byte index to a word.
        LD L,C                     ; Address the two-byte name identity.
        LD H,0
        ADD HL,HL
        LD DE,SCBINDID
        ADD HL,DE
        LD E,(HL)                  ; Recover the pending name's low identity byte.
        INC HL
        LD D,(HL)                  ; Recover the pending name's high identity byte.
        LD (SCID),DE               ; Restore the name for a sequential binding.
        LD L,C                     ; Address the matching one-byte slot record.
        LD H,0
        LD DE,SCBINDSL
        ADD HL,DE
        LD A,(HL)                  ; Recover the slot selected before the initializer.
        LD (SCSLOT),A              ; Restore it for SCSTORE or SCADDLOC.
        POP HL                     ; Restore the initializer's payload.
        POP AF                     ; Restore the initializer's value tag.
        OR A                       ; Clear carry without changing the value registers.
        RET

; Add one completed let* binding directly to the active local directory.
SCADDLOC:
        LD HL,(SCID)               ; The pending record retains the complete identity.
        LD A,(SCLOCTOP)            ; The active directory has one byte per record.
        CP 128                     ; Refuse a scope that would overwrite its table.
        JP NC,SCCAP                ; The local bound is an explicit compiler limit.
        LD L,A                     ; Widen the active-record index before doubling it.
        LD H,0                     ; Two bytes store every active identity.
        ADD HL,HL                  ; Convert the record index to a byte offset.
        LD DE,SCLOCIDS             ; Locate the next active identity slot.
        ADD HL,DE                  ; HL points at the destination ID byte.
        LD DE,(SCID)               ; Restore the complete binding identity.
        LD (HL),E                  ; Publish its low byte.
        INC HL                     ; Advance to the identity high byte.
        LD (HL),D                  ; Complete the active identity.
        LD A,(SCLOCTOP)            ; Address the matching active slot byte.
        LD L,A                     ; Widen the active-record index again.
        LD H,0                     ; One byte per active slot.
        LD DE,SCLOCSLT             ; Locate the destination slot byte.
        ADD HL,DE                  ; HL points at the slot destination.
        LD A,(SCSLOT)              ; The allocator selected this local slot.
        LD (HL),A                  ; Publish the active slot mapping.
        LD A,(SCSLOT)              ; Keep the owner alongside the active binding.
        CALL SCOWNSET               ; Captured references compare this owner.
        LD A,(SCLOCTOP)            ; Advance the active local count.
        INC A                      ; The new binding is visible to later forms.
        LD (SCLOCTOP),A            ; Publish the updated directory extent.
        XOR A                      ; Carry clear reports a complete insertion.
        RET                        ; The next let* initializer sees this name.

; Claim a letrec name.  An earlier unresolved reference leaves a zero flag in
; SCRECBND; a real declaration changes it to one instead of allocating twice.
SCRECDEC:
        CALL SCLOCF                ; An outer binding may legally be shadowed.
        JR NC,SCRECNEW             ; No active name means a fresh recursive slot.
        LD B,A                     ; Preserve the matching active slot number.
        LD A,(SCRECST)
        SUB B                       ; A negative result means B is inside the range.
        JR Z,SCRECIN                ; The first slot belongs to this scope.
        JR NC,SCRECNEW              ; A slot below the range is an outer binding.
        LD A,(SCRECLIM)             ; Only this range may claim its placeholders.
        CP B
        JR C,SCRECNEW
        JR Z,SCRECNEW
        JR SCRECIN
SCRECIN:
        LD L,B                     ; Address this slot's declaration flag.
        LD H,0
        LD DE,SCRECBND
        ADD HL,DE
        LD A,(HL)
        OR A
        JR NZ,SCRECDUP             ; Two declarations in one letrec are invalid.
        LD A,1                     ; Convert a forward placeholder to a declaration.
        LD (HL),A
        LD A,B                     ; Return the claimed slot to the caller.
        OR A
        RET
SCRECNEW:
        CALL SCNSLOT               ; Allocate a new cell in the current procedure.
        RET C
        LD (SCSLOT),A
        INC A
        LD B,A
        LD A,(SCRECLIM)
        CP B
        JR NC,SCRCNOUP
        LD A,B
        LD (SCRECLIM),A
SCRCNOUP:
        CALL SCADDLOC              ; Make the name visible to later initializers.
        RET C
        LD A,(SCSLOT)
        LD L,A
        LD H,0
        LD DE,SCRECBND
        ADD HL,DE
        LD A,1                     ; This slot has a real declaration immediately.
        LD (HL),A
        LD A,(SCSLOT)
        OR A
        RET
SCRECDUP:
        LD HL,SCDUPTXT
        LD (SCERRPTR),HL
        SCF
        RET

; Reserve a local cell for a forward reference during a letrec initializer.
SCRECREF:
        CALL SCNSLOT
        RET C
        LD (SCSLOT),A
        INC A
        LD B,A
        LD A,(SCRECLIM)
        CP B
        JR NC,SCRCFOUP
        LD A,B
        LD (SCRECLIM),A
SCRCFOUP:
        CALL SCADDLOC
        RET C
        CALL SCRECOWN               ; Move the cell back to the recursive owner.
        LD A,(SCSLOT)
        LD L,A
        LD H,0
        LD DE,SCRECBND
        ADD HL,DE
        XOR A                     ; Zero marks a placeholder awaiting a name.
        LD (HL),A
        LD A,(SCSLOT)
        OR A
        RET

; Give a forward cell the owner of the surrounding recursive binding scope and
; mark it captured by the procedure currently being compiled when necessary.
SCRECOWN:
        LD A,(SCCURPR)
        PUSH AF
        LD A,(SCTMPPR)
        PUSH AF
        LD A,(SCRECPR)
        LD (SCCURPR),A
        LD A,(SCSLOT)
        CALL SCOWNSET               ; First give the cell its enclosing owner.
        POP AF
        LD (SCTMPPR),A             ; Restore the procedure being compiled.
        POP AF
        LD (SCCURPR),A             ; Capture it from the original nested procedure.
        LD A,(SCSLOT)
        CALL SCCAPSET               ; Mark the current closure and its parents.
        RET

; Check every slot introduced by this letrec or body-definition range.
SCRECCHK:
        LD A,(SCRECST)
        LD B,A
SCRECCLP:
        LD A,(SCRECLIM)
        CP B
        JR Z,SCRECCOK
        LD A,B
        LD L,A
        LD H,0
        LD DE,SCLOCOWN
        ADD HL,DE
        LD A,(HL)
        LD E,A
        LD A,(SCRECPR)
        CP E
        JR NZ,SCRECNXT
        LD A,B
        LD L,A
        LD H,0
        LD DE,SCRECBND
        ADD HL,DE
        LD A,(HL)
        OR A
        JR Z,SCRECERR
SCRECNXT:
        INC B
        JR SCRECCLP
SCRECCOK:
        XOR A
        RET
SCRECERR:
        LD HL,SCRECTXT
        LD (SCERRPTR),HL
        SCF
        RET

; Move all pending records since the current marker into the active local scope.
SCBIND:
        POP DE                     ; Preserve SCBIND's return address.
        POP BC                     ; Peek at the marker saved by SCLETSET.
        PUSH BC                    ; Leave the marker below the caller frame.
        PUSH DE                    ; Restore the return address above the marker.
        LD A,C                     ; Keep the marker while records are copied.
        LD (SCMARK),A              ; Nested forms cannot run during this copy.
        LD A,(SCBNDTOP)            ; Save the pending-record limit for this scope.
        LD (SCBEND),A              ; The marker remains below the active call stack.
        CP C                       ; Equal is the valid empty binding group.
        JR Z,SCBINDOK              ; The body simply uses the enclosing scope.
SCBINDLP:
        LD A,(SCMARK)              ; Current pending record index.
        LD C,A                     ; C retains the source index while addressing.
        LD A,(SCBEND)              ; Check for the end before reading a record.
        CP C                       ; All pending records have been copied.
        JR Z,SCBINDOK              ; Keep the marker word for SCLETEND.
        LD A,(SCLOCTOP)            ; The active array receives the next binding.
        CP 128                     ; Check before writing either active byte.
        JP NC,SCCAP                ; Preserve the original source position.
        LD B,A                     ; B is the active destination index.
        LD A,C                     ; Address the pending ID at the source index.
        LD L,A                     ; Widen the pending index before doubling it.
        LD H,0                     ; Two pending ID bytes per record.
        ADD HL,HL                  ; Convert the record index to a byte offset.
        LD DE,SCBINDID             ; Locate the pending source ID.
        ADD HL,DE                  ; HL points at the pending name identity.
        LD E,(HL)                  ; Read the pending ID low byte.
        INC HL                     ; Advance to the pending ID high byte.
        LD D,(HL)                  ; Read the pending ID high byte.
        LD (SCID),DE               ; Retain it while addressing active arrays.
        LD A,C                     ; Address the matching pending slot.
        LD L,A                     ; Widen the pending index.
        LD H,0                     ; One byte per slot.
        LD DE,SCBINDSL             ; Locate the pending slot.
        ADD HL,DE                  ; HL points at the pending slot number.
        LD A,(HL)                  ; Read the pending slot number.
        LD (SCSLOT),A              ; Retain it for the active slot write.
        LD A,B                     ; Address the active ID destination.
        LD L,A                     ; Widen the active count before doubling it.
        LD H,0                     ; Two active ID bytes per record.
        ADD HL,HL                  ; Convert the active index to a byte offset.
        LD DE,SCLOCIDS             ; Locate the active-ID destination.
        ADD HL,DE                  ; HL points at the active ID byte.
        LD DE,(SCID)               ; Restore the pending ID.
        LD (HL),E                  ; Publish its low byte.
        INC HL                     ; Advance to the active ID high byte.
        LD (HL),D                  ; Complete the active name identity.
        LD A,B                     ; Address the active slot destination.
        LD L,A                     ; Widen the active count.
        LD H,0                     ; One byte per active slot.
        LD DE,SCLOCSLT             ; Locate the active slot destination.
        ADD HL,DE                  ; HL points at the active slot byte.
        LD A,(SCSLOT)              ; Restore the pending slot number.
        LD (HL),A                  ; Publish the active local record.
        LD A,(SCSLOT)              ; Keep the owner alongside the active binding.
        PUSH BC                     ; SCOWNSET uses B/C while setting the mask bit.
        CALL SCOWNSET               ; Captured references compare this owner.
        POP BC                      ; Resume the pending and active cursors.
        LD A,B                     ; Advance the active local count.
        INC A                      ; One pending binding is now visible.
        LD (SCLOCTOP),A            ; Publish it before copying the next record.
        LD A,C                     ; Advance the pending source index.
        INC A                      ; Move to the following pending record.
        LD (SCMARK),A              ; Publish the copied-record cursor.
        JR SCBINDLP                ; Copy another record while one remains.
SCBINDOK:
        LD A,(SCMARK)              ; The marker is the released pending top.
        LD (SCBNDTOP),A            ; Nested lets reuse the pending table space.
        XOR A                      ; Carry clear reports a complete binding scope.
        RET                        ; The caller now compiles the body.
; Search active locals.  The last matching record wins, so inner names shadow.
SCLOCF:
        LD A,(SCLOCTOP)            ; Zero active locals needs no address arithmetic.
        OR A                       ; Test the active count.
        JR Z,SCLOCFNO              ; No local binding can match.
        LD B,A                     ; B counts the active records to inspect.
        LD HL,SCLOCIDS             ; HL scans two-byte IDs from outer to inner.
        LD DE,SCLOCSLT             ; DE scans matching slot bytes in parallel.
        XOR A                      ; A=0 denotes no match yet.
        LD (SCFOUND),A             ; Clear the candidate slot value.
        LD (SCFOUNDK),A            ; Clear the match flag for this lookup.
SCLOCLP:
        LD A,(HL)                  ; Read the active identity low byte.
        LD C,A                     ; Keep it while loading the query low byte.
        LD A,(SCID)                ; Recover the requested low byte.
        CP C                       ; Compare the low bytes first.
        JR NZ,SCLOCNX              ; A mismatch leaves the previous candidate.
        INC HL                     ; Read the active identity high byte.
        LD A,(HL)                  ; Load its high byte.
        LD C,A                     ; Keep it while loading the query high byte.
        LD A,(SCID+1)              ; Recover the requested high byte.
        CP C                       ; Both bytes must match the active record.
        JR NZ,SCLOCHI               ; A mismatch leaves the previous candidate.
        LD A,(DE)                  ; A match replaces the previous outer slot.
        LD (SCFOUND),A             ; The final match is the innermost binding.
        PUSH BC                    ; The lookup loop owns all three cursors.
        PUSH HL
        PUSH DE
        CALL SCCAPSET               ; Mark a captured slot in the active procedure.
        POP DE
        POP HL
        POP BC
        LD A,1                     ; Record that at least one match exists.
        LD (SCFOUNDK),A            ; The value survives the remaining scan.
        JR SCLOCHI                 ; Advance from this record's high byte.
SCLOCNX:
        INC HL                     ; The low-byte mismatch has not reached high yet.
        JR SCLOCHI                 ; Skip the high byte and advance.
SCLOCHI:
        INC HL                     ; Advance from the high byte to the next record.
SCLOCADV:
        INC DE                     ; Advance to the next active slot.
        DJNZ SCLOCLP            ; Inspect all active locals without wrapping.
        LD A,(SCFOUNDK)            ; Check whether a match was recorded.
        OR A                       ; Z means the name is global or unbound.
        JR Z,SCLOCFNO              ; Return carry clear for global resolution.
        LD A,(SCFOUND)             ; Return the innermost local slot number.
        SCF                       ; Carry distinguishes a local from a global.
        RET                        ; The caller emits the local load.
SCLOCFNO:
        XOR A                      ; Return carry clear when no local matched.
        RET                        ; The caller resolves or allocates a global.

; Allocate or find a package-global slot for the full symbol ID in SCID.
SCGGET:
        CALL SCPLOOK                ; Classify predefined arithmetic names before allocation.
        LD (SCPKIND),A              ; Keep the classification beside the selected slot.
        LD HL,(SCGCOUNT)           ; Search only the occupied global identities.
        LD A,H                     ; The count is bounded to 256 records.
        OR L                       ; A zero count has no records to inspect.
        JR Z,SCGNEW                ; Allocate the first global slot directly.
        LD B,H                     ; BC counts occupied records during the scan.
        LD C,L
        LD HL,SCGKEYS              ; HL points at the first two-byte identity.
        LD DE,SCGSLOTS             ; DE points at the first slot byte.
        XOR A                      ; Slot zero is the first candidate.
        LD (SCGIDX),A              ; Keep the candidate index across comparisons.
SCGLOOK:
        LD A,(SCID)                ; Compare the identity low byte.
        CP (HL)
        JR NZ,SCGNEXT               ; A mismatch selects the next identity.
        INC HL                     ; Advance to the stored identity high byte.
        LD A,(SCID+1)              ; Compare the identity high byte.
        CP (HL)
        JR NZ,SCGHIGH               ; A mismatch selects the next identity.
        LD A,(DE)                  ; Return the existing package-global slot.
        LD (SCGSLOT),A             ; Preserve it across the caller's setup.
        OR A                       ; Clear carry for a successful lookup.
        RET
SCGNEXT:
        INC HL                     ; Skip the stored identity high byte.
        INC HL                     ; Advance to the next identity.
        INC DE                     ; Advance to its slot byte.
        LD A,(SCGIDX)              ; Advance the candidate slot number.
        INC A
        LD (SCGIDX),A
        DEC BC                     ; One occupied identity has been checked.
        LD A,B                     ; Test the remaining record count.
        OR C
        JR NZ,SCGLOOK
SCGNEW:
        LD HL,(SCGCOUNT)           ; The high byte becomes nonzero at 256.
        LD A,H
        OR A
        JP NZ,SCCAP                ; Refuse a 257th package-global slot.
        LD A,L                     ; The count is the new zero-based slot number.
        LD (SCGSLOT),A             ; Preserve it while addressing the key table.
        LD DE,SCGSLOTS             ; Record the slot selected for this identity.
        ADD HL,DE                  ; The count is also the one-byte slot index.
        LD (HL),A                  ; Publish the lookup result beside the key.
        LD HL,(SCGCOUNT)           ; Reload the count for the two-byte key offset.
        LD DE,SCGKEYS              ; Compute the two-byte key destination.
        ADD HL,HL                  ; Convert the slot number to a byte offset.
        ADD HL,DE
        LD DE,(SCID)               ; Store the complete symbol identity.
        LD (HL),E                  ; Publish its low byte.
        INC HL                     ; Advance to the high byte.
        LD (HL),D                  ; Complete the identity record.
        LD HL,(SCGCOUNT)           ; Publish the additional occupied slot.
        INC HL
        LD (SCGCOUNT),HL
        LD A,(SCGSLOT)             ; Address the matching primitive-kind byte.
        LD L,A
        LD H,0
        LD DE,SCGPRIM
        ADD HL,DE
        LD A,(SCPKIND)             ; A zero means that this name is ordinary.
        LD (HL),A
        LD A,(SCGSLOT)             ; Return the assigned slot with carry clear.
        OR A                       ; Preserve the slot while clearing carry.
        RET
SCGHIGH:
        INC HL                     ; The high-byte mismatch is at the record end.
        INC DE                     ; Advance the parallel slot table.
        LD A,(SCGIDX)              ; Advance the candidate slot number.
        INC A
        LD (SCGIDX),A
        DEC BC                     ; One occupied identity has been checked.
        LD A,B                     ; Test the remaining record count.
        OR C
        JR NZ,SCGLOOK
        JR SCGNEW                  ; No existing identity matched.

; Find an existing package-global identity without allocating a new slot.
; Carry set returns its slot in A; carry clear leaves the global table unchanged.
SCGHAS:
        LD HL,(SCGCOUNT)           ; Search only the occupied identity records.
        LD A,H
        OR L
        JR Z,SCGHASNO              ; An empty table cannot contain the name.
        LD B,H                     ; BC counts records still to inspect.
        LD C,L
        LD HL,SCGKEYS              ; HL points at the first two-byte identity.
        LD DE,SCGSLOTS             ; DE points at the matching slot byte.
        XOR A
        LD (SCGIDX),A              ; The slot index is retained for each step.
SCGHASLP:
        LD A,(SCID)                ; Compare the identity low byte.
        CP (HL)
        JR NZ,SCGHASNX             ; A mismatch selects the next identity.
        INC HL                     ; Advance to the stored identity high byte.
        LD A,(SCID+1)              ; Compare the identity high byte.
        CP (HL)
        JR NZ,SCGHASHI             ; A mismatch advances past this record.
        LD A,(DE)                  ; Return the existing package-global slot.
        LD (SCGSLOT),A             ; Preserve it across the caller's setup.
        SCF                        ; Carry distinguishes a found global.
        RET
SCGHASHI:
        INC HL                     ; Skip the stored identity high byte.
        INC DE                     ; Advance the parallel slot table.
        DEC BC                     ; One occupied identity has been checked.
        LD A,B
        OR C
        JR NZ,SCGHASLP             ; Continue while records remain.
        JR SCGHASNO                ; The complete table had no match.
SCGHASNX:
        INC HL                     ; Skip both identity bytes.
        INC HL
        INC DE                     ; Advance the parallel slot table.
        DEC BC                     ; One occupied identity has been checked.
        LD A,B
        OR C
        JR NZ,SCGHASLP             ; Continue while records remain.
SCGHASNO:
        XOR A                      ; Carry clear reports an unbound name.
        RET

; Read one closing parenthesis for a fixed-arity form.

; Initializers must return for the binding store, even inside a tail-position let.
SCINIT:
        LD A,(SCTCTX)              ; Save the enclosing body's tail position.
        PUSH AF                    ; Nested initializers need independent saved state.
        LD A,(SCLEBASE)            ; Save the active definition boundary as well.
        PUSH AF                    ; Nested forms must not change the enclosing marker.
        XOR A                      ; The store and body still follow this expression.
        LD (SCTCTX),A              ; Emit an ordinary call for the initializer.
        CALL SCEXPR                ; Compile the value with the outer lexical scope.
        PUSH AF                    ; Preserve its result tag and failure carry.
        POP BC                     ; Hold the result while recovering the context.
        POP AF                     ; Recover the enclosing definition boundary.
        LD (SCLEBASE),A            ; Restore it before the outer binding continues.
        POP AF                     ; Recover the enclosing tail flag.
        LD (SCTCTX),A              ; The let body retains its original tail position.
        PUSH BC                    ; Restore the expression's tag and flags.
        POP AF                     ; Keep syntax failures visible to the caller.
        RET                        ; HL still holds the expression result.
