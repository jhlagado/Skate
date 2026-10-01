; Native lexer composition.
;
; Include order preserves source control, literal decoding, classification and
; diagnostics/state from the original implementation.
%INCLUDE "lexer/core.asm"
%INCLUDE "lexer/strings.asm"
%INCLUDE "lexer/chars.asm"
%INCLUDE "lexer/classify.asm"
%INCLUDE "lexer/errors.asm"
