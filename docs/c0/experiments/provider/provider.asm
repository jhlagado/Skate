%INCLUDE "origin-provider.asm"
%INCLUDE "provider-vector.asm"
%INCLUDE "../../../../runtime/allocator.asm"
%INCLUDE "../../../../runtime/collector.asm"
%INCLUDE "../../../../runtime/binary16.asm"
%INCLUDE "../../../../runtime/numeric.asm"
%INCLUDE "../../../../runtime/execution.asm"
%INCLUDE "provider-tail.asm"

; C0 prepared runtime provider at the retained-CCP COM origin.
;
; PUBLIC ENTRIES
;   PVNCLS..PVLIT        Three-byte service-vector entries.  Each jumps to
;                         the corresponding ATOM runtime service below.
;   PVBOOT                First byte after the vector; the NOBJ entry jump at
;                         $0100 is patched to the generated payload.
;
; MEMORY
;   The initialized section starts at $0100 and owns the vector, runtime
;   instructions and their private writable state.  It ends at PV_END.
;   The separate payload section is fixed at that measured exclusive address.
;
; REGISTERS / STACK / FAILURE
;   The vector preserves the service's ordinary ATOM entry contract.  No
;   provider entry is executed directly in this fixture; the linked payload
;   owns startup, stack selection and terminal failure handling.
;
; REENTRANCY
;   Runtime modules retain their documented static-workspace restrictions.
