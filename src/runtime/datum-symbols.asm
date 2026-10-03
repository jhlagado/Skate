; Bounded datum symbol interning.  The datum reader's symbol tokeniser is
; in datum-symbol-tokens.asm, part of the optional I/O module; interning
; stays in the core because string->symbol uses it.
;
; Compiler-emitted symbols are length-prefixed literals.  The compiler publishes
; a directory of their absolute addresses in SRTSYMB..SRTSYME.  New spellings
; are copied into the fixed arena below the reader frames; those records remain
; pinned for the life of the program and are not managed heap objects.

SRTSYA EQU SRTDRFE                ; Arena follows the reader's frame band.
SRTSYAE EQU SRTMKBS               ; Keep the collector worklist untouched.

; Intern the spelling at HL with length BC and return tag four plus its pointer.
SRTSYMIN:
        LD (SRTSYINP),HL
        LD (SRTSYINL),BC
        CALL SRTSYDIR              ; Static literals have identity precedence.
        JR C,SRTSYTAG
        CALL SRTSYARN            ; Search or append in the pinned arena.
SRTSYTAG:
        LD A,4                     ; Symbols use the existing literal tag.
        OR A                       ; A successful interning operation clears carry.
        RET

; Search the published count-and-pointer directory for an equal spelling.
SRTSYDIR:
        LD HL,(SRTSYMB)
        LD DE,(SRTSYME)
        OR A
        SBC HL,DE
        RET Z                       ; An equal zero range means no directory.
        LD HL,(SRTSYMB)
        LD A,(HL)                   ; The first byte is the symbol count.
        LD (SRTSYDC),A
        INC HL
        OR A
        RET Z
SRTSYDL:
        LD E,(HL)                   ; Read one absolute literal pointer.
        INC HL
        LD D,(HL)
        INC HL
        PUSH HL                     ; Preserve the next directory pointer.
        PUSH DE                     ; Preserve the candidate pointer across comparison.
        CALL SRTSYCMP
        JR Z,SRTSYDNM
        POP DE
        POP HL
        EX DE,HL                    ; Return the matching literal pointer.
        SCF
        RET
SRTSYDNM:
        POP DE
        POP HL
        LD A,(SRTSYDC)
        DEC A
        LD (SRTSYDC),A
        JR NZ,SRTSYDL
        OR A
        RET

; Compare the input spelling with the length-prefixed record at DE.
SRTSYCMP:
        LD A,(DE)
        LD C,A
        LD A,(SRTSYINL)
        CP C
        JR NZ,SRTSYCMN
        LD B,A
        INC DE
        LD HL,(SRTSYINP)
        LD A,B
        OR A
        JR Z,SRTSYYES
SRTSYCL:
        LD A,(DE)
        CP (HL)
        JR NZ,SRTSYCMN
        INC DE
        INC HL
        DJNZ SRTSYCL
SRTSYYES:
        LD A,1
        OR A                       ; Make the successful comparison nonzero.
        SCF
        RET
SRTSYCMN:
        XOR A
        RET

; Search the pinned arena, then append a complete new record if needed.
SRTSYARN:
        LD HL,(SRTSYAP)
        LD A,H
        OR L
        JR NZ,SRTSYAOK
        LD HL,SRTSYA
        LD (SRTSYAP),HL
SRTSYAOK:
        LD HL,SRTSYA
SRTSYAL:
        LD DE,(SRTSYAP)             ; Reload the end after each comparison.
        OR A
        SBC HL,DE
        JR NC,SRTSYNEW
        ADD HL,DE                 ; Restore the current record cursor.
        PUSH HL
        EX DE,HL                  ; The comparator receives this record in DE.
        CALL SRTSYCMP
        JR Z,SRTSYANM
        POP HL
        SCF
        RET
SRTSYANM:
        POP HL
        LD A,(HL)
        INC A                     ; Skip this record's length byte and payload.
        LD C,A
        LD B,0
        ADD HL,BC
        JR SRTSYAL
SRTSYNEW:
        LD HL,(SRTSYINL)
        INC HL                    ; One length byte plus the spelling bytes.
        LD DE,(SRTSYAP)
        ADD HL,DE
        LD DE,SRTSYAE
        OR A
        SBC HL,DE
        JR C,SRTSYFIT               ; A record ending below the limit fits.
        JR Z,SRTSYFIT               ; Equality fills the final byte exactly.
        JP SRTERROR                 ; A record beyond the limit is a capacity error.
SRTSYFIT:
        LD HL,(SRTSYAP)
        LD (SRTSYRES),HL
        LD A,(SRTSYINL)
        LD (HL),A
        INC HL
        EX DE,HL                  ; DE is the destination byte cursor.
        LD HL,(SRTSYINP)
        LD BC,(SRTSYINL)
        LD A,B
        OR C
        JR Z,SRTSYCOP
        LDIR                      ; The bounds check precedes the complete copy.
SRTSYCOP:
        LD HL,(SRTSYRES)
        LD DE,1
        ADD HL,DE
        LD DE,(SRTSYINL)
        ADD HL,DE
        LD (SRTSYAP),HL
        LD HL,(SRTSYRES)
        RET

; Reset the arena pointer at program startup.  Native tests also use lazy init.
SRTSYINI:
        LD HL,SRTSYA
        LD (SRTSYAP),HL
        RET

SRTSYDC:    DB 0                   ; Remaining entries during directory search.
SRTSYINP:   DW 0                   ; Borrowed input spelling address.
SRTSYINL:   DW 0                   ; Borrowed input spelling length.
SRTSYRES:   DW 0                   ; Newly found or appended record address.
SRTSYAP:    DW 0                   ; Next free byte in the pinned arena.
