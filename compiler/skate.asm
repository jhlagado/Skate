%INCLUDE "origin.asm"
%INCLUDE "native-procedure.asm"
%INCLUDE "native-procedure-quoted.asm"
%INCLUDE "native-nobj-dynamic.asm"
%INCLUDE "native-simple.asm"
%INCLUDE "native-globals.asm"
%INCLUDE "native-printer.asm"
%INCLUDE "native-common.asm"
%INCLUDE "native-emitter.asm"
%INCLUDE "native-procedure-template.inc"
%INCLUDE "cpm-source.asm"
%INCLUDE "cpm-transport.asm"
%INCLUDE "lexer.asm"
%INCLUDE "decimal.asm"
%INCLUDE "interner.asm"
%INCLUDE "reader.asm"
%INCLUDE "native-macro.asm"
%INCLUDE "native-macro-expand.asm"
%INCLUDE "native-macro-state.asm"
%INCLUDE "native-macro-dotted.asm"
%INCLUDE "native-scope.asm"
%INCLUDE "native-macro-lowerer.asm"
%INCLUDE "../runtime/binary16.asm"
%INCLUDE "../runtime/numeric.asm"
%INCLUDE "native-publication-procedure.asm"

;=============================================================================
;  SKATE production CP/M compiler image
;=============================================================================
;
;  This is the product assembly entry.  Test images may add a host source
;  callback after these modules, but the shipped compiler is assembled from
;  this file so the product path does not depend on tests/.
;=============================================================================
