; Transport probe, assembled only with PROBE set (see docs/value-contract.md).
; Each value consumer calls PROBE on entry with the value in A:CHL.  C is
; payload byte 2 and may hold anything for an exact integer (tag 3); it
; must be zero for every other tag.  A mismatch prints "PROBE site caller" in hex, where site is the
; consumer's entry and caller is the consumer's return address, then corrects
; C so one missing producer reports once rather than at every consumer.
; Every register and flag is preserved.
PROBE:
        PUSH AF
        PUSH HL
        PUSH DE
        CP 3
        JR Z,.DONE                 ; An integer owns all of byte 2.
        LD E,0
        LD A,C
        CP E
        JR Z,.DONE
        PUSH BC
        PUSH DE
        LD HL,.TEXT
        CALL .STRING
        LD HL,10                   ; DE, BC, DE, HL, AF, then PROBE's return.
        ADD HL,SP
        LD E,(HL)
        INC HL
        LD D,(HL)
        DEC DE                     ; Step back over the CALL PROBE.
        DEC DE
        DEC DE
        CALL .WORD
        LD A,' '
        CALL .CHAR
        LD HL,12                   ; The consumer's own return address.
        ADD HL,SP
        LD E,(HL)
        INC HL
        LD D,(HL)
        CALL .WORD
        LD A,13
        CALL .CHAR
        LD A,10
        CALL .CHAR
        POP DE
        POP BC
        LD C,E                     ; Continue with the expected byte.
.DONE:
        POP DE
        POP HL
        POP AF
        RET

.STRING:
        LD A,(HL)
        OR A
        RET Z
        CALL .CHAR
        INC HL
        JR .STRING

.WORD:
        LD A,D
        CALL .BYTE
        LD A,E
.BYTE:
        PUSH AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL .NIBBLE
        POP AF
.NIBBLE:
        AND 0FH
        ADD A,90H                  ; Classic nibble-to-ASCII sequence.
        DAA
        ADC A,40H
        DAA
.CHAR:
        PUSH BC
        PUSH DE
        PUSH HL
        PUSH IX                    ; Some BIOSes do not keep IX and IY.
        PUSH IY
        LD E,A
        LD C,2                     ; BDOS console output.
        CALL 5
        POP IY
        POP IX
        POP HL
        POP DE
        POP BC
        RET

.TEXT:  DB "PROBE ",0
