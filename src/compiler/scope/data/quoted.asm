; Scope compiler quoted forms and list construction.
; Entry points: QUO_FORM, QUO_DATA and .LIST.
; Included in compiler order by ../data.asm.

; Quoted data and copied literal support for the compact compiler.
;
; The reader supplies one event at a time.  A quoted list therefore uses the
; generated runtime's four-byte data stack: each element is emitted normally,
; pushed at run time, and folded into pairs when the closing parenthesis arrives.
; Symbols and strings are copied into the output as length-prefixed literals.

QUO_LIST  EQU 1                    ; Encoding codes; see src/runtime/quoted.asm.
QUO_END   EQU 2
QUO_DOT   EQU 3
QUO_IMM   EQU 4
QUO_BYTE  EQU 5
QUO_INT   EQU 8
QUO_FLT   EQU 9
QUO_VEC   EQU 0AH

; Compile the explicit (quote datum) form.
QUO_FORM:
        CALL REC_NEXT              ; Read the one datum after quote.
        RET C                      ; Preserve a source failure.
        CALL QUO_DATA              ; Compile it without resolving symbols.
        RET C                      ; Reject malformed quoted structure.
        JP CMD_END                 ; The quote form accepts exactly one datum.

; Compile the apostrophe shorthand.  A nested apostrophe is data and therefore
; becomes the ordinary two-element list (quote datum).
QUO_TICK:
        CALL REC_NEXT              ; Read the datum following the prefix.
        RET C                      ; Preserve a reader failure.
        CP 3                       ; A second apostrophe is a quoted symbol.
        JR Z,QUO_NEST              ; Preserve it as (quote datum).
        JP QUO_DATA                ; Emit the quoted value directly.

; Quoted lists are compiled as data: CALL QT_BUILD, the cache and end words,
; then an encoding of the whole list that the runtime decodes once (see
; src/runtime/quoted.asm).  QUO_ENC is set while an encoding is open, so the
; datum compilers below write encoding bytes instead of code.

; Open an encoding: CALL QT_BUILD, the cache word and the end placeholder.
QUO_HEAD:
        LD HL,QT_BUILD
        CALL EM_CALL
        RET C
        LD A,(QUO_CNT)
        CP 255                     ; The byte-sized cache index must not wrap.
        JP NC,ERR_CAP
        LD (QUO_IDX),A
        INC A
        LD (QUO_CNT),A
        LD HL,(ST_PC)
        LD A,4                     ; Fixup kind four selects quoted cache cells.
        LD (ST_FKIND),A
        LD A,(QUO_IDX)
        LD (ST_FSLOT),A
        CALL EM_FIXUP
        RET C
        XOR A
        CALL SINK_PUT
        RET C
        CALL SINK_PUT
        RET C
        LD HL,(ST_PC)              ; The end word is patched when the list closes.
        CALL BR_PUSH
        RET C
        XOR A
        CALL SINK_PUT
        RET C
        CALL SINK_PUT
        RET C
        LD A,1
        LD (QUO_ENC),A
        RET

; Close the encoding: execution resumes at the current address.
QUO_FOOT:
        XOR A
        LD (QUO_ENC),A
        LD HL,(ST_PC)
        CALL BR_ABS
        JP BR_PATCH

; A nested apostrophe is the two-element list (quote datum).
QUO_NEST:
        LD A,(QUO_ENC)
        OR A
        JR NZ,.ENCODE
        CALL QUO_HEAD
        RET C
        CALL .ENCODE
        RET C
        JR QUO_FOOT
.ENCODE:
        LD A,QUO_LIST
        CALL SINK_PUT
        RET C
        LD HL,K_QUOTE+1            ; Intern the reader's ordinary quote name.
        LD BC,5
        LD IX,ST_SYMS
        CALL SYM_ID
        RET C
        LD A,4                     ; The quote operator is a symbol literal.
        CALL LIT_ADD
        RET C
        CALL REC_NEXT              ; The datum after the nested prefix.
        RET C
        CALL QUO_DATA
        RET C
        LD A,QUO_END
        JP SINK_PUT

; Dispatch one quoted reader event.
QUO_DATA:
        CP 7                       ; Exact integers and booleans are immediate.
        JR Z,.NUMBER
        CP 87H                     ; Float events retain their marker in replay.
        JR Z,.FLOAT
        CP 5                       ; A symbol is copied as an immutable literal.
        JP Z,.SYMBOL
        CP 8                       ; A string is copied with its byte length.
        JP Z,.STRING
        CP 1                       ; An opening parenthesis starts a data list.
        JP Z,.LIST
        CP 11                      ; #( starts a vector.
        JP Z,.VECTOR
        CP 3                       ; Quoted shorthand inside data is a pair.
        JR Z,QUO_NEST              ; Construct (quote datum) without collapsing it.
        JP ERR_BAD                 ; Close, dot and EOF are invalid datum starts.
.NUMBER:
        LD A,(QUO_ENC)
        OR A
        JP Z,CMD_NUM               ; Outside a list, emit the value as code.
        JR .SCALAR
.FLOAT:
        LD A,(QUO_ENC)
        OR A
        JP Z,EM_FLOAT
        LD (ST_IMMED),HL
        LD A,C
        LD (ST_IMMED+2),A
        LD A,QUO_FLT               ; Code 9: a float with three payload bytes.
        JR .THREE

; Encode a reader scalar: code 5 for a byte-sized exact integer, code 8 for
; a wider one, otherwise code 4 with its payload and tag.
.SCALAR:
        LD (ST_IMMED),HL
        LD A,C
        LD (ST_IMMED+2),A
        LD A,(RD_TAG)
        LD C,A
        OR A
        JR NZ,.TAGGED
        LD A,H
        CP 0FFH
        JR Z,.WIDE                 ; A character keeps its FFxx payload.
        LD A,0FEH                  ; A boolean becomes FE00H or FE01H.
        LD (ST_IMMED+1),A
        JR .WIDE
.TAGGED:
        CP 3
        JP NZ,ERR_TODO             ; Other scalar tags are not supported.
        LD A,(ST_IMMED+2)
        OR H
        JR NZ,.INT
        LD A,QUO_BYTE
        CALL SINK_PUT
        RET C
        LD A,(ST_IMMED)
        JP SINK_PUT
.INT:
        LD A,QUO_INT
.THREE:
        CALL SINK_PUT
        RET C
        LD HL,(ST_IMMED)
        CALL EM_WORD
        RET C
        LD A,(ST_IMMED+2)
        JP SINK_PUT
.WIDE:
        LD A,QUO_IMM
        CALL SINK_PUT              ; SINK_PUT keeps C, the tag.
        RET C
        LD HL,(ST_IMMED)
        CALL EM_WORD
        RET C
        LD A,C
        JP SINK_PUT

; Copy a quoted symbol into the output and return a tag-four value.
.SYMBOL:
        LD A,4                     ; Runtime tag four identifies a symbol literal.
        JP LIT_ADD

; Copy a quoted string into the output and return a tag-five value.
.STRING:
        LD A,5                     ; Runtime tag five identifies a string literal.
        JP LIT_ADD

; Compile one quoted list.  The outermost list opens the encoding; nested
; lists are encoded within it.  An outermost '() is just the constant.
.LIST:
        LD A,(QUO_ENC)
        OR A
        JR NZ,.BODY
        CALL REC_NEXT              ; The first element or the close.
        RET C
        CP 2
        JR NZ,.ITEMS
        LD HL,0FE02H               ; The empty list.
        JP EM_IMM
.ITEMS:
        PUSH AF                    ; Keep the first event across the header.
        PUSH HL
        LD A,(RD_TAG)
        PUSH AF
        PUSH BC                    ; C is the first value's byte 2.
        CALL QUO_HEAD
        JR C,.HEAD_BAD
        POP BC
        POP AF
        LD (RD_TAG),A
        POP HL
        POP AF
        CALL .GIVEN
        RET C
        JP QUO_FOOT
.HEAD_BAD:
        POP BC
        POP AF
        POP HL
        POP AF
        SCF
        RET

; Encode one list: code 1, its elements, then code 2, or code 3 after a
; dotted tail.  .GIVEN starts with the first event already read.
.BODY:
        CALL REC_NEXT
        RET C
.GIVEN:
        PUSH AF                    ; Keep the first event across code 1.
        PUSH HL
        LD A,(RD_TAG)
        PUSH AF
        PUSH BC                    ; C is the first value's byte 2.
        LD A,QUO_LIST
        CALL SINK_PUT
        JR C,.LIST_BAD
        POP BC
        POP AF
        LD (RD_TAG),A
        POP HL
        LD A,(QUO_LEN)             ; Keep the enclosing list's element count
        EX (SP),HL                 ; below the first event.
        LD B,H                     ; B is the event kind from the saved AF.
        LD H,A
        EX (SP),HL                 ; The stack word is now the count, HL the payload.
        XOR A
        LD (QUO_LEN),A
        LD A,B
        JR .ITEM
.LIST_BAD:
        POP BC
        POP AF
        POP HL
        POP AF
        SCF
        RET
.NEXT:
        CALL REC_NEXT              ; An element, a dot or the close.
        JR C,.FAIL
.ITEM:
        CP 2
        JR Z,.PROPER
        CP 4
        JR Z,.DOTTED
        OR A                       ; EOF cannot close an open quoted list.
        JR Z,.FAIL
        CALL .ELEMENT
        JR C,.FAIL
        JR .NEXT
.DOTTED:
        LD A,(QUO_LEN)             ; A dotted list needs at least one head.
        OR A
        JR Z,.FAIL
        CALL REC_NEXT              ; Exactly one tail datum.
        JR C,.FAIL
        CP 2
        JR Z,.FAIL
        CP 4
        JR Z,.FAIL
        OR A
        JR Z,.FAIL
        CALL .ELEMENT
        JR C,.FAIL
        CALL REC_NEXT              ; The tail must be followed by the close.
        JR C,.FAIL
        CP 2
        JR NZ,.FAIL
        LD A,QUO_DOT
        JR .CLOSE
.PROPER:
        LD A,QUO_END
.CLOSE:
        CALL SINK_PUT
        JR C,.FAIL
        POP AF
        LD (QUO_LEN),A
        OR A                       ; POP AF restored stale flags.
        RET
.FAIL:
        POP AF
        LD (QUO_LEN),A
        SCF
        RET

; Encode a vector: code 10, its elements, code 2.  An outermost vector opens
; and closes its own encoding.
.VECTOR:
        LD A,(QUO_ENC)
        OR A
        JR NZ,.VEC_BODY
        CALL QUO_HEAD
        RET C
        CALL .VEC_BODY
        RET C
        JP QUO_FOOT
.VEC_BODY:
        LD A,(QUO_LEN)             ; Keep the enclosing list's element count.
        PUSH AF
        XOR A
        LD (QUO_LEN),A
        LD A,QUO_VEC
        CALL SINK_PUT
        JR C,.VEC_FAIL
.VEC_NEXT:
        CALL REC_NEXT
        JR C,.VEC_FAIL
        CP 2
        JR Z,.VEC_END
        CP 4                       ; The reader already rejects a dot here.
        JR Z,.VEC_FAIL
        OR A
        JR Z,.VEC_FAIL
        CALL .ELEMENT
        JR C,.VEC_FAIL
        JR .VEC_NEXT
.VEC_END:
        LD A,QUO_END
        CALL SINK_PUT
        JR C,.VEC_FAIL
        POP AF
        LD (QUO_LEN),A
        OR A
        RET
.VEC_FAIL:
        POP AF
        LD (QUO_LEN),A
        SCF
        RET

; Encode one element, counting it against the quoted-data stack bound.
.ELEMENT:
        CALL QUO_DATA
        RET C
        LD A,(QUO_LEN)
        INC A
        LD (QUO_LEN),A
        CP 64                      ; The decoder's stack is bounded too.
        JP NC,ERR_CAP
        OR A
        RET

