; Compiler formal, rest-binding and capture-mask management.
; Entry points: CAP_DUP, CAP_REST, CAP_META, CAP_KEEP and CAP_SET.
; Return carry when the current procedure already has a formal with ST_SYMID.
CAP_DUP:
        LD A,(ST_LTOP)             ; No active records means no duplicate exists.
        OR A
        RET Z
        LD B,A                     ; B counts the active local records.
        LD HL,W_LKEYS              ; HL scans the two-byte binding identities.
        LD DE,W_LSLOTS             ; DE scans their one-byte slot numbers.
.LOOP:
        LD A,(HL)                  ; Compare the stored identity low byte.
        LD C,A
        LD A,(ST_SYMID)
        CP C
        JR NZ,.LO_MISS             ; A low-byte mismatch skips to the next record.
        INC HL                     ; Compare the stored identity high byte.
        LD C,(HL)
        LD A,(ST_SYMID+1)
        CP C
        JR NZ,.NEXT               ; A high-byte mismatch leaves this record.
        LD A,(DE)                  ; Matching names must belong to this procedure.
        LD C,A
        PUSH HL                    ; Preserve the identity cursor during owner lookup.
        PUSH DE                    ; Preserve the slot cursor for the next record.
        LD L,C                     ; Widen the matching slot number.
        LD H,0
        LD DE,W_LOWNER             ; Locate the owner procedure for that slot.
        ADD HL,DE
        LD A,(HL)
        LD C,A
        LD A,(ST_PROC)
        CP C
        POP DE                     ; Restore the active binding cursors.
        POP HL
        JR Z,.FOUND               ; A same-procedure name is a duplicate.
.NEXT:
        INC HL                     ; Advance from the high identity byte.
        INC DE                     ; Advance to the next slot number.
        DJNZ .LOOP                 ; Inspect every active binding.
        XOR A                      ; Carry clear means no duplicate was found.
        RET
.LO_MISS:
        INC HL                     ; Skip the unmatched low identity byte.
        JR .NEXT                 ; Complete the common record advance.
.FOUND:
        SCF                        ; The caller rejects the parameter list.
        RET

; Add the current ST_SYMID as the procedure's one rest binding.  The binding is
; an ordinary local slot, but it remains outside the fixed-formal descriptor
; count so the runtime can build a list from surplus arguments.
CAP_REST:
        CALL CAP_DUP               ; A rest name cannot duplicate a fixed name.
        JR NC,.NEW              ; An outer binding may still be shadowed.
        LD HL,M_DUP                ; Reuse the ordinary duplicate-formal diagnostic.
        LD (ST_ERROR),HL
        SCF                        ; Report the duplicate without changing ST_SYMID.
        RET
.NEW:
        CALL BIND_NEW              ; Allocate a normal lexical slot for the list.
        RET C                      ; The local-slot bound remains the compiler gate.
        LD (ST_SLOT),A             ; BIND_ADD reads the selected slot from state.
        CALL BIND_ADD              ; Make the rest name visible in the body.
        RET C                      ; A full active directory is a compile error.
        LD A,(ST_SLOT)             ; Keep the slot for descriptor publication.
        LD (ST_RLIST),A
        LD A,1
        LD (ST_REST),A             ; The descriptor is marked after fixed formals close.
        XOR A                      ; Carry clear reports a complete rest binding.
        RET

; Mark a rest descriptor.  Formals take consecutive slots from the base in
; byte four, so the rest slot follows the fixed ones; an all-rest procedure's
; base is its rest slot.
CAP_META:
        LD A,(ST_REST)
        OR A
        RET Z                       ; A fixed procedure needs no metadata change.
        CALL PROC_REC
        INC HL                      ; Skip the body address.
        INC HL
        LD A,(HL)                   ; The low seven bits retain the fixed arity.
        OR 80H                      ; The high bit selects minimum-arity dispatch.
        LD (HL),A
        AND 7FH                     ; Carry is clear.
        RET NZ
        INC HL                      ; Byte four is the base slot.
        INC HL
        LD A,(ST_RLIST)
        LD (HL),A
        RET

; Return carry when ST_SYMID names one of the current procedure's formal slots.
CAP_FORM:
        LD A,(ST_PROC)             ; Package-level definitions have no formals.
        CP 0FFH
        RET Z
        CALL PROC_REC              ; Locate the active descriptor metadata.
        INC HL                     ; Skip the body address.
        INC HL
        LD A,(HL)                  ; The fixed arity, and bit 7 for a rest formal.
        LD B,A
        AND 7FH
        BIT 7,B
        JR Z,.COUNT
        INC A                      ; The rest slot follows the fixed formals.
.COUNT:
        OR A
        RET Z                      ; No formals; carry is clear.
        LD B,A
        INC HL                     ; Byte four is the first formal's slot.
        INC HL
        LD C,(HL)
.LOOP:
        CALL .HAS                  ; Is ST_SYMID bound to slot C in an active record?
        RET C                      ; Carry: ST_SYMID names this formal.
        INC C
        DJNZ .LOOP
        RET

; Return carry when an active binding record for local slot C holds ST_SYMID.
; W_LKEYS and W_LSLOTS are parallel by active-record position, not by slot.
; BC and HL are preserved; A, DE and flags are clobbered.
.HAS:
        PUSH HL
        PUSH BC
        LD A,(ST_LTOP)             ; No active records means no match.
        OR A
        JR Z,.HAS_NO
        LD B,A                     ; B counts the active records.
        LD HL,W_LKEYS              ; HL scans the two-byte identities.
        LD DE,W_LSLOTS             ; DE scans the matching slot numbers.
.HAS_LOOP:
        LD A,(DE)                  ; Only records for the formal's slot qualify.
        CP C
        JR NZ,.HAS_NEXT
        PUSH HL                    ; Keep the record cursor across the compare.
        LD A,(ST_SYMID)            ; Compare the identity low byte.
        CP (HL)
        JR NZ,.HAS_CMP
        INC HL
        LD A,(ST_SYMID+1)          ; Compare the identity high byte.
        CP (HL)
.HAS_CMP:
        POP HL
        JR Z,.HAS_YES              ; Both bytes matched.
.HAS_NEXT:
        INC HL                     ; Advance to the next two-byte identity.
        INC HL
        INC DE                     ; Advance to the next slot number.
        DJNZ .HAS_LOOP
.HAS_NO:
        POP BC
        POP HL
        OR A                       ; Carry clear: no active record matched.
        RET
.HAS_YES:
        POP BC
        POP HL
        SCF                        ; Carry: ST_SYMID is bound to slot C.
        RET

; Keep recursive forward cells while discarding the lambda's private locals.
; A forward name may have been discovered after the lambda's formals, so its
; active-directory entry must survive the frame restore for a later declaration
; to claim the same slot.
CAP_KEEP:
        LD A,(ST_LTOP)
        LD A,(ST_OTOP)
        LD A,(ST_RMODE)
        OR A
        JR NZ,.SCAN
        LD A,(ST_OTOP)
        LD (ST_LTOP),A
        LD A,(ST_ONEXT)
        LD (ST_LNEXT),A
        RET
.SCAN:
        LD A,(ST_LTOP)
        LD (ST_KTOP),A
        LD A,(ST_OTOP)
        LD B,A
        LD C,A
.LOOP:
        LD A,(ST_KTOP)
        CP B
        JR Z,.DONE
        LD A,B
        LD (ST_KSRC),A
        LD L,A
        LD H,0
        LD DE,W_LSLOTS
        ADD HL,DE
        LD A,(HL)
        LD (ST_KSLOT),A
        LD L,A
        LD H,0
        LD DE,W_LOWNER
        ADD HL,DE
        LD A,(HL)
        LD E,A
        LD A,(ST_RPROC)
        CP E
        JR NZ,.NEXT
        LD A,(ST_KSRC)
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,W_LKEYS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (ST_SYMID),DE
        LD A,C
        LD (ST_KDST),A
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,W_LKEYS
        ADD HL,DE
        LD DE,(ST_SYMID)
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,C
        LD L,A
        LD H,0
        LD DE,W_LSLOTS
        ADD HL,DE
        LD A,(ST_KSLOT)
        LD (HL),A
        INC C
.NEXT:
        LD A,(ST_KSRC)
        INC A
        LD B,A
        JR .LOOP
.DONE:
        LD A,C
        LD (ST_LTOP),A
        LD E,A
        LD A,(ST_OTOP)
        CP E
        RET NZ
        LD A,(ST_ONEXT)
        LD (ST_LNEXT),A
        RET

; Restore one enclosing lambda frame from the compiler-side frame table.
CAP_POP:
        LD A,(ST_BNEST)            ; A zero depth means no frame can be restored.
        OR A
        SCF
        RET Z
        DEC A
        LD (ST_BNEST),A
        LD C,A
        LD L,C
        LD H,0
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,DE
        LD DE,W_BODY
        ADD HL,DE
        LD A,(HL)                  ; Save the enclosing active-directory extent.
        LD (ST_OTOP),A
        INC HL
        LD A,(HL)                  ; Save the enclosing reusable slot cursor.
        LD (ST_ONEXT),A
        INC HL
        LD (ST_FRAME),HL           ; Recursive retention uses this frame cursor.
        CALL CAP_KEEP               ; Keep forward cells before restoring the frame.
        LD HL,(ST_FRAME)
        LD A,(HL)                  ; Restore the enclosing procedure owner.
        LD (ST_PROC),A
        INC HL
        LD A,(HL)                  ; Restore the enclosing tail-position state.
        LD (ST_TAIL),A
        INC HL
        LD A,(HL)                  ; Restore the enclosing procedure descriptor.
        LD (ST_DESC),A
        INC HL
        LD E,(HL)                  ; Restore the enclosing jump-over patch.
        INC HL
        LD D,(HL)
        LD (ST_SKIP),DE
        INC HL
        LD E,(HL)                  ; Restore the enclosing body cursor.
        INC HL
        LD D,(HL)
        LD (ST_PBODY),DE
        XOR A
        RET

; Record the procedure that owns one reusable compiler slot.
CAP_OWN:
        LD (ST_MSLOT),A            ; Preserve the slot while addressing the map.
        LD B,A                     ; Keep it while selecting the current owner.
        LD L,A                     ; Widen the slot index to a word.
        LD H,0
        LD DE,W_LOWNER             ; One owner byte belongs to each slot.
        ADD HL,DE
        LD A,(ST_PROC)             ; FF marks a package-level local scope.
        LD (HL),A                  ; Active binding lookup reads this owner.
        CP 0FFH
        RET Z                       ; Package locals remain in static storage.
        LD A,(ST_PROC)             ; The procedure owns the new slot.
        LD (ST_DESC),A             ; PROC_REC uses the selected descriptor index.
        CALL PROC_REC
        LD DE,W_OWNOFF             ; The owned mask follows the formal fields.
        ADD HL,DE
        LD (ST_MASKP),HL           ; Keep the mask base while selecting its byte.
        LD A,B                     ; Restore the newly allocated slot number.
        LD C,A                     ; Retain the slot while dividing by eight.
        SRL A                      ; Eight slots share one ownership byte.
        SRL A
        SRL A
        LD L,A
        LD H,0
        LD DE,(ST_MASKP)
        ADD HL,DE                  ; Address the mask byte for this slot.
        LD A,C                     ; CAP_BIT consumes the original slot index.
        JP CAP_BIT                 ; Set its bit in the descriptor mask.

; Mark a slot captured by the current procedure when its owner is outer.
CAP_SET:
        LD (ST_MSLOT),A            ; Keep the matching slot across owner lookup.
        LD L,A                     ; Locate the owner byte for this slot.
        LD H,0
        LD DE,W_LOWNER
        ADD HL,DE
        LD B,(HL)                  ; B is the procedure that owns the slot.
        LD A,(ST_PROC)             ; Package-level references never capture.
        CP 0FFH
        RET Z
        CP B                       ; A slot owned by this procedure is local.
        RET Z
        LD A,(ST_MSLOT)            ; An outer reference keeps its storage live.
        CALL .ESCAPE
        LD A,B                     ; Remember the procedure that owns the cell.
        LD (ST_OWNER),A
        LD A,(ST_PROC)             ; Preserve the active procedure across mask writes.
        LD (ST_CPROC),A
        LD A,(ST_DESC)             ; Preserve the descriptor currently being finished.
        LD (ST_CDESC),A
        LD A,(ST_MSLOT)             ; Pass the captured slot to the mask writer.
        CALL .MASK                  ; The current procedure needs the capture bit.
        LD A,(ST_BNEST)            ; Walk through every intermediate procedure.
        LD (ST_CHAIN),A
.CHAIN:
        LD A,(ST_CHAIN)            ; The frame index is one below the current depth.
        OR A
        JR Z,.RESTORE             ; A malformed chain still restores compiler state.
        DEC A
        LD (ST_CHAIN),A
        LD L,A                     ; Widen the frame index before multiplying by nine.
        LD H,0
        LD D,H
        LD E,L
        ADD HL,HL                  ; Two times the frame index.
        ADD HL,HL                  ; Four times the frame index.
        ADD HL,HL                  ; Eight times the frame index.
        ADD HL,DE                  ; Complete the nine-byte frame offset.
        LD DE,W_BODY               ; Locate the saved enclosing procedure field.
        ADD HL,DE
        INC HL
        INC HL                     ; The saved owner is the third frame byte.
        LD A,(HL)
        LD B,A                     ; Compare the parent with the cell owner.
        LD A,(ST_OWNER)
        CP B
        JR Z,.RESTORE             ; The owner already owns the shared cell.
        LD A,B
        LD (ST_PROC),A             ; Select this intermediate descriptor.
        LD A,(ST_MSLOT)            ; Every enclosing mask names the same cell slot.
        CALL .MASK                 ; Preserve the cell through this procedure too.
        JR .CHAIN                ; Continue toward the procedure that owns it.
.RESTORE:
        LD A,(ST_CPROC)            ; Restore the active compiler procedure.
        LD (ST_PROC),A
        LD A,(ST_CDESC)            ; Restore the descriptor being finalized.
        LD (ST_DESC),A
        RET

; Mark one compiler slot as captured so a later sibling cannot reuse its cell.
.ESCAPE:
        LD L,A                     ; Widen the zero-based slot index.
        LD H,0
        LD DE,W_ESCAPE             ; One byte records the lifetime of each slot.
        ADD HL,DE
        LD A,1
        LD (HL),A                  ; A nonzero flag keeps this slot allocated.
        RET

; Set one bit in the current procedure's 128-slot capture mask.
.MASK:
        LD (ST_MSLOT),A            ; Preserve the slot through record arithmetic.
        LD A,(ST_PROC)             ; PROC_REC addresses the current descriptor record.
        LD (ST_MPROC),A
        LD (ST_DESC),A             ; The record helper uses the same descriptor index.
        CALL PROC_REC
        LD DE,W_CAPOFF             ; Skip the body, arity, formals and owner mask.
        ADD HL,DE
        LD (ST_MASKP),HL           ; Save the start of the capture mask.
        LD A,(ST_MSLOT)            ; Divide the slot by eight for its mask byte.
        LD C,A
        SRL A
        SRL A
        SRL A
        LD L,A
        LD H,0
        LD DE,(ST_MASKP)
        ADD HL,DE
        LD (ST_MASKP),HL           ; HL now names the selected mask byte.
        LD A,C                     ; The low three bits select a bit in that byte.

; Set one bit in the mask whose base address is in HL.
CAP_BIT:
        LD (ST_MSLOT),A            ; Preserve the slot through mask arithmetic.
        LD (ST_MASKP),HL           ; Save the selected mask's first byte.
        LD A,(ST_MSLOT)            ; The low three bits select a bit in that byte.
        AND 7
        LD B,A                     ; B shifts the bit; Z means bit zero.
        LD A,1
        JR Z,.APPLY
.SHIFT:
        ADD A,A
        DJNZ .SHIFT
.APPLY:
        LD C,A                     ; Preserve the one-bit mask across the read.
        LD HL,(ST_MASKP)
        LD A,(HL)
        OR C
        LD (HL),A
        RET
