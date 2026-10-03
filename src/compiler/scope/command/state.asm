; Compiler state and reader-owned contexts.  Descriptor and spelling storage
; lives in the high TPA regions above; these small records remain in the image.
ST_PC:       DW 0                  ; Staged generated-code cursor.
ST_PCHI:     DB 0                  ; Top byte of the exclusive output cursor.
ST_WORD:     DW 0                  ; Temporary word for opcode emission.
ST_IMMED:     DW 0                 ; Temporary literal payload.
ST_BYTE:     DB 0                  ; Temporary boolean payload.
ST_ARITY:    DB 0                  ; Formal-slot high byte during descriptor output.
ST_FADDR:     DW 0                 ; Staged address retained by EM_FIXUP.
ST_FKIND:    DB 0                  ; Pending slot kind for EM_FIXUP.
ST_FSLOT:    DB 0                  ; Pending slot number for EM_FIXUP.
ST_SYMID:       DW 0               ; Current full interner symbol identity.
ST_SLOT:     DB 0                  ; Current local or global slot number.
ST_GSLOT:    DB 0                  ; Global slot returned by GLB_GET.
ST_GIDX:     DB 0                  ; Candidate global slot during a key scan.
ST_PRIM:    DB 0                   ; Predefined primitive kind for the current name.
ST_DSLOT:  DB 0                  ; Definition initializer's global slot.
ST_ALLOW:    DB 0                  ; Package-level permission for define.
ST_ATTOP:      DB 0                ; Saved define permission for CMD_FORM.
ST_BDEF:   DB 0                    ; Leading body-definition permission.
ST_BDSAV:    DB 0                  ; Saved permission while dispatching one form.
ST_ISDEF:    DB 0                  ; Nonzero when the current form was a definition.
ST_RMODE:   DB 0                   ; A letrec initializer may create forward slots.
ST_RINIT:   DB 0                   ; One while letrec or internal definitions initialize.
ST_RBASE:    DB 0                  ; First reusable slot owned by this recursive scope.
ST_RTOP:   DB 0                    ; One past the highest recursive slot in this scope.
ST_RPROC:    DB 0FFH               ; Procedure that owns recursive forward cells.
ST_OTOP:     DB 0                  ; Saved outer active-binding count during unwind.
ST_ONEXT:     DB 0                 ; Saved outer reusable slot cursor during unwind.
ST_KTOP:   DB 0                    ; Active-binding count before recursive retention.
ST_KSRC:   DB 0                    ; Source index while retaining a forward binding.
ST_KDST:   DB 0                    ; Destination index while compacting retained names.
ST_RPEND:   DB 0                   ; Pending-record marker for the current letrec.
ST_PLAY:      DB 0                 ; Nonzero while REC_NEXT replays a binding list.
ST_PLAYN:    DB 0                  ; Nested replay-frame depth.
ST_EVLO:   DW 0                    ; First event in the active replay frame.
ST_BACK:   DB 0                    ; Nonzero replay returns to its saved stream.
ST_PUTP:    DW 0                   ; Write cursor for retained letrec events.
ST_GETP:    DW 0                   ; Read cursor for retained letrec events.
ST_EVEND:   DW 0                   ; End cursor for the retained event stream.
ST_RCNT:   DB 0                    ; Number of predeclared letrec names.
ST_LEADS:    DB 0                  ; Leading internal definitions in the buffer.
ST_LEAD:    DB 0                   ; Current buffered form is a definition.
ST_NEST:    DB 0                   ; Structural depth while buffering a binding list.
ST_HEAD:    DB 0                   ; Nonzero while a binding name is expected.
ST_RIDX:   DB 0                    ; Reverse initializer index during deferred stores.
ST_RMARK:   DB 0                   ; Saved pending marker during deferred stores.
ST_KSLOT:   DB 0                   ; Slot number selected during recursive retention.
ST_FRAME:    DW 0                  ; Frame cursor held across recursive retention.
ST_EXPRS:    DB 0                  ; Body expression count.
ST_FORMS:    DW 0                  ; Number of complete package-level forms.
ST_GLOBS:   DW 0                   ; Number of allocated package-global slots.
ST_LTOP:   DB 0                    ; Number of active local binding records.
ST_LNEXT:    DB 0                  ; Next reusable local slot number.
ST_LMAX:   DB 0                    ; Maximum simultaneous local slot count.
ST_BINDS:  DB 0                   ; Pending binding-record stack top.
ST_LSAVE:   DB 0                   ; Saved let cursor while recursive state restores.
ST_BINDP:     DB 0                 ; Pending-record cursor during BIND_ALL.
ST_BMAX:     DB 0                  ; Pending-record limit for the current let.
ST_FIXES:     DW 0                 ; Number of recorded slot-address fixups.
ST_BRTOP:    DB 0                  ; Generic branch patch stack top.
ST_IFTOP:    DB 0                  ; Nested if patch stack top.
ST_PATCH:    DW 0                  ; Temporary staged branch patch address.
ST_DEST:    DW 0                   ; Temporary absolute branch target.
ST_FOUND:    DB 0                  ; Last matching local slot.
ST_HIT:   DB 0                     ; Nonzero after a local match.
ST_OPID:     DW 0                  ; Operator identity for generic applications.
ST_NAME:    DW 0                   ; Spelling address while classifying a primitive.
ST_NAMEN:    DB 0                  ; Spelling length used by GLB_PRIM.
ST_PROCS:   DB 0                   ; Number of fixed procedure descriptors.
ST_RTLEN:    DW 0                  ; Runtime bytes loaded, chosen by .SCAN.
ST_GBASE:   DW 0                   ; Address of the global area after the runtime.
ST_PNEST:   DB 0                   ; Number of open procedure metadata records.
ST_PROC:    DB 0FFH                ; Active procedure, or FFH at package level.
ST_DESC:    DB 0                   ; Descriptor being compiled.
ST_REST:    DB 0                   ; Nonzero when the current procedure has a rest formal.
ST_RLIST:    DB 0                  ; Local slot receiving the constructed rest list.
ST_ARGS:     DB 0                  ; Generic application argument count.
ST_TAIL:     DB 0                  ; Nonzero when the current expression is tail code.
ST_ATAIL:    DB 0                  ; Saved tail context while evaluating arguments.
ST_SKIP:     DW 0                  ; Lambda jump-over patch address.
ST_PBODY:    DW 0                  ; Procedure body staged address during setup.
ST_MSLOT:    DB 0                  ; Slot selected while setting a mask bit.
ST_MPROC:      DB 0                ; Procedure index selected for mask writes.
ST_MASKP:    DW 0                  ; Mask byte address during bit assembly.
ST_DKIND:    DB 0                  ; Mutation destination kind.
ST_CHECK:  DB 0                ; Nonzero selects the checked mutation store.
ST_CPROC:   DB 0                   ; Active procedure while capture masks are chained.
ST_CDESC:   DB 0                   ; Descriptor under construction during mask writes.
ST_OWNER:   DB 0                   ; Procedure that owns the captured local slot.
ST_CHAIN:   DB 0                   ; Remaining body frames in a capture chain.
ST_AEV:     DB 0                   ; Saved generic-argument event kind.
ST_ATAG:    DW 0                   ; Saved generic-argument scalar tag.
ST_AVAL:    DW 0                   ; Saved generic-argument payload.
ST_ROUTE:   DB 0                   ; Nonzero selects the compact global-call marker.
ST_GCALL:    DB 0                  ; Global slot carried by the compact call marker.
ST_VALUE:     DW 0                 ; Procedure/body result payload during cleanup.
ST_VTAG:     DB 0                  ; Procedure/body result tag during cleanup.
ST_ERROR:   DW 0                   ; Current compiler diagnostic string.
ST_EPART:  DB 0                  ; Source-table ordinal captured at failure.
ST_EOFF:   DW 0                    ; Part-relative byte offset fallback.
ST_ELINE:   DW 0                   ; One-based source line captured at failure.
ST_ECOL:   DW 0                    ; One-based source column captured at failure.
ST_PHASE:    DB 0                  ; Zero while reading; one during finalisation.
ST_DIGIT:  DB 0                 ; Decimal formatter has emitted a digit.
ST_BNEST:     DB 0                 ; Nested body-frame depth.
ST_BTAIL:    DB 0                  ; Incoming tail context for the current body.
ST_BMODE:    DB 0                  ; 0 shares candidates, 1 isolates, 2 admits let definitions.
ST_ALONE:    DB 0                  ; Caller requests a private candidate scope.
ST_DEFLO:    DB 0                  ; First active binding in the definition scope.
ST_LETLO:   DB 0                   ; Active-binding base saved when a let opens.
ST_EVENT:      DB 0                ; Current body-frame event kind.
ST_EVTAG:     DB 0                 ; Current body-frame scalar tag.
ST_EVVAL:     DW 0                 ; Current body-frame payload.
ST_TAILS:     DB 0                 ; Number of tail-call target words in this body.
ST_MARK:    DB 0                   ; Start of the current expression's tail records.
ST_TAILP:     DW 0                 ; Tail-call patch address during table writes.
ST_CONDS:    DB 0                  ; Number of cond end-jump patches in the table.
ST_CNEST:    DB 0                  ; Active nested cond patch-frame depth.
ST_CBASE:   DB 0                   ; First patch-table record owned by this cond.
ST_INPKG:   DB 0                   ; Nonzero selects package procedure storage.
ST_NLOK:   DB 0                    ; Nonzero permits the named-let spelling.
ST_NLID:    DW 0                   ; Named-let procedure name retained after dispatch.
ST_NLREC:    DB 0                  ; First temporary name record for named let.
ST_NLPOS:   DB 0                   ; Cursor while adding named-let formals.
ST_NLOWN:    DB 0                  ; Enclosing descriptor while a named body opens.
ST_NLNEW:    DB 0                  ; Descriptor allocated by the active named form.
ST_SYMS:     DW W_SYMTAB,320,W_SYMBUF,4800,0,0
            DB 0,0                  ; Symbol context kind and ready flag.
ST_STRS:     DW W_STRTAB,64,W_STRBUF,1024,0,0
            DB 1,0                  ; String context kind and ready flag.
