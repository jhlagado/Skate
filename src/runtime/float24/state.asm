; Twenty-four-bit float workspace.
; Data labels are shared by the float24 modules.  Code ends at F24_END; the
; bytes up to F24_LIM are private writable scratch.
F24_END:
F24_WORK:
; Unpacked operands: sign 00/80, exponent biased by +16 so that normalized
; subnormals stay positive (1..142), 17-bit significand with its leading one
; at bit 16, class 0 zero, 1 finite, 2 infinity, 3 NaN.
F24_XS:   DB 0
F24_XU:   DB 0
F24_XM:   DS 3
F24_XC:   DB 0
F24_YS:   DB 0
F24_YU:   DB 0
F24_YM:   DS 3
F24_YC:   DB 0
F24_SIGN: DB 0                 ; Result sign for the packer, 00 or 80.
F24_EXP:  DW 0                 ; Result exponent for the packer, signed.
F24_M:    DS 3                 ; Guarded result magnitude for the packer.
F24_P:    DS 5                 ; Product accumulator.
F24_T:    DS 5                 ; Shifting multiplicand.
F24_Q:    DS 3                 ; Remaining multiplier.
F24_CNT:  DB 0                 ; Loop count.
F24_LIM:
