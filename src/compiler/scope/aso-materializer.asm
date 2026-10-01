;=============================================================================
;  ASO v1 bounded materializer
;=============================================================================
;
;  SCAWRITE has produced a complete ASO stage.  The COM publisher keeps the
;  output file open while this reader replays the stage once per bounded image
;  window.  Each pass reopens SPL, applies every IMAGE and PATCH record that
;  intersects its window, and then appends that window to the COM stage.
;=============================================================================

; Replay the ASO stage through bounded windows and append each window to COM.
SCAMULTI:
        LD HL,0100H                ; Every pass begins at the CP/M load origin.
        LD (SCAWIN),HL             ; SCAWIN is the inclusive window start.
SCAMWLP:
        LD HL,(SCIMGL)             ; The compiler measured the complete payload.
        LD DE,0100H                ; Convert that length to an absolute endpoint.
        ADD HL,DE
        LD (SCAENDP),HL            ; Every replay pass validates this same endpoint.
        LD A,(SCAETOP)
        OR A
        JR NZ,SCAMHAS               ; A top byte means the endpoint is $10000.
        LD DE,(SCAWIN)
        OR A
        SBC HL,DE
        JR Z,SCAMDONE              ; All windows have been written.
        JP C,SCAMBAD               ; A wrapped or reversed image is invalid.
SCAMHAS:
        LD HL,(SCAWIN)
        LD DE,SCEND-SCIMG          ; Keep one complete window in compiler memory.
        ADD HL,DE
        JR C,SCAMLAST               ; A final window may end at the address ceiling.
        LD A,(SCAETOP)
        OR A
        JR NZ,SCAMSETW              ; Every low-word window precedes $10000.
        LD DE,(SCAENDP)
        OR A
        SBC HL,DE
        JR C,SCAMSETW              ; A full window ends before the image endpoint.
        LD HL,(SCAENDP)            ; The final window is shorter or exactly full.
        LD (SCAWEND),HL
        XOR A
        LD (SCAWTOP),A             ; The final low-word window ends below $10000.
        JR SCAMOPEN
SCAMSETW:
        LD HL,(SCAWIN)
        LD DE,SCEND-SCIMG
        ADD HL,DE
        LD (SCAWEND),HL
        XOR A
        LD (SCAWTOP),A             ; This window ends below $10000.
        JR SCAMOPEN
SCAMLAST:
        LD HL,(SCAENDP)             ; The remaining image is shorter than a window.
        LD (SCAWEND),HL
        LD A,(SCAETOP)
        LD (SCAWTOP),A             ; The final exact window may end at $10000.
SCAMOPEN:
        CALL SCAMPASS              ; Reopen and replay the ASO stage for this window.
        RET C
        LD HL,(SCAWEND)            ; Append the materialized window to COM.
        LD DE,(SCAWIN)
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        LD HL,SCIMG
        CALL SCSTREAM
        RET C
        LD HL,(SCAWEND)            ; The next pass starts at this exclusive end.
        LD A,(SCAETOP)
        OR A
        JR Z,SCAMCONT
        LD A,H
        OR L
        JR Z,SCAMDONE              ; A zero low word with top one is $10000.
SCAMCONT:
        LD (SCAWIN),HL
        JP SCAMWLP
SCAMDONE:
        XOR A
        RET

; Read and validate one complete ASO stream, retaining only this window's data.
SCAMPASS:
        CALL SCSPL                 ; Select the private spool stage name.
        LD HL,SCFCB                ; Point CTOPENR at the ASO stage.
        CALL CTOPENR               ; A missing stage is a publication failure.
        JP C,SCAMBAD               ; Do not publish a COM without ASO input.
        CALL SCAMHDR               ; Validate magic, version, origin and fill.
        JP C,SCAMBAD               ; A malformed header is not compiler output.
        LD HL,0100H                ; Canonical IMAGE records start at origin.
        LD (SCAIMG),HL             ; Track contiguous IMAGE coverage this pass.
        XOR A
        LD (SCAIMGT),A             ; Coverage begins below the address ceiling.
SCAMNEXT:
        CALL SCAMBYTE              ; Read the next ASO operation kind.
        JP C,SCAMBAD               ; EOF before END means that the stream is broken.
        OR A                       ; Kind zero is the successful END record.
        JP Z,SCAMEND               ; Consume END before closing the input.
        CP 1                       ; Kind one denotes an IMAGE record.
        JR Z,SCAMREC               ; IMAGE records may contain up to 128 bytes.
        CP 2                       ; Kind two denotes a PATCH record.
        JP NZ,SCAMBAD              ; No other kind is emitted by SCAWRITE.
        LD (SCFKIND),A             ; Remember that this record is a PATCH.
        JR SCAMHEAD                ; Share the address and length reader.
SCAMREC:
        LD A,1                     ; Remember that this record is an IMAGE.
        LD (SCFKIND),A
SCAMHEAD:
        CALL SCAMBYTE              ; Read the record address low byte.
        JP C,SCAMBAD
        LD (SCAADDR),A
        CALL SCAMBYTE              ; Read the record address high byte.
        JP C,SCAMBAD
        LD (SCAADDR+1),A
        CALL SCAMBYTE              ; Read the one-byte payload length.
        JP C,SCAMBAD
        LD (SCACHUNK),A
        OR A                       ; Empty records are not canonical ASO.
        JP Z,SCAMBAD
        XOR A
        LD (SCACHUNK+1),A
        LD A,(SCFKIND)
        CP 1
        JR NZ,SCAMPTST             ; PATCH records are limited to two bytes.
        LD A,(SCACHUNK)
        CP 129
        JP NC,SCAMBAD              ; Reject an oversized IMAGE payload.
        LD HL,(SCAADDR)            ; IMAGE records must cover the image in order.
        LD DE,(SCAIMG)
        OR A
        SBC HL,DE
        JP NZ,SCAMBAD              ; Reject gaps, overlaps and descending images.
        JP SCAMADDR
SCAMPTST:
        LD A,(SCACHUNK)
        CP 3
        JP NC,SCAMBAD              ; PATCH records replace at most one word.
        CALL SCAMEOK             ; Compute its endpoint, including $10000.
        JP C,SCAMBAD
        LD A,(SCAIMGT)
        OR A
        JR NZ,SCAMADDR              ; Every endpoint fits below a complete image.
        LD A,(SCAEPTOP)
        OR A
        JP NZ,SCAMBAD               ; A wrapped PATCH precedes no short IMAGE.
        LD HL,(SCAEPTR)
        LD DE,(SCAIMG)
        OR A
        SBC HL,DE
        JR C,SCAMADDR              ; A contained PATCH is valid before later IMAGE.
        JR Z,SCAMADDR              ; Equality reaches the current IMAGE high water.
        JP SCAMBAD                 ; A PATCH may not target a future IMAGE byte.
SCAMADDR:
        CALL SCAMEOK             ; Reject prefixes and unrepresentable endpoints.
        JP C,SCAMBAD
        LD A,(SCAETOP)
        OR A
        JR NZ,SCAMCOPY              ; The complete image may end at $10000.
        LD A,(SCAEPTOP)
        OR A
        JP NZ,SCAMBAD               ; A wrapped record exceeds a short image.
        LD HL,(SCAEPTR)
        LD DE,(SCAENDP)
        OR A
        SBC HL,DE
        JR C,SCAMCOPY              ; A record ending below the image end fits.
        JR Z,SCAMCOPY              ; The final IMAGE may end exactly at the endpoint.
        JP SCAMBAD                 ; A greater endpoint exceeds the image.

; Compute the current record's exclusive endpoint.  The returned low word is
; saved in SCAEPTR and SCAEPTOP records the one permitted wrap to $10000.
SCAMEOK:
        LD HL,(SCAADDR)
        LD DE,0100H
        OR A
        SBC HL,DE
        JR C,SCAMEBAD              ; No record may address CP/M's prefix.
        LD HL,(SCAADDR)
        LD DE,(SCACHUNK)
        ADD HL,DE
        JR NC,SCAMELOW
        LD A,H
        OR L
        JR NZ,SCAMEBAD             ; A nonzero wrap exceeds the address space.
        LD A,(SCAETOP)
        OR A
        JR Z,SCAMEBAD              ; Only a complete image may reach $10000.
        LD A,1
        LD (SCAEPTOP),A
        LD (SCAEPTR),HL
        OR A
        RET
SCAMELOW:
        XOR A
        LD (SCAEPTOP),A
        LD (SCAEPTR),HL
        OR A
        RET
SCAMEBAD:
        SCF
        RET

; Consume one record and copy only bytes inside the current output window.
SCAMCOPY:
        LD A,(SCACHUNK)
        OR A
        JP Z,SCAMRECD
        CALL SCAMBYTE              ; Read the payload even when it is out of range.
        JP C,SCAMBAD
        LD (SCBTMP),A              ; Keep the byte while comparing its address.
        LD HL,(SCAADDR)
        LD DE,(SCAWIN)
        OR A
        SBC HL,DE
        JR C,SCAMNBYT              ; The payload byte is before this window.
        LD A,(SCAWTOP)
        OR A
        JR NZ,SCAMIN               ; A top-one end includes every low-word byte.
        LD HL,(SCAADDR)
        LD DE,(SCAWEND)
        OR A
        SBC HL,DE
        JR NC,SCAMNBYT             ; The payload byte is after this window.
SCAMIN:
        LD HL,(SCAADDR)
        LD DE,(SCAWIN)
        OR A
        SBC HL,DE                   ; Recompute the byte's offset when end wrapped.
        LD DE,SCIMG
        ADD HL,DE
        LD A,(SCBTMP)
        LD (HL),A                   ; Apply IMAGE or PATCH data to the window.
SCAMNBYT:
        LD HL,(SCAADDR)
        INC HL
        LD (SCAADDR),HL             ; Advance the record cursor.
        LD HL,SCACHUNK
        DEC (HL)
        JR SCAMCOPY
SCAMRECD:
        LD A,(SCFKIND)
        CP 1
        JP NZ,SCAMNEXT              ; PATCH records do not advance IMAGE coverage.
        LD HL,(SCAADDR)
        LD (SCAIMG),HL             ; Publish the next contiguous IMAGE address.
        LD A,(SCAEPTOP)
        LD (SCAIMGT),A             ; Carry the exact-end marker into coverage.
        JP SCAMNEXT

; Consume and validate both ASO END endpoints, then close this pass's input.
SCAMEND:
        LD A,(SCAIMGT)
        LD B,A
        LD A,(SCAETOP)
        CP B
        JP NZ,SCAMBAD              ; IMAGE coverage must reach the same endpoint.
        LD HL,(SCAIMG)
        LD DE,(SCAENDP)
        OR A
        SBC HL,DE
        JP NZ,SCAMBAD              ; END is valid only after complete IMAGE data.
        CALL SCAMWORD              ; Compare high-water's low word.
        JP C,SCAMBAD
        JP NZ,SCAMBAD              ; It must match the compiler's image endpoint.
        CALL SCAMBYTE              ; Read the high-water endpoint top byte.
        JP C,SCAMBAD
        LD B,A
        LD A,(SCAETOP)
        CP B
        JP NZ,SCAMBAD
        CALL SCAMWORD              ; Compare the final-cursor low word.
        JP C,SCAMBAD
        JP NZ,SCAMBAD              ; Both END words describe the same image.
        CALL SCAMBYTE              ; Read the final-cursor endpoint top byte.
        JP C,SCAMBAD
        LD B,A
        LD A,(SCAETOP)
        CP B
        JP NZ,SCAMBAD
        CALL CTCLOSER              ; A clean close completes this replay pass.
        RET C
        XOR A
        RET

; Validate the fixed seven-byte header emitted by SCAWRITE.
SCAMHDR:
        LD A,'A'
        CALL SCAMCHK
        JP C,SCAMBAD
        JP NZ,SCAMBAD
        LD A,'S'
        CALL SCAMCHK
        JP C,SCAMBAD
        JP NZ,SCAMBAD
        LD A,'O'
        CALL SCAMCHK
        JP C,SCAMBAD
        JP NZ,SCAMBAD
        LD A,1
        CALL SCAMCHK
        JP C,SCAMBAD
        JP NZ,SCAMBAD
        XOR A
        CALL SCAMCHK
        JP C,SCAMBAD
        JP NZ,SCAMBAD
        LD A,1
        CALL SCAMCHK
        JP C,SCAMBAD
        JP NZ,SCAMBAD
        XOR A
        CALL SCAMCHK               ; The current emitter uses zero fill.
        JP C,SCAMBAD
        JP NZ,SCAMBAD
        XOR A
        RET

; Read one header byte and compare it with the expected value in A.
SCAMCHK:
        LD (SCBTMP),A              ; Keep the expected byte across CTREAD.
        CALL SCAMBYTE
        RET C
        LD B,A
        LD A,(SCBTMP)
        CP B
        RET

; Read a little-endian END word and compare it with SCAENDP.
SCAMWORD:
        CALL SCAMBYTE
        RET C
        LD (SCAADDR),A
        CALL SCAMBYTE
        RET C
        LD (SCAADDR+1),A
        LD HL,(SCAADDR)
        LD DE,(SCAENDP)
        OR A
        SBC HL,DE
        RET

; Return one byte from the ASO input without changing the transport contract.
SCAMBYTE:
        JP CTREAD                  ; CTREAD sets carry at EOF or transport error.

; Close a failed input and report a publication error to SCOUT.
SCAMBAD:
        CALL CTCLOSER              ; Preserve the transport's sticky error.
        LD HL,SCOUTTXT             ; A malformed stage is an output failure.
        LD (SCERRPTR),HL
        SCF
        RET

; Window bounds for the current replay pass.
SCAWIN:   DW 0
SCAWEND:  DW 0
