; Native lexer token classification, numbers and identifiers.
; Entry points: LX_CLASS, .NUMBER, LX_IDENT and LX_ALPHA.
; Compare a zero-terminated constant against the buffered token, exactly.
LX_MATCH: LD DE,LX_BUF
        LD A,(LX_LEN)      ; Read the buffered byte count.
        LD B,A           ; Count precisely the nonempty buffered spelling.
; Compare one buffered byte, then require the constant to end too.
.LOOP:
        LD A,(HL)        ; Stop at the constant's terminator: a longer token
        OR A             ; cannot match, and bytes past it belong to another name.
        JR Z,.LONGER
        LD A,(DE)        ; Read the current byte from the candidate token.
        CP (HL)          ; Compare it against this byte of the constant spelling.
        RET NZ           ; A differing byte rejects this constant immediately.
        INC DE           ; Advance to the next candidate-token byte.
        INC HL           ; Advance to the next constant-name byte.
        DJNZ .LOOP       ; All buffered bytes must match in sequence.
        LD A,(HL)        ; Inspect the constant immediately after the matched prefix.
        OR A             ; Only its zero terminator proves equal lengths.
        RET              ; Return Z for exact equality, NZ for a longer constant.
.LONGER: INC A           ; A=1: return NZ for a token longer than the constant.
        RET
; Character names and their bytes, ended by an empty name.
LX_NAMES: DB "alarm",0,7,"backspace",0,8,"delete",0,127,"escape",0,27
        DB "newline",0,10,"null",0,0,"return",0,13,"space",0,32,"tab",0,9,0
LX_TRUE: DB "true",0
LX_FALSE: DB "false",0
LX_INF:  DB "+inf.0",0
LX_NINF: DB "-inf.0",0
LX_NAN:  DB "+nan.0",0
LX_DOTS:   DB "...",0

; Classification first recognizes decimal grammar, then identifier spelling.
LX_CLASS: LD A,(LX_LEN)
        CP 1             ; Dot is punctuation only when it is the complete token.
        JR NZ,.SPECIAL   ; Longer spellings must undergo numeric or identifier checks.
        LD A,(LX_BUF)    ; Inspect the single buffered byte.
        CP 46            ; ASCII period denotes dotted-list punctuation.
        LD B,4           ; Prepare dot kind without changing the comparison result.
        JP Z,LX_PUNCT    ; Return the structural dot, leaving context checks to the reader.
.SPECIAL: LD HL,LX_DOTS
        CALL LX_MATCH
        JP Z,LX_SYM
; Recognize the three special float spellings before ordinary grammar.
        LD HL,LX_INF       ; Try the positive infinity spelling.
        CALL LX_MATCH      ; Match the entire constant, not merely its prefix.
        JR Z,.NUM_DONE   ; Special floats need no decimal-grammar scan.
        LD HL,LX_NINF      ; Try the negative infinity spelling.
        CALL LX_MATCH      ; Match the entire constant, not merely its prefix.
        JR Z,.NUM_DONE   ; Special floats need no decimal-grammar scan.
        LD HL,LX_NAN       ; Only positive nan is a supported NaN spelling.
        CALL LX_MATCH      ; Match the entire constant, not merely its prefix.
        JR Z,.NUM_DONE   ; Special floats need no decimal-grammar scan.
        LD HL,LX_BUF     ; Begin ordinary syntax at the first buffered byte.
        LD A,(LX_LEN)      ; Read the buffered byte count.
        LD B,A           ; B bounds all subsequent reads through the token.
        LD A,(HL)        ; Inspect the optional leading sign.
        CP 43            ; A plus may introduce a signed number.
        JR Z,.SIGN       ; Skip the plus before classifying its following byte.
        CP 45            ; A minus has the same optional-sign role.
        JR NZ,.START     ; An unsigned token starts at its current cursor.
; Skip a leading sign; a sign alone remains an identifier.
.SIGN:
        INC HL           ; Skip the leading mantissa sign.
        DEC B           ; One fewer token byte remains to be checked.
        JR Z,LX_IDENT      ; A sign with no following bytes is an identifier.
; Digits or a decimal point select numeric grammar over identifiers.
.START:
        LD A,(HL)        ; Inspect the first byte after any leading sign.
        CALL LX_DIGIT      ; Carry identifies decimal zero through nine.
        JR C,.NUMBER     ; A leading digit irrevocably selects numeric syntax.
        CP 46            ; A leading decimal point also selects numeric syntax.
        JR NZ,LX_IDENT     ; Other initial bytes must satisfy identifier syntax.
        ; A leading dot must have digits; it cannot become an identifier.
; Accumulate the mantissa digit-presence flag across an optional point.
.NUMBER:
        XOR A            ; No mantissa digit has yet been seen.
        LD (LX_SEEN),A    ; Retain the digit-presence flag.
        CALL .DIGITS     ; Consume the integer or fractional digit run at HL.
        LD A,B           ; Check whether the token ended after the first run.
        OR A             ; Test whether any token bytes remain unconsumed.
        JR Z,.NUM_END    ; A complete integer spelling still needs at least one digit.
        LD A,(HL)        ; Inspect the first nondigit after that run.
        CP 46            ; A decimal point may separate integer and fraction digits.
        JR NZ,.EXPONENT  ; Without a point, only an exponent may remain.
        INC HL           ; Skip the single permitted decimal point.
        DEC B           ; One fewer token byte remains to be checked.
        CALL .DIGITS     ; Consume the integer or fractional digit run at HL.
; A mantissa needs a digit; remaining text must begin an exponent.
.EXPONENT:
        LD A,(LX_SEEN)    ; Read the digit-presence flag.
        OR A             ; The mantissa must contain digits on at least one side of the point.
        JP Z,LX_BAD      ; Reject a decimal point without any mantissa digit.
        LD A,B           ; Check for an optional exponent after the complete mantissa.
        OR A             ; Test whether any token bytes remain unconsumed.
        JR Z,.NUM_DONE   ; No remaining bytes means the mantissa is the whole number.
        LD A,(HL)        ; Inspect the first remaining byte for the exponent marker.
        OR 32            ; Treat uppercase E and lowercase e alike.
        CP 101           ; Only exponent marker e may follow the mantissa.
        JP NZ,LX_BAD     ; Reject letters, a second point, and numeric-looking suffixes.
        INC HL           ; Skip the exponent marker.
        DEC B           ; One fewer token byte remains to be checked.
        JP Z,LX_BAD      ; An exponent marker must be followed by exponent digits.
        LD A,(HL)        ; Inspect the optional exponent sign.
        CP 43            ; A plus may prefix exponent digits.
        JR Z,.EXP_SIGN   ; Skip a positive exponent sign.
        CP 45            ; A minus may prefix exponent digits.
        JR NZ,.EXP_DIGS  ; Unsigned exponents begin their digit run immediately.
; An exponent sign is optional, but never replaces its required digits.
.EXP_SIGN:
        INC HL           ; Skip the exponent sign without counting it as a digit.
        DEC B           ; One fewer token byte remains to be checked.
; Restart digit tracking for the exponent independently of the mantissa.
.EXP_DIGS:
        XOR A            ; Mantissa digits cannot satisfy the exponent-digit requirement.
        LD (LX_SEEN),A    ; Retain the digit-presence flag.
        CALL .DIGITS     ; Scan only the exponent digits now.
; Accept only a complete digit run with no trailing token bytes.
.NUM_END:
        LD A,(LX_SEEN)    ; Read the digit-presence flag.
        OR A             ; The active digit run must have at least one digit.
        JP Z,LX_BAD      ; A missing integer or exponent digit is malformed syntax.
        LD A,B           ; Every byte must belong to the accepted numeric grammar.
        OR A             ; Test whether any token bytes remain unconsumed.
        JR NZ,LX_BAD     ; Trailing bytes cannot be ignored after a numeric prefix.
; Return original numeric spelling for the separate decimal converter.
.NUM_DONE:
        LD A,6           ; Select raw numeric text for the decimal conversion module.
        LD (LX_KIND),A    ; Retain the text token kind.
        JP LX_TEXT         ; Return spelling and length; do not apply floating conversion here.
; Consume decimal digits while B counts the unconsumed token bytes.
.DIGITS:
        LD A,B           ; The remaining count guards every token-buffer read.
        OR A             ; Test whether any token bytes remain unconsumed.
        RET Z            ; Do not read beyond the complete token.
        LD A,(HL)        ; Inspect the next candidate digit.
        CALL LX_DIGIT      ; Carry means the byte is ASCII zero through nine.
        RET NC           ; Leave the first nondigit for the point/exponent parser.
        LD A,1           ; Remember that this run supplied a required digit.
        LD (LX_SEEN),A    ; Retain the digit-presence flag.
        INC HL           ; Advance past the accepted decimal digit.
        DEC B           ; One fewer token byte remains to be checked.
        JR .DIGITS       ; Continue while digits remain.
; Return C for ASCII digits, leaving the candidate byte in A.
LX_DIGIT: CP 48
        JR C,.NO         ; Bytes below zero must not inherit subtraction carry.
        CP 58            ; After the lower bound, carry means the byte is below colon.
        RET              ; Return carry exactly for ASCII digits; retain A.
; Values below ASCII zero are not digits, so clear carry explicitly.
.NO:
        OR A
        RET              ; The caller sees carry clear for a non-digit.
; Validate the fixed 31-byte identifier capacity and initial alphabet.
LX_IDENT: LD A,(LX_LEN)
        CP 32            ; Identifiers stop at 31 bytes, including their initial byte.
        JR NC,LX_LONG      ; Do not truncate a longer identifier into a different name.
        LD B,A           ; Count the complete identifier spelling.
        LD HL,LX_BUF     ; Start identifier checks from the original token start.
        LD A,(HL)        ; The initial byte must be a letter or approved punctuation.
        CALL LX_ALPHA    ; Carry reports membership in the initial alphabet.
        JR NC,LX_BAD     ; Digits and unsupported punctuation cannot start names.
; Subsequent identifier bytes may also be decimal digits.
.LOOP:
        INC HL           ; Skip the identifier byte already proven valid.
        DEC B           ; One fewer token byte remains to be checked.
        JR Z,LX_SYM      ; Every byte has now passed its alphabet check.
        LD A,(HL)        ; Inspect the next identifier byte.
        CALL LX_DIGIT      ; Digits are permitted after the initial byte.
        JR C,.LOOP       ; An accepted digit needs no punctuation search.
        CALL LX_ALPHA    ; Other bytes must belong to the initial alphabet.
        JR NC,LX_BAD     ; Reject unsupported punctuation anywhere in a name.
        JR .LOOP         ; Continue after the accepted letter or punctuation.
; Identifier spelling is valid; interning belongs to the reader above.
LX_SYM:
        LD A,5           ; Select the public symbol-spelling kind.
        LD (LX_KIND),A    ; Retain the text token kind.
        JP LX_TEXT         ; The next layer interns these case-sensitive original bytes.
; Recognize letters and the explicit punctuation alphabet; preserve HL,BC.
LX_ALPHA:
        PUSH HL          ; Protect the caller's current token cursor.
        PUSH BC          ; Protect the remaining count and caller scratch byte.
        LD C,A           ; Keep the original spelling byte for punctuation comparisons.
        OR 32            ; Case-fold only the temporary comparison value.
        CP 97            ; The folded alphabet starts at lowercase a.
        JR C,.SEARCH     ; Lower values may still be permitted punctuation.
        CP 123           ; The byte after lowercase z bounds the letter range.
        JR C,.YES         ; The folded value is a letter; original text remains unchanged.
; Search punctuation only after the case-folded letter check fails.
.SEARCH:
        LD HL,.PUNCT     ; Use the exact permitted punctuation alphabet.
        LD B,16          ; Search all sixteen entries, with no terminator access.
; C retains the original candidate; the table contains exactly 16 bytes.
.LOOP:
        LD A,(HL)        ; Fetch the next permitted punctuation byte.
        CP C             ; Compare against the original, not case-folded, candidate.
        JR Z,.YES         ; A table match proves the byte valid.
        INC HL           ; Advance to the next punctuation-table entry.
        DJNZ .LOOP       ; Stop after the final declared alphabet byte.
        POP BC           ; Restore the caller's remaining token length.
        POP HL           ; Restore its current token cursor.
        OR A             ; No letter or punctuation matched, so clear carry.
        RET              ; Report alphabet rejection without altering the scan state.
; Restore the caller scan state and report an accepted identifier byte.
.YES: POP BC
        POP HL           ; Restore the caller token cursor after successful lookup.
        SCF              ; Carry is the alphabet-membership result.
        RET              ; Resume the caller with its count and cursor intact.
.PUNCT: DB "!$%&*/:<=>?^_~+-"
