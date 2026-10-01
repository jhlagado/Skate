; CP/M source stream opening and mode selection.
; CSOPEN: HL -> a 12-byte drive/name/type prefix; carry clear means success.
; The stream accepts one text file or one ordered .SKM manifest with one active
; part. CP/M text ends at physical EOF or the first Ctrl-Z byte. The caller
; rejects wildcards, has no file already open, closes the file and checks
; CSERROR before publishing output.
; Private FCB and DMA state makes the adapter static and non-reentrant; IX and
; IY are preserved by the public entry points.

CSOPEN: LD DE,CSFCB       ; Retain the name before clearing sequential state.
        LD BC,12
        LDIR
        LD HL,CSFCB+9      ; A .SKM command names an ordered source manifest.
        LD A,(HL)
        CP 'S'
        JR NZ,.FLAT
        INC HL
        LD A,(HL)
        CP 'K'
        JR NZ,.FLAT
        INC HL
        LD A,(HL)
        CP 'M'
        JR Z,.PKINIT
        CP '8'             ; A .SK8 source may carry leading include forms.
        JP Z,CIINIT        ; The native adapter resolves those before reading.
.FLAT: XOR A
        LD HL,CSFCB             ; A flat source still needs a printable table entry.
        LD DE,CSSEEN            ; Entry zero names the standalone source file.
        LD BC,12
        LDIR
        XOR A
        LD (CSINDEX+1),A
        XOR A
        LD (CSERROR),A
        LD (CSPARTNO),A         ; Flat input is source-table part zero.
        INC A
        LD (CSPEND),A        ; The first byte starts a fresh coordinate range.
        XOR A
        LD (CSACTIVE),A
        LD (CSINDEX+2),A
        LD (CSINDEX+3),A
        LD (CSDONE),A
        LD HL,CSFCB+12
        LD B,24          ; Extent, allocation and current-record fields start zero.
.ZERO: LD (HL),A
        INC HL
        DJNZ .ZERO
        LD A,128
        LD (CSINDEX),A   ; Force a record read on the first byte request.
        LD DE,CSFCB
        LD C,15          ; BDOS open file.
        CALL CSBDOS
        CP 255
        JR Z,.OPFAIL
        LD A,1
        LD (CSACTIVE),A
        OR A
        RET
.PKINIT:
        XOR A
        LD (CSERROR),A
        LD (CSPARTNO),A         ; The manifest assigns the first part when opened.
        INC A                   ; No part has produced a location yet.
        LD (CSPEND),A
        XOR A
        LD (CSACTIVE),A
        LD (CSDONE),A
        LD (CSINDEX+1),A
        LD (CSINDEX+2),A
        LD (CSINDEX+3),A
        LD (CSINDEX+4),A
        LD (CSINDEX+5),A
        LD (CSINDEX+6),A
        LD (CSINDEX+14),A
        LD (CSINDEX+15),A
        LD HL,CSFCB+12
        LD B,24
.ZERO2:
        LD (HL),A
        INC HL
        DJNZ .ZERO2
        LD HL,CSFCB
        LD DE,CSMANFCB
        LD BC,36
        LDIR                       ; Keep the manifest FCB while parts use CSFCB.
        LD HL,CSFCB
        LD B,36
        XOR A
.ZERO3:
        LD (HL),A
        INC HL
        DJNZ .ZERO3
        LD A,128
        LD (CSINDEX+7),A
        LD DE,CSMANFCB
        LD C,15
        CALL CSBDOS
        CP 255
        JR Z,.OPFAIL
        LD A,1
        LD (CSINDEX+1),A
        LD (CSINDEX+2),A
        OR A
        RET
.OPFAIL:
        LD A,1           ; Adapter error 1: open failed.
        JR CSFAIL
