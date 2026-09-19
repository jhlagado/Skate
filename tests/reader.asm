%INCLUDE "origin.asm"
%INCLUDE "../src/compiler/lexer.asm"
%INCLUDE "../src/compiler/decimal.asm"
%INCLUDE "../src/compiler/interner.asm"
%INCLUDE "../src/compiler/reader.asm"
; Test input adapter. Every call destroys the permitted general registers.
RFSOURCE:
    LD HL,(RFPTR)
    LD DE,(RFLIMIT)
    OR A
    SBC HL,DE
    SCF
    RET Z
    LD HL,(RFPTR)
    LD A,(HL)
    INC HL
    LD (RFPTR),HL
    LD BC,055AAH
    LD DE,0AA55H
    LD HL,09669H
    OR A
    RET
RFWORK:
RFPTR: DW 0
RFLIMIT: DW 0
RFWEND:
