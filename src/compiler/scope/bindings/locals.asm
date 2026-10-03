; Local binding tables and recursive-scope bookkeeping.
;
; This module manages pending records, active local slots, capture
; ownership and the replay state used by letrec.

; Return NZ when an escape flag is set between C and the current slot cursor.
BIND_ESC:
        PUSH BC                    ; Preserve the old scope cursors for LET_DONE.
        LD A,(ST_LNEXT)            ; The current cursor bounds the newly allocated range.
        SUB C                      ; A is the number of slots in this let.
        JR Z,.NONE                 ; No new slots means no captured storage.
        LD B,A                     ; B counts the escape flags to inspect.
        LD L,C                     ; Start at the old cursor value.
        LD H,0
        LD DE,W_ESCAPE             ; One flag byte belongs to each compiler slot.
        ADD HL,DE
.LOOP:
        LD A,(HL)                  ; A nonzero flag keeps this slot live.
        OR A
        JR NZ,.FOUND
        INC HL
        DJNZ .LOOP
.NONE:
        POP BC
        XOR A                      ; No captured slot was found.
        RET
.FOUND:
        POP BC
        LD A,1                     ; Return NZ while preserving the old cursors.
        OR A
        RET

; Allocate a new local slot and track the maximum data extent observed.
BIND_NEW:
        LD A,(ST_LNEXT)            ; Slot numbers are one byte and stop at 127.
        CP 128                     ; Keep the local area bounded for the runtime.
        JP NC,ERR_CAP              ; A 129th simultaneous local is rejected.
        LD B,A                     ; B keeps the zero-based slot returned to caller.
        LD L,A                     ; Clear a stale escape mark before reuse.
        LD H,0
        LD DE,W_ESCAPE
        ADD HL,DE
        XOR A
        LD (HL),A
        LD A,B                     ; Restore the selected slot before advancing.
        INC A                      ; The next binding uses the following slot.
        LD (ST_LNEXT),A            ; Publish the updated reusable cursor.
        LD C,A                     ; C is the new simultaneous slot count.
        LD A,(ST_LMAX)             ; Track the high-water slot count separately.
        CP C                       ; Existing maximum already covers this count?
        JR NC,.OWNER               ; No update is needed when the maximum is higher.
        LD A,C                     ; Publish the new high-water count.
        LD (ST_LMAX),A             ; Finalisation sizes the local data area from it.
.OWNER:
        LD A,B                     ; Record the owner before returning the slot.
        CALL CAP_OWN                ; Procedure bodies receive cell-backed slots.
        LD A,(ST_RMODE)             ; Recursive checking ignores ordinary lambda locals.
        OR A
        JR Z,.DONE
        LD A,(ST_MSLOT)             ; CAP_BIT consumed B; CAP_OWN kept the slot here.
        LD L,A
        LD H,0
        LD DE,W_DECLS
        ADD HL,DE
        LD A,1
        LD (HL),A
.DONE:
        XOR A                      ; Clear carry after the capacity comparisons.
        LD A,(ST_MSLOT)             ; CAP_BIT uses B for its shift count.
        RET                        ; Carry remains clear on a successful allocation.

; Append the current ST_SYMID/ST_SLOT pair to the pending binding stack.
LET_PUSH:
        LD A,(ST_BINDS)           ; The pending stack uses one byte of index.
        CP 128                     ; Keep nested binding records below the guard.
        JP NC,ERR_CAP              ; A malformed source cannot overwrite the table.
        LD L,A                     ; Widen the index before doubling it for the ID.
        LD H,0                     ; Two bytes store every full interner identity.
        ADD HL,HL                  ; Convert the record index to a byte offset.
        LD DE,W_BKEYS              ; Locate the pending ID slot.
        ADD HL,DE                  ; HL points to the next pending record.
        LD DE,(ST_SYMID)           ; Store the complete interned name identity.
        LD (HL),E                  ; Publish the ID low byte first.
        INC HL                     ; Advance to the identity high byte.
        LD (HL),D                  ; Complete the pending identity.
        LD A,(ST_BINDS)           ; Repeat the index for the slot array.
        LD L,A                     ; Widen the index again.
        LD H,0                     ; The slot array uses one byte per record.
        LD DE,W_BSLOTS             ; Locate the pending slot region.
        ADD HL,DE                  ; HL points to the matching slot record.
        LD A,(ST_SLOT)             ; Store the local slot number.
        LD (HL),A                  ; Complete the pending binding record.
        LD A,(ST_BINDS)           ; Advance the pending-record top.
        INC A                      ; One more binding is now pending.
        LD (ST_BINDS),A           ; Publish the complete record.
        XOR A                      ; Carry clear reports success.
        RET                        ; Return to the binding-list parser.

; Recover the most recent pending name and slot without changing an expression value.
LET_PEEK:
        PUSH AF                    ; Preserve the initializer's value tag and flags.
        PUSH HL                    ; Preserve the initializer's payload.
        LD A,(ST_BINDS)            ; At least the current binding must be pending.
        OR A                       ; A zero top would indicate corrupted scope state.
        JR NZ,.READ                ; Read the last pending record when present.
        POP HL                     ; Restore the expression payload before failing.
        POP AF                     ; Restore the expression tag before failing.
        SCF                       ; Report the missing pending record.
        RET
.READ:
        DEC A                      ; The current record is at top minus one.
        LD C,A                     ; Keep the record index for both table lookups.
        LD B,0                     ; Widen the bounded byte index to a word.
        LD L,C                     ; Address the two-byte name identity.
        LD H,0
        ADD HL,HL
        LD DE,W_BKEYS
        ADD HL,DE
        LD E,(HL)                  ; Recover the pending name's low identity byte.
        INC HL
        LD D,(HL)                  ; Recover the pending name's high identity byte.
        LD (ST_SYMID),DE           ; Restore the name for a sequential binding.
        LD L,C                     ; Address the matching one-byte slot record.
        LD H,0
        LD DE,W_BSLOTS
        ADD HL,DE
        LD A,(HL)                  ; Recover the slot selected before the initializer.
        LD (ST_SLOT),A             ; Restore it for EM_STORE or BIND_ADD.
        POP HL                     ; Restore the initializer's payload.
        POP AF                     ; Restore the initializer's value tag.
        OR A                       ; Clear carry without changing the value registers.
        RET

; Add one completed let* binding directly to the active local directory.
BIND_ADD:
        LD HL,(ST_SYMID)           ; The pending record retains the complete identity.
        LD A,(ST_LTOP)             ; The active directory has one byte per record.
        CP 128                     ; Refuse a scope that would overwrite its table.
        JP NC,ERR_CAP              ; The local bound is an explicit compiler limit.
        LD L,A                     ; Widen the active-record index before doubling it.
        LD H,0                     ; Two bytes store every active identity.
        ADD HL,HL                  ; Convert the record index to a byte offset.
        LD DE,W_LKEYS              ; Locate the next active identity slot.
        ADD HL,DE                  ; HL points at the destination ID byte.
        LD DE,(ST_SYMID)           ; Restore the complete binding identity.
        LD (HL),E                  ; Publish its low byte.
        INC HL                     ; Advance to the identity high byte.
        LD (HL),D                  ; Complete the active identity.
        LD A,(ST_LTOP)             ; Address the matching active slot byte.
        LD L,A                     ; Widen the active-record index again.
        LD H,0                     ; One byte per active slot.
        LD DE,W_LSLOTS             ; Locate the destination slot byte.
        ADD HL,DE                  ; HL points at the slot destination.
        LD A,(ST_SLOT)             ; The allocator selected this local slot.
        LD (HL),A                  ; Publish the active slot mapping.
        LD A,(ST_SLOT)             ; Keep the owner alongside the active binding.
        CALL CAP_OWN                ; Captured references compare this owner.
        LD A,(ST_LTOP)             ; Advance the active local count.
        INC A                      ; The new binding is visible to later forms.
        LD (ST_LTOP),A             ; Publish the updated directory extent.
        XOR A                      ; Carry clear reports a complete insertion.
        RET                        ; The next let* initializer sees this name.

; Claim a letrec name.  An earlier unresolved reference leaves a zero flag in
; W_DECLS; a real declaration changes it to one instead of allocating twice.
LET_DECL:
        CALL BIND_HAS              ; An outer binding may legally be shadowed.
        JR NC,.FRESH               ; No active name means a fresh recursive slot.
        LD B,A                     ; Preserve the matching active slot number.
        LD A,(ST_RBASE)
        SUB B                       ; A negative result means B is inside the range.
        JR Z,.CLAIM                 ; The first slot belongs to this scope.
        JR NC,.FRESH                ; A slot below the range is an outer binding.
        LD A,(ST_RTOP)              ; Only this range may claim its placeholders.
        CP B
        JR C,.FRESH
        JR Z,.FRESH
.CLAIM:
        LD L,B                     ; Address this slot's declaration flag.
        LD H,0
        LD DE,W_DECLS
        ADD HL,DE
        LD A,(HL)
        OR A
        JR NZ,.DUP                 ; Two declarations in one letrec are invalid.
        LD A,1                     ; Convert a forward placeholder to a declaration.
        LD (HL),A
        LD A,B                     ; Return the claimed slot to the caller.
        OR A
        RET
.FRESH:
        CALL BIND_NEW              ; Allocate a new cell in the current procedure.
        RET C
        LD (ST_SLOT),A
        INC A
        LD B,A
        LD A,(ST_RTOP)
        CP B
        JR NC,.VISIBLE
        LD A,B
        LD (ST_RTOP),A
.VISIBLE:
        CALL BIND_ADD              ; Make the name visible to later initializers.
        RET C
        LD A,(ST_SLOT)
        LD L,A
        LD H,0
        LD DE,W_DECLS
        ADD HL,DE
        LD A,1                     ; This slot has a real declaration immediately.
        LD (HL),A
        LD A,(ST_SLOT)
        OR A
        RET
.DUP:
        LD HL,M_DUP
        LD (ST_ERROR),HL
        SCF
        RET

; Reserve a local cell for a forward reference during a letrec initializer.
BIND_FWD:
        CALL BIND_NEW
        RET C
        LD (ST_SLOT),A
        INC A
        LD B,A
        LD A,(ST_RTOP)
        CP B
        JR NC,.VISIBLE
        LD A,B
        LD (ST_RTOP),A
.VISIBLE:
        CALL BIND_ADD
        RET C
        CALL .OWNER                 ; Move the cell back to the recursive owner.
        LD A,(ST_SLOT)
        LD L,A
        LD H,0
        LD DE,W_DECLS
        ADD HL,DE
        XOR A                     ; Zero marks a placeholder awaiting a name.
        LD (HL),A
        LD A,(ST_SLOT)
        OR A
        RET

; Give a forward cell the owner of the surrounding recursive binding scope and
; mark it captured by the procedure currently being compiled when necessary.
.OWNER:
        LD A,(ST_PROC)
        PUSH AF
        LD A,(ST_DESC)
        PUSH AF
        LD A,(ST_RPROC)
        LD (ST_PROC),A
        LD A,(ST_SLOT)
        CALL CAP_OWN                ; First give the cell its enclosing owner.
        POP AF
        LD (ST_DESC),A             ; Restore the procedure being compiled.
        POP AF
        LD (ST_PROC),A             ; Capture it from the original nested procedure.
        LD A,(ST_SLOT)
        CALL CAP_SET                ; Mark the current closure and its parents.
        RET

; Check every slot introduced by this letrec or body-definition range.
BIND_CHK:
        LD A,(ST_RBASE)
        LD B,A
.LOOP:
        LD A,(ST_RTOP)
        CP B
        JR Z,.DONE
        LD A,B
        LD L,A
        LD H,0
        LD DE,W_LOWNER
        ADD HL,DE
        LD A,(HL)
        LD E,A
        LD A,(ST_RPROC)
        CP E
        JR NZ,.NEXT
        LD A,B
        LD L,A
        LD H,0
        LD DE,W_DECLS
        ADD HL,DE
        LD A,(HL)
        OR A
        JR Z,.UNBOUND
.NEXT:
        INC B
        JR .LOOP
.DONE:
        XOR A
        RET
.UNBOUND:
        LD HL,M_LETREC
        LD (ST_ERROR),HL
        SCF
        RET

; Move all pending records since the current marker into the active local scope.
BIND_ALL:
        POP DE                     ; Preserve BIND_ALL's return address.
        POP BC                     ; Peek at the marker saved by LET_OPEN.
        PUSH BC                    ; Leave the marker below the caller frame.
        PUSH DE                    ; Restore the return address above the marker.
        LD A,C                     ; Keep the marker while records are copied.
        LD (ST_BINDP),A            ; Nested forms cannot run during this copy.
        LD A,(ST_BINDS)            ; Save the pending-record limit for this scope.
        LD (ST_BMAX),A             ; The marker remains below the active call stack.
        CP C                       ; Equal is the valid empty binding group.
        JR Z,.DONE                 ; The body simply uses the enclosing scope.
.LOOP:
        LD A,(ST_BINDP)            ; Current pending record index.
        LD C,A                     ; C retains the source index while addressing.
        LD A,(ST_BMAX)             ; Check for the end before reading a record.
        CP C                       ; All pending records have been copied.
        JR Z,.DONE                 ; Keep the marker word for LET_DONE.
        LD A,(ST_LTOP)             ; The active array receives the next binding.
        CP 128                     ; Check before writing either active byte.
        JP NC,ERR_CAP              ; Preserve the original source position.
        LD B,A                     ; B is the active destination index.
        LD A,C                     ; Address the pending ID at the source index.
        LD L,A                     ; Widen the pending index before doubling it.
        LD H,0                     ; Two pending ID bytes per record.
        ADD HL,HL                  ; Convert the record index to a byte offset.
        LD DE,W_BKEYS              ; Locate the pending source ID.
        ADD HL,DE                  ; HL points at the pending name identity.
        LD E,(HL)                  ; Read the pending ID low byte.
        INC HL                     ; Advance to the pending ID high byte.
        LD D,(HL)                  ; Read the pending ID high byte.
        LD (ST_SYMID),DE           ; Retain it while addressing active arrays.
        LD A,C                     ; Address the matching pending slot.
        LD L,A                     ; Widen the pending index.
        LD H,0                     ; One byte per slot.
        LD DE,W_BSLOTS             ; Locate the pending slot.
        ADD HL,DE                  ; HL points at the pending slot number.
        LD A,(HL)                  ; Read the pending slot number.
        LD (ST_SLOT),A             ; Retain it for the active slot write.
        LD A,B                     ; Address the active ID destination.
        LD L,A                     ; Widen the active count before doubling it.
        LD H,0                     ; Two active ID bytes per record.
        ADD HL,HL                  ; Convert the active index to a byte offset.
        LD DE,W_LKEYS              ; Locate the active-ID destination.
        ADD HL,DE                  ; HL points at the active ID byte.
        LD DE,(ST_SYMID)           ; Restore the pending ID.
        LD (HL),E                  ; Publish its low byte.
        INC HL                     ; Advance to the active ID high byte.
        LD (HL),D                  ; Complete the active name identity.
        LD A,B                     ; Address the active slot destination.
        LD L,A                     ; Widen the active count.
        LD H,0                     ; One byte per active slot.
        LD DE,W_LSLOTS             ; Locate the active slot destination.
        ADD HL,DE                  ; HL points at the active slot byte.
        LD A,(ST_SLOT)             ; Restore the pending slot number.
        LD (HL),A                  ; Publish the active local record.
        LD A,(ST_SLOT)             ; Keep the owner alongside the active binding.
        PUSH BC                     ; CAP_OWN uses B/C while setting the mask bit.
        CALL CAP_OWN                ; Captured references compare this owner.
        POP BC                      ; Resume the pending and active cursors.
        LD A,B                     ; Advance the active local count.
        INC A                      ; One pending binding is now visible.
        LD (ST_LTOP),A             ; Publish it before copying the next record.
        LD A,C                     ; Advance the pending source index.
        INC A                      ; Move to the following pending record.
        LD (ST_BINDP),A            ; Publish the copied-record cursor.
        JR .LOOP                   ; Copy another record while one remains.
.DONE:
        LD A,(ST_BINDP)            ; The marker is the released pending top.
        LD (ST_BINDS),A            ; Nested lets reuse the pending table space.
        XOR A                      ; Carry clear reports a complete binding scope.
        RET                        ; The caller now compiles the body.
; Search active locals.  The last matching record wins, so inner names shadow.
BIND_HAS:
        LD A,(ST_LTOP)             ; Zero active locals needs no address arithmetic.
        OR A                       ; Test the active count.
        JR Z,.NONE                 ; No local binding can match.
        LD B,A                     ; B counts the active records to inspect.
        LD HL,W_LKEYS              ; HL scans two-byte IDs from outer to inner.
        LD DE,W_LSLOTS             ; DE scans matching slot bytes in parallel.
        XOR A                      ; A=0 denotes no match yet.
        LD (ST_FOUND),A            ; Clear the candidate slot value.
        LD (ST_HIT),A              ; Clear the match flag for this lookup.
.LOOP:
        LD A,(HL)                  ; Read the active identity low byte.
        LD C,A                     ; Keep it while loading the query low byte.
        LD A,(ST_SYMID)            ; Recover the requested low byte.
        CP C                       ; Compare the low bytes first.
        JR NZ,.LO_MISS             ; A mismatch leaves the previous candidate.
        INC HL                     ; Read the active identity high byte.
        LD A,(HL)                  ; Load its high byte.
        LD C,A                     ; Keep it while loading the query high byte.
        LD A,(ST_SYMID+1)          ; Recover the requested high byte.
        CP C                       ; Both bytes must match the active record.
        JR NZ,.NEXT                 ; A mismatch leaves the previous candidate.
        LD A,(DE)                  ; A match replaces the previous outer slot.
        LD (ST_FOUND),A            ; The final match is the innermost binding.
        PUSH BC                    ; The lookup loop owns all three cursors.
        PUSH HL
        PUSH DE
        CALL CAP_SET                ; Mark a captured slot in the active procedure.
        POP DE
        POP HL
        POP BC
        LD A,1                     ; Record that at least one match exists.
        LD (ST_HIT),A              ; The value survives the remaining scan.
        JR .NEXT                   ; Advance from this record's high byte.
.LO_MISS:
        INC HL                     ; The low-byte mismatch has not reached high yet.
.NEXT:
        INC HL                     ; Advance from the high byte to the next record.
        INC DE                     ; Advance to the next active slot.
        DJNZ .LOOP              ; Inspect all active locals without wrapping.
        LD A,(ST_HIT)              ; Check whether a match was recorded.
        OR A                       ; Z means the name is global or unbound.
        JR Z,.NONE                 ; Return carry clear for global resolution.
        LD A,(ST_FOUND)            ; Return the innermost local slot number.
        SCF                       ; Carry distinguishes a local from a global.
        RET                        ; The caller emits the local load.
.NONE:
        XOR A                      ; Return carry clear when no local matched.
        RET                        ; The caller resolves or allocates a global.
