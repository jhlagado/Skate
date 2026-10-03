; Binary16 writable arithmetic workspace.
; Data labels are shared by the binary16 modules.
; Code ends here. The following 27 bytes are private writable scratch.
F16_END:
F16_WORK:
F16_X: DW 0                       ; Original/prepared left binary16 payload; also conversion error backup
F16_Y: DW 0                       ; Original/prepared right binary16 payload
F16_XMAN: DW 0                ; Left normalized unsigned 11-bit significand
F16_YMAN: DW 0                ; Right normalized unsigned 11-bit significand
F16_XEXP: DB 0                 ; Left signed biased exponent after subnormal normalization
F16_YEXP: DB 0                 ; Right signed biased exponent after subnormal normalization
F16_XNEG: DB 0                ; Left sign as 00 or 80
F16_YNEG: DB 0                ; Right sign as 00 or 80
F16_XCAT: DB 0               ; Left class: 0 zero, 1 finite nonzero, 2 infinity, 3 NaN
F16_YCAT: DB 0               ; Right class with the same four encodings
F16_SIGN: DB 0                 ; Result sign as 00 or 80 for the shared packer
F16_EXP: DB 0                  ; Result signed biased exponent for the shared packer
F16_TERM: DW 0                ; Low word of the shifting multiplication multiplicand
F16_THI: DB 0                ; High byte extending the multiplicand to 24 bits
F16_BITS: DW 0                 ; Remaining multiplier bits, consumed from the low end
F16_PROD: DW 0                 ; Low word of the exact significand product
F16_PHI: DB 0                ; High byte extending the product to 24 bits
F16_QUOT: DW 0                 ; Fourteen-bit quotient accumulated by restoring division
F16_MODE: DB 0                 ; Integer egress mode: 0 unsigned, 1 signed
F16_LIM:
