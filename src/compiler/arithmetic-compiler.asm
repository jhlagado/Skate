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

%INCLUDE "origin.asm"                    ; Establish the CP/M load origin.
%INCLUDE "arithmetic-compiler-command.asm" ; Own the command parser and dispatch.
%INCLUDE "native-common.asm"             ; Shared error and register helpers.
%INCLUDE "arithmetic-runtime-template.inc" ; Checked serialized runtime image.
%INCLUDE "nobj-arithmetic-emitter.asm"   ; Patch, checksum and stream output.
%INCLUDE "cpm-source.asm"                ; Source FCB byte reader.
%INCLUDE "cpm-transport.asm"             ; CP/M file and console transport.
%INCLUDE "lexer.asm"                     ; Tokenization for the reader.
%INCLUDE "decimal.asm"                   ; Signed integer and binary16 parsing.
%INCLUDE "interner.asm"                  ; Symbol and string storage.
%INCLUDE "reader.asm"                    ; Structural datum reader.
%INCLUDE "../../runtime/binary16.asm"   ; Binary16 arithmetic primitives.
%INCLUDE "../../runtime/numeric.asm"    ; ABI-2 numeric dispatch.
%INCLUDE "native-publication-control.asm" ; Staged NOBJ/COM publication.
