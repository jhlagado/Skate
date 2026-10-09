; Native lexer booleans and character literals.
; Entry points: LX_HASH, .CLASSIFY, .NAMED and .BOOL.
; Hash tokens are booleans, byte characters or the vector opening #( (kind
; 11); other Scheme extensions reject.
LX_HASH:  CALL LX_TAKE       ; Consume the next hash-selector or character byte.
        JP C,LX_BAD      ; The hash or character prefix requires another source byte.
        CP 40            ; #( opens a vector literal.
        LD B,11
        JP Z,LX_PUNCT
        CP 116           ; Lowercase t selects the true singleton.
        LD HL,0FE01H     ; Prepare the true scalar payload without changing Z.
        LD DE,LX_TRUE
        JP Z,.WORD       ; #t or #true.
        CP 102           ; Lowercase f selects the false singleton.
        LD HL,0FE00H     ; Prepare false while preserving the comparison result.
        LD DE,LX_FALSE
        JP Z,.WORD       ; #f or #false.
        CP 92            ; Backslash introduces a character.
        JR Z,.CHAR1
        LD B,A           ; Any other byte is a radix prefix, #b, #o, #d or
        LD A,'#'         ; #x; the number parser checks it and reads the rest.
        CALL LX_ADD
        LD A,B
        CALL LX_ADD
        JP LX_TOKEN
.CHAR1: CALL LX_TAKE       ; Consume the next hash-selector or character byte.
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
        CP 9             ; The longest supported name is backspace, nine bytes.
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
        CP 120           ; Hex characters use lowercase x; tab is a name.
        JR NZ,.NAMED
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
; Find the name in LX_NAMES without accepting prefixes or trailing bytes.
.NAMED:
        LD HL,LX_NAMES
.NAME:
        LD A,(HL)
        OR A
        JP Z,LX_BAD      ; Reject unknown names rather than truncating them.
        PUSH HL
        CALL LX_MATCH      ; Z means all bytes and the name length match.
        POP HL
        PUSH AF
.SKIP:
        LD A,(HL)        ; Pass the name to its byte.
        INC HL
        OR A
        JR NZ,.SKIP
        POP AF
        LD A,(HL)
        INC HL
        JR Z,.CHAR
        JR .NAME
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
        JP NZ,LX_BAD     ; Reject glued-on suffixes such as #\)x.
; Return the preserved boolean or character payload as scalar kind 7.
.SCALAR:
        POP HL           ; Restore the completed scalar payload.
        LD A,7           ; Select public scalar-token kind 7.
        OR A             ; Clear carry for successful scalar delivery.
        RET              ; No token text is required for the returned scalar.
; #t and #f may be spelt out.  HL is the value and DE the full spelling.
.WORD:
        PUSH HL
        PUSH DE
        CALL LX_ADD
.LETTER:
        CALL LX_PEEK
        JR C,.SPELT
        CALL LX_DELIM
        JR Z,.SPELT
        LD A,(LX_LEN)
        CP 5
        JP Z,LX_BAD
        CALL LX_TAKE
        CALL LX_ADD
        JR .LETTER
.SPELT:
        POP HL
        LD A,(LX_LEN)
        DEC A
        JR Z,.SHORT      ; #t or #f alone.
        CALL LX_MATCH
        JP NZ,LX_BAD
.SHORT:
        POP HL
        JR .BOOL
