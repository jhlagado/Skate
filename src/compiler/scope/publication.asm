; Scope compiler publication modules.
;
; Include order follows the original publication implementation: layout and
; data first, then fixups, descriptors, stream output and shared state.
%INCLUDE "publication/layout.asm"
%INCLUDE "publication/patch.asm"
%INCLUDE "publication/descriptors.asm"
%INCLUDE "publication/stream.asm"
%INCLUDE "publication/state.asm"
