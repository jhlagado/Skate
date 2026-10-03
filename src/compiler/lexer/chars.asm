; Native lexer booleans and character literals.
; Entry points: LX_HASH, .CLASSIFY, .NAMED and .BOOL.
; Hash tokens are booleans or byte characters; other Scheme extensions reject.
LX_HASH:  CALL LX_TAKE       ; Consume the next hash-selector or character byte.
        JP C,LX_BAD      ; The hash or character prefix requires another source byte.
        CP 116           ; Lowercase t selects the true singleton.
        LD HL,0FE01H     ; Prepare the true scalar payload without changing Z.
        JP Z,.BOOL         ; Require a delimiter before returning this boolean.
        CP 102           ; Lowercase f selects the false singleton.
        LD HL,0FE00H     ; Prepare false while preserving the comparison result.
        JP Z,.BOOL         ; Require a delimiter before returning this boolean.
        CP 92            ; Otherwise only backslash character syntax is supported.
        JP NZ,LX_BAD     ; Reject vectors, prefixes and other unsupported hash forms.
        CALL LX_TAKE       ; Consume the next hash-selector or character byte.
        JP C,LX_BAD      ; The hash or character prefix requires another source byte.
        CP 33            ; Raw characters must be printable, excluding whitespace.
        JP C,LX_BAD      ; Raw control bytes cannot appear in this literal position.
        CP 127           ; DEL is not a raw printable character.
        JP Z,LX_BAD      ; Use xHH when the desired byte is not printable.
        CALL LX_ADD      ; Retain the first character byte before testing delimiters.
        CALL LX_DELIM      ; A delimiter may itself be the selected raw character.
        JR Z,.ONE        ; Do not absorb following text into a delimiter character.
; A named character ends at the same delimiters as other tokens.
.LOOP:
        CALL LX_PEEK       ; Inspect the next byte without consuming the terminator.
        JR C,.CLASSIFY   ; EOF completes a character spelling.
        CALL LX_DELIM      ; Check whether the character name has ended.
        JR Z,.CLASSIFY   ; Validate the complete name now.
        LD A,(LX_LEN)      ; Read the buffered byte count.
        CP 7             ; The longest supported name is newline, seven bytes.
        JP Z,LX_BAD      ; No valid character name has an eighth byte.
        CALL LX_TAKE       ; Consume one additional name byte.
        CALL LX_CTRL     ; Control bytes cannot appear in a character name.
        CALL LX_ADD      ; Retain it for exact name or hex matching.
        JR .LOOP         ; Continue until delimiter or EOF.
; A character is one byte, xHH, or an exact supported name.
.CLASSIFY:
        LD A,(LX_LEN)      ; Read the buffered byte count.
        CP 1             ; One printable byte directly denotes itself.
        JR Z,.ONE        ; No name lookup is needed for a one-byte spelling.
        CP 3             ; Only xHH has a valid three-byte spelling.
        JR NZ,.NAMED     ; Other lengths must exactly match a supported name.
        LD A,(LX_BUF)    ; Check the selector before interpreting the remaining bytes.
        CP 120           ; Hex characters use lowercase x.
        JP NZ,LX_BAD     ; Three-byte names other than xHH are unsupported.
        LD A,(LX_BUF+1)  ; Fetch the high hex digit from the buffered name.
        CALL LX_HEX        ; Reduce an ASCII hex digit to a checked nibble.
        RLCA             ; Move the high nibble toward its final four high bits.
        RLCA             ; Move the high nibble toward its final four high bits.
        RLCA             ; Move the high nibble toward its final four high bits.
        RLCA             ; Move the high nibble toward its final four high bits.
        LD (LX_HI),A      ; Retain the shifted high nibble.
        LD A,(LX_BUF+2)  ; Fetch the low digit after saving the shifted high nibble.
        CALL LX_HEX        ; Reduce an ASCII hex digit to a checked nibble.
        LD B,A           ; Retain the decoded low nibble.
        LD A,(LX_HI)      ; Read the shifted high nibble.
        OR B             ; Join both nibbles into the character byte.
        JR .CHAR         ; Wrap the byte in the scalar character encoding.
; Try space and newline without accepting prefixes or trailing bytes.
.NAMED:
        LD HL,LX_SPACE   ; Try the exact zero-terminated space spelling.
        CALL LX_MATCH      ; Z means all bytes and the name length match.
        LD A,32          ; Prepare the space byte without disturbing Z.
        JR Z,.CHAR       ; Use byte 32 for the matched name.
        LD HL,LX_LF      ; The only other supported name is newline.
        CALL LX_MATCH      ; Z means all bytes and the name length match.
        JP NZ,LX_BAD     ; Reject unknown names rather than truncating them.
        LD A,10          ; Newline denotes byte 10.
        JR .CHAR         ; Construct its scalar character payload.
; The first raw printable byte is itself the character value.
.ONE:
        LD A,(LX_BUF)
; Scalar character payloads use FF in the high byte.
.CHAR:
        LD L,A           ; Place the character byte in the payload low half.
        LD H,255         ; FFxx is the scalar byte-character range.
.BOOL:  PUSH HL           ; Delimiter lookahead must not destroy the payload.
        CALL LX_PEEK       ; Validate the byte following the complete scalar token.
        JR C,.SCALAR     ; EOF is a valid scalar delimiter.
        CALL LX_DELIM      ; Booleans and characters require an explicit token boundary.
        JP NZ,LX_BAD     ; Reject glued-on suffixes such as #true or #\)x.
; Return the preserved boolean or character payload as scalar kind 7.
.SCALAR:
        POP HL           ; Restore the completed scalar payload.
        LD A,7           ; Select public scalar-token kind 7.
        OR A             ; Clear carry for successful scalar delivery.
        RET              ; No token text is required for the returned scalar.
