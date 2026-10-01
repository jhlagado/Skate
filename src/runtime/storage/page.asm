; Runtime page-domain composition.
;
; Include order preserves initialisation, allocation/release helpers and shared
; page state from the original implementation.
%INCLUDE "page/init.asm"
%INCLUDE "page/alloc.asm"
%INCLUDE "page/state.asm"
