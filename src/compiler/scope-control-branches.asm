; Scope and control branch patching.
; This file contains parser-side branch address resolution.

SCEXPECT:
        CALL RNEXT                 ; The enclosing form must close now.
        RET C                      ; Preserve a source read failure.
        CP 2                       ; Event kind two is a closing parenthesis.
        JP NZ,SCEXPSYN              ; Reject a missing or overlong form.
        XOR A                      ; Carry clear reports a complete form.
        RET                        ; Return to the caller with its value intact.

SCEXPSYN:
        LD HL,SCEXPTXT
        LD (SCERRPTR),HL
        JP SCSYN

; Compare the current lexer spelling with a length-prefixed static name.
SCMATCH:
        LD A,(LBUFLEN)             ; Read the current symbol's byte count.
        LD B,A                     ; B counts the bytes to compare.
        LD A,(DE)                  ; The static name stores its length first.
        CP B                       ; A different length cannot match.
        JR NZ,SCMNO                ; A different length cannot match.
        INC DE                     ; Advance to the first static name byte.
        LD HL,LBUFFER              ; The lexer buffer holds the current spelling.
        LD A,B                     ; Recover the equal byte count.
        OR A                       ; An empty name is not produced for symbols.
        JR Z,SCMYES                ; Keep the comparison total for completeness.
SCMLOOP:
        LD A,(DE)                  ; Read one expected name byte.
        CP (HL)                    ; Compare it with the authored spelling.
        JR NZ,SCMNO                ; A mismatch selects the next form candidate.
        INC DE                     ; Advance the expected-name cursor.
        INC HL                     ; Advance the lexer-buffer cursor.
        DJNZ SCMLOOP               ; Continue until all bytes have matched.
SCMYES:
        XOR A                      ; Return Z with carry clear for a match.
        RET                        ; The caller selects the matching form.
SCMNO:
        LD A,1                     ; Return NZ with carry clear for a mismatch.
        OR A                       ; Set the mismatch flags without carry.
        RET                        ; The caller tries another static spelling.

; Convert a staged image pointer in HL to its absolute address in the COM.
SCABS:
        LD DE,SCIMG                ; The first staged payload byte executes at $0100.
        OR A                       ; Clear carry before the pointer subtraction.
        SBC HL,DE                  ; Compute the output-image offset.
        LD DE,0100H               ; Add the CP/M program load origin.
        ADD HL,DE                  ; HL now holds the executable absolute address.
        RET                        ; Return with the converted target address.

; Save one short-circuit branch patch address in the generic branch stack.
SCBRPUSH:
        LD (SCBPTMP),HL            ; Preserve the staged patch address while indexing.
        LD A,(SCBRTOP)             ; The byte-sized branch stack is bounded.
        CP 64                      ; Nested forms consume at most 64 entries.
        JP NC,SCCAP                ; Reject a source nesting depth beyond the bound.
        LD L,A                     ; Widen the record index to a word.
        LD H,0                     ; Each branch record is one word.
        ADD HL,HL                 ; Multiply the index by two bytes.
        LD DE,SCBRANCH             ; Locate the next free branch record.
        ADD HL,DE                 ; HL points at its staged patch word.
        LD DE,(SCBPTMP)            ; Recover the saved branch address.
        LD (HL),E                 ; Store the low staged address byte.
        INC HL                    ; Advance to the high address byte.
        LD (HL),D                 ; Store the high staged address byte.
        LD A,(SCBRTOP)             ; Advance the generic branch stack top.
        INC A                     ; One conditional jump is now pending.
        LD (SCBRTOP),A            ; Publish the pending branch record.
        RET                        ; Return with carry clear.

; Patch and pop the most recent generic conditional branch to absolute HL.
SCBRPAT:
        LD (SCBTARG),HL            ; Preserve the target while locating the patch.
        LD A,(SCBRTOP)             ; A zero top would indicate an internal error.
        OR A                       ; Test for a matching pending branch.
        JP Z,SCFIXERR              ; The emitter's own fixup error is terminal.
        DEC A                     ; Select the final pending branch record.
        LD (SCBRTOP),A            ; Release it only after the patch address is read.
        LD L,A                    ; Widen the record index.
        LD H,0                    ; Each branch record occupies two bytes.
        ADD HL,HL                 ; Multiply by two.
        LD DE,SCBRANCH             ; Locate the selected branch record.
        ADD HL,DE                 ; HL points at its staged patch address.
        LD E,(HL)                 ; Read the patch address low byte.
        INC HL                    ; Advance to the high address byte.
        LD D,(HL)                 ; DE now identifies the staged patch word.
        EX DE,HL                  ; HL=patch address, DE=temporary old value.
        LD DE,(SCBTARG)            ; Restore the requested absolute target.
        JP SCPATCH                 ; Write both target bytes and return.

; Save an if false-branch patch address at the current if depth.
SCIFPUSH:
        LD (SCBPTMP),HL            ; Preserve the staged false patch address.
        LD A,(SCIFTOP)             ; The if stack is bounded by reader nesting.
        CP 32                      ; Two words per form fit in the reserved area.
        JP NC,SCCAP                ; Reject a nesting depth without a safe patch.
        LD L,A                     ; Widen the form index.
        LD H,0                     ; Each false stack record occupies two bytes.
        ADD HL,HL                 ; Multiply by two.
        LD DE,SCIFALSE             ; Locate this form's false patch record.
        ADD HL,DE                 ; HL points at the staged patch word.
        LD DE,(SCBPTMP)            ; Recover the saved false patch address.
        LD (HL),E                 ; Store its low byte.
        INC HL                    ; Advance to the high patch-address byte.
        LD (HL),D                 ; Store its high byte.
        LD A,(SCIFTOP)             ; Advance the if-depth cursor.
        INC A                     ; One more nested if is now active.
        LD (SCIFTOP),A            ; Publish the new depth.
        RET                        ; Return with carry clear.

; Save an if end-jump patch address for the current form.
SCIFENDP:
        LD (SCBPTMP),HL            ; Preserve the staged end-jump patch address.
        LD A,(SCIFTOP)             ; At least the current if record must exist.
        OR A                       ; A zero depth is an internal compiler error.
        JP Z,SCFIXERR              ; Reuse the terminal fixup diagnostic.
        DEC A                     ; Address the current record below the top.
        LD L,A                     ; Widen the form index.
        LD H,0                     ; Each end record occupies two bytes.
        ADD HL,HL                 ; Multiply the index by two.
        LD DE,SCIFEND              ; Locate the current end patch record.
        ADD HL,DE                 ; HL points at the staged patch word.
        LD DE,(SCBPTMP)            ; Recover the saved end-jump address.
        LD (HL),E                 ; Store its low byte.
        INC HL                    ; Advance to the high patch-address byte.
        LD (HL),D                 ; Store its high byte.
        RET                        ; Return with carry clear.

; Patch the current if false jump to the absolute address in HL.
SCIFPATF:
        JP SCIFPAT               ; The false and end paths share address math.

; Patch the current if end jump to the absolute address in HL.
SCIFPATE:
        LD (SCBTARG),HL            ; Keep the requested target across table access.
        LD A,(SCIFTOP)             ; A zero depth is an internal compiler error.
        OR A                       ; Test that a matching if record exists.
        JP Z,SCFIXERR              ; Do not write through an invalid address.
        DEC A                     ; Select the current record.
        LD L,A                     ; Widen the record index.
        LD H,0                     ; Each end record occupies two bytes.
        ADD HL,HL                 ; Multiply by two.
        LD DE,SCIFEND              ; Locate the current end patch.
        ADD HL,DE                 ; HL points at its staged address word.
        LD E,(HL)                 ; Read the staged address low byte.
        INC HL                    ; Advance to the high address byte.
        LD D,(HL)                 ; DE now identifies the staged patch word.
        EX DE,HL                  ; HL=patch, DE=temporary old value.
        LD DE,(SCBTARG)            ; Restore the requested absolute target.
        JP SCPATCH                 ; Write both target bytes and return.

; False and end if records use the same table arithmetic.
SCIFPAT:
        LD (SCBTARG),HL            ; Preserve the target while reading the record.
        LD A,(SCIFTOP)             ; A zero depth is an internal compiler error.
        OR A                       ; Test that the current if exists.
        JP Z,SCFIXERR              ; Do not write through an invalid address.
        DEC A                     ; Select the current false record.
        LD L,A                     ; Widen the form index.
        LD H,0                     ; Each false record occupies two bytes.
        ADD HL,HL                 ; Multiply the index by two.
        LD DE,SCIFALSE             ; Locate the current false patch.
        ADD HL,DE                 ; HL points at its staged address word.
        LD E,(HL)                 ; Read the staged address low byte.
        INC HL                    ; Advance to the high address byte.
        LD D,(HL)                 ; DE now identifies the staged patch word.
        EX DE,HL                  ; HL=patch, DE=temporary old value.
        LD DE,(SCBTARG)            ; Restore the requested absolute target.
        JP SCPATCH                 ; Write both target bytes and return.

; Release the current if patch record after both branch targets are fixed.
SCIFPOP:
        LD A,(SCIFTOP)             ; The current form must still be on the stack.
        DEC A                      ; Release its false/end patch pair.
        LD (SCIFTOP),A             ; Publish the enclosing form's depth.
        XOR A                      ; Return carry clear to the expression parser.
        RET                        ; The selected branch value remains in A/HL.
