;=============================================================================
;  Arithmetic compiler command front end
;=============================================================================
;
;  The command reads one flat arithmetic form from the CP/M FCB, retains the
;  two operand values, and asks the shared ABI-2 numeric services to validate
;  the operation.  The result is not written here: the emitter records the
;  operator and operands in the generated runtime image.
;
;  The parser, numeric services and publication routines meet the measured
;  contracts imported by this command.  Their assembly labels remain stable
;  so the host budget and CP/M proof can inspect the same interfaces.
;=============================================================================

ARMAIN:
        LD HL,(6)                 ; CP/M reports the top of transient memory.
        LD DE,8000H               ; Keep the upper half for the native stack.
        OR A                       ; Clear carry before subtracting the stack reserve.
        SBC HL,DE                  ; Compare the TPA ceiling with the reserved stack top.
        JP C,ARMEMERR             ; Refuse to run without the documented guard.
        LD SP,8000H               ; Reader and emitter calls share this stack.
        CALL ARPARSE              ; Read, validate and evaluate the source form.
        JP C,ARFAIL               ; No output is opened before success.
        CALL AREMIT               ; Patch and stream NOBJ, then the COM image.
        JP C,ARFAIL               ; Failed output has no complete COMMIT.
        LD DE,AROKTXT             ; Report a successfully staged generation.
        JP ARPRINT                 ; Print the staged-generation result and return to CP/M.

; Read exactly one (+|-|*|/) expression with two numeric operands.
ARPARSE:
        LD HL,005CH               ; CCP places the source FCB here.
        CALL CSOPEN                ; Install the command-tail source callback.
        JR NC,ARPSOPEN             ; Continue when the source FCB is available.
        LD A,2                     ; Code 2 means source I/O failed.
        LD (ARCODE),A              ; Preserve the diagnostic for the caller.
        SCF                        ; Report failure without opening an output file.
        RET                        ; Return with the source still closed.
ARPSOPEN:
        LD A,1                     ; Code 1 is the open-state marker.
        LD (AROPEN),A              ; The shared emitter must close this source later.
        LD IX,ARSYMCXT             ; Select the symbol interner context.
        CALL IINIT                 ; Clear its directory and spelling arena.
        JP C,ARPREAD               ; Convert an initialization failure to a read error.
        LD IX,ARSTRCXT             ; Select the string interner context.
        CALL IINIT                 ; Clear the string directory and spelling arena.
        JP C,ARPREAD               ; The same diagnostic covers either context.
        LD HL,CSBYTE               ; Give the reader its one-byte source callback.
        LD DE,ARSYMCXT             ; Pass the symbol context as the reader's first arena.
        LD BC,ARSTRCXT             ; Pass the string context as its second arena.
        CALL RINIT                  ; Reset lexer state without consuming a byte.
        JP C,ARPREAD                ; Treat an invalid reader setup as source failure.

        CALL RNEXT                  ; The form must start with an open list.
        JP C,ARPREAD                ; Propagate a source read failure.
        CP 1                         ; Reader kind 1 is an opening parenthesis.
        JP NZ,ARPSYNT                ; Any other first event is malformed input.
        CALL RNEXT                  ; Read the operator symbol.
        JP C,ARPREAD                ; Propagate a source read failure.
        CP 5                         ; Reader kind 5 is an interned symbol.
        JP NZ,ARPSYNT                ; Operators must be symbols, not literals.
        LD A,(LBUFLEN)               ; The operator spelling must contain one byte.
        CP 1                         ; Reject names longer than one character.
        JP NZ,ARPSYNT                ; Only the four arithmetic characters are allowed.
        LD A,(LBUFFER)               ; Load that character for the operator tests.
        CP '+'                       ; Check addition first.
        JR Z,AROPGOOD                ; Keep the source character as the operation marker.
        CP '-'                       ; Check subtraction.
        JR Z,AROPGOOD                ; Keep the source character as the operation marker.
        CP '*'                       ; Check multiplication.
        JR Z,AROPGOOD                ; Keep the source character as the operation marker.
        CP '/'                       ; Check division.
        JP NZ,ARPSYNT                ; Anything else is a syntax error.
AROPGOOD:
        LD (AROP),A                  ; Save the validated operator for dispatch.

        CALL RNEXT                  ; Read the first operand datum.
        JP C,ARPREAD                ; A source failure is a read error.
        CP 7                        ; Reader kind 7 denotes a numeric literal.
        JP NZ,ARPSYNT               ; Reject symbols, lists and other datum kinds.
        LD A,(RTAG)                 ; Fetch the literal representation tag.
        CP 3                        ; Tag 3 is an exact signed integer.
        JR Z,ARLEFTOK               ; Keep an integer operand as-is.
        OR A                        ; Tag zero is the binary16 representation.
        JP NZ,ARPSYNT               ; No other representation is accepted here.
ARLEFTOK:
        LD (ARLTAG),A               ; Preserve the left operand tag for the emitter.
        LD (ARLVAL),HL              ; Preserve the left payload for the emitter.

        CALL RNEXT                  ; Read the second operand datum.
        JP C,ARPREAD                ; A source failure is a read error.
        CP 7                        ; It must also be a numeric literal.
        JP NZ,ARPSYNT               ; Reject a non-numeric second operand.
        LD A,(RTAG)                 ; Fetch the second representation tag.
        CP 3                        ; Preserve an exact integer without conversion.
        JR Z,ARROK                  ; Continue with the accepted integer tag.
        OR A                        ; Tag zero is the binary16 representation.
        JP NZ,ARPSYNT               ; No other representation is accepted here.
ARROK:
        LD (ARRTAG),A               ; Preserve the right operand tag for the emitter.
        LD (ARRVAL),HL              ; Preserve the right payload for the emitter.

        LD A,(AROP)                 ; Select the numeric service for the operator.
        CP '+'                      ; Addition uses the shared NADD entry.
        JR Z,ARDOADD                ; Dispatch addition.
        CP '-'                      ; Subtraction uses the shared NSUB entry.
        JR Z,ARDOSUB                ; Dispatch subtraction.
        CP '*'                      ; Multiplication uses the shared NMUL entry.
        JR Z,ARDOMUL                ; Dispatch multiplication.
ARDODIV:
        CALL ARARGS                 ; Load both operands and their tags.
        CALL NDIV                   ; Divide, returning carry on failure.
        JP ARNUMRET                 ; Finish the common result and EOF checks.
ARDOADD:
        CALL ARARGS                 ; Load both operands and their tags.
        CALL NADD                   ; Add, returning carry on failure.
        JP ARNUMRET                 ; Finish the common result and EOF checks.
ARDOSUB:
        CALL ARARGS                 ; Load both operands and their tags.
        CALL NSUB                   ; Subtract, returning carry on failure.
        JP ARNUMRET                 ; Finish the common result and EOF checks.
ARDOMUL:
        CALL ARARGS                 ; Load both operands and their tags.
        CALL NMUL                   ; Multiply, returning carry on failure.
        JP ARNUMRET                 ; Finish the common result and EOF checks.
ARARGS:
        LD HL,(ARLVAL)              ; ABI left payload is returned in HL.
        LD DE,(ARRVAL)              ; ABI right payload is returned in DE.
        LD A,(ARRTAG)               ; Read the right representation tag first.
        LD B,A                      ; B carries the right representation tag.
        LD A,(ARLTAG)               ; A carries the left representation tag.
        RET                         ; Return with the numeric ABI registers loaded.

; Numeric dispatch validates the literal operands during compilation.  The
; result is deliberately discarded: the emitter embeds the operands and the
; generated COM/NOBJ image performs this operation when it runs.
ARNUMRET:
        JR C,ARPNUM                 ; Numeric overflow or an invalid pair is an error.
        CALL RNEXT                  ; Read the closing parenthesis.
        JP C,ARPREAD                ; Propagate a source read failure.
        CP 2                        ; Reader kind 2 is a closing parenthesis.
        JP NZ,ARPSYNT               ; Reject an unterminated or overlong form.
        CALL RNEXT                  ; No second top-level datum is permitted.
        JP C,ARPREAD                ; Propagate a source read failure.
        OR A                        ; Reader kind zero is the only valid EOF marker.
        JP NZ,ARPSYNT               ; Reject trailing source data.
        CALL CSCLOSE                 ; Close the source before publishing output.
        JR C,ARPIO                  ; Report a close failure as source I/O.
        XOR A                       ; Clear the open-state flag.
        LD (AROPEN),A               ; The emitter may now finish independently.
        RET                         ; Return success with carry clear.

ARPNUM:
        LD A,3                      ; Code 3 identifies numeric overflow/invalid math.
        LD (ARCODE),A               ; Preserve the diagnostic for the caller.
        SCF                         ; Return failure to the command entry.
        RET                         ; Leave the source cleanup to the common failure path.
ARPREAD:
        LD A,1                      ; Code 1 identifies source parsing or setup failure.
        LD (ARCODE),A               ; Preserve the diagnostic for the caller.
        SCF                         ; Return failure to the command entry.
        RET                         ; The caller reports the staged failure.
ARPSYNT EQU ARPREAD               ; Reader and syntax failures share one path.
ARPIO:
        LD A,2                      ; Code 2 identifies source or output close failure.
        LD (ARCODE),A               ; Preserve the diagnostic for the caller.
        SCF                         ; Return failure to the command entry.
        RET                         ; No incomplete artifact is committed.
