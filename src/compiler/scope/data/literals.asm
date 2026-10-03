; Scope compiler symbol and string literal publication.
; Entry points: SCLITADD, SCLITDAT and SCSYMDAT.
; Included in compiler order by ../data.asm.

; Add one symbol or string spelling to the bounded literal pool.  A is the
; eventual runtime tag (four for symbol, five for string), HL is the reader ID.
SCLITADD:
        LD (SCLITKND),A
        LD (SCLITVAL),HL
        LD HL,(SCLITVAL)
        LD A,H
        AND 1FH                    ; Remove the reader's reference subtype.
        LD H,A
        LD A,(SCLITKND)
        CP 4
        JP Z,SCLITSYM

; String descriptor: four bytes per identity and an arbitrary byte length.
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,HL
        LD DE,SCSTRDS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCLITOFF),DE
        INC HL
        LD A,(HL)
        LD (SCLITLEN),A
        LD DE,SCSTRPL
        LD (SCLITPB),DE
        JP SCLITSP

; Symbol descriptor: three bytes per identity and a one-byte length.
SCLITSYM:
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,DE
        LD DE,SCNAMEDS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCLITOFF),DE
        INC HL
        LD A,(HL)
        LD (SCLITLEN),A
        LD DE,SCNAMEPL
        LD (SCLITPB),DE
SCLITSP:
        LD A,(SCLITLEN)
        LD C,A
        LD B,0
        LD (SCLITREM),BC
        PUSH BC                    ; The search uses BC while walking records.
        CALL SCLTFIND             ; Reuse an equal spelling and its output slot.
        POP BC                     ; Keep the source length for a new record.
        JP C,SCLITPTR             ; Existing symbols and strings keep identity.
        LD A,(SCLITN)
        CP 64
        JP NC,SCCAP               ; Only a genuinely new literal needs a record.
        LD HL,(SCLITUSE)
        LD (SCLITPOF),HL
        ADD HL,BC
        LD DE,SCLITPSZ
        OR A
        SBC HL,DE
        JP NC,SCCAP
        LD HL,(SCLITOFF)
        LD DE,(SCLITPB)
        ADD HL,DE
        LD (SCLITSRC),HL
        LD HL,(SCLITUSE)
        LD DE,SCLITPL
        ADD HL,DE
        LD (SCLITDST),HL
        LD BC,(SCLITREM)
        LD A,B                     ; A zero-length literal needs no copy at all.
        OR C                       ; A zero BC would make Z80 LDIR copy 65536 bytes.
        JR Z,SCLTNCPY              ; The descriptor still records the empty spelling.
        LD DE,(SCLITDST)
        LD HL,(SCLITSRC)
        LDIR                       ; Copy only after the nonzero length guard.
SCLTNCPY:
        LD HL,(SCLITUSE)
        LD DE,(SCLITREM)
        ADD HL,DE
        LD (SCLITUSE),HL
        LD A,(SCLITN)
        LD (SCLITIDX),A
        CALL SCLITRCA
        LD DE,(SCLITPOF)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(SCLITLEN)
        LD (HL),A
        INC HL
        LD A,(SCLITKND)            ; Keep symbol and string records distinct.
        LD (HL),A
        LD A,(SCLITN)
        INC A
        LD (SCLITN),A
        JP SCLITPTR

; Find an existing literal with the same runtime kind and copied spelling.
; SCLITIDX returns the matching record, or the next free index on a miss.
SCLTFIND:
        XOR A
        LD (SCLITIDX),A
SCLITFLP:
        LD A,(SCLITIDX)
        LD B,A
        LD A,(SCLITN)
        CP B
        JR Z,SCLTMISS
        LD A,B
        CALL SCLITRCA
        INC HL
        INC HL
        LD A,(HL)                 ; Compare decoded lengths before reading bytes.
        LD B,A
        LD A,(SCLITLEN)
        CP B
        JR NZ,SCLTNEXT
        INC HL
        LD A,(HL)                 ; The final record byte stores the value kind.
        LD B,A
        LD A,(SCLITKND)
        CP B
        JR NZ,SCLTNEXT
        LD A,(SCLITIDX)
        CALL SCLITRCA
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCLTFOFF),DE
        LD HL,(SCLITOFF)
        LD DE,(SCLITPB)
        ADD HL,DE
        LD (SCLTFSRC),HL
        LD HL,(SCLTFOFF)
        LD DE,SCLITPL
        ADD HL,DE
        LD (SCLTFDST),HL
        LD A,(SCLITLEN)
        OR A
        JR Z,SCTFOUND
        LD (SCLTFREM),A
SCLTCMP:
        LD HL,(SCLTFSRC)
        LD A,(HL)
        INC HL
        LD (SCLTFSRC),HL
        LD HL,(SCLTFDST)
        CP (HL)
        JR NZ,SCLTNEXT
        INC HL
        LD (SCLTFDST),HL
        LD A,(SCLTFREM)
        DEC A
        LD (SCLTFREM),A
        JR NZ,SCLTCMP
SCTFOUND:
        SCF
        RET
SCLTNEXT:
        LD A,(SCLITIDX)
        INC A
        LD (SCLITIDX),A
        JR SCLITFLP
SCLTMISS:
        OR A
        RET

; Emit a literal pointer placeholder and remember its record index.  Inside a
; quoted-data encoding the pointer is preceded by code 6 (symbol) or 7
; (string) instead of LD HL, and no tag load follows.
SCLITPTR:
        LD A,(SCQENC)
        OR A
        LD A,21H
        JR Z,.OPCODE
        LD A,(SCLITKND)            ; Kinds four and five become codes 6 and 7.
        ADD A,2
.OPCODE:
        CALL SINKBYTE
        RET C
        LD HL,(SCPC)
        LD A,3                     ; Fixup kind three selects SCLITOUT.
        LD (SCFKIND),A
        LD A,(SCLITIDX)
        LD (SCFSLOT),A
        CALL SCFIX
        RET C
        XOR A
        CALL SINKBYTE
        RET C
        CALL SINKBYTE
        RET C
        LD A,(SCQENC)
        OR A
        RET NZ                     ; Carry is clear: the encoding has no tag.
        LD A,3EH
        CALL SINKBYTE
        RET C
        LD A,(SCLITKND)
        JP SINKBYTE

; Append copied literals after generated code, slots and procedure records.
SCLITDAT:
        LD A,(SCLITN)
        LD (SCLITRC8),A
        XOR A
        LD (SCLITIDX),A
SCLITDL:
        LD A,(SCLITRC8)
        OR A
        JP Z,SCLITDD
        LD A,(SCLITIDX)
        CALL SCLITRCA
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCLITOFF),DE
        INC HL
        LD A,(HL)
        LD (SCLITLEN),A
        LD HL,(SCPC)
        LD (SCLITBAS),HL
        LD A,(SCLITLEN)
        CALL SINKBYTE
        RET C
        LD HL,(SCLITOFF)
        LD DE,SCLITPL
        ADD HL,DE
        LD (SCLITSRC),HL
        LD A,(SCLITLEN)
        LD (SCLITRM8),A
SCLITDB:
        LD A,(SCLITRM8)
        OR A
        JP Z,SCLITDN
        LD HL,(SCLITSRC)
        LD A,(HL)
        INC HL
        LD (SCLITSRC),HL
        CALL SINKBYTE
        RET C
        LD A,(SCLITRM8)
        DEC A
        LD (SCLITRM8),A
        JP SCLITDB
SCLITDN:
        LD A,(SCLITIDX)
        CALL SCLITOA
        LD DE,(SCLITBAS)
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,(SCLITIDX)
        INC A
        LD (SCLITIDX),A
        LD A,(SCLITRC8)
        LD B,A
        LD A,(SCLITIDX)
        CP B
        JP C,SCLITDL
SCLITDD:
        CALL SCSYMDAT              ; Publish a pointer directory for symbol literals.
        RET C
        LD HL,(SCPC)
        XOR A
        RET

; Append the count-and-pointer directory consumed by the runtime symbol reader.
SCSYMDAT:
        LD HL,(SCPC)
        LD (SCSYMBAS),HL          ; The count byte is the directory start.
        CALL SCSYMCN               ; Count kind-four records before writing bytes.
        LD A,(SCSYMCT)
        CALL SINKBYTE
        RET C
        XOR A
        LD (SCSYMIDX),A
SCSYMLP:
        LD A,(SCSYMIDX)
        LD B,A
        LD A,(SCLITN)
        CP B
        JR Z,SCSYMDON
        LD A,B
        CALL SCLITRCA
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        CP 4
        JR NZ,SCSYMNXT
        LD A,B
        CALL SCLITOA
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCSYMPTR),DE
        LD DE,(SCSYMPTR)           ; The byte sink uses DE as its buffer index.
        LD A,E
        CALL SINKBYTE
        RET C
        LD DE,(SCSYMPTR)           ; Restore the pointer before writing its high byte.
        LD A,D
        CALL SINKBYTE
        RET C
SCSYMNXT:
        LD A,(SCSYMIDX)
        INC A
        LD (SCSYMIDX),A
        JR SCSYMLP
SCSYMDON:
        LD HL,(SCPC)
        LD (SCSYMEND),HL
        XOR A
        RET

; Count copied literal records whose runtime tag identifies a symbol.
SCSYMCN:
        XOR A
        LD (SCSYMCT),A
        LD (SCSYMIDX),A
SCSYMCLP:
        LD A,(SCSYMIDX)
        LD B,A
        LD A,(SCLITN)
        CP B
        JR Z,SCSYMCED
        LD A,B
        CALL SCLITRCA
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        CP 4
        JR NZ,SCSYMCNX
        LD A,(SCSYMCT)
        INC A
        LD (SCSYMCT),A
SCSYMCNX:
        LD A,(SCSYMIDX)
        INC A
        LD (SCSYMIDX),A
        JR SCSYMCLP
SCSYMCED:
        RET

; Address one four-byte literal record or two-byte output-base entry.
SCLITRCA:
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,SCLITREC
        ADD HL,DE
        RET
SCLITOA:
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,SCLITOUT
        ADD HL,DE
        RET

SCLITKND: DB 0
SCLITIDX:  DB 0
SCLITN:    DB 0
SCLITLEN:  DB 0
SCLITRM8: DB 0
SCLITRC8: DB 0
SCLITVAL:  DW 0
SCLITUSE: DW 0
SCLITPOF: DW 0
SCLITREM:  DW 0
SCLITOFF:  DW 0
SCLITBAS:  DW 0
SCLITDST:  DW 0
SCLITSRC:  DW 0
SCLITPB: DW 0
SCLTFREM:  DB 0
SCLTFOFF:  DW 0
SCLTFSRC:  DW 0
SCLTFDST:  DW 0
SCSYMCT:   DB 0                   ; Number of published symbol literal pointers.
SCSYMIDX:  DB 0                   ; Literal record cursor during directory emission.
SCSYMBAS: DW 0                   ; Staged directory start, including its count byte.
SCSYMEND:  DW 0                   ; Staged directory exclusive end.
SCSYMPTR:  DW 0                   ; Literal pointer held across sink writes.
SCQENC:    DB 0                   ; Nonzero while a quoted list is encoded.
SCQCOUNT:  DB 0
SCQDOT:    DB 0
SCQCNT:    DB 0                   ; Number of static quoted-list cache cells.
SCQBASE:   DW 0                   ; Staged base address of the cache cells.
SCQFIX:    DB 0                   ; Cache-cell index for the current list.
SCQEV:     DB 0
SCQTAG:    DB 0
SCQVAL:    DW 0
