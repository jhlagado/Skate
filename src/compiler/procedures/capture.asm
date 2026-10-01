; Compiler formal, rest-binding and capture-mask management.
; Entry points: SCPDUP, SCRADD, SCRMETA, SCRETAIN and SCCAPSET.
; Return carry when the current procedure already has a formal with SCID.
SCPDUP:
        LD A,(SCLOCTOP)            ; No active records means no duplicate exists.
        OR A
        RET Z
        LD B,A                     ; B counts the active local records.
        LD HL,SCLOCIDS             ; HL scans the two-byte binding identities.
        LD DE,SCLOCSLT             ; DE scans their one-byte slot numbers.
SCPDUPLP:
        LD A,(HL)                  ; Compare the stored identity low byte.
        LD C,A
        LD A,(SCID)
        CP C
        JR NZ,SCPDUPLO             ; A low-byte mismatch skips to the next record.
        INC HL                     ; Compare the stored identity high byte.
        LD C,(HL)
        LD A,(SCID+1)
        CP C
        JR NZ,SCPDUPHI            ; A high-byte mismatch leaves this record.
        LD A,(DE)                  ; Matching names must belong to this procedure.
        LD C,A
        PUSH HL                    ; Preserve the identity cursor during owner lookup.
        PUSH DE                    ; Preserve the slot cursor for the next record.
        LD L,C                     ; Widen the matching slot number.
        LD H,0
        LD DE,SCLOCOWN             ; Locate the owner procedure for that slot.
        ADD HL,DE
        LD A,(HL)
        LD C,A
        LD A,(SCCURPR)
        CP C
        POP DE                     ; Restore the active binding cursors.
        POP HL
        JR Z,SCPDUPOK             ; A same-procedure name is a duplicate.
SCPDUPHI:
        INC HL                     ; Advance from the high identity byte.
        INC DE                     ; Advance to the next slot number.
        DJNZ SCPDUPLP              ; Inspect every active binding.
        XOR A                      ; Carry clear means no duplicate was found.
        RET
SCPDUPLO:
        INC HL                     ; Skip the unmatched low identity byte.
        JR SCPDUPHI              ; Complete the common record advance.
SCPDUPOK:
        SCF                        ; The caller rejects the parameter list.
        RET

; Add the current SCID as the procedure's one rest binding.  The binding is
; an ordinary local slot, but it remains outside the fixed-formal descriptor
; count so the runtime can build a list from surplus arguments.
SCRADD:
        CALL SCPDUP                ; A rest name cannot duplicate a fixed name.
        JR NC,SCRNEW            ; An outer binding may still be shadowed.
        LD HL,SCDUPTXT             ; Reuse the ordinary duplicate-formal diagnostic.
        LD (SCERRPTR),HL
        SCF                        ; Report the duplicate without changing SCID.
        RET
SCRNEW:
        CALL SCNSLOT               ; Allocate a normal lexical slot for the list.
        RET C                      ; The local-slot bound remains the compiler gate.
        LD (SCSLOT),A              ; SCADDLOC reads the selected slot from state.
        CALL SCADDLOC              ; Make the rest name visible in the body.
        RET C                      ; A full active directory is a compile error.
        LD A,(SCSLOT)              ; Keep the slot for descriptor publication.
        LD (SCRESTS),A
        LD A,1
        LD (SCRESTF),A             ; The descriptor is marked after fixed formals close.
        XOR A                      ; Carry clear reports a complete rest binding.
        RET

; Mark a rest descriptor and store its local slot in a reserved high byte.
; Fixed descriptors keep the old all-zero high bytes and remain byte-stable.
SCRMETA:
        LD A,(SCRESTF)
        OR A
        RET Z                       ; A fixed procedure needs no metadata change.
        CALL SCPREC                 ; Locate the current forty-four-byte record.
        INC HL                      ; Skip the body address low byte.
        INC HL                      ; Skip the body address high byte.
        LD A,(HL)                   ; The low seven bits retain the fixed arity.
        OR 80H                       ; The high bit selects minimum-arity dispatch.
        LD (HL),A                   ; Publish the rest policy in the existing byte.
        AND 7FH                      ; The low bits select the reserved slot field.
        INC HL                      ; Skip the arity byte to the first formal low byte.
        INC HL
        CP 4                         ; Four fixed formals use field three's high byte.
        JR Z,SCRLAST
        ADD A,A                      ; Each earlier formal occupies two bytes.
        LD E,A
        LD D,0
        ADD HL,DE
        INC HL                      ; Select the reserved high byte.
        JR SCRPUT
SCRLAST:
        LD DE,7                      ; Field three's high byte is seven bytes ahead.
        ADD HL,DE
SCRPUT:
        LD A,(SCRESTS)               ; The runtime reads this as the rest local slot.
        LD (HL),A
        XOR A                        ; Carry clear reports valid descriptor metadata.
        RET

; Return carry when SCID names one of the current procedure's formal slots.
SCPFORM:
        LD A,(SCCURPR)             ; Package-level definitions have no formals.
        CP 0FFH
        RET Z
        CALL SCPREC                ; Locate the active descriptor metadata.
        INC HL                     ; Skip the body address low byte.
        INC HL                     ; Skip the body address high byte.
        LD A,(HL)                  ; The high bit marks a procedure with a rest formal.
        LD (SCPHIGH),A             ; Keep the policy while the fixed fields are scanned.
        AND 7FH                    ; B counts only the fixed formal names.
        LD B,A                      ; B is the number of fixed formal slots.
        INC HL                     ; Skip the formal-count byte.
        INC HL                     ; Skip the capture-mask byte.
        LD A,B
        OR A                       ; Preserve a clear result for a nullary procedure.
        JR Z,SCFNOFIX              ; An all-rest procedure has no fixed fields.
SCFLOOP:
        LD C,(HL)                  ; Read one formal's local slot number.
        INC HL
        INC HL                     ; Skip the reserved high slot byte.
        PUSH HL                    ; Keep the next formal cursor across lookup.
        LD L,C
        LD H,0
        ADD HL,HL                  ; Active IDs use two bytes per slot.
        LD DE,SCLOCIDS
        ADD HL,DE
        LD A,(SCID)
        CP (HL)
        JR NZ,SCFNO
        INC HL
        LD A,(SCID+1)
        CP (HL)
        JR NZ,SCFNO
        POP HL
        SCF
        RET
SCFNO:
        POP HL
        DJNZ SCFLOOP
        LD A,(SCPHIGH)             ; Fixed names were absent; inspect the rest slot.
        AND 80H
        RET Z                      ; A fixed procedure has no further formal name.
        LD A,(SCPHIGH)
        AND 7FH
        CP 4
        JR Z,SCFREST4              ; Four fixed names leave field three's high byte.
        INC HL                     ; Earlier arities leave the next field's high byte.
        JR SCFREST
SCFREST4:
        DEC HL                     ; The fourth fixed field is the reserved rest slot.
SCFREST:
        XOR A                      ; Clear the marker so one rest scan terminates.
        LD (SCPHIGH),A
        LD B,1                      ; Reuse the ordinary slot comparison once.
        JR SCFLOOP
SCFNOFIX:
        LD A,(SCPHIGH)
        AND 80H
        RET Z                      ; A nullary fixed procedure has no formal names.
        INC HL                     ; The first field's high byte stores the rest slot.
        XOR A                      ; Clear the marker so one rest scan terminates.
        LD (SCPHIGH),A
        LD B,1
        JR SCFLOOP

; Keep recursive forward cells while discarding the lambda's private locals.
; A forward name may have been discovered after the lambda's formals, so its
; active-directory entry must survive the frame restore for a later declaration
; to claim the same slot.
SCRETAIN:
        LD A,(SCLOCTOP)
        LD A,(SCRECO)
        LD A,(SCRECMOD)
        OR A
        JR NZ,SCRTSCAN
        LD A,(SCRECO)
        LD (SCLOCTOP),A
        LD A,(SCRECN)
        LD (SCLNEXT),A
        RET
SCRTSCAN:
        LD A,(SCLOCTOP)
        LD (SCRECCUR),A
        LD A,(SCRECO)
        LD B,A
        LD C,A
SCRTLOOP:
        LD A,(SCRECCUR)
        CP B
        JR Z,SCRTDONE
        LD A,B
        LD (SCRECSRC),A
        LD L,A
        LD H,0
        LD DE,SCLOCSLT
        ADD HL,DE
        LD A,(HL)
        LD (SCRCSLOT),A
        LD L,A
        LD H,0
        LD DE,SCLOCOWN
        ADD HL,DE
        LD A,(HL)
        LD E,A
        LD A,(SCRECPR)
        CP E
        JR NZ,SCRTNEXT
        LD A,(SCRECSRC)
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,SCLOCIDS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCID),DE
        LD A,C
        LD (SCRECDST),A
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,SCLOCIDS
        ADD HL,DE
        LD DE,(SCID)
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,C
        LD L,A
        LD H,0
        LD DE,SCLOCSLT
        ADD HL,DE
        LD A,(SCRCSLOT)
        LD (HL),A
        INC C
SCRTNEXT:
        LD A,(SCRECSRC)
        INC A
        LD B,A
        JR SCRTLOOP
SCRTDONE:
        LD A,C
        LD (SCLOCTOP),A
        LD E,A
        LD A,(SCRECO)
        CP E
        RET NZ
        LD A,(SCRECN)
        LD (SCLNEXT),A
        RET

; Restore one enclosing lambda frame from the compiler-side frame table.
SCUNWIND:
        LD A,(SCBDEP)              ; A zero depth means no frame can be restored.
        OR A
        SCF
        RET Z
        DEC A
        LD (SCBDEP),A
        LD C,A
        LD L,C
        LD H,0
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,DE
        LD DE,SCBFRAME
        ADD HL,DE
        LD A,(HL)                  ; Save the enclosing active-directory extent.
        LD (SCRECO),A
        INC HL
        LD A,(HL)                  ; Save the enclosing reusable slot cursor.
        LD (SCRECN),A
        INC HL
        LD (SCUNPTR),HL            ; Recursive retention uses this frame cursor.
        CALL SCRETAIN               ; Keep forward cells before restoring the frame.
        LD HL,(SCUNPTR)
        LD A,(HL)                  ; Restore the enclosing procedure owner.
        LD (SCCURPR),A
        INC HL
        LD A,(HL)                  ; Restore the enclosing tail-position state.
        LD (SCTCTX),A
        INC HL
        LD A,(HL)                  ; Restore the enclosing procedure descriptor.
        LD (SCTMPPR),A
        INC HL
        LD E,(HL)                  ; Restore the enclosing jump-over patch.
        INC HL
        LD D,(HL)
        LD (SCSKIP),DE
        INC HL
        LD E,(HL)                  ; Restore the enclosing body cursor.
        INC HL
        LD D,(HL)
        LD (SCPBODY),DE
        XOR A
        RET

; Record the procedure that owns one reusable compiler slot.
SCOWNSET:
        LD (SCMSLOT),A             ; Preserve the slot while addressing the map.
        LD B,A                     ; Keep it while selecting the current owner.
        LD L,A                     ; Widen the slot index to a word.
        LD H,0
        LD DE,SCLOCOWN             ; One owner byte belongs to each slot.
        ADD HL,DE
        LD A,(SCCURPR)             ; FF marks a package-level local scope.
        LD (HL),A                  ; Active binding lookup reads this owner.
        CP 0FFH
        RET Z                       ; Package locals remain in static storage.
        LD A,(SCCURPR)             ; The procedure owns the new slot.
        LD (SCTMPPR),A             ; SCPREC uses the selected descriptor index.
        CALL SCPREC
        LD DE,SCOWNOF              ; The owned mask follows the formal fields.
        ADD HL,DE
        LD (SCMTADR),HL            ; Keep the mask base while selecting its byte.
        LD A,B                     ; Restore the newly allocated slot number.
        LD C,A                     ; Retain the slot while dividing by eight.
        SRL A                      ; Eight slots share one ownership byte.
        SRL A
        SRL A
        LD L,A
        LD H,0
        LD DE,(SCMTADR)
        ADD HL,DE                  ; Address the mask byte for this slot.
        LD A,C                     ; SCBITSET consumes the original slot index.
        JP SCBITSET                ; Set its bit in the descriptor mask.

; Mark a slot captured by the current procedure when its owner is outer.
SCCAPSET:
        LD (SCMSLOT),A             ; Keep the matching slot across owner lookup.
        LD L,A                     ; Locate the owner byte for this slot.
        LD H,0
        LD DE,SCLOCOWN
        ADD HL,DE
        LD B,(HL)                  ; B is the procedure that owns the slot.
        LD A,(SCCURPR)             ; Package-level references never capture.
        CP 0FFH
        RET Z
        CP B                       ; A slot owned by this procedure is local.
        RET Z
        LD A,(SCMSLOT)             ; An outer reference keeps its storage live.
        CALL SCEVSET
        LD A,B                     ; Remember the procedure that owns the cell.
        LD (SCCAPOWN),A
        LD A,(SCCURPR)             ; Preserve the active procedure across mask writes.
        LD (SCORIGPR),A
        LD A,(SCTMPPR)             ; Preserve the descriptor currently being finished.
        LD (SCORIGTM),A
        LD A,(SCMSLOT)              ; Pass the captured slot to the mask writer.
        CALL SCMSKSET               ; The current procedure needs the capture bit.
        LD A,(SCBDEP)              ; Walk through every intermediate procedure.
        LD (SCCHAINN),A
SCCAPCHN:
        LD A,(SCCHAINN)            ; The frame index is one below the current depth.
        OR A
        JR Z,SCCAPRST             ; A malformed chain still restores compiler state.
        DEC A
        LD (SCCHAINN),A
        LD L,A                     ; Widen the frame index before multiplying by nine.
        LD H,0
        LD D,H
        LD E,L
        ADD HL,HL                  ; Two times the frame index.
        ADD HL,HL                  ; Four times the frame index.
        ADD HL,HL                  ; Eight times the frame index.
        ADD HL,DE                  ; Complete the nine-byte frame offset.
        LD DE,SCBFRAME             ; Locate the saved enclosing procedure field.
        ADD HL,DE
        INC HL
        INC HL                     ; The saved owner is the third frame byte.
        LD A,(HL)
        LD B,A                     ; Compare the parent with the cell owner.
        LD A,(SCCAPOWN)
        CP B
        JR Z,SCCAPRST             ; The owner already owns the shared cell.
        LD A,B
        LD (SCCURPR),A             ; Select this intermediate descriptor.
        LD A,(SCMSLOT)             ; Every enclosing mask names the same cell slot.
        CALL SCMSKSET              ; Preserve the cell through this procedure too.
        JR SCCAPCHN              ; Continue toward the procedure that owns it.
SCCAPRST:
        LD A,(SCORIGPR)            ; Restore the active compiler procedure.
        LD (SCCURPR),A
        LD A,(SCORIGTM)            ; Restore the descriptor being finalized.
        LD (SCTMPPR),A
        RET

; Mark one compiler slot as captured so a later sibling cannot reuse its cell.
SCEVSET:
        LD L,A                     ; Widen the zero-based slot index.
        LD H,0
        LD DE,SCLOCEV              ; One byte records the lifetime of each slot.
        ADD HL,DE
        LD A,1
        LD (HL),A                  ; A nonzero flag keeps this slot allocated.
        RET

; Set one bit in the current procedure's 128-slot capture mask.
SCMSKSET:
        LD (SCMSLOT),A             ; Preserve the slot through record arithmetic.
        LD A,(SCCURPR)             ; SCPREC addresses the current descriptor record.
        LD (SCMPR),A
        LD (SCTMPPR),A             ; The record helper uses the same descriptor index.
        CALL SCPREC
        LD DE,SCCAPOF              ; Skip the body, arity, formals and owner mask.
        ADD HL,DE
        LD (SCMTADR),HL            ; Save the start of the capture mask.
        LD A,(SCMSLOT)             ; Divide the slot by eight for its mask byte.
        LD C,A
        SRL A
        SRL A
        SRL A
        LD L,A
        LD H,0
        LD DE,(SCMTADR)
        ADD HL,DE
        LD (SCMTADR),HL            ; HL now names the selected mask byte.
        LD A,C                     ; The low three bits select a bit in that byte.
        JP SCBITSET

; Set one bit in the mask whose base address is in HL.
SCBITSET:
        LD (SCMSLOT),A             ; Preserve the slot through mask arithmetic.
        LD (SCMTADR),HL            ; Save the selected mask's first byte.
        LD A,(SCMSLOT)             ; The low three bits select a bit in that byte.
        AND 7
        LD B,A
        LD A,B
        OR A
        JR Z,SCMSK0
        LD A,1
SCMSKSH:
        ADD A,A
        DJNZ SCMSKSH
        JR SCMSKBIT
SCMSK0:
        LD A,1
SCMSKBIT:
        LD C,A                     ; Preserve the one-bit mask across the read.
        LD HL,(SCMTADR)
        LD A,(HL)
        OR C
        LD (HL),A
        RET
