; Binary16 writable arithmetic workspace.
; Data labels are shared by the binary16 modules.
; Code ends here. The following 27 bytes are private writable scratch.
F16END:
F16WORK:
FLEFTVAL: DW 0                    ; Original/prepared left binary16 payload; also conversion error backup
FRIGHTVL: DW 0                    ; Original/prepared right binary16 payload
FLEFTSIG: DW 0                ; Left normalized unsigned 11-bit significand
FRIGHTSI: DW 0                ; Right normalized unsigned 11-bit significand
FLEFTEXP: DB 0                 ; Left signed biased exponent after subnormal normalization
FRIGHTEX: DB 0                 ; Right signed biased exponent after subnormal normalization
FLEFTSGN: DB 0                ; Left sign as 00 or 80
FRIGHTSG: DB 0                ; Right sign as 00 or 80
FLEFTCLS: DB 0               ; Left class: 0 zero, 1 finite nonzero, 2 infinity, 3 NaN
FRIGHTCL: DB 0               ; Right class with the same four encodings
FRESIGN: DB 0                  ; Result sign as 00 or 80 for the shared packer
FRESEXP: DB 0                  ; Result signed biased exponent for the shared packer
FMULCAND: DW 0                ; Low word of the shifting multiplication multiplicand
FMULHBYT: DB 0               ; High byte extending the multiplicand to 24 bits
FMULTPLR: DW 0                 ; Remaining multiplier bits, consumed from the low end
FPRODUCT: DW 0                 ; Low word of the exact significand product
FPRODHI: DB 0                ; High byte extending the product to 24 bits
FDIVQUOT: DW 0                 ; Fourteen-bit quotient accumulated by restoring division
FCONMODE: DB 0                 ; Integer egress mode: 0 unsigned, 1 signed
F16WEND:
