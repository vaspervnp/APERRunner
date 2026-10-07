; =============================================================================
; coins_c5.asm - spinning coins (bank C5; chunk_prewarm calls it every frame)
;
; In a frame without a coarse step, or after a frame loaded up to
; COIN_SPIN_LOAD, up to COIN_SPIN_N coins on the picture turn: the coin's 4
; bytes x 8 lines over its lane tile, ready made by png2cpc
; (src/data/gfx_coin_bg.asm), its frame from the time, its row and lane (a
; wave, not all at once). The picture rows are looked at from where the
; last frame stopped, COIN_SPIN_ROWS at most, above the runner's rows (its
; sprite keeps what is under it), not under a bridge deck nor by a name
; written on the track.
; =============================================================================

COIN_SPIN_N     equ 3                       ; coins a frame
COIN_SPIN_ROWS  equ 6                       ; picture rows looked at a frame
COIN_SPIN_LAST  equ 25                      ; the last picture row (above the runner)
COIN_SPIN_LOAD  equ 8                       ; in a coarse frame after one this loaded
COIN_SPIN_OVER  equ 12                      ; never after an overrun (its HUD catches up)

coin_spin:
                ld a,(frame_load)           ; the last frame's load
                ld b,a
                ld a,(scr_coarse)
                or a
                ld a,b
                jr z,.light
                cp COIN_SPIN_LOAD+1
                ret nc
.light:         cp COIN_SPIN_OVER
                ret nc
                ld a,COIN_SPIN_N
                ld (cs_left),a
                ld a,COIN_SPIN_ROWS
                ld (cs_rows),a
                ld hl,(label_line)          ; a name on the track: its world row
                ld de,-LABEL_Y
                add hl,de
                call hl_rows
                ld (cs_label),hl
.row:           ld a,(cs_row)               ; the next picture row
                inc a
                cp COIN_SPIN_LAST+1
                jr c,.in
                xor a
.in:            ld (cs_row),a
                ld e,a
                ld d,0
                ld hl,(cur_top_row)
                or a
                sbc hl,de                   ; HL = its world row
                jr c,.next
                ld (cs_world),hl
                ld de,(cs_label)            ; by the name (its rows - 3 .. + 1)?
                or a
                sbc hl,de
                ld de,3
                add hl,de
                ld a,h
                or a
                jr nz,.look
                ld a,l
                cp 5
                jr c,.next
.look:          ld hl,(cs_world)
                call desc_addr
                bit 7,(hl)                  ; F_BRIDGE: under the deck
                jr nz,.next
                ld (cs_desc),hl
                ld de,D_ITEM
                add hl,de                   ; HL = its 3 items
                ld b,0
.lane:          ld a,(hl)
                cp ITEM_COIN
                jr nz,.no_coin
                push hl
                push bc
                call .spin
                pop bc
                pop hl
                ld a,(cs_left)
                or a
                ret z
.no_coin:       inc hl
                inc b
                ld a,b
                cp 3
                jr c,.lane
.next:          ld hl,cs_rows
                dec (hl)
                jr nz,.row
                ret

; B = lane of a coin in the row: its next frame
.spin:          ld a,b
                ld (cs_lane),a
                add D_LANES
                ld hl,(cs_desc)
                call add_a_hl
                ld a,(hl)                   ; the tile under it
                ld hl,gfx_coin_bg_table
                call table_entry
                ld a,h
                or l
                ret z                       ; (none ready for it)
                ld a,(anim_tick)            ; its frame
                rra
                ld c,a
                ld a,(cs_row)
                add a,c
                ld c,a
                ld a,(cs_lane)
                add a,c
                and GFX_COIN_BG_FRAMES-1
                rrca                        ; * 32 bytes
                rrca
                rrca
                call add_a_hl
                push hl
                ld a,COIN_W
                ld (spr_width),a
                ld a,(cs_lane)              ; its column: as spawn_item
                ld b,a
                add a,a
                add a,b
                add a,a
                add a,a
                add a,b
                add a,b                     ; lane * 14
                add COL_LANE1+((LANE_BYTES-COIN_W)>>1)
                ld c,a
                ld a,(cs_row)
                call row_base               ; HL = its top line
                ex de,hl
                pop hl
                call coin_put
                ld hl,cs_left
                dec (hl)
                ret

; -----------------------------------------------------------------------------
; coins_row: render_row (bank C5 mapped) draws the coins of its new row, IX
; = descriptor, from the same ready-made frames (no overlay for a coin). A
; coin under a bridge deck stays hidden (it is still there to pick up).
; -----------------------------------------------------------------------------
coins_row:
                bit 7,(ix+D_FLAGS)          ; under a bridge deck: hidden
                ret nz
                ld b,0
.lane:          ld a,b
                add D_ITEM
                ld e,a
                ld d,0
                push ix
                pop hl
                add hl,de
                ld a,(hl)
                cp ITEM_COIN
                jr nz,.next
                push bc
                ld de,D_LANES-D_ITEM
                add hl,de
                ld a,(hl)                   ; the tile under it
                ld hl,gfx_coin_bg_table
                call table_entry
                pop bc
                ld a,h
                or l
                jr z,.next
                ld a,(render_row.row)       ; a frame from its row and lane
                add a,b
                and GFX_COIN_BG_FRAMES-1
                rrca                        ; * 32 bytes
                rrca
                rrca
                call add_a_hl
                push bc
                push hl
                ld a,b                      ; its column: as spawn_item
                add a,a
                add a,b
                add a,a
                add a,a
                add a,b
                add a,b                     ; lane * 14
                add COL_LANE1+((LANE_BYTES-COIN_W)>>1)
                ld de,(render_row.dest)
                call ring_column
                pop hl
                call coin_put
                pop bc
.next:          inc b
                ld a,b
                cp 3
                jr c,.lane
                ret

; HL = a coin's 4 bytes x 8 lines, DE = plane 0 address of its top line
coin_put:
                push hl
                ex de,hl
                ld c,COIN_W
                call ring_fits              ; NZ: across a plane end
                ex de,hl
                pop hl
                ld b,8
                jr nz,.wrap
                ld c,#FF                    ; (LDI counts BC down: B stays)
.line:          push de
                ldi
                ldi
                ldi
                ldi
                pop de
                ld a,d                      ; the next line: a plane on
                add 8
                ld d,a
                djnz .line
                ret
.wrap:          push bc
                push de
                ld c,COIN_W
                call ring_put
                pop de
                ld a,d
                add 8
                ld d,a
                pop bc
                djnz .wrap
                ret

cs_left:        defb 0                      ; coins still to turn this frame
cs_rows:        defb 0                      ; rows still to look at
cs_row:         defb 0                      ; the picture row (from the last frame)
cs_lane:        defb 0
cs_world:       defw 0
cs_desc:        defw 0
cs_label:       defw 0                      ; the name's world row
