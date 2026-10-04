; =============================================================================
; Runner A.P.E.R - loader (LOADER.BIN at &8000, CALLed by the DISC program)
;
; Runs with the firmware on: shows the loading screen, then loads the banks
; and the game through AMSDOS (CAS IN), and jumps to the game, which turns the
; firmware off.
;
; Loading screen: LOADSCR.BIN (ZX0) unpacked to &C000, a full-width picture
; of 21 char rows (96-byte lines: CRTC R1 = 48), centred vertically.
; Memory: loader &8000-&97FF, AMSDOS buffer &9800-&9FFF, files load at &4000
; (base RAM or the bank mapped there).
; =============================================================================

SCR_SET_MODE    equ #BC0E
SCR_SET_INK     equ #BC32
SCR_SET_BORDER  equ #BC38
CAS_IN_OPEN     equ #BC77
CAS_IN_CLOSE    equ #BC7A
CAS_IN_DIRECT   equ #BC83
GA_PORT         equ #7F
FILE_BUFFER     equ #9800
LOAD_AT         equ #4000
SCREEN          equ #C000

                include "lib/dzx0_standard.asm"

                org #8000
loader:
                xor a                       ; mode 0, all inks black meanwhile
                call SCR_SET_MODE
                xor a
.black:         push af
                ld bc,0
                call SCR_SET_INK
                pop af
                inc a
                cp 16
                jr nz,.black
                ld bc,0
                call SCR_SET_BORDER
                ld hl,crtc_setup            ; full-width lines, 21 rows, centred
.crtc:          ld a,(hl)
                cp #FF
                jr z,.picture
                ld bc,#BC00
                out (c),a
                inc hl
                ld a,(hl)
                inc b
                out (c),a
                inc hl
                jr .crtc
.picture:       ld hl,name_screen
                call load_file
                ld hl,LOAD_AT
                ld de,SCREEN
                call unpack
                ld hl,loading_palette
                xor a
.inks:          push af
                ld b,(hl)
                ld c,b
                push hl
                call SCR_SET_INK
                pop hl
                inc hl
                pop af
                inc a
                cp 16
                jr nz,.inks

                ld hl,banks                 ; the banks, then the game
.bank:          ld a,(hl)
                inc hl
                or a
                jr z,.game
                ld b,GA_PORT
                out (c),a
                call load_file              ; HL = name entry, moves past it
                jr .bank
.game:          ld bc,GA_PORT*256+#C0
                out (c),c
                ld hl,name_game
                call load_file
                jp LOAD_AT                  ; boot stub: moves the code, firmware off

unpack:         dzx0_standard               ; (returns at the end marker)

; HL = length byte + name: loads the file at LOAD_AT, HL ends after the name
load_file:
                ld b,(hl)
                inc hl
                push hl
                ld e,b
                ld d,0
                add hl,de
                ex (sp),hl                  ; (sp) = after the name, HL = name
                ld de,FILE_BUFFER
                call CAS_IN_OPEN
                ld hl,LOAD_AT
                call CAS_IN_DIRECT
                call CAS_IN_CLOSE
                pop hl
                ret

crtc_setup:     defb 1,48                   ; 96 bytes per line
                defb 2,50                   ; horizontal sync for that width
                defb 6,LOADING_ROWS         ; rows shown
                defb 7,30-((25-LOADING_ROWS)>>1) ; vertical sync: centred
                defb #FF

                include "data/loading_palette.asm"

name_screen:    defb 11
                defm "LOADSCR.BIN"
banks:          defb #C4,10
                defm "APERB4.BIN"
                defb #C5,10
                defm "APERB5.BIN"
                defb #C6,10
                defm "APERB6.BIN"
                defb #C7,10
                defm "APERB7.BIN"
                defb 0
name_game:      defb 8
                defm "APER.BIN"
loader_end:
                assert loader_end <= FILE_BUFFER
                save "build/loader.bin",loader,loader_end-loader

; the picture, ZX0-packed, loaded at &4000 first
                bank
                org #4000
loadscr_start:
                inczx0 "data/loading.bin"
loadscr_end:
                save "build/loadscr.bin",loadscr_start,loadscr_end-loadscr_start
