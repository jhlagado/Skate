; Scope and control binding support.
; This file contains local and package binding tables.

; Parallel let: initializers see the outer locals; the body sees all new slots.
SCLETF:
        CALL SCLETSET              ; Save local cursors and open the binding list.
        RET C                      ; Preserve a local-capacity failure.
SCLETB:
        CALL RNEXT                 ; Read another binding list or the list close.
        JP C,SCLETERR              ; Unwind the saved scope cursors on source failure.
        CP 2                       ; A close ends the parallel binding list.
        JR Z,SCLETBD               ; Add the pending entries to the active scope.
        CP 1                       ; Every binding is itself a two-element list.
        JP NZ,SCLETERR             ; A bare name or scalar is not a binding.
        CALL RNEXT                 ; Read the binding name.
        JP C,SCLETERR              ; Unwind the saved scope cursors on source failure.
        CP 5                       ; Names are interned symbols.
        JP NZ,SCLETERR             ; Reject literal or list binding names.
        LD (SCID),HL               ; The pending entry receives this full identity.
        CALL SCNSLOT             ; Allocate a reusable local data slot.
        JP C,SCLETERR              ; Reject the first slot beyond the local bound.
        LD (SCSLOT),A              ; Save the selected slot for the pending entry.
        CALL SCPEND                ; Record the name and slot before recursive code.
        JP C,SCLETERR              ; Pending-binding capacity is explicit.
        CALL SCEXPR                ; Initializer sees only the outer local scope.
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
        CALL SCBODY                ; Compile the body, then consume its close.
        JP C,SCLETERR              ; Preserve body failure before restoring cursors.
        JP SCLETEND                 ; Restore old local cursors and return its value.

; let* is the same syntax, but each binding becomes visible before the next one.
SCLETSF:
        CALL SCLETSET              ; Save local cursors and open the binding list.
        RET C                      ; Preserve a local-capacity failure.
SCLETSB:
        CALL RNEXT                 ; Read another binding or the list close.
        JP C,SCLETERR              ; Unwind the saved scope cursors on source failure.
        CP 2                       ; A close ends the sequential binding list.
        JR Z,SCLETSBD              ; The body follows the final binding.
        CP 1                       ; Every binding is a two-element list.
        JP NZ,SCLETERR             ; Reject a malformed binding list.
        CALL RNEXT                 ; Read this binding's name.
        JP C,SCLETERR              ; Unwind the saved scope cursors on source failure.
        CP 5                       ; Names are interned symbols.
        JP NZ,SCLETERR             ; Reject literal or list binding names.
        LD (SCID),HL               ; The active local receives this full identity.
        CALL SCNSLOT             ; Allocate a local slot before its initializer.
        JP C,SCLETERR              ; Reject the first slot beyond the local bound.
        LD (SCSLOT),A              ; Save the selected slot for the store.
        CALL SCPEND                ; Record the name and slot before recursive code.
        JP C,SCLETERR              ; Pending-binding capacity is explicit.
        CALL SCEXPR                ; The initializer sees earlier let* bindings.
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
        CALL SCBODY                ; Compile and close the sequential body.
        JP C,SCLETERR              ; Preserve body failure before cursor restore.
        JP SCLETEND                 ; Restore outer bindings and return the value.

; Save the active local cursors and consume the opening binding-list event.
SCLETSET:
        POP DE                     ; Move the caller return below saved scope data.
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
        CALL RNEXT                 ; The next event must open the binding list.
        JR NC,SCLETOP               ; Continue with the first binding when present.
        POP DE                     ; Remove the saved continuation before cleanup.
        POP BC                     ; Discard the pending-record marker.
        POP BC                     ; Discard the saved local cursors.
        PUSH DE                    ; Restore the caller continuation for the error return.
        SCF                       ; Preserve the reader failure after balanced cleanup.
        RET
SCLETOP:
        CP 1                       ; Kind one is an opening parenthesis.
        JP NZ,SCLETERR             ; Reject a malformed let binding container.
        RET                        ; The caller now reads individual bindings.

; Remove a let's saved marker and cursor words before returning a compile error.
SCLETERR:
        POP BC                     ; Discard the pending-record marker.
        POP BC                     ; Restore neither cursor on the terminal path.
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
        LD A,C                     ; Restore the outer slot-allocation cursor.
        LD (SCLNEXT),A             ; Later siblings can reuse the released slots.
        XOR A                      ; Return carry clear with the body value intact.
        RET                        ; The caller's A/HL result is not touched.

; Allocate a new local slot and track the maximum data extent observed.
SCNSLOT:
        LD A,(SCLNEXT)             ; Slot numbers are one byte and stop at 127.
        CP 128                     ; Keep the local area bounded for the runtime.
        JP NC,SCCAP                ; A 129th simultaneous local is rejected.
        LD B,A                     ; B keeps the zero-based slot returned to caller.
        INC A                      ; The next binding uses the following slot.
        LD (SCLNEXT),A             ; Publish the updated reusable cursor.
        LD C,A                     ; C is the new simultaneous slot count.
        LD A,(SCLOCMAX)            ; Track the high-water slot count separately.
        CP C                       ; Existing maximum already covers this count?
        JR NC,SCNSDONE             ; No update is needed when the maximum is higher.
        LD A,C                     ; Publish the new high-water count.
        LD (SCLOCMAX),A            ; Finalisation sizes the local data area from it.
SCNSDONE:
        XOR A                      ; Clear carry after the capacity comparisons.
        LD A,B                     ; Return the zero-based slot allocated to binding.
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
        LD A,(SCLOCTOP)            ; Advance the active local count.
        INC A                      ; The new binding is visible to later forms.
        LD (SCLOCTOP),A            ; Publish the updated directory extent.
        XOR A                      ; Carry clear reports a complete insertion.
        RET                        ; The next let* initializer sees this name.

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
        CP C                       ; Equal means no binding was supplied.
        JP Z,SCBNDERR              ; A let with no bindings is not supported.
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
SCBNDERR:
        SCF                       ; An empty binding list is a source error.
        RET                        ; SCLET restores its saved local cursor on failure.

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

; Read one closing parenthesis for a fixed-arity form.
