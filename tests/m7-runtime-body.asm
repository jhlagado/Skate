%INCLUDE "../runtime/allocator.asm"
%INCLUDE "../runtime/collector.asm"
%INCLUDE "../runtime/binary16.asm"
%INCLUDE "../runtime/numeric.asm"
%INCLUDE "../runtime/execution.asm"

; M7's target adapter makes execution failures terminal at the CP/M boundary.
RTERROR:
        LD DE,M7ERRTXT
        LD C,9
        CALL $0005
        LD C,0
        CALL $0005
        JP $0000

M7ERRTXT:
        DB "RUNTIME ERROR",13,10,"$"
