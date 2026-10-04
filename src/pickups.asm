; =============================================================================
; Collectibles and power-ups (plan.md 1.3).
;
; Items live in the row descriptors (D_ITEM) and are baked into the screen
; when their rows are drawn. The runner picks up the item of the cell under
; its feet (same probe as collide) if it is not more than one level above
; that cell: a coin on a roof needs the roof, a high jump flies over coins.
; A picked-up item is erased by redrawing the lane's track tile in its rows
; (coins 1 row, power-ups 2 rows). This happens between the sprite restores
; and the sprite draws, so no save buffer holds the old picture.
;
; Magnet: coins of the runner's lane and the lanes next to it that reach
; MAGNET_LINE leave the track and fly to the runner as sprites (at most
; FLYER_COUNT at a time). They stay below MAGNET_LINE, i.e. in D2, which the
; coarse step never copies from.
;
; Score (BCD, 6 digits): 1 point per row run (2 with turbo), 10 per coin
; (20 with the ticket).
; =============================================================================

ITEM_MAGNET     equ 2
ITEM_TURBO      equ 3
ITEM_SLOW       equ 4
ITEM_SPRING     equ 5
ITEM_HELMET     equ 6
ITEM_TICKET     equ 7

TURBO_EXTRA     equ 2                   ; turbo: base speed + 2 lines a frame
TURBO_MAX       equ 7                   ; (a coarse step every frame at 8)
COIN_POINTS     equ #10                 ; BCD

MAGNET_LINE     equ 176                 ; screen line where coins take off
FLYER_COUNT          equ 8
FLY_SIZE        equ 4
FLY_ACTIVE      equ 0
FLY_X           equ 1                   ; byte column
FLY_Y           equ 2                   ; (2) top screen line
FLY_STEP_Y      equ 24                  ; lines per game frame
FLY_STEP_X      equ 5                   ; bytes per game frame
FLY_SAVE_SIZE   equ 2+8*(2+COIN_W)
LABEL_Y         equ 112                 ; power-up name: top screen line
LABEL_BUF_SIZE  equ 8*24*FONT_W         ; a whole playfield line
LABEL_WAGONS    equ 8                   ; show_label: the hard mode hint (txt_pu_wagons),
LABEL_GO        equ 12                  ; then 3, 2, 1 (9-11) and GO!

; -----------------------------------------------------------------------------
; pickups_init: no score, no power-ups, no flying coins (new run).
; -----------------------------------------------------------------------------
pickups_init:
                ld hl,pickup_state
                ld de,pickup_state+1
                ld bc,PICKUP_STATE_SIZE-1
                ld (hl),0
                ldir
                ld hl,flyer_saves           ; width 0 = nothing to restore
                ld de,flyer_saves+1         ; (flyer_saves: src/main.asm)
                ld bc,FLYER_COUNT*FLY_SAVE_SIZE-1
                ld (hl),0
                ldir
                xor a
                ld (label_wait),a
                ld (erase_wait),a
                ret

; -----------------------------------------------------------------------------
; pickups: after collide, while running. Takes the item under the feet.
; -----------------------------------------------------------------------------
pickups:
                ld a,(no_pickups)           ; test/debug switch
                ld hl,(arc_ptr)             ; in the air: jumps over the items
                or h
                or l
                ret nz
                ld a,(probe_lane)
                ld hl,FEET_PROBE
                call cell_at
                call support_level
                ld b,a
                ld a,(player_z)             ; at most one level above the cell
                sub b
                ret c
                cp 2
                ret nc
                ld hl,(probe_row)
                call desc_addr
                ld a,(probe_lane)
                add D_ITEM
                call add_a_hl
                ld a,(hl)
                or a
                ret z
                ld (hl),0
                push af
                ld c,1                      ; coin: 1 row
                cp ITEM_COIN
                jr z,.erase
                ld a,(erase_wait)           ; power-up: 2 rows, in a light
                or a                        ; frame (late_erase) unless one
                jr nz,.now                  ; is already waiting
                inc a
                ld (erase_wait),a
                ld hl,(probe_row)
                ld (erase_row),hl
                ld a,(probe_lane)
                ld (erase_lane),a
                jr .erased
.now:           inc c
.erase:         ld hl,(probe_row)
                ld a,(probe_lane)
                call erase_item
.erased:        pop af
                cp ITEM_COIN
                jp z,collect_coin
                ; fall through

; -----------------------------------------------------------------------------
; activate_powerup: A = item 2..7.
; -----------------------------------------------------------------------------
activate_powerup:
                push af
                ld a,SFX_POWERUP
                ld (sfx_request),a
                pop af
                push af
                call make_label             ; its name in the middle of the screen
                pop af
                cp ITEM_HELMET
                jr nz,.timed
                ld (helmet),a               ; non-zero: one crash absorbed
                ret
.timed:         cp ITEM_TURBO               ; turbo and slow cancel each other
                jr nz,.not_turbo
                ld hl,0
                ld (pu_slow),hl
.not_turbo:     cp ITEM_SLOW
                jr nz,.not_slow
                ld hl,0
                ld (pu_turbo),hl
.not_slow:      sub ITEM_MAGNET
                add a,a
                ld e,a
                ld d,0
                ld hl,pu_durations
                add hl,de
                ld c,(hl)
                inc hl
                ld b,(hl)
                ld hl,pu_timers
                add hl,de
                ld (hl),c
                inc hl
                ld (hl),b
                ret

; game frames, by item 2..7 (helmet has no timer)
pu_durations:   defw 250,200,200,250,0,375  ; 10 s, 8 s, 8 s, 10 s, -, 15 s

; -----------------------------------------------------------------------------
; tick_powerups: one game frame off every running timer (paused while the
; runner is crashed).
; -----------------------------------------------------------------------------
tick_powerups:
                ld hl,pu_timers
                ld b,PU_TIMER_COUNT
.next:          ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,d
                or e
                jr z,.idle
                dec de
                ld (hl),d
                dec hl
                ld (hl),e
                inc hl
.idle:          inc hl
                djnz .next
                ret

; A = lines per game frame for the scroll: turbo, slow or the normal speed
current_speed:
                ld hl,(pu_slow)
                ld a,h
                or l
                ld a,(scroll_speed)
                jr z,.not_slow
                srl a                       ; slow: half
                ret
.not_slow:      ld hl,(pu_turbo)
                ld b,a
                ld a,h
                or l
                ld a,b
                ret z
                add TURBO_EXTRA             ; turbo: faster, at most TURBO_MAX
                cp TURBO_MAX+1
                ret c
                ld a,TURBO_MAX
                ret

; -----------------------------------------------------------------------------
; score_row: called for every row the world moves (coarse step).
; -----------------------------------------------------------------------------
score_row:
                ld hl,(distance)
                inc hl
                ld (distance),hl
                ld hl,(pu_turbo)            ; turbo: double distance points
                ld a,h
                or l
                ld a,1
                jr z,score_add
                inc a
                ; fall through

; A = BCD points (0-99) added to the 6-digit BCD score (saturates at 999999)
score_add:
                ld hl,score
                add a,(hl)
                daa
                ld (hl),a
                inc hl
                ld a,(hl)
                adc 0
                daa
                ld (hl),a
                inc hl
                ld a,(hl)
                adc 0
                daa
                ld (hl),a
                ret nc
                ld a,#99
                ld (hl),a
                dec hl
                ld (hl),a
                dec hl
                ld (hl),a
                ret

; a coin: +1 coin (BCD, saturates at 9999), +10 points (+20 with the ticket)
collect_coin:
                ld a,SFX_COIN
                ld (sfx_request),a
                ld hl,coins
                ld a,(hl)
                add 1
                daa
                ld (hl),a
                inc hl
                ld a,(hl)
                adc 0
                daa
                jr c,.full
                ld (hl),a
.full:          ld hl,(pu_ticket)
                ld a,h
                or l
                ld a,COIN_POINTS
                jr z,score_add
                ld a,COIN_POINTS*2
                jr score_add

; -----------------------------------------------------------------------------
; erase_item: HL = world row, A = lane, C = rows: redraws the lane's track
; tile in those rows (those on screen). 
; -----------------------------------------------------------------------------
erase_item:
                ld (.lane),a
                ld a,c                      ; coins: only the coin's bytes
                ld (.coin),a                ; (1 = coin, 2 = power-up)
                ld b,c
.row:           push bc
                push hl
                ex de,hl                    ; picture row = top - world row
                ld hl,(cur_top_row)
                or a
                sbc hl,de
                ld a,h
                or a
                jp nz,.next
                ld a,l
                cp PICTURE_ROWS
                jp nc,.next
                ld c,0                      ; DE = plane 0 address of the row
                call row_base
                ex de,hl
                ld a,(.lane)                ; column of the lane
                ld b,a
                add a,a
                add a,b
                add a,a
                add a,a
                add a,b
                add a,b                     ; lane * 14
                add COL_LANE1
                call ring_column
                pop hl
                push hl
                push de
                call desc_addr              ; tile of that lane
                ld a,(.lane)
                add D_LANES
                call add_a_hl
                ld a,(hl)
                MAP_RAM GA_RAM_C4
                ld hl,gfx_track_table
                call table_entry
                pop de
                ld a,(.coin)
                dec a
                jr nz,.whole
                push hl
                push de
                ld a,(LANE_BYTES-COIN_W)>>1 ; the coin's columns of the tile
                call add_a_hl
                ld a,(LANE_BYTES-COIN_W)>>1
                call ring_column
                ex de,hl
                ld c,COIN_W
                call ring_fits
                ex de,hl
                jr nz,.whole_coin
                pop af                      ; (drop the lane start)
                pop af
                ld a,8
.line:          push hl
                push de
                ldi
                ldi
                ldi
                ldi
                pop de
                pop hl
                ld bc,LANE_BYTES
                add hl,bc
                ex af,af'
                ld a,d
                add 8
                ld d,a
                ex af,af'
                dec a
                jr nz,.line
                jr .mapped
.whole_coin:    pop de                      ; crosses a plane end: whole lane
                pop hl
.whole:         ld c,LANE_BYTES
                call blit_tile
.mapped:        MAP_RAM GA_RAM_C0
.next:          pop hl
                inc hl
                pop bc
                dec b
                jp nz,.row
                ret
.lane:          defb 0
.coin:          defb 0

; -----------------------------------------------------------------------------
; magnet: while it runs, the coins near the runner's lane that reach
; MAGNET_LINE take off as flying sprites.
; -----------------------------------------------------------------------------
magnet:
                ld a,(no_pickups)
                or a
                ret nz
                ld hl,(pu_magnet)
                ld a,h
                or l
                ret z
                ld hl,MAGNET_LINE           ; world row at the magnet line
                ld a,(cur_j)
                add a,l
                ld l,a
                jr nc,.nc
                inc h
.nc:            srl h
                rr l
                srl l
                srl l
                ld a,l
                ld (.picture_row),a
                ex de,hl
                ld hl,(cur_top_row)
                or a
                sbc hl,de
                ld (.world_row),hl
                xor a
.lane:          ld (.lane_no),a
                ld b,a                      ; |lane - player_lane| <= 1
                ld a,(player_lane)
                sub b
                jr nc,.dist
                neg
.dist:          cp 2
                jr nc,.next_lane
                ld hl,(.world_row)
                call desc_addr
                ld a,(.lane_no)
                add D_ITEM
                call add_a_hl
                ld a,(hl)
                cp ITEM_COIN
                jr nz,.next_lane
                call free_flyer             ; IX = free slot, or NZ if none
                jr nz,.next_lane
                ld (hl),0
                ld (ix+FLY_ACTIVE),1
                ld a,(.lane_no)             ; coin column (as spawn_item)
                ld b,a
                add a,a
                add a,b
                add a,a
                add a,a
                add a,b
                add a,b
                add COL_LANE1+((LANE_BYTES-COIN_W)>>1)
                ld (ix+FLY_X),a
                ld a,(.picture_row)         ; top line = row*8 - j
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(cur_j)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                ld (ix+FLY_Y),l
                ld (ix+FLY_Y+1),h
                ld hl,(.world_row)
                ld a,(.lane_no)
                ld c,1
                call erase_item
.next_lane:     ld a,(.lane_no)
                inc a
                cp 3
                jr nz,.lane
                ret
.picture_row:   defb 0
.world_row:     defw 0
.lane_no:       defb 0

; IX = a free flyer slot (Z), or NZ if all are flying. Destroys A, B, DE.
free_flyer:
                ld ix,flyers
                ld de,FLY_SIZE
                ld b,FLYER_COUNT
.slot:          ld a,(ix+FLY_ACTIVE)
                or a
                ret z
                add ix,de
                djnz .slot
                or 1
                ret

; -----------------------------------------------------------------------------
; move_flyers: every flying coin heads for the runner's chest; it is
; collected when it gets there.
; -----------------------------------------------------------------------------
move_flyers:
                ld a,(player_z)             ; target line = FOOT_Y-2z-14
                add a,a
                neg
                add (FOOT_Y-14) & #FF
                ld (.target_y),a            ; (high byte is 0 for every z)
                ld a,(player_centre)
                sub COIN_W/2
                ld (.target_x),a
                ld ix,flyers
                ld b,FLYER_COUNT
.slot:          push bc
                ld a,(ix+FLY_ACTIVE)
                or a
                jr z,.next
                ld c,0                      ; C = axes still on their way
                ld a,(.target_x)            ; x: FLY_STEP_X towards the target
                sub (ix+FLY_X)
                jr z,.x_done
                inc c
                jr c,.left
                cp FLY_STEP_X
                jr c,.x_add
                ld a,FLY_STEP_X
.x_add:         add a,(ix+FLY_X)
                ld (ix+FLY_X),a
                jr .x_done
.left:          neg
                cp FLY_STEP_X
                jr c,.x_sub
                ld a,FLY_STEP_X
.x_sub:         ld b,a
                ld a,(ix+FLY_X)
                sub b
                ld (ix+FLY_X),a
.x_done:        ld l,(ix+FLY_Y)             ; y: down, FLY_STEP_Y at a time
                ld h,(ix+FLY_Y+1)
                ld a,(.target_y)
                ld e,a
                ld d,0
                ex de,hl
                or a
                sbc hl,de                   ; HL = target - y
                jr c,.y_done                ; already below: stay
                jr z,.y_done
                inc c
                ld a,h
                or a
                jr nz,.y_step
                ld a,l
                cp FLY_STEP_Y
                jr c,.y_add
.y_step:        ld hl,FLY_STEP_Y
.y_add:         add hl,de
                ld (ix+FLY_Y),l
                ld (ix+FLY_Y+1),h
.y_done:        ld a,c
                or a
                jr nz,.next
                ld (ix+FLY_ACTIVE),0        ; arrived
                call collect_coin
.next:          ld de,FLY_SIZE
                add ix,de
                pop bc
                djnz .slot
                ret
.target_y:      defb 0
.target_x:      defb 0

; -----------------------------------------------------------------------------
; Power-up name: written once on the track, centred on the playfield. It is
; part of the picture from then on: it scrolls down with the rows (copy_row
; takes it on to D2) and costs nothing afterwards. make_label (pickup frame)
; only takes note; draw_label does the work in two frames without a coarse
; step (the light ones): it builds the picture in label_buf, then copies it
; LABEL_Y lines down, plus the lines the world moved since the pickup.
; -----------------------------------------------------------------------------
make_label:                                 ; A = item 2..7
                ld (label_item),a
                call world_line
                ld (label_line),hl
                ld a,1
                ld (label_wait),a
                ret

; C if this frame's scroll_step will make a coarse step (a heavy frame)
coarse_ahead:
                call current_speed
                ld b,a
                ld a,(scr_j)
                cp b
                ret

; late_erase: the picked-up power-up (pickups) off the screen, in a frame
; without a coarse step; the runner hides it meanwhile. Between the sprite
; restores and draws.
late_erase:
                ld a,(erase_wait)
                or a
                ret z
                call coarse_ahead
                ret c
                xor a
                ld (erase_wait),a
                ld hl,(erase_row)
                ld a,(erase_lane)
                ld c,2
                jp erase_item

draw_label:                                 ; between the sprite restores and draws
                ld a,(label_wait)
                or a
                ret z
                call coarse_ahead           ; a coarse step ahead: not now
                ret c
                ld a,(label_wait)
                dec a
                jr nz,.copy
                inc a                       ; 1: build
                inc a
                ld (label_wait),a
                jr build_label
.copy:          xor a                       ; 2: copy
                ld (label_wait),a
                call world_line             ; lines moved since the pickup
                ld de,(label_line)
                or a
                sbc hl,de
                ld a,l
                add LABEL_Y
                ld c,a
; C = screen line: label_buf there, centred on the playfield
blit_label:
                ld a,(label_w)
                ld d,a
                neg
                add 72                      ; centred on the playfield
                srl a
                ld b,a
                ld e,8
                ld hl,label_buf
                jp blit_static

; A = label (item 2-7, LABEL_*), C = screen line: written there at once
; (the world stands still: the countdown)
show_label:
                ld (label_item),a
                push bc
                call build_label
                pop bc
                jr blit_label

; label_item's name -> label_buf (8 lines of label_w bytes)
build_label:
                ld a,(label_item)
                sub ITEM_MAGNET
                add a,a
                ld hl,txt_pu_magnet         ; txt_pu_* in item order
                call add_a_hl
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                MAP_RAM GA_RAM_C7
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
.built:         MAP_RAM GA_RAM_C0
                ret
.skip:          defw 0

; HL = position of the picture shown, in lines (grows as the world moves)
world_line:
                ld hl,(cur_top_row)
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(cur_j)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                ret

erase_wait:     defb 0                  ; late_erase
erase_row:      defw 0
erase_lane:     defb 0
label_item:     defb 0
label_w:        defb 0
label_line:     defw 0
label_wait:     defb 0

; -----------------------------------------------------------------------------
; restore_flyers / draw_flyers: like the runner, around the frame's work.
; Restored in reverse drawing order.
; -----------------------------------------------------------------------------
restore_flyers:
                ld hl,flyer_saves+(FLYER_COUNT-1)*FLY_SAVE_SIZE
                ld b,FLYER_COUNT
.slot:          push bc
                push hl
                call restore_sprite
                pop hl
                ld de,-FLY_SAVE_SIZE
                add hl,de
                pop bc
                djnz .slot
                ret

draw_flyers:
                MAP_RAM GA_RAM_C5
                ld a,(anim_tick)            ; spinning coin: coin0..coin3
                rra
                and 3
                ld (.frame),a
                ld hl,gfx_coin_code_table
                call table_entry
                ld (.code),hl
                ld a,(.frame)
                ld hl,gfx_items_table
                call table_entry
                ld (.sprite),hl
                ld ix,flyers
                ld iy,flyer_saves
                ld b,FLYER_COUNT
.slot:          push bc
                ld a,(ix+FLY_ACTIVE)
                or a
                jr z,.next
                push ix
                ld l,(ix+FLY_Y)
                ld h,(ix+FLY_Y+1)
                ld c,(ix+FLY_X)
                ld ix,(.sprite)
                ld de,(.code)
                ld a,GA_RAM_C5              ; (code in main RAM)
                call draw_compiled
                pop ix
.next:          ld de,FLY_SIZE
                add ix,de
                ld de,FLY_SAVE_SIZE
                add iy,de
                pop bc
                djnz .slot
                MAP_RAM GA_RAM_C0
                ret
.frame:         defb 0
.sprite:        defw 0
.code:          defw 0

                include "data/gfx_coin_code.asm"

; --- state (cleared by pickups_init) -------------------------------------------
pickup_state:
score:          defs 3                  ; BCD, low byte first
coins:          defs 2                  ; BCD, low byte first
distance:       defw 0                  ; rows run
helmet:         defb 0                  ; non-zero: the next crash is absorbed
pu_timers:                              ; game frames left, by item 2..7
pu_magnet:      defw 0
pu_turbo:       defw 0
pu_slow:        defw 0
pu_spring:      defw 0
pu_helmet:      defw 0                  ; (unused: the helmet has no timer)
pu_ticket:      defw 0
PU_TIMER_COUNT       equ ($-pu_timers)/2
flyers:         defs FLYER_COUNT*FLY_SIZE
PICKUP_STATE_SIZE equ $-pickup_state
no_pickups:     defb 0                  ; debug: items are never picked up
