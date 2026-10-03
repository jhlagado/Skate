; Binding initializer context.
;
; Initializers compile outside tail position and restore the enclosing
; body context before the binding form continues.

SCINIT:
        LD A,(ST_TAIL)             ; Save the enclosing body's tail position.
        PUSH AF                    ; Nested initializers need independent saved state.
        LD A,(ST_LETLO)            ; Save the active definition boundary as well.
        PUSH AF                    ; Nested forms must not change the enclosing marker.
        XOR A                      ; The store and body still follow this expression.
        LD (ST_TAIL),A             ; Emit an ordinary call for the initializer.
        CALL CMD_NEXT              ; Compile the value with the outer lexical scope.
        PUSH AF                    ; Preserve its result tag and failure carry.
        POP BC                     ; Hold the result while recovering the context.
        POP AF                     ; Recover the enclosing definition boundary.
        LD (ST_LETLO),A            ; Restore it before the outer binding continues.
        POP AF                     ; Recover the enclosing tail flag.
        LD (ST_TAIL),A             ; The let body retains its original tail position.
        PUSH BC                    ; Restore the expression's tag and flags.
        POP AF                     ; Keep syntax failures visible to the caller.
        RET                        ; HL still holds the expression result.
