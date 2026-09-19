RTLIEND:

; Platform-owned terminal hook for runtime type/arity/capacity failures.
; The fixture never expects this path; it exits to the host sentinel if a
; defensive runtime check rejects the prepared map.
RTERROR:
        JP 0FF00H

PVEND:
