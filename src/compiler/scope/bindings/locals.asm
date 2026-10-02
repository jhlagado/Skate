; Local binding tables and recursive-scope bookkeeping.
;
; This module manages pending records, active local slots, capture
; ownership and the replay state used by letrec.

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
        LD A,(SCMSLOT)              ; SCBITSET consumed B; SCOWNSET kept the slot here.
        LD L,A
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
SCLOCHI:
        INC HL                     ; Advance from the high byte to the next record.
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
