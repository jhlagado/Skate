; CP/M source stream composition.
;
; SRC_OPEN resolves the root's leading include tree before any byte is read;
; SRC_BYTE then streams the ordered parts and SRC_END reports the outcome.
%INCLUDE "source/open.asm"
%INCLUDE "cpm-source-include-parser.asm"
%INCLUDE "source/read.asm"
%INCLUDE "source/close.asm"
%INCLUDE "source/state.asm"
