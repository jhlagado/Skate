; Scope publication fixups for globals, locals, literals and procedures.
; Entry points: SCPSLOTS, SCFLIT and SCFPATCH.
; Patch the runtime's CALL operand with the absolute generated-code address.
SCPENTRY:
        LD HL,(ST_GBASE)           ; Generated code starts after the global area.
        LD DE,W_GLB_SZ
        ADD HL,DE
        CALL BR_ABS                ; Convert its staged address to COM address space.
        LD (SCTARG),HL             ; Retain the absolute entry address.
        LD HL,0100H+SRTCLP         ; SRTCLP points at the runtime CALL operand.
        LD DE,(SCTARG)             ; Recover the generated entry address.
        CALL SINKPTCH               ; Patch the runtime entry through the sink.
        CALL SCPIMG                 ; Publish the exact end of the loaded image.
        RET                        ; Return with the runtime image ready.

; Patch the runtime's image-end field with the complete executable extent.
SCPIMG:
        LD HL,(SCIMGL)              ; SCIMGL includes runtime, code and data.
        LD DE,0100H                 ; Add the COM origin to that length.
        ADD HL,DE                  ; HL now names the staged image end.
        CALL BR_ABS                ; Convert the staged end to a COM address.
        LD (SCTARG),HL             ; Keep the absolute end across the patch address.
        LD HL,0100H+RT_LIMIT        ; Locate the runtime's image-end field.
        LD DE,(SCTARG)             ; Recover the absolute published image end.
        CALL SINKPTCH               ; Patch the runtime image end through the sink.
        CALL SCPROOTS               ; Publish exact global and literal root bounds.
        RET C                       ; Do not hide a failed root patch with later work.
        CALL SCPSTAB                ; Publish the symbol-literal directory range.
        RET                        ; The runtime can now derive its first free page.

; Patch the runtime's static root ranges after the complete image is sized.
; Globals, static locals and quoted-list caches are four-byte records with absolute
; addresses; zero-length ranges are represented by equal start and end words.
; The first range is the used part of the fixed global area; the second runs
; from the static let slots after the code through the quoted-list caches.
SCPROOTS:
        LD HL,(ST_GBASE)
        LD (SCTARG),HL
        LD HL,0100H+G_BASE
        CALL SCPROOTW
        LD HL,(ST_GLOBS)           ; Four bytes for each allocated global.
        ADD HL,HL
        ADD HL,HL
        LD DE,(ST_GBASE)
        ADD HL,DE
        LD (SCTARG),HL
        LD HL,0100H+G_END
        CALL SCPROOTW
        LD HL,(SCLBASE)            ; Static let slots precede the caches.
        CALL BR_ABS
        LD (SCTARG),HL
        LD HL,0100H+QT_START
        CALL SCPROOTW
        LD A,(SCQCNT)
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,(SCQBASE)
        ADD HL,DE
        CALL BR_ABS
        LD (SCTARG),HL
        LD HL,0100H+QT_STOP
        CALL SCPROOTW
        RET

; Store the absolute word held in SCTARG at the staged runtime field in HL.
SCPROOTW:
        LD DE,(SCTARG)
        JP SINKPTCH                 ; Tail-call the patch sink and return directly.

; Patch the runtime's symbol-directory bounds after literal serialization.
SCPSTAB:
        LD HL,(SCSYMBAS)
        CALL BR_ABS
        LD (SCTARG),HL
        LD HL,0100H+DR_DIR
        CALL SCPROOTW
        RET C
        LD HL,(SCSYMEND)
        CALL BR_ABS
        LD (SCTARG),HL
        LD HL,0100H+DR_DEND
        JP SCPROOTW

; Resolve every four-byte slot fixup recorded by the emitter.
SCPSLOTS:
        LD HL,(ST_FIXES)           ; A zero count means no slot references exist.
        LD (SCFIXC),HL             ; Keep the count while address arithmetic runs.
        LD A,H                     ; Test the high count byte first.
        OR L                       ; Set Z for the empty-fixup case.
        RET Z                      ; No generated operand needs patching.
        LD HL,W_FIXUPS             ; HL scans staged patch records in order.
SCFIXLP:
        LD E,(HL)                  ; Read the staged patch address low byte.
        INC HL                     ; Advance to the high address byte.
        LD D,(HL)                  ; DE now identifies the placeholder word.
        INC HL                     ; Advance to the slot-kind byte.
        LD A,(HL)                  ; Read zero for global or one for local.
        LD (ST_FKIND),A            ; Preserve the kind across address arithmetic.
        INC HL                     ; Advance to the slot-number byte.
        LD A,(HL)                  ; Read the zero-based slot number.
        LD (ST_FSLOT),A            ; Preserve it while selecting the data base.
        INC HL                     ; Advance to the following fixup record.
        PUSH HL                    ; Keep the table cursor across address patching.
        LD (ST_FADDR),DE           ; Preserve the staged patch destination.
        LD A,(ST_FKIND)            ; Select a global, local or procedure target.
        CP 4                       ; Kind four names a quoted-list cache cell.
        JP Z,SCFQCH                ; Cache targets use the dedicated cache base.
        CP 3                       ; Kind three names a copied literal record.
        JR Z,SCFLIT                ; Literal targets are staged after descriptors.
        LD DE,(SCLBASE)            ; Remaining slot fixups are static locals.
SCFADDR:
        LD A,(ST_FSLOT)            ; The slot number is a three-byte index.
        CALL SCADDR                ; Return the absolute address of this slot.
        JR SCFPATCH                ; Share the placeholder write with descriptors.
SCFLIT:
        LD A,(ST_FSLOT)            ; The fixup stores a literal-record index.
        CALL SCLITOA             ; Locate its staged output base word.
        LD E,(HL)                  ; Read the staged literal header low byte.
        INC HL                     ; Advance to the high output address byte.
        LD D,(HL)                  ; DE now identifies the literal header.
        EX DE,HL                   ; BR_ABS converts the staged header address.
        CALL BR_ABS
        JR SCFPATCH                ; Share the placeholder write with descriptors.
SCFPATCH:
        LD (SCTARG),HL             ; Retain the absolute target for the write.
        LD HL,(ST_FADDR)           ; Recover the staged placeholder address.
        LD DE,(SCTARG)             ; Recover the absolute slot address.
        CALL SINKPTCH               ; Patch the slot address through the sink.
        LD HL,(SCFIXC)             ; Consume one record from the pending count.
        DEC HL                     ; The next iteration uses the following record.
        LD (SCFIXC),HL             ; Publish the remaining fixup count.
        POP HL                     ; Recover the next fixup record address.
        LD DE,(SCFIXC)             ; Reload the remaining count after restoring HL.
        LD A,D                     ; Test the remaining high count byte.
        OR E                       ; Continue until every placeholder is resolved.
        JR NZ,SCFIXLP              ; Continue until every placeholder is resolved.
        RET                        ; Carry remains clear after the final patch.
