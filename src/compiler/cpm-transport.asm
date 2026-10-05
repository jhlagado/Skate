; CP/M binary transport for compiler stages.
; CPM_OPEN/CPM_READ/CPM_ENDR read raw bytes. CPM_MAKE/CPM_PUT/CPM_SYNC/CPM_ENDW
; write padded records. CPM_ERA and CPM_REN manage staged files.
; CPM_OPEN/CPM_MAKE take HL -> a 12-byte drive/name/type prefix. CPM_READ returns
; A=byte/carry clear, carries with A=0 at physical EOF, A=2 on read failure or
; A=4 when unopened. CPM_PUT takes A=byte; CPM_SYNC and the close calls return
; A=0/carry clear or the sticky 1=open, 2=I/O, 3=close or 4=unopened error.
; CPM_ERA takes HL -> a prefix; CPM_REN takes HL -> old and DE -> new; both
; return carry clear on success. ASO callers stop at COMMIT; other consumers
; may read the raw padded file. Errors are sticky until open, and public calls
; preserve IX, IY and SP. The adapter owns its FCBs and DMA buffers.

CPM_OPEN:
        LD DE,CPM_RFCB         ; Copy the caller's concrete FCB prefix.
        LD BC,12
        LDIR
        XOR A
        LD (CPM_RERR),A        ; A fresh stream forgets earlier failures.
        LD (CPM_RACT),A
        LD (CPM_REOF),A
        LD HL,CPM_RFCB+12
        LD B,24                ; Extent and record fields begin at zero.
.ZERO:
        LD (HL),A
        INC HL
        DJNZ .ZERO
        LD A,128
        LD (CPM_RIDX),A        ; Force the first CPM_READ to fetch a record.
        LD DE,CPM_RFCB
        LD C,15                ; BDOS open file.
        CALL CPM_BDOS
        CP 255
        JR Z,.FAIL
        LD A,1
        LD (CPM_RACT),A
        XOR A                   ; Success: A=0, carry clear.
        RET
.FAIL:
        LD A,1                 ; Error 1: input open failed.
        JP CPM_RBAD

; Return the next raw byte. Physical EOF is clean; ASO callers stop at
; COMMIT before asking for transport padding.
CPM_READ:
        LD A,(CPM_REOF)
        OR A
        JR NZ,.REPLAY       ; Replay EOF or the original read error.
        LD A,(CPM_RACT)
        OR A
        JR NZ,.READY
        LD A,4                 ; Error 4: no input stream is open.
        JP CPM_RBAD
.READY:
        LD A,(CPM_RIDX)
        CP 128
        JR C,.BYTE          ; A cached record still owns a byte.
        LD DE,CPM_RBUF
        LD C,26                ; Point BDOS at this stream's private record.
        CALL CPM_BDOS
        LD DE,CPM_RFCB
        LD C,20                ; Sequential read advances the FCB.
        CALL CPM_BDOS
        OR A
        JR Z,.FRESH
        CP 1                   ; CP/M status 1 is physical EOF.
        JR Z,.EOF
        LD A,2                 ; Other statuses are read failures.
        JP CPM_RBAD
.FRESH:
        XOR A
.BYTE:
        LD E,A                 ; Use the byte index as a 16-bit offset.
        LD D,0
        INC A
        LD (CPM_RIDX),A        ; 128 records the exhausted cache.
        LD HL,CPM_RBUF
        ADD HL,DE
        LD A,(HL)
        OR A                   ; A byte, including zero, returns carry clear.
        RET
.EOF:
        LD A,1                 ; Clean physical EOF is terminal status one.
        LD (CPM_REOF),A
        XOR A                  ; Carry reports EOF; A remains a neutral value.
        SCF
        RET
.REPLAY:
        LD A,(CPM_RERR)
        OR A
        SCF
        RET

; Close input and report the first failure, even if close also fails.
CPM_ENDR:
        LD A,(CPM_RACT)
        OR A
        JR Z,.RESULT
        XOR A
        LD (CPM_RACT),A
        LD DE,CPM_RFCB
        LD C,16                ; BDOS close file.
        CALL CPM_BDOS
        CP 255
        JR NZ,.RESULT
        LD A,(CPM_RERR)
        OR A
        JR NZ,.RESULT
        LD A,3                 ; Error 3: close failed.
        LD (CPM_RERR),A
.RESULT:
        LD A,(CPM_RERR)
        OR A
        RET Z
        SCF
        RET

;-----------------------------------------------------------------------------
;  Binary output stream
;-----------------------------------------------------------------------------

CPM_MAKE:
        LD DE,CPM_WFCB         ; Copy the caller's concrete output FCB prefix.
        LD BC,12
        LDIR
        XOR A
        LD (CPM_WERR),A        ; A fresh output forgets earlier failures.
        LD (CPM_WACT),A
        LD (CPM_WIDX),A
        LD HL,CPM_WFCB+12
        LD B,24                ; Make starts with zero extent/record fields.
.ZERO:
        LD (HL),A
        INC HL
        DJNZ .ZERO
        LD DE,CPM_WFCB
        LD C,19                ; Delete any prior generation before making anew.
        CALL CPM_BDOS           ; CP/M returns 255 when the name was absent; ignore it.
        LD DE,CPM_WFCB
        LD C,22                ; BDOS make file.
        CALL CPM_BDOS
        CP 255
        JR Z,.FAIL
        LD A,1
        LD (CPM_WACT),A
        XOR A
        RET
.FAIL:
        LD A,1                 ; Error 1: output make failed.
        LD (CPM_WERR),A
        SCF
        RET

; Accept one byte into the private record cache.  A full cache is flushed
; before the new byte is stored, so exact multiples never gain an extra record.
CPM_PUT:
        PUSH AF                ; Keep the caller's byte across the flush.
        LD A,(CPM_WACT)
        OR A
        JR Z,.UNOPEN
        LD A,(CPM_WERR)
        OR A
        JR NZ,.FAIL
        LD A,(CPM_WIDX)
        CP 128
        JR C,.STORE
        CALL CPM_SYNC           ; Preserve the pending caller byte on the stack.
        JR C,.FAIL
        XOR A
.STORE:
        LD E,A
        LD D,0
        LD HL,CPM_WBUF
        ADD HL,DE
        POP AF
        LD (HL),A
        INC E
        LD A,E
        LD (CPM_WIDX),A
        XOR A
        RET
.UNOPEN:
        LD A,(CPM_WERR)
        OR A
        JR NZ,.FAIL            ; Preserve an earlier open/make failure.
        LD A,4                 ; Error 4: no output stream is open.
        LD (CPM_WERR),A
.FAIL:
        POP AF                 ; Discard the caller byte on a sticky failure.
        LD A,(CPM_WERR)
        OR A
        SCF
        RET

; Write the pending cache.  A short final record is padded with Ctrl-Z; an
; empty cache is deliberately a no-op for exact record multiples.
CPM_SYNC:
        LD A,(CPM_WERR)
        OR A
        JR NZ,.FAIL
        LD A,(CPM_WACT)
        OR A
        JR NZ,.ACTIVE
        LD A,4                 ; Error 4: no output stream is open.
        LD (CPM_WERR),A
        JR .FAIL
.ACTIVE:
        LD A,(CPM_WIDX)
        OR A
        RET Z
        LD E,A
        LD D,0
        LD HL,CPM_WBUF
        ADD HL,DE              ; HL points just after the pending bytes.
        LD A,128
        SUB E                  ; Remaining bytes are the padding count.
        OR A
        JR Z,.WRITE             ; A full cache needs no padding bytes.
        LD B,A
        LD A,26                ; CP/M padding is not part of the logical stream.
.PAD:
        LD (HL),A
        INC HL
        DJNZ .PAD
.WRITE:
        LD DE,CPM_WBUF
        LD C,26                ; Select the private output DMA record.
        CALL CPM_BDOS
        LD DE,CPM_WFCB
        LD C,21                ; Sequential write advances the FCB.
        CALL CPM_BDOS
        OR A
        JR Z,.GOOD
        LD A,2                 ; Error 2: output record write failed.
        LD (CPM_WERR),A
        SCF
        RET
.GOOD:
        XOR A
        LD (CPM_WIDX),A        ; The cache is empty after a committed record.
        RET
.FAIL:
        LD A,(CPM_WERR)
        OR A
        SCF
        RET

; Flush, close and preserve an earlier write failure over a close failure.
CPM_ENDW:
        LD A,(CPM_WACT)
        OR A
        JR Z,.RESULT
        CALL CPM_SYNC
        XOR A
        LD (CPM_WACT),A
        LD DE,CPM_WFCB
        LD C,16                ; BDOS close file.
        CALL CPM_BDOS
        CP 255
        JR NZ,.RESULT
        LD A,(CPM_WERR)
        OR A
        JR NZ,.RESULT
        LD A,3                 ; Error 3: close failed.
        LD (CPM_WERR),A
.RESULT:
        LD A,(CPM_WERR)
        OR A
        RET Z
        SCF
        RET

;-----------------------------------------------------------------------------
;  Shared BDOS entry and private state
;-----------------------------------------------------------------------------

CPM_BDOS:
        PUSH IX                ; CP/M promises the 8080 register contract.
        PUSH IY
        CALL 5                 ; Always use the platform's BDOS vector.
        POP IY
        POP IX
        LD (CPM_STAT),A        ; Retain the raw status for diagnostics.
        RET

CPM_RBAD:
        LD (CPM_RERR),A
        LD (CPM_REOF),A
        SCF
        RET

CPM_RERR:   DB 0
CPM_STAT:  DB 0
CPM_RACT:    DB 0
CPM_REOF:   DB 0
CPM_RIDX:    DB 128
CPM_RFCB:   DS 36
CPM_RBUF:    DS 128

CPM_WERR:    DB 0
CPM_WACT:    DB 0
CPM_WIDX:    DB 0
CPM_WFCB:  DS 36
CPM_WBUF:    DS 128
; The input FCB is idle while the compiler publishes output.  Reusing it keeps
; the transport workspace bounded without adding a third FCB.
