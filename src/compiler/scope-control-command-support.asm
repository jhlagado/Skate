; Report a bounded table or nesting failure.
SCCAP:
        LD HL,SCCAPTXT
        LD (SCERRPTR),HL
        SCF                       ; Carry distinguishes capacity from syntax.
        RET                        ; No partial output is published after this return.

SCSYN:
        SCF                       ; The caller reports a compile-error diagnostic.
        RET                        ; Reader state remains terminal until the next run.
SCEXERR:
        LD HL,SCEXTXT
        LD (SCERRPTR),HL
        JP SCSYN
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
SCREAD:
        SCF                       ; Reader errors are reported through SCFAIL.
        RET                        ; The reader itself retains the original code.

; Compiler state and reader-owned contexts.  Descriptor and spelling storage
; lives in the high TPA regions above; these small records remain in the image.
SCPC:       DW 0                   ; Staged generated-code cursor.
SCWTMP:     DW 0                   ; Temporary word for opcode emission.
SCVTMP:     DW 0                   ; Temporary literal payload.
SCFPTR:     DW 0                   ; Staged address retained by SCFIX.
SCPTMP:     DW 0                   ; Absolute target retained by SCPATCH.
SCFKIND:    DB 0                   ; Pending slot kind for SCFIX.
SCFSLOT:    DB 0                   ; Pending slot number for SCFIX.
SCBTMP:     DB 0                   ; Temporary boolean payload.
SCID:       DW 0                   ; Current full interner symbol identity.
SCSLOT:     DB 0                   ; Current local or global slot number.
SCGSLOT:    DB 0                   ; Global slot returned by SCGGET.
SCGIDX:     DB 0                   ; Candidate global slot during a key scan.
SCPKIND:    DB 0                   ; Predefined primitive kind for the current name.
SCDEFSL:  DB 0                   ; Definition initializer's global slot.
SCOP:       DB 0                   ; Selected binary operation 0, 1 or 2.
SCALLOW:    DB 0                   ; Package-level permission for define.
SCTOP:      DB 0                   ; Saved define permission for SCFORM.
SCBDEFIN:   DB 0                   ; Leading body-definition permission.
SCBDSAV:    DB 0                   ; Saved permission while dispatching one form.
SCISDEF:    DB 0                   ; Nonzero when the current form was a definition.
SCRECMOD:   DB 0                   ; A letrec initializer may create forward slots.
SCRECPHS:   DB 0                   ; One while letrec or internal definitions initialize.
SCRECST:    DB 0                   ; First reusable slot owned by this recursive scope.
SCRECLIM:   DB 0                   ; One past the highest recursive slot in this scope.
SCRECPR:    DB 0FFH                ; Procedure that owns recursive forward cells.
SCRECO:     DB 0                   ; Saved outer active-binding count during unwind.
SCRECN:     DB 0                   ; Saved outer reusable slot cursor during unwind.
SCRECCUR:   DB 0                   ; Active-binding count before recursive retention.
SCRECSRC:   DB 0                   ; Source index while retaining a forward binding.
SCRECDST:   DB 0                   ; Destination index while compacting retained names.
SCRECPND:   DB 0                   ; Pending-record marker for the current letrec.
SCREP:      DB 0                   ; Nonzero while SCNEXT replays a binding list.
SCRECFD:    DB 0                   ; Nested replay-frame depth.
SCRECBAS:   DW 0                   ; First event in the active replay frame.
SCRECAUT:   DB 0                   ; Nonzero replay returns to its saved stream.
SCRECWP:    DW 0                   ; Write cursor for retained letrec events.
SCRECRP:    DW 0                   ; Read cursor for retained letrec events.
SCREWEND:   DW 0                   ; End cursor for the retained event stream.
SCRECCNT:   DB 0                   ; Number of predeclared letrec names.
SCDFCNT:    DB 0                   ; Leading internal definitions in the buffer.
SCDFMOD:    DB 0                   ; Current buffered form is a definition.
SCREDEP:    DB 0                   ; Structural depth while buffering a binding list.
SCRECHD:    DB 0                   ; Nonzero while a binding name is expected.
SCRECIDX:   DB 0                   ; Reverse initializer index during deferred stores.
SCRECMRK:   DB 0                   ; Saved pending marker during deferred stores.
SCRCSLOT:   DB 0                   ; Slot number selected during recursive retention.
SCUNPTR:    DW 0                   ; Frame cursor held across recursive retention.
SCBODYN:    DB 0                   ; Body expression count.
SCFORMN:    DW 0                   ; Number of complete package-level forms.
SCGCOUNT:   DW 0                   ; Number of allocated package-global slots.
SCLOCTOP:   DB 0                   ; Number of active local binding records.
SCLNEXT:    DB 0                   ; Next reusable local slot number.
SCLOCMAX:   DB 0                   ; Maximum simultaneous local slot count.
SCBNDTOP:  DB 0                   ; Pending binding-record stack top.
SCLOCSAV:   DB 0                   ; Saved let cursor while recursive state restores.
SCMARK:     DB 0                   ; Pending-record cursor during SCBIND.
SCBEND:     DB 0                   ; Pending-record limit for the current let.
SCFIXN:     DW 0                   ; Number of recorded slot-address fixups.
SCBRTOP:    DB 0                   ; Generic branch patch stack top.
SCIFTOP:    DB 0                   ; Nested if patch stack top.
SCBPTMP:    DW 0                   ; Temporary staged branch patch address.
SCBTARG:    DW 0                   ; Temporary absolute branch target.
SCFOUND:    DB 0                   ; Last matching local slot.
SCFOUNDK:   DB 0                   ; Nonzero after a local match.
SCOPID:     DW 0                   ; Operator identity for generic applications.
SCPNADR:    DW 0                   ; Spelling address while classifying a primitive.
SCPNLEN:    DB 0                   ; Spelling length used by SCPMATCH.
SCPCOUNT:   DB 0                   ; Number of fixed procedure descriptors.
SCCURPR:    DB 0FFH                ; Active procedure, or FFH at package level.
SCTMPPR:    DB 0                   ; Descriptor being compiled.
SCARGN:     DB 0                   ; Generic application argument count.
SCTCTX:     DB 0                   ; Nonzero when the current expression is tail code.
SCIFTAIL:   DB 0                   ; Tail context saved while compiling an if.
SCTLSAV:    DB 0                   ; Saved tail context while evaluating arguments.
SCSKIP:     DW 0                   ; Lambda jump-over patch address.
SCPBODY:    DW 0                   ; Procedure body staged address during setup.
SCLOCVAL:   DB 0                   ; Temporary local slot for owner marking.
SCMSLOT:    DB 0                   ; Slot selected while setting a mask bit.
SCMPR:      DB 0                   ; Procedure index selected for mask writes.
SCMTADR:    DW 0                   ; Mask byte address during bit assembly.
SCDESTK:    DB 0                   ; Mutation destination kind.
SCMUT:  DB 0                   ; Nonzero selects the checked mutation store.
SCORIGPR:   DB 0                   ; Active procedure while capture masks are chained.
SCORIGTM:   DB 0                   ; Descriptor under construction during mask writes.
SCCAPOWN:   DB 0                   ; Procedure that owns the captured local slot.
SCCHAINN:   DB 0                   ; Remaining body frames in a capture chain.
SCAPEV:     DB 0                   ; Saved generic-argument event kind.
SCAPTAG:    DW 0                   ; Saved generic-argument scalar tag.
SCAPVAL:    DW 0                   ; Saved generic-argument payload.
SCAPMODE:   DB 0                   ; Nonzero selects the compact global-call marker.
SCAPGSL:    DB 0                   ; Global slot carried by the compact call marker.
SCRESV:     DW 0                   ; Procedure/body result payload during cleanup.
SCREST:     DB 0                   ; Procedure/body result tag during cleanup.
SCERRPTR:   DW 0                   ; Current compiler diagnostic string.
SCBDEP:     DB 0                   ; Nested body-frame depth.
SCBTAIL:    DB 0                   ; Incoming tail context for the current body.
SCBMODE:    DB 0                   ; 0 shares candidates, 1 isolates, 2 admits let definitions.
SCBISOL:    DB 0                   ; Caller requests a private candidate scope.
SCDEFSB:    DB 0                   ; First active binding in the definition scope.
SCLEBASE:   DB 0                   ; Active-binding base saved when a let opens.
SCBEV:      DB 0                   ; Current body-frame event kind.
SCBTAG:     DB 0                   ; Current body-frame scalar tag.
SCBVAL:     DW 0                   ; Current body-frame payload.
SCTTOP:     DB 0                   ; Number of tail-call target words in this body.
SCTMARK:    DB 0                   ; Start of the current expression's tail records.
SCTPTR:     DW 0                   ; Tail-call patch address during table writes.
SCCDTOP:    DB 0                   ; Number of cond end-jump patches in the table.
SCCNDEP:    DB 0                   ; Active nested cond patch-frame depth.
SCCNBASE:   DB 0                   ; First patch-table record owned by this cond.
SCIDMODE:   DB 0                   ; Nonzero selects package procedure storage.
SCLETMOD:   DB 0                   ; Nonzero permits the named-let spelling.
SCNAMID:    DW 0                   ; Named-let procedure name retained after dispatch.
SCNAMBS:    DB 0                   ; First temporary name record for named let.
SCNAMCUR:   DB 0                   ; Cursor while adding named-let formals.
SCNAMOP:    DB 0                   ; Enclosing descriptor while a named body opens.
SCNAMNP:    DB 0                   ; Descriptor allocated by the active named form.
SCNCTX:     DW SCNAMEDS,320,SCNAMEPL,5120,0,0
            DB 0,0                  ; Symbol context kind and ready flag.
SCSCTX:     DW SCSTRDS,64,SCSTRPL,1024,0,0
            DB 1,0                  ; String context kind and ready flag.

; Length-prefixed operator names.  Keeping these strings beside the parser
; makes the accepted surface obvious without adding a keyword table to output.
SCDEF:      DB 6,"define"
SCIF:       DB 2,"if"
SCBEGIN:    DB 5,"begin"
SCLET:      DB 3,"let"
SCLETST:  DB 4,"let*"
SCLETREC: DB 6,"letrec"
SCCOND:   DB 4,"cond"
SCELSE:   DB 4,"else"
SCAND:      DB 3,"and"
SCOR:       DB 2,"or"
SCLAMBK:    DB 6,"lambda"
SCSETK:     DB 4,"set!"
SCZEROK:    DB 5,"zero?"
SCPADD:     DB 1,"+"
SCPMIN:     DB 1,"-"
SCPMUL:     DB 1,"*"
SCOKTXT:    DB "COMPILED",13,10,"$"
SCERRTXT:   DB "COMPILE ERROR",13,10,"$"
SCCAPTXT:   DB "CAP",13,10,"$"
SCSYNTXT:   DB "SYN",13,10,"$"
SCUNSTXT:   DB "UNSUP",13,10,"$"
SCOUTTXT:   DB "OUTPUT ERROR",13,10,"$"
SCEXPTXT:   DB "EXPECT",13,10,"$"
SCEXTXT:    DB "EXPR",13,10,"$"
SCRECTXT:   DB "LETREC",13,10,"$"
SCAPTXT:    DB "APPLY",13,10,"$"
SCDESTT:    DB "DEST",13,10,"$"
SCDUPTXT:   DB "DUP",13,10,"$"
SCENDT:     DB "END",13,10,"$"
SCOPRT:     DB "OP",13,10,"$"
SCDEFT:     DB "DEF",13,10,"$"
SCDEFNT:    DB "DEFNAME",13,10,"$"
SCMEMTXT:   DB "INSUFFICIENT MEMORY",13,10,"$"
SCQUOTE:    DB 5,"quote"
SCNPLUS:    DB 1,"+"
SCNSUB:     DB 1,"-"
SCNMUL:     DB 1,"*"
SCNZERO:    DB 5,"zero?"
SCNCONS:    DB 4,"cons"
SCNCAR:     DB 3,"car"
SCNCDR:     DB 3,"cdr"
SCNPAIR:    DB 5,"pair?"
SCNNULL:    DB 5,"null?"
SCNLIST:    DB 4,"list"
SCNEQ:      DB 3,"eq?"
SCNWRIT:    DB 5,"write"
SCNDISP:    DB 7,"display"
SCNNWL:     DB 7,"newline"
SCNWCHR:    DB 10,"write-char"
SCNRDCHR:   DB 9,"read-char"
SCNQUOT:    DB 8,"quotient"
SCNREMA:    DB 9,"remainder"
SCNEQNUM:   DB 1,"="
SCNLT:      DB 1,"<"
SCNGT:      DB 1,">"
SCNLE:      DB 2,"<="
SCNGE:      DB 2,">="
SCNNOT:     DB 3,"not"
SCNNUM:     DB 7,"number?"
SCNBOOL:    DB 8,"boolean?"
SCNSYM:     DB 7,"symbol?"
SCNPRO:     DB 10,"procedure?"
SCNSTR:     DB 7,"string?"
SCNCHAR:    DB 5,"char?"
SCNEOFQ:    DB 11,"eof-object?"
