; CP/M source include stream.
; CIINIT scans the root and up to 31 direct include names, then CIBYTE
; streams the parts in order. Names are CP/M 8.3 names on the command drive.
; The root is reopened after scanning; no source stack or second DMA record is used.
; Entry: CIINIT uses the command FCB and leaves the source ready for CIBYTE.

CIINIT: XOR A                         ; Clear sticky state before the scan.
        LD (CSERROR),A                ; No source error has occurred yet.
        LD (CSPARTNO),A               ; The table assigns part zero to the root.
        INC A                        ; The scan has not produced a location yet.
        LD (CSPEND),A                 ; CIEPART sets this again when streaming begins.
        XOR A
        LD (CSDONE),A                 ; CIBYTE has not reached the end.
        LD A,2                         ; Mode 2 selects the native include stream.
        LD (CSINDEX+1),A
        XOR A                          ; Remaining package flags begin at zero.
        LD (CSINDEX+2),A              ; No manifest FCB is active in this mode.
        LD (CSINDEX+3),A              ; No output part is open after the scan.
        LD (CSINDEX+4),A              ; No separator is waiting for the caller.
        LD (CSINDEX+5),A              ; The part list has not ended.
        LD (CSINDEX+6),A              ; The root is installed below as entry zero.
        LD (CSINDEX+18),A             ; The first dependency is entry one.
        LD (CSINDEX+19),A             ; Phase zero streams direct dependencies.
        LD (CILAST),A                 ; No previous byte requires a separator.
        LD A,128                       ; Force the first scan read to fetch a record.
        LD (CSINDEX+12),A
        XOR A
        LD (CSINDEX+13),A             ; The scan has not reached Ctrl-Z or EOF.
        LD (CSINDEX+16),A             ; Root body skip count low byte.
        LD (CSINDEX+17),A             ; Root body skip count high byte.
        LD (CIPOS),A                  ; Source position low byte.
        LD (CIPOS+1),A                ; Source position high byte.
        LD HL,CSFCB                   ; Retain the command drive/name/type prefix.
        LD DE,CSSEEN                  ; Entry zero is always the root source.
        LD BC,12                      ; Only the prefix is needed for every open.
        LDIR                          ; Copy the root name into the source table.
        LD HL,CSFCB+12                ; Clear extent and sequential state before open.
        LD B,24
        XOR A
.ROZERO: LD (HL),A
        INC HL
        DJNZ .ROZERO
        LD A,1                        ; The root counts against the 32-part bound.
        LD (CSINDEX+6),A              ; One source entry is now known.
        LD DE,CSFCB                   ; Open the root for the scan.
        LD C,15                       ; BDOS open-file function.
        CALL CSBDOS                   ; The adapter preserves IX and IY here.
        CP 255                        ; CP/M returns FF for an unsuccessful open.
        JR NZ,.ROOPEN                  ; Continue after a successful root open.
        JP CIEOPEN                     ; Report the normal source-open error.
.ROOPEN:
        LD A,1                        ; The root is active during the scan.
        LD (CSACTIVE),A               ; CSCLOSE can clean it up after a failure.
        CALL CIPARSE                   ; Consume only the leading include region.
        JP C,CIEPARSE                  ; A malformed form is a source error.
        XOR A                          ; Close the root before later part opens.
        LD (CSACTIVE),A               ; The scan no longer owns the root FCB.
        LD DE,CSFCB                   ; Close the root's sequential FCB.
        LD C,16                       ; BDOS close-file function.
        CALL CSBDOS                   ; CP/M close status is checked below.
        CP 255                        ; A failed close is an adapter error.
        JR NZ,.ROCLOSE                 ; Continue after a successful close.
        JP CIECLOSE                    ; Preserve the existing close error code.
.ROCLOSE:
        LD A,(CSINDEX+6)              ; Inspect the number of discovered parts.
        CP 1                          ; No direct include means root-only mode.
        JR NZ,.DEPS                   ; Entry one is the first dependency.
        LD A,1                        ; Phase one streams the root body.
        LD (CSINDEX+19),A             ; CIBYTE opens entry zero next.
        XOR A                          ; Entry zero is the root itself.
        LD (CSINDEX+18),A             ; Store that output index.
        LD A,1                         ; Match CSOPEN's successful-open result.
        OR A                           ; Return with carry clear.
        RET
.DEPS:
        XOR A                          ; Direct dependency phase is zero.
        LD (CSINDEX+19),A             ; CIBYTE advances to the root afterward.
        LD A,1                        ; Entry one is the first include.
        LD (CSINDEX+18),A             ; Store the next output table index.
        LD A,1                         ; Match CSOPEN's successful-open result.
        OR A                           ; Report a successfully prepared stream.
        RET

CIEOPEN:
        LD A,1                        ; Error 1 means the root could not open.
        JP CSFAIL                     ; Set the sticky error and terminal flag.
CIEPARSE:
        XOR A                          ; Do not report a second close failure.
        LD (CSACTIVE),A               ; The parser still owns the root FCB.
        LD DE,CSFCB                   ; Close a root left open by a syntax error.
        LD C,16                       ; BDOS close-file function.
        CALL CSBDOS                   ; Ignore the close status; syntax wins.
        LD A,(CSERROR)                ; Preserve an earlier read failure.
        OR A
        JR NZ,.KEEPERR
        LD A,5                        ; Error 5 covers malformed native includes.
.KEEPERR:
        JP CSFAIL                     ; Make the failure visible to CSBYTE/CSCLOSE.
CIECLOSE:
        LD A,(CSERROR)                ; A read error has priority over close status.
        OR A
        JR NZ,.CLOSEERR
        LD A,3                        ; Error 3 is a source close failure.
        LD (CSERROR),A
.CLOSEERR:
        LD A,1                        ; Keep the terminal callback convention.
        LD (CSDONE),A
        SCF
        RET

; -----------------------------------------------------------------------------
; CIBYTE -- byte callback for a native include stream
;
; Direct dependencies are streamed in table order, then the root is reopened
; and its leading source region is skipped.  One LF separates adjacent parts.
; -----------------------------------------------------------------------------
CIBYTE: LD A,(CSDONE)                  ; A terminal stream never reads again.
        OR A
        SCF
        RET NZ
        LD A,(CSINDEX+4)               ; A pending separator is returned first.
        OR A
        JR Z,.ACTIVE
        XOR A
        LD (CSINDEX+4),A               ; Consume the one-byte source boundary.
        LD A,10                        ; LF prevents tokens joining at a boundary.
        OR A
        RET
.ACTIVE:
        LD A,(CSINDEX+3)               ; Is a source part already open?
        OR A
        JR Z,.OPEN                     ; No part means select the next table entry.
        CALL CIPARTB                   ; Read one byte from its private DMA record.
        JR NC,.BYTEOK                   ; A normal source byte is ready for RINIT.
        LD A,(CSERROR)                 ; A failed read must not look like clean EOF.
        OR A
        JR Z,.PARTEND                   ; A clean boundary advances the table.
        SCF                            ; Preserve the error as a terminal callback.
        RET
.PARTEND:
        XOR A                          ; Release ownership before the close call.
        LD (CSINDEX+3),A               ; A failed close must not be retried by CSCLOSE.
        LD DE,CSFCB                   ; A clean part end closes the active FCB.
        LD C,16                       ; BDOS close-file function.
        CALL CSBDOS                   ; Errors become sticky source failures.
        CP 255
        JR NZ,.PCLOSE
        JP CIECLOSE
.PCLOSE:
        LD A,(CSINDEX+19)               ; Phase zero is the dependency list.
        OR A
        JR Z,.NEXTDEP
        CP 1                            ; Phase one is the root body.
        JR Z,.RDONE
        JR .RDONE                     ; No later phase is valid in this adapter.
.NEXTDEP:
        LD A,(CSINDEX+18)               ; Advance to the next named dependency.
        INC A
        LD D,A                          ; Retain the increment while reading count.
        LD A,(CSINDEX+6)
        CP D
        JR Z,.START                   ; All dependencies now precede the root.
        LD A,D
        LD (CSINDEX+18),A              ; Select the next dependency table entry.
        CALL CISEP                      ; Add LF only when the prior part needs it.
        JP CIBYTE
.START:
        LD A,1
        LD (CSINDEX+19),A              ; Phase one opens entry zero below.
        XOR A
        LD (CSINDEX+18),A
        CALL CISEP                      ; Add LF only when the prior part needs it.
        JP CIBYTE
.RDONE:
        LD A,1
        LD (CSDONE),A                  ; The complete source stream is finished.
        SCF
        RET
.OPEN:
        CALL CIEPART                   ; Open the table entry selected above.
        JR C,.CIRET                   ; Missing or invalid names are sticky.
        LD A,1
        LD (CSINDEX+3),A               ; Keep a reopened root closable during skip.
        LD A,(CSINDEX+19)              ; Only phase one needs the root skip count.
        CP 1
        JR NZ,.MARK
        CALL CISKIP                   ; Discard the masked include forms.
        JR C,.CIRET                   ; A truncated root is a source error.
.MARK:
        ; The active flag was set before root skipping so failures can close it.
        JP CIBYTE                      ; Return its first byte immediately.
.CIRET: RET
.BYTEOK:
        CALL CSMARKB               ; Reset coordinates before this part's byte.
        LD (CILAST),A                  ; Remember whether a boundary needs LF.
        JR .CIRET

; -----------------------------------------------------------------------------
; CIEPART -- open the selected source table entry
; -----------------------------------------------------------------------------
CIEPART:
        LD A,(CSINDEX+18)              ; Table index is bounded to 0..31.
        LD L,A
        LD H,0
        ADD HL,HL                      ; Two times the table index.
        ADD HL,HL                      ; Four times the table index.
        PUSH HL
        ADD HL,HL                      ; Eight times the table index.
        POP DE                         ; Add the four-times component.
        ADD HL,DE
        LD DE,CSSEEN                   ; Add the table base address.
        ADD HL,DE
        LD DE,CSFCB                   ; Copy the 12-byte FCB prefix.
        LD BC,12
        LDIR
        LD HL,CSFCB+12                ; Clear extent and allocation fields.
        LD B,24
        XOR A
.CLEAR: LD (HL),A
        INC HL
        DJNZ .CLEAR
        LD A,128                       ; Force a physical record read.
        LD (CSINDEX+12),A
        XOR A
        LD (CSINDEX+13),A             ; The selected part is not at EOF.
        LD A,(CSINDEX+18)
        LD (CSPARTNO),A               ; The lexer reports this table ordinal.
        LD A,1
        LD (CSPEND),A              ; The next real byte starts the part.
        XOR A
        LD (CILAST),A                 ; The part has not emitted a byte yet.
        LD DE,CSFCB                   ; Open the selected source file.
        LD C,15
        CALL CSBDOS
        CP 255
        JR NZ,.OPENED
        LD A,5                        ; Missing files are native source errors.
        JP CSFAIL
.OPENED: OR A
        RET

; -----------------------------------------------------------------------------
; CIPARTB -- read one byte from the active source FCB
; -----------------------------------------------------------------------------
CIPARTB: LD A,(CSINDEX+13)             ; A completed part stays at EOF.
        OR A
        SCF
        RET NZ
        LD A,(CSINDEX+12)              ; Index 128 requests another BDOS record.
        CP 128
        JR C,.FETCH
        LD DE,CSBUFFER                 ; Select the private 128-byte DMA record.
        LD C,26
        CALL CSBDOS
        LD DE,CSFCB                   ; Read the next sequential source record.
        LD C,20
        CALL CSBDOS
        OR A
        JR Z,.RECORD
        CP 1                            ; CP/M status one is physical EOF.
        JR Z,.END
        LD A,2                          ; Other statuses are read failures.
        JP CSFAIL
.RECORD: XOR A                         ; The first byte in a fresh record is zero.
.FETCH: LD E,A
        LD D,0
        INC A
        LD (CSINDEX+12),A              ; Consume exactly one cached byte.
        LD HL,CSBUFFER
        ADD HL,DE
        LD A,(HL)
        CP 26                           ; Ctrl-Z terminates a CP/M text part.
        JR Z,.END
        OR A
        RET
.END:   CALL CSMARKI                ; Empty parts still have a stable location.
        LD A,1
        LD (CSINDEX+13),A              ; Report a clean part boundary to CIBYTE.
        SCF
        RET

; -----------------------------------------------------------------------------
; CISKIP -- discard the root's leading include region
; -----------------------------------------------------------------------------
CISKIP:
        LD HL,(CSINDEX+16)             ; The parser retained a 16-bit byte count.
        LD A,H
        OR L
        RET Z
.SKIP:  PUSH HL                        ; CIPARTB uses HL for its record address.
        CALL CIPARTB                   ; A truncated header is malformed source.
        POP HL                         ; Restore the remaining skip count.
        JR NC,.SKBYTE
        LD A,(CSERROR)                 ; Preserve a physical read failure.
        OR A
        JR NZ,.SKERR
        LD A,5                          ; Clean EOF before the form is malformed.
        JP CSFAIL
.SKBYTE:
        DEC HL
        LD A,H
        OR L
        JR NZ,.SKIP
        OR A
        RET
.SKERR: SCF                            ; CSERROR already records the read failure.
        RET

; The external close path for mode two only closes the current output part.
CICLOSE:
        LD A,(CSINDEX+3)
        OR A
        JR Z,.CLDONE
        XOR A
        LD (CSINDEX+3),A
        LD DE,CSFCB
        LD C,16
        CALL CSBDOS
        CP 255
        JR NZ,.CLDONE
        LD A,(CSERROR)
        OR A
        JR NZ,.CLDONE
        LD A,3
        LD (CSERROR),A
.CLDONE: LD A,1
        LD (CSDONE),A
        LD A,(CSERROR)
        OR A
        RET Z
        SCF
        RET

; Set the boundary flag unless the part already ended in a line terminator.
CISEP:  LD A,(CILAST)
        CP 10
        RET Z
        CP 13
        RET Z
        LD A,1
        LD (CSINDEX+4),A
        RET
