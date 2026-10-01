; Native lexer diagnostics, source locations and static state.
; Entry points: LEXERROR, LSETLOC and LNEWPART.
; Terminal errors restore the public call's stack regardless of private depth.
LSYNTAX:
        LD A,128         ; Select the terminal malformed-source diagnostic.
        JR LEXERROR        ; Keep the token-start position already recorded.
LEXCAP:   LD A,129
        JR LEXERROR        ; Capacity failure retains the offending token start.
LEXENC:   CALL LSETLOC    ; Encoding failures identify the offending source byte.
        LD A,130         ; Select the non-ASCII source diagnostic.
        JR LEXERROR        ; The encoding path has refreshed the offending byte position.
LPOSERR:
        CALL LSETLOC    ; Report the current cursor before its field wraps.
        LD A,131         ; Select the bounded-source-position diagnostic.
; Latch the error and discard every private lexer return address.
LEXERROR: LD (LSTATUS),A
        LD SP,(LEXENTRY)   ; Discard saved registers and helper returns, retaining caller RET.
        SCF              ; The latched A code is an error, not a token kind.
        RET              ; Return directly to LEXNEXT's caller with a balanced stack.
; Copy the current source cursor to the public diagnostic/token fields.
LSETLOC:
        LD A,(LSPART)      ; Retain the source-table ordinal with the cursor.
        LD (LTOKPART),A    ; The compiler uses it to recover the CP/M filename.
        LD HL,(LOFFSET)     ; Read the current consumed-byte position.
        LD (LTOKOFF),HL    ; Expose it as this token or diagnostic's byte offset.
        LD HL,(LLINENO)    ; Read the current one-based line.
        LD (LTOKLIN),HL   ; Expose the matching line alongside the offset.
        LD HL,(LCOLUMN)     ; Read the current one-based column.
        LD (LTOKCOL),HL    ; Finish the coherent public location snapshot.
        RET              ; No source byte was consumed by taking this snapshot.
; Start a new source part while retaining the callback and lexer status.
; A is the zero-based source-table ordinal.  The next real source byte will
; be counted at offset zero, line one and column one in that part.
LNEWPART:
        PUSH AF           ; Keep the ordinal while clearing word coordinates.
        XOR A             ; A zero clears the CR state and byte fields below.
        LD (LCRFLAG),A    ; A part boundary cannot inherit a CRLF pair.
        LD HL,0           ; New parts begin before their first source byte.
        LD (LOFFSET),HL   ; Reset the part-relative byte offset.
        LD HL,1           ; Source lines and columns are one-based.
        LD (LLINENO),HL   ; The first byte in a part is line one.
        LD (LCOLUMN),HL   ; The first byte in a part is column one.
        POP AF            ; Restore the caller's source-table ordinal.
        LD (LSPART),A     ; Publish the current part for later token snapshots.
        RET               ; The source adapter supplies the next byte.
LEXCODE:
LEXWORK:
LCALLADR: DW 0            ; Caller-supplied source callback address.
LEXSTATE:
LEXENTRY: DW 0            ; Public LEXNEXT stack boundary for terminal unwinding.
LSTATUS: DB 0           ; 0 active,1 EOF,128..131 terminal diagnostic.
LEXHAVE: DB 0             ; 0 empty lookahead,1 byte,2 EOF.
LEXLOOK: DB 0             ; The single buffered source byte.
LCRFLAG: DB 0               ; Previous consumed byte was CR.
LSPART: DB 0                ; Current zero-based source-table ordinal.
LOFFSET: DW 0              ; Consumed byte count, bounded at 65535.
LLINENO: DW 1             ; Current one-based source line.
LCOLUMN: DW 1              ; Current one-based source column.
LTOKOFF: DW 0             ; Current token's starting byte offset.
LTOKLIN: DW 0            ; Current token's starting line.
LTOKCOL: DW 0             ; Current token's starting column.
LTOKPART: DB 0            ; Current token's source-table ordinal.
LBUFLEN: DB 0              ; Buffered bytes, at most 255.
LTOKIND: DB 0             ; Text token result kind.
LTEMPSV: DB 0             ; Decoded string escape across delimiter consumption.
LHEXHIGH: DB 0            ; High hexadecimal nibble already shifted into place.
LDIGITS: DB 0             ; Decimal grammar has consumed at least one digit.
LBUFFER: DS 256         ; Current token bytes; no terminator promised.
LEXWEND:
