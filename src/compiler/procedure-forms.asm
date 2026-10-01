; Compiler procedure modules.
;
; Include order preserves application calls, lambda scopes, capture state and
; descriptor/mutation emission from the original implementation.
%INCLUDE "procedures/call.asm"
%INCLUDE "procedures/lambda.asm"
%INCLUDE "procedures/capture.asm"
%INCLUDE "procedures/descriptor.asm"
