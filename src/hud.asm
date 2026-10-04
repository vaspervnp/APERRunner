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
; pen 1); the glyphs (tools/assets.py "panel" kind) are opaque with that
; colour, so a slot never reads the screen.
; =============================================================================

HUD_PANEL_BYTE  equ #C0                 ; two pixels of pen 1
HUD_PANEL_FIRST equ COL_HUD+4
HUD_PANEL_LAST  equ COL_HUD+18
HUD_MAX_W       equ 15                  ; bytes
HUD_STEP_MAX    equ 16                  ; (2 frames at top speed) larger: wipe the panel
HUD_BAND_FIRST  equ 56                  ; screen lines the slots can reach
HUD_BAND_LAST   equ 167

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
                                        ; bit2 shown this frame
SL_SIZE         equ 15

; layout (exported to the symbol file for the tests). Slots of a group touch,
; so only the lines below the last shown one of a group need clearing.
HUD_SCORE_Y     equ 64
HUD_COINS_Y     equ 72
HUD_LIVES_Y     equ 80
HUD_PU_Y        equ 96                  ; first power-up row
HUD_PU_CELLS    equ 3                       ; power-up cells per slot
HUD_PU_W        equ HUD_PU_CELLS*4
HUD_PU_H        equ 10                      ; icon + 2-line bar
HUD_PU_X        equ HUD_PANEL_FIRST+1
HUD_LIVES_W     equ 6                       ; head + digit

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

                ld ix,hud_slots             ; clear what scrolled out
                ld b,HUD_SLOT_COUNT
.clear:         push bc
                call hud_slot_clear
                ld de,SL_SIZE
                add ix,de
                pop bc
                djnz .clear
                ld ix,hud_slots             ; draw runs of touching shown slots,
                ld b,HUD_SLOT_COUNT         ; top to bottom, ahead of the beam
.slot:          res 0,(ix+SL_STATE)
                bit 2,(ix+SL_STATE)
                jr z,.next
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
                ld a,c
                add a,(ix+SL_H)
                ld c,a
                jr .extend
.run:           ld a,c
                ld (hb_lines),a
                push bc
                call hud_blit
                pop bc
.next:          ld de,SL_SIZE
                add ix,de
                djnz .slot
                ret

; IX = slot drawn last frame: clear the lines its old picture moved to that
; this frame's drawing will not cover.
hud_slot_clear:
                bit 0,(ix+SL_STATE)
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
                ld ix,hud_slots
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
; hud_blit: copies hb_lines lines of hb_w bytes (1-16) from HL to screen line
; hb_y, column hb_x; hb_stride 0 repeats the same source line (fills).
; Per line: an unrolled LDI run entered by a patched JR (~17+5w us). Lines
; that cross the end of a 2K plane are copied byte by byte.
; -----------------------------------------------------------------------------
HB_LDI_MAX      equ 16

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
                jr nz,.slow
                ld c,255                    ; LDI decrements BC: keep B intact
.line:          push de
.jump:          jr .ldis                    ; SMC
.ldis:          repeat HB_LDI_MAX
                ldi
                rend
                pop de
.reset:         ld hl,0                     ; SMC: ld hl,src (fill) / jp $+3 (copy)
                ld c,255
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
key_coins:
                ld hl,coins                 ; 2 bytes
                ld de,hud_key
                ldi
                ldi
                xor a
                ld (de),a
                or 1
                ret
key_copy3:      ld de,hud_key
                ldi
                ldi
                ldi
                or 1
                ret
key_lives:
                ld a,(lives)
                jr key_a
key_a:          ld (hud_key),a
                xor a
                ld (hud_key+1),a
                ld (hud_key+2),a
                or 1
                ret

; power-ups: cells of up to 3 active ones per slot (magnet, turbo, slow,
; springs, helmet, ticket in that order). Key byte per cell: icon index + 1
; in the high nibble (0 = empty), bar pixels 0-8 in the low nibble.
key_pu_first:   ld hl,hud_cells
                jr key_pu
key_pu_second:  ld hl,hud_cells+HUD_PU_CELLS
key_pu:         ld de,hud_key
                ld bc,HUD_PU_CELLS
                ldir
                ld a,(hud_key)              ; visible if the first cell is used
                ret

; hud_cells: the cells of every active power-up, in order
pu_scan:
                ld hl,hud_cells
                ld b,HUD_PU_CELLS*2
.clear:         ld (hl),0
                inc hl
                djnz .clear
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
                jr z,.skip_entry
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
                jr .skip_entry
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
.skip_entry:    pop hl
                ld bc,PU_HUD_SIZE
                add hl,bc
                pop bc
                djnz .entry
                ret

PU_HUD_SIZE     equ 4
pu_hud_table:   defw pu_magnet
                defb 32,IDX_HUD_ICONS_IC_MAGNET     ; 250 frames / 8 pixels
                defw pu_turbo
                defb 25,IDX_HUD_ICONS_IC_TURBO
                defw pu_slow
                defb 25,IDX_HUD_ICONS_IC_SLOW
                defw pu_spring
                defb 32,IDX_HUD_ICONS_IC_SPRING
                defw 0                              ; helmet (no timer)
                defb 0,IDX_HUD_ICONS_IC_HELMET
                defw pu_ticket
                defb 47,IDX_HUD_ICONS_IC_TICKET
PU_HUD_COUNT    equ 6

; --- builders --------------------------------------------------------------------
build_score:                                ; 6 digits
                ld de,0
                ld hl,hud_key+2
                ld b,3
                jp put_bcd

build_coins:                                ; coin icon + 4 digits
                ld a,IDX_HUD_ICONS_IC_COIN
                ld de,0
                call put_icon
                ld de,4
                ld hl,hud_key+1
                ld b,2
                jp put_bcd

build_lives:                                ; head + number of lives
                ld a,IDX_HUD_ICONS_IC_LIFE
                ld de,0
                call put_icon
                ld a,(hud_key)
                ld de,4
                jp put_digit

; power-up cells: icon, then a 2-line bar of up to 8 pixels under it
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
                ld a,(hl)                   ; bar: 2 lines of 4 bytes at line 8
                and 15
                add a,a
                add a,a
                ld hl,hud_bar_bytes
                call add_a_hl
                ex de,hl                    ; DE = pattern, HL = cell offset
                ld a,(ix+SL_W)
                add a,a
                add a,a
                add a,a
                call add_a_hl
                ld a,(ix+SL_BUF)
                add a,l
                ld l,a
                ld a,(ix+SL_BUF+1)
                adc a,h
                ld h,a
                ex de,hl                    ; DE = buffer line 8, HL = pattern
                push hl
                ld bc,4
                ldir
                pop hl
                ld a,(ix+SL_W)              ; line 9
                sub 4
                add a,e
                ld e,a
                jr nc,.nc
                inc d
.nc:            ld bc,4
                ldir
                pop de
                ld a,e
                add 4
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
                add IDX_HUD_ICONS_D0
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
                SLOT_DEF HUD_SCORE_Y,HUD_PANEL_FIRST+1,12,8,hud_buf_score,key_score,build_score,1
                SLOT_DEF HUD_COINS_Y,HUD_PANEL_FIRST+1,12,8,hud_buf_coins,key_coins,build_coins,0
                SLOT_DEF HUD_LIVES_Y,HUD_PANEL_FIRST+1,HUD_LIVES_W,8,hud_buf_lives,key_lives,build_lives,0
                SLOT_DEF HUD_PU_Y,HUD_PU_X,HUD_PU_W,HUD_PU_H,hud_buf_pu,key_pu_first,build_pu,1
                SLOT_DEF HUD_PU_Y+HUD_PU_H,HUD_PU_X,HUD_PU_W,HUD_PU_H,hud_buf_pu+HUD_PU_W*HUD_PU_H,key_pu_second,build_pu,0
HUD_SLOT_COUNT  equ 5
                assert $-hud_layout == HUD_SLOT_COUNT*SL_KEY
                assert HUD_PU_Y+HUD_PU_H*2+HUD_STEP_MAX <= HUD_BAND_LAST+1

hud_panel_line: defs HUD_PANEL_LAST-HUD_PANEL_FIRST+1,HUD_PANEL_BYTE

; --- state ---------------------------------------------------------------------------
hud_q:          defw 0                  ; picture position at the last update
hud_fresh:      defb 1                  ; the screen was redrawn: nothing to clear
hud_step:       defb 0                  ; lines moved since the last update
hud_key:        defs 3
hud_old_key:    defs 3                  ; (right after hud_key: put_bcd)
hud_cells:   defs HUD_PU_CELLS*2
hud_partial:    defb 0
hb_y:           defb 0
hb_x:           defb 0
hb_w:           defb 0
hb_lines:       defb 0
hb_stride:      defb 0
hud_slots:      defs HUD_SLOT_COUNT*SL_SIZE
hud_buf_score:  defs 12*8
hud_buf_coins:  defs 12*8
hud_buf_lives:  defs HUD_LIVES_W*8
hud_buf_pu:     defs 2*HUD_PU_W*HUD_PU_H
