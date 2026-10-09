; Scope publication fixups for globals, locals, literals and procedures.
; Entry points: PUB_FIX, PUB_LIT and PUB_SET.
; Patch the runtime's CALL operand with the absolute generated-code address.
PUB_LINK:
        LD HL,(ST_GBASE)           ; Generated code starts after the global area.
        LD DE,W_GLB_SZ
        ADD HL,DE
        CALL BR_ABS                ; Convert its staged address to COM address space.
        LD (PUB_ABS),HL            ; Retain the absolute entry address.
        LD HL,0100H+RT_CALLP       ; RT_CALLP points at the runtime CALL operand.
        LD DE,(PUB_ABS)            ; Recover the generated entry address.
        CALL SINK_FIX               ; Patch the runtime entry through the sink.
        CALL .IMAGE                 ; Publish the exact end of the loaded image.
        RET                        ; Return with the runtime image ready.

; Patch the runtime's image-end field with the complete executable extent.
.IMAGE:
        LD HL,(PUB_SIZE)            ; PUB_SIZE includes runtime, code and data.
        LD DE,0100H                 ; Add the COM origin to that length.
        ADD HL,DE                  ; HL now names the staged image end.
        CALL BR_ABS                ; Convert the staged end to a COM address.
        LD (PUB_ABS),HL            ; Keep the absolute end across the patch address.
        LD HL,0100H+RT_LIMIT        ; Locate the runtime's image-end field.
        LD DE,(PUB_ABS)            ; Recover the absolute published image end.
        CALL SINK_FIX               ; Patch the runtime image end through the sink.
        CALL .ROOTS                 ; Publish exact global and literal root bounds.
        RET C                       ; Do not hide a failed root patch with later work.
        CALL .SYMBOLS               ; Publish the symbol-literal directory range.
        RET                        ; The runtime can now derive its first free page.

; Patch the runtime's static root ranges after the complete image is sized.
; Globals, static locals and quoted-list caches are four-byte records with absolute
; addresses; zero-length ranges are represented by equal start and end words.
; The first range is the used part of the fixed global area; the second runs
; from the static let slots after the code through the quoted-list caches.
.ROOTS:
        LD HL,(ST_GBASE)
        LD (PUB_ABS),HL
        LD HL,0100H+G_BASE
        CALL .FIELD
        LD HL,(ST_GLOBS)           ; Four bytes for each allocated global.
        ADD HL,HL
        ADD HL,HL
        LD DE,(ST_GBASE)
        ADD HL,DE
        LD (PUB_ABS),HL
        LD HL,0100H+G_END
        CALL .FIELD
        LD HL,(PUB_LOC)            ; Static let slots precede the caches.
        CALL BR_ABS
        LD (PUB_ABS),HL
        LD HL,0100H+QT_START
        CALL .FIELD
        LD A,(QUO_CNT)
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,(QUO_BASE)
        ADD HL,DE
        CALL BR_ABS
        LD (PUB_ABS),HL
        LD HL,0100H+QT_STOP
        CALL .FIELD
        RET

; Store the absolute word held in PUB_ABS at the staged runtime field in HL.
.FIELD:
        LD DE,(PUB_ABS)
        JP SINK_FIX                 ; Tail-call the patch sink and return directly.

; Patch the runtime's symbol-directory bounds after literal serialization.
.SYMBOLS:
        LD HL,(LIT_DIR)
        CALL BR_ABS
        LD (PUB_ABS),HL
        LD HL,0100H+DR_DIR
        CALL .FIELD
        RET C
        LD HL,(LIT_END)
        CALL BR_ABS
        LD (PUB_ABS),HL
        LD HL,0100H+DR_DEND
        JR .FIELD

; Resolve every four-byte slot fixup recorded by the emitter.
PUB_FIX:
        LD HL,(ST_FIXES)           ; A zero count means no slot references exist.
        LD (PUB_TODO),HL           ; Keep the count while address arithmetic runs.
        LD A,H                     ; Test the high count byte first.
        OR L                       ; Set Z for the empty-fixup case.
        RET Z                      ; No generated operand needs patching.
        LD HL,W_FIXUPS             ; HL scans staged patch records in order.
PUB_EACH:
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
        JP Z,PUB_CELL              ; Cache targets use the dedicated cache base.
        CP 3                       ; Kind three names a copied literal record.
        JR Z,PUB_LIT               ; Literal targets are staged after descriptors.
        LD DE,(PUB_LOC)            ; Remaining slot fixups are static locals.
PUB_SLOT:
        LD A,(ST_FSLOT)            ; The slot number is a three-byte index.
        CALL PUB_ADDR              ; Return the absolute address of this slot.
        JR PUB_SET                 ; Share the placeholder write with descriptors.
PUB_LIT:
        LD A,(ST_FSLOT)            ; The fixup stores a literal-record index.
        CALL LIT_OUT             ; Locate its staged output base word.
        LD E,(HL)                  ; Read the staged literal header low byte.
        INC HL                     ; Advance to the high output address byte.
        LD D,(HL)                  ; DE now identifies the literal header.
        EX DE,HL                   ; BR_ABS converts the staged header address.
        CALL BR_ABS
        JR PUB_SET                 ; Share the placeholder write with descriptors.
PUB_SET:
        LD (PUB_ABS),HL            ; Retain the absolute target for the write.
        LD HL,(ST_FADDR)           ; Recover the staged placeholder address.
        LD DE,(PUB_ABS)            ; Recover the absolute slot address.
        CALL SINK_FIX               ; Patch the slot address through the sink.
        LD HL,(PUB_TODO)           ; Consume one record from the pending count.
        DEC HL                     ; The next iteration uses the following record.
        LD (PUB_TODO),HL           ; Publish the remaining fixup count.
        POP HL                     ; Recover the next fixup record address.
        LD DE,(PUB_TODO)           ; Reload the remaining count after restoring HL.
        LD A,D                     ; Test the remaining high count byte.
        OR E                       ; Continue until every placeholder is resolved.
        JR NZ,PUB_EACH             ; Continue until every placeholder is resolved.
        RET                        ; Carry remains clear after the final patch.
