; Standard Scheme ports for the direct CP/M console.
;
; The runtime represents the three default ports as immediate tag-eight
; values. F008H, F009H and F00AH identify input, output and error. F00BH to
; F00EH identify the four native CP/M file slots, which use the same checked
; port value contract as the standard streams.

CON_IN EQU 0F008H                 ; Current input port token.
CON_OUT EQU 0F009H                ; Current output port token.
CON_ERR EQU 0F00AH                ; Current error port token.

; Accept a generation-one tag-eight port token in A:HL.  Carry means invalid.
PORT_CHK:
        CP 8                       ; Ports are opaque tag-eight values.
        JR NZ,.BAD                 ; Other value kinds are never ports.
        LD A,H                     ; The port namespace occupies F000H upward.
        CP 0F0H
        JR NZ,.BAD                 ; Reject escape tokens and ordinary values.
        LD A,L                     ; Generation one uses slots eight through 14.
        CP 8
        JR C,.BAD
        CP 0FH
        JR NC,.BAD
        XOR A                      ; Clear carry for a valid standard token.
        RET
.BAD:
        SCF                         ; Carry reports a checked port type error.
        RET

; Check the selected port token and return the canonical result through IX.
PORT_IN:
        LD A,(ARG_CNT)
        OR A
        JP NZ,ERROR
        XOR A                      ; Return the input port as a scalar token.
        LD HL,CON_IN
        LD A,8
        PUSH IX
        RET
PORT_OUT:
        LD A,(ARG_CNT)
        OR A
        JP NZ,ERROR
        XOR A                      ; Return the output port as a scalar token.
        LD HL,CON_OUT
        LD A,8
        PUSH IX
        RET
PORT_ERR:
        LD A,(ARG_CNT)
        OR A
        JP NZ,ERROR
        XOR A                      ; Return the error port as a scalar token.
        LD HL,CON_ERR
        LD A,8
        PUSH IX
        RET

; Read one input port argument, or use the permanent current input port.
IN_ARG:
        LD A,(ARG_CNT)
        OR A                       ; A zero count selects console input.
        JR Z,IN_USE                ; A is zero: the default form uses console input.
        CP 1                       ; One argument names a specific input port.
        JP NZ,ERROR
        LD HL,ARG_PKT
        CALL PKT_VAL
        CALL PORT_CHK
        JP C,ERROR
        XOR A                      ; Normalize the explicit form to no arguments.
        LD (ARG_CNT),A
        LD A,L                     ; PORT_CHK left a token in F008H..F00EH.
        CP 8                       ; The standard input port uses the console hook.
        JR Z,.CONSOLE
        CP 0BH                     ; Output and error ports cannot be read.
        JP C,ERROR
        LD A,1                     ; A file port must be an open input.
        CALL FS_OPEN               ; A is its slot.
        JR IN_USE
.CONSOLE:
        XOR A                      ; Zero selects the console adapter.

; Make input source A live (zero console, or a file slot).  Each source owns
; its lookahead state, pending byte and pending CR; the others' copies are
; parked so one file's lookahead or EOF never leaks into another's reads.
IN_USE:
        LD HL,IN_SRC               ; Compare the request with the live source.
        CP (HL)
        RET Z                      ; The requested source already owns live state.
        PUSH AF
        LD A,(HL)                  ; Park the live state with its source.
        CALL IN_PARK
        EX DE,HL
        LD HL,IN_STATE
        LD BC,3
        LDIR
        POP AF
        LD (IN_SRC),A              ; Publish the new live source and fetch its
        CALL IN_PARK               ; parked state.
        LD DE,IN_STATE
        LD BC,3
        LDIR
        RET

; HL = where source A parks IN_STATE, IN_PEEK and IN_CR.
IN_PARK:
        OR A
        LD HL,IN_CON
        RET Z
        JP FS_PARKP

; Select output or error for a one-value operation.  The value remains in the
; first packet record; an optional second record carries the port token.
OUT_ARG1:
        LD A,(ARG_CNT)
        CP 1
        JR Z,OUT_STD
        CP 2
        JP NZ,ERROR
        LD HL,ARG_PKT+4            ; The port follows the value record.
        CALL OUT_PICK              ; Validate it and select its adapter.
        LD A,1                     ; Hide the optional port from the operation.
        LD (ARG_CNT),A
        RET

; Select output or error for a zero-value operation such as newline.
OUT_ARG0:
        LD A,(ARG_CNT)
        OR A
        JR Z,OUT_STD
        CP 1
        JP NZ,ERROR
        LD HL,ARG_PKT              ; The port is the only packet record.
        CALL OUT_PICK              ; Validate it and select its adapter.
        XOR A                      ; Remove the optional port packet record.
        LD (ARG_CNT),A
        RET
OUT_STD:
        XOR A                      ; The default form uses current output.
        LD (OUT_SEL),A
        LD HL,CON_OUT
        RET

; Select the output adapter for the port in the packet record at HL.
OUT_PICK:
        CALL PKT_VAL
        CALL PORT_CHK
        JP C,ERROR
        LD A,L                     ; PORT_CHK left a token in F008H..F00EH.
        CP 0BH                     ; File output uses the CP/M file adapter.
        JR NC,.FILE
        SUB 9                      ; Output F009H and error F00AH share the hook.
        CP 2
        JP NC,ERROR                ; Input ports cannot be written.
        XOR A                      ; Select the console byte hook.
        LD (OUT_SEL),A
        RET
.FILE:
        LD A,2                     ; A file port must be an open output.
        CALL FS_OPEN
        LD (OUT_SEL),A             ; Its slot selects the file adapter.
        RET

; The three predicates validate without contacting CP/M.
PORT_IS:
        CALL PKT_ONE
        CALL PORT_CHK
        JP C,PKT_NO
        JP PKT_YES
IN_IS:
        CALL PKT_ONE
        CALL PORT_CHK
        JP C,PKT_NO
        LD A,L                     ; PORT_CHK left a token in F008H..F00EH.
        CP 8                       ; Standard input is an input port.
        JP Z,PKT_YES
        CP 0BH                     ; So is a file opened for input.
        JP C,PKT_NO
        CALL FS_WAY
        DEC A
        JP Z,PKT_YES
        JP PKT_NO
OUT_IS:
        CALL PKT_ONE
        CALL PORT_CHK
        JP C,PKT_NO
        LD A,L                     ; PORT_CHK left a token in F008H..F00EH.
        CP 8                       ; Standard input is not an output port.
        JP Z,PKT_NO
        CP 0BH                     ; Output and error are.
        JP C,PKT_YES
        CALL FS_WAY                ; So is a file opened for output.
        CP 2
        JP Z,PKT_YES
        JP PKT_NO

; Standard records are owned by the runtime and cannot be closed. File records
; call the matching CP/M adapter and then become unavailable.
PORT_END:
        LD A,(ARG_CNT)
        CP 1
        JP NZ,ERROR
        CALL PKT_ONE
        CALL PORT_CHK
        JP C,ERROR
        LD A,L                     ; PORT_CHK left a token in F008H..F00EH.
        CP 0BH                     ; Standard ports cannot be closed.
        JP C,ERROR
        CALL FS_END                ; Only the I/O module makes file tokens.
        JP C,ERROR
        JP PKT_VOID

; Dispatch the port primitive range.  Values 46 through 53 are the existing
; port kinds; file open kinds 55 through 58 are dispatched separately below.
PORT_OP:
        LD A,(PRIM_ID)
        CP 46
        JP Z,PORT_IN
        CP 47
        JP Z,PORT_OUT
        CP 48
        JP Z,PORT_ERR
        CP 49
        JP Z,PORT_IS
        CP 50
        JP Z,IN_IS
        CP 51
        JP Z,OUT_IS
        CP 52
        JP Z,PORT_END
        CP 53
        JP Z,DR_READ
        JP ERROR

; Return one logical character from the selected input port.  The shared
; state consumes a datum-reader lookahead before asking the provider for data.
; State zero is empty, one is a pending byte and two is sticky EOF.
IN_NEXT:
        LD A,(IN_STATE)           ; Select the shared pending-input state.
        OR A
        JR Z,.POLL                  ; Empty state obtains one provider byte.
        CP 1
        JR Z,.PENDING               ; A pending byte belongs to this read.
        XOR A                         ; Sticky EOF uses the canonical scalar tag.
        LD HL,0FE03H                  ; Return the shared EOF value.
        RET
.PENDING:
        XOR A                         ; The pending byte is consumed exactly once.
        LD (IN_STATE),A            ; Reopen the state for the next provider read.
        LD A,(IN_PEEK)              ; Recover the logical byte retained by peek.
        LD L,A                        ; Place the character byte in the payload low byte.
        LD H,0FFH                     ; Characters use the reserved FFxx range.
        XOR A                         ; Characters use the scalar logical tag.
        RET
.POLL:
        LD A,(IN_SRC)
        OR A
        JR Z,.CONSOLE
        CALL FILE_GET                 ; The selected file adapter supplies one byte.
        JR C,IN_EOF                  ; Distinguish EOF from a provider failure.
        LD B,A
        LD A,(IN_MODE)
        OR A
        JR NZ,IN_BIN                  ; Binary files preserve CR, LF and Control-Z.
        JR .CR_CHECK                  ; Text files share the console CR/LF folding.
.CONSOLE:
        CALL IN_BYTE                  ; BDOS function one supplies the next raw byte.
        LD B,A                        ; Keep it while checking the pending CR state.
.CR_CHECK:
        LD A,(IN_CR)
        OR A
        JR Z,.CLASSIFY                ; No earlier CR needs an LF decision.
        XOR A                         ; A non-LF byte is returned on this read.
        LD (IN_CR),A                  ; Clear the pending physical line ending.
        LD A,B                        ; Recover the byte returned by the provider.
        CP 10
        JR Z,.POLL                   ; Consume the LF paired with a returned CR.
        JP .CLASSIFY                  ; A second CR starts another logical newline.
.CLASSIFY:
        LD A,B                        ; Recover the unclassified provider byte.
        CP 13
        JR NZ,.RAW                ; Ordinary bytes become logical characters.
        LD A,1                        ; Return CR as one logical newline.
        LD (IN_CR),A                  ; Consume a following physical LF on demand.
        LD A,10                       ; Continue with the logical newline byte.
.RAW:
        CP 26
        JR NZ,IN_CHAR                ; Control-Z marks the direct text EOF.
        LD A,2                        ; Keep EOF sticky across later reads and peeks.
        LD (IN_STATE),A
        XOR A                         ; EOF uses the canonical scalar tag.
        LD HL,0FE03H                  ; Return the shared EOF value.
        RET
IN_CHAR:
        LD L,A                        ; Place the logical byte in the payload low byte.
        LD H,0FFH                     ; Characters use the reserved FFxx range.
        XOR A                         ; Characters use the scalar logical tag.
        RET

IN_EOF:
        OR A                          ; FILE_GET's A: zero is a clean EOF and
        JP NZ,ERROR                   ; anything else a BDOS read failure.
        LD A,2
        LD (IN_STATE),A
        XOR A
        LD HL,0FE03H                  ; Physical file EOF becomes the EOF object.
        RET
IN_BIN:
        LD A,B
        JP IN_CHAR

IN_STATE:  DB 0                    ; Empty, pending byte or sticky EOF.
IN_PEEK:  DB 0                      ; Logical byte retained by datum lookahead.
IN_CR:   DB 0                       ; A returned CR: consume a following LF.
IN_CON:  DS 3                       ; The console's parked copy of those three.
IN_SRC:  DB 0                       ; Zero selects console input, else a file slot.
OUT_SEL: DB 0                     ; Zero selects console output, else a file slot.
