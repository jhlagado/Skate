; Scope runtime primitive modules.
;
; Include order is part of the primitive dispatch table and image layout.
%INCLUDE "primitives/dispatch.asm"
%INCLUDE "primitives/numeric.asm"
%INCLUDE "primitives/predicates.asm"
%INCLUDE "primitives/io.asm"
%INCLUDE "primitives/data.asm"
%INCLUDE "primitives/pairs.asm"
%INCLUDE "primitives/output.asm"
