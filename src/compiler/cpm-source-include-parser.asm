; -----------------------------------------------------------------------------
; CIPARSE -- scan the open part's leading `(include "...")` forms
;
; Out: carry set for a malformed form, a bad or excess name, a cycle or a read
; error.  Otherwise A = the index of the first name not yet in the source
; table (just added), or FFH when every name is already ordered; then CIEND
; holds the length of the include region.
; -----------------------------------------------------------------------------
CIPARSE:
        LD HL,0
        LD (CIPOS),HL                  ; Count bytes from the start of the part.
        LD (CIEND),HL                  ; No include region has been seen yet.
.FORM:  CALL CISKIPV                   ; Leading comments and whitespace are free.
        JR C,.EMPTY                    ; An all-directive file has no body.
        CP '('
        JR NZ,.ORDINARY                ; Any other datum starts ordinary source.
        CALL CISKIPV                   ; Skip trivia before the directive name.
        JR C,.PSBAD
        CALL CIHEAD                    ; Match the seven-byte word `include`.
        JR NC,.HEADOK                  ; A valid directive has a delimiter.
        OR A
        JR NZ,.PSBAD                   ; A matched empty directive is malformed.
        JR .ORDINARY                   ; A different list is ordinary source.
.HEADOK:
        LD (CIARG),A                   ; One means CIHEAD consumed an opening quote.
.ARGS:  LD A,(CIARG)
        CP 1
        JR Z,.INLINE                   ; CIHEAD already consumed the opening quote.
        CALL CISKIPV                   ; Each argument must be a quoted filename.
        JR C,.ARGEND
        CP ')'
        JR Z,.ENDINC                   ; Finish a nonempty include form.
        CP '"'
        JR NZ,.PSBAD                   ; Reject symbols and computed arguments.
.INLINE: XOR A
        LD (CIARG),A                   ; Clear the pending-quote state.
        CALL CISTRING                   ; Copy one bounded filename to CSPART.
        JR C,.PSBAD
        CALL CIADD                      ; Validate the name and find or add its entry.
        JR C,.PSBAD
        RET NZ                          ; A new dependency is visited before this part.
        CALL CIHEADP                    ; An ordered part has its header length;
        LD A,(HL)                       ; a part still on the path holds FFFFH.
        INC HL
        AND (HL)
        INC A
        JR Z,.PSBAD                     ; Including a part on the path is a cycle.
        LD A,2
        LD (CIARG),A                   ; Two means at least one name is complete.
        JR .ARGS                       ; More filenames may follow in this form.
.ARGEND:
        JP .PSBAD                       ; EOF or a physical read failure is malformed.
.ENDINC:
        LD A,(CIARG)
        OR A
        JR Z,.PSBAD                    ; Empty include forms are not accepted.
        LD HL,(CIPOS)
        LD (CIEND),HL                  ; Blank this form when the part is streamed.
        JP .FORM
.EMPTY: LD A,(CSERROR)                ; A read error is not a clean empty source.
        OR A
        JR NZ,.PSBAD
.ORDINARY:
        LD A,0FFH                      ; Every leading include is already ordered.
        OR A                           ; Carry clear with the complete marker.
        RET
.PSBAD: SCF                            ; The caller assigns the source error code.
        RET

; Skip spaces, tabs, CR/LF and semicolon comments.  The first non-trivia byte
; is returned in A; CIPOS counts every byte consumed from the physical source.
CISKIPV:
.NEXT:  CALL CINRAW
        RET C
        CP ' '
        JR Z,.NEXT
        CP 9
        JR Z,.NEXT
        CP 10
        JR Z,.NEXT
        CP 13
        JR Z,.NEXT
        CP ';'
        JR NZ,.VRET
.COMMENT:
        CALL CINRAW
        RET C
        CP 10
        JR Z,.NEXT
        CP 13
        JR NZ,.COMMENT
        JR .NEXT
.VRET:  OR A
        RET

; Match `include` and require a delimiter after the final e.  The delimiter is
; consumed as trivia; that makes a following quote immediately usable by ARGS.
CIHEAD: LD DE,CIHEADS
        LD C,A                         ; CISKIPV already consumed the first byte.
        LD A,(DE)
        CP C
        JR NZ,.NO
        INC DE
        LD B,6
.CHAR:  PUSH BC                       ; BDOS may clobber the loop counter.
        PUSH DE                       ; CINRAW uses DE for its DMA address.
        CALL CINRAW
        POP DE
        POP BC
        RET C
        LD C,A
        LD A,(DE)
        INC DE
        CP C
        JR NZ,.NO
        DJNZ .CHAR
        CALL CINRAW
        RET C
        CP ' '
        JR Z,.YES
        CP 9
        JR Z,.YES
        CP 10
        JR Z,.YES
        CP 13
        JR Z,.YES
        CP '"'
        JR Z,.QUOTE
        CP ';'
        JR Z,.COMMENT
        CP ')'
        JR Z,.EMPTY
.NO:    XOR A
        SCF
        RET
.EMPTY: LD A,1                         ; Mark `(include)` as a malformed directive.
        SCF
        RET
.QUOTE: LD A,1                         ; Tell CIPARSE that the quote was consumed.
        OR A
        RET
.YES:   XOR A                          ; Whitespace remains available to ARGS.
        RET
.COMMENT:
        CALL CINRAW                    ; Discard a comment after the directive word.
        JR NC,.HCOMBYTE
        LD A,(CSERROR)
        OR A
        JR NZ,.NO
        XOR A                           ; Clean EOF lets ARGS report a missing name.
        RET
.HCOMBYTE:
        CP 10
        JR Z,.YES
        CP 13
        JR NZ,.COMMENT
        JR .YES

; Read a quoted filename into CSPART.  Escapes and control bytes are rejected;
; CP/M names are ASCII and the table builder enforces the 8.3 component sizes.
CISTRING:
        XOR A
        LD (CIPLEN),A
.BYTE:  CALL CINRAW
        RET C
        CP '"'
        JR Z,.STRDONE
        CP 92                           ; Backslash escapes are not CP/M names.
        JR Z,.STRBAD
        CP 32
        JR C,.STRBAD
        CP 127
        JR Z,.STRBAD
        LD C,A
        LD A,(CIPLEN)
        CP 12
        JR NC,.STRBAD
        LD L,A
        LD H,0
        LD DE,CSPART
        ADD HL,DE
        LD A,C
        LD (HL),A
        LD A,(CIPLEN)
        INC A
        LD (CIPLEN),A
        JR .BYTE
.STRDONE: LD A,(CIPLEN)
        OR A
        JR Z,.STRBAD
        OR A
        RET
.STRBAD: SCF
        RET

; Find or add CSPART as a normalised CP/M FCB prefix in CSSEEN.  The drive
; comes from the root; base and extension are upper-cased and space padded.
; Out: carry for a bad name or a full table; otherwise A = entry index with Z
; for a known name and NZ for a new one (a new index is never zero).
CIADD:  LD A,(CSCOUNT)                 ; Build the candidate in the next slot;
        CALL CSENTRY                    ; CSSEEN has one spare slot past the limit.
        LD (CITGT),HL                   ; Retain the destination for component writes.
        LD A,(CSSEEN)                   ; Copy the root drive byte.
        LD (HL),A
        INC HL
        LD B,11
        LD A,' '
.PAD:   LD (HL),A
        INC HL
        DJNZ .PAD
        LD A,(CIPLEN)
        LD B,A                          ; B counts source characters.
        LD HL,CSPART                    ; HL walks the quoted filename.
        LD A,0                          ; Base component is selected initially.
        LD (CIPDOT),A
        LD (CIBASE),A
        LD (CIEXT),A
.NAME:  LD A,(HL)
        INC HL
        CP '.'
        JR NZ,.NODOT
        LD A,(CIPDOT)
        OR A
        JP NZ,.ADDBAD                  ; Only one extension separator is valid.
        LD A,(CIBASE)
        OR A
        JP Z,.ADDBAD
        LD A,1
        LD (CIPDOT),A
        JR .NEXTNAME
.NODOT:
        CALL CIUPPER                    ; Return the checked uppercase byte in A.
        JP C,.ADDBAD
        LD C,A                          ; Preserve the character during indexing.
        LD A,(CIPDOT)
        OR A
        JR NZ,.EXT
        LD A,(CIBASE)
        INC A
        CP 9
        JP NC,.ADDBAD
        LD (CIBASE),A
        LD E,A
        DEC E
        LD D,0
        PUSH HL                       ; Preserve CSPART while addressing the slot.
        LD HL,(CITGT)
        INC HL
        ADD HL,DE
        LD A,C
        LD (HL),A
        POP HL
        JR .NEXTNAME
.EXT:   LD A,(CIEXT)
        INC A
        CP 4
        JP NC,.ADDBAD
        LD (CIEXT),A
        LD E,A
        DEC E
        LD D,0
        PUSH HL                       ; Preserve CSPART while addressing the slot.
        PUSH DE
        LD HL,(CITGT)
        LD DE,9
        ADD HL,DE
        POP DE
        ADD HL,DE
        LD A,C
        LD (HL),A
        POP HL
.NEXTNAME:
        DJNZ .NAME
        LD A,(CIBASE)
        OR A
        JP Z,.ADDBAD
        LD A,(CSCOUNT)
        LD B,A                          ; Compare against all prior prefixes.
        LD HL,CSSEEN                    ; HL walks prior slots.
.COMPARE:
        PUSH BC                         ; Preserve the remaining slot count.
        PUSH HL                         ; Preserve this slot for the next one.
        LD DE,(CITGT)                   ; DE walks the newly built candidate.
        LD C,12
.CBYTE: LD A,(DE)
        XOR (HL)
        JR NZ,.CMISS
        INC DE
        INC HL
        DEC C
        JR NZ,.CBYTE
        POP HL
        POP BC
        LD A,(CSCOUNT)                  ; B counted down from the table size.
        SUB B                           ; A = index of the existing entry.
        LD C,A
        XOR A                           ; Z and no carry: the name is known.
        LD A,C
        RET
.CMISS: POP HL
        POP BC
        LD DE,12
        ADD HL,DE
        DJNZ .COMPARE
        LD HL,CSCOUNT                   ; Keep the candidate as a new entry.
        LD A,(HL)
        CP CSMAXP
        JR NC,.ADDBAD                   ; Root plus 31 included parts maximum.
        INC (HL)
        OR A                            ; NZ and no carry: A is the new index.
        RET
.ADDBAD: SCF
        RET

; Upper-case an allowed CP/M filename byte.  This first native increment keeps
; the accepted set intentionally small and predictable: letters, digits, '-'
; and '_'.  Other punctuation can be added with a measured contract later.
CIUPPER:
        CP 'a'
        JR C,.CHECK
        CP 'z'+1
        JR NC,.CHECK
        SUB 32
.CHECK: CP '0'
        JR C,.SPECIAL
        CP '9'+1
        JR C,.GOOD
        CP 'A'
        JR C,.SPECIAL
        CP 'Z'+1
        JR C,.GOOD
.SPECIAL:
        CP '-'
        JR Z,.GOOD
        CP '_'
        JR NZ,.UPBAD
.GOOD:  OR A
        RET
.UPBAD: SCF
        RET

; CINRAW reads a byte while a part is being scanned and advances CIPOS.
CINRAW: CALL CSRAW
        RET C
        PUSH AF
        LD HL,CIPOS
        INC (HL)
        JR NZ,.COUNTED
        INC HL
        INC (HL)
.COUNTED:
        POP AF
        OR A
        RET
