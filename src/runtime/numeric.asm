; Numeric runtime composition.
;
; Include order preserves dispatch, exact arithmetic, division, conversion,
; comparison and shared workspace from the original implementation.
%INCLUDE "numeric/ops.asm"
%INCLUDE "numeric/divide.asm"
%INCLUDE "numeric/convert.asm"
%INCLUDE "numeric/compare.asm"
%INCLUDE "numeric/state.asm"
