; CP/M source byte delivery and source-location marks.
; Entry points: SRC_BYTE, SRC_RAW, SRC_FAIL, SRC_MARK and SRC_EDGE.
; ----------------------------------------------------------------------------
; SRC_BYTE -- byte callback for RD_INIT / LX_INIT
;
; Out:      carry clear, A = source byte; carry set = terminal stream.
; Preserves IX, IY and balances SP. BC, DE, HL are scratch.
; Parts are streamed in SRC_LIST.  A part's leading include region is delivered
; as spaces with its line breaks intact, so positions after it stay exact.
; One LF separates parts that do not already end in a line break.  EOF and
; errors are sticky until SRC_OPEN; SRC_END reports any recorded error.
; ----------------------------------------------------------------------------
SRC_BYTE: LD A,(SRC_DONE)
        OR A
        SCF
        RET NZ                   ; A terminal stream never asks BDOS for another record.
        LD HL,SRC_SEP            ; A pending separator is returned first.
        LD A,(HL)
        OR A
        JR Z,.ACTIVE
        LD (HL),0                ; Consume the one-byte part boundary.
        LD A,10                  ; LF prevents tokens joining across parts.
        OR A                     ; Carry clear: this is an ordinary byte.
        RET
.ACTIVE:
        LD A,(SRC_LIVE)          ; Is a source part already open?
        OR A
        JR Z,.NEXT               ; No part means select the next ordered entry.
        CALL SRC_RAW             ; Read one byte from the private DMA record.
        JR C,.PART_END           ; End of part, or a sticky read failure.
        LD HL,(SRC_HEAD)         ; Blank the part's include region.
        LD B,A                   ; Keep the byte while testing the count.
        LD A,H
        OR L
        LD A,B
        JR Z,.KEEP               ; Past the header every byte is delivered.
        DEC HL
        LD (SRC_HEAD),HL         ; One fewer header byte remains.
        CP 13                    ; Line breaks keep line numbers exact.
        JR Z,.KEEP
        CP 10
        JR Z,.KEEP
        LD A,' '                 ; Other header bytes read as whitespace.
.KEEP:  CALL SRC_MARK            ; Reset coordinates before a part's first byte.
        LD (SRC_LAST),A          ; Remember whether a boundary needs LF.
        OR A                     ; Carry clear: A is a source byte.
        RET
.PART_END:  LD A,(SRC_ERR)       ; A failed read must not look like clean EOF.
        OR A
        SCF
        RET NZ                   ; SRC_FAIL already made the stream terminal.
        CALL SRC_EDGE            ; Empty parts still have a stable location.
        CALL SRC_SHUT            ; Close the finished part before the next open.
        RET C                    ; A close failure is terminal.
        LD A,(SRC_LAST)          ; Separate parts unless a line break ended this one.
        CP 10
        JR Z,.NEXT
        CP 13
        JR Z,.NEXT
        LD A,1
        LD (SRC_SEP),A           ; The LF is delivered before the next part.
.NEXT:  LD HL,SRC_POS            ; Select the next part in dependency order.
        LD A,(SRC_CNT)
        CP (HL)
        JR Z,.ALL_DONE           ; Every part, ending with the root, was streamed.
        LD E,(HL)
        INC (HL)                 ; Advance the order cursor.
        LD D,0
        LD HL,SRC_LIST
        ADD HL,DE
        LD A,(HL)                ; A = source-table index of the next part.
        PUSH AF
        CALL SRC_LOAD            ; Reopen it; the scan proved it exists.
        POP BC                   ; B = the part index.
        RET C                    ; A failed reopen is terminal.
        LD A,B
        CALL INC_SLOT            ; Load the part's include-region length.
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRC_HEAD),DE
        LD A,1
        LD (SRC_PEND),A          ; The next real byte starts the part.
        XOR A
        LD (SRC_LAST),A          ; The part has not emitted a byte yet.
        JP SRC_BYTE              ; Return the separator or the part's first byte.
.ALL_DONE:
        LD A,1
        LD (SRC_DONE),A          ; The complete source stream is finished.
        SCF
        RET

; ----------------------------------------------------------------------------
; SRC_RAW -- read one byte from the open part
;
; Out: carry clear, A = byte; carry set at EOF or Ctrl-Z, or after a read
; failure recorded as SRC_ERR 2.  No source location is touched.
; ----------------------------------------------------------------------------
SRC_RAW:  LD A,(SRC_EOF)         ; A completed part stays at EOF.
        OR A
        SCF
        RET NZ
        LD A,(SRC_IDX)           ; Index 128 requests another BDOS record.
        CP 128
        JR C,.FETCH
        LD DE,SRC_BUF            ; Select the private 128-byte DMA record.
        LD C,26
        CALL SRC_BDOS
        LD DE,SRC_FCB            ; Read the next sequential source record.
        LD C,20
        CALL SRC_BDOS
        OR A
        JR Z,.RECORD
        DEC A                    ; CP/M status one is physical EOF.
        JR Z,.END
        LD A,2                   ; Other statuses are read failures.
        JR SRC_FAIL
.RECORD: XOR A                   ; The first byte in a fresh record is zero.
.FETCH: LD E,A
        LD D,0
        INC A
        LD (SRC_IDX),A           ; Consume exactly one cached byte.
        LD HL,SRC_BUF
        ADD HL,DE
        LD A,(HL)
        CP 26                    ; Ctrl-Z terminates a CP/M text part.
        JR Z,.END
        OR A                     ; Carry clear: A is a part byte.
        RET
.END:   LD A,1
        LD (SRC_EOF),A           ; Report a clean part boundary.
        SCF
        RET

; Record source error A unless an earlier error is already recorded, make the
; stream terminal and return carry.  HL and C are clobbered.
SRC_FAIL: LD HL,SRC_ERR
        LD C,A
        LD A,(HL)
        OR A
        JR NZ,.KEEP              ; The first failure is the one reported.
        LD (HL),C
.KEEP:  LD A,1
        LD (SRC_DONE),A          ; Further byte requests return EOF.
        SCF
        RET

; Stamp the first byte of a source part before the lexer can consume it.
; A is preserved.  The callback remains responsible for clearing carry.
SRC_MARK:
        EX AF,AF'          ; Preserve the source byte in the alternate pair.
        CALL SRC_EDGE
        EX AF,AF'
        RET

; Common part-boundary work for byte and EOF callbacks.
SRC_EDGE:
        LD A,(SRC_PEND)
        OR A
        RET Z                    ; The part has already reset the coordinates.
        XOR A
        LD (SRC_PEND),A
        LD A,(SRC_PART)
        JP LX_RESET              ; Line one, column one of this part.
