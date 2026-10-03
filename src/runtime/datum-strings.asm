; Read one quoted string datum into the managed string pool.
;
; The source spelling follows the compiler lexer: printable ASCII is copied
; directly, controls use n/r/t escapes, quotes and backslashes may be escaped,
; and xHH; spells any byte.  The decoded string is limited to 255 bytes so its
; length-prefixed managed representation remains one-byte addressable.

; Begin after the opening quote has already been consumed by DR_DATUM.
DR_STR:
        XOR A                       ; Start with an empty decoded string.
        LD (DR_SIZE),A              ; The buffer count is the current length.
.LOOP:
        CALL DR_TAKE                ; Take the next source byte.
        JP C,ERROR                  ; EOF before the closing quote is malformed.
        CP 34                       ; An unescaped quote closes the string.
        JP Z,DR_MAKE                ; Allocate only after the full datum is read.
        CP 92                       ; A backslash starts one supported escape.
        JR Z,.ESCAPE                ; Decode the selector before appending.
        CP 32                       ; Raw control bytes are not string contents.
        JP C,ERROR
        CP 127                      ; DEL must use the explicit byte escape.
        JP Z,ERROR
        CALL DR_ADD                  ; Append a printable source byte.
        JP .LOOP

; Decode a single-letter escape or dispatch the two-digit byte escape.
.ESCAPE:
        CALL DR_TAKE                ; Read the selector after the backslash.
        JP C,ERROR                  ; A trailing backslash is malformed.
        CP 120                      ; Lowercase x introduces a byte escape.
        JR Z,.HEX
        CP 34                       ; Escaped quote represents a quote byte.
        JR NZ,.SLASH
        CALL DR_ADD
        JP .LOOP
.SLASH:
        CP 92                       ; Escaped backslash represents a slash byte.
        JR NZ,.LETTER
        CALL DR_ADD
        JP .LOOP
.LETTER:
        CP 110                      ; Lowercase n represents line feed.
        JP Z,.NEWLINE
        CP 114                      ; Lowercase r represents carriage return.
        JP Z,.RETURN
        CP 116                      ; Lowercase t represents horizontal tab.
        JP Z,.TAB
        JP ERROR                    ; No other escape spelling is accepted.

; Append the standard control byte selected by the escape dispatcher.
.NEWLINE:
        LD A,10                      ; Newline is ASCII line feed.
        CALL DR_ADD
        JP .LOOP
.RETURN:
        LD A,13                      ; Carriage return is ASCII thirteen.
        CALL DR_ADD
        JP .LOOP
.TAB:
        LD A,9                       ; Tab is ASCII nine.
        CALL DR_ADD
        JP .LOOP

; Decode exactly two hexadecimal digits followed by a semicolon.
.HEX:
        CALL DR_TAKE                ; Read the high hexadecimal digit.
        JP C,ERROR                  ; Both digits are required.
        CALL DR_HEX                 ; Reduce ASCII hex to a four-bit value.
        JP C,ERROR                  ; Reject every non-hex source byte.
        ADD A,A                      ; Shift the high nibble into bits 7..4.
        ADD A,A
        ADD A,A
        ADD A,A
        LD (DR_TMP),A                ; Keep the high nibble across input reads.
        CALL DR_TAKE                ; Read the low hexadecimal digit.
        JP C,ERROR
        CALL DR_HEX                 ; Reduce the low digit to four bits.
        JP C,ERROR
        LD B,A                       ; Hold the decoded low nibble.
        LD A,(DR_TMP)                ; Recover the shifted high nibble.
        OR B                         ; Combine the two disjoint nibbles.
        LD (DR_TMP),A                ; Retain the decoded byte while checking ';'.
        CALL DR_TAKE                ; Consume the required escape terminator.
        JP C,ERROR
        CP 59                        ; A byte escape ends with semicolon.
        JP NZ,ERROR
        LD A,(DR_TMP)                 ; Recover the decoded byte for appending.
        CALL DR_ADD
        JP .LOOP

; Convert one ASCII hexadecimal byte to a nibble, with carry on failure.
DR_HEX:
        CP 48                        ; Bytes below ASCII zero are invalid.
        JR C,.BAD
        CP 58                        ; ASCII colon follows decimal nine.
        JR C,.DIGIT
        OR 32                        ; Fold uppercase A..F to lowercase.
        CP 97                        ; Lowercase a begins the letter range.
        JR C,.BAD
        CP 103                       ; Lowercase g follows the accepted range.
        JR NC,.BAD
        SUB 87                       ; Map a..f to ten through fifteen.
        OR A                         ; Clear carry after a valid conversion.
        RET
.DIGIT:
        SUB 48                       ; Map 0..9 to their numeric nibble.
        OR A                         ; Clear carry after a valid conversion.
        RET
.BAD:
        SCF                          ; Report a malformed hexadecimal digit.
        RET

; Append A to the raw decoded buffer while enforcing the 255-byte limit.
DR_ADD:
        LD (DR_TMP),A                ; Preserve the byte during address arithmetic.
        LD A,(DR_SIZE)               ; Read the number of bytes already stored.
        CP 255                        ; A 256th decoded byte is outside the contract.
        JP NC,ERROR
        LD L,A                        ; Zero-extend the byte count into an offset.
        LD H,0
        LD DE,DR_TEXT                ; Locate the fixed reader string buffer.
        ADD HL,DE
        LD A,(DR_TMP)                 ; Restore the decoded byte.
        LD (HL),A                     ; Store it at the next free buffer position.
        LD A,(DR_SIZE)
        INC A
        LD (DR_SIZE),A               ; Publish the new decoded length.
        OR A                          ; Clear carry for the enclosing string loop.
        RET

; Allocate a managed string and copy the decoded buffer into its payload.
DR_MAKE:
        LD A,(DR_SIZE)               ; STR_NEW reads the shared length scratch.
        LD (STR_LEN),A
        CALL STR_NEW                 ; Allocate and mark one managed string.
        JP C,ERROR                  ; Allocation failure is a runtime error.
        LD A,(STR_LEN)               ; Retain the count across the destination setup.
        LD (HL),A                    ; The managed representation starts with length.
        INC HL                       ; DE becomes the first managed payload byte.
        EX DE,HL
        LD HL,DR_TEXT                ; HL walks the decoded source buffer.
        LD B,A                       ; DJNZ copies exactly the decoded byte count.
        OR A
        JR Z,.RETURN                 ; Empty strings have no payload bytes to copy.
.COPY:
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ .COPY
.RETURN:
        LD A,6                        ; Managed strings use logical tag six.
        LD HL,(STR_DST)              ; Return the allocated object base address.
        OR A                          ; Clear carry for the ordinary datum path.
        RET

DR_TEXT: DS 255                      ; Raw decoded bytes before managed allocation.
