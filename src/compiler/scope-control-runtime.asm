;=============================================================================
;  Runtime support for the scope and control compiler
;=============================================================================
;
;  The compiler writes a short native program after this image.  The program
;  uses the routines below for integer values, lexical slots, global slots,
;  branches and output.  Slot addresses are fixed up by the compiler after
;  the generated program and its data areas have been sized.
;
;  A value is returned as A=tag, HL=payload.  Integer values use tag 3;
;  #f and #t use tag 0 with payload 0 and 1 respectively.
;=============================================================================

ORG 0100H

SRTSTART:
        LD SP,0E000H              ; Keep the generated program below the guard.
SRTCALL:
        CALL 0000H                ; The compiler patches the generated entry.
        CALL SRTPRINT             ; Print the final value returned by the program.
        JP 0                      ; Return to CP/M through the warm start.

; Load a four-byte slot addressed by HL.  The final byte is the initialized
; flag; the preceding byte preserves the value tag for booleans.
SRTLOAD:
        LD E,(HL)                 ; Read the value's low byte.
        INC HL                    ; Advance to the high value byte.
        LD D,(HL)                 ; Read the value's high byte.
        INC HL                    ; Advance to the stored value tag.
        LD A,(HL)                 ; Recover the stored scalar tag.
        LD (SRTTAG),A             ; Preserve it while testing initialization.
        INC HL                    ; Advance to the initialized flag.
        LD A,(HL)                 ; A zero flag means the binding is unbound.
        OR A                      ; Set Z for the unbound case.
        JP Z,SRTUNBD           ; Never return a fabricated value.
        EX DE,HL                  ; Return the stored payload in HL.
        LD A,(SRTTAG)             ; Restore the stored value tag.
        RET                       ; Return the value to generated code.

; Store A:HL into the four-byte slot addressed by DE.
SRTSTORE:
        LD (SRTTAG),A             ; Preserve the value tag while writing payload bytes.
        LD A,L                    ; Copy the payload low byte to the slot.
        LD (DE),A                 ; Publish the low byte first.
        INC DE                    ; Advance to the high payload byte.
        LD A,H                    ; Copy the payload high byte.
        LD (DE),A                 ; Publish the complete payload.
        INC DE                    ; Advance to the stored value tag.
        LD A,(SRTTAG)             ; Copy the caller's tag into the slot.
        LD (DE),A                 ; Publish the tag after both payload bytes.
        INC DE                    ; Advance to the initialized flag.
        LD A,1                    ; Mark the slot initialized after all value bytes.
        LD (DE),A                 ; A later load can now observe the value.
        LD A,(SRTTAG)             ; Return the stored value tag to generated code.
        RET                       ; Return with the stored value still in HL.

; Return Z exactly when the value is #f, preserving A and HL for short-circuit
; forms.  Other tag-zero scalars are true when their payload is nonzero.
SRTFALSE:
        LD (SRTTAG),A        ; Keep the logical tag while checking payload.
        OR A                      ; Nonzero tags are always true.
        JR NZ,SRTTRUE             ; Leave the original value untouched.
        LD A,H                    ; A tag-zero value is false only at payload zero.
        OR L                      ; Combine the two payload bytes for the test.
        JR NZ,SRTTRUE             ; A nonzero scalar is true.
        XOR A                     ; Record the false result in the state byte.
        JR SRTBDONE            ; Restore the original tag before returning.
SRTTRUE:
        LD A,1                    ; Record a true branch decision.
SRTBDONE:
        LD (SRTBOOL),A            ; Keep the decision while restoring the tag.
        LD A,(SRTBOOL)            ; Set flags from the branch decision.
        OR A                      ; Z means false, NZ means true.
        LD A,(SRTTAG)        ; LD does not disturb the decision flags.
        RET                       ; Generated JP Z/JR Z reads the preserved flags.

; Binary helpers pop two values in the order emitted by the compiler and call
; the shared checked numeric ABI.  The helper keeps the generated code small.
SRTADD:
        XOR A                     ; Operation zero selects integer addition.
        JR SRTBIN              ; Join the common stack and dispatch path.
SRTSUB:
        LD A,1                    ; Operation one selects subtraction.
        JR SRTBIN              ; Join the common stack and dispatch path.
SRTMUL:
        LD A,2                    ; Operation two selects multiplication.
SRTBIN:
        LD (SRTOP),A              ; Save the operation while popping operands.
        POP IX                    ; Save the CALL return address above the values.
        POP DE                    ; Recover the right payload.
        POP BC                    ; Recover right AF; B is the right tag.
        POP HL                    ; Recover the left payload.
        POP AF                    ; Recover left AF; A is the left tag.
        LD (SRTTAG),A             ; Preserve the left tag while selecting the op.
        LD A,(SRTOP)              ; Select the checked operation.
        OR A                      ; Addition is the zero operation.
        JR Z,SRTDOADD             ; Call NADD with the recovered ABI values.
        CP 1                      ; Subtraction is operation one.
        JR Z,SRTDOSUB             ; Call NSUB with the recovered ABI values.
        CALL NMUL                 ; Operation two is checked multiplication.
        JR SRTBRES           ; Common carry handling and return.
SRTDOADD:
        LD A,(SRTTAG)             ; Restore the left tag for the numeric ABI.
        CALL NADD                 ; Checked addition uses A/B and HL/DE.
        JR SRTBRES           ; Common carry handling and return.
SRTDOSUB:
        LD A,(SRTTAG)             ; Restore the left tag for the numeric ABI.
        CALL NSUB                 ; Checked subtraction uses A/B and HL/DE.
SRTBRES:
        JP C,SRTERROR             ; Overflow or an invalid value is terminal.
        PUSH IX                   ; Restore the generated caller's return address.
        RET                       ; Return the checked value in A and HL.

; Format an exact integer and print it through CP/M function 9.
SRTPRINT:
        CP 3                      ; Only exact integers are printable here.
        JP NZ,SRTERROR            ; This release prints exact integer results only.
        LD (SRTRES),HL         ; Retain the result during decimal conversion.
        LD DE,SRTBUF          ; Start writing at the message buffer.
        BIT 7,H                   ; A negative value needs a leading minus sign.
        JR Z,SRTIPOS              ; Positive values go directly to place handling.
        LD A,'-'                  ; Store the sign before taking the magnitude.
        LD (DE),A                 ; Write the sign byte.
        INC DE                    ; Advance to the first digit.
        XOR A                     ; Clear A before the low-byte negation.
        SUB L                     ; Negate the low payload byte.
        LD L,A                    ; Retain the low magnitude byte.
        XOR A                     ; Clear A before propagating the borrow.
        SBC A,H                    ; Negate the high payload byte with borrow.
        LD H,A                    ; Retain the complete magnitude.
SRTIPOS:
        LD (SRTPTR),DE             ; Give the place routine its output cursor.
        XOR A                     ; No significant digit has been emitted yet.
        LD (SRTBEG),A         ; Suppress leading zeroes until needed.
        LD DE,10000                ; Select the ten-thousands place.
        CALL SRTPLACE              ; Append a digit when this place is used.
        LD DE,1000                 ; Select the thousands place.
        CALL SRTPLACE              ; Append a digit when this place is used.
        LD DE,100                  ; Select the hundreds place.
        CALL SRTPLACE              ; Append a digit when this place is used.
        LD DE,10                   ; Select the tens place.
        CALL SRTPLACE              ; Append a digit when this place is used.
        LD A,1                     ; Units must always be emitted.
        LD (SRTBEG),A          ; Permit a zero units digit after a prefix.
        LD DE,1                    ; Select the units place.
        CALL SRTPLACE              ; Append the final digit.
        LD HL,(SRTPTR)             ; Locate the first unused message position.
        LD (HL),13                 ; CP/M text output uses carriage return first.
        INC HL                     ; Advance to the line-feed position.
        LD (HL),10                 ; Complete the CP/M line ending.
        INC HL                     ; Advance to function 9's terminator byte.
        LD (HL),'$'                ; Function 9 stops at the dollar byte.
        LD DE,SRTBUF           ; DE points to the completed message.
        LD C,9                     ; Select CP/M's string-output function.
        CALL 5                     ; Print the result and return to the caller.
        RET                       ; Return to SRTSTART for the warm start.

; Subtract one decimal place until the next subtraction would borrow.
SRTPLACE:
        LD B,0                     ; B counts how often the place value fits.
SRTPLP:
        OR A                       ; Clear carry before the signed subtraction.
        SBC HL,DE                  ; Try one more occurrence of this place.
        JR C,SRTPLDN          ; A borrow means the digit is complete.
        INC B                      ; Count the place value that fitted.
        JR SRTPLP            ; Continue until the next one would borrow.
SRTPLDN:
        ADD HL,DE                  ; Restore the first value that did not fit.
        LD A,B                     ; Copy the digit count for output decisions.
        OR A                       ; A nonzero count always becomes a digit.
        JR NZ,SRTPLOUT          ; Emit a significant digit.
        LD A,(SRTBEG)          ; Check whether a prior place emitted a digit.
        OR A                       ; A zero state still suppresses this place.
        RET Z                      ; Leave a leading zero out of the message.
SRTPLOUT:
        LD A,1                     ; Later zeroes are significant after this one.
        LD (SRTBEG),A          ; Publish the started state.
        LD A,B                     ; Convert the count to its ASCII digit.
        ADD A,'0'                  ; Add the ASCII zero offset.
        PUSH HL                    ; Preserve the remaining numeric value.
        LD HL,(SRTPTR)             ; Load the next output position.
        LD (HL),A                  ; Store the decimal digit.
        INC HL                     ; Advance the output cursor.
        LD (SRTPTR),HL             ; Preserve it for the next place.
        POP HL                     ; Restore the remaining numeric value.
        RET                        ; Return for the next decimal place.

SRTUNBD:
        LD DE,SRTUNBT        ; Explain the unbound reference.
        JR SRTERRP           ; Share the CP/M error-output path.
SRTERROR:
        LD DE,SRTERRTX          ; Explain an arithmetic or runtime failure.
SRTERRP:
        LD C,9                     ; Select CP/M's dollar-terminated output.
        CALL 5                     ; Print the terminal diagnostic.
        JP 0                       ; Do not return with a damaged value stack.

; Patched entry and generated-program data fields.
SRTRES:    DW 0                 ; Result payload retained by SRTPRINT.
SRTPTR:       DW 0                 ; Current decimal-output cursor.
SRTBEG:   DB 0                 ; Nonzero after the first significant digit.
SRTTAG:  DB 0                 ; Original tag retained by SRTFALSE.
SRTBOOL:      DB 0                 ; Branch decision retained while restoring A.
SRTOP:        DB 0                 ; Selected checked arithmetic operation.
SRTBUF:   DS 16                ; Decimal output buffer including CR/LF/$.
SRTERRTX:  DB "RUNTIME ERROR",13,10,"$"
SRTUNBT: DB "UNBOUND",13,10,"$"

SRTEND:
