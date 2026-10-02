; Native lexer control, lookahead, positions and token buffering.
; Entry points: LEXINIT, LEXNEXT, LEXPEEK, LEXTAKE and LEXTEXT.
LEXINIT:  LD (LCALLADR),HL   ; Retain the byte-source entry address.
        LD HL,LEXSTATE    ; Reset state without erasing the callback pointer.
        LD DE,LEXSTATE+1   ; The zero copy trails its source by one byte.
        LD BC,280       ; 281 state/buffer bytes, including the initial zero.
        LD (HL),0        ; Seed the overlapping copy with a zero.
        LDIR            ; Clear buffer and cursor fields for a fresh source.
        LD HL,1          ; Reset both one-based coordinates.
        LD (LLINENO),HL   ; Lines and columns start at one; offsets at zero.
        LD (LCOLUMN),HL     ; The first source byte occupies column one.
        XOR A            ; Initialization succeeds with A=0 and carry clear.
        RET              ; Return to the caller without reading the source.
LEXNEXT:  LD A,(LSTATUS)   ; A prior error/EOF never consumes another byte.
        OR A             ; Zero means the source is still active.
        JP NZ,LEXSTICK     ; Replay the previous terminal result if one exists.
        LD (LEXENTRY),SP  ; Error exits unwind private calls to this boundary.
LEXSKIP:  CALL LEXPEEK      ; One-byte lookahead owns callback clobbers.
        JR C,LEXEOF        ; A source with no next byte is complete.
        CALL LEXWHITE      ; Test the peeked byte without consuming it.
        JR Z,LEXWSKIP      ; Whitespace has no token of its own.
        CP 59           ; Semicolon starts a comment outside literals.
        JR Z,LCOMMENT    ; Discard a semicolon comment before selecting a token.
        CALL LSETLOC    ; Freeze the first byte of this token.
        XOR A            ; Reset the byte count for the new token.
        LD (LBUFLEN),A     ; Every token starts an empty byte buffer.
        CALL LEXTAKE       ; Consume the first byte whose position was just saved.
        CP 40            ; Opening parenthesis has structural kind 1.
        LD B,1           ; Prepare the result without disturbing the comparison flags.
        JR Z,LSIMPLE     ; Return the selected punctuation kind on equality.
        CP 41            ; Closing parenthesis has structural kind 2.
        LD B,2           ; Keep the CP result while selecting the closing kind.
        JR Z,LSIMPLE     ; Return the selected punctuation kind on equality.
        CP 39            ; Apostrophe is a quote-prefix token.
        LD B,3           ; Keep the CP result while selecting the quote kind.
        JR Z,LSIMPLE     ; Return the selected punctuation kind on equality.
        CP 34            ; A double quote begins decoded string contents.
        JP Z,LSTRING     ; String handling consumes its own closing quote.
        CP 35            ; Hash syntax introduces booleans and characters.
        JP Z,LEXHASH       ; Dispatch the byte immediately after the hash.
        CALL LEXCTRL     ; Source controls cannot begin an ordinary token.
        CALL LAPPEND     ; Save the first ordinary token byte.
LEXTOKEN: CALL LEXPEEK       ; Keep the terminator available to the next token request.
        JP C,LEXCLASS      ; EOF terminates an otherwise complete token.
        CALL LEXDELIM      ; Check whether the peeked byte belongs to the next token.
        JP Z,LEXCLASS      ; Classify the accumulated spelling before consuming a delimiter.
        LD A,(LBUFLEN)     ; Read the buffered byte count.
        CP 64            ; All ordinary token spellings fit the numeric-token buffer limit.
        JP Z,LEXCAP       ; Capacity is exhausted before the next buffer write.
        CALL LEXTAKE       ; Consume a nondelimiter already known to fit.
        CALL LEXCTRL     ; Control bytes are invalid anywhere in a token.
        CALL LAPPEND     ; Append this raw token byte.
        JR LEXTOKEN        ; Continue until a delimiter or EOF.
; Reject a control byte or DEL in A as malformed source; otherwise return.
LEXCTRL: CP 32           ; Bytes below space are controls.
        JP C,LSYNTAX     ; The error unwinds to LEXNEXT's caller.
        CP 127           ; DEL is a control byte even though it is ASCII.
        RET NZ           ; A printable byte is accepted unchanged.
        JP LSYNTAX       ; Reject DEL outside a supported escape.
; Consume whitespace and retry at the next source byte.
LEXWSKIP: CALL LEXTAKE
        JR LEXSKIP         ; Recheck EOF and comments after consuming whitespace.
; Skip bytes until a line boundary; the whitespace path consumes it.
LCOMMENT:
        CALL LEXTAKE      ; Comments may end with CR, LF, or source EOF.
        CALL LEXPEEK       ; Inspect the byte following the one just discarded.
        JR C,LEXEOF        ; An unterminated final comment is valid at EOF.
        CP 13            ; CR ends the comment before line accounting.
        JR Z,LEXSKIP       ; Let the whitespace path consume this line terminator.
        CP 10            ; LF also ends a comment.
        JR Z,LEXSKIP       ; Let the whitespace path consume this line terminator.
        JR LCOMMENT      ; The next byte still belongs to the comment.
LSIMPLE:
        LD A,B          ; Structural tokens need no text payload.
        OR A             ; Test whether any token bytes remain unconsumed.
        RET              ; Return the selected kind; payload registers are unspecified.
LEXEOF:   CALL LSETLOC    ; EOF diagnostics refer to the cursor after whitespace.
        LD A,1           ; Internal status one is distinct from public EOF kind zero.
        LD (LSTATUS),A  ; Status one represents successful terminal EOF.
        XOR A            ; Return public EOF with carry clear.
        RET              ; Further calls replay EOF without invoking the source.
LEXSTICK: CP 1
        JR Z,LEXREOF       ; Translate cached EOF to its public success result.
        SCF              ; All other cached terminal values are error codes.
        RET              ; Return the original error, without changing its location.
LEXREOF:  XOR A
        RET              ; Successful EOF remains repeatable.

; Lookahead keeps registers private even when the source destroys them.
LEXPEEK:  LD A,(LEXHAVE)
        OR A             ; A nonzero lookahead state already owns a byte or EOF.
        JR NZ,LEXCACHE       ; Avoid another source call for buffered input.
        PUSH BC          ; Protect the caller count from callback clobbers.
        PUSH DE          ; Protect the caller address from callback clobbers.
        PUSH HL          ; Protect the caller cursor from callback clobbers.
        LD HL,(LCALLADR)   ; Fetch the caller-selected source entry point.
        CALL LEXCALL      ; Use an indirect jump with an ordinary callback return word.
        JR C,LSRCEOF     ; Only carry, not the returned byte, indicates source EOF.
        CP 128           ; The production source alphabet is seven-bit ASCII.
        JP NC,LEXENC       ; High-bit bytes are encoding errors at the current cursor.
        LD (LEXLOOK),A    ; Retain the cached byte.
        LD A,1           ; Mark the lookahead as a real byte.
LSETHAVE:
        LD (LEXHAVE),A    ; Publish byte/EOF state before restoring the callback frame.
        POP HL           ; Restore the caller cursor after the source returns.
        POP DE           ; Restore the caller address.
        POP BC           ; Restore the caller count.
; Recover either the cached source byte or cached end-of-input marker.
LEXCACHE:   CP 2            ; Have=2 is buffered EOF; no repeated callback.
        SCF              ; Prepare the cached-EOF result without changing Z.
        RET Z            ; State two has no byte to return.
        LD A,(LEXLOOK)    ; Read the cached byte.
        OR A             ; A cached byte is successful even when its value is zero.
        RET              ; Return the byte without advancing source coordinates.
; Cache EOF while restoring registers saved around the callback.
LSRCEOF:
        LD A,2           ; The shared cache return recognizes state two as EOF.
        JR LSETHAVE      ; Restore the same save frame, then return carry set.
LEXCALL: JP (HL)         ; CALL above supplies callback's return address.
; Consume one cached byte and advance the checked source coordinates.
LEXTAKE:  CALL LEXPEEK
        RET C            ; EOF changes neither coordinates nor lookahead.
        PUSH AF          ; Keep that byte available until the public take result.
        LD HL,(LOFFSET)     ; Load the count of bytes consumed so far.
        INC HL           ; Compute the next byte offset using word arithmetic.
        LD A,H           ; Test both halves because INC HL does not set Z.
        OR L             ; A zero result identifies the forbidden 65535-to-zero wrap.
        JP Z,LPOSERR     ; Reject source coordinates that cannot be represented.
        LD (LOFFSET),HL     ; Publish the checked consumed-byte offset.
        POP AF           ; Recover the consumed byte for newline classification.
        PUSH AF          ; Keep that byte available until the public take result.
        CP 13            ; CR advances the line and starts possible CRLF coalescing.
        JR Z,LCRBYTE     ; Handle the first half of a CRLF like any CR.
        CP 10            ; LF may be standalone or follow CR.
        JR Z,LLFBYTE     ; Use the previous-byte state to decide its line effect.
        LD HL,(LCOLUMN)     ; Ordinary bytes advance only the column.
        INC HL           ; Compute the next column using checked word arithmetic.
        LD A,H           ; Test both halves because INC HL does not set Z.
        OR L             ; A zero result identifies the forbidden 65535-to-zero wrap.
        JP Z,LPOSERR     ; Reject source coordinates that cannot be represented.
        LD (LCOLUMN),HL     ; Publish the nonwrapping column.
        XOR A            ; An ordinary byte breaks a possible CRLF pair.
        LD (LCRFLAG),A       ; The previous consumed byte is no longer CR.
        JR LTAKEND       ; Finish without resetting the column.
; Suppress a second line advance when LF immediately follows CR.
LLFBYTE:
        LD A,(LCRFLAG)       ; Check whether the preceding consumed byte was CR.
        OR A             ; Zero means this LF must advance the line itself.
        JR NZ,LRESETC  ; The LF half of CRLF does not advance the line.
; Advance the line before resetting the one-based column.
LCRBYTE:
        LD HL,(LLINENO)    ; Load the current one-based line number.
        INC HL           ; Compute the next line before publishing it.
        LD A,H           ; Word increments require an explicit zero test.
        OR L             ; Detect line-number wrap without relying on INC flags.
        JP Z,LPOSERR     ; A 65536th line cannot fit the target position contract.
        LD (LLINENO),HL    ; Publish the checked next line.
; A line boundary always restores column one.
LRESETC:
        LD HL,1          ; Line starts always use column one.
        LD (LCOLUMN),HL     ; Discard the preceding line column.
        POP AF           ; Recover whether the actual consumed byte was CR or LF.
        PUSH AF          ; Keep the source byte as the eventual take result.
        CP 13            ; Only CR can suppress a following LF line increment.
        LD A,0           ; Prepare false while preserving CP equality.
        JR NZ,LEXSETCR     ; LF leaves the previous-CR flag clear.
        INC A            ; CR leaves the previous-CR flag set.
; Remember CR only, so an immediately following LF can be coalesced.
LEXSETCR: LD (LCRFLAG),A
; Publish consumed lookahead while returning its original byte.
LTAKEND:
        XOR A            ; Mark the consumed lookahead slot empty.
        LD (LEXHAVE),A   ; The buffered byte has now been consumed.
        POP AF           ; Restore the original source byte.
        OR A             ; Return that byte with carry clear.
        RET              ; The caller can now request the following byte.
; Return Z for the four permitted whitespace bytes; retain A.
LEXWHITE: CP 32            ; Recognize ASCII space.
        RET Z            ; Return immediately on this recognized delimiter.
        CP 9             ; Recognize horizontal tab.
        RET Z            ; Return immediately on this recognized delimiter.
        CP 10            ; Recognize line feed.
        RET Z            ; Return immediately on this recognized delimiter.
        CP 13            ; Recognize carriage return.
        RET              ; Return the final comparison result without altering A.
; Return Z for whitespace or a token-separating punctuation byte.
LEXDELIM: CALL LEXWHITE
        RET Z            ; Return immediately on this recognized delimiter.
        CP 40            ; An opening parenthesis ends an ordinary token.
        RET Z            ; Return immediately on this recognized delimiter.
        CP 41            ; A closing parenthesis ends an ordinary token.
        RET Z            ; Return immediately on this recognized delimiter.
        CP 39            ; An apostrophe starts the next quoted datum.
        RET Z            ; Return immediately on this recognized delimiter.
        CP 34            ; A double quote begins a separate string token.
        RET Z            ; Return immediately on this recognized delimiter.
        CP 59            ; A semicolon begins a comment after this token.
        RET              ; Return the final comparison result without altering A.
LAPPEND:
        PUSH AF         ; Buffer index is the decoded byte count.
        LD A,(LBUFLEN)     ; Read the buffered byte count.
        LD L,A           ; Use the byte count as the buffer offset.
        LD H,0           ; Zero-extend that offset to a word.
        LD DE,LBUFFER    ; Locate this lexer instance's fixed token buffer.
        ADD HL,DE        ; HL now addresses the next unused buffer byte.
        POP AF           ; Restore the source or decoded byte to be stored.
        LD (HL),A        ; The caller checked capacity before this write.
        LD HL,LBUFLEN       ; Update the count, not the buffer cursor.
        INC (HL)         ; One more byte is now owned by the current token.
        RET              ; A remains the appended byte for delimiter checks.
; Expose the current buffer and its byte count without a terminator.
LEXTEXT:  LD HL,LBUFFER
        LD BC,0          ; Text lengths are returned as zero-extended words.
        LD A,(LBUFLEN)     ; Read the buffered byte count.
        LD C,A           ; The low byte carries the complete 0..255 length.
        LD A,(LTOKIND)    ; Read the text token kind.
        OR A             ; Successful text results always clear carry.
        RET              ; The buffer remains valid until the next lexer call.
