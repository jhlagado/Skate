; Length-prefixed operator names.  Keeping these strings beside the parser
; makes the accepted surface obvious without adding a keyword table to output.
K_DEFINE:      DB 6,"define"
K_IF:       DB 2,"if"
K_BEGIN:    DB 5,"begin"
K_LET:      DB 3,"let"
K_LETSEQ:  DB 4,"let*"
K_LETREC: DB 6,"letrec"
K_COND:   DB 4,"cond"
K_ELSE:   DB 4,"else"
K_WHEN:   DB 4,"when"
K_UNLESS: DB 6,"unless"
K_CASE:   DB 4,"case"
K_DO:     DB 2,"do"
K_AND:      DB 3,"and"
K_OR:       DB 2,"or"
K_LAMBDA:    DB 6,"lambda"
K_SET:     DB 4,"set!"
M_OK:    DB "COMPILED",13,10,"$"
M_ERROR:   DB "COMPILE ERROR",13,10,"$"
M_CAP:   DB "CAP",13,10,"$"
M_UNSUP:   DB "UNSUP",13,10,"$"
M_OUTPUT:   DB "OUTPUT ERROR",13,10,"$"
M_EXPECT:   DB "EXPECT",13,10,"$"
M_LETREC:   DB "LETREC",13,10,"$"
M_APPLY:    DB "APPLY",13,10,"$"
M_DEST:    DB "DEST",13,10,"$"
M_DUP:   DB "DUP",13,10,"$"
M_END:     DB "END",13,10,"$"
M_OP:     DB "OP",13,10,"$"
M_DEF:     DB "DEF",13,10,"$"
M_DEFNAM:    DB "DEFNAME",13,10,"$"
M_INCL:   DB "INCLUDE ERROR",13,10,"$"
M_SOURCE:   DB "SOURCE ERROR",13,10,"$"
M_MEMORY:   DB "INSUFFICIENT MEMORY",13,10,"$"
K_QUOTE:    DB 5,"quote"
K_CALLEC:    DB 7,"call/ec"
; Fragment numbers for NAME_TAB spellings.
F_STR EQU 1
F_CHAR EQU 2
F_EXACT EQU 3
F_VEC EQU 4
F_PUT EQU 5
F_PORT EQU 6
F_CURR EQU 7
F_INT EQU 8
F_OPEN EQU 9
F_SYM EQU 10
F_LEN EQU 11
F_BINF EQU 12
F_LIST EQU 13
; Predefined procedures for GLB_PRIM: the compiler kind, then the spelling.
; A byte below 20H stands for a fragment of NAME_FRG, and bit 7 marks the
; last byte of a spelling.
NAME_TAB:   DB 1,'+'+80H                        ; +
            DB 2,'-'+80H                        ; -
            DB 3,'*'+80H                        ; *
            DB 32,'/'+80H                       ; /
            DB 4,"zero",'?'+80H                 ; zero?
            DB 5,"con",'s'+80H                  ; cons
            DB 6,"ca",'r'+80H                   ; car
            DB 7,"cd",'r'+80H                   ; cdr
            DB 8,"pair",'?'+80H                 ; pair?
            DB 9,"null",'?'+80H                 ; null?
            DB 10,F_LIST+80H                    ; list
            DB 11,"eq",'?'+80H                  ; eq?
            DB 12,"writ",'e'+80H                ; write
            DB 13,"displa",'y'+80H              ; display
            DB 14,"newlin",'e'+80H              ; newline
            DB 30,"write-",F_CHAR+80H           ; write-char
            DB 31,"read-",F_CHAR+80H            ; read-char
            DB 15,"quotien",'t'+80H             ; quotient
            DB 16,"remainde",'r'+80H            ; remainder
            DB 17,'='+80H                       ; =
            DB 18,'<'+80H                       ; <
            DB 19,'>'+80H                       ; >
            DB 20,"<",'='+80H                   ; <=
            DB 21,">",'='+80H                   ; >=
            DB 22,"no",'t'+80H                  ; not
            DB 23,"number",'?'+80H              ; number?
            DB 24,"boolean",'?'+80H             ; boolean?
            DB 25,F_SYM,'?'+80H              ; symbol?
            DB 26,"procedure",'?'+80H           ; procedure?
            DB 27,F_STR,'?'+80H              ; string?
            DB 28,F_CHAR,'?'+80H                ; char?
            DB 33,F_STR,"-",F_LEN+80H     ; string-length
            DB 34,F_STR,"-re",'f'+80H        ; string-ref
            DB 35,F_CHAR,"->",F_INT+80H     ; char->integer
            DB 36,F_INT,"->",F_CHAR+80H     ; integer->char
            DB 37,F_STR+80H                  ; string
            DB 38,F_STR,"-cop",'y'+80H       ; string-copy
            DB 39,F_STR,"-appen",'d'+80H     ; string-append
            DB 29,"eof-object",'?'+80H          ; eof-object?
            DB 40,F_VEC,'?'+80H              ; vector?
            DB 41,"make-",F_VEC+80H          ; make-vector
            DB 42,F_VEC+80H                  ; vector
            DB 43,F_VEC,"-",F_LEN+80H     ; vector-length
            DB 44,F_VEC,"-re",'f'+80H        ; vector-ref
            DB 45,F_VEC,"-set",'!'+80H       ; vector-set!
            DB 46,"appl",'y'+80H                ; apply
            DB 54,"rea",'d'+80H                 ; read
            DB 47,F_CURR,"in",F_PUT,F_PORT+80H  ; current-input-port
            DB 48,F_CURR,"out",F_PUT,F_PORT+80H ; current-output-port
            DB 49,F_CURR,"error-",F_PORT+80H    ; current-error-port
            DB 50,F_PORT,'?'+80H                ; port?
            DB 51,"in",F_PUT,F_PORT,'?'+80H     ; input-port?
            DB 52,"out",F_PUT,F_PORT,'?'+80H    ; output-port?
            DB 53,"close-",F_PORT+80H           ; close-port
            DB 56,F_OPEN,"in",F_PUT,"fil",'e'+80H ; open-input-file
            DB 57,F_OPEN,"out",F_PUT,"fil",'e'+80H ; open-output-file
            DB 58,F_OPEN,"in",F_PUT,F_BINF+80H ; open-input-binary-file
            DB 59,F_OPEN,"out",F_PUT,F_BINF+80H ; open-output-binary-file
            DB 61,"set-car",'!'+80H             ; set-car!
            DB 62,"set-cdr",'!'+80H             ; set-cdr!
            DB 63,"equal",'?'+80H               ; equal?
            DB 11,"eqv",'?'+80H                 ; eqv?
            DB 64,F_CHAR,"=",'?'+80H            ; char=?
            DB 65,F_CHAR,"<",'?'+80H            ; char<?
            DB 66,F_CHAR,">",'?'+80H            ; char>?
            DB 67,F_CHAR,"<=",'?'+80H           ; char<=?
            DB 68,F_CHAR,">=",'?'+80H           ; char>=?
            DB 69,F_STR,"=",'?'+80H          ; string=?
            DB 70,F_STR,"<",'?'+80H          ; string<?
            DB 71,F_STR,">",'?'+80H          ; string>?
            DB 72,F_STR,"<=",'?'+80H         ; string<=?
            DB 73,F_STR,">=",'?'+80H         ; string>=?
            DB 74,F_SYM,"->",F_STR+80H    ; symbol->string
            DB 75,F_STR,"->",F_SYM+80H    ; string->symbol
            DB 76,"number->",F_STR+80H       ; number->string
            DB 77,"modul",'o'+80H               ; modulo
            DB 78,"ab",'s'+80H                  ; abs
            DB 79,F_LEN+80H                  ; length
            DB 80,"revers",'e'+80H              ; reverse
            DB 81,"appen",'d'+80H               ; append
            DB 82,F_LIST,"-tai",'l'+80H         ; list-tail
            DB 83,F_LIST,"-re",'f'+80H          ; list-ref
            DB 84,"mem",'q'+80H                 ; memq
            DB 85,"ass",'q'+80H                 ; assq
            DB 86,"membe",'r'+80H               ; member
            DB 87,"asso",'c'+80H                ; assoc
            DB 88,F_LIST,'?'+80H                ; list?
            DB 89,F_CHAR,"-upcas",'e'+80H       ; char-upcase
            DB 90,F_CHAR,"-downcas",'e'+80H     ; char-downcase
            DB 91,F_CHAR,"-alphabetic",'?'+80H  ; char-alphabetic?
            DB 92,F_CHAR,"-numeric",'?'+80H     ; char-numeric?
            DB 93,F_CHAR,"-whitespace",'?'+80H  ; char-whitespace?
            DB 94,"sub",F_STR+80H            ; substring
            DB 95,F_EXACT,"->in",F_EXACT+80H    ; exact->inexact
            DB 95,"in",F_EXACT+80H              ; inexact
            DB 96,"in",F_EXACT,"->",F_EXACT+80H ; inexact->exact
            DB 96,F_EXACT+80H                   ; exact
            DB 97,"floo",'r'+80H                ; floor
            DB 98,"ceilin",'g'+80H              ; ceiling
            DB 99,"truncat",'e'+80H             ; truncate
            DB 100,"roun",'d'+80H               ; round
            DB 101,"mi",'n'+80H                 ; min
            DB 102,"ma",'x'+80H                 ; max
            DB 103,"even",'?'+80H               ; even?
            DB 104,"odd",'?'+80H                ; odd?
            DB 105,"positive",'?'+80H           ; positive?
            DB 106,"negative",'?'+80H           ; negative?
            DB 107,F_EXACT,'?'+80H              ; exact?
            DB 108,"in",F_EXACT,'?'+80H         ; inexact?
            DB 109,F_INT,'?'+80H            ; integer?
            DB 110,"gc",'d'+80H                 ; gcd
            DB 111,"lc",'m'+80H                 ; lcm
            DB 112,"exp",'t'+80H                ; expt
            DB 113,"sqr",'t'+80H                ; sqrt
            DB 114,"caa",'r'+80H                ; caar
            DB 115,"cad",'r'+80H                ; cadr
            DB 116,"cda",'r'+80H                ; cdar
            DB 117,"cdd",'r'+80H                ; cddr
            DB 118,"caaa",'r'+80H               ; caaar
            DB 119,"caad",'r'+80H               ; caadr
            DB 120,"cada",'r'+80H               ; cadar
            DB 121,"cadd",'r'+80H               ; caddr
            DB 122,"cdaa",'r'+80H               ; cdaar
            DB 123,"cdad",'r'+80H               ; cdadr
            DB 124,"cdda",'r'+80H               ; cddar
            DB 125,"cddd",'r'+80H               ; cdddr
            DB 84,"mem",'v'+80H                 ; memv
            DB 85,"ass",'v'+80H                 ; assv
; The fragments, numbered from one in the order of the equates above.
NAME_FRG:
            DB "strin",'g'+80H
            DB "cha",'r'+80H
            DB "exac",'t'+80H
            DB "vecto",'r'+80H
            DB "put",'-'+80H
            DB "por",'t'+80H
            DB "current",'-'+80H
            DB "intege",'r'+80H
            DB "open",'-'+80H
            DB "symbo",'l'+80H
            DB "lengt",'h'+80H
            DB "binary-fil",'e'+80H
            DB "lis",'t'+80H
