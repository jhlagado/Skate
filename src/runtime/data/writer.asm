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
        OR A                       ; Tag zero holds the scalar family below.
        JR Z,SRTWSCAL
        CP 2                       ; Closures print as opaque procedures.
        JR Z,SRTWPROC
        CP 7                       ; Vectors print with the #( reader syntax.
        JP Z,SRTWVEC
        CP 8                       ; Tag eight holds ports and escape tokens.
        JP NZ,SRTERROR             ; No other tag is a printable Scheme value.
        LD A,H                     ; Ports occupy the F000H token namespace.
        CP 0F0H
        JR NZ,SRTWPROC             ; An escape token is a callable procedure.
        LD DE,SRTWPRTT             ; Every port prints as one opaque spelling.
        JP SRTTEXT                 ; Send it through the selected output adapter.
SRTWPROC:
        LD DE,SRTWPRCT             ; Primitives, closures and escapes share this.
        JP SRTTEXT                 ; Send it through the selected output adapter.
SRTWSCAL:
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
        LD A,H                     ; Remaining FExx scalars are primitive values.
        CP 0FEH
        JR Z,SRTWPROC              ; Print them as procedures, not as booleans.
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

; Print a character raw for display, or in write mode as #\c, #\space,
; #\newline or #\xHH so the datum reader accepts the spelling again.
SRTWCHAR:
        LD A,(SRTWMODE)            ; Zero selects display's raw byte output.
        OR A
        JR Z,SRTWOUT
        LD A,35                    ; Prefix the readable character spelling with '#'.
        CALL SRTCH                 ; SRTCH preserves the character payload in HL.
        LD A,92                    ; The second prefix byte is a backslash.
        CALL SRTCH
        LD A,L                     ; Classify the character byte.
        LD DE,SRTWCNLT             ; Line feed has the reader name newline.
        CP 10
        JP Z,SRTTEXT
        LD DE,SRTWCSPT             ; Space has the reader name space.
        CP 32
        JP Z,SRTTEXT
        JR C,SRTWCHEX              ; Other controls use the hexadecimal spelling.
        CP 127                     ; Printable ASCII is spelled as itself.
        JP C,SRTCH
SRTWCHEX:
        LD A,'x'                   ; Hexadecimal spelling is valid for every byte.
        CALL SRTCH                 ; Send the hexadecimal marker.
        LD A,L                     ; Load the byte payload for hexadecimal output.
        JP SRTWBYTE                ; Emit its two lower-case hexadecimal digits.
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

; Print a tag-seven vector as #( elements ).  Elements recurse through
; SRTWRVAL; the cursor and remaining count are kept on the native stack.
SRTWVEC:
        CALL SRTVLD                ; Validate the block and return its base in HL.
        JP C,SRTERROR              ; A corrupt vector cannot be printed safely.
        LD A,35                    ; Open the vector with its reader prefix.
        CALL SRTCH                 ; SRTCH preserves the vector base in HL.
        LD A,'('                   ; Complete the opening delimiter.
        CALL SRTCH
        LD B,(HL)                  ; B counts the elements still to print.
        INC HL                     ; HL addresses the first four-byte element.
        LD A,B                     ; An empty vector closes immediately.
        OR A
        JR Z,SRTWVCLS
SRTWVLP:
        PUSH BC                    ; Keep the remaining count across recursion.
        PUSH HL                    ; Keep the element cursor across recursion.
        LD E,(HL)                  ; Read the element payload low byte.
        INC HL
        LD D,(HL)                  ; Read the element payload high byte.
        INC HL
        INC HL                     ; Skip the reserved extension byte.
        LD A,(HL)                  ; Read the element's logical tag.
        EX DE,HL                   ; A:HL is now the element value.
        CALL SRTWRVAL              ; Print the element in the current mode.
        POP HL                     ; Recover the element cursor.
        LD DE,4                    ; Advance to the next four-byte element.
        ADD HL,DE
        POP BC                     ; Recover the remaining count.
        DEC B                      ; Count the element just printed.
        JR Z,SRTWVCLS              ; The final element needs no separator.
        LD A,' '                   ; Separate consecutive elements.
        CALL SRTCH                 ; SRTCH preserves the cursor and count.
        JR SRTWVLP
SRTWVCLS:
        LD A,')'                   ; Close the vector spelling.
        JP SRTCH

; Print a string: display sends its bytes unchanged, while write quotes it
; and escapes quote, backslash and control bytes with the reader's spellings.
SRTWRSTR:
        LD A,(SRTWMODE)            ; Zero selects display's raw contents.
        OR A
        JR Z,SRTWRLIT
        LD A,34                    ; Open the readable string spelling.
        CALL SRTCH                 ; SRTCH preserves the string pointer.
        LD B,(HL)                  ; B counts the remaining string bytes.
        INC HL                     ; HL addresses the first string byte.
        LD A,B                     ; An empty string closes immediately.
        OR A
        JR Z,SRTWSEND
SRTWSLP:
        LD A,(HL)                  ; Fetch the next string byte.
        INC HL                     ; Advance before the formatter clobbers HL.
        PUSH HL                    ; Keep the string cursor across escapes.
        PUSH BC                    ; Keep the remaining count across escapes.
        CALL SRTWSCH               ; Emit the byte or its escape spelling.
        POP BC                     ; Recover the remaining count.
        POP HL                     ; Recover the string cursor.
        DJNZ SRTWSLP               ; Continue until every byte is written.
SRTWSEND:
        LD A,34                    ; Close the readable string spelling.
        JP SRTCH

; Emit one string byte from A using the reader's escape spellings.
SRTWSCH:
        LD C,A                     ; Quote and backslash follow a backslash.
        CP 34
        JR Z,SRTWSNAM
        CP 92
        JR Z,SRTWSNAM
        LD C,'n'                   ; Line feed is spelled \n.
        CP 10
        JR Z,SRTWSNAM
        LD C,'r'                   ; Carriage return is spelled \r.
        CP 13
        JR Z,SRTWSNAM
        LD C,'t'                   ; Tab is spelled \t.
        CP 9
        JR Z,SRTWSNAM
        CP 32                      ; Other controls use the \xHH; escape.
        JR C,SRTWSHEX
        CP 127                     ; Printable ASCII is emitted unchanged.
        JP C,SRTCH
SRTWSHEX:
        LD C,A                     ; Keep the byte while emitting the prefix.
        LD A,92                    ; Begin the byte escape with a backslash.
        CALL SRTCH                 ; SRTCH preserves C.
        LD A,'x'                   ; Select the hexadecimal byte escape.
        CALL SRTCH
        LD A,C                     ; Emit the byte as two hexadecimal digits.
        CALL SRTWBYTE
        LD A,59                    ; A semicolon terminates the byte escape.
        JP SRTCH
SRTWSNAM:
        LD A,92                    ; Emit the escape introducer.
        CALL SRTCH                 ; SRTCH preserves the selector in C.
        LD A,C                     ; Emit the escaped byte or selector letter.
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

SRTWPRCT:  DB "#<procedure>$"
SRTWPRTT:  DB "#<port>$"
SRTWCSPT:  DB "space$"
SRTWCNLT:  DB "newline$"
