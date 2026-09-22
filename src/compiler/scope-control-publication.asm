;=============================================================================
;  Scope compiler final layout and CP/M publication
;=============================================================================
;
;  SCFIN closes the staged image, fixes every slot address, and serializes the
;  NOBJ records.  SCOUT writes the object and matching COM image to temporary
;  CP/M files before installing their final names.
;=============================================================================

; Append zeroed four-byte slots, resolve generated addresses, and build NOBJ.
SCFIN:
        LD HL,(SCPC)              ; Generated code ends at the current cursor.
        PUSH HL                    ; Keep the code end while sizing slot data.
        LD HL,(SCGCOUNT)           ; Four bytes are needed for every global slot.
        ADD HL,HL
        ADD HL,HL
        LD A,(SCLOCMAX)            ; Add four bytes for every local high-water slot.
        PUSH HL                    ; Keep the global extent while scaling locals.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        EX DE,HL                   ; DE now contains four times the local count.
        POP HL                     ; Restore the four-times-global extent.
        ADD HL,DE
        PUSH HL                    ; Keep the combined user-slot extent.
        LD A,(SCQCNT)             ; Add one four-byte cache cell per quoted list.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        EX DE,HL                   ; DE now contains the cache-cell extent.
        POP HL                     ; Restore the global/local slot extent.
        ADD HL,DE
        PUSH HL                    ; Keep the slot extent while sizing descriptors.
        LD A,(SCPCOUNT)            ; Every procedure uses one fixed metadata record.
        LD L,A                     ; Widen the descriptor count to a word.
        LD H,0
        LD D,H                     ; Keep the original count for the final add.
        LD E,L
        ADD HL,HL                  ; Two times the descriptor count.
        ADD HL,HL                  ; Four times the descriptor count.
        PUSH HL                    ; Keep four times the count.
        ADD HL,HL                  ; Eight times the descriptor count.
        PUSH HL                    ; Keep eight times the count.
        ADD HL,HL                  ; Sixteen times the descriptor count.
        ADD HL,HL                  ; Thirty-two times the descriptor count.
        POP DE                     ; Recover eight times the count.
        ADD HL,DE                  ; Forty times the descriptor count.
        POP DE                     ; Recover four times the count.
        ADD HL,DE                  ; Complete forty-four bytes per descriptor.
        POP DE                     ; Recover the global and local slot extent.
        ADD HL,DE                  ; Add descriptor records to the final image.
        LD DE,32                   ; Leave room for the serialized tail and checksum.
        ADD HL,DE
        POP DE                     ; DE is the generated-code end address.
        ADD HL,DE                  ; HL is the complete staged-image end estimate.
        JP C,SCCAP                 ; A wrapped extent cannot fit in the staged region.
        LD DE,SCGENEND             ; The final payload must end below the tail guard.
        OR A                       ; Clear carry before the boundary comparison.
        SBC HL,DE
        JP NC,SCCAP                ; Reject before appending slot bytes.
        LD HL,(SCPC)               ; Restore the generated-code cursor for slot data.
        LD (SCGBASE),HL           ; Globals follow the generated instruction bytes.
        LD BC,(SCGCOUNT)          ; One four-byte record is reserved per global.
        XOR A                     ; Global slot zero is the first primitive mark.
        LD (SCGIDX),A
        JP SCGDATA                 ; Skip the helper body before entering the loop.

; Write one global value record, seeding predefined names with their procedure
; value while leaving ordinary names unbound until a definition stores them.
SCGINIT:
        PUSH HL                   ; Keep the slot cursor while reading its mark.
        LD A,(SCGIDX)             ; The compiler mark table is byte indexed.
        LD L,A
        LD H,0
        LD DE,SCGPRIM
        ADD HL,DE
        LD A,(HL)                 ; Zero denotes an ordinary uninitialized name.
        POP HL                    ; Resume at the four-byte output record.
        OR A
        JR Z,SCGZERO              ; Ordinary names receive four zero bytes.
        DEC A                     ; Convert kind one..four to payload low $20..$23.
        ADD A,20H
        LD (HL),A                 ; Primitive procedure payload low byte.
        INC HL
        LD A,0FEH                 ; Primitive payloads use the reserved high byte.
        LD (HL),A
        INC HL
        XOR A                     ; Tag zero identifies a primitive procedure value.
        LD (HL),A
        INC HL
        LD A,1                     ; Predefined values are initialized at startup.
        LD (HL),A
        INC HL
        RET
SCGZERO:
        XOR A                     ; Ordinary names begin with no payload or tag.
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A                 ; The zero flag makes an unresolved load fail.
        INC HL
        RET

SCGDATA:
        LD A,B                     ; Test the high count byte first.
        OR C                       ; A zero pair means all global slots are present.
        JR Z,SCLDATA               ; Continue with local storage after the globals.
        CALL SCGINIT               ; Materialize an ordinary or predefined value.
        LD A,(SCGIDX)              ; Advance the primitive-mark cursor.
        INC A
        LD (SCGIDX),A
        DEC BC                     ; Account for the slot just appended.
        JR SCGDATA                 ; Continue until the global count is exhausted.
SCLDATA:
        LD (SCLBASE),HL            ; Locals follow the complete global area.
        LD A,(SCLOCMAX)            ; The local high-water mark sets its extent.
        LD C,A                     ; Widen the byte count to a normal word.
        LD B,0                     ; Local slots also occupy four bytes each.
SCLOOP:
        LD A,B                     ; Test the high count byte first.
        OR C                       ; A zero pair means all local slots are present.
        JR Z,SCDATAOK              ; Continue with address fixups.
        XOR A                      ; Local slots start with zero payload and flag.
        LD (HL),A                  ; Store the payload low byte.
        INC HL                     ; Advance to the payload high byte.
        LD (HL),A                  ; Store the payload high byte.
        INC HL                     ; Advance to the stored value tag.
        LD (HL),A                  ; A zero tag is harmless while the slot is unbound.
        INC HL                     ; Advance to the initialized flag.
        LD (HL),A                  ; A zero flag protects an uninitialized local.
        INC HL                     ; Advance to the following local slot.
        DEC BC                     ; Account for the slot just appended.
        JR SCLOOP                  ; Continue until the local extent is filled.
SCDATAOK:
        LD (SCQBASE),HL            ; Quoted-list cache cells follow local storage.
        LD A,(SCQCNT)
        LD C,A
        LD B,0
SCQCLOOP:
        LD A,B
        OR C
        JR Z,SCQCDONE
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        DEC BC
        JR SCQCLOOP
SCQCDONE:
        LD (SCPC),HL               ; Publish the final staged image cursor.
        CALL SCPDESC               ; Append absolute procedure descriptors.
        RET C                      ; Preserve the staged-image capacity guard.
        CALL SCLITDAT             ; Append copied symbol and string literals.
        RET C                      ; Preserve the staged-image capacity guard.
        LD HL,(SCPC)               ; Literal data advances the final image cursor.
        LD DE,SCIMG                ; The payload begins at the staged image base.
        OR A                       ; Clear carry before measuring the image.
        SBC HL,DE                  ; HL becomes runtime plus code plus slot data.
        LD (SCIMGL),HL             ; SCOUT streams this exact payload length.
        LD DE,SCGENEND             ; The staged compiler region has a fixed guard.
        LD HL,(SCPC)               ; Compare the absolute cursor with that guard.
        OR A                       ; Clear carry before the boundary subtraction.
        SBC HL,DE                  ; A carry-free result means the cursor crossed it.
        JP NC,SCCAP                ; Reject output that would overwrite compiler tables.
        CALL SCPENTRY              ; Point the runtime image at the generated program.
        CALL SCPSLOTS              ; Replace every slot placeholder with an address.
        CALL SCBUILD               ; Add the NOBJ header, tail records and checksum.
        RET                        ; Carry reports any capacity or layout failure.

; Patch the runtime's CALL operand with the absolute generated-code address.
SCPENTRY:
        LD HL,SCCODE               ; Generated code starts after the runtime image.
        CALL SCABS                 ; Convert its staged address to COM address space.
        LD (SCTARG),HL             ; Retain the absolute entry address.
        LD HL,SCIMG+SRTCLP         ; SRTCLP points at the runtime CALL operand.
        LD DE,(SCTARG)             ; Recover the generated entry address.
        LD (HL),E                  ; Patch the low byte of the CALL operand.
        INC HL                     ; Advance to the high byte.
        LD (HL),D                  ; Complete the runtime entry patch.
        CALL SCPIMG                 ; Publish the exact end of the loaded image.
        RET                        ; Return with the runtime image ready.

; Patch the runtime's image-end field with the complete executable extent.
SCPIMG:
        LD HL,(SCIMGL)              ; SCIMGL includes runtime, code and data.
        LD DE,SCIMG                 ; Add the staged payload base to that length.
        ADD HL,DE                  ; HL now names the staged image end.
        CALL SCABS                 ; Convert the staged end to a COM address.
        LD (SCTARG),HL             ; Keep the absolute end across the patch address.
        LD HL,SCIMG+SRTIMGE         ; Locate the runtime's image-end field.
        LD DE,(SCTARG)             ; Recover the absolute published image end.
        LD (HL),E                  ; Store the low address byte for page setup.
        INC HL                     ; Advance to the high address byte.
        LD (HL),D                  ; Complete the runtime image-end value.
        CALL SCPROOTS               ; Publish exact global and literal root bounds.
        RET                        ; The runtime can now derive its first free page.

; Patch the runtime's static root ranges after the complete image is sized.
; Globals and quoted-list cache cells are four-byte records with absolute
; addresses; zero-length ranges are represented by equal start and end words.
SCPROOTS:
        LD HL,(SCGBASE)
        CALL SCABS
        LD (SCTARG),HL
        LD HL,SCIMG+SRTGBASE
        CALL SCPROOTW
        LD HL,(SCGCOUNT)
        ADD HL,HL
        ADD HL,HL
        LD DE,(SCGBASE)
        ADD HL,DE
        CALL SCABS
        LD (SCTARG),HL
        LD HL,SCIMG+SRTGEND
        CALL SCPROOTW
        LD HL,(SCQBASE)
        CALL SCABS
        LD (SCTARG),HL
        LD HL,SCIMG+SRTQROOT
        CALL SCPROOTW
        LD A,(SCQCNT)
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,(SCQBASE)
        ADD HL,DE
        CALL SCABS
        LD (SCTARG),HL
        LD HL,SCIMG+SRTQENDR
        CALL SCPROOTW
        RET

; Store the absolute word held in SCTARG at the staged runtime field in HL.
SCPROOTW:
        LD DE,(SCTARG)
        LD (HL),E
        INC HL
        LD (HL),D
        RET

; Resolve every four-byte slot fixup recorded by the emitter.
SCPSLOTS:
        LD HL,(SCFIXN)             ; A zero count means no slot references exist.
        LD (SCFIXC),HL             ; Keep the count while address arithmetic runs.
        LD A,H                     ; Test the high count byte first.
        OR L                       ; Set Z for the empty-fixup case.
        RET Z                      ; No generated operand needs patching.
        LD HL,SCFIXTAB             ; HL scans staged patch records in order.
SCFIXLP:
        LD E,(HL)                  ; Read the staged patch address low byte.
        INC HL                     ; Advance to the high address byte.
        LD D,(HL)                  ; DE now identifies the placeholder word.
        INC HL                     ; Advance to the slot-kind byte.
        LD A,(HL)                  ; Read zero for global or one for local.
        LD (SCFKIND),A             ; Preserve the kind across address arithmetic.
        INC HL                     ; Advance to the slot-number byte.
        LD A,(HL)                  ; Read the zero-based slot number.
        LD (SCFSLOT),A             ; Preserve it while selecting the data base.
        INC HL                     ; Advance to the following fixup record.
        PUSH HL                    ; Keep the table cursor across address patching.
        LD (SCFPTR),DE             ; Preserve the staged patch destination.
        LD A,(SCFKIND)             ; Select a global, local or procedure target.
        CP 4                       ; Kind four names a quoted-list cache cell.
        JP Z,SCFQCH                ; Cache targets use the dedicated cache base.
        CP 3                       ; Kind three names a copied literal record.
        JR Z,SCFLIT                ; Literal targets are staged after descriptors.
        CP 2                       ; Kind two names the serialized procedure table.
        JR Z,SCFPROC               ; Procedure fixups point at descriptor records.
        OR A                       ; Zero selects the global base.
        JR Z,SCFGLOB               ; A local fixup uses the local base instead.
        LD DE,(SCLBASE)            ; Select the local data region.
        JR SCFADDR                 ; Both paths share the slot-offset arithmetic.
SCFGLOB:
        LD DE,(SCGBASE)            ; Select the global data region.
SCFADDR:
        LD A,(SCFSLOT)             ; The slot number is a three-byte index.
        CALL SCADDR                ; Return the absolute address of this slot.
        JR SCFPATCH                ; Share the placeholder write with descriptors.
SCFLIT:
        LD A,(SCFSLOT)             ; The fixup stores a literal-record index.
        CALL SCLITOA             ; Locate its staged output base word.
        LD E,(HL)                  ; Read the staged literal header low byte.
        INC HL                     ; Advance to the high output address byte.
        LD D,(HL)                  ; DE now identifies the literal header.
        EX DE,HL                   ; SCABS converts the staged header address.
        CALL SCABS
        JR SCFPATCH                ; Share the placeholder write with descriptors.
SCFPROC:
        LD A,(SCFSLOT)             ; The fixup stores a descriptor table index.
        LD L,A                     ; Widen the index before multiplying by forty-four.
        LD H,0
        LD D,H                     ; Keep the original index for the final add.
        LD E,L
        ADD HL,HL                  ; Two bytes per descriptor index.
        ADD HL,HL                  ; Four bytes per descriptor index.
        PUSH HL                    ; Keep four bytes per descriptor index.
        ADD HL,HL                  ; Eight bytes per descriptor index.
        PUSH HL                    ; Keep eight bytes per descriptor index.
        ADD HL,HL                  ; Sixteen bytes per descriptor index.
        ADD HL,HL                  ; Thirty-two bytes per descriptor index.
        POP DE                     ; Recover eight bytes per descriptor index.
        ADD HL,DE                  ; Forty bytes per descriptor index.
        POP DE                     ; Recover four bytes per descriptor index.
        ADD HL,DE                  ; Complete the forty-four-byte offset.
        LD DE,(SCPBASE)            ; Add the staged descriptor table base.
        ADD HL,DE                  ; Locate the descriptor's staged record.
        CALL SCABS                 ; Convert its staged address to COM space.
SCFPATCH:
        LD (SCTARG),HL             ; Retain the absolute target for the write.
        LD HL,(SCFPTR)             ; Recover the staged placeholder address.
        LD DE,(SCTARG)             ; Recover the absolute slot address.
        LD (HL),E                  ; Patch the low address byte.
        INC HL                     ; Advance to the high address byte.
        LD (HL),D                  ; Complete the slot-address fixup.
        LD HL,(SCFIXC)             ; Consume one record from the pending count.
        DEC HL                     ; The next iteration uses the following record.
        LD (SCFIXC),HL             ; Publish the remaining fixup count.
        POP HL                     ; Recover the next fixup record address.
        LD DE,(SCFIXC)             ; Reload the remaining count after restoring HL.
        LD A,D                     ; Test the remaining high count byte.
        OR E                       ; Continue until every placeholder is resolved.
        JR NZ,SCFIXLP              ; Continue until every placeholder is resolved.
        RET                        ; Carry remains clear after the final patch.

; Append the procedure descriptor table after global and local storage.
SCPDESC:
        LD HL,(SCPC)               ; The table begins at the current image cursor.
        LD (SCPBASE),HL            ; Fixups use this staged base after serialization.
        LD A,(SCPCOUNT)            ; No procedures leave the cursor unchanged.
        LD (SCPDREM),A             ; Keep the remaining descriptor count.
        OR A
        RET Z
        XOR A                      ; Descriptor zero is the first record.
        LD (SCPDIDX),A             ; The index is also stored in every fixup.
SCPDLOOP:
        LD A,(SCPDIDX)             ; Select the metadata record being published.
        LD (SCTMPPR),A             ; SCPREC uses the current descriptor index.
        CALL SCPREC                ; Locate its compiler-side metadata record.
        LD (SCPTR),HL              ; Preserve the metadata cursor across writes.
        LD HL,(SCPTR)              ; Read the generated body address.
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL                   ; SCPDWRD takes the body address in HL.
        CALL SCPDWRD               ; Write the two-byte body address.
        RET C
        LD HL,(SCPTR)              ; Read the fixed arity and slot count.
        INC HL
        INC HL
        LD A,(HL)                  ; Descriptor byte two is its formal count.
        CALL SCBYTE                ; Use the normal guarded image writer.
        RET C
        LD A,(SCLOCMAX)            ; Every environment has the bounded slot extent.
        CALL SCBYTE
        RET C
        LD HL,(SCPTR)
        INC HL
        INC HL
        INC HL
        INC HL                    ; HL now points at the first formal slot byte.
        LD (SCPTR),HL              ; Keep it while each formal index is written.
        LD A,4
        LD (SCPDSLT),A             ; Every descriptor has four fixed formal fields.
SCPDSLP:
        LD HL,(SCPTR)              ; Read one compiler-local slot index.
        LD A,(HL)                  ; The low byte is the dynamic slot number.
        INC HL
        INC HL                     ; Skip the reserved high byte.
        LD (SCPTR),HL
        CALL SCBYTE                ; Write the formal slot index low byte.
        RET C
        XOR A                      ; The high byte keeps the descriptor format fixed.
        CALL SCBYTE
        RET C
        LD A,(SCPDSLT)            ; Four fields are emitted for every record.
        DEC A
        LD (SCPDSLT),A
        JR NZ,SCPDSLP
        LD HL,(SCPTR)              ; Owned-slot mask starts after the formal fields.
        LD (SCPTR),HL
        LD B,SCMASKB
SCPMLOOP:
        LD HL,(SCPTR)
        LD A,(HL)
        INC HL
        LD (SCPTR),HL
        CALL SCBYTE
        RET C
        DJNZ SCPMLOOP
        LD HL,(SCPTR)              ; The owner loop has reached the capture mask.
        LD (SCPTR),HL
        LD B,SCMASKB
SCPNLOOP:
        LD HL,(SCPTR)
        LD A,(HL)
        INC HL
        LD (SCPTR),HL
        CALL SCBYTE
        RET C
        DJNZ SCPNLOOP
        LD A,(SCPDIDX)              ; Advance to the following descriptor.
        INC A
        LD (SCPDIDX),A
        LD A,(SCPDREM)
        DEC A
        LD (SCPDREM),A
        JP NZ,SCPDLOOP
        XOR A
        RET

; Write an absolute descriptor word through the guarded image emitter.
SCPDWRD:
        LD (SCTARG),HL
        LD A,L
        CALL SCBYTE
        RET C
        LD HL,(SCTARG)
        LD A,H
        JP SCBYTE

; Convert a staged four-byte-slot address into its absolute COM address.
SCADDR:
        LD L,A                     ; Widen the slot index to a word.
        LD H,0                     ; The high byte is zero for all current slots.
        ADD HL,HL                  ; Form two times the slot number.
        ADD HL,HL                  ; Form four times the slot number.
        ADD HL,DE                  ; Add the selected staged data base.
        JP SCABS                   ; Convert the staged pointer to COM address.

SCFQCH:
        LD DE,(SCQBASE)            ; Select the quoted-list cache base.
        JP SCFADDR                  ; Share the four-byte slot arithmetic.

; Serialize the fixed NOBJ prefix, dynamic image record, tail and CRC.
SCBUILD:
        LD HL,SCHEAD                ; The fixed prefix is the copy source.
        LD DE,SCSTAGE              ; The object always begins at its staging base.
        LD BC,70                   ; The first image record header begins at offset 70.
        LDIR                       ; Materialize the prefix in the staged object.
        LD HL,(SCIMGL)              ; Runtime, generated code and data length.
        LD DE,6                    ; NOBJ IMAGE length includes its six-byte descriptor.
        ADD HL,DE                  ; The record length is image bytes plus descriptor.
        LD A,6                     ; Record kind six denotes an IMAGE record.
        LD (SCSTAGE+70),A           ; Store the record kind after the prefix.
        LD A,L                     ; Store the record length low byte.
        LD (SCSTAGE+71),A           ; The object format is little endian.
        LD A,H                     ; Store the record length high byte.
        LD (SCSTAGE+72),A           ; Complete the IMAGE record header.
        LD HL,SCIMAGE               ; The six-byte descriptor is the copy source.
        LD DE,SCSTAGE+73            ; Point at the descriptor destination.
        LD BC,6                     ; The descriptor is six bytes long.
        LDIR                       ; Copy the descriptor before the image payload.
        LD HL,SCIMG                 ; The payload already contains the runtime image.
        LD DE,(SCIMGL)              ; Skip the complete runtime and generated image.
        ADD HL,DE                  ; HL now points at the first tail record.
        LD (SCTAILP),HL             ; Preserve the tail address for CRC and length.
        EX DE,HL                   ; DE is the dynamic tail destination.
        LD HL,SCTAIL               ; The fixed tail is the copy source.
        LD BC,30                   ; The final two bytes are reserved for the CRC.
        LDIR                       ; Materialize every tail byte before checksum work.
        LD HL,(SCTAILP)             ; Reconstruct the end of the CRC-covered prefix.
        LD DE,30                   ; Exclude only the two checksum bytes themselves.
        ADD HL,DE                  ; HL is one past the covered object prefix.
        LD DE,SCSTAGE               ; Convert the end pointer into a byte count.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,DE                  ; HL now counts all bytes before the checksum.
        LD (SCCRCL),HL              ; Save the CRC input length.
        LD DE,32                   ; The complete tail includes its checksum word.
        LD HL,(SCTAILP)             ; Restore the tail start address.
        ADD HL,DE                  ; HL is one past the complete object.
        LD DE,SCSTAGE               ; Convert the complete end pointer into a length.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,DE                  ; HL is the complete serialized object length.
        LD (SCOBJL),HL              ; SCOUT streams exactly this many bytes.
        CALL SCCRC                  ; Compute CRC-16/CCITT-FALSE over the prefix.
        LD HL,(SCTAILP)             ; Locate the two checksum bytes at tail offset 30.
        LD DE,30                   ; Skip the 30 fixed tail bytes.
        ADD HL,DE                  ; HL now points at the checksum field.
        LD DE,(SCCRVAL)             ; Recover the computed little-endian checksum.
        LD (HL),E                  ; Store the low CRC byte first.
        INC HL                     ; Advance to the high checksum byte.
        LD (HL),D                  ; Complete the COMMIT record.
        RET                        ; Return with a complete object in SCSTAGE.

; Compute CRC-16/CCITT-FALSE over SCSTAGE for SCCRCL bytes.
SCCRC:
        LD HL,SCSTAGE              ; Start at the first serialized object byte.
        LD BC,(SCCRCL)             ; Cover every byte before the checksum field.
        LD DE,0FFFFH               ; CRC-16/CCITT-FALSE initial value.
        LD (SCPTR),HL              ; Preserve the input pointer across bit work.
        LD (SCLEFT),BC             ; Preserve the remaining count across bit work.
SCCRBY:
        LD BC,(SCLEFT)             ; Test the high byte of the remaining count.
        LD A,B                     ; Combine both count bytes into one zero test.
        OR C                       ; A zero pair means the CRC input is complete.
        JR Z,SCCRFIN                ; Store the completed CRC in the caller's field.
        LD HL,(SCPTR)              ; Load the next object byte address.
        LD A,(HL)                  ; Mix one serialized byte into the high CRC byte.
        INC HL                     ; Advance the input pointer.
        LD (SCPTR),HL              ; Preserve it for the next object byte.
        XOR D                      ; The polynomial operates on the high byte first.
        LD D,A                     ; Publish the mixed high CRC byte.
        LD A,8                     ; Process all eight bits of this byte.
        LD (SCBITS),A              ; Keep the inner-loop count outside DE.
SCCRBIT:
        SLA E                      ; Shift the low CRC byte toward the high byte.
        RL D                       ; Shift the high CRC byte and expose carry.
        JR NC,SCCRNOX              ; No polynomial reduction when carry is clear.
        LD A,D                     ; Load the high CRC byte for the polynomial XOR.
        XOR 10H                    ; Apply the high polynomial byte.
        LD D,A                     ; Store the reduced high CRC byte.
        LD A,E                     ; Load the low CRC byte for the polynomial XOR.
        XOR 21H                    ; Apply the low polynomial byte.
        LD E,A                     ; Store the reduced low CRC byte.
SCCRNOX:
        LD A,(SCBITS)              ; Load the remaining bit count.
        DEC A                      ; Account for the bit just processed.
        LD (SCBITS),A              ; Preserve the updated bit count.
        JR NZ,SCCRBIT              ; Continue until all eight bits are shifted.
        LD BC,(SCLEFT)             ; Reload the remaining object-byte count.
        DEC BC                     ; Account for the byte just processed.
        LD (SCLEFT),BC             ; Publish the decremented count.
        JR SCCRBY                  ; Process the next object byte.
SCCRFIN:
        LD (SCCRVAL),DE             ; Return the completed checksum to SCBUILD.
        RET                        ; The caller writes it to the tail.

; Stream the complete object or COM image through the CP/M transport.
SCSTREAM:
        LD (SCPTR),HL              ; Save the stream pointer while CTWRITE runs.
        LD (SCLEFT),BC             ; Save the remaining byte count.
SCSTRLP:
        LD BC,(SCLEFT)             ; Test for the end of this stream.
        LD A,B                     ; Combine both count bytes into one zero test.
        OR C                       ; A zero pair means every byte has been accepted.
        JR Z,SCSTRDN               ; Return after the final record has been flushed.
        LD HL,(SCPTR)              ; Load the next staged byte address.
        LD A,(HL)                  ; Pass that byte to the CP/M output adapter.
        INC HL                     ; Advance the saved pointer before the call.
        LD (SCPTR),HL              ; Preserve the advanced pointer.
        CALL CTWRITE               ; Write one byte through the private record cache.
        RET C                      ; A transport failure aborts publication.
        LD HL,(SCLEFT)             ; Reload the remaining count.
        DEC HL                     ; Account for the byte just written.
        LD (SCLEFT),HL             ; Publish the decremented stream count.
        JR SCSTRLP                 ; Stream the next byte.
SCSTRDN:
        XOR A                      ; Carry clear reports a complete stream.
        RET                        ; The caller closes the output FCB.

; Write the staged NOBJ and COM pair, then replace the previous final pair.
SCOUT:
        CALL SCNBS                 ; Build the temporary NOBJ FCB name.
        LD HL,SCFCB                ; Point CTOPENW at the temporary object.
        CALL CTOPENW               ; Create a fresh stage file.
        JP C,SCOUTER               ; Stop before any output is considered complete.
        LD HL,SCSTAGE              ; Stream from the serialized object base.
        LD BC,(SCOBJL)             ; Include the header, image, tail and CRC.
        CALL SCSTREAM              ; Write the complete NOBJ stream.
        JP C,SCOUTER               ; Close and abandon a failed stream.
        CALL CTCLOSEW              ; Flush and close the NOBJ stage.
        JP C,SCOUTER               ; A close failure leaves no valid stage.
        CALL SCCBS                 ; Build the temporary COM FCB name.
        LD HL,SCFCB                ; Point CTOPENW at the temporary COM.
        CALL CTOPENW               ; Create a fresh stage file.
        JP C,SCOUTER               ; Leave the completed NOBJ stage untouched.
        LD HL,SCIMG                ; COM contains the runtime image payload only.
        LD BC,(SCIMGL)             ; Stream exactly the runnable image bytes.
        CALL SCSTREAM              ; Write the COM stage.
        JP C,SCOUTER               ; Close and abandon a failed stream.
        CALL CTCLOSEW              ; Flush and close the COM stage.
        JP C,SCOUTER               ; A close failure prevents replacement.
        CALL SCNOB                 ; Build the final NOBJ destination FCB.
        LD HL,SCFCB                ; A final file may already exist from an earlier run.
        CALL CTDELETE              ; Remove it only after both stages are complete.
        JP C,SCOUTER               ; Preserve the old pair when deletion fails.
        CALL SCCOM                 ; Build the final COM destination FCB.
        LD HL,SCFCB                ; Remove the old COM before installing the stage.
        CALL CTDELETE               ; CP/M reports an absent file as success.
        JP C,SCOUTER               ; Preserve the staged NOBJ for recovery.
        CALL SCNBS                 ; Rebuild the NOBJ stage source FCB.
        CALL SCF2NOB               ; Build the final NOBJ destination in SCF2.
        LD HL,SCFCB                ; Rename the NOBJ stage into its final name.
        LD DE,SCF2                 ; SCF2 holds the matching final destination.
        CALL CTRENAME              ; Install the object before the COM stage.
        JP C,SCOUTER               ; No COM is installed when this rename fails.
        CALL SCCBS                 ; Rebuild the COM stage source FCB.
        CALL SCF2COM               ; Build the final COM destination in SCF2.
        LD HL,SCFCB                ; Rename the COM stage into its final name.
        LD DE,SCF2                 ; SCF2 holds the matching final destination.
        CALL CTRENAME              ; Complete the public output pair.
        JP C,SCROLL                ; Remove the newly installed object on failure.
        XOR A                      ; Both final files now name one committed image.
        RET                        ; Return success to SCMAIN.
SCOUTER:
        CALL CTCLOSEW              ; Close any open stage and flush no bad bytes.
        LD HL,SCOUTTXT             ; Distinguish a disk publication failure from source errors.
        LD (SCERRPTR),HL           ; The command driver prints this diagnostic.
        SCF                       ; Carry reports the publication failure.
        RET                        ; Staged names remain available for inspection.
SCROLL:
        CALL SCNOB                 ; Build the final NOBJ FCB for cleanup.
        LD HL,SCFCB                ; Point CTDELETE at the incomplete object.
        CALL CTDELETE              ; Remove the half-installed pair member.
        JP SCOUTER                 ; Report failure after best-effort cleanup.

; Copy the command basename into SCFCB, retaining drive and eight name bytes.
SCBASE:
        LD HL,005CH               ; CCP places the command-tail FCB here.
        LD DE,SCFCB               ; SCFCB owns the output basename.
        LD BC,9                   ; Copy drive and eight-character name fields.
        LDIR                       ; Preserve the selected source basename.
        RET                        ; Extension helpers fill bytes 9..11.

; Build a final NOBJ destination without changing the stage source FCB.
SCF2NOB:
        LD HL,005CH               ; CCP retains the selected command basename.
        LD DE,SCF2                ; SCF2 receives the final destination prefix.
        LD BC,9                   ; Copy drive and eight-character name fields.
        LDIR                       ; Preserve the source basename.
        LD HL,SCF2+9              ; Point at the destination extension.
        LD (HL),'N'                ; Use NOB for the public object.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'O'                ; Store the object marker.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'B'                ; Store the object suffix.
        RET                        ; CTRENAME accepts this concrete destination.

; Build a final COM destination without changing the stage source FCB.
SCF2COM:
        LD HL,005CH               ; CCP retains the selected command basename.
        LD DE,SCF2                ; SCF2 receives the final destination prefix.
        LD BC,9                   ; Copy drive and eight-character name fields.
        LDIR                       ; Preserve the source basename.
        LD HL,SCF2+9              ; Point at the destination extension.
        LD (HL),'C'                ; Use COM for the public program.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'O'                ; Store the program marker.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'M'                ; Store the program suffix.
        RET                        ; CTRENAME accepts this concrete destination.

SCNBS:
        CALL SCBASE                ; Start from the command basename.
        LD HL,SCFCB+9              ; Point at the temporary NOBJ extension.
        LD (HL),'N'                ; Use NBS for the private object stage.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'B'                ; Store the stage marker.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'S'                ; Store the stage suffix.
        RET                        ; Return with SCFCB ready for CTOPENW.

SCCBS:
        CALL SCBASE                ; Start from the command basename.
        LD HL,SCFCB+9              ; Point at the temporary COM extension.
        LD (HL),'C'                ; Use CBS for the private COM stage.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'B'                ; Store the stage marker.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'S'                ; Store the stage suffix.
        RET                        ; Return with SCFCB ready for CTOPENW.

SCNOB:
        CALL SCBASE                ; Start from the command basename.
        LD HL,SCFCB+9              ; Point at the final NOBJ extension.
        LD (HL),'N'                ; Use NOB for the public object.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'O'                ; Store the object marker.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'B'                ; Store the object suffix.
        RET                        ; Return with SCFCB ready for CTDELETE.

SCCOM:
        CALL SCBASE                ; Start from the command basename.
        LD HL,SCFCB+9              ; Point at the final COM extension.
        LD (HL),'C'                ; Use COM for the public program.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'O'                ; Store the program marker.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'M'                ; Store the program suffix.
        RET                        ; Return with SCFCB ready for CTDELETE.

; Static NOBJ prefix copied before the dynamic IMAGE record.
SCHEAD:
        DB $01,$09,$00,$4e,$4f,$42,$4a,$01,$00,$01,$00,$00,$03,$1b,$00,$01
        DB $00,$07,$7a,$38,$30,$2e,$63,$70,$75,$07,$63,$70,$6d,$2e,$72,$61
        DB $6d,$00,$01,$00,$e3,$00,$00,$00,$07,$00,$04,$19,$00,$01,$00,$01
        DB $07,$01,$00,$c2,$08,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$01
        DB $00,$00,$00,$00,$00,$00

; Six-byte IMAGE descriptor: load address, bank and relocation fields.
SCIMAGE:
        DB $01,$00,$00,$00,$00,$00

; Fixed tail: one symbol, one relocation and one commit record without CRC.
SCTAIL:
        DB $08,$0a,$00,$01,$00,$00,$01,$01,$00,$00,$00,$00,$00
        DB $0b,$04,$00,$00,$00,$01,$00
        DB $0c,$09,$00,$07,$00,$00,$00,$00,$01,$00

; Compiler publication state and private CP/M FCBs.
SCGBASE:  DW 0                   ; Staged address of global slot zero.
SCLBASE:  DW 0                   ; Staged address of local slot zero.
SCPBASE:  DW 0                   ; Staged address of procedure descriptor zero.
SCIMGL:   DW 0                   ; Runtime image payload length.
SCOBJL:   DW 0                   ; Complete serialized NOBJ length.
SCCRCL:   DW 0                   ; CRC input length excluding checksum bytes.
SCCRVAL:  DW 0                   ; Completed CRC-16 value.
SCTAILP:  DW 0                   ; Staged address of the fixed tail.
SCTARG:   DW 0                   ; Temporary absolute address for a patch.
SCPTR:    DW 0                   ; Stream or checksum input cursor.
SCLEFT:   DW 0                   ; Remaining stream or checksum byte count.
SCBITS:   DB 0                   ; CRC inner-loop bit count.
SCFIXC:   DW 0                   ; Remaining slot-fixup record count.
SCPDREM:  DB 0                   ; Descriptors still waiting for serialization.
SCPDIDX:  DB 0                   ; Descriptor index being serialized.
SCPDSLT: DB 0                  ; Formal slot fields left in one descriptor.
SCFCB:    DS 36                  ; Working stage or final output FCB.
SCF2:     DS 36                  ; Destination FCB used by CTRENAME.
