; Read one quoted string datum into the managed string pool.
;
; The source spelling follows the compiler lexer: printable ASCII is copied
; directly, controls use n/r/t escapes, quotes and backslashes may be escaped,
; and xHH; spells any byte.  The decoded string is limited to 255 bytes so its
; length-prefixed managed representation remains one-byte addressable.

; Begin after the opening quote has already been consumed by SRTDRVAL.
SRTDRSTR:
        XOR A                       ; Start with an empty decoded string.
        LD (SRTDSLN),A              ; The buffer count is the current length.
SRTDSSL:
        CALL SRTDRTK                ; Take the next source byte.
        JP C,SRTERROR               ; EOF before the closing quote is malformed.
        CP 34                       ; An unescaped quote closes the string.
        JP Z,SRTDSFIN               ; Allocate only after the full datum is read.
        CP 92                       ; A backslash starts one supported escape.
        JR Z,SRTDSEP                ; Decode the selector before appending.
        CP 32                       ; Raw control bytes are not string contents.
        JP C,SRTERROR
        CP 127                      ; DEL must use the explicit byte escape.
        JP Z,SRTERROR
        CALL SRTDSAPP                ; Append a printable source byte.
        JP SRTDSSL

; Decode a single-letter escape or dispatch the two-digit byte escape.
SRTDSEP:
        CALL SRTDRTK                ; Read the selector after the backslash.
        JP C,SRTERROR               ; A trailing backslash is malformed.
        CP 120                      ; Lowercase x introduces a byte escape.
        JR Z,SRTDSHEX
        CP 34                       ; Escaped quote represents a quote byte.
        JR NZ,SRTDSBS
        CALL SRTDSAPP
        JP SRTDSSL
SRTDSBS:
        CP 92                       ; Escaped backslash represents a slash byte.
        JR NZ,SRTDSNLT
        CALL SRTDSAPP
        JP SRTDSSL
SRTDSNLT:
        CP 110                      ; Lowercase n represents line feed.
        JP Z,SRTDSNL
        CP 114                      ; Lowercase r represents carriage return.
        JP Z,SRTDSCR
        CP 116                      ; Lowercase t represents horizontal tab.
        JP Z,SRTDSTB
        JP SRTERROR                 ; No other escape spelling is accepted.

; Append the standard control byte selected by the escape dispatcher.
SRTDSNL:
        LD A,10                      ; Newline is ASCII line feed.
        CALL SRTDSAPP
        JP SRTDSSL
SRTDSCR:
        LD A,13                      ; Carriage return is ASCII thirteen.
        CALL SRTDSAPP
        JP SRTDSSL
SRTDSTB:
        LD A,9                       ; Tab is ASCII nine.
        CALL SRTDSAPP
        JP SRTDSSL

; Decode exactly two hexadecimal digits followed by a semicolon.
SRTDSHEX:
        CALL SRTDRTK                ; Read the high hexadecimal digit.
        JP C,SRTERROR               ; Both digits are required.
        CALL SRTDSHX                ; Reduce ASCII hex to a four-bit value.
        JP C,SRTERROR               ; Reject every non-hex source byte.
        ADD A,A                      ; Shift the high nibble into bits 7..4.
        ADD A,A
        ADD A,A
        ADD A,A
        LD (SRTDSTMP),A              ; Keep the high nibble across input reads.
        CALL SRTDRTK                ; Read the low hexadecimal digit.
        JP C,SRTERROR
        CALL SRTDSHX                ; Reduce the low digit to four bits.
        JP C,SRTERROR
        LD B,A                       ; Hold the decoded low nibble.
        LD A,(SRTDSTMP)              ; Recover the shifted high nibble.
        OR B                         ; Combine the two disjoint nibbles.
        LD (SRTDSTMP),A              ; Retain the decoded byte while checking ';'.
        CALL SRTDRTK                ; Consume the required escape terminator.
        JP C,SRTERROR
        CP 59                        ; A byte escape ends with semicolon.
        JP NZ,SRTERROR
        LD A,(SRTDSTMP)               ; Recover the decoded byte for appending.
        CALL SRTDSAPP
        JP SRTDSSL

; Convert one ASCII hexadecimal byte to a nibble, with carry on failure.
SRTDSHX:
        CP 48                        ; Bytes below ASCII zero are invalid.
        JR C,SRTDSBAD
        CP 58                        ; ASCII colon follows decimal nine.
        JR C,SRTDSDIG
        OR 32                        ; Fold uppercase A..F to lowercase.
        CP 97                        ; Lowercase a begins the letter range.
        JR C,SRTDSBAD
        CP 103                       ; Lowercase g follows the accepted range.
        JR NC,SRTDSBAD
        SUB 87                       ; Map a..f to ten through fifteen.
        OR A                         ; Clear carry after a valid conversion.
        RET
SRTDSDIG:
        SUB 48                       ; Map 0..9 to their numeric nibble.
        OR A                         ; Clear carry after a valid conversion.
        RET
SRTDSBAD:
        SCF                          ; Report a malformed hexadecimal digit.
        RET

; Append A to the raw decoded buffer while enforcing the 255-byte limit.
SRTDSAPP:
        LD (SRTDSTMP),A              ; Preserve the byte during address arithmetic.
        LD A,(SRTDSLN)               ; Read the number of bytes already stored.
        CP 255                        ; A 256th decoded byte is outside the contract.
        JP NC,SRTERROR
        LD L,A                        ; Zero-extend the byte count into an offset.
        LD H,0
        LD DE,SRTDSB                 ; Locate the fixed reader string buffer.
        ADD HL,DE
        LD A,(SRTDSTMP)               ; Restore the decoded byte.
        LD (HL),A                     ; Store it at the next free buffer position.
        LD A,(SRTDSLN)
        INC A
        LD (SRTDSLN),A               ; Publish the new decoded length.
        OR A                          ; Clear carry for the enclosing string loop.
        RET

; Allocate a managed string and copy the decoded buffer into its payload.
SRTDSFIN:
        LD A,(SRTDSLN)               ; STR_NEW reads the shared length scratch.
        LD (STR_LEN),A
        CALL STR_NEW                 ; Allocate and mark one managed string.
        JP C,SRTERROR               ; Allocation failure is a runtime error.
        LD A,(STR_LEN)               ; Retain the count across the destination setup.
        LD (HL),A                    ; The managed representation starts with length.
        INC HL                       ; DE becomes the first managed payload byte.
        EX DE,HL
        LD HL,SRTDSB                 ; HL walks the decoded source buffer.
        LD B,A                       ; DJNZ copies exactly the decoded byte count.
        OR A
        JR Z,SRTDSRET                ; Empty strings have no payload bytes to copy.
SRTDSCP:
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ SRTDSCP
SRTDSRET:
        LD A,6                        ; Managed strings use logical tag six.
        LD HL,(STR_DST)              ; Return the allocated object base address.
        OR A                          ; Clear carry for the ordinary datum path.
        RET

SRTDSB: DS 255                       ; Raw decoded bytes before managed allocation.
