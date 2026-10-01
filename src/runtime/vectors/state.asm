; Vector scratch and saved cursors.
SRTVLENB: DB 0                     ; Element count for the active vector.
SRTVREQ:  DB 0                     ; Requested count preserved across allocation GC.
SRTVINDX: DB 0                     ; Checked byte index for vector-ref/set!.
SRTVFTAG: DB 0                     ; Fill or replacement value tag.
SRTVLEFT: DB 0                     ; Remaining elements in an initialisation/trace.
SRTVOBJ:  DW 0                     ; Active vector allocation start.
SRTVFILL: DW 0                     ; Fill or replacement value payload.
SRTVPTR:  DW 0                     ; Current vector element cursor.
SRTVPKT:  DW 0                     ; Current constructor packet cursor.
SRTVADR1: DW 0                     ; Selected element address.
