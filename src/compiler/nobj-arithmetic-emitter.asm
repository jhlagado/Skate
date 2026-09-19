;=============================================================================
;  NOBJ arithmetic-output emitter
;=============================================================================
;
;  The compiler publishes one checked NOBJ object whose image is also the
;  standalone COM program.  The image contains the numeric dispatcher and
;  formatter; this module patches only the operator and two source operands.
;  The generated program therefore produces the answer after compilation.
;=============================================================================

; Stream BC bytes from HL through the CP/M transport.  CTWRITE clobbers BC,
; so the pointer and remaining count live in private words.
ARSTREAM:
        LD (ARPTR),HL              ; Save the image pointer while CTWRITE uses HL.
        LD (ARLEFT),BC             ; Save the remaining byte count across each write.
ARSTLOOP:
        LD BC,(ARLEFT)             ; Load the count for the end-of-stream test.
        LD A,B                     ; Test the high count byte first.
        OR C                       ; Combine both count bytes into one zero test.
        JR Z,ARSTDONE              ; Return success when every byte has been written.
        LD HL,(ARPTR)              ; Load the next image byte address.
        LD A,(HL)                  ; Pass that byte to the transport routine.
        INC HL                     ; Advance the saved pointer before the call.
        LD (ARPTR),HL              ; Preserve the advanced pointer.
        CALL CTWRITE               ; Write one byte through the CP/M transport.
        RET C                      ; Propagate a transport failure unchanged.
        LD HL,(ARLEFT)             ; Reload the remaining count.
        DEC HL                     ; Account for the byte just written.
        LD (ARLEFT),HL             ; Save the decremented count.
        JR ARSTLOOP                ; Stream the next byte.
ARSTDONE:
        XOR A                      ; Clear carry to report a complete stream.
        RET                        ; Return to the publication state machine.

; Build the final NOBJ and COM FCBs from the command-tail basename.
ARFCBN:
        LD HL,005CH                ; Point at the command-tail FCB basename.
        LD DE,ARFCB                ; Point at the working NOBJ FCB.
        LD BC,9                    ; Copy drive and eight-character basename fields.
        LDIR                       ; Preserve the user's selected source name.
        LD HL,ARFCB+9              ; Point at the three-character extension.
        LD (HL),'N'                ; Set the first NOBJ extension character.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'O'                ; Set the second NOBJ extension character.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'B'                ; Set the final NOBJ extension character.
        RET                        ; Return with the NOBJ FCB prepared.
ARFCBC:
        LD HL,ARFCB+9              ; Point at the three-character extension.
        LD (HL),'C'                ; Set the first COM extension character.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'O'                ; Set the second COM extension character.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'M'                ; Set the final COM extension character.
        RET                        ; Return with the COM FCB prepared.

; Patch the generated image with the parsed expression.  Numeric services use
; tag 3 for exact integers and tag 0 for binary16 values.  The operator byte is
; compacted from its source character so the image has no parser dependency.
ARPATCH:
        LD A,(AROP)                ; Load the validated source operator character.
        CP '-'                    ; Test the subtraction operator.
        JR Z,ARPSUB                ; Select operation code one.
        CP '*'                    ; Test the multiplication operator.
        JR Z,ARPMUL                ; Select operation code two.
        CP '/'                    ; Test the division operator.
        JR Z,ARPDIV                ; Select operation code three.
        XOR A                      ; Addition is operation code zero.
        JR ARPOK                   ; Store the common operation field.
ARPSUB:
        LD A,1                      ; Encode subtraction as operation code one.
        JR ARPOK                    ; Store the common operation field.
ARPMUL:
        LD A,2                      ; Encode multiplication as operation code two.
        JR ARPOK                    ; Store the common operation field.
ARPDIV:
        LD A,3                      ; Encode division as operation code three.
ARPOK:
        LD (ARROPA),A              ; Patch the runtime operation byte.
        LD A,(ARLTAG)               ; Load the validated left representation tag.
        LD (ARRLTA),A               ; Patch the runtime left tag.
        LD HL,(ARLVAL)              ; Load the validated left payload.
        LD (ARRLVA),HL              ; Patch the runtime left payload.
        LD A,(ARRTAG)               ; Load the validated right representation tag.
        LD (ARRRTA),A               ; Patch the runtime right tag.
        LD HL,(ARRVAL)              ; Load the validated right payload.
        LD (ARRRVA),HL              ; Patch the runtime right payload.
        RET                         ; Return with the generated image complete.

; CRC-16/CCITT-FALSE covers every byte through the COMMIT header and payload,
; excluding only the two checksum bytes at the end of the generated object.
ARCRC:
        LD HL,AROBJ                ; Start the CRC at the serialized object header.
        LD DE,0FFFFH               ; CRC-16/CCITT-FALSE initial value.
        LD BC,ARCRCLN              ; Cover every byte except the checksum itself.
        CALL ARCRSEG               ; Accumulate the object bytes.
        PUSH DE                    ; Preserve the completed CRC while locating its field.
        LD HL,AROBJ                ; Restart at the object base.
        LD BC,ARCRCOF              ; Offset of the two-byte checksum field.
        ADD HL,BC                  ; Point at the checksum bytes.
        POP DE                     ; Restore the computed CRC.
        LD (HL),E                  ; Store the low checksum byte first.
        INC HL                     ; Advance to the high checksum byte.
        LD (HL),D                  ; Store the high checksum byte.
        RET                        ; Return with the serialized checksum installed.

ARCRSEG:
ARCRBY:
        LD A,B                     ; Test the high byte of the remaining length.
        OR C                       ; Include the low byte in the zero test.
        RET Z                      ; Return when all bytes have been covered.
        LD A,(HL)                  ; Load the next serialized object byte.
        INC HL                     ; Advance to the following object byte.
        XOR D                      ; Mix the byte into the high CRC register.
        LD D,A                     ; Keep the mixed high CRC byte.
        LD A,8                     ; Process all eight bits of this object byte.
        LD (ARBITS),A              ; Store the inner-loop bit count.
ARCRCBIT:
        SLA E                      ; Shift the low CRC byte toward the high byte.
        RL D                       ; Shift the high CRC byte and expose the carry.
        JR NC,ARCRCNOX             ; No polynomial reduction when the carry is clear.
        LD A,D                     ; Load the high CRC byte for the polynomial XOR.
        XOR 10H                    ; Apply the high polynomial byte.
        LD D,A                     ; Store the reduced high CRC byte.
        LD A,E                     ; Load the low CRC byte for the polynomial XOR.
        XOR 21H                    ; Apply the low polynomial byte.
        LD E,A                     ; Store the reduced low CRC byte.
ARCRCNOX:
        LD A,(ARBITS)              ; Load the remaining bit count.
        DEC A                      ; Account for the bit just processed.
        LD (ARBITS),A              ; Preserve the updated bit count.
        JR NZ,ARCRCBIT             ; Continue until all eight bits are shifted.
        DEC BC                     ; Account for the object byte just processed.
        JR ARCRBY                  ; Process the next object byte.

; Absolute addresses inside the serialized NOBJ image.  The image offset points at the
; six-byte IMAGE header's payload, so the same bytes stream directly to COM.
ARROPA EQU AROBJ+ARIMGOF+ARROPOF ; Absolute operation-byte address in the image.
ARRLTA EQU AROBJ+ARIMGOF+ARRLTOF ; Absolute left-tag address in the image.
ARRLVA EQU AROBJ+ARIMGOF+ARRLVOF ; Absolute left-payload address in the image.
ARRRTA EQU AROBJ+ARIMGOF+ARRRTOF ; Absolute right-tag address in the image.
ARRRVA EQU AROBJ+ARIMGOF+ARRRVOF ; Absolute right-payload address in the image.

ARCODE:   DB 0                    ; Parser diagnostic code returned to the command.
AROPEN:   DB 0                    ; Non-zero while the source FCB remains open.
AROP:     DB 0                    ; Validated source operator character.
ARLTAG:   DB 0                    ; Parsed left operand representation tag.
ARRTAG:   DB 0                    ; Parsed right operand representation tag.
ARLVAL:   DW 0                    ; Parsed left operand payload.
ARRVAL:   DW 0                    ; Parsed right operand payload.
ARPTR:    DW 0                    ; Current stream or object-image pointer.
ARLEFT:   DW 0                    ; Remaining stream byte count.
ARBITS:   DB 0                    ; CRC inner-loop bit count.
ARFCB:    DS 36                   ; Working NOBJ/COM CP/M file-control block.

; Reader contexts and diagnostics retained by the current command contract.
ARSYMCXT:                         ; Symbol interner context: table, count, arena, size.
          DW ARSYMS,16,ARSYMPL,512,0,0 ; Six words plus type and flags bytes.
          DB 0,0                   ; Symbol context kind and reserved flags.
ARSTRCXT:                         ; String interner context with an independent arena.
          DW ARSTRS,16,ARSTRPL,512,0,0 ; Six words plus type and flags bytes.
          DB 1,0                   ; String context kind and reserved flags.
ARSYMS:   DS 48                   ; Fixed symbol directory used by the reader.
ARSTRS:   DS 64                   ; Fixed string directory used by the reader.
ARSYMPL:  DS 512                  ; Symbol spelling arena.
ARSTRPL:  DS 512                  ; String spelling arena.

AROKTXT:  DB "COMPILED",13,10,"$"        ; Successful command message.
ARBADTXT: DB "COMPILE ERROR",13,10,"$"   ; Parser or numeric diagnostic.
ARIOTXT:  DB "SOURCE I/O ERROR",13,10,"$" ; Source open/read/close diagnostic.
AROUTTXT: DB "OUTPUT ERROR",13,10,"$"     ; NOBJ/COM write diagnostic.
ARMEMTXT: DB "INSUFFICIENT MEMORY",13,10,"$" ; Guard failure diagnostic.
