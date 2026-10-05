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
; stream and releases both event ranges.

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
        JP Z,.FAIL                 ; EOF inside the form.
        CALL DEF_PUT
        JP C,.FAIL
        LD A,(ST_EVENT)
        CP 1
        JP NZ,.CLOSE
        LD HL,ST_NEST
        INC (HL)
        JP .CAPTURE
.CLOSE:
        CP 2
        JP NZ,.CAPTURE
        LD HL,ST_NEST
        DEC (HL)
        JP NZ,.CAPTURE
; Intern the names the rewritten form uses.
        LD HL,K_IF+1
        LD BC,2
        CALL .INTERN
        JP C,.FAIL
        LD (DO_IF),HL
        LD HL,K_BEGIN+1
        LD BC,5
        CALL .INTERN
        JP C,.FAIL
        LD (DO_BEGIN),HL
        LD HL,DO_NAME
        LD BC,7
        CALL .INTERN
        JP C,.FAIL
        LD (DO_LOOP),HL
        LD HL,(ST_PUTP)
        LD (DO_START),HL           ; The rewritten events start here.
; The binding list: <loop> ( (var init) ... ).
        LD HL,(DO_FROM)
        LD A,(HL)
        CP 1
        JP NZ,.FAIL
        INC HL
        INC HL
        INC HL
        INC HL
        LD (DO_P),HL
        CALL .LOOPSYM
        JP C,.FAIL
        CALL .OPEN
        JP C,.FAIL
        XOR A
        LD (DO_VARS),A
.BINDING:
        LD HL,(DO_P)
        LD A,(HL)
        CP 2
        JP Z,.BOUND
        CP 1
        JP NZ,.FAIL
        LD A,(DO_VARS)             ; A named let takes at most a few formals.
        CP 8
        JP NC,ERR_CAP
        INC HL
        INC HL
        INC HL
        INC HL
        LD A,(HL)                  ; The variable.
        CP 5
        JP NZ,.FAIL
        LD (DO_VAR),HL
        CALL .OPEN
        JP C,.FAIL
        LD HL,(DO_VAR)
        LD DE,4
        PUSH HL
        ADD HL,DE
        EX DE,HL
        POP HL
        CALL .COPY                 ; var
        JP C,.FAIL
        LD HL,(DO_VAR)
        LD DE,4
        ADD HL,DE
        PUSH HL
        CALL .SKIP                 ; init
        EX DE,HL
        POP HL
        PUSH DE
        CALL .COPY
        POP HL
        JP C,.FAIL
        LD A,(HL)                  ; An optional step, then the close.
        CP 2
        JP Z,.NO_STEP
        PUSH HL
        CALL .SKIP
        EX DE,HL
        POP HL
        LD A,(DE)
        CP 2
        JP NZ,.FAIL
        JP .KEEP
.NO_STEP:
        LD HL,(DO_VAR)             ; The step is the variable itself.
        LD DE,4
        PUSH HL
        ADD HL,DE
        EX DE,HL
        POP HL
.KEEP:
        PUSH DE                    ; Record the step range [HL,DE).
        PUSH HL
        LD A,(DO_VARS)
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,DO_STEPS
        ADD HL,DE
        POP DE
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        POP DE
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,DO_VARS
        INC (HL)
        CALL .CLOSE_EV             ; End this binding.
        JP C,.FAIL
        LD HL,(DO_VAR)             ; Move past the source binding.
        LD DE,4
        ADD HL,DE
        CALL .SKIP                 ; init
        LD A,(HL)
        CP 2
        JP Z,.PAST
        CALL .SKIP                 ; step
.PAST:
        INC HL                     ; the binding's close
        INC HL
        INC HL
        INC HL
        LD (DO_P),HL
        JP .BINDING
.BOUND:
        INC HL
        INC HL
        INC HL
        INC HL
        LD (DO_P),HL
        CALL .CLOSE_EV
        JP C,.FAIL
; The body: ( if test result (begin body ... (<loop> step ...)) ).
        CALL .OPEN
        JP C,.FAIL
        LD HL,(DO_IF)
        CALL .SYMBOL
        JP C,.FAIL
        LD HL,(DO_P)               ; The test clause.
        LD A,(HL)
        CP 1
        JP NZ,.FAIL
        INC HL
        INC HL
        INC HL
        INC HL
        PUSH HL
        CALL .SKIP                 ; test
        EX DE,HL
        POP HL
        PUSH DE
        CALL .COPY
        POP HL
        JP C,.FAIL
        LD A,(HL)
        CP 2
        JP NZ,.RESULTS
        PUSH HL                    ; No results: (if #f #f).
        CALL .OPEN
        JP C,.FAIL_POP
        LD HL,(DO_IF)
        CALL .SYMBOL
        JP C,.FAIL_POP
        CALL .FALSE
        JP C,.FAIL_POP
        CALL .FALSE
        JP C,.FAIL_POP
        CALL .CLOSE_EV
        JP C,.FAIL_POP
        POP HL
        JP .AFTER
.FAIL_POP:
        POP HL
        JP .FAIL
.RESULTS:
        PUSH HL                    ; (begin res ...).
        CALL .OPEN
        JP C,.FAIL_POP
        LD HL,(DO_BEGIN)
        CALL .SYMBOL
        JP C,.FAIL_POP
        POP HL
        PUSH HL
.RES_END:
        LD A,(HL)
        CP 2
        JP Z,.RES_COPY
        CALL .SKIP
        JP .RES_END
.RES_COPY:
        EX DE,HL
        POP HL
        PUSH DE
        CALL .COPY
        POP HL
        JP C,.FAIL
        PUSH HL
        CALL .CLOSE_EV
        POP HL
        JP C,.FAIL
.AFTER:
        INC HL                     ; Past the test clause's close.
        INC HL
        INC HL
        INC HL
        PUSH HL
        CALL .OPEN                 ; (begin body ...
        JP C,.FAIL_POP
        LD HL,(DO_BEGIN)
        CALL .SYMBOL
        JP C,.FAIL_POP
        POP HL
        PUSH HL
.BODY_END:
        LD A,(HL)
        CP 2
        JP Z,.BODY_CPY
        CALL .SKIP
        JP .BODY_END
.BODY_CPY:
        EX DE,HL
        POP HL
        CALL .COPY
        JP C,.FAIL
        CALL .OPEN                 ; (<loop> step ...)
        JP C,.FAIL
        CALL .LOOPSYM
        JP C,.FAIL
        LD HL,DO_STEPS
        LD (DO_P),HL
.STEP:
        LD A,(DO_VARS)
        OR A
        JP Z,.STEPPED
        DEC A
        LD (DO_VARS),A
        LD HL,(DO_P)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        PUSH DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (DO_P),HL
        POP HL
        CALL .COPY
        JP C,.FAIL
        JP .STEP
.STEPPED:
        LD B,4                     ; Close the call, begin, if and let.
.CLOSES:
        PUSH BC
        CALL .CLOSE_EV
        POP BC
        JP C,.FAIL
        DJNZ .CLOSES
; Replay the rewritten events into the let compiler.
        LD A,(ST_PLAY)
        OR A
        JP Z,.REPLAY
        CALL REC_SAVE              ; Preserve the enclosing replay cursor.
.REPLAY:
        LD HL,(DO_START)
        LD (ST_GETP),HL
        LD HL,(ST_PUTP)
        LD (ST_EVEND),HL
        LD A,1
        LD (ST_BACK),A             ; REC_NEXT returns to the saved stream.
        LD (ST_PLAY),A
        JP LET_FORM
.FAIL:
        CALL REC_POP
        SCF
        RET

; Intern the spelling HL, length BC, as a symbol reference in HL.
.INTERN:
        LD IX,ST_SYMS
        CALL SYM_ID
        RET C
        LD A,H
        OR 20H                     ; Symbol references carry subtype one.
        LD H,A
        OR A
        RET

; Append one event: kind A, tag B, payload HL.
.EVENT:
        LD (ST_EVENT),A
        LD A,B
        LD (ST_EVTAG),A
        LD (ST_EVVAL),HL
        XOR A
        LD (ST_EVEXT),A
        JP REC_PUT
.OPEN:
        LD A,1
        JR .PUNCT
.CLOSE_EV:
        LD A,2
.PUNCT:
        LD B,0
        LD HL,0
        JR .EVENT
.LOOPSYM:
        LD HL,(DO_LOOP)
.SYMBOL:
        LD A,5
        LD B,1
        JR .EVENT
.FALSE:
        LD A,7                     ; The scalar #f.
        LD B,0
        LD HL,0
        JR .EVENT

; Copy the captured events [HL,DE) to the end of the replay stream.
.COPY:
        PUSH HL
        EX DE,HL
        OR A
        SBC HL,DE                  ; The byte count.
        LD B,H
        LD C,L
        LD HL,(ST_PUTP)
        ADD HL,BC
        LD DE,W_REPEND
        OR A
        SBC HL,DE
        POP HL
        JP NC,ERR_CAP
        LD A,B
        OR C
        RET Z
        LD DE,(ST_PUTP)
        LDIR
        LD (ST_PUTP),DE
        OR A
        RET

; Return HL past the expression whose first event is at HL.
.SKIP:
        LD A,(HL)
        LD DE,4
        ADD HL,DE
        CP 3                       ; A quote prefix covers the next expression.
        JR Z,.SKIP
        CP 1
        RET NZ                     ; Every other event is one expression.
        LD B,1
.NESTED:
        LD A,(HL)
        ADD HL,DE
        CP 1
        JR NZ,.NOT_OPEN
        INC B
        JR .NESTED
.NOT_OPEN:
        CP 2
        JR NZ,.NESTED
        DJNZ .NESTED
        RET

DO_NAME:  DB "do loop"
DO_FROM:  DW 0                     ; The captured form's events.
DO_START: DW 0                     ; The rewritten events.
DO_P:     DW 0                     ; A cursor in the captured events.
DO_VAR:   DW 0                     ; The current binding's variable event.
DO_VARS:  DB 0                     ; Bindings, and steps still to emit.
DO_IF:    DW 0                     ; Symbol references used by the rewrite.
DO_BEGIN: DW 0
DO_LOOP:  DW 0
DO_STEPS: DS 32                    ; Each binding's step range [start,end).
