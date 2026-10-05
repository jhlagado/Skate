; CP/M delete and rename, used only by the compiler's publication.
; Entry points: CPM_ERA and CPM_REN.  They share CPM_RFCB with the transport.
; Delete a file named by the caller.  CP/M reports FF when no matching file
; exists; cleanup treats that as success so stale stage names are harmless.
CPM_ERA:
        LD DE,CPM_RFCB
        LD BC,12
        LDIR
        CALL CPM_WIPE
        LD DE,CPM_RFCB
        LD C,19
        CALL CPM_BDOS
        OR A
        JR Z,.GOOD
        CP 255
        JR Z,.GOOD
        SCF
        RET
.GOOD:
        XOR A
        RET

; Rename one CP/M file.  The BDOS rename FCB contains the old prefix in its
; first 16 bytes and the new prefix at offset 16.  The two prefixes are kept
; separate from the stream FCBs so a failed publication cannot corrupt them.
CPM_REN:
        PUSH HL
        PUSH DE
        CALL CPM_WIPE
        POP DE
        POP HL
        PUSH DE
        LD DE,CPM_RFCB
        LD BC,12
        LDIR
        POP HL
        LD DE,CPM_RFCB+16
        LD BC,12
        LDIR
        LD DE,CPM_RFCB
        LD C,23
        CALL CPM_BDOS
        OR A
        RET Z
        SCF
        RET

; Clear the non-prefix bytes shared by delete and rename FCBs.
CPM_WIPE:
        XOR A
        LD HL,CPM_RFCB+12
        LD B,24
.FILL:
        LD (HL),A
        INC HL
        DJNZ .FILL
        RET
