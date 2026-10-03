; Native CP/M file ports.
;
; File ports use the same opaque tag-eight value family as the three standard
; ports.  This first adapter keeps one input and one output file open at a
; time.  The provider owns the FCB and 128-byte record buffers; Scheme sees
; only the port token and the ordinary character operations.
;
; The accepted name is a current-drive CP/M 8.3 spelling.  Drive prefixes,
; wildcards, directory separators, spaces and CP/M command-line delimiters are
; deliberately rejected until the provider-backed file contract has a portable
; path policy.  Opening the input file's name for output is also rejected.

; Dispatch the four file-opening primitives (runtime kinds 55 through 58).
FILE_OP:
        LD A,(PRIM_ID)
        CP 55
        JP Z,.TEXT_IN
        CP 56
        JP Z,.TEXT_OUT
        CP 57
        JP Z,.BIN_IN
        CP 58
        JP Z,.BIN_OUT
        JP ERROR

; Open a text input file.
.TEXT_IN:
        XOR A
        LD (FILE_BIN),A
        JP .OPEN_IN

; Open a binary input file.
.BIN_IN:
        LD A,1
        LD (FILE_BIN),A
.OPEN_IN:
        LD A,(ARG_CNT)
        CP 1
        JP NZ,ERROR
        LD A,(IN_FILE)
        OR A
        JP NZ,ERROR
        LD HL,ARG_PKT
        CALL PKT_VAL
        CALL FILE_ARG
        JP C,ERROR
        LD HL,FILE_FCB
        CALL CTOPENR
        JP C,ERROR
        LD A,1
        LD (IN_FILE),A
        LD A,(FILE_BIN)
        LD (IN_MODE),A
        CALL IN_RESET              ; The new file starts with no lookahead or EOF.
        LD A,8
        LD HL,FILE_IN
        PUSH IX
        RET

; Open a text output file, replacing an existing file of the same name.
.TEXT_OUT:
        XOR A
        LD (FILE_BIN),A
        JP .OPEN_OUT

; Open a binary output file, replacing an existing file of the same name.
.BIN_OUT:
        LD A,1
        LD (FILE_BIN),A
.OPEN_OUT:
        LD A,(ARG_CNT)
        CP 1
        JP NZ,ERROR
        LD A,(OUT_FILE)
        OR A
        JP NZ,ERROR
        LD HL,ARG_PKT
        CALL PKT_VAL
        CALL FILE_ARG
        JP C,ERROR
        LD A,(IN_FILE)             ; Only an open input file can share the name.
        OR A
        JR Z,.CREATE
        LD HL,FILE_FCB+1           ; Compare the new name with the input FCB name.
        LD DE,CTINFCB+1
        LD B,11                    ; Eight name bytes and three extension bytes.
.COMPARE:
        LD A,(DE)                  ; BDOS may set attribute bits in the input FCB.
        AND 7FH
        CP (HL)
        JR NZ,.CREATE              ; A different name may be replaced safely.
        INC HL
        INC DE
        DJNZ .COMPARE
        JP ERROR                   ; Replacing the file being read would delete it.
.CREATE:
        LD HL,FILE_FCB
        CALL CTOPENW
        JP C,ERROR
        LD A,1
        LD (OUT_FILE),A
        LD A,(FILE_BIN)
        LD (OUT_MODE),A
        XOR A
        LD (OUT_CR),A
        LD A,8
        LD HL,FILE_OUT
        PUSH IX
        RET

; Read one byte from the active CP/M input stream.
FILE_GET:
        LD A,(IN_FILE)
        OR A
        JR NZ,.OPEN
        SCF
        RET
.OPEN:
        JP CTREAD

; Close the input stream.  A closed stream is left alone; a failed close
; poisons the logical port.
IN_SHUT:
        LD A,(IN_FILE)
        OR A
        JR Z,FILE_NOP
        XOR A
        LD (IN_FILE),A
        CALL IN_RESET              ; Restore console state and drop the file's state.
        JP CTCLOSER

; Close the output stream and flush its final record.
OUT_SHUT:
        LD A,(OUT_FILE)
        OR A
        JR Z,FILE_NOP
        XOR A
        LD (OUT_FILE),A
        LD (OUT_SEL),A
        JP CTCLOSEW

FILE_NOP:
        XOR A                      ; Closing a closed port is a no-op, as in R7RS.
        RET                        ; Carry clear reports success to close-port.

; Write one byte to the active output stream.  Text mode turns a bare LF into
; CR/LF and avoids adding a second CR when newline has already emitted CR.
FILE_PUT:
        LD A,(OUT_FILE)
        OR A
        JR NZ,.MODE
        SCF
        RET
.MODE:
        LD A,(OUT_MODE)
        OR A
        JR NZ,.RAW
        LD A,(OUT_BYTE)
        CP 13
        JR Z,.CR
        CP 10
        JR Z,.LF
        XOR A
        LD (OUT_CR),A
        JR .RAW
.CR:
        CALL .RAW
        RET C
        LD A,1
        LD (OUT_CR),A
        RET
.LF:
        LD A,(OUT_CR)
        OR A
        JR Z,.CRLF
        XOR A
        LD (OUT_CR),A
        JR .RAW
.CRLF:
        LD A,13
        LD (OUT_BYTE),A
        CALL .RAW
        RET C
        LD A,10
        LD (OUT_BYTE),A
        JP .RAW
.RAW:
        LD A,(OUT_BYTE)
        JP CTWRITE

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
