; Vector reachability and allocation-kind markers.
; SRTVMARK accepts HL as an object address; SRTMVEC traces its elements.

; Mark a vector allocation as a reachable queued leaf/container.
SRTVMARK:
        LD (SRTCLOBJ),HL           ; Keep the object base for map operations.
        CALL SRTVLD                ; Validate before setting any mark bit.
        RET C
        CALL SRTCLSEE              ; A previously queued vector needs no duplicate.
        RET NZ
        CALL SRTCLSET              ; Set the shared closure mark map.
        LD DE,(SRTMSTK)            ; Queue the object for element tracing.
        LD A,D
        CP 0D4H
        JR NC,SRTVMFUL             ; Defer children when the bounded queue is full.
        LD HL,(SRTCLOBJ)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD (SRTMSTK),DE
        RET
SRTVMFUL:
        LD A,1
        LD (SRTMOVER),A            ; The fallback scan will revisit this vector.
        LD (SRTCLER),A             ; Retain the existing overflow diagnostic bit.
        RET
; Trace every tagged element of a queued vector.
SRTMVEC:
        CALL SRTVLD                ; Recover the validated object and its count.
        RET C
        LD A,(SRTVLENB)
        LD (SRTVLEFT),A            ; Keep the loop count outside the value ABI.
        LD HL,(SRTCLOBJ)
        INC HL                     ; Skip the vector length byte.
        LD (SRTVPTR),HL            ; Keep the element cursor across each mark.
SRTVMLP:
        LD A,(SRTVLEFT)
        OR A
        RET Z
        LD HL,(SRTVPTR)            ; Recover the next four-byte element.
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        INC HL
        INC HL                     ; Skip the element spare byte.
        LD (SRTVPTR),HL            ; Retain the cursor before tracing the value.
        EX DE,HL                   ; Present the child in the runtime ABI.
        CALL SRTMVALU              ; Mark a pair, closure, string or vector child.
        LD A,(SRTVLEFT)
        DEC A
        LD (SRTVLEFT),A
        JR SRTVMLP

; Test the vector marker in the odd bit of the persistent mark map.
SRTVSST:
        LD HL,(SRTCLOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLMK
        ADD HL,DE
        LD A,C
        ADD A,A
        LD C,A
        LD A,(HL)
        AND C
        RET

; Set the vector marker in the odd bit of the persistent mark map.
SRTVSMK:
        LD HL,(SRTVOBJ)
        LD (SRTCLOBJ),HL
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLMK
        ADD HL,DE
        LD A,C
        ADD A,A
        LD C,A
        LD A,(HL)
        OR C
        LD (HL),A
        RET
