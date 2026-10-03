; String and character primitives.
;
; Literal strings use the generated value's payload as an address of a length
; byte followed by that many bytes.  Managed strings use the same layout with
; tag six and are validated by the collector-backed helpers.

; Dispatch string and character primitives.
STR_PRIM:
        LD A,(SRTPID)              ; Read the zero-based primitive kind.
        CP 32                      ; Kind thirty-two is string-length.
        JP Z,.LENGTH               ; Return the literal's byte count.
        CP 33                      ; Kind thirty-three is string-ref.
        JP Z,.REF                  ; Index a literal and return a character.
        CP 34                      ; Kind thirty-four is char->integer.
        JP Z,.CHAR_INT             ; Convert one byte character to an integer.
        CP 35                      ; Kind thirty-five is integer->char.
        JP Z,.INT_CHAR
        CP 36                      ; Kind thirty-six constructs a managed string.
        JP Z,STR_MAKE
        CP 37                      ; Kind thirty-seven copies a string.
        JP Z,STR_COPY
        JP STR_JOIN            ; Kind thirty-eight appends two strings.

; Return the length byte of one literal string as an exact integer.
.LENGTH:
        LD A,(SRTARGC)             ; The procedure accepts exactly one value.
        CP 1
        JP NZ,SRTERROR             ; Reject missing and extra arguments.
        LD HL,SRTARGPK             ; Read the only packet record.
        CALL PKT_VAL               ; Recover its payload and logical tag.
        CP 5
        JR Z,.LEN_READ             ; Literal strings need no managed validation.
        CP 6
        JP NZ,SRTERROR             ; Every other value is outside the string type.
        CALL STR_CHK             ; Reject stale or interior managed pointers.
        JP C,SRTERROR
.LEN_READ:
        LD A,(HL)                  ; The first byte records the string length.
        LD L,A                     ; Widen the byte count into an exact payload.
        LD H,0
        LD A,3                     ; Exact integers use logical tag three.
        PUSH IX                    ; Return through the packet cleanup path.
        RET

; Return the byte character at an exact, in-range string index.
.REF:
        LD A,(SRTARGC)             ; string-ref takes a string and an index.
        CP 2
        JP NZ,SRTERROR             ; Reject every other arity.
        LD HL,SRTARGPK             ; Read the string argument first.
        CALL PKT_VAL
        CP 5
        JR Z,.REF_IDX              ; Literal strings use the image representation.
        CP 6
        JP NZ,SRTERROR             ; The first argument must be a string.
        CALL STR_CHK             ; Check the managed allocation before indexing.
        JP C,SRTERROR
.REF_IDX:
        LD (SRTNVAL),HL            ; Preserve its address while reading index.
        LD HL,SRTARGPK+4           ; The second packet record is the index.
        CALL PKT_VAL
        CP 3
        JP NZ,SRTERROR             ; The index must be an exact integer.
        LD A,H                     ; Only the nonnegative byte range is addressable.
        OR A
        JP NZ,SRTERROR             ; Negative and wider integers are out of range.
        LD A,L                     ; Retain the checked byte index in the work byte.
        LD (SRTNLEFT),A
        LD HL,(SRTNVAL)             ; Recover the literal's length-byte address.
        LD B,(HL)                  ; Compare the index with its bounded length.
        LD A,(SRTNLEFT)
        CP B
        JP NC,SRTERROR             ; An index at or beyond the end is an error.
        INC HL                     ; Skip the length byte to the first character.
        LD E,A                     ; Add the byte index to the character base.
        LD D,0
        ADD HL,DE
        LD L,(HL)                   ; Return the selected byte as FFxx.
        LD H,0FFH
        XOR A                       ; Characters use scalar logical tag zero.
        PUSH IX
        RET

; Convert one byte character (FFxx, scalar tag zero) to an exact integer.
.CHAR_INT:
        LD A,(SRTARGC)              ; The conversion is unary.
        CP 1
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL PKT_VAL
        OR A
        JP NZ,SRTERROR              ; Characters share tag zero with other scalars.
        LD A,H
        CP 0FFH
        JP NZ,SRTERROR              ; Only the reserved FFxx range is a character.
        LD A,L                      ; Keep the byte before replacing the high byte.
        LD H,0
        LD L,A
        LD A,3                      ; Return an exact integer value.
        PUSH IX
        RET

; Convert an exact integer in the byte range to the FFxx character form.
.INT_CHAR:
        LD A,(SRTARGC)              ; The conversion is unary.
        CP 1
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL PKT_VAL
        CP 3
        JP NZ,SRTERROR              ; Binary16 values are not exact characters.
        LD A,H
        OR A
        JP NZ,SRTERROR              ; Accept only integers from zero through 255.
        LD H,0FFH
        XOR A                       ; Character values use scalar logical tag zero.
        PUSH IX
        RET
