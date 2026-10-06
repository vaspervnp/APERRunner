; =============================================================================
; HUD slot contents, in bank C7 with the font and the icons (hud_prepare maps
; it). Key functions: A = visible (non-zero), hud_key = 3 bytes that identify
; what the buffer must show. Build functions: IX = slot. (src/hud.asm)
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


; label_item's name -> label_buf (8 lines of label_w bytes); src/pickups.asm
; build_label maps this bank
build_label_c7:
                ld a,(label_item)
                sub ITEM_MAGNET
                add a,a
                ld hl,txt_pu_magnet         ; txt_pu_* in item order
                call add_a_hl
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                push hl
                ld b,0                      ; B = glyphs
.count:         ld a,(hl)
                cp TXT_END
                jr z,.counted
                inc b
                inc hl
                jr .count
.counted:       pop hl
                ld a,b
                add a,a
                add a,b
                ld (label_w),a              ; bytes = 3 * glyphs
                sub FONT_W
                ld (.skip),a                ; to the glyph's next line
                ld de,label_buf
.glyph:         ld a,(hl)
                cp TXT_END
                jr z,.built
                push hl
                push de
                ld hl,gfx_font_table
                call table_entry            ; HL = 8 lines of 3 bytes
                pop de
                push de
                ld a,8
.line:          ldi
                ldi
                ldi
                ex de,hl
                ld bc,(.skip)               ; (high byte: .skip+1 = 0)
                add hl,bc
                ex de,hl
                dec a
                jr nz,.line
                pop de
                inc de
                inc de
                inc de
                pop hl
                inc hl
                jr .glyph
.built:         ret
.skip:          defw 0

