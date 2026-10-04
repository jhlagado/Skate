; Numeric runtime workspace.
; NUM_END marks the code boundary; the labels below are shared scratch storage.
NUM_END:                   ; Exclusive end of numeric-dispatch instructions.
; Private static operands and scratch. Calls may also use the float24 workspace.
; Exact integers are signed twenty-four-bit values held as C:HL in registers
; and as three bytes, low first, in memory.
.WORK:
NUM_ORIG: DS 3                 ; Original left/unary value returned on failure.
NUM_X:    DS 4                 ; Left operand cell; later its converted float.
NUM_Y:    DS 4                 ; Right operand cell, the binary ABI's second value.
NUM_OP:   DB 0                 ; Operation 0..3, or the division result selector.
NUM_PNEG: DB 0                 ; Product or text sign: 00H nonnegative, 80H negative.
NUM_MULT: DS 3                 ; Remaining multiplier magnitude.
NUM_SWAP: DB 0                 ; Mixed-comparison order: 0 normal, 1 reversed.
NUM_INT:  DS 3                 ; Exact integer in a mixed comparison.
NUM_FLT:  DS 3                 ; Original float in a mixed comparison.
NUM_CHOP: DS 3                 ; Float truncated toward zero to a signed integer.
NUM_QNEG: DB 0                 ; Dividend or quotient sign bit.
NUM_DNEG: DB 0                 ; Divisor sign bit.
NUM_NMAG: DS 3                 ; Shifting unsigned dividend magnitude.
NUM_DMAG: DS 3                 ; Unsigned divisor magnitude.
NUM_QMAG: DS 3                 ; Unsigned quotient magnitude.
NUM_RMAG: DS 3                 ; Unsigned remainder magnitude.
NUM_CNT:  DB 0                 ; Remaining restoring-division iterations.
NUM_BUF:  DS 9                 ; Decimal text of an integer, built backwards.
.WORK_END:                 ; Exclusive end of private numeric workspace.
