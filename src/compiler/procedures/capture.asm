; Compiler formal, rest-binding and capture-mask management.
; Entry points: SCPDUP, SCRADD, SCRMETA, SCRETAIN and SCCAPSET.
; Return carry when the current procedure already has a formal with ST_SYMID.
SCPDUP:
        LD A,(ST_LTOP)             ; No active records means no duplicate exists.
        OR A
        RET Z
        LD B,A                     ; B counts the active local records.
        LD HL,W_LKEYS              ; HL scans the two-byte binding identities.
        LD DE,W_LSLOTS             ; DE scans their one-byte slot numbers.
SCPDUPLP:
        LD A,(HL)                  ; Compare the stored identity low byte.
        LD C,A
        LD A,(ST_SYMID)
        CP C
        JR NZ,SCPDUPLO             ; A low-byte mismatch skips to the next record.
        INC HL                     ; Compare the stored identity high byte.
        LD C,(HL)
        LD A,(ST_SYMID+1)
        CP C
        JR NZ,SCPDUPHI            ; A high-byte mismatch leaves this record.
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

; Add the current ST_SYMID as the procedure's one rest binding.  The binding is
; an ordinary local slot, but it remains outside the fixed-formal descriptor
; count so the runtime can build a list from surplus arguments.
SCRADD:
        CALL SCPDUP                ; A rest name cannot duplicate a fixed name.
        JR NC,SCRNEW            ; An outer binding may still be shadowed.
        LD HL,M_DUP                ; Reuse the ordinary duplicate-formal diagnostic.
        LD (ST_ERROR),HL
        SCF                        ; Report the duplicate without changing ST_SYMID.
        RET
SCRNEW:
        CALL SCNSLOT               ; Allocate a normal lexical slot for the list.
        RET C                      ; The local-slot bound remains the compiler gate.
        LD (ST_SLOT),A             ; SCADDLOC reads the selected slot from state.
        CALL SCADDLOC              ; Make the rest name visible in the body.
        RET C                      ; A full active directory is a compile error.
        LD A,(ST_SLOT)             ; Keep the slot for descriptor publication.
        LD (ST_RLIST),A
        LD A,1
        LD (ST_REST),A             ; The descriptor is marked after fixed formals close.
        XOR A                      ; Carry clear reports a complete rest binding.
        RET

; Mark a rest descriptor and store its local slot in a reserved high byte.
; Fixed descriptors keep the old all-zero high bytes and remain byte-stable.
SCRMETA:
        LD A,(ST_REST)
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
        LD A,(ST_RLIST)              ; The runtime reads this as the rest local slot.
        LD (HL),A
        XOR A                        ; Carry clear reports valid descriptor metadata.
        RET

; Return carry when ST_SYMID names one of the current procedure's formal slots.
SCPFORM:
        LD A,(ST_PROC)             ; Package-level definitions have no formals.
        CP 0FFH
        RET Z
        CALL SCPREC                ; Locate the active descriptor metadata.
        INC HL                     ; Skip the body address low byte.
        INC HL                     ; Skip the body address high byte.
        LD A,(HL)                  ; The high bit marks a procedure with a rest formal.
        LD (ST_ARITY),A            ; Keep the policy while the fixed fields are scanned.
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
        CALL SCFHAS                ; Is ST_SYMID bound to that slot in an active record?
        RET C                      ; Carry: ST_SYMID names this formal.
        DJNZ SCFLOOP
        LD A,(ST_ARITY)            ; Fixed names were absent; inspect the rest slot.
        AND 80H
        RET Z                      ; A fixed procedure has no further formal name.
        LD A,(ST_ARITY)
        AND 7FH
        CP 4
        JR Z,SCFREST4              ; Four fixed names leave field three's high byte.
        INC HL                     ; Earlier arities leave the next field's high byte.
        JR SCFREST
SCFREST4:
        DEC HL                     ; The fourth fixed field is the reserved rest slot.
SCFREST:
        XOR A                      ; Clear the marker so one rest scan terminates.
        LD (ST_ARITY),A
        LD B,1                      ; Reuse the ordinary slot comparison once.
        JR SCFLOOP
SCFNOFIX:
        LD A,(ST_ARITY)
        AND 80H
        RET Z                      ; A nullary fixed procedure has no formal names.
        INC HL                     ; The first field's high byte stores the rest slot.
        XOR A                      ; Clear the marker so one rest scan terminates.
        LD (ST_ARITY),A
        LD B,1
        JR SCFLOOP

; Return carry when an active binding record for local slot C holds ST_SYMID.
; W_LKEYS and W_LSLOTS are parallel by active-record position, not by slot.
; BC and HL are preserved; A, DE and flags are clobbered.
SCFHAS:
        PUSH HL
        PUSH BC
        LD A,(ST_LTOP)             ; No active records means no match.
        OR A
        JR Z,SCFHNO
        LD B,A                     ; B counts the active records.
        LD HL,W_LKEYS              ; HL scans the two-byte identities.
        LD DE,W_LSLOTS             ; DE scans the matching slot numbers.
SCFHLP:
        LD A,(DE)                  ; Only records for the formal's slot qualify.
        CP C
        JR NZ,SCFHNX
        PUSH HL                    ; Keep the record cursor across the compare.
        LD A,(ST_SYMID)            ; Compare the identity low byte.
        CP (HL)
        JR NZ,SCFHNE
        INC HL
        LD A,(ST_SYMID+1)          ; Compare the identity high byte.
        CP (HL)
SCFHNE:
        POP HL
        JR Z,SCFHYES               ; Both bytes matched.
SCFHNX:
        INC HL                     ; Advance to the next two-byte identity.
        INC HL
        INC DE                     ; Advance to the next slot number.
        DJNZ SCFHLP
SCFHNO:
        POP BC
        POP HL
        OR A                       ; Carry clear: no active record matched.
        RET
SCFHYES:
        POP BC
        POP HL
        SCF                        ; Carry: ST_SYMID is bound to slot C.
        RET

; Keep recursive forward cells while discarding the lambda's private locals.
; A forward name may have been discovered after the lambda's formals, so its
; active-directory entry must survive the frame restore for a later declaration
; to claim the same slot.
SCRETAIN:
        LD A,(ST_LTOP)
        LD A,(ST_OTOP)
        LD A,(ST_RMODE)
        OR A
        JR NZ,SCRTSCAN
        LD A,(ST_OTOP)
        LD (ST_LTOP),A
        LD A,(ST_ONEXT)
        LD (ST_LNEXT),A
        RET
SCRTSCAN:
        LD A,(ST_LTOP)
        LD (ST_KTOP),A
        LD A,(ST_OTOP)
        LD B,A
        LD C,A
SCRTLOOP:
        LD A,(ST_KTOP)
        CP B
        JR Z,SCRTDONE
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
        JR NZ,SCRTNEXT
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
SCRTNEXT:
        LD A,(ST_KSRC)
        INC A
        LD B,A
        JR SCRTLOOP
SCRTDONE:
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
SCUNWIND:
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
        CALL SCRETAIN               ; Keep forward cells before restoring the frame.
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
SCOWNSET:
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
        LD (ST_DESC),A             ; SCPREC uses the selected descriptor index.
        CALL SCPREC
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
        LD A,C                     ; SCBITSET consumes the original slot index.
        JP SCBITSET                ; Set its bit in the descriptor mask.

; Mark a slot captured by the current procedure when its owner is outer.
SCCAPSET:
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
        CALL SCEVSET
        LD A,B                     ; Remember the procedure that owns the cell.
        LD (ST_OWNER),A
        LD A,(ST_PROC)             ; Preserve the active procedure across mask writes.
        LD (ST_CPROC),A
        LD A,(ST_DESC)             ; Preserve the descriptor currently being finished.
        LD (ST_CDESC),A
        LD A,(ST_MSLOT)             ; Pass the captured slot to the mask writer.
        CALL SCMSKSET               ; The current procedure needs the capture bit.
        LD A,(ST_BNEST)            ; Walk through every intermediate procedure.
        LD (ST_CHAIN),A
SCCAPCHN:
        LD A,(ST_CHAIN)            ; The frame index is one below the current depth.
        OR A
        JR Z,SCCAPRST             ; A malformed chain still restores compiler state.
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
        JR Z,SCCAPRST             ; The owner already owns the shared cell.
        LD A,B
        LD (ST_PROC),A             ; Select this intermediate descriptor.
        LD A,(ST_MSLOT)            ; Every enclosing mask names the same cell slot.
        CALL SCMSKSET              ; Preserve the cell through this procedure too.
        JR SCCAPCHN              ; Continue toward the procedure that owns it.
SCCAPRST:
        LD A,(ST_CPROC)            ; Restore the active compiler procedure.
        LD (ST_PROC),A
        LD A,(ST_CDESC)            ; Restore the descriptor being finalized.
        LD (ST_DESC),A
        RET

; Mark one compiler slot as captured so a later sibling cannot reuse its cell.
SCEVSET:
        LD L,A                     ; Widen the zero-based slot index.
        LD H,0
        LD DE,W_ESCAPE             ; One byte records the lifetime of each slot.
        ADD HL,DE
        LD A,1
        LD (HL),A                  ; A nonzero flag keeps this slot allocated.
        RET

; Set one bit in the current procedure's 128-slot capture mask.
SCMSKSET:
        LD (ST_MSLOT),A            ; Preserve the slot through record arithmetic.
        LD A,(ST_PROC)             ; SCPREC addresses the current descriptor record.
        LD (ST_MPROC),A
        LD (ST_DESC),A             ; The record helper uses the same descriptor index.
        CALL SCPREC
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
SCBITSET:
        LD (ST_MSLOT),A            ; Preserve the slot through mask arithmetic.
        LD (ST_MASKP),HL           ; Save the selected mask's first byte.
        LD A,(ST_MSLOT)            ; The low three bits select a bit in that byte.
        AND 7
        LD B,A                     ; B shifts the bit; Z means bit zero.
        LD A,1
        JR Z,SCMSKBIT
SCMSKSH:
        ADD A,A
        DJNZ SCMSKSH
SCMSKBIT:
        LD C,A                     ; Preserve the one-bit mask across the read.
        LD HL,(ST_MASKP)
        LD A,(HL)
        OR C
        LD (HL),A
        RET
