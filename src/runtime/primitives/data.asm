; Primitive pair, list and output dispatch.
; Entry point: SRTDAT.
; Included in runtime order by ../primitives.asm.

; Dispatch pair, list and console output primitives.
SRTDAT:
        LD A,(SRTPID)
        CP 4
        JP Z,SRTPCONS
        CP 5
        JP Z,SRTPCAR
        CP 6
        JP Z,SRTPCDR
        CP 7
        JP Z,SRTPPAR
        CP 8
        JP Z,SRTNPRED
        CP 9
        JP Z,SRTLIST
        CP 10
        JP Z,SRTPEQ
        CP 11
        JP Z,SRTWRITE
        CP 12
        JP Z,SRTDSPP
        CP 13
        JP Z,SRTNWL
        JP SRTERROR
