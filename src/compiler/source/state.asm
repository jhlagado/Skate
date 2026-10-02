; CP/M source stream state and private buffers.
; Data labels are shared by the source modules.
CSMAXP   EQU 32               ; Root plus 31 included parts.
CSMAXDEP EQU 8                ; Files simultaneously open on the include path.
CSERROR: DB 0                 ; 0 ok, 1 open, 2 read, 3 close, 5 include error.
CSDONE:  DB 0                 ; Nonzero once the stream is terminal.
CSPARTNO: DB 0                ; Current zero-based source-table ordinal.
CSPEND:  DB 0                 ; First real byte has not reset this part yet.
CSOPENF: DB 0                 ; CSFCB is open and must be closed.
CSSEP:   DB 0                 ; One LF separator is waiting for the reader.
CSRIDX:  DB 128               ; Next byte in CSBUFFER; 128 requests a record.
CSPEOF:  DB 0                 ; The open part has reached EOF or Ctrl-Z.
CSCOUNT: DB 0                 ; Source-table entries discovered so far.
CSOUT:   DB 0                 ; Order-list cursor (append, then stream).
CSDEPTH: DB 0                 ; Parts on the include path during the scan.
CSHEAD:  DW 0                 ; Header bytes of the open part still to blank.
CILAST:  DB 0                 ; Last emitted byte, for clean part boundaries.
CIHEADS: DB "include"         ; Native include parser's fixed directive spelling.
CIPOS:   DW 0                 ; Physical scan position in the open part.
CIEND:   DW 0                 ; Position just after the part's last include form.
CIPLEN:  DB 0                 ; Length of the current quoted filename.
CIPDOT:  DB 0                 ; Extension separator has been seen.
CIBASE:  DB 0                 ; Base-name character count.
CIEXT:   DB 0                 ; Extension character count.
CIARG:   DB 0                 ; Current include form has at least one name.
CITGT:   DW 0                 ; Destination prefix while a name is assembled.
CSFCB:   DS 36
CSPART:  DS 12                ; Quoted filename being normalised.
CSSEEN:  DS 12*CSMAXP+12      ; FCB prefixes; the extra slot holds a candidate.
CSHEADT: DS 2*CSMAXP          ; Header length per part; FFFFH while on the path.
CSORDER: DS CSMAXP            ; Parts in dependency order; the root is last.
CSBUFFER: DS 128

CSWEND:
