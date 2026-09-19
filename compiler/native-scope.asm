;=============================================================================
;  I3 native source-scope marking
;=============================================================================
;
;  Give source-side lexical binders a compact identity before macro matching.
;  The syntax node keeps the identity in its one-byte scope mark; the reader's
;  spelling and value payload remain unchanged.  A reverse lexical table makes
;  the nearest let or lambda binder win, so a locally bound macro name cannot
;  be mistaken for a top-level transformer.
;
;  This pass is deliberately separate from the macro arena.  It owns no node
;  storage and is reset by NMINIT through the state block in native-macro.asm.
;  The generated-template hygiene pass will use the same table and allocator.
;
;  PUBLIC
;    NMHMARK  HL=root.  Mark one source tree; carry means a bounded scope or
;             lexical-table limit was reached before publication.
;=============================================================================

NMHMAXD EQU 64

; Clear the companion state which lives after the main macro module's fixed
; workspace.  NMINIT calls this after clearing its own NMREND..NMWEND range.
NMHINIT:
        XOR A
        LD HL,NMLXN
        LD DE,NMHSEND
.clear:
        LD (HL),A
        INC HL
        PUSH HL
        OR A
        SBC HL,DE
        POP HL
        JR C,.clear
        RET

; Allocate the next non-zero scope identity.  Zero is the top-level scope.
NMNEWSCP:
        LD A,(NMSCOPE)
        INC A
        JR NZ,.ok
        SCF
        RET
.ok:
        LD (NMSCOPE),A
        XOR A
        RET

; Protect the Z80 return stack from malformed source nesting.
NMHDPIN:
        LD A,(NMHDEP)
        INC A
        CP NMHMAXD
        JR NC,.bad
        LD (NMHDEP),A
        XOR A
        RET
.bad:
        SCF
        RET

NMHDPOUT:
        LD A,(NMHDEP)
        DEC A
        LD (NMHDEP),A
        RET

; Look up the nearest binding for the symbol node in HL.  A=1 returns its
; scope in NMLXSCP; A=0 means the symbol is top-level or otherwise unbound.
NMLXLOOK:
        LD (NMHNODE),HL
        LD DE,9
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMNAME),DE
        LD A,(NMLXN)
        OR A
        JR Z,.none
        LD C,A
        LD B,0
        LD H,0
        LD L,A
        ADD HL,HL
        LD D,0
        LD E,A
        ADD HL,DE
        LD DE,NMLXTB
        ADD HL,DE
.scan:
        LD DE,3
        OR A
        SBC HL,DE
        LD A,(NMNAME)
        CP (HL)
        JR NZ,.next
        INC HL
        LD A,(NMNAME+1)
        CP (HL)
        JR NZ,.nextp
        INC HL
        LD A,(HL)
        LD (NMLXSCP),A
        LD A,1
        RET
.nextp:
        DEC HL
.next:
        DEC C
        JR NZ,.scan
.none:
        XOR A
        RET

; Add the symbol node in NMHNODE with scope A to the lexical table.
NMLXADD:
        LD (NMLXNEW),A
        LD A,(NMLXN)
        CP NMLXMAX
        JR NC,.bad
        LD C,A
        LD B,0
        LD H,0
        LD L,A
        ADD HL,HL
        LD D,0
        LD E,A
        ADD HL,DE
        LD DE,NMLXTB
        ADD HL,DE
        PUSH HL
        LD HL,(NMHNODE)
        LD DE,9
        ADD HL,DE
        LD A,(HL)
        POP HL
        LD (HL),A
        INC HL
        PUSH HL
        LD HL,(NMHNODE)
        LD DE,10
        ADD HL,DE
        LD A,(HL)
        POP HL
        LD (HL),A
        INC HL
        LD A,(NMLXNEW)
        LD (HL),A
        LD A,(NMLXN)
        INC A
        LD (NMLXN),A
        XOR A
        RET
.bad:
        SCF
        RET

; Write the scope byte of the syntax node in HL.
NMHSETS:
        LD DE,NMSCOP
        ADD HL,DE
        LD (HL),A
        RET

; Compare the scope marks of the pattern symbol in NMSYMP and the input
; symbol in NMIVAL.  Carry is not used; Z means the identifiers have the same
; binding identity.
NMSCOPEQ:
        LD HL,(NMSYMP)
        LD DE,NMSCOP
        ADD HL,DE
        LD A,(HL)
        LD C,A
        LD HL,(NMIVAL)
        LD DE,NMSCOP
        ADD HL,DE
        LD A,(HL)
        CP C
        RET

; Mark one source symbol.  A source occurrence resolves to the nearest table
; entry; an unbound occurrence retains scope zero.
NMHSYM:
        CALL NMLXLOOK
        OR A
        JR Z,.top
        LD A,(NMLXSCP)
        LD HL,(NMHNODE)
        JP NMHSETS
.top:
        LD HL,(NMHNODE)
        XOR A
        JP NMHSETS

; Return the first child of the list node in HL, or HL=0 for an empty list.
NMHFIRST:
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        XOR A
        RET

; Return a node's next sibling in HL.
NMHNEXT:
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        RET

; Identify the special binding forms at NMHROOT.  A=1 lambda, A=2 let,
; A=0 otherwise.  The head itself is still marked by NMHLIST.
NMHHEADK:
        LD HL,(NMHROOT)
        CALL NMHFIRST
        LD A,H
        OR L
        JR Z,.none
        LD (NMHHEAD),HL
        LD DE,NMLAMBT
        LD B,6
        CALL NMSPNAM
        JR NC,.lambda
        LD HL,(NMHHEAD)
        LD DE,NMLETT
        LD B,3
        CALL NMSPNAM
        JR NC,.let
.none:
        XOR A
        RET
.lambda:
        LD A,1
        RET
.let:
        LD A,2
        RET

; Give one binding-position symbol a fresh scope and publish it in the
; nearest-binding table.  A malformed non-symbol is traversed as ordinary data.
NMHBIND:
        LD A,H
        OR L
        RET Z
        LD A,(HL)
        CP NMKSYM
        JP NZ,NMHMARK
        LD (NMHNODE),HL
        CALL NMNEWSCP
        RET C
        LD A,(NMSCOPE)
        CALL NMHSETS
        JP NMLXADD

; Mark a formal list.  The source subset accepts a proper or dotted list of
; symbols; malformed entries still receive ordinary traversal treatment.
NMHFORM:
        LD A,H
        OR L
        RET Z
        LD A,(HL)
        CP NMKSYM
        JR Z,NMHBIND
        CP NMKLIST
        JP NZ,NMHMARK
        LD (NMHFORMS),HL
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMHSCAN),DE
.loop:
        LD HL,(NMHSCAN)
        LD A,H
        OR L
        JR Z,.tail
        PUSH HL
        CALL NMHBIND
        POP HL
        RET C
        CALL NMHNEXT
        LD (NMHSCAN),HL
        JR .loop
.tail:
        LD HL,(NMHFORMS)
        INC HL
        LD A,(HL)
        AND 1
        RET Z
        LD HL,(NMHFORMS)
        LD DE,6
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        JP NMHBIND

; Mark a sequence of body forms beginning at HL.
NMHBODY:
.loop:
        LD A,H
        OR L
        RET Z
        PUSH HL
        CALL NMHMARK
        POP HL
        RET C
        CALL NMHNEXT
        JR .loop

; Mark an ordinary list recursively.  The caller has already marked its head.
NMHGEN:
        LD HL,(NMHROOT)
        PUSH HL
        CALL NMHFIRST
        LD A,H
        OR L
        JR Z,.done
        CALL NMHNEXT
.loop:
        LD A,H
        OR L
        JR Z,.done
        PUSH HL
        CALL NMHMARK
        POP HL
        JR C,.bad
        CALL NMHNEXT
        JR .loop
.bad:
        POP DE
        SCF
        RET
.done:
        POP DE
        XOR A
        RET

; Lambda: initialises are not special, while every body form sees the newly
; allocated formal scopes.  Restore the old table depth on every return.
NMHLAMB:
        LD A,(NMLXN)
        PUSH AF
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        LD (NMHFORMS),HL
        CALL NMHFORM
        JR C,.bad
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        CALL NMHNEXT
        CALL NMHBODY
        JR C,.bad
        POP AF
        LD (NMLXN),A
        XOR A
        RET
.bad:
        POP AF
        LD (NMLXN),A
        SCF
        RET

; First pass over an ordinary let's initialisers.  Let binders are not visible
; in any initializer, so this runs before the second binding pass.
NMLETIN:
        CALL NMHFIRST
        LD (NMHSCAN),HL
.loop:
        LD HL,(NMHSCAN)
        LD A,H
        OR L
        RET Z
        CALL NMHFIRST
        LD A,H
        OR L
        JR Z,.bad
        CALL NMHNEXT
        LD DE,(NMHSCAN)
        PUSH DE
        PUSH HL
        CALL NMHMARK
        POP HL
        POP DE
        LD (NMHSCAN),DE
        JR C,.bad
        LD HL,(NMHSCAN)
        CALL NMHNEXT
        LD (NMHSCAN),HL
        JR .loop
.bad:
        SCF
        RET

; Second pass over an ordinary let's binding names.
NMLETBN:
        CALL NMHFIRST
        LD (NMHSCAN),HL
.loop:
        LD HL,(NMHSCAN)
        LD A,H
        OR L
        RET Z
        CALL NMHFIRST
        LD A,H
        OR L
        JR Z,.bad
        LD DE,(NMHSCAN)
        PUSH DE
        CALL NMHBIND
        POP DE
        LD (NMHSCAN),DE
        JR C,.bad
        LD HL,(NMHSCAN)
        CALL NMHNEXT
        LD (NMHSCAN),HL
        JR .loop
.bad:
        SCF
        RET

; Let: all initialisers use the outer table, then all binders become visible
; together in the body.
NMHLET:
        LD A,(NMLXN)
        PUSH AF
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        LD A,H
        OR L
        JR Z,.bad
        LD A,(HL)
        CP NMKSYM
        JR Z,.named
        CP NMKLIST
        JR NZ,.bad
        CALL NMLETIN
        JR C,.bad
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        CALL NMLETBN
        JR C,.bad
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        CALL NMHNEXT
        CALL NMHBODY
        JR C,.bad
        POP AF
        LD (NMLXN),A
        XOR A
        RET
.named:
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        CALL NMHNEXT
        CALL NMLETIN
        JR C,.bad
        ; A named-let procedure is recursive in its body, not its initializers.
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        CALL NMHBIND
        JR C,.bad
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        CALL NMHNEXT
        CALL NMLETBN
        JR C,.bad
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        CALL NMHNEXT
        CALL NMHNEXT
        CALL NMHBODY
        JR C,.bad
        POP AF
        LD (NMLXN),A
        XOR A
        RET
.bad:
        POP AF
        LD (NMLXN),A
        SCF
        RET

; Mark one list, dispatching lexical forms while keeping all other lists
; structurally traversed.
NMHLIST:
        LD DE,(NMHROOT)
        PUSH DE
        PUSH HL
        LD (NMHROOT),HL
        CALL NMHHEADK
        LD (NMHFKIND),A
        LD HL,(NMHROOT)
        CALL NMHFIRST
        LD A,H
        OR L
        JR Z,.nohead
        PUSH AF
        CALL NMHMARK
        JR C,.headbad
        POP AF
        POP HL
        LD (NMHROOT),HL
        PUSH HL
        LD A,(NMHFKIND)
        CP 1
        JR Z,.lambda
        CP 2
        JR Z,.let
        CALL NMHGEN
        JR .restore
.lambda:
        CALL NMHLAMB
        JR .restore
.let:
        CALL NMHLET
.restore:
        POP HL
        POP DE
        LD (NMHROOT),DE
        RET
.bad:
        POP HL
        POP DE
        LD (NMHROOT),DE
        SCF
        RET
.headbad:
        POP AF
        POP HL
        POP DE
        LD (NMHROOT),DE
        SCF
        RET
.nohead:
        POP HL
        POP DE
        LD (NMHROOT),DE
        XOR A
        RET

; Mark one syntax node.  Quote data is deliberately opaque to lexical scope.
NMHMARK:
        CALL NMHDPIN
        RET C
        LD A,(HL)
        CP NMKSYM
        JR Z,.sym
        CP NMKQUOT
        JR Z,.done
        CP NMKLIST
        JR Z,.list
        JR .done
.sym:
        CALL NMHSYM
        JR .finish
.list:
        CALL NMHLIST
.finish:
        PUSH AF
        CALL NMHDPOUT
        POP AF
        RET
.done:
        CALL NMHDPOUT
        XOR A
        RET

;-------------------------------------------------------------------------
; Generated-template scope propagation
;-------------------------------------------------------------------------
;
; NMCLONE gives every introduced symbol one expansion mark while captured
; symbols retain their use-site mark.  This pass turns that temporary mark
; into definition-site free references and fresh identities for generated
; lambda/let binders.  Quoted data remains opaque.
;
; PUBLIC
;   NMHGENP  HL=root.  Propagate generated binding identities; carry means
;            the bounded generated-scope table or traversal stack overflowed.
;-------------------------------------------------------------------------

NMHGENP:
        LD (NMHROOT),HL
        XOR A
        LD (NMLXN),A
        LD (NMHDEP),A
        JP NMGNODE

; Mark one generated or captured node.  Only the expansion mark is rewritten;
; source and captured nodes are already bound to their use-site identity.
NMGNODE:
        CALL NMHDPIN
        RET C
        LD A,(HL)
        CP NMKSYM
        JR Z,.sym
        CP NMKQUOT
        JR Z,.done
        CP NMKLIST
        JR Z,.list
        JR .done
.sym:
        CALL NMGSYM
        JR .finish
.list:
        CALL NMGLIST
.finish:
        PUSH AF
        CALL NMHDPOUT
        POP AF
        RET
.done:
        CALL NMHDPOUT
        XOR A
        RET

; Resolve one generated symbol through the temporary binding table.  A symbol
; from the use site or a quoted subtree keeps its existing scope byte.
NMGSYM:
        LD (NMHNODE),HL
        LD DE,NMSCOP
        ADD HL,DE
        LD A,(HL)
        LD C,A
        LD A,(NMGENSCP)
        CP C
        RET NZ
        LD HL,(NMHNODE)
        CALL NMLXLOOK
        OR A
        JR Z,.free
        LD A,(NMLXSCP)
        LD HL,(NMHNODE)
        JP NMHSETS
.free:
        LD A,(NMDEFSCP)
        LD HL,(NMHNODE)
        JP NMHSETS

; Give one generated binding position a fresh scope and enter it in the
; nearest-binding table.  Captured binding positions remain use-site scoped.
NMGBIND:
        LD A,H
        OR L
        RET Z
        LD A,(HL)
        CP NMKSYM
        JP NZ,NMGNODE
        LD (NMHNODE),HL
        LD DE,NMSCOP
        ADD HL,DE
        LD A,(HL)
        LD C,A
        LD A,(NMGENSCP)
        CP C
        JR NZ,.keep
        CALL NMNEWSCP
        RET C
        LD A,(NMSCOPE)
        LD HL,(NMHNODE)
        CALL NMHSETS
        JP NMLXADD
.keep:
        XOR A
        RET

; Mark a generated formal list, including a dotted final formal.
NMGFORM:
        LD A,H
        OR L
        RET Z
        LD A,(HL)
        CP NMKSYM
        JR Z,NMGBIND
        CP NMKLIST
        JP NZ,NMGNODE
        LD (NMHFORMS),HL
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMHSCAN),DE
.loop:
        LD HL,(NMHSCAN)
        LD A,H
        OR L
        JR Z,.tail
        PUSH HL
        CALL NMGBIND
        POP HL
        RET C
        CALL NMHNEXT
        LD (NMHSCAN),HL
        JR .loop
.tail:
        LD HL,(NMHFORMS)
        INC HL
        LD A,(HL)
        AND 1
        RET Z
        LD HL,(NMHFORMS)
        LD DE,6
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        JP NMGBIND

; Mark a generated body sequence under the current binding table.
NMGBODY:
.loop:
        LD A,H
        OR L
        RET Z
        PUSH HL
        CALL NMGNODE
        POP HL
        RET C
        CALL NMHNEXT
        JR .loop

; Mark ordinary children after a list head.  The head has already been
; resolved by NMGLIST; nested lists restore NMHROOT before returning.
NMGGEN:
        LD HL,(NMHROOT)
        CALL NMHFIRST
        LD A,H
        OR L
        JR Z,.tail
        CALL NMHNEXT
.loop:
        LD A,H
        OR L
        JR Z,.tail
        PUSH HL
        CALL NMGNODE
        POP HL
        JR C,.bad
        CALL NMHNEXT
        JR .loop
.tail:
        LD HL,(NMHROOT)
        INC HL
        LD A,(HL)
        AND 1
        RET Z
        LD HL,(NMHROOT)
        LD DE,6
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        JP NMGNODE
.bad:
        SCF
        RET

; Identify generated lambda and let heads before NMGSYM changes their mark.
; A=1 lambda, A=2 let, A=0 ordinary or captured head.
NMGHEAD:
        LD HL,(NMHROOT)
        CALL NMHFIRST
        LD A,H
        OR L
        JR Z,.none
        LD (NMHHEAD),HL
        LD DE,NMSCOP
        ADD HL,DE
        LD A,(HL)
        LD C,A
        LD A,(NMGENSCP)
        CP C
        JR NZ,.none
        LD HL,(NMHHEAD)
        LD DE,NMLAMBT
        LD B,6
        CALL NMSPNAM
        JR NC,.lambda
        LD HL,(NMHHEAD)
        LD DE,NMLETT
        LD B,3
        CALL NMSPNAM
        JR NC,.let
.none:
        XOR A
        RET
.lambda:
        LD A,1
        RET
.let:
        LD A,2
        RET

; Mark one ordinary let binding list's initializers before any binder enters
; the generated lexical table.
NMGLETIN:
        CALL NMHFIRST
        LD (NMHSCAN),HL
.loop:
        LD HL,(NMHSCAN)
        LD A,H
        OR L
        RET Z
        CALL NMHFIRST
        LD A,H
        OR L
        JR Z,.bad
        CALL NMHNEXT
        LD DE,(NMHSCAN)
        PUSH DE
        PUSH HL
        CALL NMGNODE
        POP HL
        POP DE
        LD (NMHSCAN),DE
        JR C,.bad
        LD HL,(NMHSCAN)
        CALL NMHNEXT
        LD (NMHSCAN),HL
        JR .loop
.bad:
        SCF
        RET

; Enter all ordinary let binding names after their initializers are marked.
NMGLETBN:
        CALL NMHFIRST
        LD (NMHSCAN),HL
.loop:
        LD HL,(NMHSCAN)
        LD A,H
        OR L
        RET Z
        CALL NMHFIRST
        LD A,H
        OR L
        JR Z,.bad
        LD DE,(NMHSCAN)
        PUSH DE
        CALL NMGBIND
        POP DE
        LD (NMHSCAN),DE
        JR C,.bad
        LD HL,(NMHSCAN)
        CALL NMHNEXT
        LD (NMHSCAN),HL
        JR .loop
.bad:
        SCF
        RET

; Generated lambda: formals bind the body, while the outer table remains in
; force for any malformed or non-binding initializer-like forms.
NMGLAMB:
        LD A,(NMLXN)
        PUSH AF
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        LD (NMHFORMS),HL
        CALL NMGFORM
        JR C,.bad
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        CALL NMHNEXT
        CALL NMGBODY
        JR C,.bad
        POP AF
        LD (NMLXN),A
        XOR A
        RET
.bad:
        POP AF
        LD (NMLXN),A
        SCF
        RET

; Generated let: initializers use the outer table; the binding names are
; visible together in the body.  Named let adds its procedure name only after
; its initializers have been traversed.
NMGLET:
        LD A,(NMLXN)
        PUSH AF
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        LD A,H
        OR L
        JR Z,.bad
        LD A,(HL)
        CP NMKSYM
        JR Z,.named
        CP NMKLIST
        JR NZ,.bad
        CALL NMGLETIN
        JR C,.bad
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        CALL NMGLETBN
        JR C,.bad
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        CALL NMHNEXT
        CALL NMGBODY
        JR C,.bad
        POP AF
        LD (NMLXN),A
        XOR A
        RET
.named:
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        CALL NMHNEXT
        CALL NMGLETIN
        JR C,.bad
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        CALL NMGBIND
        JR C,.bad
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        CALL NMHNEXT
        CALL NMGLETBN
        JR C,.bad
        LD HL,(NMHROOT)
        CALL NMHFIRST
        CALL NMHNEXT
        CALL NMHNEXT
        CALL NMHNEXT
        CALL NMGBODY
        JR C,.bad
        POP AF
        LD (NMLXN),A
        XOR A
        RET
.bad:
        POP AF
        LD (NMLXN),A
        SCF
        RET

; Dispatch one list while preserving the parent's current root for nested
; lists.  Binding-form detection happens before the generated head is mapped
; to its definition-site scope.
NMGLIST:
        LD DE,(NMHROOT)
        PUSH DE
        PUSH HL
        LD (NMHROOT),HL
        CALL NMGHEAD
        LD (NMHFKIND),A
        LD HL,(NMHROOT)
        CALL NMHFIRST
        LD A,H
        OR L
        JR Z,.nohead
        PUSH AF
        CALL NMGNODE
        JR C,.headbad
        POP AF
        POP HL
        LD (NMHROOT),HL
        PUSH HL
        LD A,(NMHFKIND)
        CP 1
        JR Z,.lambda
        CP 2
        JR Z,.let
        CALL NMGGEN
        JR .restore
.lambda:
        CALL NMGLAMB
        JR .restore
.let:
        CALL NMGLET
.restore:
        POP HL
        POP DE
        LD (NMHROOT),DE
        RET
.bad:
        POP HL
        POP DE
        LD (NMHROOT),DE
        SCF
        RET
.headbad:
        POP AF
        POP HL
        POP DE
        LD (NMHROOT),DE
        SCF
        RET
.nohead:
        POP HL
        POP DE
        LD (NMHROOT),DE
        XOR A
        RET

; Human-readable names used only for role dispatch.
NMLAMBT: DB "lambda"
NMLETT:  DB "let"

NMLXN:      DB 0
NMLXSCP:    DB 0
NMLXNEW:    DB 0
NMHDEP:     DB 0
NMHFKIND:   DB 0
NMHNODE:    DW 0
NMHROOT:    DW 0
NMHHEAD:    DW 0
NMHSCAN:    DW 0
NMHFORMS:   DW 0
NMLXTB:     DS NMLXMAX*3
NMHSEND:
