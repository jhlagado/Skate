; Close the source and choose a positioned diagnostic for parse failures.
SCDIAG:
        CALL SRC_END               ; Close any open part and read its sticky error.
        JR NC,.SRCOK               ; The source itself did not fail.
        CP 5                       ; Error 5 is a missing, malformed or cyclic include.
        LD HL,SCINCTXT
        JR Z,.SRCMSG
        LD HL,SCSRCTXT             ; Open, read and close failures share one text.
.SRCMSG:
        LD (SCERRPTR),HL           ; A source failure replaces a later parse symptom.
.SRCOK:
        CALL CPM_ENDR              ; Close a transport stream left open by a failure.
        CALL SINKABRT              ; Delete the spool after the input FCBs are closed.
        LD A,(SCPHASE)             ; Finalisation errors no longer have source text.
        OR A
        JR NZ,.PLAINC
        LD A,(SRC_PEND)            ; Zero means a byte or terminal EOF was observed.
        OR A
        JR NZ,.PLAINC
        LD A,(LX_TPART)            ; Snapshot the location of the failing token.
        LD (SCERRPT),A
        LD HL,(LX_TPOS)
        LD (SCERROFF),HL
        LD HL,(LX_TLINE)
        LD (SCERRLIN),HL
        LD HL,(LX_TCOL)
        LD (SCERRCOL),HL
        JP SCPRLOC                  ; Prefix the existing diagnostic with its source.
.PLAINC:
        LD DE,(SCERRPTR)            ; All rejected forms remain unpublished.
        JP SCPRINT                  ; Print the diagnostic and warm-start CP/M.

; Print a source-positioned diagnostic through CP/M's character output call.
; The existing message strings remain dollar-terminated and include CR/LF.
SCPRLOC:
        LD A,(SCERRPT)             ; A valid part maps to the CP/M source table.
        CP 32
        JR NC,.FALLBACK              ; Defensive fallback for a corrupt ordinal.
        CALL SCPARTNM               ; Print the trimmed 8.3 source name.
        JR .COLON
.FALLBACK:
        LD HL,(SCERROFF)
        CALL SCDEC                 ; Preserve an actionable raw byte offset.
.COLON:
        LD E,':'
        CALL SCCPUT
        LD HL,(SCERRLIN)
        CALL SCDEC                    ; Print the one-based line number.
        LD E,':'
        CALL SCCPUT
        LD HL,(SCERRCOL)
        CALL SCDEC                    ; Print the one-based column number.
        LD E,':'
        CALL SCCPUT
        LD E,' '
        CALL SCCPUT
        LD DE,(SCERRPTR)              ; The ordinary short diagnostic follows.
        JP SCPRINT                    ; Reuse the command's BDOS/warm-start path.

; Print one source-table FCB prefix as NAME.EXT, omitting CP/M padding spaces.
SCPARTNM:
        CALL SRC_SLOT                 ; HL addresses the part's 12-byte FCB prefix.
        INC HL                        ; FCB byte zero is the drive number.
        LD B,8
        CALL SCPRSEG                 ; Print the padded base name without spaces.
        LD E,'.'
        CALL SCCPUT
        LD B,3                       ; The extension follows in the same print loop.

; Print B bytes from HL, skipping CP/M padding spaces.
SCPRSEG:
.LOOP: LD A,(HL)
        CP ' '
        JR Z,.SKIP
        LD E,A
        CALL SCCPUT
.SKIP: INC HL
        DJNZ .LOOP
        RET
; BDOS function two writes the character in E while preserving all registers.
SCCPUT:
        PUSH BC
        PUSH HL
        LD C,2
        CALL 5
        POP HL
        POP BC
        RET

; Print an unsigned 16-bit value in decimal without leading zeroes.
SCDEC:
        XOR A
        LD (SCDECH),A
        LD DE,2710H                    ; 10000.
        CALL SCDECP
        LD DE,03E8H                    ; 1000.
        CALL SCDECP
        LD DE,0064H                    ; 100.
        CALL SCDECP
        LD DE,000AH                    ; 10.
        CALL SCDECP
        LD A,L                         ; The final remainder is one decimal digit.
        ADD A,'0'
        LD E,A
        JP SCCPUT

; Emit one decimal place and return HL reduced modulo DE.
SCDECP:
        CALL SCDIV
        OR A
        JR NZ,.OUT
        LD A,(SCDECH)
        OR A
        RET Z                          ; Suppress leading zeroes only.
        XOR A                          ; An inner zero digit is printed.
.OUT:  PUSH AF
        LD A,1
        LD (SCDECH),A
        POP AF
        ADD A,'0'
        LD E,A
        JP SCCPUT

; Divide HL by the positive 16-bit divisor in DE using bounded subtraction.
; The quotient returns in A and the remainder in HL.  Diagnostic coordinates
; are small enough that this keeps the formatter compact and infrequently used.
SCDIV: XOR A
.LOOP: OR A
        SBC HL,DE
        JR C,.DONE
        INC A
        JR .LOOP
.DONE: ADD HL,DE
        RET
