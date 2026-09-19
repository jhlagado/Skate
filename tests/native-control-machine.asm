%INCLUDE "origin.asm"
%INCLUDE "../compiler/native-control.asm"
%INCLUDE "../compiler/native-common.asm"
%INCLUDE "../compiler/native-emitter.asm"
%INCLUDE "../compiler/native-template.inc"
%INCLUDE "../compiler/cpm-source.asm"
%INCLUDE "../compiler/cpm-transport.asm"
%INCLUDE "../compiler/lexer.asm"
%INCLUDE "../compiler/decimal.asm"
%INCLUDE "../compiler/interner.asm"
%INCLUDE "../compiler/reader.asm"
%INCLUDE "../runtime/binary16.asm"
%INCLUDE "../runtime/numeric.asm"

; Host-test source adapter.  It supplies the same byte callback contract as
; CP/M source files without involving BDOS, so N5EXPR can be tested directly.
%INCLUDE "../compiler/native-publication-control.asm"
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
