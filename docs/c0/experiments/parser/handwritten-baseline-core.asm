;=============================================================================
;  Handwritten predictive C0 parser
;=============================================================================
;
;  PURPOSE
;  -------
;  Parse the bounded grammar directly with one native lookahead.  The action
;  sink is called at the grammar positions in parser-experiment.md; no syntax
;  tree or input replay is retained.
;
;  PUBLIC INTERFACE
;  ----------------
;
;  PPARSE  Parse the fixture input from start to synthesized EOF.
;
;+---------------------------------------------------------------------------+
;| CALL                                                                      |
;|   ADBASE..ADLIM and SKBASE..SKLIM already describe fixture buffers.       |
;|   SKINJ is preserved as the optional injected-sink-failure selector.      |
;|                                                                           |
;| SUCCESS                                                                   |
;|   A=0, carry clear; IX, IY, SP and the caller return PC are preserved.    |
;|                                                                           |
;| FAILURE                                                                   |
;|   A=128 syntax, 129 capacity, or 130 sink; carry set.                    |
;+---------------------------------------------------------------------------+
;
;  REGISTER AND STACK CONTRACT
;  ---------------------------
;  Recursive calls are only used for nested expressions and list forms.  The
;  sequence, argument and parameter loops are iterative, so a long flat input
;  cannot grow the native stack.  AF/BC/DE/HL are scratch; IX and IY survive.
;  Every failure returns through the caller's balanced CALL frames.
;=============================================================================

HSTART:
PPARSE:
        CALL ADRESET              ; Re-entry starts a fresh monotonic token run.
        CALL SKRESET              ; Output records from an earlier run disappear.
        CALL HPROGRAM             ; The recursive expression routines report A.
        RET C                     ; Carry and reason already identify the failure.
        XOR A                     ; A=0 and carry clear are the public success ABI.
        RET

; Parse zero or more top-level expressions, retaining EOF as lookahead.  TOP is
; recorded after each expression and therefore sees the following token index.
HPROGRAM:
HPROGLOP:
        CALL ADPEEK
        OR A
        JR Z,HPROGOK              ; Empty input and end after the last form.
        CP CLOSE
        JP Z,HSYNTAX              ; A top-level close has no matching OPEN.
        CALL HEXPR
        RET C
        LD A,3                    ; TOP action follows the just-finished expr.
        CALL HACT
        RET C
        JR HPROGLOP
HPROGOK:
        XOR A
        RET

; Select the expression production from its current token.
HEXPR:
        CALL ADPEEK
        CP ATOM
        JR Z,HATOMEX
        CP NAME
        JR Z,HNAMEEX
        CP OPEN
        JR Z,HOPENEX
        JP HSYNTAX                ; Keywords and unknown ordinals are not values.

; ATOM_ACTION and NAME_ACTION run before the value token is consumed.
HATOMEX:
        LD A,1
        CALL HACT
        RET C
        LD B,ATOM
        JP HTOKEN
HNAMEEX:
        LD A,2
        CALL HACT
        RET C
        LD B,NAME
        JP HTOKEN

; OPEN belongs to the common depth check.  Its list dispatcher observes the
; first token after the opening delimiter.
HOPENEX:
        LD B,OPEN
        CALL HTOKEN
        RET C
        JP HLIST

; List prediction is handwritten here; all three reserved list heads have a
; dedicated routine and every other head enters the generic application form.
HLIST:
        CALL ADPEEK
        CP IFTOK
        JP Z,HIF
        CP BEGIN
        JP Z,HBEGIN
        CP LAMBDA
        JP Z,HLAMBDA
        JP HAPP

; IF IF_OPEN expr IF_TEST expr IF_THEN alternative CLOSE IF_END
HIF:
        LD B,IFTOK
        CALL HTOKEN              ; Consume the reserved IF head first.
        RET C
        LD A,4
        CALL HACT
        RET C
        CALL HEXPR
        RET C
        LD A,5
        CALL HACT
        RET C
        CALL HEXPR
        RET C
        LD A,6
        CALL HACT
        RET C
        CALL ADPEEK
        CP CLOSE
        JR Z,HIFABSNT
        CALL HEXPR
        RET C
        LD A,7
        CALL HACT
        RET C
        JR HIFCLOSE
HIFABSNT:
        LD A,8
        CALL HACT
        RET C
HIFCLOSE:
        LD B,CLOSE
        CALL HTOKEN
        RET C
        LD A,9
        JP HACT

; BEGIN BEGIN_OPEN sequence CLOSE BEGIN_END.  HSEQ intentionally accepts an
; empty sequence; the argument and formal loops likewise accept their empty
; lists, while every expression sequence still requires its caller's delimiters.
HBEGIN:
        LD B,BEGIN
        CALL HTOKEN
        RET C
        LD A,10
        CALL HACT
        RET C
        CALL HSEQ
        RET C
        LD B,CLOSE
        CALL HTOKEN
        RET C
        LD A,11
        JP HACT

; LAMBDA LAMBDA_OPEN OPEN parameters CLOSE PARAMS_END expr BODY_VALUE sequence
; CLOSE LAMBDA_END.  The first body expression is explicit to reject empty
; lambda bodies; HSEQ handles any later body expressions.
HLAMBDA:
        LD B,LAMBDA
        CALL HTOKEN
        RET C
        LD A,12
        CALL HACT
        RET C
        LD B,OPEN
        CALL HTOKEN
        RET C
        CALL HPARAMS
        RET C
        LD B,CLOSE
        CALL HTOKEN
        RET C
        LD A,14
        CALL HACT
        RET C
        CALL HEXPR
        RET C
        LD A,15
        CALL HACT
        RET C
        CALL HSEQ
        RET C
        LD B,CLOSE
        CALL HTOKEN
        RET C
        LD A,16
        JP HACT

; Parameter identity is intentionally outside this grammar experiment.  The
; loop still enforces a proper NAME-only formal list without growing the stack.
HPARAMS:
        CALL ADPEEK
        CP CLOSE
        RET Z
        CP NAME
        JP NZ,HSYNTAX
        LD A,13
        CALL HACT
        RET C
        LD B,NAME
        CALL HTOKEN
        RET C
        JR HPARAMS

; A begin sequence and the later lambda body share this iterative walker.
; BODY_VALUE is supplied by the caller for each expression, including the last.
HSEQ:
        CALL ADPEEK
        CP CLOSE
        RET Z
        CALL HEXPR
        RET C
        LD A,15
        CALL HACT
        RET C
        JR HSEQ

; Generic application: APP_OPEN expr OPERATOR arguments CLOSE APP_END.
HAPP:
        LD A,17
        CALL HACT
        RET C
        CALL HEXPR
        RET C
        LD A,18
        CALL HACT
        RET C
        CALL HARGS
        RET C
        LD B,CLOSE
        CALL HTOKEN
        RET C
        LD A,20
        JP HACT

; Zero or more arguments, with ARGUMENT after every argument expression.
HARGS:
        CALL ADPEEK
        CP CLOSE
        RET Z
        CALL HEXPR
        RET C
        LD A,19
        CALL HACT
        RET C
        JR HARGS

; Every action refreshes lookahead before writing its index.  Keeping the
; ordinal on the real stack makes sink calls independent of adapter clobbers.
HACT:
        PUSH AF
        CALL ADPEEK
        POP AF
        JP SKACT

; Match one required terminal and consume it through the common bound checker.
; B is stable because both adapter routines use only AF/DE/HL.
HTOKEN:
        CALL ADPEEK
        CP B
        JP NZ,HSYNTAX
        JP ADTAKE

; All parser-generated syntax failures use the contract's one public reason.
HSYNTAX:
        LD A,128
        SCF
        RET

HCODEEND:
; The handwritten engine has no private persistent fields; its loops use the
; hardware stack and the shared adapter state only.
HGUARD: DS 4
HWORK:
HWEND:
HTAIL: DS 4
