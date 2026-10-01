; Native CP/M file ports.
;
; File ports use the same opaque tag-eight value family as the three standard
; ports.  This first adapter keeps one input and one output file open at a
; time.  The provider owns the FCB and 128-byte record buffers; Scheme sees
; only the port token and the ordinary character operations.
;
; The accepted name is a current-drive CP/M 8.3 spelling.  Drive prefixes,
; wildcards and directory separators are deliberately rejected until the
; provider-backed file contract has a portable path policy.

; Dispatch the four file-opening primitives (runtime kinds 55 through 58).
SRTFILE:
        LD A,(SRTPID)
        CP 55
        JP Z,SRTFOPR
        CP 56
        JP Z,SRTFOPW
        CP 57
        JP Z,SRTFOPB
        CP 58
        JP Z,SRTFOWB
        JP SRTERROR

; Open a text input file.
SRTFOPR:
        XOR A
        LD (SRTFOMOD),A
        JP SRTFOPI

; Open a binary input file.
SRTFOPB:
        LD A,1
        LD (SRTFOMOD),A
SRTFOPI:
        LD A,(SRTARGC)
        CP 1
        JP NZ,SRTERROR
        LD A,(SRTFIACT)
        OR A
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        CALL SRTFBLD
        JP C,SRTERROR
        LD HL,SRTFCBP
        CALL CTOPENR
        JP C,SRTERROR
        LD A,1
        LD (SRTFIACT),A
        LD A,(SRTFOMOD)
        LD (SRTFIMOD),A
        XOR A
        LD (SRTINCR),A
        LD (SRTINST),A
        LD A,8
        LD HL,SRTFIPT
        PUSH IX
        RET

; Open a text output file, replacing an existing file of the same name.
SRTFOPW:
        XOR A
        LD (SRTFOMOD),A
        JP SRTFOWI

; Open a binary output file, replacing an existing file of the same name.
SRTFOWB:
        LD A,1
        LD (SRTFOMOD),A
SRTFOWI:
        LD A,(SRTARGC)
        CP 1
        JP NZ,SRTERROR
        LD A,(SRTFOACT)
        OR A
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        CALL SRTFBLD
        JP C,SRTERROR
        LD HL,SRTFCBP
        CALL CTOPENW
        JP C,SRTERROR
        LD A,1
        LD (SRTFOACT),A
        LD A,(SRTFOMOD)
        LD (SRTFWMDE),A
        XOR A
        LD (SRTFCR),A
        LD A,8
        LD HL,SRTFOPT
        PUSH IX
        RET

; Read one byte from the active CP/M input stream.
SRTFREAD:
        LD A,(SRTFIACT)
        OR A
        JR NZ,SRTFROK
        SCF
        RET
SRTFROK:
        JP CTREAD

; Close the input stream.  A failed close poisons the logical port.
SRTFCLR:
        LD A,(SRTFIACT)
        OR A
        JR Z,SRTFCBAD
        XOR A
        LD (SRTFIACT),A
        LD (SRTINSEL),A
        JP CTCLOSER

; Close the output stream and flush its final record.
SRTFCLW:
        LD A,(SRTFOACT)
        OR A
        JR Z,SRTFCBAD
        XOR A
        LD (SRTFOACT),A
        LD (SRTOUTS),A
        JP CTCLOSEW

SRTFCBAD:
        SCF
        RET

; Write one byte to the active output stream.  Text mode turns a bare LF into
; CR/LF and avoids adding a second CR when newline has already emitted CR.
SRTFWR:
        LD A,(SRTFOACT)
        OR A
        JR NZ,SRTFWMOD
        SCF
        RET
SRTFWMOD:
        LD A,(SRTFWMDE)
        OR A
        JR NZ,SRTFWRAW
        LD A,(SRTFBYTE)
        CP 13
        JR Z,SRTFWCR
        CP 10
        JR Z,SRTFWLF
        XOR A
        LD (SRTFCR),A
        JR SRTFWRAW
SRTFWCR:
        CALL SRTFWRAW
        RET C
        LD A,1
        LD (SRTFCR),A
        RET
SRTFWLF:
        LD A,(SRTFCR)
        OR A
        JR Z,SRTFWLP
        XOR A
        LD (SRTFCR),A
        JR SRTFWRAW
SRTFWLP:
        LD A,13
        LD (SRTFBYTE),A
        CALL SRTFWRAW
        RET C
        LD A,10
        LD (SRTFBYTE),A
        JP SRTFWRAW
SRTFWRAW:
        LD A,(SRTFBYTE)
        JP CTWRITE

; Build a current-drive CP/M FCB prefix from one literal or managed string.
; The parser accepts NAME or NAME.EXT with an eight-character name and a
; three-character extension.  The FCB is padded with spaces.
SRTFBLD:
        CALL SRTSCHK
        JP C,SRTERROR
        LD A,(HL)
        OR A
        JP Z,SRTERROR
        CP 13
        JP NC,SRTERROR
        LD (SRTFNLEN),A
        INC HL
        LD (SRTFFPTR),HL
        XOR A
        LD (SRTFEXT),A
        LD (SRTFNPOS),A
        LD (SRTFEPOS),A
        LD HL,SRTFCBP
        LD (HL),A
        INC HL
        LD B,11
        LD A,' '
SRTFBLK:
        LD (HL),A
        INC HL
        DJNZ SRTFBLK
SRTFPLP:
        LD A,(SRTFNLEN)
        OR A
        JP Z,SRTFPDON
        LD HL,(SRTFFPTR)
        LD A,(HL)
        INC HL
        LD (SRTFFPTR),HL
        LD HL,SRTFNLEN
        DEC (HL)
        ; Keep the character read above in A while the remaining length is
        ; updated.  Reloading from SRTFFPTR here would skip the first byte.
        CP '.'
        JR Z,SRTFFDOT
        CP ':'
        JP Z,SRTERROR
        CP '/'
        JP Z,SRTERROR
        CP 5CH
        JP Z,SRTERROR
        CP '*'
        JP Z,SRTERROR
        CP '?'
        JP Z,SRTERROR
        CP 20H
        JP C,SRTERROR
        CP 7FH
        JP NC,SRTERROR
        CP 'a'
        JR C,SRTFCASE
        CP '{'
        JR NC,SRTFCASE
        SUB 20H
SRTFCASE:
        LD (SRTFCHAR),A
        LD A,(SRTFEXT)
        OR A
        JR NZ,SRTFEXC
        LD A,(SRTFNPOS)
        CP 8
        JP NC,SRTERROR
        LD E,A
        LD D,0
        LD HL,SRTFCBP+1
        ADD HL,DE
        LD A,(SRTFCHAR)
        LD (HL),A
        LD A,(SRTFNPOS)
        INC A
        LD (SRTFNPOS),A
        JP SRTFPLP
SRTFEXC:
        LD A,(SRTFEPOS)
        CP 3
        JP NC,SRTERROR
        LD E,A
        LD D,0
        LD HL,SRTFCBP+9
        ADD HL,DE
        LD A,(SRTFCHAR)
        LD (HL),A
        LD A,(SRTFEPOS)
        INC A
        LD (SRTFEPOS),A
        JP SRTFPLP
SRTFFDOT:
        LD A,(SRTFEXT)
        OR A
        JP NZ,SRTERROR
        LD A,(SRTFNPOS)
        OR A
        JP Z,SRTERROR
        LD A,1
        LD (SRTFEXT),A
        JP SRTFPLP
SRTFPDON:
        LD A,(SRTFNPOS)
        OR A
        JP Z,SRTERROR
        LD A,(SRTFEXT)
        OR A
        JR Z,SRTFGOOD
        LD A,(SRTFEPOS)
        OR A
        JP Z,SRTERROR
SRTFGOOD:
        XOR A
        RET

SRTFOMOD: DB 0
SRTFIACT:    DB 0
SRTFOACT:   DB 0
SRTFIMOD:    DB 0
SRTFWMDE:  DB 0
SRTFCR:       DB 0
SRTFNLEN:     DB 0
SRTFEXT:      DB 0
SRTFNPOS:     DB 0
SRTFEPOS:     DB 0
SRTFCHAR:     DB 0
SRTFFPTR:      DW 0
SRTFCBP:    DS 12
