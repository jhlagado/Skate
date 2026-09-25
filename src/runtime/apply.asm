; Dynamic apply for the bounded procedure-call packet.
;
; The compiler call path accepts eight four-byte value records.  Apply keeps
; the procedure and final list aside, moves any leading arguments down, then
; appends the list elements in order.  A proper list longer than the packet is
; rejected before the target is entered.  The ordinary call and tail-call
; dispatchers then perform the same descriptor, closure and rest checks as a
; directly written call.

; Spread the final proper list argument into SRTARGPK and enter its procedure.
SRTAPPLY:
        LD A,(SRTARGC)             ; Apply needs a procedure and a final list.
        CP 2
        JP C,SRTERROR              ; A missing list or procedure is malformed.
        LD HL,SRTARGPK             ; Record zero contains the target procedure.
        CALL SRTPVAL
        LD (SRTAPTAG),A            ; Keep its logical tag while the list is read.
        LD (SRTAPVAL),HL          ; Keep its payload beside the tag.
        LD A,(SRTARGC)             ; The final packet record is the list argument.
        DEC A
        LD L,A
        LD H,0
        ADD HL,HL                  ; Four bytes describe each packet record.
        ADD HL,HL
        LD DE,SRTARGPK
        ADD HL,DE
        CALL SRTPVAL               ; Recover the list tag and payload.
        LD (SRTQATAG),A            ; The existing pair helpers use these fields.
        LD (SRTQAVAL),HL
        LD A,(SRTARGC)             ; Leading arguments exclude procedure and list.
        SUB 2
        LD (SRTLCN),A              ; This is also the next output record index.
        CALL SRTAPMOV              ; Move leading records over the procedure slot.
SRTAPWLK:
        LD A,(SRTQATAG)            ; NIL is the only non-pair list terminator.
        OR A
        JR NZ,SRTAPPR
        LD HL,(SRTQAVAL)
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JP NZ,SRTERROR              ; Reject booleans, numbers and other scalars.
        JR SRTAPDN
SRTAPPR:
        CP 1
        JP NZ,SRTERROR              ; A dotted tail is not an apply argument list.
        LD A,(SRTLCN)
        CP 8
        JP NC,SRTERROR              ; The dynamic call packet has eight records.
        LD HL,(SRTQAVAL)            ; Read this pair's CAR before advancing its CDR.
        LD A,1
        CALL SRTCARV
        JP C,SRTERROR
        LD (SRTQCTAG),A             ; Preserve the CAR while computing its slot.
        LD (SRTQCAR),HL
        LD A,(SRTLCN)
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,SRTARGPK
        ADD HL,DE
        EX DE,HL                    ; DE now addresses the next output record.
        LD HL,(SRTQCAR)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD A,(SRTQCTAG)
        LD (DE),A
        INC DE
        LD A,1
        LD (DE),A                   ; Publish the appended value as initialized.
        LD A,(SRTLCN)
        INC A
        LD (SRTLCN),A
        LD HL,(SRTQAVAL)            ; Recover the same pair for its CDR.
        LD A,1
        CALL SRTCDRV
        JP C,SRTERROR
        LD (SRTQATAG),A
        LD (SRTQAVAL),HL
        JR SRTAPWLK

; Move the leading apply arguments from records one..n to records zero..n-1.
SRTAPMOV:
        LD A,(SRTLCN)
        OR A
        RET Z
        LD B,A
        LD HL,SRTARGPK+4
        LD DE,SRTARGPK
SRTAPML:
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ SRTAPML
        RET

; Enter the target through the ordinary or tail dispatcher selected by the
; caller.  SRTARGC is reduced to the number of spread arguments before entry.
SRTAPDN:
        LD A,(SRTLCN)
        LD (SRTARGC),A
        LD A,(SRTAPMOD)
        OR A
        JR NZ,SRTAPTGO
        LD A,1
        LD (SRTAPDIS),A            ; Preserve the outer continuation for either target.
        LD IX,(SRTRET)              ; Closure targets use the same saved continuation.
        LD A,(SRTAPTAG)
        LD HL,(SRTAPVAL)
        JP SRTDISP
SRTAPTGO:
        LD A,(SRTAPTAG)
        LD HL,(SRTAPVAL)
        JP SRTTARG
