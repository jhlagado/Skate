; Runtime entry at the CP/M load origin.
;
; The entry is only a stack setup and a jump so that the runtime's state
; files can follow it.  Placing the state before the code keeps most data
; references backward, which bounds Atom's pending forward-reference list.
; A generated COM therefore still begins with LD SP,nn.

ORG 0100H

START:
        LD SP,RT_STACK            ; Use a private boot stack until the TPA is known.
        JP RT_BOOT
