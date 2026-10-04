; Twenty-four-bit float runtime composition (see docs/float24.md).
;
; Classification and unpacking, arithmetic, the shared rounding packer,
; comparison, integer conversion and the shared workspace.
%INCLUDE "float24/classify.asm"
%INCLUDE "float24/arith.asm"
%INCLUDE "float24/pack.asm"
%INCLUDE "float24/compare.asm"
%INCLUDE "float24/convert.asm"
%INCLUDE "float24/state.asm"
