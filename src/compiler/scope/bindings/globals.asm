; Package-global binding table.
;
; These routines find or allocate a slot for a complete symbol identity.
; Local lookup remains here with the table hand-off it serves.

; Allocate or find a package-global slot for the full symbol ID in ST_SYMID.
SCGGET:
        CALL SCPLOOK                ; Classify predefined arithmetic names before allocation.
        LD (ST_PRIM),A              ; Keep the classification beside the selected slot.
        LD HL,(ST_GLOBS)           ; Search only the occupied global identities.
        LD A,H                     ; The count is bounded to 256 records.
        OR L                       ; A zero count has no records to inspect.
        JR Z,SCGNEW                ; Allocate the first global slot directly.
        LD B,H                     ; BC counts occupied records during the scan.
        LD C,L
        LD HL,W_GKEYS              ; HL points at the first two-byte identity.
        LD DE,W_GSLOTS             ; DE points at the first slot byte.
        XOR A                      ; Slot zero is the first candidate.
        LD (ST_GIDX),A             ; Keep the candidate index across comparisons.
SCGLOOK:
        LD A,(ST_SYMID)            ; Compare the identity low byte.
        CP (HL)
        JR NZ,SCGNEXT               ; A mismatch selects the next identity.
        INC HL                     ; Advance to the stored identity high byte.
        LD A,(ST_SYMID+1)          ; Compare the identity high byte.
        CP (HL)
        JR NZ,SCGHIGH               ; A mismatch selects the next identity.
        LD A,(DE)                  ; Return the existing package-global slot.
        LD (ST_GSLOT),A            ; Preserve it across the caller's setup.
        OR A                       ; Clear carry for a successful lookup.
        RET
SCGNEXT:
        INC HL                     ; Skip the stored identity high byte.
        INC HL                     ; Advance to the next identity.
        INC DE                     ; Advance to its slot byte.
        LD A,(ST_GIDX)             ; Advance the candidate slot number.
        INC A
        LD (ST_GIDX),A
        DEC BC                     ; One occupied identity has been checked.
        LD A,B                     ; Test the remaining record count.
        OR C
        JR NZ,SCGLOOK
SCGNEW:
        LD HL,(ST_GLOBS)           ; The high byte becomes nonzero at 256.
        LD A,H
        OR A
        JP NZ,ERR_CAP              ; Refuse a 257th package-global slot.
        LD A,L                     ; The count is the new zero-based slot number.
        LD (ST_GSLOT),A            ; Preserve it while addressing the key table.
        LD DE,W_GSLOTS             ; Record the slot selected for this identity.
        ADD HL,DE                  ; The count is also the one-byte slot index.
        LD (HL),A                  ; Publish the lookup result beside the key.
        LD HL,(ST_GLOBS)           ; Reload the count for the two-byte key offset.
        LD DE,W_GKEYS              ; Compute the two-byte key destination.
        ADD HL,HL                  ; Convert the slot number to a byte offset.
        ADD HL,DE
        LD DE,(ST_SYMID)           ; Store the complete symbol identity.
        LD (HL),E                  ; Publish its low byte.
        INC HL                     ; Advance to the high byte.
        LD (HL),D                  ; Complete the identity record.
        LD HL,(ST_GLOBS)           ; Publish the additional occupied slot.
        INC HL
        LD (ST_GLOBS),HL
        LD A,(ST_GSLOT)            ; Address the matching primitive-kind byte.
        LD L,A
        LD H,0
        LD DE,W_GPRIM
        ADD HL,DE
        LD A,(ST_PRIM)             ; A zero means that this name is ordinary.
        LD (HL),A
        LD A,(ST_GSLOT)            ; Return the assigned slot with carry clear.
        OR A                       ; Preserve the slot while clearing carry.
        RET
SCGHIGH:
        INC HL                     ; The high-byte mismatch is at the record end.
        INC DE                     ; Advance the parallel slot table.
        LD A,(ST_GIDX)             ; Advance the candidate slot number.
        INC A
        LD (ST_GIDX),A
        DEC BC                     ; One occupied identity has been checked.
        LD A,B                     ; Test the remaining record count.
        OR C
        JR NZ,SCGLOOK
        JR SCGNEW                  ; No existing identity matched.

; Find an existing package-global identity without allocating a new slot.
; Carry set returns its slot in A; carry clear leaves the global table unchanged.
SCGHAS:
        LD HL,(ST_GLOBS)           ; Search only the occupied identity records.
        LD A,H
        OR L
        JR Z,SCGHASNO              ; An empty table cannot contain the name.
        LD B,H                     ; BC counts records still to inspect.
        LD C,L
        LD HL,W_GKEYS              ; HL points at the first two-byte identity.
        LD DE,W_GSLOTS             ; DE points at the matching slot byte.
        XOR A
        LD (ST_GIDX),A             ; The slot index is retained for each step.
SCGHASLP:
        LD A,(ST_SYMID)            ; Compare the identity low byte.
        CP (HL)
        JR NZ,SCGHASNX             ; A mismatch selects the next identity.
        INC HL                     ; Advance to the stored identity high byte.
        LD A,(ST_SYMID+1)          ; Compare the identity high byte.
        CP (HL)
        JR NZ,SCGHASHI             ; A mismatch advances past this record.
        LD A,(DE)                  ; Return the existing package-global slot.
        LD (ST_GSLOT),A            ; Preserve it across the caller's setup.
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
