; Vector scratch and saved cursors.
VEC_LEN: DB 0                      ; Element count for the active vector.
VEC_REQ:  DB 0                     ; Requested count preserved across allocation GC.
VEC_POS: DB 0                      ; Checked byte index for vector-ref/set!.
VEC_TAG: DB 0                      ; Fill or replacement value tag.
VEC_LEFT: DB 0                     ; Remaining elements in an initialisation/trace.
VEC_OBJ:  DW 0                     ; Active vector allocation start.
VEC_VAL: DW 0                      ; Fill or replacement value payload.
VEC_PTR:  DW 0                     ; Current vector element cursor.
VEC_PKTP:  DW 0                    ; Current constructor packet cursor.
VEC_CELL: DW 0                     ; Selected element address.
