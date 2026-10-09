; Conversions between lists, vectors and strings, and the standard procedures
; that make and fill them.  These are standard procedures: STD_DISP reaches
; them, and they lie between STD_MOD and NUM_MOD.
;
; A list argument stays in the packet, which is a root, while the result is
; allocated; a list being built is a constructor input of each PAIR_NEW.

; (list->vector list): at most 255 elements, the largest vector.
STD_L2V:
        CALL CV_LEN                ; B is the length of the packet's list.
        LD A,B
        LD (VEC_REQ),A
        CALL VEC_NEW
        JP C,ERROR
        LD HL,(VEC_OBJ)
        LD A,(VEC_REQ)
        LD (HL),A
        INC HL
        LD (VEC_PTR),HL
        CALL PKT_ARG0
.FILL:
        CALL STD_NIL
        JR Z,.DONE
        LD (STD_LIST),HL
        LD (STD_LTAG),A
        CALL PAIR_CAR
        EX DE,HL                   ; Store A:CDE as the next element.
        LD HL,(VEC_PTR)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (HL),C
        INC HL
        LD (HL),A
        INC HL
        LD (VEC_PTR),HL
        LD HL,(STD_LIST)
        LD A,(STD_LTAG)
        CALL PAIR_CDR
        JR .FILL
.DONE:
        LD HL,(VEC_OBJ)
        LD A,7
        PUSH IX
        RET

; (vector->list vector): built from the last element back.
STD_V2L:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CP 7
        JP NZ,ERROR
        CALL VEC_CHK
        JP C,ERROR
        LD (STD_PTR),HL
        LD A,(HL)
        LD (STD_CNT),A
        CALL CV_NIL
.LOOP:
        LD A,(STD_CNT)
        OR A
        JR Z,CV_ACC
        DEC A
        LD (STD_CNT),A
        LD L,A                     ; Element A is at base + 1 + 4A.
        LD H,0
        ADD HL,HL
        ADD HL,HL
        INC HL
        LD DE,(STD_PTR)
        ADD HL,DE
        CALL STD_GET
        CALL CV_CONS
        JR .LOOP

; (string->list string): built from the last character back.
STD_S2L:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CALL STR_ARG
        JP C,ERROR
        LD (STD_PTR),HL
        LD A,(HL)
        LD (STD_CNT),A
        CALL CV_NIL
.LOOP:
        LD A,(STD_CNT)
        OR A
        JR Z,CV_ACC
        LD E,A                     ; Character A-1 is at base + A.
        LD D,0
        DEC A
        LD (STD_CNT),A
        LD HL,(STD_PTR)
        ADD HL,DE
        LD L,(HL)
        LD H,0FFH
        XOR A
        LD C,A
        CALL CV_CONS
        JR .LOOP

; Return the list built by CV_CONS.
CV_ACC:
        LD HL,(STD_ACC)
        LD A,(STD_ATAG)
        PUSH IX
        RET

; Start an empty list in STD_ACC.
CV_NIL:
        LD HL,0FE02H
        LD (STD_ACC),HL
        XOR A
        LD (STD_ATAG),A
        RET

; Cons A:CHL onto STD_ACC.
CV_CONS:
        LD (QT_CAR),HL
        LD (QT_CTAG),A
        LD A,C
        LD (QT_CEXT),A
        LD HL,(STD_ACC)
        LD (QT_CDR),HL
        LD A,(STD_ATAG)
        LD (QT_DTAG),A
        XOR A
        LD (QT_DEXT),A
        CALL PAIR_NEW
        LD (STD_ACC),HL
        LD (STD_ATAG),A
        RET

; (list->string list): at most 255 characters.
STD_L2S:
        CALL CV_LEN
        LD A,B
        LD (STR_LEN),A
        CALL STR_NEW
        JP C,ERROR
        LD A,(STR_LEN)
        LD (HL),A
        INC HL
        LD (STR_DSTP),HL
        CALL PKT_ARG0
.FILL:
        CALL STD_NIL
        JP Z,STR_RET
        LD (STD_LIST),HL
        LD (STD_LTAG),A
        CALL PAIR_CAR
        CALL STD_BYTE
        JP NZ,ERROR                ; Only characters make a string.
        LD A,L
        LD HL,(STR_DSTP)
        LD (HL),A
        INC HL
        LD (STR_DSTP),HL
        LD HL,(STD_LIST)
        LD A,(STD_LTAG)
        CALL PAIR_CDR
        JR .FILL

; B = the length of the list in the first packet record, at most 255.  Any
; other value, or an improper list, is an error.
CV_LEN:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        LD B,0
.STEP:
        CALL STD_NIL
        RET Z
        INC B
        JP Z,ERROR                 ; More than 255 elements.
        PUSH BC
        CALL PAIR_CDR
        POP BC
        JP C,ERROR
        JR .STEP

; (make-string k [char]): the fill is a space when none is given.
STD_MKS:
        LD A,(ARG_CNT)
        DEC A
        CP 2
        JP NC,ERROR                ; One or two arguments.
        LD A,20H
        LD (STR_OFF),A
        LD A,(ARG_CNT)
        CP 2
        JR C,.SIZE
        CALL PKT_ARG1
        CALL STD_BYTE
        JP NZ,ERROR
        LD A,L
        LD (STR_OFF),A
.SIZE:
        CALL PKT_ARG0
        CALL CV_BYTE
        LD (STR_LEN),A
        CALL STR_NEW
        JP C,ERROR
        LD A,(STR_LEN)
        LD (HL),A
        OR A
        JP Z,STR_RET
        LD B,A
        LD A,(STR_OFF)
.FILL:
        INC HL
        LD (HL),A
        DJNZ .FILL
        JP STR_RET

; A = the exact integer A:CHL when it is 0..255; otherwise an error.
CV_BYTE:
        CP 3
        JP NZ,ERROR
        LD A,C
        OR H
        JP NZ,ERROR
        LD A,L
        RET

; (string-set! string k char): literal strings are part of the program and
; cannot change.
STD_SSET:
        LD A,3
        CALL PKT_NARG
        CALL PKT_ARG0
        CP 6
        JP NZ,ERROR
        CALL STR_ARG
        JP C,ERROR
        LD (STD_PTR),HL
        CALL PKT_ARG1
        CALL CV_BYTE
        LD HL,(STD_PTR)
        CP (HL)
        JP NC,ERROR                ; The index must be below the length.
        INC A
        LD E,A
        LD D,0
        ADD HL,DE
        LD (STD_PTR),HL
        LD HL,ARG_PKT+8
        CALL PKT_VAL
        CALL STD_BYTE
        JP NZ,ERROR
        LD A,L
        LD HL,(STD_PTR)
        LD (HL),A
        JP STD_VOID

; (vector-fill! vector value)
STD_VFIL:
        LD A,2
        CALL PKT_NARG
        CALL PKT_ARG0
        CP 7
        JP NZ,ERROR
        CALL VEC_CHK
        JP C,ERROR
        LD (VEC_OBJ),HL
        LD A,(HL)
        LD (VEC_REQ),A
        CALL PKT_ARG1
        LD (VEC_VAL),HL
        LD (VEC_TAG),A
        LD A,C
        LD (VEC_EXT),A
        CALL VEC_FILL
        JP STD_VOID

; (list-copy list): reversed twice; the first copy is rooted on the side stack
; while the second is made.
STD_LCPY:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CALL STD_RINI
        CALL STD_RALL
        LD HL,(STD_ACC)
        LD A,(STD_ATAG)
        LD C,0
        CALL OPS_PUSH
        LD HL,(STD_ACC)
        LD A,(STD_ATAG)
        CALL STD_RINI
        CALL STD_RALL
        CALL OPS_POP
        JP CV_ACC

