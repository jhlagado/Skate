; Bounded runtime datum reader.
;
; This unit accepts scalar datums and delegates compound construction to the
; adjacent datum modules.  The shared input helpers leave a delimiter or
; sticky EOF for the next operation.  Symbol tokens are interned separately.

; Read one datum from the current input port or an explicit input port.
DR_READ:
        CALL IN_ARG                 ; No argument selects current input; one names a port.
.START:
        LD A,1                      ; Mark the reader active for root cleanup.
        LD (DR_LIVE),A
        XOR A                       ; No construction roots are live yet.
        LD (DR_ROOTS),A
        LD (DR_DEPTH),A         ; No list, vector or quote frame is open.
        LD (DR_SLOTS),A           ; No temporary value slots are occupied.
        LD (DR_LEN),A             ; No numeric token bytes have been consumed.
        XOR A                     ; No nested value has produced EOF yet.
        LD (DR_EOF),A
        CALL DR_DATUM             ; Parse one complete scalar or list datum.
        JP C,ERROR                ; A checked parser failure propagates outward.
        JP DR_DONE                ; Top-level cleanup preserves the lookahead.

; Parse one datum and return its ordinary A:HL value without ending the read.
DR_DATUM:
        XOR A                     ; The caller must inspect EOF from this value.
        LD (DR_EOF),A
        CALL DR_SKIP              ; Whitespace and comments precede every datum.
        JR C,.EOF                 ; EOF is a value at the top level.
        CALL DR_TAKE              ; Consume the first non-space input byte.
        JP C,.EOF                 ; A provider race still produces EOF.
        LD (DR_BYTE),A            ; Preserve the first token byte for numeric parsing.
        CP '#'                     ; Dispatch booleans and characters together.
        JP Z,.HASH
        CP '('                     ; Lists are constructed by datum-lists.asm.
        JR Z,.LIST
        CP 34                      ; Strings are built by datum-strings.asm.
        JR Z,.STRING
        CP ')'                     ; A close without an open list is malformed.
        JP Z,ERROR
        CP 39                      ; Quote syntax waits for the quote increment.
        JP Z,ERROR
        CP '0'                     ; A digit-leading token is an exact integer.
        JR C,.TRY_SIGN
        CP ':'
        JP C,DR_NUM
.TRY_SIGN:
        CP '+'                     ; A sign followed by a digit is numeric.
        JR Z,.SIGN
        CP '-'                     ; A sign followed by a digit is numeric.
        JR Z,.SIGN
        JP DR_SYM                  ; Other tokens use the bounded symbol interner.
.SIGN:
        CALL DR_PEEK               ; Inspect the byte after the possible sign.
        JP C,DR_SYM                ; A lone sign is an ordinary symbol.
        LD (DR_AHEAD),A            ; Keep the peeked byte across the delimiter test.
        CALL DR_DELIM              ; A delimiter leaves the sign as a symbol.
        JP Z,DR_SYM
        LD A,(DR_AHEAD)
        CP '0'
        JP C,DR_SYM
        CP ':'
        JP C,DR_NUM                ; The existing exact-integer parser owns digits.
        JP DR_SYM
.LIST:
        CALL DR_LIST              ; Return the completed list as a raw value.
        RET
.STRING:
        CALL DR_STR               ; Return the completed string as a raw value.
        RET

; Return the canonical EOF value after an empty input or sticky provider EOF.
.EOF:
        LD A,1                     ; An enclosing list rejects EOF before close.
        LD (DR_EOF),A
        XOR A                       ; EOF uses the scalar logical tag.
        LD HL,0FE03H                ; FE03 is the runtime EOF singleton.
        RET                          ; Top-level .START performs normal cleanup.

; Parse the dispatch byte following a hash marker.
.HASH:
        CALL DR_TAKE              ; Read t, f or the character backslash.
        JP C,ERROR                  ; A missing dispatch byte is malformed.
        CP 't'                      ; #t is the canonical true value.
        JP Z,.TRUE
        CP 'f'                      ; #f is the canonical false value.
        JP Z,.FALSE
        CP 92                       ; Backslash introduces one byte character data.
        JP Z,.CHAR
        CP '('                      ; #(...) is a bounded datum vector.
        JP Z,DR_VEC
        JP ERROR                    ; Other dispatch forms wait for later units.

; Return true after checking that the token has ended at a delimiter.
.TRUE:
        CALL DR_ENDS           ; A boolean cannot be a prefix of a symbol.
        JP NZ,ERROR
        XOR A                       ; Boolean values use the scalar tag.
        LD HL,0FE01H                ; FE01 is canonical #t.
        RET

; Return false after checking that the token has ended at a delimiter.
.FALSE:
        CALL DR_ENDS           ; A boolean cannot be a prefix of a symbol.
        JP NZ,ERROR
        XOR A                       ; Boolean values use the scalar tag.
        LD HL,0FE00H                ; FE00 is canonical #f.
        RET

; Read a character spelling after #\: one printable byte, xHH or an R7RS
; name from CH_NAMES.  The spelling is collected in the symbol buffer until a delimiter.
.CHAR:
        XOR A                       ; Start an empty spelling in the symbol buffer.
        LD (DR_LEN),A
        CALL DR_TAKE              ; The first byte may itself be a delimiter.
        JP C,ERROR                  ; A missing character is malformed.
        CP 33                       ; Control bytes and space need a name.
        JP C,ERROR
        CP 127                      ; DEL and high bytes need the hex spelling.
        JP NC,ERROR
.SPELL:
        CALL DR_SPELL               ; Append the byte; carry after 31 bytes.
        JP C,ERROR                  ; No accepted spelling is that long.
        CALL DR_ENDS                ; Z means a delimiter or EOF ends the spelling.
        JR Z,.DECODE
        CALL DR_TAKE                ; Consume the next spelling byte.
        JP C,ERROR                  ; A peeked byte cannot turn into provider EOF.
        JR .SPELL
.DECODE:
        LD HL,DR_TOKEN              ; HL addresses the first spelling byte.
        LD A,(DR_LEN)               ; Select the spelling form by its length.
        DEC A                       ; A single byte denotes itself.
        JR Z,.SINGLE
        CP 2                        ; Three bytes may be the xHH spelling.
        JR NZ,.NAMED
        LD A,(HL)                   ; The hex form starts with lowercase x.
        CP 'x'
        JR NZ,.NAMED
        INC HL                      ; Decode the high hexadecimal digit.
        LD A,(HL)
        CALL DR_HEX
        JP C,ERROR                  ; Reject a malformed hexadecimal digit.
        RLCA                        ; Move the nibble into bits 7..4.
        RLCA
        RLCA
        RLCA
        LD B,A                      ; Keep the high nibble while decoding the low.
        INC HL                      ; Decode the low hexadecimal digit.
        LD A,(HL)
        CALL DR_HEX
        JP C,ERROR                  ; Reject a malformed hexadecimal digit.
        OR B                        ; Join both nibbles into the character byte.
        JR .CHAR_VAL
.NAMED:
        LD HL,CH_NAMES
.NAME:
        LD A,(HL)                   ; The byte the name stands for.
        CP 0FFH
        JP Z,ERROR                  ; Unknown names are malformed.
        LD C,A
        INC HL
        CALL .MATCH                 ; Z: the spelling is this name.
        LD A,C
        JR Z,.CHAR_VAL
.PASS:
        LD A,(HL)                   ; Move to the next entry.
        INC HL
        CP '$'
        JR NZ,.PASS
        JR .NAME
.SINGLE:
        LD A,(HL)                   ; Return the single spelling byte.
.CHAR_VAL:
        LD L,A                      ; Characters use the low payload byte.
        LD H,0FFH                   ; FFxx is the reserved character range.
        XOR A                       ; Characters use the scalar logical tag.
        RET

; Compare the collected spelling with the $-ended name at HL.  Z reports an
; exact match; HL is left inside the entry.  C is kept.
.MATCH:
        LD A,(DR_LEN)
        LD B,A                      ; B counts the bytes left to compare.
        LD DE,DR_TOKEN              ; DE walks the collected spelling.
.CMP_LOOP:
        LD A,(DE)
        CP (HL)
        RET NZ                      ; A mismatch, or the name ended early.
        INC DE
        INC HL
        DJNZ .CMP_LOOP
        LD A,(HL)                   ; The name must end here too.
        CP '$'
        RET

; Skip spaces and semicolon comments.  A delimiter remains in lookahead.
DR_SKIP:
.LOOP:
        CALL DR_PEEK              ; Peek without consuming the next datum byte.
        RET C                       ; Sticky EOF ends the skip operation.
        CP ' '                      ; Space is horizontal whitespace.
        JR Z,.TAKE
        CP 9                        ; Tab is horizontal whitespace.
        JR Z,.TAKE
        CP 10                       ; LF is a logical line ending.
        JR Z,.TAKE
        CP 13                       ; Keep CR accepted for provider compatibility.
        JR Z,.TAKE
        CP ';'                      ; A semicolon starts a line comment.
        JR Z,.COMMENT
        OR A                        ; A non-space byte remains in lookahead.
        RET
.TAKE:
        CALL DR_TAKE              ; Consume the whitespace byte.
        JR C,.LOOP                ; EOF after whitespace is still ordinary EOF.
        JR .LOOP
.COMMENT:
        CALL DR_TAKE              ; Consume the semicolon itself.
.TO_EOL:
        CALL DR_TAKE              ; Consume comment bytes through the newline.
        JR C,.LOOP                ; EOF terminates a final comment cleanly.
        CP 10                       ; Logical LF ends the comment.
        JR NZ,.TO_EOL
        JR .LOOP

; Peek one logical input byte and return it in A, with carry for sticky EOF.
DR_PEEK:
        LD A,(IN_STATE)          ; Inspect the shared port lookahead state.
        CP 1
        JR Z,.PENDING          ; A pending byte needs no provider call.
        CP 2
        JR Z,.EOF               ; Sticky EOF is returned without blocking.
        CALL IN_NEXT               ; Obtain one byte through the port adapter.
        CALL DR_ASCII              ; Datum input is restricted to ASCII bytes.
        LD A,H                      ; EOF has the reserved FE high payload byte.
        CP 0FEH
        JR NZ,.CHAR            ; A different high byte is a character.
        LD A,L                      ; Check the canonical EOF low payload byte.
        CP 03H
        JR Z,.EOF               ; IN_NEXT has already made EOF sticky.
.CHAR:
        LD A,L                      ; Retain the logical byte for the next take.
        LD (IN_PEEK),A
        LD A,1                      ; State one means a pending logical byte.
        LD (IN_STATE),A
.PENDING:
        LD A,(IN_PEEK)            ; Return the retained byte with carry clear.
        OR A                        ; OR clears carry without changing the byte.
        RET
.EOF:
        SCF                         ; Carry distinguishes EOF from a byte value.
        RET

; Take one logical input byte and return it in A, with carry for sticky EOF.
DR_TAKE:
        LD A,(IN_STATE)          ; Consume a byte already retained by peek.
        CP 1
        JR Z,.PENDING
        CP 2
        JR Z,.EOF               ; Sticky EOF remains EOF on every take.
        CALL IN_NEXT               ; Obtain an unbuffered logical value.
        CALL DR_ASCII              ; Datum input is restricted to ASCII bytes.
        LD A,H                      ; Inspect the returned value's high payload.
        CP 0FEH
        JR NZ,.CHAR            ; A character has high byte FF.
        LD A,L                      ; Confirm the canonical EOF low payload byte.
        CP 03H
        JR Z,.EOF               ; IN_NEXT has already recorded sticky EOF.
.CHAR:
        LD A,L                      ; Return the unbuffered logical character byte.
        OR A                        ; Clear carry for a normal byte result.
        RET
.PENDING:
        XOR A                       ; Empty the shared pending-byte state.
        LD (IN_STATE),A
        LD A,(IN_PEEK)             ; Return the retained character byte.
        OR A                        ; Clear carry for a normal byte result.
        RET
.EOF:
        SCF                         ; Carry reports the sticky EOF state.
        RET

; Return Z when A is a token delimiter and NZ otherwise.
DR_DELIM:
        CP ' '                      ; Space terminates a token.
        JR Z,.YES
        CP 9                        ; Tab terminates a token.
        JR Z,.YES
        CP 10                       ; LF terminates a token.
        JR Z,.YES
        CP 13                       ; CR terminates a token.
        JR Z,.YES
        CP 34                       ; A string opener terminates a preceding token.
        JR Z,.YES
        CP '('                      ; An opening list delimiter ends a scalar.
        JR Z,.YES
        CP ')'                      ; A closing list delimiter ends a scalar.
        JR Z,.YES
        CP 39                       ; Apostrophe ends a scalar token.
        JR Z,.YES
        CP ';'                      ; A comment begins at a token boundary.
        JR Z,.YES
        LD A,1                      ; Non-delimiters return a nonzero flag.
        OR A                        ; Clear carry while setting NZ.
        RET
.YES:
        XOR A                       ; Z identifies a delimiter to the caller.
        RET

; Check the next byte without consuming a delimiter.
DR_ENDS:
        CALL DR_PEEK              ; EOF also terminates a complete scalar token.
        JR C,.EOF
        JP DR_DELIM               ; Return the delimiter predicate directly.
.EOF:
        XOR A                       ; EOF is an accepted token boundary.
        RET

; Reject non-ASCII character bytes while keeping the direct read-char contract.
DR_ASCII:
        LD A,H                      ; Only FFxx values are raw character bytes.
        CP 0FFH
        RET NZ                      ; EOF and other scalar values are left alone.
        LD A,L
        CP 80H                      ; Seven-bit input is the datum-reader policy.
        RET C
        JP ERROR

; Start a signed decimal exact-integer token with its first byte in A.
DR_NUM:
        XOR A                       ; Clear the accumulating magnitude.
        LD (DR_MAG),A
        LD (DR_MAG+1),A
        LD (DR_MAG+2),A
        LD A,1                      ; Count the first spelling byte.
        LD (DR_LEN),A
        XOR A                       ; Positive sign is the default.
        LD (DR_NEG),A
        LD (DR_SEEN),A             ; A sign by itself is not a number.
        LD A,(DR_BYTE)               ; The first byte was staged by the caller.
        JP .FIRST

; The dispatch path stages the first token byte here before entering parsing.
.FIRST:
        CP '+'                       ; A leading plus changes no magnitude.
        JR Z,.PLUS
        CP '-'                       ; A leading minus is applied after parsing.
        JR Z,.MINUS
        CALL DR_DIGIT            ; The first byte must be a decimal digit.
        JP C,ERROR
        LD A,1                       ; Record that at least one digit was seen.
        LD (DR_SEEN),A
        JR .LOOP
.PLUS:
        XOR A                        ; Keep the explicit positive sign.
        LD (DR_NEG),A
        JR .LOOP
.MINUS:
        LD A,1                       ; Record the negative sign for final folding.
        LD (DR_NEG),A
        JR .LOOP

; Consume subsequent token digits until a delimiter or EOF is encountered.
.LOOP:
        CALL DR_PEEK              ; Leave the terminating delimiter pending.
        JR C,DR_INT             ; EOF finishes an unterminated final integer.
        CALL DR_DELIM              ; A delimiter ends the numeric spelling.
        JR Z,DR_INT
        CALL DR_TAKE              ; Consume the next non-delimiter byte.
        JP C,ERROR                  ; A provider EOF cannot follow a peeked byte.
        LD (DR_BYTE),A              ; Preserve it while checking token capacity.
        LD A,(DR_LEN)
        INC A
        CP 65                       ; A numeric spelling is limited to 64 bytes.
        JP NC,ERROR
        LD (DR_LEN),A
        LD A,(DR_BYTE)
        CALL DR_DIGIT            ; Every remaining byte must be a digit.
        JP C,ERROR
        LD A,1                       ; Publish that the token contains a digit.
        LD (DR_SEEN),A
        JR .LOOP

; Add the decimal digit in A to the bounded 24-bit magnitude.
DR_DIGIT:
        CP '0'                       ; Reject bytes below ASCII zero.
        RET C
        CP ':'                       ; ASCII colon is one past the digit range.
        JR C,.ADD
        SCF                         ; Bytes after nine are malformed digits.
        RET
.ADD:
        SUB '0'                      ; Convert the digit to an unsigned value.
        LD (DR_BYTE),A               ; Retain it while multiplying the magnitude.
        LD HL,(DR_MAG)               ; C:HL is the current accumulated magnitude.
        LD A,(DR_MAG+2)
        LD C,A
        ADD HL,HL                    ; Multiply the accumulator by two.
        RL C
        JR C,.OVERFLOW               ; Reject overflow before widening the product.
        LD E,L                       ; B:DE keeps two times the value for the final add.
        LD D,H
        LD B,C
        ADD HL,HL                    ; Multiply by four.
        RL C
        JR C,.OVERFLOW               ; Reject overflow before the next doubling.
        ADD HL,HL                    ; Multiply by eight.
        RL C
        JR C,.OVERFLOW               ; Reject overflow before adding the final digit.
        ADD HL,DE                    ; Eight plus two gives ten times the value.
        LD A,C
        ADC A,B
        LD C,A
        JR C,.OVERFLOW               ; Carry means the 24-bit magnitude overflowed.
        LD A,(DR_BYTE)               ; Add the converted decimal digit.
        ADD A,L
        LD L,A
        LD A,0
        ADC A,H
        LD H,A
        LD A,0
        ADC A,C
        LD C,A
        JR C,.OVERFLOW
        LD (DR_MAG),HL               ; Publish the new magnitude for the next digit.
        LD A,C
        LD (DR_MAG+2),A
        OR A                         ; Clear carry for the successful digit.
        RET
.OVERFLOW:
        SCF                          ; Report an overflowing or malformed digit.
        RET

; Finish the exact-integer token and apply its sign with a signed-24 bound.
; The value returns in A:CHL.
DR_INT:
        LD A,(DR_SEEN)             ; A sign without a digit is malformed.
        OR A
        JP Z,ERROR
        LD HL,(DR_MAG)               ; Recover the unsigned magnitude.
        LD A,(DR_MAG+2)
        LD C,A
        LD A,(DR_NEG)
        OR A
        JR Z,.POSITIVE
        LD A,C                       ; Negative values may reach magnitude 800000H.
        CP 80H
        JR C,.NEGATE
        JP NZ,ERROR
        LD A,H
        OR L
        JP NZ,ERROR
.NEGATE:
        CALL NUM_INV                 ; Form the two's-complement signed payload.
        LD A,3                       ; Exact integers use logical tag three.
        OR A                          ; Successful integer parsing clears carry.
        RET
.POSITIVE:
        BIT 7,C                      ; Positive values must remain below 800000H.
        JP NZ,ERROR
        LD A,3                       ; Exact integers use logical tag three.
        OR A                          ; Successful integer parsing clears carry.
        RET

; Publish a successful immediate result and preserve shared lookahead state.
; Only an exact integer or a float owns byte 2; every other value's is zero.
DR_DONE:
        LD (DR_TAG),A                ; Save the result while clearing reader state.
        LD (DR_VAL),HL
        CP 3
        JR Z,.WIDE
        CP 9
        JR Z,.WIDE
        LD C,0
.WIDE:
        LD A,C
        LD (DR_EXT),A
        CALL .STOP                  ; Keep pending delimiter or sticky EOF intact.
        LD A,(DR_EXT)
        LD C,A
        LD A,(DR_TAG)
        LD HL,(DR_VAL)
        PUSH IX                      ; Return through the common packet cleanup.
        RET

; Stop a successful read without touching the port's pending input state.
.STOP:
        XOR A                        ; The parser no longer owns temporary roots.
        LD (DR_LIVE),A
        LD (DR_ROOTS),A
        LD (DR_DEPTH),A
        LD (DR_SLOTS),A
        LD (DR_HELD),A
        LD (DR_FRAME),A
        LD (DR_FRAME+1),A
        LD HL,RT_DRVLO               ; Discard any value slots consumed by the read.
        LD (DR_SP),HL
        LD (DR_LEN),A
        LD (DR_SIZE),A
        RET

