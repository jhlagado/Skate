; Native lexer diagnostics, source locations and static state.
; Entry points: LX_ERR, LX_MARK and LX_RESET.
; Terminal errors restore the public call's stack regardless of private depth.
LX_BAD:
        LD A,128         ; Select the terminal malformed-source diagnostic.
        JR LX_ERR          ; Keep the token-start position already recorded.
LX_LONG:   LD A,129
        JR LX_ERR          ; Capacity failure retains the offending token start.
LX_ASCII:   CALL LX_MARK  ; Encoding failures identify the offending source byte.
        LD A,130         ; Select the non-ASCII source diagnostic.
        JR LX_ERR          ; The encoding path has refreshed the offending byte position.
LX_WRAP:
        CALL LX_MARK    ; Report the current cursor before its field wraps.
        LD A,131         ; Select the bounded-source-position diagnostic.
; Latch the error and discard every private lexer return address.
LX_ERR: LD (LX_STAT),A
        LD SP,(LX_STACK)   ; Discard saved registers and helper returns, retaining caller RET.
        SCF              ; The latched A code is an error, not a token kind.
        RET              ; Return directly to LX_NEXT's caller with a balanced stack.
; Copy the current source cursor to the public diagnostic/token fields.
LX_MARK:
        LD A,(LX_PART)     ; Retain the source-table ordinal with the cursor.
        LD (LX_TPART),A    ; The compiler uses it to recover the CP/M filename.
        LD HL,(LX_POS)      ; Read the current consumed-byte position.
        LD (LX_TPOS),HL    ; Expose it as this token or diagnostic's byte offset.
        LD HL,(LX_LINE)    ; Read the current one-based line.
        LD (LX_TLINE),HL  ; Expose the matching line alongside the offset.
        LD HL,(LX_COL)      ; Read the current one-based column.
        LD (LX_TCOL),HL    ; Finish the coherent public location snapshot.
        RET              ; No source byte was consumed by taking this snapshot.
; Start a new source part while retaining the callback and lexer status.
; A is the zero-based source-table ordinal.  The next real source byte will
; be counted at offset zero, line one and column one in that part.
LX_RESET:
        PUSH AF           ; Keep the ordinal while clearing word coordinates.
        XOR A             ; A zero clears the CR state and byte fields below.
        LD (LX_CR),A      ; A part boundary cannot inherit a CRLF pair.
        LD HL,0           ; New parts begin before their first source byte.
        LD (LX_POS),HL    ; Reset the part-relative byte offset.
        LD HL,1           ; Source lines and columns are one-based.
        LD (LX_LINE),HL   ; The first byte in a part is line one.
        LD (LX_COL),HL    ; The first byte in a part is column one.
        POP AF            ; Restore the caller's source-table ordinal.
        LD (LX_PART),A    ; Publish the current part for later token snapshots.
        RET               ; The source adapter supplies the next byte.
.CODE_END:
.WORK:
LX_FEED: DW 0             ; Caller-supplied source callback address.
LX_STATE:
LX_STACK: DW 0            ; Public LX_NEXT stack boundary for terminal unwinding.
LX_STAT: DB 0           ; 0 active,1 EOF,128..131 terminal diagnostic.
LX_HAVE: DB 0             ; 0 empty lookahead,1 byte,2 EOF.
LX_LOOK: DB 0             ; The single buffered source byte.
LX_CR: DB 0                 ; Previous consumed byte was CR.
LX_PART: DB 0               ; Current zero-based source-table ordinal.
LX_POS: DW 0               ; Consumed byte count, bounded at 65535.
LX_LINE: DW 1             ; Current one-based source line.
LX_COL: DW 1               ; Current one-based source column.
LX_TPOS: DW 0             ; Current token's starting byte offset.
LX_TLINE: DW 0           ; Current token's starting line.
LX_TCOL: DW 0             ; Current token's starting column.
LX_TPART: DB 0            ; Current token's source-table ordinal.
LX_LEN: DB 0               ; Buffered bytes, at most 255.
LX_KIND: DB 0             ; Text token result kind.
LX_TMP: DB 0              ; Decoded string escape across delimiter consumption.
LX_HI: DB 0               ; High hexadecimal nibble already shifted into place.
LX_SEEN: DB 0             ; Decimal grammar has consumed at least one digit.
LX_BUF: DS 256          ; Current token bytes; no terminator promised.
.WORK_END:
