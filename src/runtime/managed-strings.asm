; Managed strings allocated from the existing rounded closure classes.
;
; A managed string is a tag-six pointer to a class block whose first byte is
; its length and whose following bytes are the string data.  The closure start
; map supplies allocation ownership; the bit immediately after the start bit
; identifies a string block.  Strings contain no managed references, so the
; collector marks them without enqueueing them for closure tracing.

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

; Allocate one rounded class block and publish its start and string marker.
; Carry set means the managed pool could not satisfy the request after GC.
SRTSACL:
        CALL SRTSSZ
        CALL SRTCLALC
        JR NC,SRTSOK
        CALL SRTGC
        CALL SRTSSZ             ; Collection may reuse the sizing scratch.
        CALL SRTCLALC
        RET C
SRTSOK:
        LD (SRTSDST),HL
        LD (SRTOBJ),HL
        CALL SRTCLNEW               ; Record the exact block start for validation.
        CALL SRTSSET              ; Set the adjacent string marker bit.
        LD HL,(SRTSDST)
        LD A,6
        OR A
        RET

; Calculate the rounded closure class for a length-prefixed string.
SRTSSZ:
        LD A,(SRTSLENB)
        INC A
        JR NZ,SRTSSZ8             ; Lengths below 255 fit in one byte here.
        LD HL,0100H                 ; 255 data bytes plus the length byte.
        JR SRTSSZC
SRTSSZ8:
        LD L,A
        LD H,0
        LD DE,3
        ADD HL,DE
        LD A,L
        AND 0FCH
        LD L,A
SRTSSZC:
        LD (SRTCLSZ),HL
        SRL H
        RR L
        SRL H
        RR L
        DEC L
        LD A,L
        LD (SRTCLIDX),A
        RET

; Mark a managed string as a live leaf during collection.
SRTSMARK:
        LD (SRTCLOBJ),HL
        CALL SRTSVLD
        RET C
        CALL SRTCLSEE
        RET NZ
        CALL SRTCLSET
        RET

; Test the string marker adjacent to an exact closure allocation start.
; Z means the object is not a managed string.
SRTSSTA:
        LD HL,(SRTCLOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLBM
        ADD HL,DE
        LD A,(HL)
        AND C
        RET Z
        LD A,C
        ADD A,A
        LD C,A
        LD A,(HL)
        AND C
        RET

; Set the string marker for the object in SRTOBJ.
SRTSSET:
        LD HL,(SRTOBJ)
        LD (SRTCLOBJ),HL
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLBM
        ADD HL,DE
        LD A,C
        ADD A,A
        LD C,A
        LD A,(HL)
        OR C
        LD (HL),A
        RET

; Clear the string marker before a dead block returns to a closure free list.
SRTSCL:
        LD HL,(SRTCLOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLBM
        ADD HL,DE
        LD A,C
        ADD A,A
        LD C,A
        LD A,C
        CPL
        LD B,A
        LD A,(HL)
        AND B
        LD (HL),A
        RET

; Validate a managed string's start, class extent and length byte.
SRTSVLD:
        LD (SRTCLOBJ),HL
        LD DE,SRTHEAP
        OR A
        SBC HL,DE
        JP C,SRTSVB
        LD HL,(SRTCLOBJ)
        LD A,L
        AND 3
        JP NZ,SRTSVB
        LD DE,(SRTHEAPP)
        OR A
        SBC HL,DE
        JP NC,SRTSVB
        CALL SRTSSTA
        JP Z,SRTSVB
        LD HL,(SRTCLOBJ)
        LD (SRTCLBAS),HL
        CALL SRTCLFND
        LD A,(SRTCLPGI)
        CP 80H
        JP NC,SRTSVB
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
        ADD HL,DE
        LD A,(HL)
        CP 1
        JP C,SRTSVB
        CP 41H
        JP NC,SRTSVB             ; Strings use only the one-page classes.
        DEC A
        LD (SRTCLIDX),A
        CALL SRTCLGET
        LD HL,(SRTCLOBJ)
        LD DE,(SRTCLPGA)
        OR A
        SBC HL,DE
        JP C,SRTSVB
        LD A,H
        OR A
        JP NZ,SRTSVB
        LD A,L
        LD (SRTSOFF),A
        LD A,(SRTCLIDX)
        INC A
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD (SRTCLSZ),HL
        LD A,(SRTSOFF)
        LD E,A
        LD D,0
        ADD HL,DE
        LD A,H
        OR A
        JP Z,SRTSVGOK
        CP 1
        JP NZ,SRTSVB
        LD A,L
        OR A
        JP NZ,SRTSVB
SRTSVGOK:
        LD HL,(SRTCLOBJ)
        LD A,(HL)
        LD L,A
        LD H,0
        INC HL
        LD DE,(SRTCLSZ)
        OR A
        SBC HL,DE
        JP C,SRTSVGO
        JP Z,SRTSVGO
SRTSVB:
        SCF
        RET
SRTSVGO:
        LD HL,(SRTCLOBJ)
        OR A
        RET

; Scratch is kept outside the collector's existing fields.
SRTSLENB:  DB 0
SRTSLLN: DB 0
SRTSRLN: DB 0
SRTSOFF:  DB 0
SRTSSRC:  DW 0
SRTSSRCB: DW 0
SRTSLHS:  DW 0
SRTSRHS:  DW 0
SRTSDST:  DW 0
SRTSDSTB: DW 0
SRTSTMP:  DW 0
