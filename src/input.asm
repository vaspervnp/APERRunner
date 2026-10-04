; =============================================================================
; Keyboard + joystick 0, read through the PPI and the AY's port A (reg 14).
;
; keys_held    - controls held now (1 = down)
; keys_pressed - controls that went down since the previous read
;
; Controls: left  = cursor left, O, joystick left
;           right = cursor right, P, joystick right
;           jump  = cursor up, Q, space, joystick up/fire, return/enter
;           (menus: up = cursor up, Q, joystick up; select = space, fire, return)
;           down  = cursor down, A, joystick down (fast landing)
;           pause = H
;           esc   = ESC
; =============================================================================

KEY_LEFT        equ 1
KEY_RIGHT       equ 2
KEY_JUMP        equ 4
KEY_DOWN        equ 8
KEY_PAUSE       equ 16
KEY_ESC         equ 32
KEY_UP          equ 64                  ; menus: up (also a jump in the game)
KEY_FIRE        equ 128                 ; menus: select (also a jump in the game)

PPI_A           equ #F4
PPI_C           equ #F6
PPI_CONTROL     equ #F7
AY_PORT_A       equ 14

; key -> control: matrix line, bit mask (1 = key), control bits. Unrolled
; into read_input (KEY_MAP_CODE).
macro KEY line,mask,bits
                ld a,(matrix+{line})
                and {mask}
                jr z,@skip
                ld a,c
                or {bits}
                ld c,a
@skip:
mend

macro KEY_MAP_CODE
                KEY 0,%00000001,KEY_JUMP|KEY_UP     ; cursor up
                KEY 0,%00000010,KEY_RIGHT           ; cursor right
                KEY 0,%00000100,KEY_DOWN            ; cursor down
                KEY 1,%00000001,KEY_LEFT            ; cursor left
                KEY 3,%00001000,KEY_RIGHT           ; P
                KEY 4,%00000100,KEY_LEFT            ; O
                KEY 5,%00010000,KEY_PAUSE           ; H
                KEY 5,%10000000,KEY_JUMP|KEY_FIRE   ; space
                KEY 2,%00000100,KEY_JUMP|KEY_FIRE   ; return
                KEY 0,%01000000,KEY_JUMP|KEY_FIRE   ; enter
                KEY 8,%00000100,KEY_ESC             ; ESC
                KEY 8,%00001000,KEY_JUMP|KEY_UP     ; Q
                KEY 8,%00100000,KEY_DOWN            ; A
                KEY 9,%00000001,KEY_JUMP|KEY_UP     ; joystick up
                KEY 9,%00000010,KEY_DOWN            ; joystick down
                KEY 9,%00000100,KEY_LEFT            ; joystick left
                KEY 9,%00001000,KEY_RIGHT           ; joystick right
                KEY 9,%00010000,KEY_JUMP|KEY_FIRE   ; fire 1
                KEY 9,%00100000,KEY_JUMP|KEY_FIRE   ; fire 2
mend

; -----------------------------------------------------------------------------
; read_input: updates keys_held / keys_pressed. Destroys A, BC, DE, HL.
; Interrupts are held off while the PPI/AY are switched to reading.
; -----------------------------------------------------------------------------
read_input:
                di
                ld bc,PPI_A*256+AY_PORT_A   ; select AY register 14
                out (c),c
                ld bc,PPI_C*256+#C0
                out (c),c
                ld bc,PPI_C*256+#00
                out (c),c
                ld bc,PPI_CONTROL*256+#92   ; PPI port A = input
                out (c),c
                ld hl,matrix
                ld e,0                      ; matrix line
.line:          ld b,PPI_C
                ld a,e
                or #40                      ; AY read + keyboard line
                out (c),a
                ld b,PPI_A
                in a,(c)
                cpl                         ; 1 = pressed
                ld (hl),a
                inc hl
                inc e
                ld a,e
                cp 10
                jr nz,.line
                ld bc,PPI_CONTROL*256+#82   ; PPI port A = output
                out (c),c
                ld bc,PPI_C*256+#00
                out (c),c
                ei

                ld c,0                      ; matrix -> controls
                KEY_MAP_CODE

                ld a,(keys_held)            ; pressed = now AND NOT before
                cpl
                and c
                ld (keys_pressed),a
                ld a,c
                ld (keys_held),a
                ret

matrix:         defs 10
keys_held:      defb 0
keys_pressed:   defb 0
