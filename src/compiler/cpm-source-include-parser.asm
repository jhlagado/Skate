; -----------------------------------------------------------------------------
; INC_SCAN -- scan the open part's leading `(include "...")` forms
;
; Out: carry set for a malformed form, a bad or excess name, a cycle or a read
; error.  Otherwise A = the index of the first name not yet in the source
; table (just added), or FFH when every name is already ordered; then INC_END
; holds the length of the include region.
; -----------------------------------------------------------------------------
INC_SCAN:
        LD HL,0
        LD (INC_POS),HL                ; Count bytes from the start of the part.
        LD (INC_END),HL                ; No include region has been seen yet.
.FORM:  CALL INC_SKIP                  ; Leading comments and whitespace are free.
        JR C,.EMPTY                    ; An all-directive file has no body.
        CP '('
        JR NZ,.ORDINARY                ; Any other datum starts ordinary source.
        CALL INC_SKIP                  ; Skip trivia before the directive name.
        JR C,.BAD
        CALL INC_WORD                  ; Match the seven-byte word `include`.
        JR NC,.HEAD_OK                 ; A valid directive has a delimiter.
        OR A
        JR NZ,.BAD                     ; A matched empty directive is malformed.
        JR .ORDINARY                   ; A different list is ordinary source.
.HEAD_OK:
        LD (INC_ARG),A                 ; One means INC_WORD consumed an opening quote.
.ARGS:  LD A,(INC_ARG)
        CP 1
        JR Z,.INLINE                   ; INC_WORD already consumed the opening quote.
        CALL INC_SKIP                  ; Each argument must be a quoted filename.
        JR C,.ARG_END
        CP ')'
        JR Z,.CLOSE                    ; Finish a nonempty include form.
        CP '"'
        JR NZ,.BAD                     ; Reject symbols and computed arguments.
.INLINE: XOR A
        LD (INC_ARG),A                 ; Clear the pending-quote state.
        CALL INC_READ                   ; Copy one bounded filename to INC_NAME.
        JR C,.BAD
        CALL INC_ADD                    ; Validate the name and find or add its entry.
        JR C,.BAD
        RET NZ                          ; A new dependency is visited before this part.
        CALL INC_SLOT                   ; An ordered part has its header length;
        LD A,(HL)                       ; a part still on the path holds FFFFH.
        INC HL
        AND (HL)
        INC A
        JR Z,.BAD                       ; Including a part on the path is a cycle.
        LD A,2
        LD (INC_ARG),A                 ; Two means at least one name is complete.
        JR .ARGS                       ; More filenames may follow in this form.
.ARG_END:
        JR .BAD                         ; EOF or a physical read failure is malformed.
.CLOSE:
        LD A,(INC_ARG)
        OR A
        JR Z,.BAD                      ; Empty include forms are not accepted.
        LD HL,(INC_POS)
        LD (INC_END),HL                ; Blank this form when the part is streamed.
        JR .FORM
.EMPTY: LD A,(SRC_ERR)                ; A read error is not a clean empty source.
        OR A
        JR NZ,.BAD
.ORDINARY:
        LD A,0FFH                      ; Every leading include is already ordered.
        OR A                           ; Carry clear with the complete marker.
        RET
.BAD: SCF                              ; The caller assigns the source error code.
        RET

; Skip spaces, tabs, CR/LF and semicolon comments.  The first non-trivia byte
; is returned in A; INC_POS counts every byte consumed from the physical source.
INC_SKIP:
.NEXT:  CALL INC_BYTE
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
        JR NZ,.FOUND
.COMMENT:
        CALL INC_BYTE
        RET C
        CP 10
        JR Z,.NEXT
        CP 13
        JR NZ,.COMMENT
        JR .NEXT
.FOUND:  OR A
        RET

; Match `include` and require a delimiter after the final e.  The delimiter is
; consumed as trivia; that makes a following quote immediately usable by ARGS.
INC_WORD: LD DE,INC_TEXT
        LD C,A                         ; INC_SKIP already consumed the first byte.
        LD A,(DE)
        CP C
        JR NZ,.NO
        INC DE
        LD B,6
.CHAR:  PUSH BC                       ; BDOS may clobber the loop counter.
        PUSH DE                       ; INC_BYTE uses DE for its DMA address.
        CALL INC_BYTE
        POP DE
        POP BC
        RET C
        LD C,A
        LD A,(DE)
        INC DE
        CP C
        JR NZ,.NO
        DJNZ .CHAR
        CALL INC_BYTE
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
.QUOTE: LD A,1                         ; Tell INC_SCAN that the quote was consumed.
        OR A
        RET
.YES:   XOR A                          ; Whitespace remains available to ARGS.
        RET
.COMMENT:
        CALL INC_BYTE                  ; Discard a comment after the directive word.
        JR NC,.LINE_END
        LD A,(SRC_ERR)
        OR A
        JR NZ,.NO
        XOR A                           ; Clean EOF lets ARGS report a missing name.
        RET
.LINE_END:
        CP 10
        JR Z,.YES
        CP 13
        JR NZ,.COMMENT
        JR .YES

; Read a quoted filename into INC_NAME.  Escapes and control bytes are rejected;
; CP/M names are ASCII and the table builder enforces the 8.3 component sizes.
INC_READ:
        XOR A
        LD (INC_LEN),A
.BYTE:  CALL INC_BYTE
        RET C
        CP '"'
        JR Z,.DONE
        CP 92                           ; Backslash escapes are not CP/M names.
        JR Z,.BAD
        CP 32
        JR C,.BAD
        CP 127
        JR Z,.BAD
        LD C,A
        LD A,(INC_LEN)
        CP 12
        JR NC,.BAD
        LD L,A
        LD H,0
        LD DE,INC_NAME
        ADD HL,DE
        LD A,C
        LD (HL),A
        LD A,(INC_LEN)
        INC A
        LD (INC_LEN),A
        JR .BYTE
.DONE: LD A,(INC_LEN)
        OR A
        JR Z,.BAD
        OR A
        RET
.BAD: SCF
        RET

; Find or add INC_NAME as a normalised CP/M FCB prefix in SRC_SEEN.  The drive
; comes from the root; base and extension are upper-cased and space padded.
; Out: carry for a bad name or a full table; otherwise A = entry index with Z
; for a known name and NZ for a new one (a new index is never zero).
INC_ADD:  LD A,(SRC_CNT)               ; Build the candidate in the next slot;
        CALL SRC_SLOT                   ; SRC_SEEN has one spare slot past the limit.
        LD (INC_DST),HL                 ; Retain the destination for component writes.
        LD A,(SRC_SEEN)                 ; Copy the root drive byte.
        LD (HL),A
        INC HL
        LD B,11
        LD A,' '
.PAD:   LD (HL),A
        INC HL
        DJNZ .PAD
        LD A,(INC_LEN)
        LD B,A                          ; B counts source characters.
        LD HL,INC_NAME                  ; HL walks the quoted filename.
        LD A,0                          ; Base component is selected initially.
        LD (INC_DOT),A
        LD (INC_BASE),A
        LD (INC_EXT),A
.NAME:  LD A,(HL)
        INC HL
        CP '.'
        JR NZ,.LETTER
        LD A,(INC_DOT)
        OR A
        JP NZ,.BAD                     ; Only one extension separator is valid.
        LD A,(INC_BASE)
        OR A
        JP Z,.BAD
        LD A,1
        LD (INC_DOT),A
        JR .NEXT
.LETTER:
        CALL .UPPER                     ; Return the checked uppercase byte in A.
        JR C,.BAD
        LD C,A                          ; Preserve the character during indexing.
        LD A,(INC_DOT)
        OR A
        JR NZ,.EXT
        LD A,(INC_BASE)
        INC A
        CP 9
        JR NC,.BAD
        LD (INC_BASE),A
        LD E,A
        DEC E
        LD D,0
        PUSH HL                       ; Preserve INC_NAME while addressing the slot.
        LD HL,(INC_DST)
        INC HL
        ADD HL,DE
        LD A,C
        LD (HL),A
        POP HL
        JR .NEXT
.EXT:   LD A,(INC_EXT)
        INC A
        CP 4
        JR NC,.BAD
        LD (INC_EXT),A
        LD E,A
        DEC E
        LD D,0
        PUSH HL                       ; Preserve INC_NAME while addressing the slot.
        PUSH DE
        LD HL,(INC_DST)
        LD DE,9
        ADD HL,DE
        POP DE
        ADD HL,DE
        LD A,C
        LD (HL),A
        POP HL
.NEXT:
        DJNZ .NAME
        LD A,(INC_BASE)
        OR A
        JR Z,.BAD
        LD A,(SRC_CNT)
        LD B,A                          ; Compare against all prior prefixes.
        LD HL,SRC_SEEN                  ; HL walks prior slots.
.SLOT:
        PUSH BC                         ; Preserve the remaining slot count.
        PUSH HL                         ; Preserve this slot for the next one.
        LD DE,(INC_DST)                 ; DE walks the newly built candidate.
        LD C,12
.BYTE: LD A,(DE)
        XOR (HL)
        JR NZ,.MISS
        INC DE
        INC HL
        DEC C
        JR NZ,.BYTE
        POP HL
        POP BC
        LD A,(SRC_CNT)                  ; B counted down from the table size.
        SUB B                           ; A = index of the existing entry.
        LD C,A
        XOR A                           ; Z and no carry: the name is known.
        LD A,C
        RET
.MISS: POP HL
        POP BC
        LD DE,12
        ADD HL,DE
        DJNZ .SLOT
        LD HL,SRC_CNT                   ; Keep the candidate as a new entry.
        LD A,(HL)
        CP SRC_MAX
        JR NC,.BAD                      ; Root plus 31 included parts maximum.
        INC (HL)
        OR A                            ; NZ and no carry: A is the new index.
        RET
.BAD: SCF
        RET

; Upper-case an allowed CP/M filename byte.  This first native increment keeps
; the accepted set intentionally small and predictable: letters, digits, '-'
; and '_'.  Other punctuation can be added with a measured contract later.
.UPPER:
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
        JR NZ,.REJECT
.GOOD:  OR A
        RET
.REJECT: SCF
        RET

; INC_BYTE reads a byte while a part is being scanned and advances INC_POS.
INC_BYTE: CALL SRC_RAW
        RET C
        PUSH AF
        LD HL,INC_POS
        INC (HL)
        JR NZ,.COUNTED
        INC HL
        INC (HL)
.COUNTED:
        POP AF
        OR A
        RET
