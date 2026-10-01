; Lexical binding compiler modules.
;
; Keep these includes in this order: form parsing, local scope state,
; global lookup, and initializer context. The order preserves the existing
; assembled image while giving each responsibility a separate source file.
%INCLUDE "bindings/forms.asm"
%INCLUDE "bindings/locals.asm"
%INCLUDE "bindings/globals.asm"
%INCLUDE "bindings/initializers.asm"
