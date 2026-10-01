; Native lexer booleans and character literals.
; Entry points: LEXHASH, LCHARCLS, LCHNAME and LEXBOOL.
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
