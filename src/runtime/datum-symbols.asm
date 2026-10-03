; Bounded datum symbol interning.  The datum reader's symbol tokeniser is
; in datum-symbol-tokens.asm, part of the optional I/O module; interning
; stays in the core because string->symbol uses it.
;
; Compiler-emitted symbols are length-prefixed literals.  The compiler publishes
; a directory of their absolute addresses in DR_DIR..DR_DEND.  New spellings
; are copied into the fixed arena below the reader frames; those records remain
; pinned for the life of the program and are not managed heap objects.

DR_ARENA EQU RT_DRFHI             ; Arena follows the reader's frame band.
DR_LIMIT EQU RT_GCLO              ; Keep the collector worklist untouched.

; Intern the spelling at HL with length BC and return tag four plus its pointer.
DR_FIND:
        LD (DR_NAME),HL
        LD (DR_SPAN),BC
        CALL .STATIC               ; Static literals have identity precedence.
        JR C,.TAG
        CALL DR_PIN              ; Search or append in the pinned arena.
.TAG:
        LD A,4                     ; Symbols use the existing literal tag.
        OR A                       ; A successful interning operation clears carry.
        RET

; Search the published count-and-pointer directory for an equal spelling.
.STATIC:
        LD HL,(DR_DIR)
        LD DE,(DR_DEND)
        OR A
        SBC HL,DE
        RET Z                       ; An equal zero range means no directory.
        LD HL,(DR_DIR)
        LD A,(HL)                   ; The first byte is the symbol count.
        LD (DR_LEFT),A
        INC HL
        OR A
        RET Z
.DIR_LOOP:
        LD E,(HL)                   ; Read one absolute literal pointer.
        INC HL
        LD D,(HL)
        INC HL
        PUSH HL                     ; Preserve the next directory pointer.
        PUSH DE                     ; Preserve the candidate pointer across comparison.
        CALL DR_EQUAL
        JR Z,.DIR_NEXT
        POP DE
        POP HL
        EX DE,HL                    ; Return the matching literal pointer.
        SCF
        RET
.DIR_NEXT:
        POP DE
        POP HL
        LD A,(DR_LEFT)
        DEC A
        LD (DR_LEFT),A
        JR NZ,.DIR_LOOP
        OR A
        RET

; Compare the input spelling with the length-prefixed record at DE.
DR_EQUAL:
        LD A,(DE)
        LD C,A
        LD A,(DR_SPAN)
        CP C
        JR NZ,.NO
        LD B,A
        INC DE
        LD HL,(DR_NAME)
        LD A,B
        OR A
        JR Z,.YES
.LOOP:
        LD A,(DE)
        CP (HL)
        JR NZ,.NO
        INC DE
        INC HL
        DJNZ .LOOP
.YES:
        LD A,1
        OR A                       ; Make the successful comparison nonzero.
        SCF
        RET
.NO:
        XOR A
        RET

; Search the pinned arena, then append a complete new record if needed.
DR_PIN:
        LD HL,(DR_TOP)
        LD A,H
        OR L
        JR NZ,.READY
        LD HL,DR_ARENA
        LD (DR_TOP),HL
.READY:
        LD HL,DR_ARENA
.LOOP:
        LD DE,(DR_TOP)              ; Reload the end after each comparison.
        OR A
        SBC HL,DE
        JR NC,.NEW
        ADD HL,DE                 ; Restore the current record cursor.
        PUSH HL
        EX DE,HL                  ; The comparator receives this record in DE.
        CALL DR_EQUAL
        JR Z,.NEXT
        POP HL
        SCF
        RET
.NEXT:
        POP HL
        LD A,(HL)
        INC A                     ; Skip this record's length byte and payload.
        LD C,A
        LD B,0
        ADD HL,BC
        JR .LOOP
.NEW:
        LD HL,(DR_SPAN)
        INC HL                    ; One length byte plus the spelling bytes.
        LD DE,(DR_TOP)
        ADD HL,DE
        LD DE,DR_LIMIT
        OR A
        SBC HL,DE
        JR C,.FITS                  ; A record ending below the limit fits.
        JR Z,.FITS                  ; Equality fills the final byte exactly.
        JP ERROR                    ; A record beyond the limit is a capacity error.
.FITS:
        LD HL,(DR_TOP)
        LD (DR_FOUND),HL
        LD A,(DR_SPAN)
        LD (HL),A
        INC HL
        EX DE,HL                  ; DE is the destination byte cursor.
        LD HL,(DR_NAME)
        LD BC,(DR_SPAN)
        LD A,B
        OR C
        JR Z,.COPIED
        LDIR                      ; The bounds check precedes the complete copy.
.COPIED:
        LD HL,(DR_FOUND)
        LD DE,1
        ADD HL,DE
        LD DE,(DR_SPAN)
        ADD HL,DE
        LD (DR_TOP),HL
        LD HL,(DR_FOUND)
        RET

; Reset the arena pointer at program startup.  Native tests also use lazy init.
DR_INIT:
        LD HL,DR_ARENA
        LD (DR_TOP),HL
        RET

DR_LEFT:    DB 0                   ; Remaining entries during directory search.
DR_NAME:   DW 0                    ; Borrowed input spelling address.
DR_SPAN:   DW 0                    ; Borrowed input spelling length.
DR_FOUND:   DW 0                   ; Newly found or appended record address.
DR_TOP:    DW 0                    ; Next free byte in the pinned arena.
