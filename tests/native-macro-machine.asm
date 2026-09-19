%INCLUDE "origin.asm"
%INCLUDE "../compiler/lexer.asm"
%INCLUDE "../compiler/decimal.asm"
%INCLUDE "../compiler/interner.asm"
%INCLUDE "../compiler/reader.asm"
%INCLUDE "../compiler/native-macro.asm"
%INCLUDE "../compiler/native-macro-expand.asm"
%INCLUDE "../compiler/native-macro-state.asm"
%INCLUDE "../compiler/native-macro-dotted.asm"
%INCLUDE "../compiler/native-scope.asm"

; In-memory source callback for the arena proof.
NMSOURCE:
        LD HL,(NMSPTR)
        LD DE,(NMSEND)
        OR A
        SBC HL,DE
        SCF
        RET Z
        LD HL,(NMSPTR)
        LD A,(HL)
        INC HL
        LD (NMSPTR),HL
        OR A
        RET
NMSPTR: DW 0
NMSEND: DW 0
