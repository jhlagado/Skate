;  Runtime image assembly wrapper
;
;  Keep the program entry and its numeric service modules in one ATOM image.
;  The template generator serializes this image into the compiler's NOBJ
;  staging area, where the emitter patches the five operand fields.

%INCLUDE "arithmetic-runtime.asm"        ; Entry, formatting and patched fields.
%INCLUDE "../../runtime/binary16.asm"    ; Binary16 operations used by the image.
%INCLUDE "../../runtime/numeric.asm"     ; ABI-2 arithmetic service routines.
