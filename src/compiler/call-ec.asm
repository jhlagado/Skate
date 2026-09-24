; Compiler support for the bounded one-shot call/ec form.
;
; The target procedure is evaluated once and kept as an exact root while the
; runtime installs its dynamic escape record. The target receives one private
; escape value; the runtime does the stack restore when that value is called.

SCCALEF:
        LD A,(SCTCTX)              ; call/ec itself returns a normal expression value.
        PUSH AF                    ; Preserve the surrounding tail context.
        XOR A
        LD (SCTCTX),A              ; The target expression is never tail-position.
        CALL SCEXPR                ; Evaluate the procedure supplied to call/ec.
        JR C,SCCALEE               ; Restore the compiler context after a source error.
        POP AF
        LD (SCTCTX),A
        CALL SCPUSH                ; Root the target while the closing delimiter is read.
        RET C
        CALL SCEXPECT              ; call/ec takes exactly one target expression.
        RET C
        LD HL,SRTCECAL             ; The runtime installs and invokes the escape frame.
        JP SCCALL

SCCALEE:
        POP AF                     ; Do not leave the enclosing tail context on the stack.
        LD (SCTCTX),A
        SCF                        ; The nested target expression already reported failure.
        RET
