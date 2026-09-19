; Standalone runtime for one arithmetic expression.
;
; The compiler patches ARROP, ARRLT, ARRLV, ARRRT, and ARRRV before it writes
; the object.  At run time the dispatcher selects the numeric operation,
; formats either a signed integer or a binary16 result, and returns to CP/M.
; The fixed stack limit is shared with the compiler's guarded memory map.
;
; Numeric ABI on entry to NADD/NSUB/NMUL/NDIV:
;   A = left value tag, B = right value tag, HL = left payload, DE = right.
; The service returns A = result tag and HL = result payload, with carry set
; for overflow, invalid input, or division by zero.
ORG 0100H

ARRSTART:
        LD SP,8000H               ; Private runtime stack below the CP/M TPA ceiling.
        ; ARROP is the compact operation code written by the emitter:
        ; 0 add, 1 subtract, 2 multiply, 3 divide.
        LD A,(ARROP)               ; Load the compact operation code patched by the compiler.
        CP 0                       ; Zero selects addition.
        JP Z,ARRADD                ; Run the addition service.
        CP 1                       ; One selects subtraction.
        JP Z,ARRSUB                ; Run the subtraction service.
        CP 2                       ; Two selects multiplication.
        JP Z,ARRMUL                ; Run the multiplication service.
        CP 3                       ; Three selects division.
        JP Z,ARRDIV                ; Run the division service.
        JP ARRERR                  ; Any other code is a malformed image.

; Each operation reloads the patched operands because the numeric routines may
; change their working registers while computing the result.
ARRADD:
        LD A,(ARRRT)               ; Load the right representation tag.
        LD B,A                     ; Numeric ABI places that tag in B.
        LD A,(ARRLT)               ; Load the left representation tag.
        LD HL,(ARRLV)              ; Load the left payload into HL.
        LD DE,(ARRRV)              ; Load the right payload into DE.
        CALL NADD                  ; Add the two tagged values.
        JP C,ARRERR                ; Report overflow or invalid input.
        JP ARRPRINT                ; Format the successful numeric result.
ARRSUB:
        LD A,(ARRRT)               ; Load the right representation tag.
        LD B,A                     ; Numeric ABI places that tag in B.
        LD A,(ARRLT)               ; Load the left representation tag.
        LD HL,(ARRLV)              ; Load the left payload into HL.
        LD DE,(ARRRV)              ; Load the right payload into DE.
        CALL NSUB                  ; Subtract the two tagged values.
        JP C,ARRERR                ; Report overflow or invalid input.
        JP ARRPRINT                ; Format the successful numeric result.
ARRMUL:
        LD A,(ARRRT)               ; Load the right representation tag.
        LD B,A                     ; Numeric ABI places that tag in B.
        LD A,(ARRLT)               ; Load the left representation tag.
        LD HL,(ARRLV)              ; Load the left payload into HL.
        LD DE,(ARRRV)              ; Load the right payload into DE.
        CALL NMUL                  ; Multiply the two tagged values.
        JP C,ARRERR                ; Report overflow or invalid input.
        JP ARRPRINT                ; Format the successful numeric result.
ARRDIV:
        LD A,(ARRRT)               ; Load the right representation tag.
        LD B,A                     ; Numeric ABI places that tag in B.
        LD A,(ARRLT)               ; Load the left representation tag.
        LD HL,(ARRLV)              ; Load the left payload into HL.
        LD DE,(ARRRV)              ; Load the right payload into DE.
        CALL NDIV                  ; Divide the two tagged values.
        JP C,ARRERR                ; Report overflow or division by zero.

; Store the numeric result before choosing its text representation.  Tag 3 is
; an exact signed integer; every other successful tag in this product is the
; two-byte binary16 representation.
ARRPRINT:
        LD (ARRRES),HL             ; Retain the result payload for the formatter.
        LD (ARRREST),A              ; Retain the result representation tag.
        CP 3                       ; Exact signed integers use decimal output.
        JP Z,ARRINT                ; Format the integer result.
        JP ARRF16                  ; Other successful results use binary16 hex.

ARRINT:
        ; Convert the signed payload to magnitude, retaining the minus sign.
        LD HL,(ARRRES)             ; Copy the signed result into the subtraction workspace.
        LD DE,ARRMSG               ; DE points at the start of the output buffer.
        BIT 7,H                    ; Test the sign bit of the 16-bit payload.
        JR Z,ARRIPOS               ; A non-negative value needs no sign character.
        LD A,'-'                   ; Emit the sign before converting to magnitude.
        LD (DE),A                  ; Store the sign at the current buffer position.
        INC DE                     ; Advance past the sign.
        XOR A                      ; Clear A before the low-byte two's complement.
        SUB L                      ; Negate the low byte.
        LD L,A                     ; Keep the low magnitude byte in L.
        XOR A                      ; Clear A before propagating the borrow.
        SBC A,H                    ; Negate the high byte with the low-byte borrow.
        LD H,A                     ; Keep the high magnitude byte in H.
ARRIPOS:
        LD (ARRPTR),DE             ; Save the next output position for ARRPLACE.
        XOR A                      ; Suppress leading zeroes initially.
        LD (ARRBEG),A              ; ARRBEG becomes set after the first digit.
        LD DE,10000                 ; Select the ten-thousands place.
        CALL ARRPLACE               ; Append it when non-zero or required.
        LD DE,1000                  ; Select the thousands place.
        CALL ARRPLACE               ; Append it when non-zero or required.
        LD DE,100                   ; Select the hundreds place.
        CALL ARRPLACE               ; Append it when non-zero or required.
        LD DE,10                    ; Select the tens place.
        CALL ARRPLACE               ; Append it when non-zero or required.
        LD A,1                      ; Units must always be emitted.
        LD (ARRBEG),A              ; Permit a zero units digit after a prefix.
        LD DE,1                     ; Select the units place.
        CALL ARRPLACE               ; Append the final decimal digit.
        JP ARRMSGED                 ; Terminate and print the message.

ARRPLACE:
        ; Subtract one decimal place until the digit would become negative.
        ; ARRBEG suppresses leading zeroes but always permits the units digit.
        LD B,0                     ; B counts how many times the place value fits.
ARRPLP:
        OR A                       ; Clear carry before the signed subtraction.
        SBC HL,DE                  ; Try subtracting one decimal place value.
        JR C,ARRPLDN               ; A borrow means the next digit would be negative.
        INC B                      ; Count one more occurrence of the place value.
        JR ARRPLP                  ; Continue until the place no longer fits.
ARRPLDN:
        ADD HL,DE                  ; Restore the first value that did not fit.
        LD A,B                     ; Copy the digit count for the output tests.
        OR A                       ; Set flags from the digit count.
        JR NZ,ARRPLOUT              ; A non-zero digit always becomes output.
        LD A,(ARRBEG)              ; Check whether an earlier digit was emitted.
        OR A                       ; Test the leading-zero state.
        RET Z                      ; Suppress this zero until a later place is used.
ARRPLOUT:
        LD A,1                     ; Mark that subsequent zeroes are significant.
        LD (ARRBEG),A              ; Store the leading-digit state.
        LD A,B                     ; Convert the decimal digit count to a character.
        ADD A,'0'                  ; Add the ASCII zero offset.
        PUSH HL                    ; Preserve the remaining numeric value.
        LD HL,(ARRPTR)             ; Load the next message position.
        LD (HL),A                  ; Write this digit.
        INC HL                     ; Advance to the following message position.
        LD (ARRPTR),HL             ; Save the advanced position.
        POP HL                     ; Restore the remaining numeric value.
        RET                        ; Return for the next decimal place.

ARRF16:
        ; Binary16 output is intentionally diagnostic hexadecimal (F16:hhhh),
        ; so formatting it never needs a floating-point conversion routine.
        LD DE,ARRMSG               ; Start the diagnostic prefix at the buffer base.
        LD A,'F'                   ; Write the first prefix character.
        LD (DE),A                  ; Store F.
        INC DE                     ; Advance past F.
        LD A,'1'                   ; Write the second prefix character.
        LD (DE),A                  ; Store 1.
        INC DE                     ; Advance past 1.
        LD A,'6'                   ; Write the third prefix character.
        LD (DE),A                  ; Store 6.
        INC DE                     ; Advance past 6.
        LD A,':'                   ; Separate the prefix from the hexadecimal digits.
        LD (DE),A                  ; Store the colon.
        INC DE                     ; Point at the first hexadecimal digit.
        LD (ARRPTR),DE             ; Give ARRBYTE the output cursor.
        LD HL,(ARRRES)             ; Reload the result payload.
        LD A,H                     ; Format the high byte first.
        CALL ARRBYTE               ; Append two hexadecimal nibbles.
        LD HL,(ARRRES)             ; Reload the result payload for the low byte.
        LD A,L                     ; Format the low byte second.
        CALL ARRBYTE               ; Append the final two hexadecimal nibbles.
ARRMSGED:
        LD HL,(ARRPTR)             ; Load the first unused message position.
        LD (HL),13                 ; Terminate the line with carriage return.
        INC HL                     ; Advance to the line-feed position.
        LD (HL),10                 ; Terminate the line with line feed.
        INC HL                     ; Advance to CP/M's string terminator position.
        LD (HL),'$'                ; Function 9 requires a dollar terminator.
        LD DE,ARRMSG               ; DE points to the completed message.
        LD C,9                     ; CP/M function 9 prints a dollar-terminated string.
        CALL 5                     ; Display the result and return status to CP/M.
        JP 0                       ; End the COM program through the CP/M warm start.

ARRBYTE:
        ; Emit the high nibble first, then the low nibble.
        PUSH AF                    ; Preserve the original byte for the low nibble.
        SRL A                      ; Shift the high nibble into the low four bits.
        SRL A                      ; Continue the high-nibble extraction.
        SRL A                      ; Continue the high-nibble extraction.
        SRL A                      ; Leave only the original high nibble.
        CALL ARRNIB                ; Append that high nibble.
        POP AF                     ; Restore the original byte.
        AND 15                     ; Mask it down to the low nibble.
        JP ARRNIB                  ; Append the low nibble and return.
ARRNIB:
        CP 10                      ; Values below ten use decimal hexadecimal digits.
        JR C,ARRDIG                ; Keep 0--9 unchanged.
        ADD A,7                     ; Map 10--15 to A--F after adding the zero offset.
ARRDIG:
        ADD A,'0'                  ; Convert the nibble to its ASCII representation.
        LD HL,(ARRPTR)             ; Load the output cursor.
        LD (HL),A                  ; Store one hexadecimal character.
        INC HL                     ; Advance the cursor.
        LD (ARRPTR),HL             ; Preserve it for the next nibble.
        RET                        ; Return to ARRBYTE or its caller.

ARRERR:
        ; All runtime arithmetic failures share a short CP/M console message.
        LD DE,ARRERRM              ; Point CP/M function 9 at the error message.
        LD C,9                     ; Select CP/M's dollar-terminated print function.
        CALL 5                     ; Display the error text.
        JP 0                       ; End the COM program through the CP/M warm start.

; The compiler patches these five fields in the checked payload.  The remaining
; words are runtime scratch and the CP/M function-9 message buffer.
ARROP:  DB 0                     ; Patched operation code: add, subtract, multiply or divide.
ARRLT:  DB 3                     ; Patched left operand representation tag.
ARRLV:  DW 0                     ; Patched left operand payload.
ARRRT:  DB 3                     ; Patched right operand representation tag.
ARRRV:  DW 0                     ; Patched right operand payload.
ARRRES: DW 0                     ; Result payload retained while it is formatted.
ARRREST: DB 0                    ; Result representation tag retained by ARRPRINT.
ARRPTR: DW 0                     ; Current output position in ARRMSG.
ARRBEG: DB 0                     ; Non-zero after ARRINT has emitted its first digit.
ARRMSG: DS 16                    ; CP/M function-9 result buffer including CR/LF/$.
ARRERRM: DB "RUNTIME ERROR",13,10,"$" ; Failure text for arithmetic/runtime errors.
