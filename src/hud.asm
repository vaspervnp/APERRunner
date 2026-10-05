; =============================================================================
; HUD (right quarter of the screen).
;
; The HUD shares screen memory with the playfield, so it scrolls with it.
; Its background is vertically uniform (render_row draws it with every row),
; so only the dynamic elements need care. Each element ("slot") is an
; 8-line box of opaque bytes built in a buffer when its value changes. Every
; game frame, before the beam gets there, each slot is copied to its fixed
; screen line again, and the lines the scroll pushed below it (s lines, s =
; how far the picture moved since the last frame) are cleared to the panel
; colour. Slots are handled top to bottom, so a strip cleared into the next
; slot is redrawn right after. The buffers are rebuilt at the end of the
; previous game frame (hud_prepare), so the start of a frame only copies.
;
; Elements sit on the flat panel (bytes HUD_PANEL_FIRST..HUD_PANEL_LAST,
; pen 1); the glyphs (tools/assets.py "panel" kind, bank C7) are opaque with
; that colour, so a slot never reads the screen.
;
; Layout: SC score, HI best score (or this one when higher), coins and lives,
; the six power-ups (dark, or lit with a time bar), the route Kiato-Piraeus
; with the runner's place. The background (render_row) frames it and runs a
; little track with the stations on the right.
; =============================================================================

HUD_PANEL_BYTE  equ #C0                 ; two pixels of pen 1
HUD_PANEL_FIRST equ COL_HUD+2
HUD_PANEL_LAST  equ COL_HUD+19
HUD_MAX_W       equ 18                  ; bytes
HUD_STEP_MAX    equ 16                  ; (2 frames at top speed) larger: wipe the panel
HUD_BAND_FIRST  equ 80                  ; screen lines the slots can reach
HUD_BAND_LAST   equ 203

; slot record (hud_slots, HUD_SLOT_COUNT of them)
SL_Y            equ 0                   ; top screen line
SL_X            equ 1                   ; byte column
SL_W            equ 2                   ; bytes
SL_H            equ 3                   ; lines
SL_BUF          equ 4                   ; (2) buffer, W*H bytes
SL_KEY_FN       equ 6                   ; (2) A = visible, hud_key = value
SL_BUILD_FN     equ 8                   ; (2) fills the buffer from hud_key
SL_COVER        equ 10                  ; 1: the next slot sits right below, as wide
SL_KEY          equ 11                  ; (3) value the buffer shows
SL_STATE        equ 14                  ; bit0 drawn on screen, bit1 buffer valid,
                                        ; bit2 shown this frame, bit3 drawn last frame
SL_SIZE         equ 15

; layout (exported to the symbol file for the tests). Slots of a group touch,
; so only the lines below the last shown one of a group need clearing.
; The slots are drawn faster than nothing but slower than the beam (~100 us
; a line for 64), so the groups are spread down the band: the gaps between
; them give the drawing its lead back.
HUD_SCORE_Y     equ 88
HUD_HI_Y        equ 96
HUD_COINS_Y     equ 116                 ; coins and lives side by side
HUD_COINS_W     equ 18
HUD_COINS_H     equ 12                      ; and the route bar under them
HUD_PU_Y        equ 136                 ; first power-up row
HUD_PU_CELLS    equ 3                       ; power-up cells per slot
HUD_PU_CELL     equ 4
HUD_PU_W        equ HUD_PU_CELLS*HUD_PU_CELL
HUD_PU_H        equ 8                       ; icon, its time bar on the last line
HUD_PU_X        equ HUD_PANEL_FIRST+3
HUD_SCORE_W     equ 12                      ; 6 digits (the best score in orange)
HUD_ROUTE_LINE  equ 9                       ; the route bar in the coins slot:
HUD_ROUTE_W     equ HUD_COINS_W             ; 36 pixels, a station every 6
HUD_ROUTE_H     equ 3

; -----------------------------------------------------------------------------
; hud_init: slots from hud_layout, nothing drawn (the screen is fresh).
; -----------------------------------------------------------------------------
hud_init:
                ld hl,hud_layout
                ld ix,hud_slots
                ld b,HUD_SLOT_COUNT
.slot:          push bc
                ld b,SL_KEY                 ; static part
                push ix
                pop de
.copy:          ld a,(hl)
                ld (de),a
                inc hl
                inc de
                djnz .copy
                xor a                       ; key, state
                ld (ix+SL_KEY),a
                ld (ix+SL_KEY+1),a
                ld (ix+SL_KEY+2),a
                ld (ix+SL_STATE),a
                ld de,SL_SIZE
                add ix,de
                pop bc
                djnz .slot
                ld a,1
                ld (hud_fresh),a
                ret

; -----------------------------------------------------------------------------
; hud_update: first thing in a game frame: only
; draws, hud_prepare (end of the previous frame) did the rest.
; -----------------------------------------------------------------------------
hud_update:
                ld a,(next_ready)           ; last frame overran: the picture
                or a                        ; it scrolled is not shown yet, wait
                ret nz
                ld hl,(cur_top_row)         ; Q = top*8 - j of the picture shown
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(cur_j)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                ld de,(hud_q)
                ld (hud_q),hl
                or a
                sbc hl,de                   ; HL = lines moved
                ld a,(hud_fresh)
                or a
                jr nz,.fresh
                ld a,h
                or a
                jr nz,.jump
                ld a,l
                cp HUD_STEP_MAX+1
                jr c,.step
.jump:          call hud_clear_band         ; (never expected) wipe the panel
.fresh:         xor a                       ; new screen: nothing to clear
                ld (hud_fresh),a
.step:          ld (hud_step),a

                ld ix,hud_slots             ; bit 3: drawn last frame
                ld b,HUD_SLOT_COUNT
                ld de,SL_SIZE
.old:           res 3,(ix+SL_STATE)
                bit 0,(ix+SL_STATE)
                jr z,.old_next
                set 3,(ix+SL_STATE)
                res 0,(ix+SL_STATE)
.old_next:      add ix,de
                djnz .old
                ld ix,hud_slots             ; top to bottom, ahead of the beam:
                ld b,HUD_SLOT_COUNT         ; each run of touching shown slots,
.slot:          bit 2,(ix+SL_STATE)         ; then what scrolled out below it
                jr nz,.shown
                push bc
                call hud_slot_clear         ; hidden: its old place
                pop bc
                jr .next
.shown:         ld (hud_run),ix
                ld a,1
                ld (hud_run_n),a
                ld a,(ix+SL_Y)
                ld (hb_y),a
                ld a,(ix+SL_X)
                ld (hb_x),a
                ld a,(ix+SL_W)
                ld (hb_w),a
                ld (hb_stride),a
                ld l,(ix+SL_BUF)
                ld h,(ix+SL_BUF+1)
                ld c,(ix+SL_H)              ; C = lines of the run
.extend:        set 0,(ix+SL_STATE)
                ld a,(ix+SL_COVER)          ; next slot continues the run?
                or a
                jr z,.run
                bit 2,(ix+SL_STATE+SL_SIZE)
                jr z,.run
                ld de,SL_SIZE
                add ix,de
                dec b
                ld a,(hud_run_n)
                inc a
                ld (hud_run_n),a
                ld a,c
                add a,(ix+SL_H)
                ld c,a
                jr .extend
.run:           ld a,c
                ld (hb_lines),a
                push bc
                push ix
                call hud_blit
                ld ix,(hud_run)             ; the run's slots: below them
                ld a,(hud_run_n)
.run_clear:     push af
                call hud_slot_clear
                ld de,SL_SIZE
                add ix,de
                pop af
                dec a
                jr nz,.run_clear
                pop ix
                pop bc
.next:          ld de,SL_SIZE
                add ix,de
                djnz .slot
                ret

; IX = slot: if it was drawn last frame, clear the lines its old picture
; moved to that this frame's drawing will not cover.
hud_slot_clear:
                bit 3,(ix+SL_STATE)
                ret z
                ld c,0                      ; C = the next slot is drawn below
                ld a,(ix+SL_COVER)
                or a
                jr z,.below
                bit 2,(ix+SL_STATE+SL_SIZE)
                jr z,.below
                ld a,(hud_step)             ; (a big jump passes beyond it)
                cp 9
                jr nc,.below
                ld a,(ix+SL_H+SL_SIZE)      ; (the next slot must be as tall)
                cp 8
                jr c,.below
                inc c
.below:         bit 2,(ix+SL_STATE)
                jr nz,.shown
                xor a                       ; gone: its own lines,
                dec c                       ; + the s below unless covered
                jr z,.gone
                ld a,(hud_step)
.gone:          add a,(ix+SL_H)
                ld b,(ix+SL_Y)
                jr .fill
.shown:         dec c                       ; still there: the s lines below,
                ret z                       ; unless the next slot covers them
                ld a,(hud_step)
                or a
                ret z
                ld b,a
                ld a,(ix+SL_Y)
                add a,(ix+SL_H)
                ld c,a
                ld a,b
                ld b,c
.fill:          ld (hb_lines),a
                ld a,b
                ld (hb_y),a
                ld a,(ix+SL_X)
                ld (hb_x),a
                ld a,(ix+SL_W)
                ld (hb_w),a
                xor a
                ld (hb_stride),a
                ld hl,hud_panel_line
                jp hud_blit

; -----------------------------------------------------------------------------
; hud_prepare: end of a game frame without a coarse step: which slots show
; next frame, and their buffers for the values of now.
; -----------------------------------------------------------------------------
hud_prepare:
                ld a,(scr_coarse)           ; the heavy frames: leave it to the
                or a                        ; next light one (speed < 8: there is
                ret nz                      ; one at least every 4 frames)
                call pu_scan                ; power-up cells for both slots
                MAP_RAM GA_RAM_C7           ; (the glyphs)
                call .slots
                MAP_RAM GA_RAM_C0
                ret
.slots:         ld ix,hud_slots
                ld b,HUD_SLOT_COUNT
.slot:          push bc
                call hud_slot_build         ; A = visible
                res 2,(ix+SL_STATE)
                or a
                jr z,.hidden
                set 2,(ix+SL_STATE)
.hidden:        ld de,SL_SIZE
                add ix,de
                pop bc
                djnz .slot
                ret

; every line the slots can reach (rarely: a new screen), panel colour
hud_clear_band:
                ld a,HUD_BAND_LAST-HUD_BAND_FIRST+1
                ld (hb_lines),a
                ld a,HUD_BAND_FIRST
                ld (hb_y),a
                ld a,HUD_PANEL_FIRST
                ld (hb_x),a
                ld a,HUD_PANEL_LAST-HUD_PANEL_FIRST+1
                ld (hb_w),a
                xor a
                ld (hb_stride),a
                ld hl,hud_panel_line
                jp hud_blit

hud_slot:
.call_hl:       jp (hl)

; IX = slot: rebuilds its buffer if the value changed. A = visible.
hud_slot_build:
                ld l,(ix+SL_KEY_FN)
                ld h,(ix+SL_KEY_FN+1)
                call hud_slot.call_hl       ; A = visible, hud_key
                or a
                ret z
                call .compare
                ld a,1
                ret
.compare:       ld a,(ix+SL_STATE)          ; buffer valid: only changed digits
                and 2
                ld (hud_partial),a
                jr z,.build
                ld a,(hud_key)
                cp (ix+SL_KEY)
                jr nz,.build
                ld a,(hud_key+1)
                cp (ix+SL_KEY+1)
                jr nz,.build
                ld a,(hud_key+2)
                cp (ix+SL_KEY+2)
                ret z
.build:         ld a,(ix+SL_KEY)            ; old value (put_bcd compares)
                ld (hud_old_key),a
                ld a,(ix+SL_KEY+1)
                ld (hud_old_key+1),a
                ld a,(ix+SL_KEY+2)
                ld (hud_old_key+2),a
                ld a,(hud_key)
                ld (ix+SL_KEY),a
                ld a,(hud_key+1)
                ld (ix+SL_KEY+1),a
                ld a,(hud_key+2)
                ld (ix+SL_KEY+2),a
                set 1,(ix+SL_STATE)
                ld l,(ix+SL_BUILD_FN)
                ld h,(ix+SL_BUILD_FN+1)
                jp (hl)

; -----------------------------------------------------------------------------
; hud_blit: copies hb_lines lines of hb_w bytes (1-18) from HL to screen line
; hb_y, column hb_x; hb_stride 0 repeats the same source line (fills).
; Per line: an unrolled LDI run entered by a patched JR (~17+5w us). Lines
; that cross the end of a 2K plane are copied byte by byte.
; -----------------------------------------------------------------------------
HB_LDI_MAX      equ 18

hud_blit:
                ld (.src),hl
                ld a,(hb_w)
                ld (spr_width),a            ; (row_base: plane-end test)
                neg
                add HB_LDI_MAX
                add a,a                     ; skip (16-w) LDIs of 2 bytes
                ld (.jump+1),a
                ld a,(hb_stride)            ; fill: rewind the source each line
                or a
                ld a,#21                    ; ld hl,src
                ld hl,(.src)
                jr z,.rewind
                ld a,#C3                    ; copy: jp to the next instruction
                ld hl,.reset+3
.rewind:        ld (.reset),a
                ld (.reset+1),hl
                ld a,(hb_y)                 ; picture line -> row, plane
                ld l,a
                ld h,0
                ld a,(cur_j)
                call add_a_hl
                ld a,l
                and 7
                ld (.plane),a
                srl h
                rr l
                srl l
                srl l
                ld a,l
                ld (.row),a
.row_start:     ld a,(hb_x)
                ld c,a
                ld a,(.row)
                call row_base               ; HL = plane 0 address, spr_wrap
.have_base:     ld (.base),hl
                ld a,(.plane)               ; DE = first line of this char row
                add a,a
                add a,a
                add a,a
                or h
                ld d,a
                ld e,l
                ld a,(.plane)               ; B = lines in this char row
                neg
                add 8
                ld b,a
                ld a,(hb_lines)
                cp b
                jr nc,.count
                ld b,a
.count:         ld a,(hb_lines)
                sub b
                ld (hb_lines),a
                ld hl,(.src)
                ld a,(spr_wrap)
                or a
                jp nz,.slow
                ld a,(hb_stride)            ; a fill within a 256-byte page:
                or a                        ; LD (HL),C : INC L
                jr nz,.copy
                ld a,(hb_w)
                add a,e
                jr c,.copy
                jr z,.copy
                ld a,(hb_w)                 ; SMC: skip (max - w) pairs of
                neg                         ; 1-byte instructions
                add HB_LDI_MAX
                add a,a
                ld (.fjump+1),a
                ld c,HUD_PANEL_BYTE
.fline:         ld h,d
                ld l,e
.fjump:         jr .fills                   ; SMC
.fills:         repeat HB_LDI_MAX
                ld (hl),c
                inc l
                rend
                ld a,d
                add 8
                ld d,a
                djnz .fline
                ld hl,(.src)
                jr .row_done
.copy:          ld c,255                    ; LDI decrements BC: keep B intact
                                            ; (8 lines of <= 18 bytes: C stays > 0)
.line:          push de
.jump:          jr .ldis                    ; SMC
.ldis:          repeat HB_LDI_MAX
                ldi
                rend
                pop de
.reset:         ld hl,0                     ; SMC: ld hl,src (fill) / jp $+3 (copy)
                ld a,d
                add 8
                ld d,a
                djnz .line
                jr .row_done

.slow:          push bc                     ; line crosses the plane end
                push de
                ex de,hl
                ld a,(hb_w)
                ld b,a
.slow_byte:     ld a,(de)
                ld (hl),a
                inc de
                call next_ring_byte
                djnz .slow_byte
                ex de,hl                    ; HL = source after the line
                ld a,(hb_stride)
                or a
                jr nz,.slow_next
                ld hl,(.src)
.slow_next:     pop de
                ld a,d
                add 8
                ld d,a
                pop bc
                djnz .slow

.row_done:      ld (.src),hl
                ld a,(hb_lines)
                or a
                ret z
                xor a
                ld (.plane),a
                ld hl,.row                  ; next char row
                inc (hl)
                ld a,(hl)
                cp ROWS_PER_BLOCK           ; into D2: from its start address
                jp z,.row_start
                ld hl,(.base)               ; same block: 96 bytes on in the ring
                ld a,h
                and #C0
                ld b,a
                ld a,l
                add ROW_BYTES
                ld l,a
                ld a,h
                adc 0
                and RING_MASK>>8
                or b
                ld h,a
                xor a                       ; wrap test (as row_base)
                ld (spr_wrap),a
                ld a,h
                and 7
                cp 7
                jp nz,.have_base
                ld a,l
                or a
                jp z,.have_base
                neg
                ld b,a
                ld a,(hb_w)
                cp b
                jp c,.have_base
                jp z,.have_base
                ld (spr_wrap),a
                jp .have_base
.src:           defw 0
.base:          defw 0
.plane:         defb 0
.row:           defb 0

; =============================================================================
; Slot contents. Key functions: A = visible (non-zero), hud_key = 3 bytes
; that identify what the buffer must show. Build functions: IX = slot.
; =============================================================================

key_score:
                ld hl,score
                jr key_copy3
key_hi:                                     ; the best score, or this one if higher
                ld hl,score+2
                ld de,hiscore_table+2       ; (BCD, most significant byte last)
                ld b,3
.cmp:           ld a,(de)
                cp (hl)
                jr c,key_score
                jr nz,.table
                dec hl
                dec de
                djnz .cmp
.table:         ld hl,hiscore_table
                jr key_copy3
key_coins:                                  ; coins (2 bytes), lives + route pixel * 8
                call route_pixel
                add a,a
                add a,a
                add a,a
                ld b,a
                ld a,(lives)
                or b
                ld (hud_key+2),a
                ld hl,coins
                ld de,hud_key
                ldi
                ldi
                or 1
                ret
key_copy3:      ld de,hud_key
                ldi
                ldi
                ldi
                or 1
                ret
; A = the runner's pixel on the route bar: 6 per station + rows / 64 (0-34)
route_pixel:
                ld hl,ROUTE_SEG
                ld de,(route_left)
                or a
                sbc hl,de
                add hl,hl
                add hl,hl                   ; H = rows into this stretch / 64
                ld a,(route_station)
                ld b,a
                add a,a
                add a,b
                add a,a
                add a,h
                ret
key_a:          ld (hud_key),a
                xor a
                ld (hud_key+1),a
                ld (hud_key+2),a
                or 1
                ret

; power-ups: a cell for each of the six, always (magnet, turbo, slow, springs
; in the first slot; helmet, ticket in the second). Key byte per cell: icon
; index + 1 in the high nibble (the dark icon when not running), bar pixels
; 0-8 in the low nibble.
key_pu_first:   ld hl,hud_cells
                jr key_pu
key_pu_second:  ld hl,hud_cells+HUD_PU_CELLS
key_pu:         ld de,hud_key
                ld bc,HUD_PU_CELLS
                ldir
                ld a,(hud_key)              ; visible if the first cell is used
                ret

; hud_cells: a cell for every power-up, in pu_hud_table order
pu_scan:
                ld de,hud_cells
                ld hl,pu_hud_table
                ld b,PU_HUD_COUNT
.entry:         push bc
                push hl
                ld c,(hl)                   ; timer
                inc hl
                ld b,(hl)
                inc hl
                ld a,b
                or c
                jr nz,.timed
                ld a,(helmet)               ; no timer: the helmet
                or a
                jr z,.off
                ld c,0                      ; no bar
                jr .active
.timed:         push hl                     ; frames left
                ld a,(bc)
                ld l,a
                inc bc
                ld a,(bc)
                ld h,a
                ex (sp),hl
                ld c,(hl)                   ; frames per bar pixel
                ex (sp),hl
                ld a,h
                or l
                jr z,.idle
                ld b,0                      ; pixels = ceil(frames / step)
.count:         inc b
                ld a,l
                sub c
                ld l,a
                jr nc,.more
                ld a,h
                or a
                jr z,.counted
                dec h
.more:          ld a,h
                or l
                jr nz,.count
.counted:       ld a,b
                cp 9
                jr c,.px
                ld a,8
.px:            ld c,a
                pop hl
                jr .active
.idle:          pop hl
.off:           inc hl                      ; the dark icon, no bar
                ld c,0
.active:        inc hl                      ; icon
                ld a,(hl)
                inc a
                add a,a
                add a,a
                add a,a
                add a,a
                or c
                ld (de),a
                inc de
                pop hl
                ld bc,PU_HUD_SIZE
                add hl,bc
                pop bc
                djnz .entry
                ret

PU_HUD_SIZE     equ 5                       ; timer, frames per pixel, icon, dark icon
pu_hud_table:   defw pu_magnet
                defb 32,IDX_HUD_ICONS_IC_MAGNET,IDX_HUD_ICONS_IC_MAGNET_OFF   ; 250 frames / 8 pixels
                defw pu_turbo
                defb 25,IDX_HUD_ICONS_IC_TURBO,IDX_HUD_ICONS_IC_TURBO_OFF
                defw pu_slow
                defb 25,IDX_HUD_ICONS_IC_SLOW,IDX_HUD_ICONS_IC_SLOW_OFF
                defw 0                              ; helmet (no timer)
                defb 0,IDX_HUD_ICONS_IC_HELMET,IDX_HUD_ICONS_IC_HELMET_OFF
                defw pu_spring
                defb 32,IDX_HUD_ICONS_IC_SPRING,IDX_HUD_ICONS_IC_SPRING_OFF
                defw pu_ticket
                defb 47,IDX_HUD_ICONS_IC_TICKET,IDX_HUD_ICONS_IC_TICKET_OFF
PU_HUD_COUNT    equ 6

; --- builders --------------------------------------------------------------------
build_score:                                ; 6 digits
                ld de,0
                ld hl,hud_key+2
                ld b,3
                jp put_bcd
build_hi:                                   ; the same in orange
                ld a,IDX_HUD_ICONS_H0
                ld (put_digit.base+1),a
                call build_score
                ld a,IDX_HUD_ICONS_D0
                ld (put_digit.base+1),a
                ret

; the route: stations, the stretch done in yellow, the runner in red
build_route:
                ld l,(ix+SL_BUF)
                ld h,(ix+SL_BUF+1)
                ld de,HUD_ROUTE_LINE*HUD_ROUTE_W
                add hl,de
                push hl
                ex de,hl
                ld hl,route_template
                ld bc,HUD_ROUTE_W*HUD_ROUTE_H
                ldir
                pop hl                      ; HL = buffer
                push hl
                ld a,(hud_key+2)            ; C = runner's pixel
                rrca
                rrca
                rrca
                and 31
                ld c,a
                srl a
                ld b,a                      ; B = whole yellow bytes
                ld de,HUD_ROUTE_W           ; the track: lines 1 and 2
                add hl,de
                push hl
                call .fill
                pop hl
                ld de,HUD_ROUTE_W
                add hl,de
                call .fill
                pop hl                      ; the runner: a red pixel column
                ld a,c
                srl a
                call add_a_hl
                ld de,#55A2                 ; even pixel: keep the right one
                bit 0,c
                jr z,.mark
                ld de,#AA51
.mark:          ld b,HUD_ROUTE_H
.mark_line:     ld a,(hl)
                and d
                or e
                ld (hl),a
                ld a,HUD_ROUTE_W
                call add_a_hl
                djnz .mark_line
                ret
.fill:          push bc
                ld a,b
                or a
                jr z,.half
.byte:          ld (hl),#FC                 ; yellow, yellow
                inc hl
                djnz .byte
.half:          pop bc
                bit 0,c
                ret z
                ld (hl),#AC                 ; yellow, grey
                ret

; the station ticks on line 0 (white on the panel, pixels 0, 6 .. 30 and
; 35), the track on 1 and 2 (grey); pens: blue #80/#40, white #88/#44,
; grey #08/#04
route_template:
                defb #C8,#C0,#C0,#C8,#C0,#C0,#C8,#C0,#C0,#C8,#C0,#C0,#C8,#C0,#C0,#C8,#C0,#C4
                defs HUD_ROUTE_W,#0C
                defs HUD_ROUTE_W,#0C

build_coins:                                ; coin + 4 digits, head + lives,
                ld a,(hud_partial)          ; the route under them
                or a
                jr nz,.digits
                call clear_buffer
                ld a,IDX_HUD_ICONS_IC_COIN
                ld de,0
                call put_icon
                ld a,IDX_HUD_ICONS_IC_LIFE
                ld de,12
                call put_icon
.digits:        ld de,4
                ld hl,hud_key+1
                ld b,2
                call put_bcd
                ld a,(hud_partial)          ; lives and route as they were?
                or a
                jr z,.lives
                ld a,(hud_key+2)
                ld hl,hud_old_key+2
                cp (hl)
                ret z
.lives:         ld a,(hud_key+2)
                and 7
                ld de,16
                call put_digit
                jp build_route

; power-up cells: icon, its time bar (up to 8 pixels) on the last line
build_pu:
                call clear_buffer
                ld hl,hud_key
                ld de,0
                ld b,HUD_PU_CELLS
.cell:          ld a,(hl)
                or a
                ret z
                push bc
                push hl
                push de
                rrca
                rrca
                rrca
                rrca
                and 15
                dec a
                call put_icon
                pop de
                pop hl
                push hl
                push de
                ld a,(hl)                   ; bar: 4 bytes on the icon's last line
                and 15                      ; (empty on every icon)
                add a,a
                add a,a
                ld hl,hud_bar_bytes
                call add_a_hl
                ex de,hl                    ; DE = pattern, HL = cell offset
                ld a,(ix+SL_W)
                ld c,a
                add a,a
                add a,a
                add a,a
                sub c                       ; line 7
                call add_a_hl
                ld a,(ix+SL_BUF)
                add a,l
                ld l,a
                ld a,(ix+SL_BUF+1)
                adc a,h
                ld h,a
                ex de,hl                    ; DE = buffer line 7, HL = pattern
                ld bc,4
                ldir
                pop de
                ld a,e
                add HUD_PU_CELL
                ld e,a
                pop hl
                inc hl
                pop bc
                djnz .cell
                ret

; bar patterns by filled pixels 0-8 (yellow on the panel), 4 bytes each:
; pen 7 left #A8 / right #54, pen 1 left #80 / right #40
hud_bar_bytes:
                defb #C0,#C0,#C0,#C0, #E8,#C0,#C0,#C0, #FC,#C0,#C0,#C0, #FC,#E8,#C0,#C0
                defb #FC,#FC,#C0,#C0, #FC,#FC,#E8,#C0, #FC,#FC,#FC,#C0, #FC,#FC,#FC,#E8
                defb #FC,#FC,#FC,#FC

put_icon:       ld c,4
                jr put_glyph

; HL = last (most significant) BCD byte in hud_key, B = bytes, DE = byte
; offset: 2*B digits, most significant first. With hud_partial set only
; the digits that differ from hud_old_key are drawn.
put_bcd:
.byte:          push bc
                push hl
                ld a,(hud_partial)
                or a
                ld c,#FF                    ; C = changed nibbles
                jr z,.changed
                push hl                     ; old byte: same offset in hud_old_key
                ld bc,hud_old_key-hud_key
                add hl,bc
                ld a,(hl)
                pop hl
                xor (hl)
                ld c,a
.changed:       ld a,c
                and #F0
                jr z,.low
                ld a,(hl)
                rrca
                rrca
                rrca
                rrca
                push bc
                push de
                call put_digit
                pop de
                pop bc
.low:           inc de
                inc de
                pop hl
                push hl
                ld a,c
                and #0F
                jr z,.next
                ld a,(hl)
                push de
                call put_digit
                pop de
.next:          inc de
                inc de
                pop hl
                dec hl
                pop bc
                djnz .byte
                ret

; A (low nibble) = digit, DE = byte offset
put_digit:
                and 15
.base:          add IDX_HUD_ICONS_D0        ; SMC: H0 for the best score
                ld c,2
                ; fall through
; A = glyph index, C = glyph width (bytes), DE = byte offset in the slot buffer
; (width SL_W). Destroys A, BC, DE, HL.
put_glyph:
                ld (.glyph),a
                ld a,4                      ; SMC: run of C LDIs (C = 1-4)
                sub c
                add a,a
                ld (.jump+1),a
                ld a,(ix+SL_W)              ; SMC: buffer stride after a line
                sub c
                ld (.stride+1),a
                push de
                ld a,(.glyph)
                ld hl,gfx_hud_icons_table
                call table_entry
                pop de
                push hl
                ld l,(ix+SL_BUF)
                ld h,(ix+SL_BUF+1)
                add hl,de
                ex de,hl                    ; DE = destination
                pop hl
                ld bc,8*256+255             ; B = lines (LDI only touches C)
.line:
.jump:          jr .ldis                    ; SMC
.ldis:          ldi
                ldi
                ldi
                ldi
                ld a,e
.stride:        add 0                       ; SMC
                ld e,a
                jr nc,.nc
                inc d
.nc:            djnz .line
                ret
.glyph:         defb 0

clear_buffer:
                ld l,(ix+SL_BUF)
                ld h,(ix+SL_BUF+1)
                ld b,(ix+SL_H)              ; W*H bytes
                xor a
.mul:           add a,(ix+SL_W)
                djnz .mul
                ld b,a
.byte:          ld (hl),HUD_PANEL_BYTE
                inc hl
                djnz .byte
                ret

; --- layout: y, x, w, buffer, key, build (top to bottom) -------------------------
macro SLOT_DEF y,x,w,h,buffer,key,build,cover
                defb {y},{x},{w},{h}
                defw {buffer},{key},{build}
                defb {cover}
mend

hud_layout:
                SLOT_DEF HUD_SCORE_Y,HUD_PANEL_FIRST+3,HUD_SCORE_W,8,hud_buf_score,key_score,build_score,1
                SLOT_DEF HUD_HI_Y,HUD_PANEL_FIRST+3,HUD_SCORE_W,8,hud_buf_hi,key_hi,build_hi,0
                SLOT_DEF HUD_COINS_Y,HUD_PANEL_FIRST,HUD_COINS_W,HUD_COINS_H,hud_buf_coins,key_coins,build_coins,0
                SLOT_DEF HUD_PU_Y,HUD_PU_X,HUD_PU_W,HUD_PU_H,hud_buf_pu,key_pu_first,build_pu,1
                SLOT_DEF HUD_PU_Y+HUD_PU_H,HUD_PU_X,HUD_PU_W,HUD_PU_H,hud_buf_pu+HUD_PU_W*HUD_PU_H,key_pu_second,build_pu,0
HUD_SLOT_COUNT  equ 5
                assert $-hud_layout == HUD_SLOT_COUNT*SL_KEY
                assert HUD_PU_Y+2*HUD_PU_H+HUD_STEP_MAX <= HUD_BAND_LAST+1
                assert HUD_COINS_Y+HUD_COINS_H <= HUD_PU_Y
                assert HUD_PANEL_FIRST+HUD_COINS_W-1 == HUD_PANEL_LAST

hud_panel_line: defs HUD_PANEL_LAST-HUD_PANEL_FIRST+1,HUD_PANEL_BYTE

; --- state ---------------------------------------------------------------------------
hud_q:          defw 0                  ; picture position at the last update
hud_fresh:      defb 1                  ; the screen was redrawn: nothing to clear
hud_step:       defb 0                  ; lines moved since the last update
hud_key:        defs 3
hud_old_key:    defs 3                  ; (right after hud_key: put_bcd)
hud_cells:   defs HUD_PU_CELLS*2
hud_partial:    defb 0
hud_run:        defw 0                  ; hud_update: first slot of a run
hud_run_n:      defb 0                  ; and its slots
hb_y:           defb 0
hb_x:           defb 0
hb_w:           defb 0
hb_lines:       defb 0
hb_stride:      defb 0
hud_slots:      defs HUD_SLOT_COUNT*SL_SIZE
; slot buffers: below the code (src/main.asm, from hud_buf_score)
hud_buf_hi      equ hud_buf_score+HUD_SCORE_W*8
hud_buf_coins   equ hud_buf_hi+HUD_SCORE_W*8
hud_buf_pu      equ hud_buf_coins+HUD_COINS_W*HUD_COINS_H
HUD_BUF_END     equ hud_buf_pu+2*HUD_PU_W*HUD_PU_H
