; Scope and control branch patching.
; This file contains parser-side branch address resolution.

CMD_END:
        CALL REC_NEXT              ; The enclosing form must close now.
        RET C                      ; Preserve a source read failure.
        CP 2                       ; Event kind two is a closing parenthesis.
        JP NZ,.BAD                  ; Reject a missing or overlong form.
        XOR A                      ; Carry clear reports a complete form.
        RET                        ; Return to the caller with its value intact.

.BAD:
        LD HL,M_EXPECT
        LD (ST_ERROR),HL
        JP ERR_BAD

; Compare the current lexer spelling with a length-prefixed static name.
CMD_SAME:
        LD A,(LX_LEN)              ; Read the current symbol's byte count.
        LD B,A                     ; B counts the bytes to compare.
        LD A,(DE)                  ; The static name stores its length first.
        CP B                       ; A different length cannot match.
        JR NZ,.NO                  ; A different length cannot match.
        INC DE                     ; Advance to the first static name byte.
        LD HL,LX_BUF               ; The lexer buffer holds the current spelling.
        LD A,B                     ; Recover the equal byte count.
        OR A                       ; An empty name is not produced for symbols.
        JR Z,.YES                  ; Keep the comparison total for completeness.
.LOOP:
        LD A,(DE)                  ; Read one expected name byte.
        CP (HL)                    ; Compare it with the authored spelling.
        JR NZ,.NO                  ; A mismatch selects the next form candidate.
        INC DE                     ; Advance the expected-name cursor.
        INC HL                     ; Advance the lexer-buffer cursor.
        DJNZ .LOOP                 ; Continue until all bytes have matched.
.YES:
        XOR A                      ; Return Z with carry clear for a match.
        RET                        ; The caller selects the matching form.
.NO:
        LD A,1                     ; Return NZ with carry clear for a mismatch.
        OR A                       ; Set the mismatch flags without carry.
        RET                        ; The caller tries another static spelling.

; Generated cursors are already logical COM addresses.  Keep this helper for
; the callers that still express the conversion explicitly.
BR_ABS:
        RET                        ; HL already holds the logical COM address.

; Save one short-circuit branch patch address in the generic branch stack.
BR_PUSH:
        LD (ST_PATCH),HL           ; Preserve the staged patch address while indexing.
        LD A,(ST_BRTOP)            ; The byte-sized branch stack is bounded.
        CP 128                     ; W_BRANCH holds 128 words.
        JP NC,ERR_CAP              ; Reject a source nesting depth beyond the bound.
        LD L,A                     ; Widen the record index to a word.
        LD H,0                     ; Each branch record is one word.
        ADD HL,HL                 ; Multiply the index by two bytes.
        LD DE,W_BRANCH             ; Locate the next free branch record.
        ADD HL,DE                 ; HL points at its staged patch word.
        LD DE,(ST_PATCH)           ; Recover the saved branch address.
        LD (HL),E                 ; Store the low staged address byte.
        INC HL                    ; Advance to the high address byte.
        LD (HL),D                 ; Store the high staged address byte.
        LD A,(ST_BRTOP)            ; Advance the generic branch stack top.
        INC A                     ; One conditional jump is now pending.
        LD (ST_BRTOP),A           ; Publish the pending branch record.
        RET                        ; Return with carry clear.

; Patch and pop the most recent generic conditional branch to absolute HL.
BR_PATCH:
        LD (ST_DEST),HL            ; Preserve the target while locating the patch.
        LD A,(ST_BRTOP)            ; A zero top would indicate an internal error.
        OR A                       ; Test for a matching pending branch.
        JP Z,EM_FAIL               ; The emitter's own fixup error is terminal.
        DEC A                     ; Select the final pending branch record.
        LD (ST_BRTOP),A           ; Release it only after the patch address is read.
        LD L,A                    ; Widen the record index.
        LD H,0                    ; Each branch record occupies two bytes.
        ADD HL,HL                 ; Multiply by two.
        LD DE,W_BRANCH             ; Locate the selected branch record.
        ADD HL,DE                 ; HL points at its staged patch address.
        LD E,(HL)                 ; Read the patch address low byte.
        INC HL                    ; Advance to the high address byte.
        LD D,(HL)                 ; DE now identifies the staged patch word.
        EX DE,HL                  ; HL=patch address, DE=temporary old value.
        LD DE,(ST_DEST)            ; Restore the requested absolute target.
        JP SINK_FIX                ; Write both target bytes and return.

; Save an if false-branch patch address at the current if depth.
BR_IFNEW:
        LD (ST_PATCH),HL           ; Preserve the staged false patch address.
        LD A,(ST_IFTOP)            ; The if stack is bounded by reader nesting.
        CP 64                      ; W_IFALSE and W_IFEND hold 64 words each.
        JP NC,ERR_CAP              ; Reject a nesting depth without a safe patch.
        LD L,A                     ; Widen the form index.
        LD H,0                     ; Each false stack record occupies two bytes.
        ADD HL,HL                 ; Multiply by two.
        LD DE,W_IFALSE             ; Locate this form's false patch record.
        ADD HL,DE                 ; HL points at the staged patch word.
        LD DE,(ST_PATCH)           ; Recover the saved false patch address.
        LD (HL),E                 ; Store its low byte.
        INC HL                    ; Advance to the high patch-address byte.
        LD (HL),D                 ; Store its high byte.
        LD A,(ST_IFTOP)            ; Advance the if-depth cursor.
        INC A                     ; One more nested if is now active.
        LD (ST_IFTOP),A           ; Publish the new depth.
        RET                        ; Return with carry clear.

; Save an if end-jump patch address for the current form.
BR_IFEND:
        LD (ST_PATCH),HL           ; Preserve the staged end-jump patch address.
        LD A,(ST_IFTOP)            ; At least the current if record must exist.
        OR A                       ; A zero depth is an internal compiler error.
        JP Z,EM_FAIL               ; Reuse the terminal fixup diagnostic.
        DEC A                     ; Address the current record below the top.
        LD L,A                     ; Widen the form index.
        LD H,0                     ; Each end record occupies two bytes.
        ADD HL,HL                 ; Multiply the index by two.
        LD DE,W_IFEND              ; Locate the current end patch record.
        ADD HL,DE                 ; HL points at the staged patch word.
        LD DE,(ST_PATCH)           ; Recover the saved end-jump address.
        LD (HL),E                 ; Store its low byte.
        INC HL                    ; Advance to the high patch-address byte.
        LD (HL),D                 ; Store its high byte.
        RET                        ; Return with carry clear.

; Patch the current if false jump to the absolute address in HL.
BR_ELSE:
        JP BR_FALSE              ; The false and end paths share address math.

; Patch the current if end jump to the absolute address in HL.
BR_JOIN:
        LD (ST_DEST),HL            ; Keep the requested target across table access.
        LD A,(ST_IFTOP)            ; A zero depth is an internal compiler error.
        OR A                       ; Test that a matching if record exists.
        JP Z,EM_FAIL               ; Do not write through an invalid address.
        DEC A                     ; Select the current record.
        LD L,A                     ; Widen the record index.
        LD H,0                     ; Each end record occupies two bytes.
        ADD HL,HL                 ; Multiply by two.
        LD DE,W_IFEND              ; Locate the current end patch.
        ADD HL,DE                 ; HL points at its staged address word.
        LD E,(HL)                 ; Read the staged address low byte.
        INC HL                    ; Advance to the high address byte.
        LD D,(HL)                 ; DE now identifies the staged patch word.
        EX DE,HL                  ; HL=patch, DE=temporary old value.
        LD DE,(ST_DEST)            ; Restore the requested absolute target.
        JP SINK_FIX                ; Write both target bytes and return.

; False and end if records use the same table arithmetic.
BR_FALSE:
        LD (ST_DEST),HL            ; Preserve the target while reading the record.
        LD A,(ST_IFTOP)            ; A zero depth is an internal compiler error.
        OR A                       ; Test that the current if exists.
        JP Z,EM_FAIL               ; Do not write through an invalid address.
        DEC A                     ; Select the current false record.
        LD L,A                     ; Widen the form index.
        LD H,0                     ; Each false record occupies two bytes.
        ADD HL,HL                 ; Multiply the index by two.
        LD DE,W_IFALSE             ; Locate the current false patch.
        ADD HL,DE                 ; HL points at its staged address word.
        LD E,(HL)                 ; Read the staged address low byte.
        INC HL                    ; Advance to the high address byte.
        LD D,(HL)                 ; DE now identifies the staged patch word.
        EX DE,HL                  ; HL=patch, DE=temporary old value.
        LD DE,(ST_DEST)            ; Restore the requested absolute target.
        JP SINK_FIX                ; Write both target bytes and return.

; Release the current if patch record after both branch targets are fixed.
BR_IFPOP:
        LD A,(ST_IFTOP)            ; The current form must still be on the stack.
        DEC A                      ; Release its false/end patch pair.
        LD (ST_IFTOP),A            ; Publish the enclosing form's depth.
        XOR A                      ; Return carry clear to the expression parser.
        RET                        ; The selected branch value remains in A/HL.
