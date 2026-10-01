; Standard Scheme ports for the direct CP/M console.
;
; The first port stage keeps the three default ports as immediate tag-eight
; values.  F008H, F009H and F00AH identify input, output and error.  The
; provider table and nonstandard handles arrive in later stages; these checks
; make the public port operations use the same value contract from the start.

SRTINPT EQU 0F008H                ; Current input port token.
SRTPOUT EQU 0F009H                ; Current output port token.
SRTPERR EQU 0F00AH                ; Current error port token.
SRTFIPT EQU 0F00BH                ; Native CP/M file input token.
SRTFOPT EQU 0F00CH                ; Native CP/M file output token.

; Accept a generation-one tag-eight port token in A:HL.  Carry means invalid.
SRTVPORT:
        CP 8                       ; Ports are opaque tag-eight values.
        JR NZ,SRTBADPT             ; Other value kinds are never ports.
        LD A,H                     ; The port namespace occupies F000H upward.
        CP 0F0H
        JR NZ,SRTBADPT             ; Reject escape tokens and ordinary values.
        LD A,L                     ; Generation one uses slots eight through twelve.
        CP 8
        JR C,SRTBADPT
        CP 0DH
        JR NC,SRTBADPT
        XOR A                      ; Clear carry for a valid standard token.
        RET
SRTBADPT:
        SCF                         ; Carry reports a checked port type error.
        RET

; Check the selected port token and return the canonical result through IX.
SRTPORTI:
        LD A,(SRTARGC)
        OR A
        JP NZ,SRTERROR
        XOR A                      ; Return the input port as a scalar token.
        LD HL,SRTINPT
        LD A,8
        PUSH IX
        RET
SRTPORTO:
        LD A,(SRTARGC)
        OR A
        JP NZ,SRTERROR
        XOR A                      ; Return the output port as a scalar token.
        LD HL,SRTPOUT
        LD A,8
        PUSH IX
        RET
SRTPORTE:
        LD A,(SRTARGC)
        OR A
        JP NZ,SRTERROR
        XOR A                      ; Return the error port as a scalar token.
        LD HL,SRTPERR
        LD A,8
        PUSH IX
        RET

; Read one input port argument, or use the permanent current input port.
SRTINSET:
        LD A,(SRTARGC)
        OR A
        JR NZ,SRTINEXP             ; An argument selects a specific input port.
        XOR A
        LD (SRTINSEL),A             ; The compatibility form uses console input.
        RET
SRTINEXP:
        CP 1
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        CALL SRTVPORT
        JP C,SRTERROR
        LD (SRTVAL),HL
        LD DE,SRTINPT
        OR A
        SBC HL,DE
        JR Z,SRTINCON               ; The standard input port uses the console hook.
        LD HL,(SRTVAL)
        LD DE,SRTFIPT
        OR A
        SBC HL,DE
        JP NZ,SRTERROR              ; Output and error ports cannot be read.
        LD A,(SRTFIACT)
        OR A
        JP Z,SRTERROR               ; A closed file token cannot be read.
        LD A,1
        LD (SRTINSEL),A             ; Select the native file adapter.
        XOR A
        LD (SRTARGC),A
        RET
SRTINCON:
        XOR A
        LD (SRTINSEL),A             ; Select the direct console adapter.
        XOR A                      ; Normalize the explicit form to no arguments.
        LD (SRTARGC),A
        RET

; Select output or error for a one-value operation.  The value remains in the
; first packet record; an optional second record carries the port token.
SRTOUT1:
        LD A,(SRTARGC)
        CP 1
        JR Z,SRTO1DEF
        CP 2
        JP NZ,SRTERROR
        LD HL,SRTARGPK+4
        CALL SRTPVAL
        CALL SRTVPORT
        JP C,SRTERROR
        LD (SRTVAL),HL             ; Keep the selected token across comparisons.
        LD DE,SRTPOUT
        OR A
        SBC HL,DE
        JR Z,SRTO1CON
        LD HL,(SRTVAL)
        LD DE,SRTPERR
        OR A
        SBC HL,DE
        JR Z,SRTO1CON
        LD HL,(SRTVAL)
        LD DE,SRTFOPT
        OR A
        SBC HL,DE
        JP NZ,SRTERROR
        LD A,(SRTFOACT)
        OR A
        JP Z,SRTERROR              ; A closed file token cannot be written.
        LD A,1
        LD (SRTOUTS),A
        LD A,1                     ; Hide the optional port from the operation.
        LD (SRTARGC),A
        RET
SRTO1CON:
        XOR A
        LD (SRTOUTS),A           ; Standard output and error share the byte hook.
        LD A,1
        LD (SRTARGC),A
        RET
SRTO1DEF:
        XOR A
        LD (SRTOUTS),A
        LD HL,SRTPOUT               ; Compatibility output uses current output.
        RET

; Select output or error for a zero-value operation such as newline.
SRTOUT0:
        LD A,(SRTARGC)
        OR A
        JR Z,SRTO0DEF
        CP 1
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        CALL SRTVPORT
        JP C,SRTERROR
        LD (SRTVAL),HL
        LD DE,SRTPOUT
        OR A
        SBC HL,DE
        JR Z,SRTO0CON
        LD HL,(SRTVAL)
        LD DE,SRTPERR
        OR A
        SBC HL,DE
        JR Z,SRTO0CON
        LD HL,(SRTVAL)
        LD DE,SRTFOPT
        OR A
        SBC HL,DE
        JP NZ,SRTERROR
        LD A,(SRTFOACT)
        OR A
        JP Z,SRTERROR
        LD A,1
        LD (SRTOUTS),A
        XOR A                      ; Remove the optional port packet record.
        LD (SRTARGC),A
        RET
SRTO0CON:
        XOR A
        LD (SRTOUTS),A
        XOR A                      ; Remove the optional port packet record.
        LD (SRTARGC),A
        RET
SRTO0DEF:
        XOR A
        LD (SRTOUTS),A
        LD HL,SRTPOUT
        RET

; The three predicates validate without contacting CP/M.
SRTPORTQ:
        CALL SRTONE
        CALL SRTVPORT
        JP C,SRTBNO
        JP SRTBYES
SRTINPQ:
        CALL SRTONE
        CALL SRTVPORT
        JP C,SRTBNO
        LD (SRTVAL),HL
        LD DE,SRTINPT
        OR A
        SBC HL,DE
        JP Z,SRTBYES
        LD HL,(SRTVAL)
        LD DE,SRTFIPT
        OR A
        SBC HL,DE
        JP Z,SRTBYES
        JP SRTBNO
SRTOUTPQ:
        CALL SRTONE
        CALL SRTVPORT
        JP C,SRTBNO
        LD A,H
        CP 0F0H
        JP NZ,SRTBNO
        LD A,L
        CP 9
        JP C,SRTBNO
        CP 0DH
        JP NC,SRTBNO
        JP SRTBYES

; Standard records are owned by the runtime and cannot be closed. File records
; call the matching CP/M adapter and then become unavailable.
SRTCLOSP:
        LD A,(SRTARGC)
        CP 1
        JP NZ,SRTERROR
        CALL SRTONE
        CALL SRTVPORT
        JP C,SRTERROR
        LD (SRTVAL),HL
        LD DE,SRTFIPT
        OR A
        SBC HL,DE
        JR Z,SRTCLWIN
        LD HL,(SRTVAL)
        LD DE,SRTFOPT
        OR A
        SBC HL,DE
        JP NZ,SRTERROR
SRTCLWOU:
        CALL SRTFCLW
        JP C,SRTERROR
        JP SRTUNSP
SRTCLWIN:
        CALL SRTFCLR
        JP C,SRTERROR
        JP SRTUNSP

; Dispatch the port primitive range.  Values 46 through 53 are the existing
; port kinds; file open kinds 55 through 58 are dispatched separately below.
SRTPORTS:
        LD A,(SRTPID)
        CP 46
        JP Z,SRTPORTI
        CP 47
        JP Z,SRTPORTO
        CP 48
        JP Z,SRTPORTE
        CP 49
        JP Z,SRTPORTQ
        CP 50
        JP Z,SRTINPQ
        CP 51
        JP Z,SRTOUTPQ
        CP 52
        JP Z,SRTCLOSP
        CP 53
        JP Z,SRTDRRD
        JP SRTERROR

; Return one logical character from the selected input port.  The shared
; state consumes a datum-reader lookahead before asking the provider for data.
; State zero is empty, one is a pending byte and two is sticky EOF.
SRTINNXT:
        LD A,(SRTINST)            ; Select the shared pending-input state.
        OR A
        JR Z,SRTINPOL               ; Empty state obtains one provider byte.
        CP 1
        JR Z,SRTINPND               ; A pending byte belongs to this read.
        XOR A                         ; Sticky EOF uses the canonical scalar tag.
        LD HL,0FE03H                  ; Return the shared EOF value.
        RET
SRTINPND:
        XOR A                         ; The pending byte is consumed exactly once.
        LD (SRTINST),A             ; Reopen the state for the next provider read.
        LD A,(SRTINPBY)             ; Recover the logical byte retained by peek.
        LD L,A                        ; Place the character byte in the payload low byte.
        LD H,0FFH                     ; Characters use the reserved FFxx range.
        XOR A                         ; Characters use the scalar logical tag.
        RET
SRTINPOL:
        LD A,(SRTINSEL)
        OR A
        JR Z,SRTINC2
        CALL SRTFREAD                 ; The selected file adapter supplies one byte.
        JR C,SRTFEND                 ; Distinguish EOF from a provider failure.
        LD B,A
        LD A,(SRTFIMOD)
        OR A
        JR NZ,SRTINBIN                ; Binary files preserve CR, LF and Control-Z.
        JR SRTCRNXT                   ; Text files use the normal CR/LF policy.
SRTINC2:
        CALL SRTIN                    ; BDOS function one supplies the next raw byte.
        LD B,A                        ; Keep it while checking the pending CR state.
        LD A,(SRTINCR)
        OR A
        JR Z,SRTCRNXT                 ; No earlier CR needs an LF decision.
        XOR A                         ; A non-LF byte is returned on this read.
        LD (SRTINCR),A                ; Clear the pending physical line ending.
        LD A,B                        ; Recover the byte returned by the provider.
        CP 10
        JR Z,SRTINPOL                ; Consume the LF paired with a returned CR.
        JP SRTCRNXT                   ; A second CR starts another logical newline.
SRTCRNXT:
        LD A,B                        ; Recover the unclassified provider byte.
        CP 13
        JR NZ,SRTINRAW            ; Ordinary bytes become logical characters.
        LD A,1                        ; Return CR as one logical newline.
        LD (SRTINCR),A                ; Consume a following physical LF on demand.
        LD A,10                       ; Continue with the logical newline byte.
SRTINRAW:
        CP 26
        JR NZ,SRTINCHR               ; Control-Z marks the direct text EOF.
        LD A,2                        ; Keep EOF sticky across later reads and peeks.
        LD (SRTINST),A
        XOR A                         ; EOF uses the canonical scalar tag.
        LD HL,0FE03H                  ; Return the shared EOF value.
        RET
SRTINCHR:
        LD L,A                        ; Place the logical byte in the payload low byte.
        LD H,0FFH                     ; Characters use the reserved FFxx range.
        XOR A                         ; Characters use the scalar logical tag.
        RET

SRTFEND:
        LD A,(CTREERR)
        OR A
        JP NZ,SRTERROR                ; A BDOS read failure is not a clean EOF.
        LD A,2
        LD (SRTINST),A
        XOR A
        LD HL,0FE03H                  ; Physical file EOF becomes the EOF object.
        RET
SRTINBIN:
        LD A,B
        JP SRTINCHR

SRTINST:  DB 0                     ; Empty, pending byte or sticky EOF.
SRTINPBY:  DB 0                     ; Logical byte retained by datum lookahead.
SRTINSEL:  DB 0                     ; Zero selects console input; one selects a file.
SRTOUTS: DB 0                     ; Zero selects console output; one selects a file.
