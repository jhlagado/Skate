; Runtime activation-slot composition.
;
; Include order preserves inline slots, promotion, closure-map transfer and root
; scanning from the original implementation.
%INCLUDE "slots/base.asm"
%INCLUDE "slots/promote.asm"
%INCLUDE "slots/copy.asm"
%INCLUDE "slots/root.asm"
