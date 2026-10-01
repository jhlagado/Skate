; Native ASO v1 writer.
;
; The compiler emits one logical byte at a time, but this writer keeps only a
; single 128-byte IMAGE run in RAM.  Fixups are written in the order in which
; they are resolved, so later IMAGE runs may legally follow PATCH records.

; Open the temporary ASO stage and write its fixed header.
SINKOPEN:
        XOR A
        LD (SCACTIV),A          ; No output owns the stage before CTOPENW.
        LD (SCARUNC),A            ; The pending IMAGE run starts empty.
        LD (SCPCET),A             ; The output cursor begins below $10000.
        LD (SCAETOP),A            ; The ASO high-water endpoint begins at origin.
        LD HL,0100H
        LD (SCAREND),HL        ; The first IMAGE byte starts at the origin.
        LD (SCAHIGH),HL          ; No byte has advanced the high-water mark yet.
        CALL SCSPL                ; Build the private SPL stage name.
        LD HL,SCFCB
        CALL CTOPENW              ; Create the tentative ASO file.
        JP C,SCAERR
        LD A,1
        LD (SCACTIV),A          ; Cleanup now owns the open stage.
        LD HL,SCAHEAD
        LD (SCAHPTR),HL
        LD A,7
        LD (SCACHUNK),A
SCAHLP:
        LD A,(SCACHUNK)
        OR A
        JR Z,SCAHOK
        LD HL,(SCAHPTR)
        LD A,(HL)
        INC HL
        LD (SCAHPTR),HL
        CALL CTWRITE
        JR C,SCAHFAIL
        LD HL,SCACHUNK
        DEC (HL)
        JR SCAHLP
SCAHOK:
        XOR A
        RET
SCAHFAIL:
        CALL SINKABRT
        JP SCAERR

; Flush the pending IMAGE run as one canonical ASO record.
SCARUNFL:
        LD A,(SCARUNC)
        OR A
        RET Z
        LD A,1                    ; ASO record kind one denotes IMAGE.
        CALL CTWRITE
        RET C
        LD HL,(SCARADD)
        CALL SCAWORD
        RET C
        LD A,(SCARUNC)
        CALL CTWRITE
        RET C
        LD A,(SCARUNC)
        LD (SCACHUNK),A
        LD HL,SCIMG
        LD (SCAWPTR),HL
SCARLP:
        LD A,(SCACHUNK)
        OR A
        JR Z,SCARDONE
        LD HL,(SCAWPTR)
        LD A,(HL)
        INC HL
        LD (SCAWPTR),HL
        CALL CTWRITE
        RET C
        LD HL,SCACHUNK
        DEC (HL)
        JR SCARLP
SCARDONE:
        XOR A
        LD (SCARUNC),A
        RET

; Write a little-endian word held in HL through the CTWRITE byte sink.
SCAWORD:
        LD (SCAWORDV),HL
        LD A,(SCAWORDV)
        CALL CTWRITE
        RET C
        LD A,(SCAWORDV+1)
        JP CTWRITE

; Finish the ASO stream with matching high-water and final-cursor endpoints.
SINKEND:
        CALL SCARUNFL
        RET C
        XOR A                    ; ASO record kind zero denotes END.
        CALL CTWRITE
        RET C
        LD HL,(SCAHIGH)
        CALL SCAWORD
        RET C
        LD A,(SCAETOP)           ; Preserve an exact $10000 exclusive endpoint.
        CALL CTWRITE
        RET C
        LD HL,(SCPC)
        CALL SCAWORD
        RET C
        LD A,(SCPCET)
        CALL CTWRITE
        RET C
        CALL CTCLOSEW
        JR C,SINKECFL
        LD A,0
        LD (SCACTIV),A
        RET
SINKECFL:
        SCF
        RET

; Close and delete a partial ASO stage after a parse or transport failure.
SINKABRT:
        LD A,(SCACTIV)
        OR A
        RET Z
        CALL CTCLOSEW
        CALL SCSPL
        LD HL,SCFCB
        CALL CTDELETE
        XOR A
        LD (SCACTIV),A
        RET

; Mark a transport failure as an output error for the command diagnostic.
SCAERR:
        LD HL,SCOUTTXT
        LD (SCERRPTR),HL
        SCF
        RET

; Writer state and the one bounded IMAGE run.
SCACTIV:   DB 0
SCABYTE:   DB 0
SCARUNC:   DB 0
SCFPET:    DB 0                   ; Top byte of the pending PATCH endpoint.
SCAWORDV:  DW 0
SCARADD:    DW 0
SCAREND:    DW 0
SCAHIGH:    DW 0
SCAHPTR:    DW 0
SCAWPTR:    DW 0
