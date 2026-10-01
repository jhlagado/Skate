; Mutable vector values and their collector support.
; A vector is tag seven and points at a managed class block.  The first byte
; stores the element count; every element then uses the same four-byte payload,
; tag and spare-byte shape as an argument packet.  The closure start map owns
; the block, while an odd bit in the persistent mark map identifies a vector.
; Include order preserves the runtime image and shared scratch addresses.
%INCLUDE "vectors/ops.asm"
%INCLUDE "vectors/storage.asm"
%INCLUDE "vectors/trace.asm"
%INCLUDE "vectors/state.asm"
