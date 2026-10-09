;=============================================================================
;  ASO v1 bounded materializer
;=============================================================================
;
;  PUB_ASO has produced a complete ASO stage.  The COM publisher keeps the
;  output file open while this reader replays the stage once per bounded image
;  window.  Each pass reopens SPL, applies every IMAGE and PATCH record that
;  intersects its window, and then appends that window to the COM stage.
;=============================================================================

; Replay the ASO stage through bounded windows and append each window to COM.
ASO_COM:
        LD HL,0100H                ; Every pass begins at the CP/M load origin.
        LD (.WIN_FROM),HL          ; .WIN_FROM is the inclusive window start.
.WINDOW:
        LD HL,(PUB_SIZE)           ; The compiler measured the complete payload.
        LD DE,0100H                ; Convert that length to an absolute endpoint.
        ADD HL,DE
        LD (ASO_STOP),HL           ; Every replay pass validates this same endpoint.
        LD A,(ASO_TOP)
        OR A
        JR NZ,.MORE                 ; A top byte means the endpoint is $10000.
        LD DE,(.WIN_FROM)
        OR A
        SBC HL,DE
        JR Z,.DONE                 ; All windows have been written.
        JP C,.BAD                  ; A wrapped or reversed image is invalid.
.MORE:
        LD HL,(.WIN_FROM)
        LD DE,W_IMGEND-W_IMAGE     ; Keep one complete window in compiler memory.
        ADD HL,DE
        JR C,.CEILING               ; A final window may end at the address ceiling.
        LD A,(ASO_TOP)
        OR A
        JR NZ,.FULL_WIN             ; Every low-word window precedes $10000.
        LD DE,(ASO_STOP)
        OR A
        SBC HL,DE
        JR C,.FULL_WIN             ; A full window ends before the image endpoint.
        LD HL,(ASO_STOP)           ; The final window is shorter or exactly full.
        LD (.WIN_END),HL
        XOR A
        LD (ASO_CEIL),A            ; The final low-word window ends below $10000.
        JR .APPLY
.FULL_WIN:
        LD HL,(.WIN_FROM)
        LD DE,W_IMGEND-W_IMAGE
        ADD HL,DE
        LD (.WIN_END),HL
        XOR A
        LD (ASO_CEIL),A            ; This window ends below $10000.
        JR .APPLY
.CEILING:
        LD HL,(ASO_STOP)            ; The remaining image is shorter than a window.
        LD (.WIN_END),HL
        LD A,(ASO_TOP)
        LD (ASO_CEIL),A            ; The final exact window may end at $10000.
.APPLY:
        CALL .PASS                 ; Reopen and replay the ASO stage for this window.
        RET C
        LD HL,(.WIN_END)           ; Append the materialized window to COM.
        LD DE,(.WIN_FROM)
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        LD HL,W_IMAGE
        CALL PUB_SEND
        RET C
        LD HL,(.WIN_END)           ; The next pass starts at this exclusive end.
        LD A,(ASO_TOP)
        OR A
        JR Z,.ADVANCE
        LD A,H
        OR L
        JR Z,.DONE                 ; A zero low word with top one is $10000.
.ADVANCE:
        LD (.WIN_FROM),HL
        JP .WINDOW
.DONE:
        XOR A
        RET

; Read and validate one complete ASO stream, retaining only this window's data.
.PASS:
        CALL PUB_SPL               ; Select the private spool stage name.
        LD HL,PUB_FCB              ; Point CPM_OPEN at the ASO stage.
        CALL CPM_OPEN              ; A missing stage is a publication failure.
        JP C,.BAD                  ; Do not publish a COM without ASO input.
        CALL .MAGIC                ; Validate magic, version, origin and fill.
        JP C,.BAD                  ; A malformed header is not compiler output.
        LD HL,0100H                ; Canonical IMAGE records start at origin.
        LD (ASO_FILL),HL           ; Track contiguous IMAGE coverage this pass.
        XOR A
        LD (ASO_FULL),A            ; Coverage begins below the address ceiling.
.RECORD:
        CALL .READ                 ; Read the next ASO operation kind.
        JP C,.BAD                  ; EOF before END means that the stream is broken.
        OR A                       ; Kind zero is the successful END record.
        JP Z,.END_REC              ; Consume END before closing the input.
        CP 1                       ; Kind one denotes an IMAGE record.
        JR Z,.IMAGE                ; IMAGE records may contain up to 128 bytes.
        CP 2                       ; Kind two denotes a PATCH record.
        JP NZ,.BAD                 ; No other kind is emitted by PUB_ASO.
        LD (ST_FKIND),A            ; Remember that this record is a PATCH.
        JR .REC_HEAD               ; Share the address and length reader.
.IMAGE:
        LD A,1                     ; Remember that this record is an IMAGE.
        LD (ST_FKIND),A
.REC_HEAD:
        CALL .READ                 ; Read the record address low byte.
        JP C,.BAD
        LD (ASO_ADDR),A
        CALL .READ                 ; Read the record address high byte.
        JP C,.BAD
        LD (ASO_ADDR+1),A
        CALL .READ                 ; Read the one-byte payload length.
        JP C,.BAD
        LD (ASO_LEN),A
        OR A                       ; Empty records are not canonical ASO.
        JP Z,.BAD
        XOR A
        LD (ASO_LEN+1),A
        LD A,(ST_FKIND)
        CP 1
        JR NZ,.PATCH               ; PATCH records are limited to two bytes.
        LD A,(ASO_LEN)
        CP 129
        JP NC,.BAD                 ; Reject an oversized IMAGE payload.
        LD HL,(ASO_ADDR)           ; IMAGE records must cover the image in order.
        LD DE,(ASO_FILL)
        OR A
        SBC HL,DE
        JP NZ,.BAD                 ; Reject gaps, overlaps and descending images.
        JR .BOUNDS
.PATCH:
        LD A,(ASO_LEN)
        CP 3
        JP NC,.BAD                 ; PATCH records replace at most one word.
        CALL .ENDPOINT           ; Compute its endpoint, including $10000.
        JP C,.BAD
        LD A,(ASO_FULL)
        OR A
        JR NZ,.BOUNDS               ; Every endpoint fits below a complete image.
        LD A,(ASO_OVER)
        OR A
        JP NZ,.BAD                  ; A wrapped PATCH precedes no short IMAGE.
        LD HL,(ASO_EDGE)
        LD DE,(ASO_FILL)
        OR A
        SBC HL,DE
        JR C,.BOUNDS               ; A contained PATCH is valid before later IMAGE.
        JR Z,.BOUNDS               ; Equality reaches the current IMAGE high water.
        JP .BAD                    ; A PATCH may not target a future IMAGE byte.
.BOUNDS:
        CALL .ENDPOINT           ; Reject prefixes and unrepresentable endpoints.
        JP C,.BAD
        LD A,(ASO_TOP)
        OR A
        JR NZ,.COPY                 ; The complete image may end at $10000.
        LD A,(ASO_OVER)
        OR A
        JP NZ,.BAD                  ; A wrapped record exceeds a short image.
        LD HL,(ASO_EDGE)
        LD DE,(ASO_STOP)
        OR A
        SBC HL,DE
        JR C,.COPY                 ; A record ending below the image end fits.
        JR Z,.COPY                 ; The final IMAGE may end exactly at the endpoint.
        JP .BAD                    ; A greater endpoint exceeds the image.

; Compute the current record's exclusive endpoint.  The returned low word is
; saved in ASO_EDGE and ASO_OVER records the one permitted wrap to $10000.
.ENDPOINT:
        LD HL,(ASO_ADDR)
        LD DE,0100H
        OR A
        SBC HL,DE
        JR C,.END_BAD              ; No record may address CP/M's prefix.
        LD HL,(ASO_ADDR)
        LD DE,(ASO_LEN)
        ADD HL,DE
        JR NC,.END_LOW
        LD A,H
        OR L
        JR NZ,.END_BAD             ; A nonzero wrap exceeds the address space.
        LD A,(ASO_TOP)
        OR A
        JR Z,.END_BAD              ; Only a complete image may reach $10000.
        LD A,1
        LD (ASO_OVER),A
        LD (ASO_EDGE),HL
        OR A
        RET
.END_LOW:
        XOR A
        LD (ASO_OVER),A
        LD (ASO_EDGE),HL
        OR A
        RET
.END_BAD:
        SCF
        RET

; Consume one record and copy only bytes inside the current output window.
.COPY:
        LD A,(ASO_LEN)
        OR A
        JR Z,.REC_DONE
        CALL .READ                 ; Read the payload even when it is out of range.
        JP C,.BAD
        LD (ST_BYTE),A             ; Keep the byte while comparing its address.
        LD HL,(ASO_ADDR)
        LD DE,(.WIN_FROM)
        OR A
        SBC HL,DE
        JR C,.SKIP                 ; The payload byte is before this window.
        LD A,(ASO_CEIL)
        OR A
        JR NZ,.INSIDE              ; A top-one end includes every low-word byte.
        LD HL,(ASO_ADDR)
        LD DE,(.WIN_END)
        OR A
        SBC HL,DE
        JR NC,.SKIP                ; The payload byte is after this window.
.INSIDE:
        LD HL,(ASO_ADDR)
        LD DE,(.WIN_FROM)
        OR A
        SBC HL,DE                   ; Recompute the byte's offset when end wrapped.
        LD DE,W_IMAGE
        ADD HL,DE
        LD A,(ST_BYTE)
        LD (HL),A                   ; Apply IMAGE or PATCH data to the window.
.SKIP:
        LD HL,(ASO_ADDR)
        INC HL
        LD (ASO_ADDR),HL            ; Advance the record cursor.
        LD HL,ASO_LEN
        DEC (HL)
        JR .COPY
.REC_DONE:
        LD A,(ST_FKIND)
        CP 1
        JP NZ,.RECORD               ; PATCH records do not advance IMAGE coverage.
        LD HL,(ASO_ADDR)
        LD (ASO_FILL),HL           ; Publish the next contiguous IMAGE address.
        LD A,(ASO_OVER)
        LD (ASO_FULL),A            ; Carry the exact-end marker into coverage.
        JP .RECORD

; Consume and validate both ASO END endpoints, then close this pass's input.
.END_REC:
        LD A,(ASO_FULL)
        LD B,A
        LD A,(ASO_TOP)
        CP B
        JP NZ,.BAD                 ; IMAGE coverage must reach the same endpoint.
        LD HL,(ASO_FILL)
        LD DE,(ASO_STOP)
        OR A
        SBC HL,DE
        JP NZ,.BAD                 ; END is valid only after complete IMAGE data.
        CALL .END_WORD             ; Compare high-water's low word.
        JP C,.BAD
        JP NZ,.BAD                 ; It must match the compiler's image endpoint.
        CALL .READ                 ; Read the high-water endpoint top byte.
        JP C,.BAD
        LD B,A
        LD A,(ASO_TOP)
        CP B
        JP NZ,.BAD
        CALL .END_WORD             ; Compare the final-cursor low word.
        JR C,.BAD
        JR NZ,.BAD                 ; Both END words describe the same image.
        CALL .READ                 ; Read the final-cursor endpoint top byte.
        JR C,.BAD
        LD B,A
        LD A,(ASO_TOP)
        CP B
        JR NZ,.BAD
        CALL CPM_ENDR              ; A clean close completes this replay pass.
        RET C
        XOR A
        RET

; Validate the fixed seven-byte header emitted by PUB_ASO.
.MAGIC:
        LD A,'A'
        CALL .EXPECT
        JR C,.BAD
        JR NZ,.BAD
        LD A,'S'
        CALL .EXPECT
        JR C,.BAD
        JR NZ,.BAD
        LD A,'O'
        CALL .EXPECT
        JR C,.BAD
        JR NZ,.BAD
        LD A,1
        CALL .EXPECT
        JR C,.BAD
        JR NZ,.BAD
        XOR A
        CALL .EXPECT
        JR C,.BAD
        JR NZ,.BAD
        LD A,1
        CALL .EXPECT
        JR C,.BAD
        JR NZ,.BAD
        XOR A
        CALL .EXPECT               ; The current emitter uses zero fill.
        JR C,.BAD
        JR NZ,.BAD
        XOR A
        RET

; Read one header byte and compare it with the expected value in A.
.EXPECT:
        LD (ST_BYTE),A             ; Keep the expected byte across CPM_READ.
        CALL .READ
        RET C
        LD B,A
        LD A,(ST_BYTE)
        CP B
        RET

; Read a little-endian END word and compare it with ASO_STOP.
.END_WORD:
        CALL .READ
        RET C
        LD (ASO_ADDR),A
        CALL .READ
        RET C
        LD (ASO_ADDR+1),A
        LD HL,(ASO_ADDR)
        LD DE,(ASO_STOP)
        OR A
        SBC HL,DE
        RET

; Return one byte from the ASO input without changing the transport contract.
.READ:
        JP CPM_READ                ; CPM_READ sets carry at EOF or transport error.

; Close a failed input and report a publication error to PUB_MAIN.
.BAD:
        CALL CPM_ENDR              ; Preserve the transport's sticky error.
        LD HL,M_OUTPUT             ; A malformed stage is an output failure.
        LD (ST_ERROR),HL
        SCF
        RET

; Window bounds for the current replay pass.
.WIN_FROM:   DW 0
.WIN_END:  DW 0
