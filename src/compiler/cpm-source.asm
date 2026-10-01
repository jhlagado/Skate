%INCLUDE "cpm-source-includes.asm"
%INCLUDE "cpm-source-include-parser.asm"

; CP/M source stream composition.
;
; Include order preserves source opening, byte delivery, package streams,
; closing and shared state from the original implementation.
%INCLUDE "source/open.asm"
%INCLUDE "source/read.asm"
%INCLUDE "source/package.asm"
%INCLUDE "source/close.asm"
%INCLUDE "source/state.asm"
