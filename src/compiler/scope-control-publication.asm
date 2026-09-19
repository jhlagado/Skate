;=============================================================================
;  Scope compiler final layout and CP/M publication
;=============================================================================
;
;  SCFIN closes the staged image, fixes every slot address, and serializes the
;  NOBJ records.  SCOUT writes the object and matching COM image to temporary
;  CP/M files before installing their final names.
;=============================================================================

; Append zeroed three-byte slots, resolve generated addresses, and build NOBJ.
SCFIN:
        LD HL,(SCPC)              ; Generated code ends at the current cursor.
        LD (SCGBASE),HL           ; Globals follow the generated instruction bytes.
        LD BC,(SCGCOUNT)          ; One three-byte record is reserved per global.
SCGDATA:
        LD A,B                     ; Test the high count byte first.
        OR C                       ; A zero pair means all global slots are present.
        JR Z,SCLDATA               ; Continue with local storage after the globals.
        XOR A                      ; Slot payload and initialized flag start at zero.
        LD (HL),A                  ; Store the payload low byte.
        INC HL                     ; Advance to the payload high byte.
        LD (HL),A                  ; Store the payload high byte.
        INC HL                     ; Advance to the initialized flag.
        LD (HL),A                  ; A zero flag makes an unresolved load fail.
        INC HL                     ; Advance to the following global slot.
        DEC BC                     ; Account for the slot just appended.
        JR SCGDATA                 ; Continue until the global count is exhausted.
SCLDATA:
        LD (SCLBASE),HL            ; Locals follow the complete global area.
        LD A,(SCLOCMAX)            ; The local high-water mark sets its extent.
        LD C,A                     ; Widen the byte count to a normal word.
        LD B,0                     ; Local slots also occupy three bytes each.
SCLOOP:
        LD A,B                     ; Test the high count byte first.
        OR C                       ; A zero pair means all local slots are present.
        JR Z,SCDATAOK              ; Continue with address fixups.
        XOR A                      ; Local slots start with zero payload and flag.
        LD (HL),A                  ; Store the payload low byte.
        INC HL                     ; Advance to the payload high byte.
        LD (HL),A                  ; Store the payload high byte.
        INC HL                     ; Advance to the initialized flag.
        LD (HL),A                  ; A zero flag protects an uninitialized local.
        INC HL                     ; Advance to the following local slot.
        DEC BC                     ; Account for the slot just appended.
        JR SCLOOP                  ; Continue until the local extent is filled.
SCDATAOK:
        LD (SCPC),HL               ; Publish the final staged image cursor.
        LD DE,SCIMG                ; The payload begins at the staged image base.
        OR A                       ; Clear carry before measuring the image.
        SBC HL,DE                  ; HL becomes runtime plus code plus slot data.
        LD (SCIMGL),HL             ; SCOUT streams this exact payload length.
        LD DE,SCEND                ; The staged compiler region has a fixed guard.
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
        RET                        ; Return with the runtime image ready.

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
        LD A,(SCFKIND)             ; Select the matching staged data region.
        OR A                       ; Zero selects the global base.
        JR Z,SCFGLOB               ; A local fixup uses the local base instead.
        LD DE,(SCLBASE)            ; Select the local data region.
        JR SCFADDR                 ; Both paths share the slot-offset arithmetic.
SCFGLOB:
        LD DE,(SCGBASE)            ; Select the global data region.
SCFADDR:
        LD A,(SCFSLOT)             ; The slot number is a three-byte index.
        CALL SCADDR                ; Return the absolute address of this slot.
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

; Convert a staged three-byte-slot address into its absolute COM address.
SCADDR:
        LD L,A                     ; Widen the slot index to a word.
        LD H,0                     ; The high byte is zero for all current slots.
        ADD HL,HL                  ; Form two times the slot number.
        LD B,H                     ; Keep the two-times value in BC.
        LD C,L                     ; The next addition forms three times the slot.
        LD L,A                     ; Restore the original slot index.
        LD H,0                     ; Clear the high byte before the third term.
        ADD HL,BC                  ; HL now equals three times the slot number.
        ADD HL,DE                  ; Add the selected staged data base.
        JP SCABS                   ; Convert the staged pointer to COM address.

; Serialize the fixed NOBJ prefix, dynamic image record, tail and CRC.
SCBUILD:
        LD HL,SCSTAGE              ; The object always begins at its staging base.
        LD DE,SCHEAD                ; Copy the measured 70-byte NOBJ prefix.
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
        LD DE,SCIMAGE               ; The six-byte descriptor follows the header.
        LD HL,SCSTAGE+73            ; Point at the descriptor destination.
        LD BC,6                     ; The descriptor is six bytes long.
        LDIR                       ; Copy the descriptor before the image payload.
        LD HL,SCIMG                 ; The payload already contains the runtime image.
        LD DE,(SCIMGL)              ; Skip the complete runtime and generated image.
        ADD HL,DE                  ; HL now points at the first tail record.
        LD (SCTAILP),HL             ; Preserve the tail address for CRC and length.
        LD DE,SCTAIL                ; Copy the fixed symbol/relocation/commit tail.
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
SCFCB:    DS 36                  ; Working stage or final output FCB.
SCF2:     DS 36                  ; Destination FCB used by CTRENAME.
