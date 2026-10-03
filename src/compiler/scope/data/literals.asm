; Scope compiler symbol and string literal publication.
; Entry points: LIT_ADD, LIT_EMIT and .SYM_DIR.
; Included in compiler order by ../data.asm.

; Add one symbol or string spelling to the bounded literal pool.  A is the
; eventual runtime tag (four for symbol, five for string), HL is the reader ID.
LIT_ADD:
        LD (LIT_KIND),A
        LD (LIT_ID),HL
        LD HL,(LIT_ID)
        LD A,H
        AND 1FH                    ; Remove the reader's reference subtype.
        LD H,A
        LD A,(LIT_KIND)
        CP 4
        JP Z,.SYMBOL

; String descriptor: four bytes per identity and an arbitrary byte length.
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,HL
        LD DE,W_STRTAB
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (LIT_OFF),DE
        INC HL
        LD A,(HL)
        LD (LIT_LEN),A
        LD DE,W_STRBUF
        LD (LIT_POOL),DE
        JP .SPELL

; Symbol descriptor: three bytes per identity and a one-byte length.
.SYMBOL:
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,DE
        LD DE,W_SYMTAB
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (LIT_OFF),DE
        INC HL
        LD A,(HL)
        LD (LIT_LEN),A
        LD DE,W_SYMBUF
        LD (LIT_POOL),DE
.SPELL:
        LD A,(LIT_LEN)
        LD C,A
        LD B,0
        LD (LIT_SIZE),BC
        PUSH BC                    ; The search uses BC while walking records.
        CALL .FIND                ; Reuse an equal spelling and its output slot.
        POP BC                     ; Keep the source length for a new record.
        JP C,.POINTER             ; Existing symbols and strings keep identity.
        LD A,(LIT_CNT)
        CP 64
        JP NC,ERR_CAP             ; Only a genuinely new literal needs a record.
        LD HL,(LIT_USED)
        LD (LIT_POS),HL
        ADD HL,BC
        LD DE,W_LITCAP
        OR A
        SBC HL,DE
        JP NC,ERR_CAP
        LD HL,(LIT_OFF)
        LD DE,(LIT_POOL)
        ADD HL,DE
        LD (LIT_SRCP),HL
        LD HL,(LIT_USED)
        LD DE,W_LITBUF
        ADD HL,DE
        LD (LIT_DST),HL
        LD BC,(LIT_SIZE)
        LD A,B                     ; A zero-length literal needs no copy at all.
        OR C                       ; A zero BC would make Z80 LDIR copy 65536 bytes.
        JR Z,.COPIED               ; The descriptor still records the empty spelling.
        LD DE,(LIT_DST)
        LD HL,(LIT_SRCP)
        LDIR                       ; Copy only after the nonzero length guard.
.COPIED:
        LD HL,(LIT_USED)
        LD DE,(LIT_SIZE)
        ADD HL,DE
        LD (LIT_USED),HL
        LD A,(LIT_CNT)
        LD (LIT_IDX),A
        CALL LIT_REC
        LD DE,(LIT_POS)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(LIT_LEN)
        LD (HL),A
        INC HL
        LD A,(LIT_KIND)            ; Keep symbol and string records distinct.
        LD (HL),A
        LD A,(LIT_CNT)
        INC A
        LD (LIT_CNT),A
        JP .POINTER

; Find an existing literal with the same runtime kind and copied spelling.
; LIT_IDX returns the matching record, or the next free index on a miss.
.FIND:
        XOR A
        LD (LIT_IDX),A
.RECORD:
        LD A,(LIT_IDX)
        LD B,A
        LD A,(LIT_CNT)
        CP B
        JR Z,.MISS
        LD A,B
        CALL LIT_REC
        INC HL
        INC HL
        LD A,(HL)                 ; Compare decoded lengths before reading bytes.
        LD B,A
        LD A,(LIT_LEN)
        CP B
        JR NZ,.NEXT_REC
        INC HL
        LD A,(HL)                 ; The final record byte stores the value kind.
        LD B,A
        LD A,(LIT_KIND)
        CP B
        JR NZ,.NEXT_REC
        LD A,(LIT_IDX)
        CALL LIT_REC
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (LIT_OLD),DE
        LD HL,(LIT_OFF)
        LD DE,(LIT_POOL)
        ADD HL,DE
        LD (LIT_NEWP),HL
        LD HL,(LIT_OLD)
        LD DE,W_LITBUF
        ADD HL,DE
        LD (LIT_OLDP),HL
        LD A,(LIT_LEN)
        OR A
        JR Z,.FOUND
        LD (LIT_TODO),A
.COMPARE:
        LD HL,(LIT_NEWP)
        LD A,(HL)
        INC HL
        LD (LIT_NEWP),HL
        LD HL,(LIT_OLDP)
        CP (HL)
        JR NZ,.NEXT_REC
        INC HL
        LD (LIT_OLDP),HL
        LD A,(LIT_TODO)
        DEC A
        LD (LIT_TODO),A
        JR NZ,.COMPARE
.FOUND:
        SCF
        RET
.NEXT_REC:
        LD A,(LIT_IDX)
        INC A
        LD (LIT_IDX),A
        JR .RECORD
.MISS:
        OR A
        RET

; Emit a literal pointer placeholder and remember its record index.  Inside a
; quoted-data encoding the pointer is preceded by code 6 (symbol) or 7
; (string) instead of LD HL, and no tag load follows.
.POINTER:
        LD A,(QUO_ENC)
        OR A
        LD A,21H
        JR Z,.OPCODE
        LD A,(LIT_KIND)            ; Kinds four and five become codes 6 and 7.
        ADD A,2
.OPCODE:
        CALL SINK_PUT
        RET C
        LD HL,(ST_PC)
        LD A,3                     ; Fixup kind three selects W_LITOUT.
        LD (ST_FKIND),A
        LD A,(LIT_IDX)
        LD (ST_FSLOT),A
        CALL EM_FIXUP
        RET C
        XOR A
        CALL SINK_PUT
        RET C
        CALL SINK_PUT
        RET C
        LD A,(QUO_ENC)
        OR A
        RET NZ                     ; Carry is clear: the encoding has no tag.
        LD A,3EH
        CALL SINK_PUT
        RET C
        LD A,(LIT_KIND)
        JP SINK_PUT

; Append copied literals after generated code, slots and procedure records.
LIT_EMIT:
        LD A,(LIT_CNT)
        LD (LIT_STOP),A
        XOR A
        LD (LIT_IDX),A
.RECORD:
        LD A,(LIT_STOP)
        OR A
        JP Z,.SYMBOLS
        LD A,(LIT_IDX)
        CALL LIT_REC
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (LIT_OFF),DE
        INC HL
        LD A,(HL)
        LD (LIT_LEN),A
        LD HL,(ST_PC)
        LD (LIT_BASE),HL
        LD A,(LIT_LEN)
        CALL SINK_PUT
        RET C
        LD HL,(LIT_OFF)
        LD DE,W_LITBUF
        ADD HL,DE
        LD (LIT_SRCP),HL
        LD A,(LIT_LEN)
        LD (LIT_LEFT),A
.BYTE:
        LD A,(LIT_LEFT)
        OR A
        JP Z,.BASE
        LD HL,(LIT_SRCP)
        LD A,(HL)
        INC HL
        LD (LIT_SRCP),HL
        CALL SINK_PUT
        RET C
        LD A,(LIT_LEFT)
        DEC A
        LD (LIT_LEFT),A
        JP .BYTE
.BASE:
        LD A,(LIT_IDX)
        CALL LIT_OUT
        LD DE,(LIT_BASE)
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,(LIT_IDX)
        INC A
        LD (LIT_IDX),A
        LD A,(LIT_STOP)
        LD B,A
        LD A,(LIT_IDX)
        CP B
        JP C,.RECORD
.SYMBOLS:
        CALL .SYM_DIR              ; Publish a pointer directory for symbol literals.
        RET C
        LD HL,(ST_PC)
        XOR A
        RET

; Append the count-and-pointer directory consumed by the runtime symbol reader.
.SYM_DIR:
        LD HL,(ST_PC)
        LD (LIT_DIR),HL           ; The count byte is the directory start.
        CALL .SYM_CNT              ; Count kind-four records before writing bytes.
        LD A,(LIT_SYMS)
        CALL SINK_PUT
        RET C
        XOR A
        LD (LIT_ROW),A
.DIR_LOOP:
        LD A,(LIT_ROW)
        LD B,A
        LD A,(LIT_CNT)
        CP B
        JR Z,.DIR_DONE
        LD A,B
        CALL LIT_REC
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        CP 4
        JR NZ,.DIR_NEXT
        LD A,B
        CALL LIT_OUT
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (LIT_PTR),DE
        LD DE,(LIT_PTR)            ; The byte sink uses DE as its buffer index.
        LD A,E
        CALL SINK_PUT
        RET C
        LD DE,(LIT_PTR)            ; Restore the pointer before writing its high byte.
        LD A,D
        CALL SINK_PUT
        RET C
.DIR_NEXT:
        LD A,(LIT_ROW)
        INC A
        LD (LIT_ROW),A
        JR .DIR_LOOP
.DIR_DONE:
        LD HL,(ST_PC)
        LD (LIT_END),HL
        XOR A
        RET

; Count copied literal records whose runtime tag identifies a symbol.
.SYM_CNT:
        XOR A
        LD (LIT_SYMS),A
        LD (LIT_ROW),A
.CNT_LOOP:
        LD A,(LIT_ROW)
        LD B,A
        LD A,(LIT_CNT)
        CP B
        JR Z,.CNT_DONE
        LD A,B
        CALL LIT_REC
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        CP 4
        JR NZ,.CNT_NEXT
        LD A,(LIT_SYMS)
        INC A
        LD (LIT_SYMS),A
.CNT_NEXT:
        LD A,(LIT_ROW)
        INC A
        LD (LIT_ROW),A
        JR .CNT_LOOP
.CNT_DONE:
        RET

; Address one four-byte literal record or two-byte output-base entry.
LIT_REC:
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,W_LITREC
        ADD HL,DE
        RET
LIT_OUT:
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,W_LITOUT
        ADD HL,DE
        RET

LIT_KIND: DB 0
LIT_IDX:  DB 0
LIT_CNT:    DB 0
LIT_LEN:  DB 0
LIT_LEFT: DB 0
LIT_STOP: DB 0
LIT_ID:  DW 0
LIT_USED: DW 0
LIT_POS: DW 0
LIT_SIZE:  DW 0
LIT_OFF:  DW 0
LIT_BASE:  DW 0
LIT_DST:  DW 0
LIT_SRCP:  DW 0
LIT_POOL: DW 0
LIT_TODO:  DB 0
LIT_OLD:  DW 0
LIT_NEWP:  DW 0
LIT_OLDP:  DW 0
LIT_SYMS:   DB 0                  ; Number of published symbol literal pointers.
LIT_ROW:  DB 0                    ; Literal record cursor during directory emission.
LIT_DIR: DW 0                    ; Staged directory start, including its count byte.
LIT_END:  DW 0                    ; Staged directory exclusive end.
LIT_PTR:  DW 0                    ; Literal pointer held across sink writes.
QUO_ENC:    DB 0                  ; Nonzero while a quoted list is encoded.
QUO_LEN:  DB 0
QUO_TAIL:    DB 0
QUO_CNT:    DB 0                  ; Number of static quoted-list cache cells.
QUO_BASE:   DW 0                  ; Staged base address of the cache cells.
QUO_IDX:    DB 0                  ; Cache-cell index for the current list.
.EVENT:     DB 0
.TAG:    DB 0
.VALUE:    DW 0
