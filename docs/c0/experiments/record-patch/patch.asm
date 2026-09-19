; C0 experiment: overwrite one to four existing staged-file bytes via BDOS.
; RPATCH: HL=file byte offset, DE=source address, B=length (1..4).
; RPLIMIT is the logical file length; RPFCB belongs to an already-open private
; staging file. No create, close, rename, publication or recovery is performed.
; A=0/C=0 succeeds; A=1 bounds, 2 random read, 3 random write with C=1 fail.
; IX/IY and caller SP survive even a BDOS that destroys other registers.
; Partial writes on I/O failure stay in the private staging file. Caller must
; abandon that generation. Static workspace is non-reentrant. Caller guarantees
; [DE,DE+B) is readable, nonwrapping, stable across BDOS and disjoint from this
; workspace, DMA buffer and stack. Valid-range attempts leave DMA at RPBUFFER;
; bounds failures leave the previous DMA selection unchanged.
; All file/FCB addresses fit 16 bits. Random record number uses all FCB fields.
        ORG 0100H
RPATCH:
        PUSH IX
        PUSH IY
        LD A,B
        OR A                  ; Zero cannot express a patch.
        JR Z,RPBOUND
        CP 5                  ; Fixed-width operand/header patches need <=4.
        JR NC,RPBOUND
        LD (RPCOUNT),A
        LD (RPSOURCE),DE
        LD (RPOFFSET),HL
        LD C,A
        LD B,0
        ADD HL,BC             ; Exclusive patch end must not wrap or exceed EOF.
        JR C,RPBOUND
        LD DE,(RPLIMIT)
        OR A
        SBC HL,DE
        JR C,RPDMA
        JR Z,RPDMA
RPBOUND:
        LD A,1
        JR RPFAIL
RPDMA:
        LD DE,RPBUFFER
        LD C,26
        CALL 5                ; Private operation selects DMA once; reads/writes retain it.
RPREAD:
        LD HL,(RPOFFSET)
        LD A,L
        AND 127               ; Low seven bits select the byte within DMA.
        LD (RPINDEX),A
        LD B,7
RPSHIFT:
        SRL H
        RR L
        DJNZ RPSHIFT
        LD (RPFCB+33),HL       ; Remaining bits select the 128-byte record.
        XOR A
        LD (RPFCB+35),A        ; No stale high record byte can select another file area.
        LD DE,RPFCB
        LD C,33
        CALL 5
        OR A
        JR Z,RPCOPY
        LD A,2
        JR RPFAIL
RPCOPY:
        LD A,(RPINDEX)
        LD E,A
        LD D,0
        LD HL,RPBUFFER
        ADD HL,DE
        LD DE,(RPSOURCE)
        LD A,(DE)
        LD (HL),A             ; Checked index is 0..127, never the next record.
        INC DE
        LD (RPSOURCE),DE
        LD HL,(RPOFFSET)
        INC HL
        LD (RPOFFSET),HL
        LD HL,RPCOUNT
        DEC (HL)
        JR Z,RPWRITE          ; Last patch byte commits this record.
        LD HL,RPINDEX
        INC (HL)
        LD A,(HL)
        CP 128
        JR C,RPCOPY            ; Continue in the same cached record when possible.
RPWRITE:
        LD DE,RPFCB
        LD C,34
        CALL 5
        OR A
        JR Z,RPNEXT
        LD A,3
        JR RPFAIL
RPNEXT:
        LD A,(RPCOUNT)
        OR A
        JR NZ,RPREAD           ; Crossing a boundary needs a fresh read/modify/write.
        JR RPRETURN           ; Zero and clear carry are the successful result.
RPFAIL:
        SCF                   ; POP does not alter the failure reason or flags.
RPRETURN:
        POP IY
        POP IX
        RET
RPEND:
RPWORK:
RPLIMIT:  DW 0                ; Logical extent, never physical Ctrl-Z padding.
RPOFFSET: DW 0                ; Next byte position during this patch.
RPSOURCE: DW 0                ; Next immutable input byte.
RPCOUNT:  DB 0                ; Remaining bytes, initially one through four.
RPINDEX:  DB 0                ; Byte position within the current DMA record.
RPFCB:    DS 36               ; Caller owns open-file identity/extent state.
RPBUFFER: DS 128              ; Exactly one read/modify/write record.
RPWEND:
