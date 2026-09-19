;=============================================================================
;  Native pull lexer
;=============================================================================

;  PURPOSE
;  -------
;  Return one token at a time from a callback-backed byte source.

;  PUBLIC INTERFACE
;  ----------------
;

;+---------------------------------------------------------------------------+
;|  LEXINIT - Initialize the source callback and lexer state.                  |
;|                                                                           |
;|  CALL                                                                     |
;|    HL -> byte-source callback address.                                    |
;|                                                                           |
;|  SUCCESS                                                                  |
;|    A = 0; carry clear. No source byte is read.                            |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  LEXNEXT - Return a token or replay EOF/error.                              |
;|                                                                           |
;|  SUCCESS                                                                  |
;|    A = token kind; carry clear.                                           |
;|    Text: HL = LBUFFER; BC = byte length.                                  |
;|    Scalar: HL = payload.                                                  |
;|                                                                           |
;|  FAILURE                                                                  |
;|    A = lexer error code; carry set.                                       |
;+---------------------------------------------------------------------------+

;  CALLBACK CONTRACT
;  -----------------
;
;  RETURNS    A = ASCII byte; carry clear. Carry set means EOF.
;  CLOBBERS   BC, DE and HL may change.
;  PRESERVES  IX and IY; SP is balanced.
;  SOURCE     Every source read passes through this callback.

;  TOKEN KINDS
;  -----------
;
;  0  EOF
;  1  open parenthesis
;  2  close parenthesis
;  3  quote
;  4  dot
;  5  symbol
;  6  numeric text
;  7  scalar
;  8  string

;  ERROR CODES
;  -----------
;
;  128  syntax
;  129  capacity
;  130  encoding
;  131  position overflow

;  BUFFER LIFETIME
;  ---------------
;
;  Text tokens borrow LBUFFER until the next LEXNEXT call.
;  Scalar HL holds the payload, not a buffer address.
;  Numeric grammar is validated; decimal conversion is separate.

;  STATE AND OWNERSHIP
;  -------------------
;
;  EOF and errors are sticky until LEXINIT.
;  Current and token-start offsets, lines and columns are unsigned words.
;  None of these coordinates wrap.
;
;  IX and IY are preserved; static state makes the module non-reentrant.
;  Keep callback, source, stack and LEXWORK..LEXWEND disjoint.
;=============================================================================

LEXINIT:  LD (LCALLADR),HL   ; Retain the byte-source entry address.
        LD HL,LEXSTATE    ; Reset state without erasing the callback pointer.
        LD DE,LEXSTATE+1   ; The zero copy trails its source by one byte.
        LD BC,278       ; 279 state/buffer bytes, including the initial zero.
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
        CP 32            ; Other source controls cannot begin an ordinary token.
        JP C,LSYNTAX     ; The first byte is below printable ASCII.
        CP 127           ; DEL is a control byte even though it is ASCII.
        JP Z,LSYNTAX     ; Reject DEL outside a supported escape.
        CALL LAPPEND     ; Save the first ordinary token byte.
LEXTOKEN: CALL LEXPEEK       ; Keep the terminator available to the next token request.
        JP C,LEXCLASS      ; EOF terminates an otherwise complete token.
        CALL LEXDELIM      ; Check whether the peeked byte belongs to the next token.
        JP Z,LEXCLASS      ; Classify the accumulated spelling before consuming a delimiter.
        LD A,(LBUFLEN)     ; Read the buffered byte count.
        CP 64            ; All ordinary token spellings fit the numeric-token buffer limit.
        JP Z,LEXCAP       ; Capacity is exhausted before the next buffer write.
        CALL LEXTAKE       ; Consume a nondelimiter already known to fit.
        CALL LAPPEND     ; Append this raw token byte.
        JR LEXTOKEN        ; Continue until a delimiter or EOF.
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

; Strings count decoded bytes. Hex escapes may represent all 256 byte values.
LSTRING:
        CALL LEXTAKE       ; Read another literal byte or its closing quote.
        JP C,LSYNTAX     ; EOF before the closing quote is an incomplete string.
        CP 34            ; An unescaped double quote ends the literal.
        JR Z,LSTRDONE    ; Do not append the closing delimiter.
        CP 92            ; A backslash introduces a decoded escape.
        JR Z,LESCAPE     ; The escape path returns through the common byte append.
        CP 32            ; Raw controls must be spelled through escapes.
        JP C,LSYNTAX     ; Raw control bytes cannot appear in this literal position.
        CP 127           ; DEL must also use a byte escape.
        JP Z,LSYNTAX     ; Reject an unescaped DEL byte.
; Check decoded capacity before storing the next string byte.
LSTRBYTE:
        LD B,A           ; Preserve the decoded byte during the capacity check.
        LD A,(LBUFLEN)     ; Read the buffered byte count.
        CP 255           ; A string may own at most 255 decoded bytes.
        JP Z,LEXCAP       ; Capacity is exhausted before the next buffer write.
        LD A,B           ; Recover the byte after proving there is room.
        CALL LAPPEND     ; Store one decoded byte, irrespective of escape source length.
        JR LSTRING       ; Continue looking for the terminating quote.
; Translate supported single-letter escapes or dispatch two hex digits.
LESCAPE:
        CALL LEXTAKE       ; Read the escape selector following the backslash.
        JP C,LSYNTAX     ; An escape needs at least its selector byte.
        CP 120           ; Lowercase x selects a two-digit byte escape.
        JR Z,LHEXSTR     ; Decode hex, then require its terminating semicolon.
        CP 34            ; Escaped double quote becomes an ordinary string byte.
        JR Z,LSTRBYTE    ; Store the literal quote or backslash.
        CP 92            ; Escaped backslash also represents itself.
        JR Z,LSTRBYTE    ; Store the literal quote or backslash.
        CP 110           ; The letter n selects newline byte 10.
        LD B,10          ; Prepare newline while retaining the comparison flags.
        JR Z,LESCBYTE    ; Use the decoded control byte prepared in B.
        CP 114           ; The letter r selects carriage return byte 13.
        LD B,13          ; Prepare CR while retaining the comparison flags.
        JR Z,LESCBYTE    ; Use the decoded control byte prepared in B.
        CP 116           ; The only remaining selector is t for tab.
        JP NZ,LSYNTAX    ; Unsupported escape letters are not silently accepted.
        LD B,9           ; Tab is byte 9.
; Use the decoded escape byte chosen by the comparisons above.
LESCBYTE:
        LD A,B
        JR LSTRBYTE      ; Apply the same decoded-capacity check as ordinary contents.
; Require the semicolon after exactly two string-escape hex digits.
LHEXSTR:
        CALL LHEXPAIR    ; Decode exactly two source hex digits.
        LD (LTEMPSV),A    ; Retain the saved escape byte.
        CALL LEXTAKE       ; Consume the required escape terminator.
        JP C,LSYNTAX     ; EOF cannot replace the hex escape semicolon.
        CP 59            ; String byte escapes end with a semicolon.
        JP NZ,LSYNTAX    ; Reject missing or alternative terminators.
        LD A,(LTEMPSV)    ; Read the saved escape byte.
        JR LSTRBYTE      ; Append the decoded byte, including zero or high-bit values.
; The closing quote finishes a decoded literal, including an empty one.
LSTRDONE:
        LD A,8           ; Select the public string-token kind.
        LD (LTOKIND),A    ; Retain the text token kind.
        JR LEXTEXT         ; Expose decoded bytes and decoded length.
; Combine two checked source hex digits into one byte.
LHEXPAIR:
        CALL LEXTAKE       ; Read the next required hex digit.
        JP C,LSYNTAX     ; Both hex digits must be present.
        CALL LEXHEX        ; Validate and reduce this ASCII digit to 0..15.
        RLCA             ; Shift the four-bit high digit toward bits 7..4.
        RLCA             ; Shift the four-bit high digit toward bits 7..4.
        RLCA             ; Shift the four-bit high digit toward bits 7..4.
        RLCA             ; Shift the four-bit high digit toward bits 7..4.
        LD (LHEXHIGH),A   ; Retain the shifted high nibble.
        CALL LEXTAKE       ; Read the next required hex digit.
        JP C,LSYNTAX     ; Both hex digits must be present.
        CALL LEXHEX        ; Validate and reduce this ASCII digit to 0..15.
        LD B,A           ; Hold the decoded low nibble for combination.
        LD A,(LHEXHIGH)   ; Read the shifted high nibble.
        OR B             ; Combine disjoint high and low nibble bits.
        RET              ; Return the complete decoded byte in A.
; Decode ASCII hex to a nibble, rejecting every other byte.
LEXHEX:   CP 48
        JP C,LSYNTAX     ; Values below ASCII zero cannot be hexadecimal.
        CP 58            ; ASCII colon follows the last decimal digit.
        JR C,LHEXDIG     ; Decode zero through nine by their simpler offset.
        OR 32            ; Fold uppercase A..F to the lowercase comparison range.
        CP 97            ; Lowercase a is the first permitted letter.
        JP C,LSYNTAX     ; The folded nondigit lies below a, so it is not a hex letter.
        CP 103           ; Lowercase g is the first letter beyond hex.
        JP NC,LSYNTAX    ; Only a..f survive the upper-bound check.
        SUB 87           ; Map a..f to nibble values ten through fifteen.
        RET              ; The caller consumes only the decoded nibble.
; ASCII decimal hex digits differ from their nibble by 48.
LHEXDIG:
        SUB 48
        RET              ; Return a nibble from zero through nine.

; Hash tokens are booleans or byte characters; other Scheme extensions reject.
LEXHASH:  CALL LEXTAKE       ; Consume the next hash-selector or character byte.
        JP C,LSYNTAX     ; The hash or character prefix requires another source byte.
        CP 116           ; Lowercase t selects the true singleton.
        LD HL,0FE01H     ; Prepare the true scalar payload without changing Z.
        JP Z,LEXBOOL       ; Require a delimiter before returning this boolean.
        CP 102           ; Lowercase f selects the false singleton.
        LD HL,0FE00H     ; Prepare false while preserving the comparison result.
        JP Z,LEXBOOL       ; Require a delimiter before returning this boolean.
        CP 92            ; Otherwise only backslash character syntax is supported.
        JP NZ,LSYNTAX    ; Reject vectors, prefixes and other unsupported hash forms.
        CALL LEXTAKE       ; Consume the next hash-selector or character byte.
        JP C,LSYNTAX     ; The hash or character prefix requires another source byte.
        CP 33            ; Raw characters must be printable, excluding whitespace.
        JP C,LSYNTAX     ; Raw control bytes cannot appear in this literal position.
        CP 127           ; DEL is not a raw printable character.
        JP Z,LSYNTAX     ; Use xHH when the desired byte is not printable.
        CALL LAPPEND     ; Retain the first character byte before testing delimiters.
        CALL LEXDELIM      ; A delimiter may itself be the selected raw character.
        JR Z,LCHARONE    ; Do not absorb following text into a delimiter character.
; A named character ends at the same delimiters as other tokens.
LCHARLOP:
        CALL LEXPEEK       ; Inspect the next byte without consuming the terminator.
        JR C,LCHARCLS    ; EOF completes a character spelling.
        CALL LEXDELIM      ; Check whether the character name has ended.
        JR Z,LCHARCLS    ; Validate the complete name now.
        LD A,(LBUFLEN)     ; Read the buffered byte count.
        CP 7             ; The longest supported name is newline, seven bytes.
        JP Z,LSYNTAX     ; No valid character name has an eighth byte.
        CALL LEXTAKE       ; Consume one additional name byte.
        CALL LAPPEND     ; Retain it for exact name or hex matching.
        JR LCHARLOP      ; Continue until delimiter or EOF.
; A character is one byte, xHH, or an exact supported name.
LCHARCLS:
        LD A,(LBUFLEN)     ; Read the buffered byte count.
        CP 1             ; One printable byte directly denotes itself.
        JR Z,LCHARONE    ; No name lookup is needed for a one-byte spelling.
        CP 3             ; Only xHH has a valid three-byte spelling.
        JR NZ,LCHNAME    ; Other lengths must exactly match a supported name.
        LD A,(LBUFFER)   ; Check the selector before interpreting the remaining bytes.
        CP 120           ; Hex characters use lowercase x.
        JP NZ,LSYNTAX    ; Three-byte names other than xHH are unsupported.
        LD A,(LBUFFER+1) ; Fetch the high hex digit from the buffered name.
        CALL LEXHEX        ; Reduce an ASCII hex digit to a checked nibble.
        RLCA             ; Move the high nibble toward its final four high bits.
        RLCA             ; Move the high nibble toward its final four high bits.
        RLCA             ; Move the high nibble toward its final four high bits.
        RLCA             ; Move the high nibble toward its final four high bits.
        LD (LHEXHIGH),A   ; Retain the shifted high nibble.
        LD A,(LBUFFER+2) ; Fetch the low digit after saving the shifted high nibble.
        CALL LEXHEX        ; Reduce an ASCII hex digit to a checked nibble.
        LD B,A           ; Retain the decoded low nibble.
        LD A,(LHEXHIGH)   ; Read the shifted high nibble.
        OR B             ; Join both nibbles into the character byte.
        JR LCHARVAL      ; Wrap the byte in the scalar character encoding.
; Try space and newline without accepting prefixes or trailing bytes.
LCHNAME:
        LD HL,LCSPACE    ; Try the exact zero-terminated space spelling.
        CALL LEXMATCH      ; Z means all bytes and the name length match.
        LD A,32          ; Prepare the space byte without disturbing Z.
        JR Z,LCHARVAL    ; Use byte 32 for the matched name.
        LD HL,LCNEWLN    ; The only other supported name is newline.
        CALL LEXMATCH      ; Z means all bytes and the name length match.
        JP NZ,LSYNTAX    ; Reject unknown names rather than truncating them.
        LD A,10          ; Newline denotes byte 10.
        JR LCHARVAL      ; Construct its scalar character payload.
; The first raw printable byte is itself the character value.
LCHARONE:
        LD A,(LBUFFER)
; Scalar character payloads use FF in the high byte.
LCHARVAL:
        LD L,A           ; Place the character byte in the payload low half.
        LD H,255         ; FFxx is the scalar byte-character range.
LEXBOOL:  PUSH HL         ; Delimiter lookahead must not destroy the payload.
        CALL LEXPEEK       ; Validate the byte following the complete scalar token.
        JR C,LSCALAR     ; EOF is a valid scalar delimiter.
        CALL LEXDELIM      ; Booleans and characters require an explicit token boundary.
        JP NZ,LSYNTAX    ; Reject glued-on suffixes such as #true or #\)x.
; Return the preserved boolean or character payload as scalar kind 7.
LSCALAR:
        POP HL           ; Restore the completed scalar payload.
        LD A,7           ; Select public scalar-token kind 7.
        OR A             ; Clear carry for successful scalar delivery.
        RET              ; No token text is required for the returned scalar.

; Compare a zero-terminated constant against the buffered token, exactly.
LEXMATCH: LD DE,LBUFFER
        LD A,(LBUFLEN)     ; Read the buffered byte count.
        LD B,A           ; Count precisely the nonempty buffered spelling.
; Compare one buffered byte, then require the constant to end too.
LMATLOP:
        LD A,(DE)        ; Read the current byte from the candidate token.
        CP (HL)          ; Compare it against this byte of the constant spelling.
        RET NZ           ; A differing byte rejects this constant immediately.
        INC DE           ; Advance to the next candidate-token byte.
        INC HL           ; Advance to the next constant-name byte.
        DJNZ LMATLOP     ; All buffered bytes must match in sequence.
        LD A,(HL)        ; Inspect the constant immediately after the matched prefix.
        OR A             ; Only its zero terminator proves equal lengths.
        RET              ; Return Z for exact equality, NZ for a longer constant.
LCSPACE: DB "space",0
LCNEWLN: DB "newline",0
LEXCINF:  DB "+inf.0",0
LEXCMINF: DB "-inf.0",0
LEXCNAN:  DB "+nan.0",0
LEXELL:   DB "...",0

; Classification first recognizes decimal grammar, then identifier spelling.
LEXCLASS: LD A,(LBUFLEN)
        CP 1             ; Dot is punctuation only when it is the complete token.
        JR NZ,LSPECIAL   ; Longer spellings must undergo numeric or identifier checks.
        LD A,(LBUFFER)   ; Inspect the single buffered byte.
        CP 46            ; ASCII period denotes dotted-list punctuation.
        LD B,4           ; Prepare dot kind without changing the comparison result.
        JP Z,LSIMPLE     ; Return the structural dot, leaving context checks to the reader.
LSPECIAL: LD HL,LEXELL
        CALL LEXMATCH
        JP Z,LIDDONE
; Recognize the three special float spellings before ordinary grammar.
        LD HL,LEXCINF      ; Try the positive infinity spelling.
        CALL LEXMATCH      ; Match the entire constant, not merely its prefix.
        JR Z,LNUMDONE    ; Special floats need no decimal-grammar scan.
        LD HL,LEXCMINF     ; Try the negative infinity spelling.
        CALL LEXMATCH      ; Match the entire constant, not merely its prefix.
        JR Z,LNUMDONE    ; Special floats need no decimal-grammar scan.
        LD HL,LEXCNAN      ; Only positive nan is a supported NaN spelling.
        CALL LEXMATCH      ; Match the entire constant, not merely its prefix.
        JR Z,LNUMDONE    ; Special floats need no decimal-grammar scan.
        LD HL,LBUFFER    ; Begin ordinary syntax at the first buffered byte.
        LD A,(LBUFLEN)     ; Read the buffered byte count.
        LD B,A           ; B bounds all subsequent reads through the token.
        LD A,(HL)        ; Inspect the optional leading sign.
        CP 43            ; A plus may introduce a signed number.
        JR Z,LNUMSIGN    ; Skip the plus before classifying its following byte.
        CP 45            ; A minus has the same optional-sign role.
        JR NZ,LNUMSTAR   ; An unsigned token starts at its current cursor.
; Skip a leading sign; a sign alone remains an identifier.
LNUMSIGN:
        INC HL           ; Skip the leading mantissa sign.
        DEC B           ; One fewer token byte remains to be checked.
        JR Z,LEXIDENT      ; A sign with no following bytes is an identifier.
; Digits or a decimal point select numeric grammar over identifiers.
LNUMSTAR:
        LD A,(HL)        ; Inspect the first byte after any leading sign.
        CALL LEXDIGIT      ; Carry identifies decimal zero through nine.
        JR C,LNUMSCAN    ; A leading digit irrevocably selects numeric syntax.
        CP 46            ; A leading decimal point also selects numeric syntax.
        JR NZ,LEXIDENT     ; Other initial bytes must satisfy identifier syntax.
        ; A leading dot must have digits; it cannot become an identifier.
; Accumulate the mantissa digit-presence flag across an optional point.
LNUMSCAN:
        XOR A            ; No mantissa digit has yet been seen.
        LD (LDIGITS),A    ; Retain the digit-presence flag.
        CALL LDIGRUN     ; Consume the integer or fractional digit run at HL.
        LD A,B           ; Check whether the token ended after the first run.
        OR A             ; Test whether any token bytes remain unconsumed.
        JR Z,LNUMEND     ; A complete integer spelling still needs at least one digit.
        LD A,(HL)        ; Inspect the first nondigit after that run.
        CP 46            ; A decimal point may separate integer and fraction digits.
        JR NZ,LNUMEXP    ; Without a point, only an exponent may remain.
        INC HL           ; Skip the single permitted decimal point.
        DEC B           ; One fewer token byte remains to be checked.
        CALL LDIGRUN     ; Consume the integer or fractional digit run at HL.
; A mantissa needs a digit; remaining text must begin an exponent.
LNUMEXP:
        LD A,(LDIGITS)    ; Read the digit-presence flag.
        OR A             ; The mantissa must contain digits on at least one side of the point.
        JP Z,LSYNTAX     ; Reject a decimal point without any mantissa digit.
        LD A,B           ; Check for an optional exponent after the complete mantissa.
        OR A             ; Test whether any token bytes remain unconsumed.
        JR Z,LNUMDONE    ; No remaining bytes means the mantissa is the whole number.
        LD A,(HL)        ; Inspect the first remaining byte for the exponent marker.
        OR 32            ; Treat uppercase E and lowercase e alike.
        CP 101           ; Only exponent marker e may follow the mantissa.
        JP NZ,LSYNTAX    ; Reject letters, a second point, and numeric-looking suffixes.
        INC HL           ; Skip the exponent marker.
        DEC B           ; One fewer token byte remains to be checked.
        JP Z,LSYNTAX     ; An exponent marker must be followed by exponent digits.
        LD A,(HL)        ; Inspect the optional exponent sign.
        CP 43            ; A plus may prefix exponent digits.
        JR Z,LEXPSIGN    ; Skip a positive exponent sign.
        CP 45            ; A minus may prefix exponent digits.
        JR NZ,LEXPDIG    ; Unsigned exponents begin their digit run immediately.
; An exponent sign is optional, but never replaces its required digits.
LEXPSIGN:
        INC HL           ; Skip the exponent sign without counting it as a digit.
        DEC B           ; One fewer token byte remains to be checked.
; Restart digit tracking for the exponent independently of the mantissa.
LEXPDIG:
        XOR A            ; Mantissa digits cannot satisfy the exponent-digit requirement.
        LD (LDIGITS),A    ; Retain the digit-presence flag.
        CALL LDIGRUN     ; Scan only the exponent digits now.
; Accept only a complete digit run with no trailing token bytes.
LNUMEND:
        LD A,(LDIGITS)    ; Read the digit-presence flag.
        OR A             ; The active digit run must have at least one digit.
        JP Z,LSYNTAX     ; A missing integer or exponent digit is malformed syntax.
        LD A,B           ; Every byte must belong to the accepted numeric grammar.
        OR A             ; Test whether any token bytes remain unconsumed.
        JR NZ,LSYNTAX    ; Trailing bytes cannot be ignored after a numeric prefix.
; Return original numeric spelling for the separate decimal converter.
LNUMDONE:
        LD A,6           ; Select raw numeric text for the decimal conversion module.
        LD (LTOKIND),A    ; Retain the text token kind.
        JP LEXTEXT         ; Return spelling and length; do not apply floating conversion here.
; Consume decimal digits while B counts the unconsumed token bytes.
LDIGRUN:
        LD A,B           ; The remaining count guards every token-buffer read.
        OR A             ; Test whether any token bytes remain unconsumed.
        RET Z            ; Do not read beyond the complete token.
        LD A,(HL)        ; Inspect the next candidate digit.
        CALL LEXDIGIT      ; Carry means the byte is ASCII zero through nine.
        RET NC           ; Leave the first nondigit for the point/exponent parser.
        LD A,1           ; Remember that this run supplied a required digit.
        LD (LDIGITS),A    ; Retain the digit-presence flag.
        INC HL           ; Advance past the accepted decimal digit.
        DEC B           ; One fewer token byte remains to be checked.
        JR LDIGRUN       ; Continue while digits remain.
; Return C for ASCII digits, leaving the candidate byte in A.
LEXDIGIT: CP 48
        JR C,LNOTDIG     ; Bytes below zero must not inherit subtraction carry.
        CP 58            ; After the lower bound, carry means the byte is below colon.
        RET              ; Return carry exactly for ASCII digits; retain A.
; Values below ASCII zero are not digits, so clear carry explicitly.
LNOTDIG:
        OR A
        RET              ; The caller sees carry clear for a non-digit.
; Validate the fixed 31-byte identifier capacity and initial alphabet.
LEXIDENT: LD A,(LBUFLEN)
        CP 32            ; Identifiers stop at 31 bytes, including their initial byte.
        JR NC,LEXCAP       ; Do not truncate a longer identifier into a different name.
        LD B,A           ; Count the complete identifier spelling.
        LD HL,LBUFFER    ; Start identifier checks from the original token start.
        LD A,(HL)        ; The initial byte must be a letter or approved punctuation.
        CALL LINITIAL    ; Carry reports membership in the initial alphabet.
        JR NC,LSYNTAX    ; Digits and unsupported punctuation cannot start names.
; Subsequent identifier bytes may also be decimal digits.
LIDLOOP:
        INC HL           ; Skip the identifier byte already proven valid.
        DEC B           ; One fewer token byte remains to be checked.
        JR Z,LIDDONE     ; Every byte has now passed its alphabet check.
        LD A,(HL)        ; Inspect the next identifier byte.
        CALL LEXDIGIT      ; Digits are permitted after the initial byte.
        JR C,LIDLOOP     ; An accepted digit needs no punctuation search.
        CALL LINITIAL    ; Other bytes must belong to the initial alphabet.
        JR NC,LSYNTAX    ; Reject unsupported punctuation anywhere in a name.
        JR LIDLOOP       ; Continue after the accepted letter or punctuation.
; Identifier spelling is valid; interning belongs to the reader above.
LIDDONE:
        LD A,5           ; Select the public symbol-spelling kind.
        LD (LTOKIND),A    ; Retain the text token kind.
        JP LEXTEXT         ; The next layer interns these case-sensitive original bytes.
; Recognize letters and the explicit punctuation alphabet; preserve HL,BC.
LINITIAL:
        PUSH HL          ; Protect the caller's current token cursor.
        PUSH BC          ; Protect the remaining count and caller scratch byte.
        LD C,A           ; Keep the original spelling byte for punctuation comparisons.
        OR 32            ; Case-fold only the temporary comparison value.
        CP 97            ; The folded alphabet starts at lowercase a.
        JR C,LIDPUNC     ; Lower values may still be permitted punctuation.
        CP 123           ; The byte after lowercase z bounds the letter range.
        JR C,LEXIDOK      ; The folded value is a letter; original text remains unchanged.
; Search punctuation only after the case-folded letter check fails.
LIDPUNC:
        LD HL,LIPUNCT    ; Use the exact permitted punctuation alphabet.
        LD B,16          ; Search all sixteen entries, with no terminator access.
; C retains the original candidate; the table contains exactly 16 bytes.
LIDPLOP:
        LD A,(HL)        ; Fetch the next permitted punctuation byte.
        CP C             ; Compare against the original, not case-folded, candidate.
        JR Z,LEXIDOK      ; A table match proves the byte valid.
        INC HL           ; Advance to the next punctuation-table entry.
        DJNZ LIDPLOP     ; Stop after the final declared alphabet byte.
        POP BC           ; Restore the caller's remaining token length.
        POP HL           ; Restore its current token cursor.
        OR A             ; No letter or punctuation matched, so clear carry.
        RET              ; Report alphabet rejection without altering the scan state.
; Restore the caller scan state and report an accepted identifier byte.
LEXIDOK: POP BC
        POP HL           ; Restore the caller token cursor after successful lookup.
        SCF              ; Carry is the alphabet-membership result.
        RET              ; Resume the caller with its count and cursor intact.
LIPUNCT: DB "!$%&*/:<=>?^_~+-"

; Terminal errors restore the public call's stack regardless of private depth.
LSYNTAX:
        LD A,128         ; Select the terminal malformed-source diagnostic.
        JR LEXERROR        ; Keep the token-start position already recorded.
LEXCAP:   LD A,129
        JR LEXERROR        ; Capacity failure retains the offending token start.
LEXENC:   CALL LSETLOC    ; Encoding failures identify the offending source byte.
        LD A,130         ; Select the non-ASCII source diagnostic.
        JR LEXERROR        ; The encoding path has refreshed the offending byte position.
LPOSERR:
        CALL LSETLOC    ; Report the current cursor before its field wraps.
        LD A,131         ; Select the bounded-source-position diagnostic.
; Latch the error and discard every private lexer return address.
LEXERROR: LD (LSTATUS),A
        LD SP,(LEXENTRY)   ; Discard saved registers and helper returns, retaining caller RET.
        SCF              ; The latched A code is an error, not a token kind.
        RET              ; Return directly to LEXNEXT's caller with a balanced stack.
; Copy the current source cursor to the public diagnostic/token fields.
LSETLOC:
        LD HL,(LOFFSET)     ; Read the current consumed-byte position.
        LD (LTOKOFF),HL    ; Expose it as this token or diagnostic's byte offset.
        LD HL,(LLINENO)    ; Read the current one-based line.
        LD (LTOKLIN),HL   ; Expose the matching line alongside the offset.
        LD HL,(LCOLUMN)     ; Read the current one-based column.
        LD (LTOKCOL),HL    ; Finish the coherent public location snapshot.
        RET              ; No source byte was consumed by taking this snapshot.
LEXCODE:
LEXWORK:
LCALLADR: DW 0            ; Caller-supplied source callback address.
LEXSTATE:
LEXENTRY: DW 0            ; Public LEXNEXT stack boundary for terminal unwinding.
LSTATUS: DB 0           ; 0 active,1 EOF,128..131 terminal diagnostic.
LEXHAVE: DB 0             ; 0 empty lookahead,1 byte,2 EOF.
LEXLOOK: DB 0             ; The single buffered source byte.
LCRFLAG: DB 0               ; Previous consumed byte was CR.
LOFFSET: DW 0              ; Consumed byte count, bounded at 65535.
LLINENO: DW 1             ; Current one-based source line.
LCOLUMN: DW 1              ; Current one-based source column.
LTOKOFF: DW 0             ; Current token's starting byte offset.
LTOKLIN: DW 0            ; Current token's starting line.
LTOKCOL: DW 0             ; Current token's starting column.
LBUFLEN: DB 0              ; Buffered bytes, at most 255.
LTOKIND: DB 0             ; Text token result kind.
LTEMPSV: DB 0             ; Decoded string escape across delimiter consumption.
LHEXHIGH: DB 0            ; High hexadecimal nibble already shifted into place.
LDIGITS: DB 0             ; Decimal grammar has consumed at least one digit.
LBUFFER: DS 256         ; Current token bytes; no terminator promised.
LEXWEND:
