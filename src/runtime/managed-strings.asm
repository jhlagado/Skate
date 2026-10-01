; Managed strings allocated from the existing rounded closure classes.
;
; A managed string is a tag-six pointer to a class block whose first byte is
; its length and whose following bytes are the string data.  The closure start
; map supplies allocation ownership; the bit immediately after the start bit
; identifies a string block.  Strings contain no managed references, so the
; collector marks them without enqueueing them for closure tracing.
; Include order preserves the runtime image and shared scratch addresses.
%INCLUDE "strings/ops.asm"
%INCLUDE "strings/storage.asm"
%INCLUDE "strings/state.asm"
