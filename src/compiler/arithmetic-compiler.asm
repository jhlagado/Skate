;=============================================================================
;  Skate arithmetic compiler command
;=============================================================================
;
;  This command reads one CP/M source file, accepts a bounded arithmetic form,
;  validates it with the ABI-2 numeric services, and publishes a committed NOBJ
;  object plus a runnable COM image.  The generated image computes its result
;  when it runs; the compiler never formats the answer into the output.
;
;  The reader, numeric services, and publication routines are measured
;  contracts reused from the preserved prototype.  The include list is the
;  production boundary: a later compiler change can replace one module without
;  copying the whole prototype or changing the CP/M command contract.
;
;  The current command retains exact signed16 integers and the binary16 seam.
;  It does not yet compile definitions, lexical bindings, procedures,
;  collections, or general Scheme programs.  The source reader consumes bytes
;  incrementally, and the output path refuses to commit an incomplete object.
;=============================================================================

%INCLUDE "../../compiler/origin.asm"
%INCLUDE "arithmetic-compiler-command.asm"
%INCLUDE "../../compiler/native-common.asm"
%INCLUDE "arithmetic-runtime-template.inc"
%INCLUDE "nobj-arithmetic-emitter.asm"
%INCLUDE "../../compiler/cpm-source.asm"
%INCLUDE "../../compiler/cpm-transport.asm"
%INCLUDE "../../compiler/lexer.asm"
%INCLUDE "../../compiler/decimal.asm"
%INCLUDE "../../compiler/interner.asm"
%INCLUDE "../../compiler/reader.asm"
%INCLUDE "../../runtime/binary16.asm"
%INCLUDE "../../runtime/numeric.asm"
%INCLUDE "../../compiler/native-publication-control.asm"
