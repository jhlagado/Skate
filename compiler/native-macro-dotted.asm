;=============================================================================
;  Native macro dotted-pattern helper
;=============================================================================
;
;  NMHASREP reports whether a list pattern has an ellipsis among its direct
;  children.  A dotted tail may absorb remaining proper-list children only
;  when that prefix has no ellipsis; a repeated prefix requires an actual
;  dotted input tail.
;=============================================================================

NMHASREP:
        LD DE,2                 ; Start at the pattern's first child.
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
.loop:
        LD A,D
        OR E
        JR Z,.none              ; The direct child chain has ended.
        LD H,D
        LD L,E
        LD BC,4                 ; BC receives this child's sibling.
        ADD HL,BC
        LD C,(HL)
        INC HL
        LD B,(HL)
        LD A,B
        OR C
        JR Z,.next              ; The last child has no following marker.
        PUSH BC
        LD H,B
        LD L,C
        CALL NMDOT              ; A clear carry identifies an ellipsis node.
        POP BC
        JR NC,.yes
.next:
        LD D,B
        LD E,C
        JR .loop
.yes:
        LD A,1
        RET
.none:
        XOR A
        RET

NMHEND:
