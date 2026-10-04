; Runtime literals, quoted-data state and writer scratch.
; Data labels are shared by the preceding runtime modules.
; Included in runtime order by ../data.asm.

WR_FALSE:    DB "#f$"
WR_TRUE:    DB "#t$"
WR_EMPTY: DB "()$"
WR_EOF:   DB "#<eof>$"
WR_VOID:  DB "#<unspecified>$"
WR_HEX:    DB "0123456789abcdef"

QT_SP:   DW RT_QTLO
QT_NEXT:  DW 0
QT_CAR:  DW 0
QT_CDR:  DW 0
QT_ACC: DW 0
QT_PAIR: DW 0
QT_CTAG: DB 0
QT_DTAG: DB 0
QT_FLAGS:  DB 0                 ; Packed pair flags retained while tracing or printing.
.CAR_TAG:  DB 0                 ; Temporary packed CAR tag during pair construction.
QT_ATAG: DB 0
QT_CEXT: DB 0                   ; Byte 2 of the constructor's CAR input.
QT_DEXT: DB 0                   ; Byte 2 of the constructor's CDR input.
QT_AEXT: DB 0                   ; Byte 2 of the list accumulator.
QT_CNT:   DB 0
QT_TAIL: DB 0
QT_HELD: DB 0                 ; Nonzero while the list accumulator is a root.
GC_CAR: DW 0                    ; CAR payload rooted across a collecting allocation.
GC_CDR: DW 0                    ; CDR payload rooted across a collecting allocation.
GC_CTAG: DB 0                   ; CAR tag for the pending constructor root.
GC_DTAG: DB 0                   ; CDR tag for the pending constructor root.
GC_HOLD:  DB 0                  ; Nonzero while constructor roots are active.
BND_CELL: DW 0                  ; Binding pointer being validated or traced.
BND_FLAG:  DB 0                 ; Binding flags retained across value decoding.
ROOT_PTR: DW 0                  ; Exact-root cursor shared by range walkers.
ROOT_END: DW 0                  ; Exclusive end for an exact-root range.
GC_VAL: DW 0                    ; Payload address of the current root record.
GC_TAG: DB 0                    ; Tag of the current exact-root record.
GC_ENVP:  DW 0                  ; Environment-map cursor during root tracing.
GC_LEFT:  DB 0                  ; Remaining environment entries.
CL_OBJ: DW 0                    ; Closure object being validated.
CL_DESC: DW 0                   ; Descriptor pointer read from a closure header.
CL_COUNT:   DB 0                ; Closure slot count from its descriptor.
CL_MASKP:  DW 0                 ; Capture-mask cursor during closure tracing.
CL_MASK:  DB 0                  ; Current capture-mask byte.
CL_SLOT: DB 0                   ; Slot index represented by the mask cursor.
CL_FULL:  DB 0                  ; Nonzero reports a closure worklist overflow.
CL_TOP: DW 0                    ; High-water cursor for upward closure allocation.
CL_SCANP: DW 0                  ; Address-unit cursor for closure scans.
CL_FREE:  DS 130                 ; Heads for rounded four-byte closure classes.
; The page tables live in the fixed band C400H..C780H beside the operator
; side stack, outside the program image, so they cost no heap.  Startup
; clears the four 128-byte tables as one block; PS_TABLE is read only up to
; PS_COUNT entries.
CL_OWNER   EQU 0C400H            ; Class owner for each logical closure page.
                                  ; Zero is free; 41H owns a two-page run; FFH continues it.
CL_LIVE   EQU 0C480H             ; Live object count for each owned page.
CL_PHYS   EQU 0C500H             ; Physical page high byte for each owner entry.
BND_PHYS    EQU 0C580H           ; Physical page high bytes assigned to bindings.
CL_LIMIT   EQU 0C600H            ; End of the four cleared tables.
PS_TABLE    EQU 0C600H           ; One hundred twenty-eight three-byte descriptors.
CL_CAP:  DB 64,32,21,16,12,10,9,8,7,6,5,5,4,4,4,4
            DB 3,3,3,3,3,2,2,2,2,2,2,2,2,2,2,2
            DB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
            DB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
CL_HEAD:  DW 0                  ; Active closure free-list head address.
CL_BASE:  DW 0                  ; Base of the active closure allocation.
CL_PAGE:   DB 0                  ; Closure page index being selected or rebuilt.
CL_LEFT:   DB 0                  ; Slots remaining while a slab chain is built.
CL_TODO:   DB 0                  ; Remaining slots during a page sweep.
CL_HIGH:   DB 0                  ; Physical high byte during owner lookup.
CL_PBASE:   DW 0                 ; Physical base of the active closure page.
CL_STOP:   DW 0                  ; Exclusive end of a selected page or run.
CL_CUR:   DW 0                   ; Current object while building a slab chain.
CL_NEXT:   DW 0                  ; Next object while building a slab chain.
CL_STEP:   DW 0                  ; Stride of the class currently being swept.
BND_FREE: DW 0                  ; Head of the reclaimed four-byte binding list.
BND_TOP:  DW 0                  ; End of the current binding page for reports.
BND_NEXT:  DW 0                 ; Next four-byte binding slot in the current page.
BND_END: DW 0                   ; Exclusive end of the current binding page.
BND_BASE: DW 0                  ; Physical base of the current binding page.
BND_SAVE:  DW 0                 ; Physical base saved across a binding sweep.
BND_CNT:  DB 0                  ; Number of pages assigned to bindings.
BND_IDX:  DB 0                  ; Binding page index during a sweep.
BND_HEAD: DW 0                  ; Page-local free-chain head during a sweep.
BND_TAIL: DW 0                  ; Tail of the page-local free chain.
BND_LIVE: DB 0                  ; Live binding count on the current page.
BND_PTR: DW 0                   ; Binding address during sweep.
BND_MAPP:  DW 0                 ; Binding bitmap byte during sweep.
BND_MASK:  DB 0                 ; Binding bitmap bit during sweep.
.LEFT: DW 0                     ; Binding bytes left in the sweep interval.
.MAP: DW 0                      ; Closure mark-map cursor during sweep.
.MARK: DB 0                     ; Closure mark bit during sweep.
GC_QTOP:  DW RT_GCLO
GC_OVER: DB 0                     ; Nonzero means the bounded mark queue filled.
GC_FOUND:  DB 0                   ; Nonzero means a fallback pass marked an object.
GC_SCANP:   DW 0
GC_LIMIT:   DW 0
GC_QPAIR:  DW 0
.TAG:  DB 0
.WR_PTR:   DW 0
WR_SEEN:  DB 0
WR_MODE: DB 0                     ; Zero displays contents; one writes readable syntax.

; Pair-class table and scan cursors.  Each entry is a page-aligned slab base.
PS_COUNT: DB 0                    ; Number of eight-byte pair slabs currently assigned.
PS_HEAD: DB 0                     ; One-based index of the first available slab.
PS_LIMIT: DB 0                    ; Maximum descriptor slots for the page domain.
PS_NEXT: DB 0                     ; Temporary free-record or slab-list successor.
PS_INDEX: DB 0                    ; Current descriptor index during a rebuild.
PS_LIVE:  DB 0                    ; Live-record count while rebuilding one slab.
PS_FIRST: DW 0                    ; First free record while chains are rebuilt.
PS_LAST: DW 0                     ; Last free record while chains are rebuilt.
PS_DESC:   DW 0                   ; Current slab descriptor during a rebuild.
PS_BASE:   DW 0                   ; Current slab base during allocation or tracing.
PS_RECP:  DW 0                    ; Current eight-byte record during a slab walk.
PS_PAIR:   DW 0                   ; Candidate pair address being validated or marked.
PS_SAVE:   DW 0                   ; Next slab-table entry saved during a record walk.
GC_FDESC:   DW 0                  ; Fallback scan's saved descriptor cursor.
GC_FBASE:   DW 0                  ; Fallback scan's saved slab base.
GC_FREC:  DW 0                    ; Fallback scan's saved record cursor.

; One-byte staging for a BDOS console input call that may clobber registers.
CON_BYTE:    DB 0
OUT_BYTE:  DB 0                   ; One-byte staging for a file output call.
; A returned CR sets this flag so the following physical LF is consumed.
IN_CR:   DB 0
