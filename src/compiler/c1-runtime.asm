%INCLUDE "c1-runtime-main.asm"
%INCLUDE "../../runtime/binary16.asm"
%INCLUDE "../../runtime/numeric.asm"

; Header-only wrapper for the checked generated runtime image.  The main
; program is included before the numeric modules so C1RSTART remains $0100.
