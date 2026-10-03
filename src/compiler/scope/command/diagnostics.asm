; Close the source and choose a positioned diagnostic for parse failures.
DIAG_OUT:
        CALL SRC_END               ; Close any open part and read its sticky error.
        JR NC,.SRC_OK              ; The source itself did not fail.
        CP 5                       ; Error 5 is a missing, malformed or cyclic include.
        LD HL,M_INCL
        JR Z,.SRC_MSG
        LD HL,M_SOURCE             ; Open, read and close failures share one text.
.SRC_MSG:
        LD (ST_ERROR),HL           ; A source failure replaces a later parse symptom.
.SRC_OK:
        CALL CPM_ENDR              ; Close a transport stream left open by a failure.
        CALL ASO_DROP              ; Delete the spool after the input FCBs are closed.
        LD A,(ST_PHASE)            ; Finalisation errors no longer have source text.
        OR A
        JR NZ,.PLAIN
        LD A,(SRC_PEND)            ; Zero means a byte or terminal EOF was observed.
        OR A
        JR NZ,.PLAIN
        LD A,(LX_TPART)            ; Snapshot the location of the failing token.
        LD (ST_EPART),A
        LD HL,(LX_TPOS)
        LD (ST_EOFF),HL
        LD HL,(LX_TLINE)
        LD (ST_ELINE),HL
        LD HL,(LX_TCOL)
        LD (ST_ECOL),HL
        JP .POSITION                ; Prefix the existing diagnostic with its source.
.PLAIN:
        LD DE,(ST_ERROR)            ; All rejected forms remain unpublished.
        JP CMD_QUIT                 ; Print the diagnostic and warm-start CP/M.

; Print a source-positioned diagnostic through CP/M's character output call.
; The existing message strings remain dollar-terminated and include CR/LF.
.POSITION:
        LD A,(ST_EPART)            ; A valid part maps to the CP/M source table.
        CP 32
        JR NC,.FALLBACK              ; Defensive fallback for a corrupt ordinal.
        CALL .PARTNAME              ; Print the trimmed 8.3 source name.
        JR .COLON
.FALLBACK:
        LD HL,(ST_EOFF)
        CALL DIAG_NUM              ; Preserve an actionable raw byte offset.
.COLON:
        LD E,':'
        CALL DIAG_CHR
        LD HL,(ST_ELINE)
        CALL DIAG_NUM                 ; Print the one-based line number.
        LD E,':'
        CALL DIAG_CHR
        LD HL,(ST_ECOL)
        CALL DIAG_NUM                 ; Print the one-based column number.
        LD E,':'
        CALL DIAG_CHR
        LD E,' '
        CALL DIAG_CHR
        LD DE,(ST_ERROR)              ; The ordinary short diagnostic follows.
        JP CMD_QUIT                   ; Reuse the command's BDOS/warm-start path.

; Print one source-table FCB prefix as NAME.EXT, omitting CP/M padding spaces.
.PARTNAME:
        CALL SRC_SLOT                 ; HL addresses the part's 12-byte FCB prefix.
        INC HL                        ; FCB byte zero is the drive number.
        LD B,8
        CALL .FIELD                  ; Print the padded base name without spaces.
        LD E,'.'
        CALL DIAG_CHR
        LD B,3                       ; The extension follows in the same print loop.

; Print B bytes from HL, skipping CP/M padding spaces.
.FIELD:
.LOOP: LD A,(HL)
        CP ' '
        JR Z,.SKIP
        LD E,A
        CALL DIAG_CHR
.SKIP: INC HL
        DJNZ .LOOP
        RET
; BDOS function two writes the character in E while preserving all registers.
DIAG_CHR:
        PUSH BC
        PUSH HL
        LD C,2
        CALL 5
        POP HL
        POP BC
        RET

; Print an unsigned 16-bit value in decimal without leading zeroes.
DIAG_NUM:
        XOR A
        LD (ST_DIGIT),A
        LD DE,2710H                    ; 10000.
        CALL .PLACE
        LD DE,03E8H                    ; 1000.
        CALL .PLACE
        LD DE,0064H                    ; 100.
        CALL .PLACE
        LD DE,000AH                    ; 10.
        CALL .PLACE
        LD A,L                         ; The final remainder is one decimal digit.
        ADD A,'0'
        LD E,A
        JP DIAG_CHR

; Emit one decimal place and return HL reduced modulo DE.
.PLACE:
        CALL .DIVIDE
        OR A
        JR NZ,.DIGIT
        LD A,(ST_DIGIT)
        OR A
        RET Z                          ; Suppress leading zeroes only.
        XOR A                          ; An inner zero digit is printed.
.DIGIT:  PUSH AF
        LD A,1
        LD (ST_DIGIT),A
        POP AF
        ADD A,'0'
        LD E,A
        JP DIAG_CHR

; Divide HL by the positive 16-bit divisor in DE using bounded subtraction.
; The quotient returns in A and the remainder in HL.  Diagnostic coordinates
; are small enough that this keeps the formatter compact and infrequently used.
.DIVIDE: XOR A
.LOOP: OR A
        SBC HL,DE
        JR C,.DONE
        INC A
        JR .LOOP
.DONE: ADD HL,DE
        RET
