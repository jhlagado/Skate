%INCLUDE "origin-4200.asm"
; ATOM-built Skate runtime provider for the native I5 execution gate.
; The provider is assembled at a fixed test placement so the caller object
; can remain at $0100 while service relocations are still resolved by NOBJ.

%INCLUDE "../runtime/allocator.asm"
%INCLUDE "../runtime/collector.asm"
%INCLUDE "../runtime/binary16.asm"
%INCLUDE "../runtime/numeric.asm"
%INCLUDE "../runtime/execution.asm"

RTERROR:
        LD C,9
        LD DE,ERRTXT
        CALL 5
        LD C,0
        CALL 5
        JP 0

ERRTXT:
        DB "RUNTIME ERROR",13,10,"$"
