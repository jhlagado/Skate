;=============================================================================
;  CP/M binary transport
;=============================================================================
;
;  PURPOSE
;  -------
;  Stream binary files through private CP/M FCBs and one private 128-byte DMA
;  record.  The reader exposes raw bytes for NOBJ/COM consumers; the writer
;  pads only its final physical record with Ctrl-Z.  Logical NOBJ end is the
;  COMMIT record, so padding remains transport data and never becomes object
;  data.
;
;  PUBLIC INTERFACE
;  ----------------
;  CTOPENR   HL -> 12-byte drive/name/type prefix; open a binary input.
;  CTREAD    Return A = next byte, carry set at physical EOF or error.
;  CTCLOSER  Close input; A = sticky error (zero means success).
;  CTOPENW   HL -> 12-byte drive/name/type prefix; make a binary output.
;  CTWRITE   A = one byte; carry clear means it was accepted.
;  CTFLUSH   Write a pending short record, padding with Ctrl-Z.
;  CTCLOSEW  Flush and close output; A = sticky error (zero means success).
;  CTDELETE  HL -> 12-byte drive/name/type prefix; remove a file if present.
;  CTRENAME  HL -> source prefix, DE -> destination prefix; rename a file.
;
;  STATUS AND OWNERSHIP
;  --------------------
;  Error codes are 1=open/make, 2=read/write, 3=close, 4=not open.  Errors and
;  terminal reads are sticky until the corresponding open call.  The adapter
;  preserves IX, IY and SP across every public call.  BC, DE, HL and flags are
;  scratch unless a successful CTREAD returns its byte in A.
;
;  BDOS is entered only through the CP/M call vector at 0005H.  The adapter
;  owns both FCBs and both buffers; callers must not change DMA while a stream
;  is active.  This module is static and non-reentrant.
;=============================================================================

;-----------------------------------------------------------------------------
;  Binary input stream
;-----------------------------------------------------------------------------

CTOPENR:
        LD DE,CTINFCB          ; Copy the caller's concrete FCB prefix.
        LD BC,12
        LDIR
        XOR A
        LD (CTREERR),A         ; A fresh stream forgets earlier failures.
        LD (CTRACT),A
        LD (CTRDONE),A
        LD HL,CTINFCB+12
        LD B,24                ; Extent and record fields begin at zero.
CTRZERO:
        LD (HL),A
        INC HL
        DJNZ CTRZERO
        LD A,128
        LD (CTRIDX),A          ; Force the first CTREAD to fetch a record.
        LD DE,CTINFCB
        LD C,15                ; BDOS open file.
        CALL CTBDOS
        CP 255
        JR Z,CTROFAIL
        LD A,1
        LD (CTRACT),A
        XOR A                   ; Success: A=0, carry clear.
        RET
CTROFAIL:
        LD A,1                 ; Error 1: input open failed.
        JP CTREFAIL

; Return the next raw byte.  Physical EOF is clean; NOBJ callers stop at
; COMMIT before asking for transport padding.
CTREAD:
        LD A,(CTRDONE)
        OR A
        JR NZ,CTRTERM       ; Replay EOF or the original read error.
        LD A,(CTRACT)
        OR A
        JR NZ,CTRREADY
        LD A,4                 ; Error 4: no input stream is open.
        JP CTREFAIL
CTRREADY:
        LD A,(CTRIDX)
        CP 128
        JR C,CTRBYTE        ; A cached record still owns a byte.
        LD DE,CTRBUF
        LD C,26                ; Point BDOS at this stream's private record.
        CALL CTBDOS
        LD DE,CTINFCB
        LD C,20                ; Sequential read advances the FCB.
        CALL CTBDOS
        OR A
        JR Z,CTNEWREC
        CP 1                   ; CP/M status 1 is physical EOF.
        JR Z,CTREOF
        LD A,2                 ; Other statuses are read failures.
        JP CTREFAIL
CTNEWREC:
        XOR A
CTRBYTE:
        LD E,A                 ; Use the byte index as a 16-bit offset.
        LD D,0
        INC A
        LD (CTRIDX),A          ; 128 records the exhausted cache.
        LD HL,CTRBUF
        ADD HL,DE
        LD A,(HL)
        OR A                   ; A byte, including zero, returns carry clear.
        RET
CTREOF:
        LD A,1                 ; Clean physical EOF is terminal status one.
        LD (CTRDONE),A
        XOR A                  ; Carry reports EOF; A remains a neutral value.
        SCF
        RET
CTRTERM:
        LD A,(CTREERR)
        OR A
        SCF
        RET

; Close input and report the first failure, even if close also fails.
CTCLOSER:
        LD A,(CTRACT)
        OR A
        JR Z,CTRRES
        XOR A
        LD (CTRACT),A
        LD DE,CTINFCB
        LD C,16                ; BDOS close file.
        CALL CTBDOS
        CP 255
        JR NZ,CTRRES
        LD A,(CTREERR)
        OR A
        JR NZ,CTRRES
        LD A,3                 ; Error 3: close failed.
        LD (CTREERR),A
CTRRES:
        LD A,(CTREERR)
        OR A
        RET Z
        SCF
        RET

;-----------------------------------------------------------------------------
;  Binary output stream
;-----------------------------------------------------------------------------

CTOPENW:
        LD DE,CTOUTFCB         ; Copy the caller's concrete output FCB prefix.
        LD BC,12
        LDIR
        XOR A
        LD (CTWERR),A          ; A fresh output forgets earlier failures.
        LD (CTWACT),A
        LD (CTWIDX),A
        LD HL,CTOUTFCB+12
        LD B,24                ; Make starts with zero extent/record fields.
CTWZERO:
        LD (HL),A
        INC HL
        DJNZ CTWZERO
        LD DE,CTOUTFCB
        LD C,19                ; Delete any prior generation before making anew.
        CALL CTBDOS             ; CP/M returns 255 when the name was absent; ignore it.
        LD DE,CTOUTFCB
        LD C,22                ; BDOS make file.
        CALL CTBDOS
        CP 255
        JR Z,CTWOFAIL
        LD A,1
        LD (CTWACT),A
        XOR A
        RET
CTWOFAIL:
        LD A,1                 ; Error 1: output make failed.
        LD (CTWERR),A
        SCF
        RET

; Accept one byte into the private record cache.  A full cache is flushed
; before the new byte is stored, so exact multiples never gain an extra record.
CTWRITE:
        PUSH AF                ; Keep the caller's byte across the flush.
        LD A,(CTWACT)
        OR A
        JR Z,CTWNOOP
        LD A,(CTWERR)
        OR A
        JR NZ,CTWFAIL
        LD A,(CTWIDX)
        CP 128
        JR C,CTWSTORE
        CALL CTFLUSH            ; Preserve the pending caller byte on the stack.
        JR C,CTWFAIL
        XOR A
CTWSTORE:
        LD E,A
        LD D,0
        LD HL,CTWBUF
        ADD HL,DE
        POP AF
        LD (HL),A
        INC E
        LD A,E
        LD (CTWIDX),A
        XOR A
        RET
CTWNOOP:
        LD A,(CTWERR)
        OR A
        JR NZ,CTWFAIL          ; Preserve an earlier open/make failure.
        LD A,4                 ; Error 4: no output stream is open.
        LD (CTWERR),A
CTWFAIL:
        POP AF                 ; Discard the caller byte on a sticky failure.
        LD A,(CTWERR)
        OR A
        SCF
        RET

; Write the pending cache.  A short final record is padded with Ctrl-Z; an
; empty cache is deliberately a no-op for exact record multiples.
CTFLUSH:
        LD A,(CTWERR)
        OR A
        JR NZ,CTWFERR
        LD A,(CTWACT)
        OR A
        JR NZ,CTWFACT
        LD A,4                 ; Error 4: no output stream is open.
        LD (CTWERR),A
        JR CTWFERR
CTWFACT:
        LD A,(CTWIDX)
        OR A
        RET Z
        LD E,A
        LD D,0
        LD HL,CTWBUF
        ADD HL,DE              ; HL points just after the pending bytes.
        LD A,128
        SUB E                  ; Remaining bytes are the padding count.
        OR A
        JR Z,CTWPFOK            ; A full cache needs no padding bytes.
        LD B,A
        LD A,26                ; CP/M text padding is not part of NOBJ data.
CTWPAD:
        LD (HL),A
        INC HL
        DJNZ CTWPAD
CTWPFOK:
        LD DE,CTWBUF
        LD C,26                ; Select the private output DMA record.
        CALL CTBDOS
        LD DE,CTOUTFCB
        LD C,21                ; Sequential write advances the FCB.
        CALL CTBDOS
        OR A
        JR Z,CTWGOOD
        LD A,2                 ; Error 2: output record write failed.
        LD (CTWERR),A
        SCF
        RET
CTWGOOD:
        XOR A
        LD (CTWIDX),A          ; The cache is empty after a committed record.
        RET
CTWFERR:
        LD A,(CTWERR)
        OR A
        SCF
        RET

; Flush, close and preserve an earlier write failure over a close failure.
CTCLOSEW:
        LD A,(CTWACT)
        OR A
        JR Z,CTWRES
        CALL CTFLUSH
        XOR A
        LD (CTWACT),A
        LD DE,CTOUTFCB
        LD C,16                ; BDOS close file.
        CALL CTBDOS
        CP 255
        JR NZ,CTWRES
        LD A,(CTWERR)
        OR A
        JR NZ,CTWRES
        LD A,3                 ; Error 3: close failed.
        LD (CTWERR),A
CTWRES:
        LD A,(CTWERR)
        OR A
        RET Z
        SCF
        RET

;-----------------------------------------------------------------------------
;  Shared BDOS entry and private state
;-----------------------------------------------------------------------------

; Delete a file named by the caller.  CP/M reports FF when no matching file
; exists; cleanup treats that as success so stale stage names are harmless.
CTDELETE:
        LD DE,CTINFCB
        LD BC,12
        LDIR
        CALL CTRZFCB
        LD DE,CTINFCB
        LD C,19
        CALL CTBDOS
        OR A
        JR Z,CTDGOOD
        CP 255
        JR Z,CTDGOOD
        SCF
        RET
CTDGOOD:
        XOR A
        RET

; Rename one CP/M file.  The BDOS rename FCB contains the old prefix in its
; first 16 bytes and the new prefix at offset 16.  The two prefixes are kept
; separate from the stream FCBs so a failed publication cannot corrupt them.
CTRENAME:
        PUSH HL
        PUSH DE
        CALL CTRZFCB
        POP DE
        POP HL
        PUSH DE
        LD DE,CTINFCB
        LD BC,12
        LDIR
        POP HL
        LD DE,CTINFCB+16
        LD BC,12
        LDIR
        LD DE,CTINFCB
        LD C,23
        CALL CTBDOS
        OR A
        RET Z
        SCF
        RET

; Clear the non-prefix bytes shared by delete and rename FCBs.
CTRZFCB:
        XOR A
        LD HL,CTINFCB+12
        LD B,24
.FILL:
        LD (HL),A
        INC HL
        DJNZ .FILL
        RET

CTBDOS:
        PUSH IX                ; CP/M promises the 8080 register contract.
        PUSH IY
        CALL 5                 ; Always use the platform's BDOS vector.
        POP IY
        POP IX
        LD (CTSTATUS),A        ; Retain the raw status for diagnostics.
        RET

CTREFAIL:
        LD (CTREERR),A
        LD (CTRDONE),A
        SCF
        RET

CTREERR:   DB 0
CTSTATUS:  DB 0
CTRACT:    DB 0
CTRDONE:   DB 0
CTRIDX:    DB 128
CTINFCB:   DS 36
CTRBUF:    DS 128

CTWERR:    DB 0
CTWACT:    DB 0
CTWIDX:    DB 0
CTOUTFCB:  DS 36
CTWBUF:    DS 128
; The input FCB is idle while the compiler publishes output.  Reusing it keeps
; the transport workspace bounded without adding a third FCB.
