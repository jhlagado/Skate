; Symbol tokens for the datum reader.  Part of the optional I/O module; the
; interner it calls is in datum-symbols.asm.

; Read one symbol token whose first byte is in SRTDRDIG.
SRTDRSYM:
        XOR A                     ; The token buffer starts empty.
        LD (SRTDRLEN),A
        LD A,(SRTDRDIG)           ; Validate the initial identifier alphabet.
        CALL SRTSYFST
        JP NC,SRTERROR             ; Runtime symbols follow the compiler alphabet.
        LD A,(SRTDRDIG)           ; SRTSYFST uses A while searching punctuation.
        CALL SRTSYPUT              ; Copy the first spelling byte.
        JP C,SRTERROR
SRTSYMLP:
        CALL SRTDRPK               ; Leave the token delimiter in lookahead.
        JR C,SRTSYMDN              ; EOF terminates the final symbol.
        CALL SRTDISDL
        JR Z,SRTSYMDN
        CALL SRTDRTK               ; Consume one more spelling byte.
        JP C,SRTERROR              ; A peeked byte cannot turn into provider EOF.
        LD (SRTDRDIG),A
        CP 128                     ; Raw high bytes are not symbol source bytes.
        JP NC,SRTERROR
        CALL SRTSYSUB              ; Validate letters, punctuation or digits.
        JP NC,SRTERROR
        LD A,(SRTDRDIG)
        CALL SRTSYPUT
        JP C,SRTERROR
        JP SRTSYMLP
SRTSYMDN:
        LD HL,SRTDRSB              ; Pass the complete spelling to the interner.
        LD A,(SRTDRLEN)
        LD C,A
        LD B,0
        CALL SRTSYMIN
        RET                         ; SRTSYMIN returns tag four and a stable pointer.

; A is an initial symbol byte.  Carry means that it belongs to the alphabet.
SRTSYFST:
        LD C,A                     ; Preserve the original case for punctuation.
        OR 32                      ; Fold letters only for the range comparison.
        CP 97
        JR C,SRTSYFUN
        CP 123
        JR C,SRTSYFOK
SRTSYFUN:
        LD HL,SRTSYPU
        LD B,16                    ; The punctuation table has exactly sixteen bytes.
SRTSYFPL:
        LD A,(HL)
        CP C
        JR Z,SRTSYFOK
        INC HL
        DJNZ SRTSYFPL
        OR A                       ; No letter or punctuation matched.
        RET
SRTSYFOK:
        SCF
        RET

; A is a subsequent symbol byte.  Digits are permitted after the first byte.
SRTSYSUB:
        LD A,(SRTDRDIG)
        CALL SRTSYFST
        RET C
        LD A,(SRTDRDIG)
        CP '0'
        JR C,SRTSYBAD
        CP ':'
        JR C,SRTSYOK
SRTSYBAD:
        OR A                       ; Invalid subsequent byte returns carry clear.
        RET
SRTSYOK:
        SCF
        RET

; Append A to the bounded 31-byte token buffer.
SRTSYPUT:
        LD C,A
        LD A,(SRTDRLEN)
        CP 31
        JR NC,SRTSYFUL
        LD E,A
        LD D,0
        LD HL,SRTDRSB
        ADD HL,DE
        LD A,C
        LD (HL),A
        LD A,(SRTDRLEN)
        INC A
        LD (SRTDRLEN),A
        OR A                       ; Clear carry after the successful append.
        RET
SRTSYFUL:
        SCF
        RET

SRTSYPU:    DB "!$%&*/:<=>?^_~+-" ; Same initial punctuation alphabet as the lexer.
SRTDRSB:    DS 31                  ; Maximum accepted symbol spelling.
