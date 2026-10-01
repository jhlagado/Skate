; Binary16 normalisation, rounding and result construction.
; Entry points: FPKNORM, FPACKENC, FZEROSGN, FMAKEINF and FMAKENAN.
; HL has mantissa with three G/R/S bits. Exponent is signed biased.
; Normalize before the single final rounding operation.
FPKNORM:
    LD A,H                  ; Test the guarded magnitude
    OR L                    ; Include its low byte
    JP Z,FZEROSGN              ; An empty magnitude produces the saved signed zero

; The guarded leading one belongs at bit 13; larger values shift right.
FPACKLGE:
    BIT 7,H                 ; Check whether bit 15 is set
    JP NZ,FPACKRSH              ; A leading bit 15 needs a sticky right shift
    BIT 6,H                 ; Check whether bit 14 is set
    JP Z,FPACKSML              ; With neither high bit set, test for a small magnitude

; One right shift halves the significand and increases its exponent.
FPACKRSH:
    LD B,1                  ; Request one sticky right shift
    CALL FJAMSHFT              ; Retain discarded information for final rounding
    LD A,(FRESEXP)             ; Fetch the signed biased exponent
    INC A                   ; Compensate for halving the magnitude
    LD (FRESEXP),A             ; Save the new exponent
    JP FPACKLGE                ; Check whether another right shift is needed

; A nonzero guarded magnitude is normalized when bit 13 is set.
FPACKSML:
    BIT 5,H                 ; Check the target leading-one position
    JP NZ,FPACKVAL               ; The significand is now ready for exponent handling
    ADD HL,HL               ; Move the leading one toward bit 13
    LD A,(FRESEXP)             ; Fetch the signed biased exponent
    DEC A                   ; Compensate for doubling the magnitude
    LD (FRESEXP),A             ; Save the new exponent
    JP FPACKSML                ; Continue until bit 13 is set

; Exponent 1 is the smallest normal scale; lower values become subnormals.
FPACKVAL:
    LD A,(FRESEXP)             ; Fetch the normalized exponent
    OR A                    ; Test its zero and sign flags
    JP Z,FPACKSUB             ; Exponent zero needs a subnormal shift
    JP M,FPACKSUB             ; A negative exponent also needs a subnormal shift
    CP 31                   ; Exponent 31 is beyond the largest finite encoding
    JP NC,FMAKEINF              ; Overflow produces signed infinity
    JP FPACKRND               ; A normal-range exponent can round directly

; Shift to the scale for exponent 1 before rounding, retaining sticky data.
FPACKSUB:
    NEG                     ; Form the negated exponent
    INC A                   ; The shift distance is 1 minus exponent
    LD B,A                  ; Pass that distance in B
    CALL FJAMSHFT              ; Shift into the gradual-underflow range
    LD A,1                  ; Use the smallest normal exponent as the working scale
    LD (FRESEXP),A             ; Save that scale for rounding and encoding
FPACKRND:
    ; Round nearest-even: add 3 + retained low bit, then drop G/R/S.
    LD DE,3                 ; Bias by three before dropping three rounding bits
    BIT 3,L                 ; Inspect the least significant retained bit
    JP Z,FROUNDAD           ; An even retained value uses the smaller bias
    INC DE                  ; An odd retained value adds four for ties-to-even

; Adding 3 + retained parity resolves halfway cases before truncation.
FROUNDAD:
    ADD HL,DE               ; Apply the rounding bias to the guarded magnitude
    SRL H                   ; Start dropping the sticky position from the word
    RR L                    ; Complete the first right shift
    SRL H                   ; Start dropping the round position
    RR L                    ; Complete the second right shift
    SRL H                   ; Start dropping the guard position
    RR L                    ; HL holds the rounded significand, possibly with carry
    BIT 3,H                 ; Test for rounding carry into bit 11
    JP Z,FPACKENC              ; No carry means the exponent is unchanged
    SRL H                   ; Shift the rounding carry toward the normal leading bit
    RR L                    ; Complete that extra right shift
    LD A,(FRESEXP)             ; Fetch the exponent before carry normalization
    INC A                   ; Account for the extra shift
    LD (FRESEXP),A             ; Save the rounded exponent

; A rounded subnormal has no implicit bit; a normal value removes bit 10.
FPACKENC:
    LD A,(FRESEXP)             ; Fetch the final exponent
    CP 31                   ; Check for overflow caused by rounding
    JP NC,FMAKEINF              ; Return infinity if rounding crossed the finite limit
    BIT 2,H                 ; Test for the implicit bit of a normal significand
    JP Z,FPACKSGN             ; Without it, encode an exponent-zero subnormal
    RES 2,H                 ; Remove the implicit leading one from the stored fraction
    RLCA                    ; Move the exponent toward its high-byte field
    RLCA                    ; Place exponent bits in positions 2 through 6
    OR H                    ; Combine exponent and high fraction bits
    LD H,A                  ; Install the encoded magnitude high byte

; The magnitude is encoded; only the saved sign remains to be applied.
FPACKSGN:
    LD A,(FRESIGN)             ; Fetch the result sign in bit 7
    OR H                    ; Combine sign with the encoded magnitude
    LD H,A                  ; Install the complete high byte
    JP F16OKAY                  ; Return the rounded binary16 result

; Construct a zero with the sign selected by the arithmetic path.
FZEROSGN:
    LD A,(FRESIGN)             ; Fetch the selected sign bit
    LD H,A                  ; The high byte contains only the sign
    LD L,0                  ; The low fraction byte is zero
    JP F16OKAY                  ; Return signed zero successfully

; Construct infinity with the sign selected by the arithmetic path.
FMAKEINF:
    LD A,(FRESIGN)             ; Fetch the selected sign bit
    OR 7CH                  ; Set the all-ones exponent with a zero fraction
    LD H,A                  ; Install sign and exponent
    LD L,0                  ; Keep the fraction low byte zero
    JP F16OKAY                  ; Return signed infinity successfully

; Every numeric NaN result uses the sole language NaN encoding.
FMAKENAN:
    LD HL,7E00H             ; Construct canonical numeric NaN
    JP F16OKAY                  ; Return it as a successful arithmetic result

; Shift HL right B places, OR every discarded bit into sticky bit zero.
FJAMSHFT:
    LD A,B                  ; Test the requested shift count
    OR A                    ; A zero count leaves the magnitude unchanged
    RET Z                   ; Return without entering the decrementing loop

; Once sticky is one, subsequent shifts retain it even if other bits vanish.
FJAMLOOP:
    SRL H                   ; Shift the high magnitude byte toward L
    RR L                    ; Shift the low byte; carry is the discarded bit
    JP NC,FJAMNEXT          ; No extra sticky bit is needed for a discarded zero
    SET 0,L                 ; OR a discarded one into the low bit

; B counts remaining shifts; the jammed low bit summarizes lost precision.
FJAMNEXT:
    DJNZ FJAMLOOP            ; Repeat for the requested alignment distance
    RET                     ; Return the shifted magnitude in HL

; Negate a raw 16-bit word modulo 65536; 8000H remains its own negation.
FNEGWORD:
    LD A,L                  ; Fetch the low byte
    CPL                     ; Invert its bits
    LD L,A                  ; Save the inverted low byte
    LD A,H                  ; Fetch the high byte
    CPL                     ; Invert its bits
    LD H,A                  ; Save the inverted high byte
    INC HL                  ; Add one to complete two's-complement negation
    RET                     ; Return the negated raw word
