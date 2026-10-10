; Native CP/M file ports.
;
; File ports use the same opaque tag-eight value family as the three standard
; ports.  Four file streams may be open at once, in either direction; slot k
; (1 to 4) is the port token F00AH+k.  FS_TAB holds each slot's direction (1
; input, 2 output) and, while it is open, the heap page that holds its state:
; the CP/M FCB, the 128-byte record buffer, and the lookahead it parks while
; another input is read.  Opening takes the page and closing returns it, so a
; program pays for a stream only while it is open.  A closed slot keeps its
; direction, so the port predicates still answer for its token, and a later
; open may reuse the slot.
;
; The accepted name is a current-drive CP/M 8.3 spelling.  Drive prefixes,
; wildcards, directory separators, spaces and CP/M command-line delimiters are
; deliberately rejected until the provider-backed file contract has a portable
; path policy.  Opening for output a file that is open for input is rejected.

FS_SLOTS EQU 4                     ; File streams open at once.
FS_BIN   EQU 0                     ; Nonzero for a binary stream.
FS_IDX   EQU 1                     ; Next byte in the record buffer.
FS_ERR   EQU 2                     ; Sticky failure: 2 I/O, 3 close.
FS_EOF   EQU 3                     ; Nonzero once input has ended.
FS_OCR   EQU 4                     ; Text output has just written a CR.
FS_PARK  EQU 5                     ; Parked IN_STATE, IN_PEEK and IN_CR.
FS_FCB   EQU 8                     ; The CP/M file control block, 36 bytes.
FS_BUF   EQU 44                    ; The record buffer, 128 bytes.

; Dispatch the four file-opening primitives (runtime kinds 55 through 58).
FILE_OP:
        LD A,(ARG_CNT)
        CP 1
        JP NZ,ERROR
        LD A,(PRIM_ID)
        SUB 55                     ; 0 text in, 1 text out, 2 binary in,
        CP 4                       ; 3 binary out.
        JP NC,ERROR
        LD B,A
        AND 2
        LD (FILE_BIN),A
        LD A,B
        AND 1
        INC A
        LD (FILE_DIR),A            ; 1 input, 2 output.
        LD HL,ARG_PKT
        CALL PKT_VAL
        CALL FILE_ARG              ; FILE_FCB holds the name.
        PUSH IY
        LD A,(FILE_DIR)
        DEC A
        CALL NZ,FS_BUSY            ; Output must not replace an open input.
        LD B,FS_SLOTS              ; Find a closed slot.
.FIND:
        LD A,B
        CALL FS_SLOT
        JR Z,.FREE
        DJNZ .FIND
        JP ERROR                   ; Every stream is in use.
.FREE:
        LD A,B
        LD (FILE_SL),A
        LD HL,1                    ; The stream's state takes one heap page,
        CALL PAGE_NEW              ; after a collection if need be.
        JR NC,.PAGE
        CALL GC
        LD HL,1
        CALL PAGE_NEW
        JP C,ERROR
.PAGE:
        PUSH HL
        POP IY
        LD D,H                     ; Clear the state, the parked lookahead
        LD E,L                     ; and the FCB.
        INC DE
        LD (HL),0
        LD BC,FS_BUF-1
        LDIR
        LD A,(FILE_BIN)
        LD (IY+FS_BIN),A
        CALL FS_FCBP               ; Copy the name.
        LD HL,FILE_FCB
        LD BC,12
        LDIR
        CALL FS_FCBP
        LD A,(FILE_DIR)
        DEC A
        JR NZ,.MAKE
        LD A,128                   ; The first read fetches a record.
        LD (IY+FS_IDX),A
        LD C,15                    ; Open the file.
        CALL FS_BDOS
        JR .OPENED
.MAKE:
        PUSH DE
        LD C,19                    ; Delete any prior file; absence is fine.
        CALL FS_BDOS
        POP DE
        LD C,22                    ; Make the file.
        CALL FS_BDOS
.OPENED:
        INC A                      ; CP/M reports failure as 255.
        JR NZ,.KEEP
        PUSH IY                    ; Return the page before reporting it.
        POP HL
        LD DE,1
        CALL PAGE_REL
        JP ERROR
.KEEP:
        LD A,(FILE_SL)
        CALL FS_ENT                ; Publish the slot: its direction and page.
        LD A,(FILE_DIR)
        LD (HL),A
        INC HL
        PUSH IY
        POP DE
        LD (HL),D
        DEC A
        JR Z,.TOKEN
        LD HL,FS_OUTS              ; Count open outputs for the exit flush.
        INC (HL)
.TOKEN:
        POP IY
        LD A,(FILE_SL)
        ADD A,0AH                  ; Slot k is the token F00AH+k.
        LD L,A
        LD H,0F0H
        LD A,8
        PUSH IX
        RET

; Refuse to open for output the file an open input slot is reading.
FS_BUSY:
        LD B,FS_SLOTS
.SLOT:
        LD A,B
        CALL FS_SLOT
        JR Z,.NEXT
        LD A,(HL)                  ; HL is the slot's direction byte.
        DEC A
        JR NZ,.NEXT                ; Only an input can be replaced.
        CALL FS_FCBP
        INC DE
        LD HL,FILE_FCB+1
        LD C,11                    ; Eight name bytes and three type bytes.
.SAME:
        LD A,(DE)                  ; BDOS may set attribute bits in the FCB.
        AND 7FH
        CP (HL)
        JR NZ,.NEXT
        INC HL
        INC DE
        DEC C
        JR NZ,.SAME
        JP ERROR
.NEXT:
        DJNZ .SLOT
        RET

; HL = slot A's entry in FS_TAB, its direction byte.  Keeps BC.
FS_ENT:
        ADD A,A
        LD E,A
        LD D,0
        LD HL,FS_TAB-2
        ADD HL,DE
        RET

; HL = slot A's direction byte and IY = its state page.  Z means the slot is
; closed.  Keeps BC.
FS_SLOT:
        CALL FS_ENT
        INC HL
        LD A,(HL)
        DEC HL
        PUSH HL
        LD H,A
        LD L,0
        PUSH HL
        POP IY
        POP HL
        OR A
        RET

; DE = the FCB in the state page at IY.
FS_FCBP:
        PUSH IY
        POP DE
        LD E,FS_FCB
        RET

; HL = where open slot A parks its input lookahead.
FS_PARKP:
        CALL FS_ENT
        INC HL
        LD H,(HL)
        LD L,FS_PARK
        RET

; A = the slot of the file port token in L, which must be open in direction
; A (1 input, 2 output).
FS_OPEN:
        PUSH IY
        LD B,A
        LD A,L
        SUB 0AH
        LD C,A
        CALL FS_SLOT
        JP Z,ERROR                 ; A closed port.
        LD A,(HL)
        CP B
        JP NZ,ERROR                ; A port of the other direction.
        LD A,C
        POP IY
        RET

; A = the direction of the file port token in L, or zero for a slot never
; opened.
FS_WAY:
        LD A,L
        SUB 0AH
        CALL FS_ENT
        LD A,(HL)
        RET

; Close the file port token in L; closing a closed port does nothing.  Carry
; reports a failure.
FS_END:
        PUSH IY
        LD A,L
        SUB 0AH
        LD C,A
        LD A,(IN_SRC)              ; The console takes over from this input.
        CP C
        JR NZ,.SHUT
        PUSH BC
        XOR A
        CALL IN_USE
        POP BC
.SHUT:
        XOR A                      ; Output reverts to the console too.
        LD (OUT_SEL),A
        LD A,C
        CALL FS_SHUT
        POP IY
        RET

; Close every open stream at exit or after an error; ignore failures.
FS_ALL:
        PUSH IY
        LD B,FS_SLOTS
.LOOP:
        PUSH BC
        LD A,B
        CALL FS_SHUT
        POP BC
        DJNZ .LOOP
        POP IY
        RET

; Close slot A, flushing an output's last record, and return its page.
; Carry reports a failure, the first one the stream met.
FS_SHUT:
        CALL FS_SLOT
        RET Z                      ; Already closed.
        INC HL
        LD (HL),0                  ; The slot is closed; its direction stays.
        DEC HL
        LD A,(HL)
        DEC A
        JR Z,.CLOSE
        LD HL,FS_OUTS
        DEC (HL)
        CALL FS_SYNC
.CLOSE:
        CALL FS_FCBP
        LD C,16                    ; Close the file.
        CALL FS_BDOS
        INC A
        JR NZ,.FREE
        LD A,(IY+FS_ERR)
        OR A
        JR NZ,.FREE
        LD (IY+FS_ERR),3           ; A close failure.
.FREE:
        LD A,(IY+FS_ERR)
        PUSH AF
        PUSH IY
        POP HL
        LD DE,1
        CALL PAGE_REL
        POP AF
        OR A
        RET Z
        SCF
        RET

; Read one byte from the input slot in IN_SRC.  Carry with A=0 is the end
; of the file; carry with A nonzero is a read failure.  IN_MODE becomes the
; slot's binary flag.
FILE_GET:
        PUSH IY
        LD A,(IN_SRC)
        CALL FS_SLOT
        LD A,(IY+FS_BIN)
        LD (IN_MODE),A
        CALL .BYTE
        POP IY
        RET
.BYTE:
        LD A,(IY+FS_EOF)
        OR A
        JR NZ,.AGAIN
        LD A,(IY+FS_IDX)
        CP 128
        JR C,.TAKE                 ; The buffer still holds a byte.
        CALL FS_DMA
        CALL FS_FCBP
        LD C,20                    ; Read the next record.
        CALL FS_BDOS
        OR A
        JR Z,.TAKE
        DEC A                      ; Status 1 is the end of the file.
        LD A,2
        JR NZ,.FAIL
        XOR A
.FAIL:
        LD (IY+FS_ERR),A
        LD (IY+FS_EOF),1
.AGAIN:
        LD A,(IY+FS_ERR)
        SCF
        RET
.TAKE:
        LD E,A
        INC A
        LD (IY+FS_IDX),A
        LD A,E
        ADD A,FS_BUF               ; The buffer ends within the page.
        PUSH IY
        POP HL
        LD L,A
        LD A,(HL)
        OR A
        RET

; Write the byte in OUT_BYTE to the output slot in OUT_SEL.  A text stream
; turns a bare LF into CR/LF and adds no second CR after newline's own.
FILE_PUT:
        PUSH IY
        LD A,(OUT_SEL)
        CALL FS_SLOT
        CALL .MODE
        POP IY
        RET
.MODE:
        LD A,(IY+FS_BIN)
        OR A
        JR NZ,.RAW
        LD A,(OUT_BYTE)
        CP 13
        JR Z,.CR
        CP 10
        JR Z,.LF
        LD (IY+FS_OCR),0
        JR .RAW
.CR:
        CALL .RAW
        RET C
        LD (IY+FS_OCR),1
        RET
.LF:
        LD A,(IY+FS_OCR)
        OR A
        LD (IY+FS_OCR),0
        JR NZ,.RAW
        LD A,13
        CALL FS_PUT
        RET C
.RAW:
        LD A,(OUT_BYTE)

; Store A in the record buffer at IY, writing the buffer first when full.
FS_PUT:
        LD C,A
        LD A,(IY+FS_ERR)
        OR A
        SCF
        RET NZ
        LD A,(IY+FS_IDX)
        CP 128
        JR C,.STORE
        PUSH BC
        CALL FS_SYNC
        POP BC
        RET C
        XOR A
.STORE:
        LD E,A
        INC A
        LD (IY+FS_IDX),A
        LD A,E
        ADD A,FS_BUF
        PUSH IY
        POP HL
        LD L,A
        LD (HL),C
        XOR A
        RET

; Write the pending record at IY, padding a short one with Control-Z.
FS_SYNC:
        LD A,(IY+FS_ERR)
        OR A
        SCF
        RET NZ
        LD A,(IY+FS_IDX)
        OR A
        RET Z
        LD B,A
        ADD A,FS_BUF
        PUSH IY
        POP HL
        LD L,A
        LD A,128
        SUB B
        JR Z,.WRITE
        LD B,A
.PAD:
        LD (HL),26
        INC HL
        DJNZ .PAD
.WRITE:
        CALL FS_DMA
        CALL FS_FCBP
        LD C,21                    ; Write the record.
        CALL FS_BDOS
        OR A
        JR NZ,.FAIL
        LD (IY+FS_IDX),A
        RET
.FAIL:
        LD (IY+FS_ERR),2
        SCF
        RET

; Point the CP/M DMA address at the record buffer at IY.
FS_DMA:
        PUSH IY
        POP DE
        LD E,FS_BUF
        LD C,26
; Call the BDOS, keeping the index registers CP/M does not promise to keep.
FS_BDOS:
        PUSH IX
        PUSH IY
        CALL 5
        POP IY
        POP IX
        RET

; Build a current-drive CP/M FCB prefix from one literal or managed string.
; The parser accepts NAME or NAME.EXT with an eight-character name and a
; three-character extension.  The FCB is padded with spaces.
FILE_ARG:
        CALL STR_ARG
        JP C,ERROR
        LD A,(HL)
        OR A
        JP Z,ERROR
        CP 13
        JP NC,ERROR
        LD (FILE_LEN),A
        INC HL
        LD (FILE_PTR),HL
        XOR A
        LD (FILE_DOT),A
        LD (FILE_POS),A
        LD (FILE_EXT),A
        LD HL,FILE_FCB
        LD (HL),A
        INC HL
        LD B,11
        LD A,' '
.BLANK:
        LD (HL),A
        INC HL
        DJNZ .BLANK
.LOOP:
        LD A,(FILE_LEN)
        OR A
        JP Z,.FINISH
        LD HL,(FILE_PTR)
        LD A,(HL)
        INC HL
        LD (FILE_PTR),HL
        LD HL,FILE_LEN
        DEC (HL)
        ; Keep the character read above in A while the remaining length is
        ; updated.  Reloading from FILE_PTR here would skip the first byte.
        CP '.'
        JR Z,.DOT
        LD HL,.RESERVED            ; Search the bytes CP/M reserves in names.
        LD BC,13                   ; The table holds thirteen reserved bytes.
        CPIR                       ; Z means A matched a reserved byte.
        JP Z,ERROR                 ; Reject drives, paths, wildcards and delimiters.
        CP 21H                     ; Controls and space are not name bytes.
        JP C,ERROR
        CP 7FH                     ; DEL and high bytes are not name bytes.
        JP NC,ERROR
        CP 'a'
        JR C,.STORE
        CP '{'
        JR NC,.STORE
        SUB 20H
.STORE:
        LD (FILE_CHR),A
        LD A,(FILE_DOT)
        OR A
        JR NZ,.EXT_CHAR
        LD A,(FILE_POS)
        CP 8
        JP NC,ERROR
        LD E,A
        LD D,0
        LD HL,FILE_FCB+1
        ADD HL,DE
        LD A,(FILE_CHR)
        LD (HL),A
        LD A,(FILE_POS)
        INC A
        LD (FILE_POS),A
        JP .LOOP
.EXT_CHAR:
        LD A,(FILE_EXT)
        CP 3
        JP NC,ERROR
        LD E,A
        LD D,0
        LD HL,FILE_FCB+9
        ADD HL,DE
        LD A,(FILE_CHR)
        LD (HL),A
        LD A,(FILE_EXT)
        INC A
        LD (FILE_EXT),A
        JP .LOOP
.DOT:
        LD A,(FILE_DOT)
        OR A
        JP NZ,ERROR
        LD A,(FILE_POS)
        OR A
        JP Z,ERROR
        LD A,1
        LD (FILE_DOT),A
        JP .LOOP
.FINISH:
        LD A,(FILE_POS)
        OR A
        JP Z,ERROR
        LD A,(FILE_DOT)
        OR A
        JR Z,.GOOD
        LD A,(FILE_EXT)
        OR A
        JP Z,ERROR
.GOOD:
        XOR A
        RET

; Drive, path, wildcard and CP/M command-line delimiter bytes.
.RESERVED:  DB ":/",5CH,"*?<>=,;[]|"

FILE_FCB:    DS 12
FS_TAB:   DS 2*FS_SLOTS            ; Each slot's direction and state page.
