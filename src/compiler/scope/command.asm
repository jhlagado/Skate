; Scope compiler modules.
;
; Keep these includes in source order: driver, forms, conditionals and body.
; The order is part of the generated image layout.
%INCLUDE "command/driver.asm"
%INCLUDE "command/forms.asm"
%INCLUDE "command/conditionals.asm"
%INCLUDE "command/body.asm"
%INCLUDE "command/do.asm"
