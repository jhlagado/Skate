; Numeric runtime workspace.
; NEND marks the code boundary; the labels below are shared scratch storage.
NEND:                      ; Exclusive end of numeric-dispatch instructions.
; Private static operands and scratch. Calls may also use binary16 workspace.
NWORK:
NORIGVAL: DW 0                 ; Original left/unary word returned on failure.
NLEFTWK: DW 0                    ; Working left payload; later its converted float.
NRIGHTWK: DW 0                    ; Original right payload.
NLEFTTG: DB 0                   ; Original left representation tag.
NRIGHTTG: DB 0                   ; Original right representation tag.
; Store BC together so setting operation C does not disturb input A/B.
NOPCODE: DW 0                   ; Low byte: operation 0..3. High byte: saved B, unused.
NPRODSGN: DB 0                 ; Product sign: 00H nonnegative, 80H negative.
NREVORD: DB 0                  ; Mixed-comparison order: 0 normal, 1 reversed.
NINTCMP: DW 0                    ; Exact integer in a mixed comparison.
NFLOATV: DW 0                    ; Original binary16 word in a mixed comparison.
NTRUNCV: DW 0                    ; Float truncated toward zero to a signed word.
NIDOP:   DB 0                    ; Quotient/remainder selector.
NIDLT:   DB 0                    ; Original left value tag.
NIDRT:   DB 0                    ; Original right value tag.
NIDLEFT: DW 0                    ; Original left payload.
NIDRIGHT: DW 0                   ; Original right payload.
NIDSIGN: DB 0                    ; Dividend or quotient sign bit.
NIDRSIGN: DB 0                   ; Divisor sign bit.
NIDNUM:  DW 0                    ; Shifting unsigned dividend magnitude.
NIDDIV:  DW 0                    ; Unsigned divisor magnitude.
NIDQUO:  DW 0                    ; Unsigned quotient magnitude.
NIDREM:  DW 0                    ; Unsigned remainder magnitude.
NIDCNT:  DB 0                    ; Remaining restoring-division iterations.
NWEND:                     ; Exclusive end of private numeric workspace.
