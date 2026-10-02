; Native lexer token classification, numbers and identifiers.
; Entry points: LEXCLASS, LNUMSCAN, LEXIDENT and LINITIAL.
; Compare a zero-terminated constant against the buffered token, exactly.
LEXMATCH: LD DE,LBUFFER
        LD A,(LBUFLEN)     ; Read the buffered byte count.
        LD B,A           ; Count precisely the nonempty buffered spelling.
; Compare one buffered byte, then require the constant to end too.
LMATLOP:
        LD A,(HL)        ; Stop at the constant's terminator: a longer token
        OR A             ; cannot match, and bytes past it belong to another name.
        JR Z,LMATLONG
        LD A,(DE)        ; Read the current byte from the candidate token.
        CP (HL)          ; Compare it against this byte of the constant spelling.
        RET NZ           ; A differing byte rejects this constant immediately.
        INC DE           ; Advance to the next candidate-token byte.
        INC HL           ; Advance to the next constant-name byte.
        DJNZ LMATLOP     ; All buffered bytes must match in sequence.
        LD A,(HL)        ; Inspect the constant immediately after the matched prefix.
        OR A             ; Only its zero terminator proves equal lengths.
        RET              ; Return Z for exact equality, NZ for a longer constant.
LMATLONG: INC A          ; A=1: return NZ for a token longer than the constant.
        RET
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
