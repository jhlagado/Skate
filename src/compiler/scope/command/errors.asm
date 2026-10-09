; Compiler error entry points selected by scope and reader failures.
; Carry set identifies every failure; ST_ERROR selects the diagnostic text.

; Report a bounded table or nesting failure.
ERR_CAP:
        LD HL,M_CAP
        LD (ST_ERROR),HL
        SCF                       ; Carry distinguishes capacity from syntax.
        RET                        ; No partial output is published after this return.

ERR_BAD:
        SCF                       ; The caller reports a compile-error diagnostic.
        RET                        ; Reader state remains terminal until the next run.
ERR_END:
        LD HL,M_END
        LD (ST_ERROR),HL
        JR ERR_BAD
ERR_OP:
        LD HL,M_OP
        LD (ST_ERROR),HL
        JR ERR_BAD
ERR_DEF:
        LD HL,M_DEF
        LD (ST_ERROR),HL
        JR ERR_BAD
ERR_NAME:
        LD HL,M_DEFNAM
        LD (ST_ERROR),HL
        JR ERR_BAD
ERR_TODO:
        LD HL,M_UNSUP
        LD (ST_ERROR),HL
        SCF                       ; Binary16 and unsupported forms are explicit errors.
        RET                        ; The public command does not publish a partial file.
