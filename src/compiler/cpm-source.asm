; CP/M source stream composition.
;
; CSOPEN resolves the root's leading include tree before any byte is read;
; CSBYTE then streams the ordered parts and CSCLOSE reports the outcome.
%INCLUDE "source/open.asm"
%INCLUDE "cpm-source-include-parser.asm"
%INCLUDE "source/read.asm"
%INCLUDE "source/close.asm"
%INCLUDE "source/state.asm"
