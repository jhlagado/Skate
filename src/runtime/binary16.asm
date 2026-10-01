; Binary16 runtime composition.
;
; Include order preserves classification, arithmetic, packing, comparison,
; conversion and shared workspace from the original implementation.
%INCLUDE "binary16/classify.asm"
%INCLUDE "binary16/add.asm"
%INCLUDE "binary16/muldiv.asm"
%INCLUDE "binary16/pack.asm"
%INCLUDE "binary16/compare.asm"
%INCLUDE "binary16/convert.asm"
%INCLUDE "binary16/state.asm"
