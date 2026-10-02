; CP/M source byte delivery and source-location marks.
; Entry points: CSBYTE, CSRAW, CSFAIL, CSMARKB and CSMARKI.
; ----------------------------------------------------------------------------
; CSBYTE -- byte callback for RINIT / LEXINIT
;
; Out:      carry clear, A = source byte; carry set = terminal stream.
; Preserves IX, IY and balances SP. BC, DE, HL are scratch.
; Parts are streamed in CSORDER.  A part's leading include region is delivered
; as spaces with its line breaks intact, so positions after it stay exact.
; One LF separates parts that do not already end in a line break.  EOF and
; errors are sticky until CSOPEN; CSCLOSE reports any recorded error.
; ----------------------------------------------------------------------------
CSBYTE: LD A,(CSDONE)
        OR A
        SCF
        RET NZ                   ; A terminal stream never asks BDOS for another record.
        LD HL,CSSEP              ; A pending separator is returned first.
        LD A,(HL)
        OR A
        JR Z,.ACTIVE
        LD (HL),0                ; Consume the one-byte part boundary.
        LD A,10                  ; LF prevents tokens joining across parts.
        OR A                     ; Carry clear: this is an ordinary byte.
        RET
.ACTIVE:
        LD A,(CSOPENF)           ; Is a source part already open?
        OR A
        JR Z,.NEXT               ; No part means select the next ordered entry.
        CALL CSRAW               ; Read one byte from the private DMA record.
        JR C,.PEND               ; End of part, or a sticky read failure.
        LD HL,(CSHEAD)           ; Blank the part's include region.
        LD B,A                   ; Keep the byte while testing the count.
        LD A,H
        OR L
        LD A,B
        JR Z,.KEEP               ; Past the header every byte is delivered.
        DEC HL
        LD (CSHEAD),HL           ; One fewer header byte remains.
        CP 13                    ; Line breaks keep line numbers exact.
        JR Z,.KEEP
        CP 10
        JR Z,.KEEP
        LD A,' '                 ; Other header bytes read as whitespace.
.KEEP:  CALL CSMARKB             ; Reset coordinates before a part's first byte.
        LD (CILAST),A            ; Remember whether a boundary needs LF.
        OR A                     ; Carry clear: A is a source byte.
        RET
.PEND:  LD A,(CSERROR)           ; A failed read must not look like clean EOF.
        OR A
        SCF
        RET NZ                   ; CSFAIL already made the stream terminal.
        CALL CSMARKI             ; Empty parts still have a stable location.
        CALL CICLOSE             ; Close the finished part before the next open.
        RET C                    ; A close failure is terminal.
        LD A,(CILAST)            ; Separate parts unless a line break ended this one.
        CP 10
        JR Z,.NEXT
        CP 13
        JR Z,.NEXT
        LD A,1
        LD (CSSEP),A             ; The LF is delivered before the next part.
.NEXT:  LD HL,CSOUT              ; Select the next part in dependency order.
        LD A,(CSCOUNT)
        CP (HL)
        JR Z,.ENDALL             ; Every part, ending with the root, was streamed.
        LD E,(HL)
        INC (HL)                 ; Advance the order cursor.
        LD D,0
        LD HL,CSORDER
        ADD HL,DE
        LD A,(HL)                ; A = source-table index of the next part.
        PUSH AF
        CALL CIOPEN              ; Reopen it; the scan proved it exists.
        POP BC                   ; B = the part index.
        RET C                    ; A failed reopen is terminal.
        LD A,B
        CALL CIHEADP             ; Load the part's include-region length.
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (CSHEAD),DE
        LD A,1
        LD (CSPEND),A            ; The next real byte starts the part.
        XOR A
        LD (CILAST),A            ; The part has not emitted a byte yet.
        JP CSBYTE                ; Return the separator or the part's first byte.
.ENDALL:
        LD A,1
        LD (CSDONE),A            ; The complete source stream is finished.
        SCF
        RET

; ----------------------------------------------------------------------------
; CSRAW -- read one byte from the open part
;
; Out: carry clear, A = byte; carry set at EOF or Ctrl-Z, or after a read
; failure recorded as CSERROR 2.  No source location is touched.
; ----------------------------------------------------------------------------
CSRAW:  LD A,(CSPEOF)            ; A completed part stays at EOF.
        OR A
        SCF
        RET NZ
        LD A,(CSRIDX)            ; Index 128 requests another BDOS record.
        CP 128
        JR C,.FETCH
        LD DE,CSBUFFER           ; Select the private 128-byte DMA record.
        LD C,26
        CALL CSBDOS
        LD DE,CSFCB              ; Read the next sequential source record.
        LD C,20
        CALL CSBDOS
        OR A
        JR Z,.RECORD
        DEC A                    ; CP/M status one is physical EOF.
        JR Z,.END
        LD A,2                   ; Other statuses are read failures.
        JR CSFAIL
.RECORD: XOR A                   ; The first byte in a fresh record is zero.
.FETCH: LD E,A
        LD D,0
        INC A
        LD (CSRIDX),A            ; Consume exactly one cached byte.
        LD HL,CSBUFFER
        ADD HL,DE
        LD A,(HL)
        CP 26                    ; Ctrl-Z terminates a CP/M text part.
        JR Z,.END
        OR A                     ; Carry clear: A is a part byte.
        RET
.END:   LD A,1
        LD (CSPEOF),A            ; Report a clean part boundary.
        SCF
        RET

; Record source error A unless an earlier error is already recorded, make the
; stream terminal and return carry.  HL and C are clobbered.
CSFAIL: LD HL,CSERROR
        LD C,A
        LD A,(HL)
        OR A
        JR NZ,.KEEP              ; The first failure is the one reported.
        LD (HL),C
.KEEP:  LD A,1
        LD (CSDONE),A            ; Further byte requests return EOF.
        SCF
        RET

; Stamp the first byte of a source part before the lexer can consume it.
; A is preserved.  The callback remains responsible for clearing carry.
CSMARKB:
        EX AF,AF'          ; Preserve the source byte in the alternate pair.
        CALL CSMARKI
        EX AF,AF'
        RET

; Common part-boundary work for byte and EOF callbacks.
CSMARKI:
        LD A,(CSPEND)
        OR A
        RET Z                    ; The part has already reset the coordinates.
        XOR A
        LD (CSPEND),A
        LD A,(CSPARTNO)
        JP LNEWPART              ; Line one, column one of this part.
