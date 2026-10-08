; Managed string construction, copying and concatenation.
; Primitive entries consume the argument packet and return through IX.

; Return the newly constructed value through the packet cleanup continuation.
STR_RET:
        LD A,6
        LD HL,(STR_DST)
        PUSH IX
        RET
; Construct a managed string from zero through eight byte characters.
STR_MAKE:
        LD A,(ARG_CNT)             ; The compiler packet supports at most eight values.
        CP ARG_MAX+1               ; A full packet of characters.
        JP NC,ERROR                ; Keep the runtime safe for a malformed caller.
        LD (STR_LEN),A            ; The argument count is the resulting byte length.
        LD B,A                     ; Validate every packet value before allocating.
        LD HL,ARG_PKT
.CHECK:
        LD A,B
        OR A
        JR Z,.ALLOC
        LD E,(HL)                  ; Recover the character payload.
        INC HL
        LD D,(HL)
        INC HL
        INC HL                     ; Skip the extension byte.
        LD A,(HL)
        INC HL
        AND 0FH                    ; Characters use the scalar tag.
        JP NZ,ERROR                ; A string constructor accepts characters only.
        LD A,D
        CP 0FFH
        JP NZ,ERROR                ; FFxx is the byte-character representation.
        DJNZ .CHECK
.ALLOC:
        CALL STR_NEW             ; Packet arguments remain roots during a GC retry.
        JP C,ERROR
        LD (STR_DST),HL          ; Retain the new object while filling its bytes.
        LD A,(STR_LEN)
        LD (HL),A                  ; The first byte is the managed length.
        INC HL
        LD (STR_DSTP),HL          ; Keep the destination cursor beside the object base.
        LD B,A
        LD HL,ARG_PKT
        LD (STR_SRCP),HL          ; The packet cursor is independent of the data cursor.
.WRITE:
        LD A,B
        OR A
        JR Z,STR_RET
        LD HL,(STR_SRCP)
        LD A,(HL)                  ; The character payload low byte is the source byte.
        INC HL
        INC HL                     ; Skip the payload high byte.
        INC HL                     ; Skip the logical tag.
        INC HL                     ; Skip the packet publication flag.
        LD (STR_SRCP),HL          ; Retain the next packet record.
        LD HL,(STR_DSTP)           ; The separate cursor leaves the object base intact.
        LD (HL),A
        INC HL
        LD (STR_DSTP),HL
        DJNZ .WRITE
        JR STR_RET

; Make a managed copy of either a literal or an existing managed string.
STR_COPY:
        LD A,(ARG_CNT)
        CP 1
        JP NZ,ERROR
        LD HL,ARG_PKT
        CALL PKT_VAL
        CALL STR_ARG           ; Return the source pointer in HL.
        JP C,ERROR
        LD A,(HL)
        LD (STR_LEN),A
        LD (STR_SRC),HL
        CALL STR_NEW
        JP C,ERROR
        LD (STR_DST),HL
        LD A,(STR_LEN)
        LD (HL),A
        INC HL
        LD (STR_DSTP),HL
        LD HL,(STR_SRC)
        INC HL
        LD (STR_SRCP),HL
        LD A,(STR_LEN)
        CALL STR_MOVE
        JP STR_RET

; Concatenate two literal or managed strings into one managed string.
STR_JOIN:
        LD A,(ARG_CNT)
        CP 2
        JP NZ,ERROR
        LD HL,ARG_PKT
        CALL PKT_VAL
        CALL STR_ARG
        JP C,ERROR
        LD (STR_LHS),HL
        LD A,(HL)
        LD (STR_LLEN),A
        LD HL,ARG_PKT+4
        CALL PKT_VAL
        CALL STR_ARG
        JP C,ERROR
        LD (STR_RHS),HL
        LD A,(HL)
        LD (STR_RLEN),A
        LD A,(STR_LLEN)
        LD B,A
        LD A,(STR_RLEN)
        ADD A,B
        JP C,ERROR                ; A result above 255 cannot fit the length byte.
        LD (STR_LEN),A
        CALL STR_NEW
        JP C,ERROR
        LD (STR_DST),HL
        LD A,(STR_LEN)
        LD (HL),A
        INC HL
        LD (STR_DSTP),HL
        LD HL,(STR_LHS)
        INC HL
        LD (STR_SRCP),HL
        LD A,(STR_LLEN)
        CALL STR_MOVE
        LD HL,(STR_RHS)
        INC HL
        LD (STR_SRCP),HL
        LD A,(STR_RLEN)
        CALL STR_MOVE
        JP STR_RET

; Validate a string argument and leave its length-prefixed address in HL.
; Literal strings are compiler-owned and tag five; managed strings are tag six.
STR_ARG:
        LD (STR_TMP),HL
        CP 5
        JR Z,.OK
        CP 6
        JR NZ,.BAD
        LD HL,(STR_TMP)
        LD (CL_OBJ),HL
        CALL STR_CHK
        JR C,.BAD
.OK:
        LD HL,(STR_TMP)
        OR A
        RET
.BAD:
        SCF
        RET

; Copy A bytes from the source byte cursor to the destination byte cursor.
; The cursors are updated so append can copy its second operand immediately.
STR_MOVE:
        LD B,A
        OR A
        RET Z
        LD HL,(STR_SRCP)
        LD DE,(STR_DSTP)
.LOOP:
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ .LOOP
        LD (STR_SRCP),HL
        LD (STR_DSTP),DE
        RET
