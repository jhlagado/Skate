; Primitive pair, list and output dispatch.
; Entry point: PRIM_DAT.
; Included in runtime order by ../primitives.asm.

; Dispatch pair, list and console output primitives.
PRIM_DAT:
        LD A,(PRIM_ID)
        CP 4
        JP Z,PKT_CONS
        CP 5
        JP Z,PKT_CAR
        CP 6
        JP Z,PKT_CDR
        CP 7
        JP Z,PKT_PAIR
        CP 8
        JP Z,PKT_NULL
        CP 9
        JP Z,PKT_LIST
        CP 10
        JP Z,PKT_EQ
        CP 11
        JP Z,PKT_EMIT
        CP 12
        JP Z,PKT_SHOW
        CP 13
        JP Z,PKT_CRLF
        JP ERROR
