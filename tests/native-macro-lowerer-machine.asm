%INCLUDE "origin.asm"
%INCLUDE "../compiler/native-procedure.asm"
%INCLUDE "../compiler/native-procedure-quoted.asm"
%INCLUDE "../compiler/native-nobj-dynamic.asm"
%INCLUDE "../compiler/native-simple.asm"
%INCLUDE "../compiler/native-globals.asm"
%INCLUDE "../compiler/native-printer.asm"
%INCLUDE "../compiler/native-common.asm"
%INCLUDE "../compiler/native-emitter.asm"
%INCLUDE "../compiler/native-procedure-template.inc"
%INCLUDE "../compiler/cpm-source.asm"
%INCLUDE "../compiler/cpm-transport.asm"
%INCLUDE "../compiler/lexer.asm"
%INCLUDE "../compiler/decimal.asm"
%INCLUDE "../compiler/interner.asm"
%INCLUDE "../compiler/reader.asm"
%INCLUDE "../compiler/native-macro.asm"
%INCLUDE "../compiler/native-macro-expand.asm"
%INCLUDE "../compiler/native-macro-state.asm"
%INCLUDE "../compiler/native-macro-dotted.asm"
%INCLUDE "../compiler/native-scope.asm"
%INCLUDE "../compiler/native-macro-lowerer.asm"
%INCLUDE "../runtime/binary16.asm"
%INCLUDE "../runtime/numeric.asm"
%INCLUDE "../compiler/native-publication-procedure.asm"

; In-memory source callback used by the native macro/lowerer proof.
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
