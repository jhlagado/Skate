; Scheme value and pair printing through the output adapter.
; Entry points: SRTWRVAL, SRTWPAIR, SRTWTAIL, SRTCH and SRTIN.
; Included in runtime order by ../data.asm.

SRTWRVAL:
        CP 3
        JP Z,SRTWRNUM
        CP 1
        JP Z,SRTWPAIR
        CP 4
        JP Z,SRTWRLIT
        CP 5
        JP Z,SRTWRSTR
        CP 6
        JP NZ,SRTWREST
        CALL SRTSVLD
        JP C,SRTERROR
        JP SRTWRSTR
SRTWREST:
        OR A
        JP NZ,SRTERROR
        LD A,H
        CP 0FFH
        JP Z,SRTWCHAR              ; Byte characters share the scalar tag with booleans.
        PUSH HL
        LD DE,0FE02H
        OR A
        SBC HL,DE
        POP HL
        JR Z,SRTWNIL
        PUSH HL
        LD DE,0FE03H
        OR A
        SBC HL,DE
        POP HL
        JR Z,SRTWEOFV
        PUSH HL
        LD DE,0FE04H
        OR A
        SBC HL,DE
        POP HL
        JR Z,SRTWUNS
        PUSH HL                    ; Compare the false payload without changing it.
        LD DE,0FE00H               ; #f is the reserved false scalar.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,DE                  ; Test whether the payload is exactly FE00H.
        POP HL                     ; Restore the value for the following formatter.
        JR Z,SRTWBOOL              ; Preserve the established #t spelling.
        PUSH HL                    ; Compare the true payload without changing it.
        LD DE,0FE01H               ; #t is the reserved true scalar.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,DE                  ; Test whether the payload is exactly FE01H.
        POP HL                     ; Restore the value for the following formatter.
        JR Z,SRTWBOOL              ; Preserve the established #t spelling.
        PUSH HL
        XOR A
        CALL NCLASS
        POP HL
        JP NC,SRTFPRN
SRTWBOOL:
        LD DE,SRTWQF
        LD A,H
        CP 0FEH
        JR NZ,SRTWMSG
        LD A,L
        OR A
        JR Z,SRTWMSG
        LD DE,SRTWQT
SRTWMSG:
        JP SRTTEXT

SRTWNIL:
        LD DE,SRTWNILT
        JP SRTTEXT

SRTWUNS:
        LD DE,SRTWUNST
        JP SRTTEXT

SRTWEOFV:
        LD DE,SRTWEOF
        JP SRTTEXT

; Print a character raw for display or as a hexadecimal reader spelling.
SRTWCHAR:
        LD A,(SRTWMODE)
        OR A
        JR Z,SRTWOUT
        LD A,35                    ; Prefix the readable character spelling with '#'.
        CALL SRTCH                  ; Send the hash byte through the BDOS-safe writer.
        LD A,92                    ; The second prefix byte is a backslash.
        CALL SRTCH                  ; Send the backslash through the BDOS-safe writer.
        LD A,'x'                    ; Hexadecimal spelling is valid for every byte.
        CALL SRTCH                  ; Send the hexadecimal marker.
        LD A,L                      ; Load the byte payload for hexadecimal output.
        CALL SRTWBYTE               ; Emit its two lower-case hexadecimal digits.
        RET                         ; The complete reader spelling is now emitted.
SRTWOUT:
        LD A,L                     ; Emit the byte payload itself.
        JP SRTCH

; Emit the two hexadecimal digits in one byte held in A.
SRTWBYTE:
        LD (SRTINB),A              ; Preserve the byte while selecting its nibbles.
        AND 0F0H                   ; Keep the high nibble of the byte.
        RRCA                       ; Shift the high nibble into the low position.
        RRCA                       ; Shift the high nibble into the low position.
        RRCA                       ; Shift the high nibble into the low position.
        RRCA                       ; Shift the high nibble into the low position.
        CALL SRTWHXD               ; Emit the selected high-nibble digit.
        LD A,(SRTINB)              ; Restore the original byte for its low nibble.
        AND 0FH                    ; Keep the low nibble.
        JP SRTWHXD                 ; Emit the selected low-nibble digit.

; Look up one hexadecimal digit and send it to the CP/M character writer.
SRTWHXD:
        LD E,A                     ; Use the nibble as a table offset.
        LD D,0                     ; Form a word-sized table index.
        LD HL,SRTWHX               ; Point at the lower-case digit table.
        ADD HL,DE                  ; Select the requested digit.
        LD A,(HL)                  ; Load the selected digit character.
        JP SRTCH                   ; Send it while preserving the formatter state.

SRTWPAIR:
        PUSH HL                     ; CP/M output is allowed to clobber HL.
        LD A,'('
        CALL SRTCH
        POP HL
        PUSH HL                     ; Keep the outer pair while printing its CAR.
        LD A,1                       ; The outer value has already selected pair output.
        CALL SRTCARV                ; Decode the packed CAR field through one helper.
        JP C,SRTERROR               ; A corrupt pair cannot be printed safely.
        CALL SRTWRVAL
        POP HL
        PUSH HL                     ; Keep the outer pair while inspecting its CDR.
        LD A,1                       ; Decode the packed CDR tag and payload together.
        CALL SRTCDRV
        JP C,SRTERROR               ; A corrupt pair cannot be printed safely.
        LD (SRTQATAG),A
        LD (SRTQAVAL),HL
        LD A,(SRTQATAG)
        CP 1
        JR NZ,SRTWRDOT
        LD HL,(SRTQAVAL)
        CALL SRTPCHK
        JR C,SRTWRDOT
        LD A,' '
        CALL SRTCH
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        CALL SRTWTAIL
        POP HL
        JR SRTWCLS
SRTWRDOT:
        LD A,(SRTQATAG)
        OR A
        JR NZ,SRTWRDV
        LD HL,(SRTQAVAL)
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JR Z,SRTWRNIL
SRTWRDV:
        LD A,' '
        CALL SRTCH
        LD A,'.'
        CALL SRTCH
        LD A,' '
        CALL SRTCH
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        CALL SRTWRVAL
        POP HL
        JR SRTWCLS
SRTWRNIL:
        POP HL
        JR SRTWCLS
SRTWCLS:
        LD A,')'
        JP SRTCH

; Print the tail of a proper list without opening another parenthesis.
SRTWTAIL:
        PUSH HL                     ; Preserve this pair across its CAR output.
        LD A,1
        CALL SRTCARV                ; Read the next CAR from the packed record.
        JP C,SRTERROR
        CALL SRTWRVAL
        POP HL
        PUSH HL                     ; Preserve this pair while inspecting its CDR.
        LD A,1
        CALL SRTCDRV                ; Read the next CDR and its packed tag.
        JP C,SRTERROR
        LD (SRTQATAG),A
        LD (SRTQAVAL),HL
        LD A,(SRTQATAG)
        CP 1
        JR NZ,SRTWTNIL
        LD HL,(SRTQAVAL)
        CALL SRTPCHK
        JR C,SRTWTDOT
        LD A,' '
        CALL SRTCH
        LD HL,(SRTQAVAL)
        CALL SRTWTAIL
        POP HL
        RET
SRTWTNIL:
        OR A
        JR NZ,SRTWTDOT
        LD HL,(SRTQAVAL)
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JR NZ,SRTWTDOT
        POP HL
        RET
SRTWTDOT:
        LD A,' '
        CALL SRTCH
        LD A,'.'
        CALL SRTCH
        LD A,' '
        CALL SRTCH
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        CALL SRTWRVAL
        POP HL
        RET

SRTWRSTR:
        PUSH HL                     ; Preserve the literal pointer across BDOS.
        LD A,'"'
        CALL SRTCH
        POP HL
        CALL SRTWRLIT
        LD A,'"'
        JP SRTCH
SRTWRLIT:
        LD B,(HL)
        INC HL
SRTWLLP:
        LD A,B
        OR A
        RET Z
        LD A,(HL)
        INC HL
        PUSH HL                     ; Preserve the literal cursor across BDOS.
        PUSH BC                     ; Preserve the remaining count across BDOS.
        CALL SRTCH
        POP BC
        POP HL
        DJNZ SRTWLLP
        RET

SRTWRNUM:
        XOR A
        LD (SRTWBEG),A
        BIT 7,H
        JR Z,SRTWNP
        LD A,'-'
        CALL SRTCH
        XOR A
        SUB L
        LD L,A
        LD A,0                    ; Preserve the low-byte borrow for negating H.
        SBC A,H
        LD H,A
SRTWNP:
        LD DE,10000
        CALL SRTWDIG
        LD DE,1000
        CALL SRTWDIG
        LD DE,100
        CALL SRTWDIG
        LD DE,10
        CALL SRTWDIG
        LD A,1
        LD (SRTWBEG),A
        LD DE,1
        JP SRTWDIG
SRTWDIG:
        LD B,0
SRTWDL:
        OR A
        SBC HL,DE
        JR C,SRTWDD
        INC B
        JR SRTWDL
SRTWDD:
        ADD HL,DE
        LD A,B
        OR A
        JR NZ,SRTWDOUT
        LD A,(SRTWBEG)
        OR A
        RET Z
SRTWDOUT:
        LD A,1
        LD (SRTWBEG),A
        LD A,B
        ADD A,'0'
        JP SRTCH

; Preserve the caller's numeric remainder and procedure continuation across BDOS.
SRTCH:
        PUSH AF                    ; Retain the value tag and flags.
        PUSH BC                    ; Retain loop counters.
        PUSH DE                    ; Retain the decimal divisor or data pointer.
        PUSH HL                    ; Retain the decimal remainder or literal cursor.
        PUSH IX                    ; Retain the primitive return continuation.
        PUSH IY                    ; Retain any active indexed runtime state.
        LD (SRTFBYTE),A            ; Keep the byte while selecting the output adapter.
        LD A,(SRTOUTS)
        OR A
        JR Z,.CONSOLE               ; The default path sends bytes to the provider hook.
        LD A,(SRTFBYTE)
        CALL SRTFWR               ; A file output port uses the CP/M file adapter.
        JR .CHECK
.CONSOLE:
        LD A,(SRTFBYTE)
        CALL SRTIOPC                 ; Send the byte through the selected provider.
.CHECK:
        JP C,SRTERROR                ; Provider failure follows the checked path.
        POP IY                     ; Restore the caller's indexed state.
        POP IX                     ; Restore the primitive continuation.
        POP HL                     ; Restore the numeric remainder.
        POP DE                     ; Restore the divisor or data pointer.
        POP BC                     ; Restore loop counters.
        POP AF                     ; Restore the original flags and value tag.
        RET                        ; Continue formatting or return to the primitive.

; Read one console byte while preserving the runtime continuation and cursors.
SRTIN:
        PUSH BC                    ; Preserve the caller's packet count and counters.
        PUSH DE                    ; Preserve the caller's data pointer or divisor.
        PUSH HL                    ; Preserve the caller's value payload or cursor.
        PUSH IX                    ; Preserve the generated continuation across BDOS.
        PUSH IY                    ; Preserve indexed runtime state used by collection.
        CALL SRTIOGC                ; Obtain one byte through the selected provider.
        JP C,SRTERROR              ; Empty or failed provider input is not EOF.
        LD (SRTINB),A              ; Stage the byte before restoring caller registers.
        POP IY                     ; Restore indexed runtime state.
        POP IX                     ; Restore the primitive return continuation.
        POP HL                     ; Restore the caller's payload or cursor.
        POP DE                     ; Restore the caller's pointer or divisor.
        POP BC                     ; Restore the caller's packet count and counters.
        LD A,(SRTINB)              ; Return the byte obtained from the console.
        RET                        ; The primitive maps Control-Z to the EOF value.
