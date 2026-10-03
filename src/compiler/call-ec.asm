; Compiler support for the bounded one-shot call/ec form.
;
; The target procedure is evaluated once and kept as an exact root while the
; runtime installs its dynamic escape record. The target receives one private
; escape value; the runtime does the stack restore when that value is called.

CALL_EC:
        LD A,(ST_TAIL)             ; call/ec itself returns a normal expression value.
        PUSH AF                    ; Preserve the surrounding tail context.
        XOR A
        LD (ST_TAIL),A             ; The target expression is never tail-position.
        CALL CMD_NEXT              ; Evaluate the procedure supplied to call/ec.
        JR C,.FAIL                 ; Restore the compiler context after a source error.
        POP AF
        LD (ST_TAIL),A
        CALL EM_PUSH               ; Root the target while the closing delimiter is read.
        RET C
        CALL CMD_END               ; call/ec takes exactly one target expression.
        RET C
        LD HL,EC_CALL              ; The runtime installs and invokes the escape frame.
        JP EM_CALL

.FAIL:
        POP AF                     ; Do not leave the enclosing tail context on the stack.
        LD (ST_TAIL),A
        SCF                        ; The nested target expression already reported failure.
        RET
