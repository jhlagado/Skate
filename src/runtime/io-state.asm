; State shared between the core runtime and its optional I/O module.
;
; The datum reader, file ports and CP/M transport form a module at the end
; of the runtime image that a program without read or file procedures does
; not load.  Every variable the core reads or initialises lives here, inside
; the core, so the core never touches bytes of an absent module.  The
; module's private buffers stay with its code.

; Datum reader.
DR_LIVE:    DB 0                     ; Nonzero while a datum read owns its roots.
DR_ROOTS:  DB 0                   ; Active exact-root count for later units.
DR_DEPTH: DB 0                   ; Open construction frames for later units.
DR_SLOTS:   DB 0                   ; Used construction-value slots for later units.
DR_SP:   DW RT_DRVLO              ; Next free reader value-stack address.
DR_FRAME:   DW 0                   ; Current reader frame address, if any.
DR_ATAG: DB 0                     ; Tag of the list being relinked by a close.
DR_ACC: DW 0                      ; Payload of that list.
DR_EOF: DB 0                     ; Nonzero when the current nested value is EOF.
DR_LEN:   DB 0                      ; Numeric spelling length, bounded at 64 bytes.
DR_NBUF:   DS 64                   ; A number's spelling for DEC_READ.
DR_BYTE:    DB 0                     ; Current decimal or character byte.
DR_AHEAD:    DB 0                    ; Peeked byte used to classify a signed token.
DR_TAG:    DB 0                      ; Result tag saved across normal cleanup.
DR_AEXT:   DB 0                      ; Byte 2 of the list accumulator.
DR_EXT:    DB 0                      ; Result byte 2 saved across normal cleanup.
DR_VAL:    DW 0                     ; Result payload saved across normal cleanup.
DR_SIZE: DB 0                        ; Decoded byte count, bounded at 255.
DR_TMP: DB 0                         ; One-byte scratch for append and escapes.

; File ports.
FILE_BIN: DB 0                       ; Nonzero opens a binary stream.
FILE_DIR: DB 0                       ; 1 opens an input, 2 an output.
FILE_SL: DB 0                      ; The slot being opened.
FS_OUTS:  DB 0                       ; Open output streams, flushed at exit.
IN_MODE:    DB 0                     ; Nonzero while a binary file is read.
FILE_LEN:     DB 0
FILE_DOT:      DB 0
FILE_POS:     DB 0
FILE_EXT:     DB 0
FILE_CHR:     DB 0
FILE_PTR:      DW 0
