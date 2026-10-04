; =============================================================================
; Overscan display with vertical hardware scroll (see plan.md 2.2)
;
; Every 312-line frame is three CRTC "frames" (vertical ruptures), all R9=7:
;
;   B  : 4 rows (R4=3) + adjust 8-j lines. VSYNC at its row 1. Shows 4 black
;        rows kept in base RAM bank 1 (B_ROWS_ADDR), R6=4 blanks the adjust.
;   D1 : 17 rows, top half of the picture, &8000 bank, 16K mode.
;   D2 : 17 rows, bottom half, &C000 bank, 16K mode, + adjust j lines that
;        show its ring row 17 (R6=18): the world row below the picture.
;
;   32-j lines from VSYNC to D1 start  ->  j (0..7) moves the picture by
;   one line; 8-j + j keeps the frame at 312 lines. The top edge of the
;   picture (which moves with j) stays above the visible area, and with the
;   adjust lines shown the picture always reaches B: the bottom edge does
;   not move either (no flicker at the edges).
;
; Gate array interrupts come 2 lines after VSYNC and then every 52 lines,
; so relative to B line 0 they land at:
;   irq0  B+10     : R4=3, R5=8-j, R6=4, R7=127, R12/13=D1, then the sound
;   irq1  D1 22+j  : R4=16, R6=18, R5=0, R12/13=D2   (must be < D1 line 32)
;   irq4  D2 42+j  : R5=j, R7=1, R12/13=B rows
; Writes only happen where the old value can no longer match (real CRTC
; compares with equality) and avoid VCC=0 rows for R12/13 (CRTC 1 reloads
; the start address on every line of row 0).
; =============================================================================

ROW_BYTES       equ 96
ROWS_PER_BLOCK  equ 17
PLANE_SIZE      equ #800
RING_MASK       equ #7FF
D1_BANK_HI      equ #80
D2_BANK_HI      equ #C0
D1_R12_BASE     equ #20             ; MA13-12 = 10 -> &8000, 16K mode
D2_R12_BASE     equ #30             ; MA13-12 = 11 -> &C000

B_ROWS          equ 4
VSYNC_ROW       equ 1                   ; B row with the VSYNC
B_ROWS_OFFSET   equ #800-B_ROWS*ROW_BYTES   ; #680, end of every 2K plane
B_ROWS_ADDR     equ #4000+B_ROWS_OFFSET
B_R12           equ #10|(B_ROWS_OFFSET>>9)    ; rasm '/' is float: use shifts
B_R13           equ (B_ROWS_OFFSET>>1)&#FF

IRQ_UNSYNCED    equ #80             ; irq_index start value: no match before first VSYNC

; -----------------------------------------------------------------------------
; crtc_init: firmware off, IM 1, black B rows, overscan registers.
; Interrupts stay disabled; the caller enables them when the screen is ready.
; -----------------------------------------------------------------------------
crtc_init:
                di
                im 1
                ld a,#C3                    ; JP irq_handler at &0038
                ld (#0038),a
                ld hl,irq_handler
                ld (#0039),hl

                ld bc,GA_PORT*256+GA_RMR_MODE0_NOROM
                out (c),c
                ld bc,GA_PORT*256+GA_RAM_C0
                ld (cur_ram),bc
                out (c),c

                call clear_b_rows

                ld a,IRQ_UNSYNCED
                ld (irq_index),a

                CRTC_N R_HTOTAL,63
                CRTC_N R_HDISP,48
                CRTC_N R_HSYNCPOS,50
                CRTC_N R_SYNCWIDTHS,#8E
                CRTC_N R_MAXRASTER,7
                CRTC_N R_VADJUST,0
                CRTC_N R_VDISP,B_ROWS
                CRTC_N R_STARTHI,B_R12
                CRTC_N R_STARTLO,B_R13
                ; one plain 312-line frame with VSYNC at row 0, so the first
                ; irq0 already finds VCC=0 and switches to the rupture layout
                CRTC_N R_VSYNCPOS,0
                CRTC_N R_VTOTAL,38
                ret

clear_b_rows:
                ld hl,B_ROWS_ADDR
                ld a,8
.plane:         ld d,h
                ld e,l
                inc de
                ld (hl),0
                ld bc,B_ROWS*ROW_BYTES-1
                ldir
                ld bc,PLANE_SIZE-B_ROWS*ROW_BYTES+1
                add hl,bc
                dec a
                jr nz,.plane
                ret

; -----------------------------------------------------------------------------
; set_palette: HL = 16 hardware colours for pens 0-15. Border = black.
; -----------------------------------------------------------------------------
set_palette:
                ld e,0
.pen:           ld bc,GA_PORT*256
                out (c),e
                ld a,(hl)
                or GA_COLOUR
                out (c),a
                inc hl
                inc e
                ld a,e
                cp 16
                jr nz,.pen
                ld a,GA_SELECT_BORDER
                out (c),a
                ld a,GA_COLOUR|#14
                out (c),a
                ret

; -----------------------------------------------------------------------------
; publish_scroll: hands the scroll state (scr_j/scr_d1/scr_d2) to irq0,
; which applies it at the VSYNC that starts the next game frame, so the whole
; picture changes at once and in step with the sprites drawn for it.
; -----------------------------------------------------------------------------
publish_scroll:
                di
                ld a,(scr_j)
                ld (next_j),a
                ld hl,(scr_d1)
                ld (next_d1),hl
                ld hl,(scr_d2)
                ld (next_d2),hl
                ld hl,(scr_top_row)
                ld (next_top),hl
                ld a,(last_tick)
                add VBLS_PER_FRAME
                ld (next_apply_tick),a
                ld a,1
                ld (next_ready),a
                ei
                ret

; -----------------------------------------------------------------------------
; Interrupt handler (IM 1)
; -----------------------------------------------------------------------------
irq_handler:
                push af
                push bc
                push de
                push hl
                ld b,PPI_B
                in a,(c)
                rra
                jr c,irq0
                ld hl,irq_index
                inc (hl)
                ld a,(hl)
                cp 1
                jp z,irq1
                cp 4
                jp z,irq4
irq_exit:
                pop hl
                pop de
                pop bc
                pop af
                ei
                ret

; --- B line 10: VSYNC -----------------------------------------------------------
irq0:
                xor a
                ld (irq_index),a
                ld hl,vbl_tick
                inc (hl)

                ld a,(next_ready)
                or a
                jr z,.keep
                ld a,(next_apply_tick)
                ld b,a
                ld a,(hl)
                sub b
                cp 128                      ; tick before the apply tick
                jr nc,.keep
                xor a
                ld (next_ready),a
                ld a,(next_j)
                ld (cur_j),a
                ld hl,(next_d1)
                ld (cur_d1),hl
                ld hl,(next_d2)
                ld (cur_d2),hl
                ld hl,(next_top)
                ld (cur_top_row),hl
.keep:
                CRTC_N R_VTOTAL,B_ROWS-1
                ld a,(cur_j)
                neg
                add 8
                CRTC_A R_VADJUST
                CRTC_N R_VDISP,B_ROWS
                CRTC_N R_VSYNCPOS,127

                ; R12/13 for D1: B is in row 1 (CRTC 1 reloads them on every
                ; line of row 0 only), D1 starts at B line 40-j
                ld hl,(cur_d1)
                ld a,D1_R12_BASE
                call write_start_addr

                ; sound, 50 times a second: bank C7 (src/sound.asm). At the
                ; VSYNC that starts a game frame the main loop draws the HUD
                ; first, racing the beam: the sound waits for it (sound_due)
                ld a,(last_tick)
                ld b,a
                ld a,(vbl_tick)
                sub b
                cp VBLS_PER_FRAME
                jr nz,sound_now
                ld (sound_due),a
                jp irq_exit
sound_now:      push ix
                ld a,(cur_ram)              ; whatever the game had mapped
                push af
                ld bc,GA_PORT*256+GA_RAM_C7
                out (c),c
                call sound_tick
                pop af
                ld b,GA_PORT
                out (c),a
                pop ix
                jp irq_exit

; --- D1 line 22+j ---------------------------------------------------------------
irq1:
                CRTC_N R_VTOTAL,ROWS_PER_BLOCK-1
                CRTC_N R_VDISP,ROWS_PER_BLOCK+1     ; D2: adjust lines shown
                CRTC_N R_VADJUST,0
                ld hl,(cur_d2)
                ld a,D2_R12_BASE
                call write_start_addr
                jp irq_exit

; --- D2 line 42+j ---------------------------------------------------------------
irq4:
                ld a,(cur_j)
                CRTC_A R_VADJUST
                CRTC_N R_VSYNCPOS,VSYNC_ROW
                CRTC_N R_STARTHI,B_R12
                CRTC_N R_STARTLO,B_R13
                jp irq_exit

; HL = byte offset in the 2K ring, A = bank bits for R12. Destroys A, BC, HL.
write_start_addr:
                srl h
                rr l
                or h
                CRTC_A R_STARTHI
                ld a,l
                CRTC_A R_STARTLO
                ret

; --- variables -------------------------------------------------------------------
irq_index:      defb 0
cur_ram:        defw GA_PORT*256+GA_RAM_C0  ; RAM configuration (MAP_RAM)
sfx_request:    defb 0                  ; effect to play (SFX_*), 0 = none
sound_due:      defb 0                  ; a sound tick for the main loop (irq0)
vbl_tick:       defb 0              ; +1 every VSYNC
next_ready:     defb 0
next_apply_tick: defb 0
next_j:         defb 0
next_d1:        defw 0
next_d2:        defw 0
next_top:       defw 0
cur_j:          defb 0
cur_top_row:    defw 0              ; world row in D1 row 0 of the picture shown
cur_d1:         defw 0
cur_d2:         defw 0
