; Managed string allocation, leaf marking and address validation.
; SRTSACL may collect; source values must remain rooted by its caller.
; SRTSVLD checks an address after the caller selects the managed-string tag.

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
        LD HL,0100H                 ; 255 data bytes plus the length byte fit one page.
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
