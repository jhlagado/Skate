; Symbol tokens for the datum reader.  Part of the optional I/O module; the
; interner it calls is in datum-symbols.asm.

; Read one symbol token whose first byte is in DR_BYTE.
DR_SYM:
        XOR A                     ; The token buffer starts empty.
        LD (DR_LEN),A
        LD A,(DR_BYTE)            ; Validate the initial identifier alphabet.
        CALL DR_FIRST
        JP NC,ERROR                ; Runtime symbols follow the compiler alphabet.
        LD A,(DR_BYTE)            ; DR_FIRST uses A while searching punctuation.
        CALL DR_SPELL              ; Copy the first spelling byte.
        JP C,ERROR
.LOOP:
        CALL DR_PEEK               ; Leave the token delimiter in lookahead.
        JR C,.DONE                 ; EOF terminates the final symbol.
        CALL DR_DELIM
        JR Z,.DONE
        CALL DR_TAKE               ; Consume one more spelling byte.
        JP C,ERROR                 ; A peeked byte cannot turn into provider EOF.
        LD (DR_BYTE),A
        CP 128                     ; Raw high bytes are not symbol source bytes.
        JP NC,ERROR
        CALL DR_LATER              ; Validate letters, punctuation or digits.
        JP NC,ERROR
        LD A,(DR_BYTE)
        CALL DR_SPELL
        JP C,ERROR
        JP .LOOP
.DONE:
        LD HL,DR_TOKEN             ; Pass the complete spelling to the interner.
        LD A,(DR_LEN)
        LD C,A
        LD B,0
        CALL DR_FIND
        RET                         ; DR_FIND returns tag four and a stable pointer.

; A is an initial symbol byte.  Carry means that it belongs to the alphabet.
DR_FIRST:
        LD C,A                     ; Preserve the original case for punctuation.
        OR 32                      ; Fold letters only for the range comparison.
        CP 97
        JR C,.PUNCT
        CP 123
        JR C,.YES
.PUNCT:
        LD HL,DR_PUNCT
        LD B,16                    ; The punctuation table has exactly sixteen bytes.
.SCAN:
        LD A,(HL)
        CP C
        JR Z,.YES
        INC HL
        DJNZ .SCAN
        OR A                       ; No letter or punctuation matched.
        RET
.YES:
        SCF
        RET

; A is a subsequent symbol byte.  Digits are permitted after the first byte.
DR_LATER:
        LD A,(DR_BYTE)
        CALL DR_FIRST
        RET C
        LD A,(DR_BYTE)
        CP '0'
        JR C,.NO
        CP ':'
        JR C,.YES
.NO:
        OR A                       ; Invalid subsequent byte returns carry clear.
        RET
.YES:
        SCF
        RET

; Append A to the bounded 31-byte token buffer.
DR_SPELL:
        LD C,A
        LD A,(DR_LEN)
        CP 31
        JR NC,.FULL
        LD E,A
        LD D,0
        LD HL,DR_TOKEN
        ADD HL,DE
        LD A,C
        LD (HL),A
        LD A,(DR_LEN)
        INC A
        LD (DR_LEN),A
        OR A                       ; Clear carry after the successful append.
        RET
.FULL:
        SCF
        RET

DR_PUNCT:    DB "!$%&*/:<=>?^_~+-" ; Same initial punctuation alphabet as the lexer.
DR_TOKEN:    DS 31                 ; Maximum accepted symbol spelling.
