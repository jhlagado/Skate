; Scope publication of slot addresses.
; Entry points: PUB_ADDR and PUB_CELL.
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
