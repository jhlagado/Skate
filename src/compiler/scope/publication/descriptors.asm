; Scope publication of procedure descriptors and slot addresses.
; Entry points: SCPDESC, SCPDWRD, SCADDR and SCFQCH.
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
        CALL SINKBYTE                ; Use the normal guarded image writer.
        RET C
        LD A,(SCLOCMAX)            ; Every environment has the bounded slot extent.
        CALL SINKBYTE
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
        LD (SCBTMP),A              ; Keep the low byte while reading its high byte.
        LD A,(HL)                  ; Fixed records keep this byte zero.
        LD (SCPHIGH),A             ; A rest record uses it for the list slot.
        LD A,(SCBTMP)              ; Restore the slot low byte for publication.
        INC HL                     ; Advance beyond the two-byte metadata field.
        LD (SCPTR),HL
        CALL SINKBYTE                ; Write the formal slot index low byte.
        RET C
        LD A,(SCPHIGH)             ; Publish the rest slot in its reserved high byte.
        CALL SINKBYTE
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
        CALL SINKBYTE
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
        CALL SINKBYTE
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
        CALL SINKBYTE
        RET C
        LD HL,(SCTARG)
        LD A,H
        JP SINKBYTE

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
