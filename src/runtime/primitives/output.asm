; Primitive write, display, newline and tail helpers.
; Entry points: SRTWRITE, SRTDSPP, SRTNWL and SRTTPRIM.
; Included in runtime order by ../primitives.asm.

; write and display return UNSPECIFIED after printing their one argument.
SRTWRITE:
        LD A,1
        LD (SRTWMODE),A            ; write uses readable character syntax.
        CALL SRTOUT1
        CALL SRTONE
        CALL SRTWRVAL
        JP SRTUNSP
SRTDSPP:
        XOR A                      ; display prints strings and characters raw,
        LD (SRTWMODE),A            ; including those nested inside compound values.
        CALL SRTOUT1               ; Select the optional output port.
        CALL SRTONE                ; Load the one value to display.
        CALL SRTWRVAL              ; Share the writer with display formatting.
        JP SRTUNSP

; newline accepts no arguments and returns UNSPECIFIED.
SRTNWL:
        CALL SRTOUT0
        LD A,13
        CALL SRTCH
        LD A,10
        CALL SRTCH
SRTUNSP:
        XOR A
        LD HL,0FE04H
        PUSH IX
        RET

; Read a packet record at HL and return its tag in A and payload in HL.
SRTPVAL:
        LD E,(HL)                  ; Read payload low.
        INC HL
        LD D,(HL)                  ; Read payload high.
        INC HL
        LD A,(HL)                  ; Read the logical value tag.
        EX DE,HL                   ; Return the payload while discarding the cursor.
        RET

; A primitive tail call removes the current epilogue, then returns through it
; after the checked operation has consumed the packet values.
SRTTPRIM:
        CALL SRTIVAL               ; Validate and classify the reserved payload.
        LD A,(SRTPID)              ; Apply keeps the current frame for dynamic transfer.
        CP 45
        JR Z,SRTAPTAL
        POP IX                     ; The current frame's epilogue is now the return.
        JP SRTPRIM                 ; Evaluate with the reused procedure frame.
SRTAPTAL:
        LD A,1
        LD (SRTAPMOD),A            ; SRTAPPLY will finish through SRTTARG.
        JP SRTAPPLY                ; Build the packet without popping the frame.
