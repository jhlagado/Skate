; Load the checked runtime provider into the staged output image.
;
; The resident compiler carries the provider's length and service addresses,
; but not its executable bytes. CP/M installs the provider as SKATE.RT; this
; loader copies exactly the assembled logical image before source parsing.

SCLOADRT:
        LD HL,SCRTFNM              ; Select the fixed provider file on the active drive.
        CALL CTOPENR               ; Open it through the binary transport adapter.
        JR C,SCRTFAIL              ; A missing or unreadable provider aborts setup.
        LD HL,SCIMG                ; The staged image begins at the NOBJ payload base.
        LD BC,SRTLEN               ; Copy the exact ATOM image extent, excluding padding.
SCRTREAD:
        LD A,B                     ; Test the high byte of the remaining count first.
        OR C                       ; Zero means every provider byte has been copied.
        JP Z,SCRTCLS                ; Close the provider before accepting the image.
        PUSH HL                    ; CTREAD uses HL for its private DMA cursor.
        PUSH BC                    ; CTREAD may use BC while fetching a record.
        CALL CTREAD                ; Read one binary provider byte.
        POP BC                     ; Restore the remaining logical byte count.
        POP HL                     ; Restore the staged destination cursor.
        JR C,SCRTFAIL              ; A short file or transport error is a setup failure.
        LD (HL),A                  ; Publish the byte only after CTREAD succeeds.
        INC HL                     ; Advance to the next staged provider position.
        DEC BC                     ; Account for the byte just copied.
        JR SCRTREAD                ; Continue until the metadata length is exhausted.
SCRTCLS:
        CALL CTCLOSER              ; Preserve the transport's sticky close status.
        JR C,SCRTFAIL              ; A failed close cannot qualify the provider.
        XOR A                      ; Carry clear reports a complete runtime image.
        RET
SCRTFAIL:
        CALL CTCLOSER              ; Closing twice is harmless and preserves the first error.
        LD HL,SCRTTXT              ; Select the public provider diagnostic.
        LD (SCERRPTR),HL           ; SCFAIL prints this message and publishes nothing.
        SCF                        ; Carry distinguishes provider failure from success.
        RET

SCRTFNM: DB 0,"SKATE   ","RT "     ; CP/M 8.3 name: SKATE.RT.
SCRTTXT: DB "RUNTIME FILE",13,10,"$"
