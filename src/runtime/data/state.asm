; Runtime literals, quoted-data state and writer scratch.
; Data labels are shared by the preceding runtime modules.
; Included in runtime order by ../data.asm.

SRTWQF:    DB "#f$"
SRTWQT:    DB "#t$"
SRTWNILT: DB "()$"
SRTWEOF:   DB "#<eof>$"
SRTWUNST:  DB "#<unspecified>$"
SRTWHX:    DB "0123456789abcdef"

SRTQSP:   DW SRTQBASE
SRTQNXT:  DW 0
SRTQCAR:  DW 0
SRTQCDR:  DW 0
SRTQAVAL: DW 0
SRTQPAIR: DW 0
SRTQCTAG: DB 0
SRTQDTAG: DB 0
SRTQFLG:  DB 0                  ; Packed pair flags retained while tracing or printing.
SRTPTAG:  DB 0                  ; Temporary packed CAR tag during pair construction.
SRTQATAG: DB 0
SRTQNR:   DB 0
SRTQDOTR: DB 0
SRTQACTV: DB 0                ; Nonzero while the list accumulator is a root.
SRTCRCAR: DW 0                  ; CAR payload rooted across a collecting allocation.
SRTCRCDR: DW 0                  ; CDR payload rooted across a collecting allocation.
SRTCRCTA: DB 0                  ; CAR tag for the pending constructor root.
SRTCRDTA: DB 0                  ; CDR tag for the pending constructor root.
SRTCRON:  DB 0                  ; Nonzero while constructor roots are active.
SRTBADDR: DW 0                  ; Binding pointer being validated or traced.
SRTBFLG:  DB 0                  ; Binding flags retained across value decoding.
SRTROOTP: DW 0                  ; Exact-root cursor shared by range walkers.
SRTROOTE: DW 0                  ; Exclusive end for an exact-root range.
SRTROOTV: DW 0                  ; Payload address of the current root record.
SRTROOTT: DB 0                  ; Tag of the current exact-root record.
SRTENVP:  DW 0                  ; Environment-map cursor during root tracing.
SRTENVN:  DB 0                  ; Remaining environment entries.
SRTCLOBJ: DW 0                  ; Closure object being validated.
SRTCLDSC: DW 0                  ; Descriptor pointer read from a closure header.
SRTCLN:   DB 0                  ; Closure slot count from its descriptor.
SRTCLMP:  DW 0                  ; Capture-mask cursor during closure tracing.
SRTCLMV:  DB 0                  ; Current capture-mask byte.
SRTCLSLT: DB 0                  ; Slot index represented by the mask cursor.
SRTCLER:  DB 0                  ; Nonzero reports a closure worklist overflow.
SRTCLCUR: DW 0                  ; High-water cursor for upward closure allocation.
SRTCLSCN: DW 0                  ; Address-unit cursor for closure scans.
SRTCFREE:  DS 130                ; Heads for rounded four-byte closure classes.
SRTCLOWN:  DS 128                ; Class owner for each logical closure page.
                                  ; Zero is free; 41H owns a two-page run; FFH continues it.
SRTCLUSE:  DS 128                ; Live object count for each owned page.
SRTCLPBA:  DS 128                ; Physical page high byte for each owner entry.
SRTCLCAP:  DB 64,32,21,16,12,10,9,8,7,6,5,5,4,4,4,4
            DB 3,3,3,3,3,2,2,2,2,2,2,2,2,2,2,2
            DB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
            DB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
SRTCLFP:  DW 0                  ; Active closure free-list head address.
SRTCLBAS:  DW 0                 ; Base of the active closure allocation.
SRTCLPGI:   DB 0                 ; Closure page index being selected or rebuilt.
SRTCLPGN:   DB 0                 ; Slots remaining while a slab chain is built.
SRTCLPGQ:   DB 0                 ; Remaining slots during a page sweep.
SRTCLPGH:   DB 0                 ; Physical high byte during owner lookup.
SRTCLPGA:   DW 0                 ; Physical base of the active closure page.
SRTCLPGE:   DW 0                 ; Exclusive end of a selected page or run.
SRTCLPGF:   DW 0                 ; Current object while building a slab chain.
SRTCLPGL:   DW 0                 ; Next object while building a slab chain.
SRTCLSTR:   DW 0                 ; Stride of the class currently being swept.
SRTBHEAD: DW 0                  ; Head of the reclaimed four-byte binding list.
SRTBEND:  DW 0                  ; End of the current binding page for reports.
SRTBPGP:  DW 0                  ; Next four-byte binding slot in the current page.
SRTBPGED: DW 0                  ; Exclusive end of the current binding page.
SRTBPGBA: DW 0                  ; Physical base of the current binding page.
SRTBPGC:  DW 0                  ; Physical base saved across a binding sweep.
SRTBPGN:  DB 0                  ; Number of pages assigned to bindings.
SRTBPGI:  DB 0                  ; Binding page index during a sweep.
SRTBPGS:  DS 128                ; Physical page high bytes assigned to bindings.
SRTBPFRE: DW 0                  ; Page-local free-chain head during a sweep.
SRTBPLST: DW 0                  ; Tail of the page-local free chain.
SRTBPLIV: DB 0                  ; Live binding count on the current page.
SRTBSCAN: DW 0                  ; Binding address during sweep.
SRTBMAP:  DW 0                  ; Binding bitmap byte during sweep.
SRTBMSK:  DB 0                  ; Binding bitmap bit during sweep.
SRTBLEFT: DW 0                  ; Binding bytes left in the sweep interval.
SRTCLMAP: DW 0                  ; Closure mark-map cursor during sweep.
SRTCLMKV: DB 0                  ; Closure mark bit during sweep.
SRTMSTK:  DW SRTMKBS
SRTMOVER: DB 0                    ; Nonzero means the bounded mark queue filled.
SRTMNEW:  DB 0                    ; Nonzero means a fallback pass marked an object.
SRTSCP:   DW 0
SRTSCE:   DW 0
SRTMVAL:  DW 0
SRTMTAG:  DB 0
SRTWRP:   DW 0
SRTWBEG:  DB 0
SRTWMODE: DB 0                    ; Zero displays contents; one writes readable syntax.

; Pair-class table and scan cursors.  Each entry is a page-aligned slab base.
SRTPSLBN: DB 0                    ; Number of five-byte pair slabs currently assigned.
SRTPSLT:  DS 384                  ; One hundred twenty-eight three-byte descriptors.
SRTPSLHD: DB 0                    ; One-based index of the first available slab.
SRTPSLIM: DB 0                    ; Maximum descriptor slots for the page domain.
SRTPSNXT: DB 0                    ; Temporary free-record or slab-list successor.
SRTPSIDX: DB 0                    ; Current descriptor index during a rebuild.
SRTPSLV:  DB 0                    ; Live-record count while rebuilding one slab.
SRTPSFST: DW 0                    ; First free record while chains are rebuilt.
SRTPSFLK: DW 0                    ; Last free record while chains are rebuilt.
SRTPSDP:   DW 0                   ; Current slab descriptor during a rebuild.
SRTPSBA:   DW 0                   ; Current slab base during allocation or tracing.
SRTPSCAN:  DW 0                   ; Current five-byte record during a slab walk.
SRTPSAD:   DW 0                   ; Candidate pair address being validated or marked.
SRTPSST:   DW 0                   ; Next slab-table entry saved during a record walk.
SRTFSST:   DW 0                   ; Fallback scan's saved descriptor cursor.
SRTFSBA:   DW 0                   ; Fallback scan's saved slab base.
SRTFSCAN:  DW 0                   ; Fallback scan's saved record cursor.

; One-byte staging for a BDOS console input call that may clobber registers.
SRTINB:    DB 0
SRTFBYTE:  DB 0                   ; One-byte staging for a file output call.
; A returned CR sets this flag so the following physical LF is consumed.
SRTINCR:   DB 0
