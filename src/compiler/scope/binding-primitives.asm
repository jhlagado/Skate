; Return the predefined procedure kind for SCID, or zero for an ordinary name.
; Symbol references carry subtype bits in the high byte; the interner index is
; the remaining thirteen bits and addresses a three-byte descriptor.
SCPLOOK:
        LD HL,(SCID)               ; Copy the encoded symbol identity locally.
        LD A,H                     ; Remove the reference subtype from the index.
        AND 1FH
        LD H,A
        LD D,H                     ; Multiply the thirteen-bit index by descriptor size.
        LD E,L
        ADD HL,HL                  ; Two bytes per descriptor so far.
        ADD HL,DE                  ; Add one more byte for the three-byte stride.
        LD DE,SCNAMEDS             ; Address the selected symbol descriptor.
        ADD HL,DE
        LD E,(HL)                  ; Descriptor bytes zero and one hold pool offset.
        INC HL
        LD D,(HL)
        INC HL
        LD C,(HL)                  ; Descriptor byte two holds spelling length.
        LD HL,SCNAMEPL             ; Add the offset to the symbol spelling pool.
        ADD HL,DE
        LD (SCPNADR),HL            ; Keep the spelling while trying each name.
        LD A,C
        LD (SCPNLEN),A             ; Keep the length beside the spelling pointer.
        LD DE,SCNPLUS
        CALL SCPMATCH
        JP Z,SCPPLUS
        LD DE,SCNSUB
        CALL SCPMATCH
        JP Z,SCPSUB
        LD DE,SCNMUL
        CALL SCPMATCH
        JP Z,SCPMULR
        LD DE,SCNDIV
        CALL SCPMATCH
        JP Z,SCPDIV
        LD DE,SCNZERO
        CALL SCPMATCH
        JP Z,SCPZERO
        LD DE,SCNCONS
        CALL SCPMATCH
        JP Z,SCPCONS
        LD DE,SCNCAR
        CALL SCPMATCH
        JP Z,SCPCAR
        LD DE,SCNCDR
        CALL SCPMATCH
        JP Z,SCPCDR
        LD DE,SCNPAIR
        CALL SCPMATCH
        JP Z,SCPPAIR
        LD DE,SCNNULL
        CALL SCPMATCH
        JP Z,SCPNULL
        LD DE,SCNLIST
        CALL SCPMATCH
        JP Z,SCPLIST
        LD DE,SCNEQ
        CALL SCPMATCH
        JP Z,SCPEQ
        LD DE,SCNWRIT
        CALL SCPMATCH
        JP Z,SCPWRIT
        LD DE,SCNDISP
        CALL SCPMATCH
        JP Z,SCPDISP
        LD DE,SCNNWL
        CALL SCPMATCH
        JP Z,SCPNWL
        LD DE,SCNWCHR
        CALL SCPMATCH
        JP Z,SCPWCHR
        LD DE,SCNRDCHR
        CALL SCPMATCH
        JP Z,SCPRDCHR
        LD DE,SCNQUOT
        CALL SCPMATCH
        JP Z,SCPQUOT
        LD DE,SCNREMA
        CALL SCPMATCH
        JP Z,SCPREMA
        LD DE,SCNEQNUM
        CALL SCPMATCH
        JP Z,SCPEQNUM
        LD DE,SCNLT
        CALL SCPMATCH
        JP Z,SCPLT
        LD DE,SCNGT
        CALL SCPMATCH
        JP Z,SCPGT
        LD DE,SCNLE
        CALL SCPMATCH
        JP Z,SCPLE
        LD DE,SCNGE
        CALL SCPMATCH
        JP Z,SCPGE
        LD DE,SCNNOT
        CALL SCPMATCH
        JP Z,SCPNOT
        LD DE,SCNNUM
        CALL SCPMATCH
        JP Z,SCPNUM
        LD DE,SCNBOOL
        CALL SCPMATCH
        JP Z,SCPBOOL
        LD DE,SCNSYM
        CALL SCPMATCH
        JP Z,SCPSYM
        LD DE,SCNPRO
        CALL SCPMATCH
        JP Z,SCPPRO
        LD DE,SCNSTR
        CALL SCPMATCH
        JP Z,SCPSTR
        LD DE,SCNCHAR
        CALL SCPMATCH
        JP Z,SCPCHAR
        LD DE,SCNSTRLN
        CALL SCPMATCH
        JP Z,SCPSTRLN
        LD DE,SCNSTRRF
        CALL SCPMATCH
        JP Z,SCPSTRRF
        LD DE,SCNCHINT
        CALL SCPMATCH
        JP Z,SCPCHINT
        LD DE,SCNINTCH
        CALL SCPMATCH
        JP Z,SCPINTCH
        LD DE,SCNSTRMK
        CALL SCPMATCH
        JP Z,SCPSTRMK
        LD DE,SCNSTRCP
        CALL SCPMATCH
        JP Z,SCPSTRCP
        LD DE,SCNSTRAP
        CALL SCPMATCH
        JP Z,SCPSTRAP
        LD DE,SCNEOFQ
        CALL SCPMATCH
        JP Z,SCPEOFQ
        LD DE,SCNVECT
        CALL SCPMATCH
        JP Z,SCPVECT
        LD DE,SCNMKV
        CALL SCPMATCH
        JP Z,SCPMKV
        LD DE,SCNVEC
        CALL SCPMATCH
        JP Z,SCPVEC
        LD DE,SCNVLEN
        CALL SCPMATCH
        JP Z,SCPVLEN
        LD DE,SCNVREF
        CALL SCPMATCH
        JP Z,SCPVREF
        LD DE,SCNVSET
        CALL SCPMATCH
        JP Z,SCPVSET
        LD DE,SCNAPP
        CALL SCPMATCH
        JP Z,SCPAPPLY
        JP SCPNONE
SCPZERO:
        LD A,4                     ; Kind four identifies zero? at runtime.
        RET
SCPPLUS:
        LD A,1                     ; Kind one identifies addition.
        RET
SCPSUB:
        LD A,2                     ; Kind two identifies subtraction.
        RET
SCPMULR:
        LD A,3                     ; Kind three identifies multiplication.
        RET
SCPDIV:
        LD A,32                    ; Kind thirty-two identifies floating division.
        RET
SCPCONS:
        LD A,5                     ; Kind five identifies cons.
        RET
SCPCAR:
        LD A,6                     ; Kind six identifies car.
        RET
SCPCDR:
        LD A,7                     ; Kind seven identifies cdr.
        RET
SCPPAIR:
        LD A,8                     ; Kind eight identifies pair?.
        RET
SCPNULL:
        LD A,9                     ; Kind nine identifies null?.
        RET
SCPLIST:
        LD A,10                    ; Kind ten identifies list.
        RET
SCPEQ:
        LD A,11                    ; Kind eleven identifies eq?.
        RET
SCPWRIT:
        LD A,12                    ; Kind twelve identifies write.
        RET
SCPDISP:
        LD A,13                    ; Kind thirteen identifies display.
        RET
SCPNWL:
        LD A,14                    ; Kind fourteen identifies newline.
        RET
SCPWCHR:
        LD A,30                    ; Kind thirty identifies write-char.
        RET
SCPRDCHR:
        LD A,31                    ; Kind thirty-one identifies read-char.
        RET
SCPQUOT:
        LD A,15                    ; Kind fifteen identifies quotient.
        RET
SCPREMA:
        LD A,16                    ; Kind sixteen identifies remainder.
        RET
SCPEQNUM:
        LD A,17                    ; Kind seventeen identifies numeric equality.
        RET
SCPLT:
        LD A,18                    ; Kind eighteen identifies numeric less-than.
        RET
SCPGT:
        LD A,19                    ; Kind nineteen identifies numeric greater-than.
        RET
SCPLE:
        LD A,20                    ; Kind twenty identifies numeric less-or-equal.
        RET
SCPGE:
        LD A,21                    ; Kind twenty-one identifies numeric greater-or-equal.
        RET
SCPNOT:
        LD A,22                    ; Kind twenty-two identifies not.
        RET
SCPNUM:
        LD A,23                    ; Kind twenty-three identifies number?.
        RET
SCPBOOL:
        LD A,24                    ; Kind twenty-four identifies boolean?.
        RET
SCPSYM:
        LD A,25                    ; Kind twenty-five identifies symbol?.
        RET
SCPPRO:
        LD A,26                    ; Kind twenty-six identifies procedure?.
        RET
SCPSTR:
        LD A,27                    ; Kind twenty-seven identifies string?.
        RET
SCPCHAR:
        LD A,28                    ; Kind twenty-eight identifies char?.
        RET
SCPSTRLN:
        LD A,33                    ; Kind thirty-three identifies string-length.
        RET
SCPSTRRF:
        LD A,34                    ; Kind thirty-four identifies string-ref.
        RET
SCPCHINT:
        LD A,35                    ; Kind thirty-five identifies char->integer.
        RET
SCPINTCH:
        LD A,36                    ; Kind thirty-six identifies integer->char.
        RET
SCPSTRMK:
        LD A,37                    ; Kind thirty-seven identifies string.
        RET
SCPSTRCP:
        LD A,38                    ; Kind thirty-eight identifies string-copy.
        RET
SCPSTRAP:
        LD A,39                    ; Kind thirty-nine identifies string-append.
        RET
SCPEOFQ:
        LD A,29                    ; Kind twenty-nine identifies eof-object?.
        RET
SCPVECT:
        LD A,40                    ; Kind forty identifies vector?.
        RET
SCPMKV:
        LD A,41                    ; Kind forty-one identifies make-vector.
        RET
SCPVEC:
        LD A,42                    ; Kind forty-two identifies vector.
        RET
SCPVLEN:
        LD A,43                    ; Kind forty-three identifies vector-length.
        RET
SCPVREF:
        LD A,44                    ; Kind forty-four identifies vector-ref.
        RET
SCPVSET:
        LD A,45                    ; Kind forty-five identifies vector-set!.
        RET
SCPAPPLY:
        LD A,46                    ; Kind forty-six identifies apply.
        RET
SCPNONE:
        XOR A                      ; Ordinary names receive no primitive mark.
        RET

; Compare the saved interned spelling with one length-prefixed static name.
SCPMATCH:
        LD HL,(SCPNADR)
        LD A,(SCPNLEN)
        LD B,A
        LD A,(DE)
        CP B
        JR NZ,SCPMN
        INC DE
        LD A,B
        OR A
        JR Z,SCPMY
SCPMLP:
        LD A,(DE)
        CP (HL)
        JR NZ,SCPMN
        INC DE
        INC HL
        DJNZ SCPMLP
SCPMY:
        XOR A
        RET
SCPMN:
        LD A,1
        OR A
        RET
