; CP/M source stream state and private buffers.
; Data labels are shared by the source modules.
SRC_MAX   EQU 32              ; Root plus 31 included parts.
INC_MAX EQU 8                 ; Files simultaneously open on the include path.
SRC_ERR: DB 0                 ; 0 ok, 1 open, 2 read, 3 close, 5 include error.
SRC_DONE:  DB 0               ; Nonzero once the stream is terminal.
SRC_PART: DB 0                ; Current zero-based source-table ordinal.
SRC_PEND:  DB 0               ; First real byte has not reset this part yet.
SRC_LIVE: DB 0                ; SRC_FCB is open and must be closed.
SRC_SEP:   DB 0               ; One LF separator is waiting for the reader.
SRC_IDX:  DB 128              ; Next byte in SRC_BUF; 128 requests a record.
SRC_EOF:  DB 0                ; The open part has reached EOF or Ctrl-Z.
SRC_CNT: DB 0                 ; Source-table entries discovered so far.
SRC_POS:   DB 0               ; Order-list cursor (append, then stream).
INC_NEST: DB 0                ; Parts on the include path during the scan.
SRC_HEAD:  DW 0               ; Header bytes of the open part still to blank.
SRC_LAST:  DB 0               ; Last emitted byte, for clean part boundaries.
INC_TEXT: DB "include"        ; Native include parser's fixed directive spelling.
INC_POS:   DW 0               ; Physical scan position in the open part.
INC_END:   DW 0               ; Position just after the part's last include form.
INC_LEN:  DB 0                ; Length of the current quoted filename.
INC_DOT:  DB 0                ; Extension separator has been seen.
INC_BASE:  DB 0               ; Base-name character count.
INC_EXT:   DB 0               ; Extension character count.
INC_ARG:   DB 0               ; Current include form has at least one name.
INC_DST:   DW 0               ; Destination prefix while a name is assembled.
SRC_FCB:   DS 36
INC_NAME:  DS 12              ; Quoted filename being normalised.
SRC_SEEN:  DS 12*SRC_MAX+12   ; FCB prefixes; the extra slot holds a candidate.
INC_SPAN: DS 2*SRC_MAX        ; Header length per part; FFFFH while on the path.
SRC_LIST: DS SRC_MAX          ; Parts in dependency order; the root is last.
SRC_BUF: DS 128

.WORK_END:
