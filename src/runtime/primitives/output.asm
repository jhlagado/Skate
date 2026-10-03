; Primitive write, display, newline and tail helpers.
; Entry points: PKT_EMIT, PKT_SHOW, PKT_CRLF and PRIM_TCO.
; Included in runtime order by ../primitives.asm.

; write and display return UNSPECIFIED after printing their one argument.
PKT_EMIT:
        LD A,1
        LD (SRTWMODE),A            ; write uses readable character syntax.
        CALL SRTOUT1
        CALL PKT_ONE
        CALL SRTWRVAL
        JP PKT_VOID
PKT_SHOW:
        XOR A                      ; display prints strings and characters raw,
        LD (SRTWMODE),A            ; including those nested inside compound values.
        CALL SRTOUT1               ; Select the optional output port.
        CALL PKT_ONE               ; Load the one value to display.
        CALL SRTWRVAL              ; Share the writer with display formatting.
        JP PKT_VOID

; newline accepts no arguments and returns UNSPECIFIED.
PKT_CRLF:
        CALL SRTOUT0
        LD A,13
        CALL SRTCH
        LD A,10
        CALL SRTCH
PKT_VOID:
        XOR A
        LD HL,0FE04H
        PUSH IX
        RET

; Read a packet record at HL and return its tag in A and payload in HL.
PKT_VAL:
        LD E,(HL)                  ; Read payload low.
        INC HL
        LD D,(HL)                  ; Read payload high.
        INC HL
        INC HL                     ; Skip the extension byte.
        LD A,(HL)
        AND 0FH                    ; The logical value tag.
        EX DE,HL                   ; Return the payload while discarding the cursor.
        RET

; A primitive tail call removes the current epilogue, then returns through it
; after the checked operation has consumed the packet values.
PRIM_TCO:
        CALL INV_KIND              ; Validate and classify the reserved payload.
        LD A,(SRTPID)              ; Apply keeps the current frame for dynamic transfer.
        CP 45
        JR Z,.APPLY
        POP IX                     ; The current frame's epilogue is now the return.
        JP PRIM_RUN                ; Evaluate with the reused procedure frame.
.APPLY:
        LD A,1
        LD (APPLY_TL),A            ; APPLY will finish through INV_TLGO.
        JP APPLY                   ; Build the packet without popping the frame.
