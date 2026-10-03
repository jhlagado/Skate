; Scope publication of procedure descriptors and slot addresses.
; Entry points: SCPDESC, SCPDWRD, SCADDR and SCFQCH.
; Patch byte three of every emitted descriptor with the shared slot extent.
; Descriptors were written after their bodies; bytes two and three are
; rewritten together because PATCH records carry a whole word.
SCPDESC:
        LD A,(SCPCOUNT)            ; No procedures leave nothing to patch.
        OR A
        RET Z
        LD C,0                     ; C is the descriptor index; SINKPTCH keeps BC.
SCPDLOOP:
        LD L,C
        LD H,0
        ADD HL,HL
        LD DE,SCPADDR
        ADD HL,DE
        LD E,(HL)                  ; DE is the descriptor's image address.
        INC HL
        LD D,(HL)
        INC DE                     ; The patched word is bytes two and three.
        INC DE
        PUSH DE
        LD L,C
        LD H,0
        LD DE,SCPARITY
        ADD HL,DE
        LD E,(HL)                  ; Byte two keeps the published arity.
        LD A,(SCLOCMAX)            ; Every environment has the bounded slot extent.
        LD D,A
        POP HL
        CALL SINKPTCH
        RET C
        INC C
        LD A,(SCPCOUNT)
        CP C
        JR NZ,SCPDLOOP
        XOR A
        RET

; Write an absolute descriptor word through the guarded image emitter.
SCPDWRD:
        LD (SCTARG),HL
        LD A,L
        CALL SINKBYTE
        RET C
        LD HL,(SCTARG)
        LD A,H
        JP SINKBYTE

; Convert a staged four-byte-slot address into its absolute COM address.
SCADDR:
        LD L,A                     ; Widen the slot index to a word.
        LD H,0                     ; The high byte is zero for all current slots.
        ADD HL,HL                  ; Form two times the slot number.
        ADD HL,HL                  ; Form four times the slot number.
        ADD HL,DE                  ; Add the selected staged data base.
        JP SCABS                   ; Convert the staged pointer to COM address.

SCFQCH:
        LD DE,(SCQBASE)            ; Select the quoted-list cache base.
        JP SCFADDR                  ; Share the four-byte slot arithmetic.
