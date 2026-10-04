; Scheme value and pair printing through the output adapter.
; Entry points: WR_VALUE, WR_PAIR, OUT_CHAR and IN_BYTE.
; Included in runtime order by ../data.asm.

WR_VALUE:
        CP 3
        JP Z,WR_INT
        CP 1
        JP Z,WR_PAIR
        CP 4
        JP Z,WR_LIT
        CP 5
        JP Z,WR_STR
        CP 6
        JP NZ,.OTHER
        CALL STR_CHK
        JP C,ERROR
        JP WR_STR
.OTHER:
        OR A                       ; Tag zero holds the scalar family below.
        JR Z,.SCALAR
        CP 2                       ; Closures print as opaque procedures.
        JR Z,.PROC
        CP 7                       ; Vectors print with the #( reader syntax.
        JP Z,WR_VEC
        CP 8                       ; Tag eight holds ports and escape tokens.
        JP NZ,ERROR                ; No other tag is a printable Scheme value.
        LD A,H                     ; Ports occupy the F000H token namespace.
        CP 0F0H
        JR NZ,.PROC                ; An escape token is a callable procedure.
        LD DE,WR_PORT              ; Every port prints as one opaque spelling.
        JR WR_SEND
.SCALAR:
        LD A,H                     ; FFxx payloads are byte characters.
        CP 0FFH
        JP Z,WR_CHAR
        CP 0FEH                    ; FExx holds reserved singletons and primitives.
        JR NZ,WR_FLOAT
        LD A,L                     ; FE00..FE04 have fixed spellings.
        LD DE,WR_FALSE             ; FE00 is #f.
        OR A
        JR Z,WR_SEND
        LD DE,WR_TRUE              ; FE01 is #t.
        DEC A
        JR Z,WR_SEND
        LD DE,WR_EMPTY             ; FE02 is the empty list.
        DEC A
        JR Z,WR_SEND
        LD DE,WR_EOF               ; FE03 is the EOF object.
        DEC A
        JR Z,WR_SEND
        LD DE,WR_VOID              ; FE04 is the unspecified value.
        DEC A
        JR Z,WR_SEND
.PROC:
        LD DE,WR_PROC              ; Primitives, closures and escapes share this.
WR_SEND:
        JP OUT_TEXT                ; Send the spelling through the output adapter.
WR_FLOAT:
        PUSH HL                    ; Keep the payload across classification.
        XOR A                      ; Classify it as a binary16 scalar.
        CALL NUM_CHK
        POP HL
        JP NC,FLT_EMIT             ; Valid binary16 values use the float printer.
        LD DE,WR_FALSE             ; Keep the established fallback spelling.
        JR WR_SEND

; Print a character raw for display, or in write mode as #\c, #\space,
; #\newline or #\xHH so the datum reader accepts the spelling again.
WR_CHAR:
        LD A,(WR_MODE)             ; Zero selects display's raw byte output.
        OR A
        JR Z,.RAW
        LD A,35                    ; Prefix the readable character spelling with '#'.
        CALL OUT_CHAR              ; OUT_CHAR preserves the character payload in HL.
        LD A,92                    ; The second prefix byte is a backslash.
        CALL OUT_CHAR
        LD A,L                     ; Classify the character byte.
        LD DE,WR_LINE              ; Line feed has the reader name newline.
        CP 10
        JP Z,OUT_TEXT
        LD DE,WR_SPACE             ; Space has the reader name space.
        CP 32
        JP Z,OUT_TEXT
        JR C,.HEX                  ; Other controls use the hexadecimal spelling.
        CP 127                     ; Printable ASCII is spelled as itself.
        JP C,OUT_CHAR
.HEX:
        LD A,'x'                   ; Hexadecimal spelling is valid for every byte.
        CALL OUT_CHAR              ; Send the hexadecimal marker.
        LD A,L                     ; Load the byte payload for hexadecimal output.
        JP WR_BYTE                 ; Emit its two lower-case hexadecimal digits.
.RAW:
        LD A,L                     ; Emit the byte payload itself.
        JP OUT_CHAR

; Emit the two hexadecimal digits in one byte held in A.
WR_BYTE:
        LD (CON_BYTE),A            ; Preserve the byte while selecting its nibbles.
        AND 0F0H                   ; Keep the high nibble of the byte.
        RRCA                       ; Shift the high nibble into the low position.
        RRCA                       ; Shift the high nibble into the low position.
        RRCA                       ; Shift the high nibble into the low position.
        RRCA                       ; Shift the high nibble into the low position.
        CALL .DIGIT                ; Emit the selected high-nibble digit.
        LD A,(CON_BYTE)            ; Restore the original byte for its low nibble.
        AND 0FH                    ; Keep the low nibble.
        JP .DIGIT                  ; Emit the selected low-nibble digit.

; Look up one hexadecimal digit and send it to the CP/M character writer.
.DIGIT:
        LD E,A                     ; Use the nibble as a table offset.
        LD D,0                     ; Form a word-sized table index.
        LD HL,WR_HEX               ; Point at the lower-case digit table.
        ADD HL,DE                  ; Select the requested digit.
        LD A,(HL)                  ; Load the selected digit character.
        JP OUT_CHAR                ; Send it while preserving the formatter state.

; Print a pair as a list.  Only CAR values recurse; successive CDR pairs are
; followed in a loop so a long proper list uses constant native stack.
WR_PAIR:
        CALL WR_GUARD              ; Refuse nesting that would reach the guard band.
        LD A,'('                   ; Open the list; OUT_CHAR preserves the pair in HL.
        CALL OUT_CHAR
.LOOP:
        PUSH HL                    ; Keep this pair while printing its CAR.
        LD A,1                     ; HL names a pair record.
        CALL PAIR_CAR              ; Decode the packed CAR field into A:HL.
        JP C,ERROR                 ; A corrupt pair cannot be printed safely.
        CALL WR_VALUE              ; Nested values recurse only through the CAR.
        POP HL                     ; Recover this pair for its CDR.
        LD A,1                     ; HL still names a pair record.
        CALL PAIR_CDR              ; Decode the packed CDR field into A:HL.
        JP C,ERROR                 ; A corrupt pair cannot be printed safely.
        CP 1                       ; A pair CDR continues the same list.
        JR NZ,.TAIL
        LD A,' '                   ; Separate the next element.
        CALL OUT_CHAR              ; OUT_CHAR preserves the CDR pair in HL.
        JR .LOOP                   ; Iterate rather than recurse along the list.
.TAIL:
        OR A                       ; Only a scalar can be the empty list.
        JR NZ,.DOT
        PUSH HL                    ; Compare the payload without changing it.
        LD DE,0FE02H               ; FE02 is the empty list.
        SBC HL,DE                  ; OR A above cleared carry for the compare.
        POP HL                     ; Restore the CDR payload.
        JR Z,.CLOSE                ; A proper list closes immediately.
.DOT:
        LD B,A                     ; Keep the CDR tag while printing the dot.
        LD A,' '                   ; A non-list CDR uses dotted-pair syntax.
        CALL OUT_CHAR              ; OUT_CHAR preserves B and the payload in HL.
        LD A,'.'
        CALL OUT_CHAR
        LD A,' '
        CALL OUT_CHAR
        LD A,B                     ; Restore the CDR tag for the final value.
        CALL WR_VALUE              ; Print the dotted tail.
.CLOSE:
        LD A,')'                   ; Close the list.
        JP OUT_CHAR

; Raise a runtime error before nested printing can descend into the guarded
; bands below RT_GUARD.  HL is preserved; A, DE and the flags are clobbered.
WR_GUARD:
        PUSH HL                    ; Keep the value payload while measuring SP.
        LD HL,0                    ; Copy the native stack pointer into HL.
        ADD HL,SP
        LD DE,RT_GUARD             ; Compare it with the guarded band's top.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,DE                  ; Carry means SP is already below the guard.
        POP HL                     ; Restore the payload; POP leaves flags unchanged.
        RET NC                     ; Enough native stack remains for another level.
        JP ERROR                   ; Report the nesting as a checked runtime error.

; Print a tag-seven vector as #( elements ).  Elements recurse through
; WR_VALUE; the cursor and remaining count are kept on the native stack.
WR_VEC:
        CALL WR_GUARD              ; Refuse nesting that would reach the guard band.
        CALL VEC_CHK               ; Validate the block and return its base in HL.
        JP C,ERROR                 ; A corrupt vector cannot be printed safely.
        LD A,35                    ; Open the vector with its reader prefix.
        CALL OUT_CHAR              ; OUT_CHAR preserves the vector base in HL.
        LD A,'('                   ; Complete the opening delimiter.
        CALL OUT_CHAR
        LD B,(HL)                  ; B counts the elements still to print.
        INC HL                     ; HL addresses the first four-byte element.
        LD A,B                     ; An empty vector closes immediately.
        OR A
        JR Z,.CLOSE
.LOOP:
        PUSH BC                    ; Keep the remaining count across recursion.
        PUSH HL                    ; Keep the element cursor across recursion.
        LD E,(HL)                  ; Read the element payload low byte.
        INC HL
        LD D,(HL)                  ; Read the element payload high byte.
        INC HL
        LD C,(HL)                  ; Byte 2.
        INC HL
        LD A,(HL)                  ; Read the element's logical tag.
        EX DE,HL                   ; A:HL is now the element value.
        CALL WR_VALUE              ; Print the element in the current mode.
        POP HL                     ; Recover the element cursor.
        LD DE,4                    ; Advance to the next four-byte element.
        ADD HL,DE
        POP BC                     ; Recover the remaining count.
        DEC B                      ; Count the element just printed.
        JR Z,.CLOSE                ; The final element needs no separator.
        LD A,' '                   ; Separate consecutive elements.
        CALL OUT_CHAR              ; OUT_CHAR preserves the cursor and count.
        JR .LOOP
.CLOSE:
        LD A,')'                   ; Close the vector spelling.
        JP OUT_CHAR

; Print a string: display sends its bytes unchanged, while write quotes it
; and escapes quote, backslash and control bytes with the reader's spellings.
WR_STR:
        LD A,(WR_MODE)             ; Zero selects display's raw contents.
        OR A
        JR Z,WR_LIT
        LD A,34                    ; Open the readable string spelling.
        CALL OUT_CHAR              ; OUT_CHAR preserves the string pointer.
        LD B,(HL)                  ; B counts the remaining string bytes.
        INC HL                     ; HL addresses the first string byte.
        LD A,B                     ; An empty string closes immediately.
        OR A
        JR Z,.CLOSE
.LOOP:
        LD A,(HL)                  ; Fetch the next string byte.
        INC HL                     ; Advance before the formatter clobbers HL.
        PUSH HL                    ; Keep the string cursor across escapes.
        PUSH BC                    ; Keep the remaining count across escapes.
        CALL .BYTE                 ; Emit the byte or its escape spelling.
        POP BC                     ; Recover the remaining count.
        POP HL                     ; Recover the string cursor.
        DJNZ .LOOP                 ; Continue until every byte is written.
.CLOSE:
        LD A,34                    ; Close the readable string spelling.
        JP OUT_CHAR

; Emit one string byte from A using the reader's escape spellings.
.BYTE:
        LD C,A                     ; Quote and backslash follow a backslash.
        CP 34
        JR Z,.ESCAPE
        CP 92
        JR Z,.ESCAPE
        LD C,'n'                   ; Line feed is spelled \n.
        CP 10
        JR Z,.ESCAPE
        LD C,'r'                   ; Carriage return is spelled \r.
        CP 13
        JR Z,.ESCAPE
        LD C,'t'                   ; Tab is spelled \t.
        CP 9
        JR Z,.ESCAPE
        CP 32                      ; Other controls use the \xHH; escape.
        JR C,.HEX
        CP 127                     ; Printable ASCII is emitted unchanged.
        JP C,OUT_CHAR
.HEX:
        LD C,A                     ; Keep the byte while emitting the prefix.
        LD A,92                    ; Begin the byte escape with a backslash.
        CALL OUT_CHAR              ; OUT_CHAR preserves C.
        LD A,'x'                   ; Select the hexadecimal byte escape.
        CALL OUT_CHAR
        LD A,C                     ; Emit the byte as two hexadecimal digits.
        CALL WR_BYTE
        LD A,59                    ; A semicolon terminates the byte escape.
        JP OUT_CHAR
.ESCAPE:
        LD A,92                    ; Emit the escape introducer.
        CALL OUT_CHAR              ; OUT_CHAR preserves the selector in C.
        LD A,C                     ; Emit the escaped byte or selector letter.
        JP OUT_CHAR
WR_LIT:
        LD B,(HL)
        INC HL
.LOOP:
        LD A,B
        OR A
        RET Z
        LD A,(HL)
        INC HL
        PUSH HL                     ; Preserve the literal cursor across BDOS.
        PUSH BC                     ; Preserve the remaining count across BDOS.
        CALL OUT_CHAR
        POP BC
        POP HL
        DJNZ .LOOP
        RET

WR_INT:
        XOR A
        LD (WR_SEEN),A
        BIT 7,H
        JR Z,.PLACES
        LD A,'-'
        CALL OUT_CHAR
        XOR A
        SUB L
        LD L,A
        LD A,0                    ; Preserve the low-byte borrow for negating H.
        SBC A,H
        LD H,A
.PLACES:
        LD DE,10000
        CALL .PLACE
        LD DE,1000
        CALL .PLACE
        LD DE,100
        CALL .PLACE
        LD DE,10
        CALL .PLACE
        LD A,1
        LD (WR_SEEN),A
        LD DE,1
        JP .PLACE
.PLACE:
        LD B,0
.SUB_LOOP:
        OR A
        SBC HL,DE
        JR C,.COUNTED
        INC B
        JR .SUB_LOOP
.COUNTED:
        ADD HL,DE
        LD A,B
        OR A
        JR NZ,.DIGIT
        LD A,(WR_SEEN)
        OR A
        RET Z
.DIGIT:
        LD A,1
        LD (WR_SEEN),A
        LD A,B
        ADD A,'0'
        JP OUT_CHAR

; Preserve the caller's numeric remainder and procedure continuation across BDOS.
OUT_CHAR:
        PUSH AF                    ; Retain the value tag and flags.
        PUSH BC                    ; Retain loop counters.
        PUSH DE                    ; Retain the decimal divisor or data pointer.
        PUSH HL                    ; Retain the decimal remainder or literal cursor.
        PUSH IX                    ; Retain the primitive return continuation.
        PUSH IY                    ; Retain any active indexed runtime state.
        LD (OUT_BYTE),A            ; Keep the byte while selecting the output adapter.
        LD A,(OUT_SEL)
        OR A
        JR Z,.CONSOLE               ; The default path sends bytes to the provider hook.
        LD A,(OUT_BYTE)
        CALL FILE_PUT             ; A file output port uses the CP/M file adapter.
        JR .CHECK
.CONSOLE:
        LD A,(OUT_BYTE)
        CALL CON_SEND                ; Send the byte through the selected provider.
.CHECK:
        JP C,ERROR                   ; Provider failure follows the checked path.
        POP IY                     ; Restore the caller's indexed state.
        POP IX                     ; Restore the primitive continuation.
        POP HL                     ; Restore the numeric remainder.
        POP DE                     ; Restore the divisor or data pointer.
        POP BC                     ; Restore loop counters.
        POP AF                     ; Restore the original flags and value tag.
        RET                        ; Continue formatting or return to the primitive.

; Read one console byte while preserving the runtime continuation and cursors.
IN_BYTE:
        PUSH BC                    ; Preserve the caller's packet count and counters.
        PUSH DE                    ; Preserve the caller's data pointer or divisor.
        PUSH HL                    ; Preserve the caller's value payload or cursor.
        PUSH IX                    ; Preserve the generated continuation across BDOS.
        PUSH IY                    ; Preserve indexed runtime state used by collection.
        CALL CON_READ               ; Obtain one byte through the selected provider.
        JP C,ERROR                 ; Empty or failed provider input is not EOF.
        LD (CON_BYTE),A            ; Stage the byte before restoring caller registers.
        POP IY                     ; Restore indexed runtime state.
        POP IX                     ; Restore the primitive return continuation.
        POP HL                     ; Restore the caller's payload or cursor.
        POP DE                     ; Restore the caller's pointer or divisor.
        POP BC                     ; Restore the caller's packet count and counters.
        LD A,(CON_BYTE)            ; Return the byte obtained from the console.
        RET                        ; The primitive maps Control-Z to the EOF value.

WR_PROC:  DB "#<procedure>$"
WR_PORT:  DB "#<port>$"
WR_SPACE:  DB "space$"
WR_LINE:  DB "newline$"
