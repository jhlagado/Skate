; Scope publication of procedure descriptors and slot addresses.
; Entry points: PUB_DESC, .WORD, PUB_ADDR and PUB_CELL.
; Patch byte three of every emitted descriptor with the shared slot extent.
; Descriptors were written after their bodies; bytes two and three are
; rewritten together because PATCH records carry a whole word.
PUB_DESC:
        LD A,(ST_PROCS)            ; No procedures leave nothing to patch.
        OR A
        RET Z
        LD C,0                     ; C is the descriptor index; SINK_FIX keeps BC.
.LOOP:
        LD L,C
        LD H,0
        ADD HL,HL
        LD DE,W_PDESC
        ADD HL,DE
        LD E,(HL)                  ; DE is the descriptor's image address.
        INC HL
        LD D,(HL)
        INC DE                     ; The patched word is bytes two and three.
        INC DE
        PUSH DE
        LD L,C
        LD H,0
        LD DE,W_PARITY
        ADD HL,DE
        LD E,(HL)                  ; Byte two keeps the published arity.
        LD A,(ST_LMAX)             ; Every environment has the bounded slot extent.
        LD D,A
        POP HL
        CALL SINK_FIX
        RET C
        INC C
        LD A,(ST_PROCS)
        CP C
        JR NZ,.LOOP
        XOR A
        RET

; Write an absolute descriptor word through the guarded image emitter.
.WORD:
        LD (PUB_ABS),HL
        LD A,L
        CALL SINK_PUT
        RET C
        LD HL,(PUB_ABS)
        LD A,H
        JP SINK_PUT

; Convert a staged four-byte-slot address into its absolute COM address.
PUB_ADDR:
        LD L,A                     ; Widen the slot index to a word.
        LD H,0                     ; The high byte is zero for all current slots.
        ADD HL,HL                  ; Form two times the slot number.
        ADD HL,HL                  ; Form four times the slot number.
        ADD HL,DE                  ; Add the selected staged data base.
        JP BR_ABS                  ; Convert the staged pointer to COM address.

PUB_CELL:
        LD DE,(QUO_BASE)           ; Select the quoted-list cache base.
        JP PUB_SLOT                 ; Share the four-byte slot arithmetic.
