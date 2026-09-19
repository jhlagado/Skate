;=============================================================================
;  Skate compact compiler C1 entry
;=============================================================================
;
;  C1 is the first direct compact compiler slice.  It reads one CP/M source
;  file, accepts a bounded arithmetic form, evaluates it with the ABI-2
;  numeric services and publishes a committed NOBJ plus a runnable COM image.
;
;  The front-end and publication entry points are the measured N4 contracts
;  reused from the preserved prototype for this first vertical slice.  This
;  entry owns the production include boundary: later C1 increments can replace
;  one imported module at a time without changing the CP/M command contract.
;
;  C1 deliberately retains exact signed16 integers and the binary16 seam.  It
;  does not claim global definitions, lexical bindings, procedures, collection
;  or full Scheme compilation; those capabilities remain later gates.  The
;  source reader still consumes bytes incrementally and the output path refuses
;  to commit an incomplete generation.
;=============================================================================

%INCLUDE "../../compiler/origin.asm"
%INCLUDE "c1-entry.asm"
%INCLUDE "../../compiler/native-common.asm"
%INCLUDE "../../compiler/native-emitter.asm"
%INCLUDE "../../compiler/native-template.inc"
%INCLUDE "../../compiler/cpm-source.asm"
%INCLUDE "../../compiler/cpm-transport.asm"
%INCLUDE "../../compiler/lexer.asm"
%INCLUDE "../../compiler/decimal.asm"
%INCLUDE "../../compiler/interner.asm"
%INCLUDE "../../compiler/reader.asm"
%INCLUDE "../../runtime/binary16.asm"
%INCLUDE "../../runtime/numeric.asm"
%INCLUDE "../../compiler/native-publication-control.asm"
