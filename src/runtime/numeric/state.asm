; Numeric runtime workspace.
; NUM_END marks the code boundary; the labels below are shared scratch storage.
NUM_END:                   ; Exclusive end of numeric-dispatch instructions.
; Private static operands and scratch. Calls may also use binary16 workspace.
.WORK:
NUM_ORIG: DW 0                 ; Original left/unary word returned on failure.
NUM_X: DW 0                      ; Working left payload; later its converted float.
NUM_Y: DW 0                       ; Original right payload.
NUM_XTAG: DB 0                  ; Original left representation tag.
NUM_YTAG: DB 0                   ; Original right representation tag.
; Store BC together so setting operation C does not disturb input A/B.
NUM_OP: DW 0                    ; Low byte: operation 0..3. High byte: saved B, unused.
NUM_PNEG: DB 0                 ; Product sign: 00H nonnegative, 80H negative.
NUM_SWAP: DB 0                 ; Mixed-comparison order: 0 normal, 1 reversed.
NUM_INT: DW 0                    ; Exact integer in a mixed comparison.
NUM_FLT: DW 0                    ; Original binary16 word in a mixed comparison.
NUM_CHOP: DW 0                   ; Float truncated toward zero to a signed word.
NUM_WANT:   DB 0                 ; Quotient/remainder selector.
NUM_NTAG:   DB 0                 ; Original left value tag.
NUM_DTAG:   DB 0                 ; Original right value tag.
NUM_NARG: DW 0                   ; Original left payload.
NUM_DARG: DW 0                   ; Original right payload.
NUM_QNEG: DB 0                   ; Dividend or quotient sign bit.
NUM_DNEG: DB 0                   ; Divisor sign bit.
NUM_NMAG:  DW 0                  ; Shifting unsigned dividend magnitude.
NUM_DMAG:  DW 0                  ; Unsigned divisor magnitude.
NUM_QMAG:  DW 0                  ; Unsigned quotient magnitude.
NUM_RMAG:  DW 0                  ; Unsigned remainder magnitude.
NUM_CNT:  DB 0                   ; Remaining restoring-division iterations.
.WORK_END:                 ; Exclusive end of private numeric workspace.
