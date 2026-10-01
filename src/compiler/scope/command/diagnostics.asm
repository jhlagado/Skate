; Close the source and choose a positioned diagnostic for parse failures.
SCDIAG:
        LD A,(SCPHASE)             ; Finalisation errors no longer have source text.
        OR A
        JR NZ,.PLAINC
        LD A,(CSPEND)              ; Zero means a byte or terminal EOF was observed.
        OR A
        JR NZ,.PLAINC
        LD A,(LTOKPART)            ; Snapshot the location before closing the source.
        LD (SCERRPT),A
        LD HL,(LTOKOFF)
        LD (SCERROFF),HL
        LD HL,(LTOKLIN)
        LD (SCERRLIN),HL
        LD HL,(LTOKCOL)
        LD (SCERRCOL),HL
        CALL CTCLOSER               ; Close a source left open by a parse failure.
        CALL SINKABRT              ; Delete the spool after its source FCB is closed.
        JP SCPRLOC                  ; Prefix the existing diagnostic with its source.
.PLAINC:
        CALL CTCLOSER               ; Close a source left open by a parse failure.
        CALL SINKABRT              ; Delete the spool after its source FCB is closed.
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
        LD L,A                        ; Twelve bytes describe each source entry.
        LD H,0
        ADD HL,HL                     ; Two times the part ordinal.
        ADD HL,HL                     ; Four times the part ordinal.
        PUSH HL
        ADD HL,HL                     ; Eight times the part ordinal.
        POP DE                        ; Add the four-times component for twelve.
        ADD HL,DE
        LD DE,CSSEEN
        ADD HL,DE
        INC HL                        ; FCB byte zero is the drive number.
        LD B,8
        CALL SCPRSEG                 ; Print the padded base name without spaces.
        LD E,'.'
        CALL SCCPUT
        LD B,3
        JP SCPRSEG

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
        RET NZ                         ; Suppress leading zeroes.
        RET
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
