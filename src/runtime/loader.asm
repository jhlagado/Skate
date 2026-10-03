; Load the checked runtime provider into the staged output image.
;
; The resident compiler carries the provider's length and service addresses,
; but not its executable bytes. CP/M installs the provider as SKATE.RT; this
; loader copies exactly the assembled logical image before source parsing.

RT_COPY:
        LD HL,.NAME                ; Select the fixed provider file on the active drive.
        CALL CPM_OPEN              ; Open it through the binary transport adapter.
        JR C,.FAIL                 ; A missing or unreadable provider aborts setup.
        LD BC,(ST_RTLEN)           ; Copy the selected prefix of the runtime image.
.READ:
        LD A,B                     ; Test the high byte of the remaining count first.
        OR C                       ; Zero means every provider byte has been copied.
        JP Z,.CLOSE                 ; Close the provider before accepting the image.
        PUSH BC                    ; CPM_READ may use BC while fetching a record.
        CALL CPM_READ              ; Read one binary provider byte.
        POP BC                     ; Restore the remaining logical byte count.
        JR C,.FAIL                 ; A short file or transport error is a setup failure.
        CALL SINKBYTE              ; Publish the byte through the ASO image sink.
        RET C                      ; A spool failure is a setup failure.
        DEC BC                     ; Account for the byte just copied.
        JR .READ                   ; Continue until the metadata length is exhausted.
.CLOSE:
        CALL CPM_ENDR              ; Preserve the transport's sticky close status.
        JR C,.FAIL                 ; A failed close cannot qualify the provider.
        XOR A                      ; Carry clear reports a complete runtime image.
        RET
.FAIL:
        CALL CPM_ENDR              ; Closing twice is harmless and preserves the first error.
        LD HL,.MSG                 ; Select the public provider diagnostic.
        LD (ST_ERROR),HL           ; .FAIL prints this message and publishes nothing.
        SCF                        ; Carry distinguishes provider failure from success.
        RET

.NAME: DB 0,"SKATE   ","RT "       ; CP/M 8.3 name: SKATE.RT.
.MSG: DB "RUNTIME FILE",13,10,"$"
