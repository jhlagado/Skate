; Binary16 value printer for the scope-control runtime.
;
; Finite binary16 values are exact dyadic fractions.  The printer converts
; the small significand to decimal digits, multiplies those digits by five
; once for each binary fractional place, and places the decimal point.  At
; most twenty-four fractional places are required by a binary16 subnormal.

; Print a validated binary16 value in a source-compatible decimal spelling.
SRTFPRN:
        LD (SRTFVAL),HL             ; Preserve the value while its fields are decoded.
        LD A,H                      ; Extract the exponent field from the high byte.
        AND 7CH                     ; Keep only the five exponent bits.
        CP 7CH                      ; An all-ones exponent denotes an exceptional value.
        JP Z,SRTFSPEC               ; Infinity and NaN use their named spellings.
        LD A,H                      ; Extract the sign before discarding the high bits.
        AND 80H                     ; Keep only the binary16 sign bit.
        LD (SRTFSIGN),A             ; The magnitude path never changes this sign.
        LD A,H                      ; Form the eleven-bit significand's upper bits.
        AND 3                       ; The low two bits of H are the fraction high bits.
        LD D,A                      ; Keep those bits in the high byte of DE.
        LD E,L                      ; The payload low byte completes the fraction.
        LD A,H                      ; Recover the exponent for normal values.
        AND 7CH                     ; Discard sign and fraction bits.
        RRCA                        ; Move the exponent's upper bit toward bit zero.
        RRCA                        ; A now contains the unbiased field value.
        LD (SRTFEXP),A              ; Temporarily retain the encoded exponent.
        OR A                        ; Zero selects the subnormal representation.
        JP Z,SRTFSUB                 ; Subnormals use a fixed binary scale of 2^-24.
        SET 2,D                     ; Normal values have the implicit significand bit.
        LD (SRTFSIG),DE              ; Save the complete normal significand.
        LD A,(SRTFEXP)              ; Fetch the encoded exponent again.
        CP 25                       ; Fields below 25 leave a decimal fraction.
        JP C,SRTFFRAC                ; Convert the fractional power of two.
        SUB 25                      ; Fields 25..30 shift the integer significand.
        LD B,A                      ; B counts the required binary left shifts.
        LD HL,(SRTFSIG)              ; Start with the eleven-bit significand.
        LD A,B                       ; A zero means the significand already is an integer.
        OR A                         ; Test the exponent-field-25 boundary explicitly.
        JP Z,SRTFINT                 ; Avoid DJNZ's 256-iteration interpretation of zero.
SRTFSH:
        ADD HL,HL                   ; Shift the exact integer magnitude one place.
        DJNZ SRTFSH                 ; Repeat until the binary exponent is consumed.
SRTFINT:
        XOR A                       ; This finite value has no decimal fraction.
        LD (SRTFEXP),A              ; The output path will append .0 for a float.
        LD (SRTFSIG),HL              ; Retain the shifted integer magnitude.
        JP SRTFSET                  ; Convert the magnitude to decimal digits.

; Decode a subnormal value, whose significand is already in DE.
SRTFSUB:
        LD (SRTFSIG),DE              ; Subnormal fraction bits are the significand.
        LD A,24                      ; Every subnormal uses the scale 2^-24.
        LD (SRTFEXP),A              ; The decimal path will multiply by five 24 times.
        LD A,D                      ; A zero subnormal is a signed zero, not a fraction.
        OR E                        ; Include both significand bytes in the zero test.
        JP NZ,SRTFSET               ; Nonzero subnormals keep the 2^-24 scale.
        XOR A                       ; Signed zero is rendered through the integer-valued path.
        LD (SRTFEXP),A              ; The printer will append the required .0 suffix.
        JP SRTFSET                  ; Zero is handled by the same digit path.

; Convert a normal value with exponent field 1..24 to decimal digits.
SRTFFRAC:
        LD B,A                      ; Preserve the encoded exponent while subtracting.
        LD A,25                     ; Normal value scale is significand * 2^(e-25).
        SUB B                       ; A is the number of binary fractional places.
        LD (SRTFEXP),A              ; Store the decimal fractional-place count.
        JP SRTFSET                  ; Build and scale the decimal digit array.

; Print the named exceptional binary16 values.
SRTFSPEC:
        LD HL,(SRTFVAL)              ; Recover the complete exceptional payload.
        LD DE,7E00H                 ; Canonical NaN is the only accepted NaN encoding.
        OR A                        ; Clear carry before the equality subtraction.
        SBC HL,DE                    ; Compare the value against canonical NaN.
        JP Z,SRTFNAN                 ; Print the Scheme NaN spelling.
        LD HL,(SRTFVAL)              ; Restore the value for the positive infinity test.
        LD DE,7C00H                 ; Positive infinity has no fraction bits.
        OR A                        ; Clear carry before the second comparison.
        SBC HL,DE                    ; Check the positive infinity encoding.
        JP Z,SRTFIP                  ; Print +inf.0.
        LD DE,SRTFIMSG               ; The remaining valid exceptional value is -inf.0.
        JP SRTFMSG                   ; Print the selected dollar-terminated message.
SRTFNAN:
        LD DE,SRTFNMSG               ; Select the canonical +nan.0 spelling.
        JP SRTFMSG                   ; Print the selected dollar-terminated message.
SRTFIP:
        LD DE,SRTFIPMS               ; Select the +inf.0 spelling.
        JP SRTFMSG                   ; Print the selected dollar-terminated message.

; Convert the saved nonnegative significand into least-significant-first digits.
SRTFSET:
        LD HL,SRTFDIG                ; The digit array starts empty.
        LD (SRTFPTR),HL              ; Save the next free digit position.
        XOR A                        ; No decimal digits have been written yet.
        LD (SRTFDN),A               ; Reset the digit count for this value.
        LD HL,(SRTFSIG)              ; Load the binary16 significand or shifted integer.
        LD DE,10                     ; Repeated subtraction divides by ten.
SRTFDIV:
        LD BC,0                      ; BC accumulates the full 16-bit quotient.
SRTFDVL:
        OR A                        ; Clear carry before subtracting the divisor.
        SBC HL,DE                    ; Try one more ten in the current quotient.
        JP C,SRTFDVR                ; A borrow leaves the remainder in HL.
        INC BC                       ; Count the successful subtraction without overflow.
        JP SRTFDVL                  ; Continue until the quotient is complete.
SRTFDVR:
        ADD HL,DE                   ; Restore the first value below zero.
        LD A,L                      ; The remainder is the low digit 0..9.
        ADD A,'0'                   ; Store it as an ASCII byte.
        LD HL,(SRTFPTR)             ; Recover the next free digit address.
        LD (HL),A                   ; Save the least-significant digit first.
        INC HL                      ; Advance to the next decimal digit position.
        LD (SRTFPTR),HL             ; Publish the updated digit cursor.
        LD A,(SRTFDN)               ; Count the digit just stored.
        INC A                       ; One more digit belongs to this value.
        LD (SRTFDN),A              ; Keep the count beside the digit array.
        LD A,B                      ; A zero quotient ends the conversion.
        OR C                        ; Test both quotient bytes through the zero flag.
        JP Z,SRTFMUL                ; The complete significand is now represented.
        LD H,B                      ; Restore the high quotient byte for the next divide.
        LD L,C                      ; Restore the low quotient byte for the next divide.
        JP SRTFDIV                 ; Extract the following decimal digit.

; Multiply the decimal digit array by five for each binary fractional place.
SRTFMUL:
        LD A,(SRTFEXP)              ; A counts the required powers of five.
        LD (SRTFCNT),A              ; Keep the loop counter outside the digit pass.
        XOR A                        ; No leading zeroes have been discarded yet.
        LD (SRTFST),A               ; The first live digit remains at array offset zero.
SRTFMLP:
        LD A,(SRTFCNT)              ; Stop after all powers of five are applied.
        OR A                        ; A zero count selects the trimming pass.
        JP Z,SRTFTRIM               ; Remove only fractional trailing zeroes.
        DEC A                       ; Consume one multiplication by five.
        LD (SRTFCNT),A              ; Publish the remaining multiplication count.
        LD A,(SRTFDN)               ; Every live digit participates in the product.
        LD B,A                      ; B controls the digit loop.
        LD HL,SRTFDIG               ; Begin with the least-significant digit.
        XOR A                        ; The first digit has no incoming carry.
        LD C,A                      ; C carries the quotient after division by ten.
SRTFML:
        LD A,(HL)                   ; Recover the current ASCII digit.
        SUB '0'                     ; Work with its numeric value.
        LD D,A                      ; Preserve the original digit for multiplication.
        ADD A,A                     ; Double the digit.
        ADD A,A                     ; Four times the digit.
        ADD A,D                     ; Five times the digit.
        LD D,A                      ; Keep the product while adding the carry.
        LD A,C                      ; Add the carry from the previous digit.
        ADD A,D                     ; The total is at most 49.
        LD D,A                      ; D now holds the complete digit product.
        XOR A                        ; Reset C before forming the new decimal carry.
        LD C,A                      ; The carry starts at zero for this digit.
SRTFMQ:
        LD A,D                      ; Test whether the product still contains ten.
        CP 10                       ; A decimal carry is needed at ten or above.
        JP C,SRTFMD                 ; The remaining value is the output digit.
        SUB 10                      ; Remove one ten from the product.
        LD D,A                      ; Preserve the reduced output digit.
        INC C                       ; Count the ten carried to the next digit.
        JP SRTFMQ                   ; Continue until the output digit is below ten.
SRTFMD:
        LD A,D                      ; Recover the reduced numeric digit.
        ADD A,'0'                   ; Store the updated ASCII representation.
        LD (HL),A                   ; Replace the current least-significant digit.
        INC HL                      ; Advance to the next digit in the product.
        DJNZ SRTFML                 ; Continue through the original digit count.
        LD A,C                      ; A nonzero carry extends the digit array.
        OR A                        ; Test whether a new most-significant digit exists.
        JP Z,SRTFMLP                ; No extension is needed for this multiplication.
        ADD A,'0'                   ; The carry is a single decimal digit 1..4.
        LD (HL),A                   ; Append it after the existing most-significant digit.
        LD A,(SRTFDN)               ; Extend the live digit count by one.
        INC A                       ; The appended carry is now part of the product.
        LD (SRTFDN),A              ; Publish the extended digit count.
        JP SRTFMLP                 ; Apply another power of five if required.

; Drop zeroes at the least-significant end while they are fractional places.
SRTFTRIM:
        LD A,(SRTFEXP)              ; Only fractional digits may be trimmed.
        OR A                        ; An integer-valued float needs no trimming.
        JP Z,SRTFOUT                ; The output path will add the required .0.
        LD HL,SRTFDIG               ; Start at the current least-significant digit.
        LD A,(SRTFST)               ; Move past zeroes removed by earlier iterations.
        LD E,A                      ; Widen the array offset to a word.
        LD D,0                      ; The digit array has a byte-sized offset.
        ADD HL,DE                   ; HL now addresses the least-significant live digit.
        LD A,(HL)                   ; Inspect the candidate fractional trailing digit.
        CP '0'                      ; A zero can be removed without changing the value.
        JP NZ,SRTFOUT               ; A nonzero digit is the final fractional place.
        LD A,(SRTFST)               ; Advance the live-array start past the zero.
        INC A                       ; The next digit becomes least significant.
        LD (SRTFST),A               ; Preserve the trimmed prefix count.
        LD A,(SRTFDN)               ; Remove the discarded digit from the live count.
        DEC A                       ; At least one nonzero digit remains for a nonzero value.
        LD (SRTFDN),A               ; Publish the shorter live digit array.
        LD A,(SRTFEXP)              ; Remove one fractional decimal place as well.
        DEC A                       ; The point moves with the discarded trailing zero.
        LD (SRTFEXP),A              ; Keep the reduced fractional-place count.
        JP SRTFTRIM                ; Continue while the new trailing digit is zero.

; Render the decimal digit array into the CP/M output buffer.
SRTFOUT:
        LD HL,SRTBUF                ; Begin the completed line at the shared buffer.
        LD (SRTFPTR),HL             ; SRTFPUT appends each character here.
        LD A,(SRTFSIGN)             ; A nonzero sign needs a leading minus character.
        OR A                        ; Test the saved binary16 sign.
        JP Z,SRTFNS                 ; Positive values omit the sign.
        LD A,'-'                    ; Signed zero and negative finite values keep it.
        CALL SRTFPUT                ; Append the minus sign to the output buffer.
SRTFNS:
        LD A,(SRTFDN)               ; The live digit count is the total product length.
        LD B,A                      ; Preserve the count while comparing the point.
        LD A,(SRTFEXP)              ; C will hold the fractional digit count.
        LD C,A                      ; Copy the point position into the loop register.
        LD A,B                      ; Recover the total digit count for subtraction.
        SUB C                       ; A is the number of integer digits when nonnegative.
        JP C,SRTFLESS               ; Fewer product digits means a leading zero integer.
        LD (SRTFINN),A              ; Save the integer digit count for the reverse pass.
        OR A                        ; An equal count still needs an explicit integer zero.
        JP Z,SRTFNOIN               ; Print zero before the decimal point.
        CALL SRTFDST                ; Point HL at the most-significant live digit.
        LD A,(SRTFINN)              ; B counts the integer digits to emit.
        LD B,A                      ; Copy the byte count into the reverse loop.
        CALL SRTFREV                ; Emit integer digits and leave HL at the fraction.
        JP SRTFDOT                 ; Append the decimal point and fraction.
SRTFNOIN:
        LD A,'0'                    ; Fractions equal to one still need an integer zero.
        CALL SRTFPUT                ; Append the leading zero.
        CALL SRTFDST                ; Start the fractional reverse pass at the top digit.
SRTFDOT:
        LD A,'.'                    ; Every float spelling contains a decimal point.
        CALL SRTFPUT                ; Append the point between integer and fraction.
        LD A,(SRTFEXP)              ; A zero count denotes an integer-valued float.
        OR A                        ; Test whether any fractional digits remain.
        JP Z,SRTFZERO               ; Append the mandatory zero after the point.
        LD B,A                      ; B counts the fractional digits to emit.
        CALL SRTFREV                ; Emit the remaining product digits in reverse order.
        JP SRTFFIN                  ; Terminate and print the completed buffer.
SRTFZERO:
        LD A,'0'                    ; Integer-valued floats use a .0 suffix.
        CALL SRTFPUT                ; Append the suffix digit.
        JP SRTFFIN                  ; Terminate and print the completed buffer.

; Render a value smaller than one, adding the zeroes between point and digits.
SRTFLESS:
        LD A,'0'                    ; The integer part is zero when D is below n.
        CALL SRTFPUT                ; Append the leading integer zero.
        LD A,'.'                    ; The decimal point precedes the leading fraction zeroes.
        CALL SRTFPUT                ; Append the point before the fractional digits.
        LD A,C                      ; Recover the fractional count n.
        LD D,A                      ; Preserve n while subtracting the digit count.
        LD A,(SRTFDN)               ; Recover the product digit count D.
        LD E,A                      ; E is the number of leading zeroes required.
        LD A,D                      ; Start with the full fractional-place count.
        SUB E                       ; A is n-D and is positive on this path.
        LD B,A                      ; B counts zeroes before the first product digit.
SRTFLZ:
        LD A,'0'                    ; Each missing product digit is a leading zero.
        CALL SRTFPUT                ; Append one fractional zero.
        DJNZ SRTFLZ                 ; Continue until the product reaches the point.
        CALL SRTFDST                ; Point HL at the product's most-significant digit.
        LD A,(SRTFDN)               ; B counts every remaining product digit.
        LD B,A                      ; Copy the count into the reverse loop.
        CALL SRTFREV                ; Emit the product digits after the leading zeroes.
        JP SRTFFIN                  ; Terminate and print the completed buffer.

; Return HL at the most-significant live decimal digit.
SRTFDST:
        LD HL,SRTFDIG               ; Start at the physical digit-array base.
        LD A,(SRTFST)               ; Add the number of discarded low digits.
        LD E,A                      ; Widen the offset for pointer arithmetic.
        LD D,0                      ; The digit-array offset is byte-sized.
        ADD HL,DE                   ; Skip the discarded low digits.
        LD A,(SRTFDN)               ; Move to the final live digit.
        DEC A                       ; The count is one-based for this offset.
        LD E,A                      ; Widen the final-digit offset.
        LD D,0                      ; Keep the high offset byte clear.
        ADD HL,DE                   ; Return the most-significant live digit address.
        RET                         ; SRTFREV consumes digits downward from HL.

; Emit B live digits from HL in most-significant-first order.
SRTFREV:
        LD A,B                      ; A zero count has nothing to append.
        OR A                        ; Set Z without disturbing the digit pointer.
        RET Z                       ; Return after an empty reverse pass.
SRTFRL:
        LD A,(HL)                   ; Load the current ASCII digit.
        CALL SRTFPUT                ; Append it without changing the digit pointer.
        DEC HL                      ; Move toward the next less-significant digit.
        DJNZ SRTFRL                 ; Continue through the requested digit count.
        RET                         ; HL now points just before the emitted range.

; Append one character to the decimal output buffer.
SRTFPUT:
        LD DE,(SRTFPTR)             ; Recover the next free output byte.
        LD (DE),A                   ; Store the character in the shared buffer.
        INC DE                      ; Advance the output cursor.
        LD (SRTFPTR),DE             ; Publish the cursor for the next character.
        RET                         ; The caller keeps its digit pointer and counters.

; Add the BDOS terminator and send the completed decimal spelling.
SRTFFIN:
        LD HL,(SRTFPTR)             ; Locate the first byte after the final digit.
        LD (HL),'$'                 ; BDOS function 9 stops at the dollar byte.
        LD DE,SRTBUF                ; DE selects the completed output buffer.
        LD C,9                      ; CP/M function 9 prints a dollar-terminated string.
        JP 5                         ; Send only the value; newline is a separate primitive.

; Print one of the fixed special-value messages selected by DE.
SRTFMSG:
        LD C,9                      ; CP/M function 9 prints a dollar-terminated string.
        CALL 5                      ; Send +inf.0, -inf.0 or +nan.0 to the console.
        RET                         ; Return to the generated program continuation.

SRTFNMSG: DB "+nan.0$"              ; Canonical Scheme NaN spelling.
SRTFIPMS: DB "+inf.0$"              ; Positive infinity spelling.
SRTFIMSG: DB "-inf.0$"              ; Negative infinity spelling.

; Private nonreentrant state for the finite decimal conversion.
SRTFVAL:  DW 0                     ; Original binary16 payload.
SRTFSIG: DW 0                     ; Positive significand or shifted integer.
SRTFSIGN: DB 0                     ; Original sign bit, either zero or 80H.
SRTFEXP:  DB 0                     ; Decimal fractional-place count.
SRTFCNT:  DB 0                     ; Remaining powers of five.
SRTFST:   DB 0                     ; Number of discarded low decimal digits.
SRTFDN:   DB 0                     ; Number of live least-significant-first digits.
SRTFINN:  DB 0                     ; Number of integer digits in the output.
SRTFPTR:  DW 0                     ; Current output or digit-array cursor.
SRTFDIG:  DS 24                    ; ASCII decimal digits, least significant first.
