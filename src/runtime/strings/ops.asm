; Managed string construction, copying and concatenation.
; Primitive entries consume the argument packet and return through IX.

; Return the newly constructed value through the packet cleanup continuation.
SRTSRET:
        LD A,6
        LD HL,(SRTSDST)
        PUSH IX
        RET
; Construct a managed string from zero through seven byte characters.
SRTSMK:
        LD A,(SRTARGC)             ; The compiler packet supports at most seven values.
        CP 8
        JP NC,SRTERROR             ; Keep the runtime safe for a malformed caller.
        LD (SRTSLENB),A           ; The argument count is the resulting byte length.
        LD B,A                     ; Validate every packet value before allocating.
        LD HL,SRTARGPK
SRTSMCHK:
        LD A,B
        OR A
        JR Z,SRTSMA
        LD E,(HL)                  ; Recover the character payload.
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)                  ; Characters use the scalar tag.
        INC HL
        INC HL                     ; Skip the packet publication flag.
        OR A
        JP NZ,SRTERROR             ; A string constructor accepts characters only.
        LD A,D
        CP 0FFH
        JP NZ,SRTERROR             ; FFxx is the byte-character representation.
        DJNZ SRTSMCHK
SRTSMA:
        CALL SRTSACL             ; Packet arguments remain roots during a GC retry.
        JP C,SRTERROR
        LD (SRTSDST),HL          ; Retain the new object while filling its bytes.
        LD A,(SRTSLENB)
        LD (HL),A                  ; The first byte is the managed length.
        INC HL
        LD (SRTSDSTB),HL          ; Keep the destination cursor beside the object base.
        LD B,A
        LD HL,SRTARGPK
        LD (SRTSSRCB),HL          ; The packet cursor is independent of the data cursor.
SRTSMW:
        LD A,B
        OR A
        JR Z,SRTSRET
        LD HL,(SRTSSRCB)
        LD A,(HL)                  ; The character payload low byte is the source byte.
        INC HL
        INC HL                     ; Skip the payload high byte.
        INC HL                     ; Skip the logical tag.
        INC HL                     ; Skip the packet publication flag.
        LD (SRTSSRCB),HL          ; Retain the next packet record.
        LD HL,(SRTSDSTB)           ; The separate cursor leaves the object base intact.
        LD (HL),A
        INC HL
        LD (SRTSDSTB),HL
        DJNZ SRTSMW
        JR SRTSRET

; Make a managed copy of either a literal or an existing managed string.
SRTSCPY:
        LD A,(SRTARGC)
        CP 1
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        CALL SRTSCHK           ; Return the source pointer in HL.
        JP C,SRTERROR
        LD A,(HL)
        LD (SRTSLENB),A
        LD (SRTSSRC),HL
        CALL SRTSACL
        JP C,SRTERROR
        LD (SRTSDST),HL
        LD A,(SRTSLENB)
        LD (HL),A
        INC HL
        LD (SRTSDSTB),HL
        LD HL,(SRTSSRC)
        INC HL
        LD (SRTSSRCB),HL
        LD A,(SRTSLENB)
        CALL SRTSCPYB
        JP SRTSRET

; Concatenate two literal or managed strings into one managed string.
SRTSJN:
        LD A,(SRTARGC)
        CP 2
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        CALL SRTSCHK
        JP C,SRTERROR
        LD (SRTSLHS),HL
        LD A,(HL)
        LD (SRTSLLN),A
        LD HL,SRTARGPK+4
        CALL SRTPVAL
        CALL SRTSCHK
        JP C,SRTERROR
        LD (SRTSRHS),HL
        LD A,(HL)
        LD (SRTSRLN),A
        LD A,(SRTSLLN)
        LD B,A
        LD A,(SRTSRLN)
        ADD A,B
        JP C,SRTERROR             ; A result above 255 cannot fit the length byte.
        LD (SRTSLENB),A
        CALL SRTSACL
        JP C,SRTERROR
        LD (SRTSDST),HL
        LD A,(SRTSLENB)
        LD (HL),A
        INC HL
        LD (SRTSDSTB),HL
        LD HL,(SRTSLHS)
        INC HL
        LD (SRTSSRCB),HL
        LD A,(SRTSLLN)
        CALL SRTSCPYB
        LD HL,(SRTSRHS)
        INC HL
        LD (SRTSSRCB),HL
        LD A,(SRTSRLN)
        CALL SRTSCPYB
        JP SRTSRET

; Validate a string argument and leave its length-prefixed address in HL.
; Literal strings are compiler-owned and tag five; managed strings are tag six.
SRTSCHK:
        LD (SRTSTMP),HL
        CP 5
        JR Z,SRTSCOK
        CP 6
        JR NZ,SRTSCBAD
        LD HL,(SRTSTMP)
        LD (SRTCLOBJ),HL
        CALL SRTSVLD
        JR C,SRTSCBAD
SRTSCOK:
        LD HL,(SRTSTMP)
        OR A
        RET
SRTSCBAD:
        SCF
        RET

; Copy A bytes from the source byte cursor to the destination byte cursor.
; The cursors are updated so append can copy its second operand immediately.
SRTSCPYB:
        LD B,A
        OR A
        RET Z
        LD HL,(SRTSSRCB)
        LD DE,(SRTSDSTB)
SRTSLP:
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ SRTSLP
        LD (SRTSSRCB),HL
        LD (SRTSDSTB),DE
        RET
