; =============================================================================
; Hardware constants and helper macros
; =============================================================================

GA_PORT         equ #7F             ; gate array (high byte of port)
GA_PEN          equ #00             ; OR pen number (0-15), #10 = border
GA_SELECT_BORDER equ #10
GA_COLOUR       equ #40             ; OR hardware colour number
GA_RMR          equ #80             ; OR: bit4 = reset IRQ counter, bit3/2 = ROMs off, bits1-0 = mode
GA_RMR_MODE0_NOROM equ GA_RMR|%1100 ; mode 0, upper+lower ROM disabled
GA_RAM_C0       equ #C0             ; base 64K mapping
GA_RAM_C4       equ #C4             ; extra bank 0 at &4000 (6128: 4-7 = 2nd 64K)
GA_RAM_C5       equ #C5
GA_RAM_C6       equ #C6
GA_RAM_C7       equ #C7

CRTC_SELECT     equ #BC
CRTC_WRITE      equ #BD

PPI_B           equ #F5             ; bit 0 = VSYNC

; CRTC register numbers
R_HTOTAL        equ 0
R_HDISP         equ 1
R_HSYNCPOS      equ 2
R_SYNCWIDTHS    equ 3
R_VTOTAL        equ 4
R_VADJUST       equ 5
R_VDISP         equ 6
R_VSYNCPOS      equ 7
R_MAXRASTER     equ 9
R_STARTHI       equ 12
R_STARTLO       equ 13

; -----------------------------------------------------------------------------
; CRTC_A reg : writes A to CRTC register `reg`. Destroys BC.
; -----------------------------------------------------------------------------
macro CRTC_A reg
                ld bc,CRTC_SELECT*256+{reg}
                out (c),c
                inc b
                out (c),a
mend

; -----------------------------------------------------------------------------
; CRTC_N reg,value : writes a constant. Destroys BC.
; -----------------------------------------------------------------------------
macro CRTC_N reg,value
                ld bc,CRTC_SELECT*256+{reg}
                out (c),c
                ld bc,CRTC_WRITE*256+{value}
                out (c),c
mend

; -----------------------------------------------------------------------------
; WAIT_DJNZ n : busy-waits ~4*n NOPs (n = 1..256, 0 = 256). Destroys B.
; -----------------------------------------------------------------------------
macro WAIT_DJNZ n
                ld b,{n}
@loop:          djnz @loop
mend

; -----------------------------------------------------------------------------
; MAP_RAM config : selects the RAM configuration (GA_RAM_*). Preserves all.
; cur_ram keeps it (low byte) for irq2, which maps bank C7 for the sound and
; puts the configuration back.
; -----------------------------------------------------------------------------
macro MAP_RAM config
                push bc
                ld bc,GA_PORT*256+{config}
                ld (cur_ram),bc
                out (c),c
                pop bc
mend
