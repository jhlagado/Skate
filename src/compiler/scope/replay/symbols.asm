; Scope replay reconstruction of interned symbol spellings.
; Entry point: REC_NAME.
; Included in compiler order by ../replay.asm.

; Restore LX_BUF/LX_LEN for an interned symbol retained in a replay event.
REC_NAME:
        LD A,H                    ; Strip the symbol subtype from the identity.
        AND 01FH
        LD H,A
        LD B,H                    ; Preserve the thirteen-bit identity in BC.
        LD C,L
        ADD HL,HL                 ; Two identity bytes are not enough: use stride three.
        ADD HL,BC
        PUSH HL                   ; Retain the descriptor offset while reading the context.
        LD HL,(RD_SYMS)
        LD E,(HL)                 ; Descriptor table base, low byte.
        INC HL
        LD D,(HL)                 ; Descriptor table base, high byte.
        POP HL
        ADD HL,DE                 ; Address the selected three-byte descriptor.
        LD E,(HL)                 ; Packed-name offset, low byte.
        INC HL
        LD D,(HL)                 ; Packed-name offset, high byte.
        INC HL
        LD A,(HL)                 ; Symbol spelling length is the third descriptor byte.
        LD (LX_LEN),A
        LD C,A                    ; LDIR takes the recovered length in the low byte.
        XOR A
        LD B,A                    ; The lexer limits symbol spellings to 31 bytes.
        PUSH DE                   ; Preserve the packed-name offset across context lookup.
        LD HL,(RD_SYMS)
        INC HL
        INC HL
        INC HL
        INC HL
        LD E,(HL)                 ; Symbol pool base, low byte.
        INC HL
        LD D,(HL)                 ; Symbol pool base, high byte.
        POP HL                    ; Recover the packed-name offset.
        ADD HL,DE                 ; HL now points at the permanent spelling bytes.
        LD DE,LX_BUF               ; The permanent spelling is the source; LX_BUF receives it.
        LDIR                       ; Recreate the normal lexer-buffer contract.
        RET
