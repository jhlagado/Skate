; Return the predefined procedure kind for ST_SYMID, or zero for an ordinary name.
; Symbol references carry subtype bits in the high byte; the interner index is
; the remaining thirteen bits and addresses a three-byte descriptor.
GLB_PRIM:
        LD HL,(ST_SYMID)           ; Copy the encoded symbol identity locally.
        LD A,H                     ; Remove the reference subtype from the index.
        AND 1FH
        LD H,A
        LD D,H                     ; Multiply the thirteen-bit index by descriptor size.
        LD E,L
        ADD HL,HL                  ; Two bytes per descriptor so far.
        ADD HL,DE                  ; Add one more byte for the three-byte stride.
        LD DE,W_SYMTAB             ; Address the selected symbol descriptor.
        ADD HL,DE
        LD E,(HL)                  ; Descriptor bytes zero and one hold pool offset.
        INC HL
        LD D,(HL)
        INC HL
        LD C,(HL)                  ; Descriptor byte two holds spelling length.
        LD HL,W_SYMBUF             ; Add the offset to the symbol spelling pool.
        ADD HL,DE
        LD (ST_NAME),HL            ; Keep the spelling while trying each name.
        LD A,C
        LD (ST_NAMEN),A            ; Keep the length beside the spelling pointer.
        LD HL,NAME_TAB             ; Try every kind/spelling record.
        LD B,GLB_ROWS              ; Count the records instead of using a terminator.
.TRY:
        LD A,(HL)                  ; Hold the candidate kind for a full match.
        LD (ST_PRIM),A
        INC HL
        LD DE,(ST_NAME)            ; DE walks the interned source spelling.
        LD A,(ST_NAMEN)            ; C counts the source bytes still unmatched.
        LD C,A
.NEXT:
        LD A,(HL)                  ; One spelling byte: a character or a fragment.
        AND 7FH
        CP 20H
        JR NC,.PLAIN
        PUSH HL                    ; Find fragment A, keeping the record and B.
        PUSH BC
        LD B,A
        LD HL,NAME_FRG
.FIND:
        DEC B
        JR Z,.FRAG
.PASS:
        BIT 7,(HL)                 ; Pass one fragment.
        INC HL
        JR Z,.PASS
        JR .FIND
.FRAG:
        POP BC
.FRAG_CH:
        LD A,(HL)                  ; Match the fragment's characters in turn.
        CALL .CHAR
        JR NZ,.FRAG_NO
        BIT 7,(HL)
        INC HL
        JR Z,.FRAG_CH
        POP HL                     ; The fragment matched; continue the record.
        JR .STEP
.FRAG_NO:
        POP HL
        JR .MISS
.PLAIN:
        CALL .CHAR
        JR NZ,.MISS
.STEP:
        BIT 7,(HL)                 ; Bit 7 ends the spelling.
        INC HL
        JR Z,.NEXT
        LD A,C                     ; A match must use the whole source name.
        OR A
        JR NZ,.ROW
        LD A,(ST_PRIM)             ; Every byte matched: return the nonzero kind.
        RET
.MISS:
        BIT 7,(HL)                 ; Skip the rest of the spelling.
        INC HL
        JR Z,.MISS
.ROW:
        DJNZ .TRY                  ; Try every record before classifying as ordinary.
        XOR A                      ; Ordinary names receive no primitive mark.
        RET

; Compare character A (bit 7 ignored) with the next source byte at DE, counted
; by C.  Return Z and step past it on a match, NZ otherwise.
.CHAR:
        AND 7FH
        INC C                      ; No source byte is left: NZ, as A is not zero.
        DEC C
        JR Z,.NONE
        EX DE,HL
        CP (HL)
        EX DE,HL
        RET NZ
        INC DE
        DEC C
        CP A
        RET
.NONE:
        OR A
        RET

GLB_ROWS  EQU 130                ; Records in NAME_TAB.
