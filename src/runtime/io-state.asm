; State shared between the core runtime and its optional I/O module.
;
; The datum reader, file ports and CP/M transport form a module at the end
; of the runtime image that a program without read or file procedures does
; not load.  Every variable the core reads or initialises lives here, inside
; the core, so the core never touches bytes of an absent module.  The
; module's private buffers stay with its code.

; Datum reader.
SRTDRACT:    DB 0                    ; Nonzero while a datum read owns its roots.
SRTDRRC:  DB 0                    ; Active exact-root count for later units.
SRTDRFC: DB 0                    ; Open construction frames for later units.
SRTDRVC:   DB 0                    ; Used construction-value slots for later units.
SRTDRVP:   DW SRTDRVB             ; Next free reader value-stack address.
SRTDRFP:   DW 0                    ; Current reader frame address, if any.
SRTDRACC:  DB 0                    ; Nonzero while the list accumulator is a root.
SRTDATAG: DB 0                    ; Accumulator tag during list construction.
SRTDAVAL: DW 0                    ; Accumulator payload during list construction.
SRTDRNR:   DB 0                    ; Remaining values while folding one list.
SRTDRDOT:  DB 0                    ; Nonzero while SRTDRBLD is folding a dotted list.
SRTDEOF: DB 0                    ; Nonzero when the current nested value is EOF.
SRTDRLEN:   DB 0                    ; Numeric spelling length, bounded at 64 bytes.
SRTDRNUM:    DW 0                    ; Unsigned magnitude for an exact integer.
SRTDRSG:   DB 0                    ; Nonzero while the token has a minus sign.
SRTDRSN:   DB 0                    ; Nonzero after at least one digit is read.
SRTDRDIG:    DB 0                    ; Current decimal or character byte.
SRTDRNXT:    DB 0                    ; Peeked byte used to classify a signed token.
SRTDRTAG:    DB 0                    ; Result tag saved across normal cleanup.
SRTDVAL:    DW 0                    ; Result payload saved across normal cleanup.
SRTDSLN: DB 0                        ; Decoded byte count, bounded at 255.
SRTDSTMP: DB 0                       ; One-byte scratch for append and escapes.

; File ports.
SRTFOMOD: DB 0
SRTFIACT:    DB 0
SRTFOACT:   DB 0
SRTFIMOD:    DB 0
SRTFWMDE:  DB 0
SRTFCR:       DB 0
SRTFNLEN:     DB 0
SRTFEXT:      DB 0
SRTFNPOS:     DB 0
SRTFEPOS:     DB 0
SRTFCHAR:     DB 0
SRTFFPTR:      DW 0
