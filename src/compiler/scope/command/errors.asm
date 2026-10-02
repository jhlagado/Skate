; Compiler error entry points selected by scope and reader failures.
; Carry set identifies every failure; SCERRPTR selects the diagnostic text.

; Report a bounded table or nesting failure.
SCCAP:
        LD HL,SCCAPTXT
        LD (SCERRPTR),HL
        SCF                       ; Carry distinguishes capacity from syntax.
        RET                        ; No partial output is published after this return.

SCSYN:
        SCF                       ; The caller reports a compile-error diagnostic.
        RET                        ; Reader state remains terminal until the next run.
SCENDSYN:
        LD HL,SCENDT
        LD (SCERRPTR),HL
        JP SCSYN
SCOPRSYN:
        LD HL,SCOPRT
        LD (SCERRPTR),HL
        JP SCSYN
SCDEFSYN:
        LD HL,SCDEFT
        LD (SCERRPTR),HL
        JP SCSYN
SCDEFNSY:
        LD HL,SCDEFNT
        LD (SCERRPTR),HL
        JP SCSYN
SCUNSUP:
        LD HL,SCUNSTXT
        LD (SCERRPTR),HL
        SCF                       ; Binary16 and unsupported forms are explicit errors.
        RET                        ; The public command does not publish a partial file.
