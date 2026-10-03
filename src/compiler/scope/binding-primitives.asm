; Return the predefined procedure kind for SCID, or zero for an ordinary name.
; Symbol references carry subtype bits in the high byte; the interner index is
; the remaining thirteen bits and addresses a three-byte descriptor.
SCPLOOK:
        LD HL,(SCID)               ; Copy the encoded symbol identity locally.
        LD A,H                     ; Remove the reference subtype from the index.
        AND 1FH
        LD H,A
        LD D,H                     ; Multiply the thirteen-bit index by descriptor size.
        LD E,L
        ADD HL,HL                  ; Two bytes per descriptor so far.
        ADD HL,DE                  ; Add one more byte for the three-byte stride.
        LD DE,SCNAMEDS             ; Address the selected symbol descriptor.
        ADD HL,DE
        LD E,(HL)                  ; Descriptor bytes zero and one hold pool offset.
        INC HL
        LD D,(HL)
        INC HL
        LD C,(HL)                  ; Descriptor byte two holds spelling length.
        LD HL,SCNAMEPL             ; Add the offset to the symbol spelling pool.
        ADD HL,DE
        LD (SCPNADR),HL            ; Keep the spelling while trying each name.
        LD A,C
        LD (SCPNLEN),A             ; Keep the length beside the spelling pointer.
        LD HL,SCPRIMTB             ; Scan every length/kind/spelling record.
        LD B,SCPRIMN               ; Count the records instead of using a terminator.
SCPPTRY:
        LD A,(HL)                  ; Read the candidate spelling length.
        LD C,A                     ; Keep it while comparing the source name.
        LD A,(SCPNLEN)             ; Compare it with the source spelling length.
        CP C
        JR NZ,SCPPADV              ; A different length skips this record.
        INC HL                     ; The kind follows the length byte.
        LD A,(HL)
        LD (SCPKIND),A             ; Hold the candidate kind for a full match.
        INC HL                     ; HL now points at the candidate spelling.
        LD DE,(SCPNADR)            ; DE walks the interned source spelling.
SCPPCMP:
        LD A,(DE)                  ; Compare one source byte with the candidate.
        CP (HL)
        JR NZ,SCPPMISM             ; Skip the rest of this record on a mismatch.
        INC DE
        INC HL
        DEC C                      ; C counts the bytes still to compare.
        JR NZ,SCPPCMP
        LD A,(SCPKIND)             ; Every byte matched: return the nonzero kind.
        RET
SCPPADV:
        INC HL                     ; Skip the candidate length.
        INC HL                     ; Skip the candidate kind; C bytes of spelling remain.
SCPPMISM:
        LD E,C                     ; Skip the unexamined remainder of the name.
        LD D,0
        ADD HL,DE                  ; HL now addresses the next record's length.
        DJNZ SCPPTRY               ; Try every record before classifying as ordinary.
        XOR A                      ; Ordinary names receive no primitive mark.
        RET

SCPRIMN  EQU 93                 ; Records in SCPRIMTB.
