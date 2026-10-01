; Native lexer string literals and hexadecimal escapes.
; Entry points: LSTRING, LESCAPE, LHEXSTR and LEXHEX.
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
