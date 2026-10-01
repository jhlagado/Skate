; CP/M source byte delivery and source-location marks.
; Entry points: CSBYTE, CSEOF, CSFAIL, CSMARKB and CSMARKI.
; ----------------------------------------------------------------------------
; CSBYTE -- byte callback for RINIT / LEXINIT
;
; Out:      carry clear, A = source byte; carry set = terminal stream.
; Preserves IX, IY and balances SP. BC, DE, HL are scratch.
; CSERROR:  0 = no I/O error, 1 = open, 2 = read, 3 = close, 4 = not open,
;           5 = malformed/duplicate/missing manifest part, 6 = manifest read.
; CSSTATUS retains the raw status of the most recent BDOS call.
; EOF and errors are sticky until CSOPEN. DMA is reset before every read;
; on return the process DMA address remains CSBUFFER.
; ----------------------------------------------------------------------------
CSBYTE: LD A,(CSDONE)
        OR A
        SCF
        RET NZ           ; A terminal stream never asks BDOS for another record.
        LD A,(CSINDEX+1)
        CP 1
        JP Z,CSPKBYTE      ; Mode one is the existing ordered .SKM stream.
        CP 2
        JP Z,CIBYTE        ; Mode two is the bounded native .SK8 stream.
.FLATB:
        LD A,(CSACTIVE)
        OR A
        JR NZ,.READY
        LD A,4
        JR CSFAIL
.READY:
        LD A,(CSINDEX)
        CP 128
        JR C,.FETCH
        LD DE,CSBUFFER
        LD C,26          ; Select this stream's private 128-byte DMA record.
        CALL CSBDOS
        LD DE,CSFCB
        LD C,20          ; BDOS advances the FCB across sequential extents.
        CALL CSBDOS
        OR A
        JR Z,.RECORD
        CP 1             ; CP/M sequential-read status 1 is physical EOF.
        JR Z,CSEOF
        LD A,2           ; Other read statuses are errors, never clean EOF.
        JR CSFAIL
.RECORD:
        XOR A
.FETCH:
        LD E,A
        LD D,0
        INC A
        LD (CSINDEX),A   ; Consume exactly one byte from the cached record.
        LD HL,CSBUFFER
        ADD HL,DE
        LD A,(HL)
        CP 26
        JR Z,CSEOF       ; Text padding is not passed to the Scheme lexer.
        CALL CSMARKB  ; Stamp the byte with its source-part coordinate base.
        OR A
        RET
CSEOF:  CALL CSMARKI  ; Empty and terminal parts still have a useful location.
        LD A,1
        LD (CSDONE),A
        SCF
        RET
CSFAIL: LD (CSERROR),A
        JR CSEOF

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
        JR Z,.VALID
        XOR A
        LD (CSPEND),A
        LD A,(CSPARTNO)
        CALL LNEWPART
.VALID: LD A,1
        RET

; ----------------------------------------------------------------------------
