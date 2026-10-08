; The do loop, compiled as the named let it abbreviates:
;
;   (do ((var init step) ...) (test res ...) body ...)
;   = (let <loop> ((var init) ...)
;       (if test (begin res ...) (begin body ... (<loop> step ...))))
;
; A variable without a step keeps its value, and an empty result list gives
; the unspecified value, written (if #f #f).  <loop> is spelt with a space so
; no source name can refer to it.
;
; The rest of the form is captured as replay events, the rewritten events are
; appended after it, and the replay of the rewritten events is compiled by
; LET_FORM.  When the replay runs out, REC_NEXT returns to the enclosing
; stream and releases both event ranges.  The rewrite is at most 52 bytes,
; plus 4 for each variable without a step, longer than the capture, so
; checking that space once, and again for each such variable, covers every
; append.

DO_FORM:
        LD A,(ST_PLAY)             ; A body scan may have replayed just the
        OR A                       ; (do head; leave that finished replay first
        JR Z,.FRAME                ; so the frames stay nested.
        LD A,(ST_BACK)
        OR A
        JR Z,.FRAME
        LD HL,(ST_GETP)
        LD DE,(ST_EVEND)
        OR A
        SBC HL,DE
        JR NZ,.FRAME
        CALL REC_EXIT
        LD A,(ST_PLAY)
        OR A
        JR NZ,DO_FORM
        LD (ST_BACK),A
.FRAME:
        CALL REC_OPEN              ; Save the source or enclosing replay cursor.
        RET C
        LD HL,(ST_PUTP)
        LD (DO_FROM),HL
        LD A,1                     ; The do form's own opening is consumed.
        LD (ST_NEST),A
.CAPTURE:
        CALL REC_NEXT
        JP C,.FAIL
        OR A
        JR Z,.FAIL                 ; EOF inside the form.
        CALL DEF_PUT
        JR C,.FAIL
        LD A,(ST_EVENT)
        LD HL,ST_NEST
        CP 1
        JR NZ,.SHUT
        INC (HL)
        JR .CAPTURE
.SHUT:
        CP 2
        JR NZ,.CAPTURE
        DEC (HL)
        JR NZ,.CAPTURE
        LD HL,(ST_PUTP)            ; The rewrite must fit after the capture.
        LD D,H                     ; CP 2 left carry clear.
        LD E,L
        LD BC,(DO_FROM)
        SBC HL,BC
        ADD HL,DE
        LD DE,52
        ADD HL,DE
        LD (DO_NEED),HL
        LD DE,W_REPEND
        OR A
        SBC HL,DE
        JR NC,.CAP
        LD HL,K_IF+1               ; Intern the names the rewrite uses.
        LD BC,2
        CALL .INTERN
        LD (DO_IF),HL
        LD HL,K_BEGIN+1
        LD BC,5
        CALL .INTERN
        LD (DO_BEGIN),HL
        LD HL,DO_NAME
        LD BC,7
        CALL .INTERN
        LD (DO_LOOP),HL
        LD HL,(ST_PUTP)
        LD (DO_START),HL
        LD HL,(DO_FROM)            ; <loop> ( ... the bindings.
        LD A,(HL)
        CP 1
        JR NZ,.FAIL
        CALL .ADV
        CALL .LOOPSYM
        CALL .OPEN
        XOR A
        LD (DO_VARS),A
        JR .BINDING
.CAP:
        CALL ERR_CAP
.FAIL:
        CALL REC_POP
        SCF
        RET
; Intern the spelling HL, length BC, as a symbol reference in HL.
.INTERN:
        LD IX,ST_SYMS
        CALL SYM_ID
        JR C,.LOST
        LD A,H
        OR 20H                     ; Symbol references carry subtype one.
        LD H,A                     ; OR left carry clear.
        RET
.LOST:
        POP AF                     ; Fail from DO_FORM itself.
        JR .FAIL

; Each binding becomes (var init); its step range is kept for the call.
.BINDING:
        LD A,(HL)
        CP 2
        JR Z,.BOUND
        CP 1
        JR NZ,.FAIL
        LD A,(DO_VARS)
        CP ARG_MAX                 ; Each variable is an argument of the loop.
        JR NC,.CAP
        CALL .ADV
        LD A,(HL)
        CP 5
        JR NZ,.FAIL
        LD (DO_VAR),HL
        CALL .OPEN
        CALL .EXPR                 ; var
        CALL .EXPR                 ; init
        CALL .CLOSE
        LD A,(HL)
        CP 2
        JR Z,.SAME
        LD D,H                     ; The step is [DE,BC).
        LD E,L
        CALL .SKIP
        LD A,(HL)
        CP 2
        JR NZ,.FAIL
        LD B,H
        LD C,L
        JR .KEEP
.SAME:
        PUSH HL                    ; The variable is copied again as its step.
        LD HL,(DO_NEED)
        LD DE,4
        ADD HL,DE
        LD (DO_NEED),HL
        LD DE,W_REPEND
        OR A
        SBC HL,DE
        POP HL
        JR NC,.CAP
        LD DE,(DO_VAR)             ; No step: the variable itself.
        LD B,D
        LD C,E
        INC BC
        INC BC
        INC BC
        INC BC
.KEEP:
        PUSH HL
        LD A,(DO_VARS)
        ADD A,A
        ADD A,A
        LD L,A
        LD H,0
        PUSH DE
        LD DE,W_DOSTEP
        ADD HL,DE
        POP DE
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (HL),C
        INC HL
        LD (HL),B
        LD HL,DO_VARS
        INC (HL)
        POP HL
        CALL .ADV                  ; Past the binding's close.
        JR .BINDING
; ) (if test result (begin body ... (<loop> step ...))))
.BOUND:
        CALL .ADV
        CALL .CLOSE
        CALL .OPEN
        CALL .IF
        LD A,(HL)
        CP 1
        JP NZ,.FAIL
        CALL .ADV
        CALL .EXPR                 ; test
        CALL .OPEN
        LD A,(HL)
        CP 2
        JR NZ,.RESULT
        CALL .IF                   ; (if #f #f) is the unspecified value.
        CALL .FALSE
        CALL .FALSE
        JR .TESTED
.RESULT:
        CALL .BEGIN
        CALL .UPTO
.TESTED:
        CALL .CLOSE
        CALL .ADV                  ; Past the test clause's close.
        CALL .OPEN
        CALL .BEGIN
        CALL .UPTO                 ; body ...
        CALL .OPEN
        CALL .LOOPSYM
        LD HL,W_DOSTEP
.STEP:
        LD A,(DO_VARS)
        OR A
        JR Z,.STEPPED
        DEC A
        LD (DO_VARS),A
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD C,(HL)
        INC HL
        LD B,(HL)
        INC HL
        PUSH HL
        EX DE,HL
        LD D,B
        LD E,C
        CALL .COPY
        POP HL
        JR .STEP
.STEPPED:
        LD B,4                     ; Close the call, begin, if and let.
.CLOSES:
        PUSH BC
        CALL .CLOSE
        POP BC
        DJNZ .CLOSES
        LD A,(ST_PLAY)             ; Replay the rewrite into the let compiler.
        OR A
        CALL NZ,REC_SAVE           ; Preserve an enclosing replay cursor.
        LD HL,(DO_START)
        LD (ST_GETP),HL
        LD HL,(ST_PUTP)
        LD (ST_EVEND),HL
        LD A,1
        LD (ST_BACK),A             ; REC_NEXT returns to the saved stream.
        LD (ST_PLAY),A
        JP LET_FORM

; Append events: kind A, tag B, payload DE.  HL is kept.
.OPEN:
        LD A,1
.PUNCT:
        LD B,0
        LD DE,0
.EVENT:
        LD (ST_EVENT),A
        LD A,B
        LD (ST_EVTAG),A
        LD (ST_EVVAL),DE
        XOR A
        LD (ST_EVEXT),A
        PUSH HL
        CALL REC_PUT
        POP HL
        RET
.CLOSE:
        LD A,2
        JR .PUNCT
.FALSE:
        LD A,7                     ; The scalar #f.
        JR .PUNCT
.IF:
        LD DE,(DO_IF)
        JR .SYMBOL
.BEGIN:
        LD DE,(DO_BEGIN)
        JR .SYMBOL
.LOOPSYM:
        LD DE,(DO_LOOP)
.SYMBOL:
        LD A,5
        LD B,1
        JR .EVENT

; Copy the expression at HL; return HL past it.
.EXPR:
        PUSH HL
        CALL .SKIP
        JR .FOUND

; Copy the expressions from HL up to a close; return HL at the close.
.UPTO:
        PUSH HL
.UNTIL:
        LD A,(HL)
        CP 2
        JR Z,.FOUND
        CALL .SKIP
        JR .UNTIL
.FOUND:
        EX DE,HL
        POP HL
        PUSH DE
        CALL .COPY
        POP HL
        RET

; Copy the captured events [HL,DE) to the end of the replay stream.
.COPY:
        PUSH HL
        EX DE,HL
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        POP HL
        LD A,B
        OR C
        RET Z
        LD DE,(ST_PUTP)
        LDIR
        LD (ST_PUTP),DE
        RET

; Return HL past the expression at HL.  DE is kept.
.SKIP:
        LD A,(HL)
        CALL .ADV
        CP 3                       ; A quote prefix covers the next expression.
        JR Z,.SKIP
        CP 1
        RET NZ                     ; Every other event is one expression.
        LD B,1
.NESTED:
        LD A,(HL)
        CALL .ADV
        CP 1
        JR NZ,.NOT_OPEN
        INC B
        JR .NESTED
.NOT_OPEN:
        CP 2
        JR NZ,.NESTED
        DJNZ .NESTED
        RET

; Advance HL over one four-byte event.
.ADV:
        INC HL
        INC HL
        INC HL
        INC HL
        RET

DO_NAME:  DB "do loop"
DO_FROM:  DW 0                     ; The captured form's events.
DO_START: DW 0                     ; The rewritten events.
DO_VAR:   DW 0                     ; The current binding's variable event.
DO_NEED:  DW 0                     ; Where the rewrite will end.
DO_VARS:  DB 0                     ; Bindings, and steps still to emit.
DO_IF:    DW 0                     ; Symbol references used by the rewrite.
DO_BEGIN: DW 0
DO_LOOP:  DW 0
