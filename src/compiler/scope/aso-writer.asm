; Native ASO v1 writer.
;
; The compiler emits one logical byte at a time, but this writer keeps only a
; single 128-byte IMAGE run in RAM.  Fixups are written in the order in which
; they are resolved, so later IMAGE runs may legally follow PATCH records.

; Open the temporary ASO stage and write its fixed header.
ASO_OPEN:
        XOR A
        LD (ASO_LIVE),A         ; No output owns the stage before CPM_MAKE.
        LD (ASO_CNT),A            ; The pending IMAGE run starts empty.
        LD (ST_PCHI),A            ; The output cursor begins below $10000.
        LD (ASO_TOP),A            ; The ASO high-water endpoint begins at origin.
        LD HL,0100H
        LD (ASO_END),HL        ; The first IMAGE byte starts at the origin.
        LD (ASO_HIGH),HL         ; No byte has advanced the high-water mark yet.
        CALL PUB_SPL              ; Build the private SPL stage name.
        LD HL,PUB_FCB
        CALL CPM_MAKE             ; Create the tentative ASO file.
        JP C,ASO_FAIL
        LD A,1
        LD (ASO_LIVE),A         ; Cleanup now owns the open stage.
        LD HL,ASO_HEAD
        LD (ASO_HDRP),HL
        LD A,7
        LD (ASO_LEN),A
.HEADER:
        LD A,(ASO_LEN)
        OR A
        JR Z,.DONE
        LD HL,(ASO_HDRP)
        LD A,(HL)
        INC HL
        LD (ASO_HDRP),HL
        CALL CPM_PUT
        JR C,.FAIL
        LD HL,ASO_LEN
        DEC (HL)
        JR .HEADER
.DONE:
        XOR A
        RET
.FAIL:
        CALL ASO_DROP
        JP ASO_FAIL

; Flush the pending IMAGE run as one canonical ASO record.
ASO_EMIT:
        LD A,(ASO_CNT)
        OR A
        RET Z
        LD A,1                    ; ASO record kind one denotes IMAGE.
        CALL CPM_PUT
        RET C
        LD HL,(ASO_RUN)
        CALL ASO_WORD
        RET C
        LD A,(ASO_CNT)
        CALL CPM_PUT
        RET C
        LD A,(ASO_CNT)
        LD (ASO_LEN),A
        LD HL,W_IMAGE
        LD (ASO_RUNP),HL
.LOOP:
        LD A,(ASO_LEN)
        OR A
        JR Z,.DONE
        LD HL,(ASO_RUNP)
        LD A,(HL)
        INC HL
        LD (ASO_RUNP),HL
        CALL CPM_PUT
        RET C
        LD HL,ASO_LEN
        DEC (HL)
        JR .LOOP
.DONE:
        XOR A
        LD (ASO_CNT),A
        RET

; Write a little-endian word held in HL through the CPM_PUT byte sink.
ASO_WORD:
        LD (ASO_TMP),HL
        LD A,(ASO_TMP)
        CALL CPM_PUT
        RET C
        LD A,(ASO_TMP+1)
        JP CPM_PUT

; Finish the ASO stream with matching high-water and final-cursor endpoints.
ASO_DONE:
        CALL ASO_EMIT
        RET C
        XOR A                    ; ASO record kind zero denotes END.
        CALL CPM_PUT
        RET C
        LD HL,(ASO_HIGH)
        CALL ASO_WORD
        RET C
        LD A,(ASO_TOP)           ; Preserve an exact $10000 exclusive endpoint.
        CALL CPM_PUT
        RET C
        LD HL,(ST_PC)
        CALL ASO_WORD
        RET C
        LD A,(ST_PCHI)
        CALL CPM_PUT
        RET C
        CALL CPM_ENDW
        JR C,.FAIL
        LD A,0
        LD (ASO_LIVE),A
        RET
.FAIL:
        SCF
        RET

; Close and delete a partial ASO stage after a parse or transport failure.
ASO_DROP:
        LD A,(ASO_LIVE)
        OR A
        RET Z
        CALL CPM_ENDW
        CALL PUB_SPL
        LD HL,PUB_FCB
        CALL CPM_ERA
        XOR A
        LD (ASO_LIVE),A
        RET

; Mark a transport failure as an output error for the command diagnostic.
ASO_FAIL:
        LD HL,M_OUTPUT
        LD (ST_ERROR),HL
        SCF
        RET

; Writer state and the one bounded IMAGE run.
ASO_LIVE:   DB 0
ASO_BYTE:   DB 0
ASO_CNT:   DB 0
SINK_TOP:    DB 0                 ; Top byte of the pending PATCH endpoint.
ASO_TMP:  DW 0
ASO_RUN:    DW 0
ASO_END:    DW 0
ASO_HIGH:    DW 0
ASO_HDRP:    DW 0
ASO_RUNP:    DW 0
