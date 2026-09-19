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
        OR A
        RET
RFPTR:  DW 0
RFLIMIT: DW 0
