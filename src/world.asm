; =============================================================================
; World: generates one map row at a time (world row n, growing upwards) and
; draws it into screen memory.
;
;   generate_row  - fills the row descriptor in world_ring (n & 63):
;                   environment (urban/forest + 2-row transitions), side tiles,
;                   bridges, track lanes from chunks (levels/chunks), scenery
;                   and item overlays.
;   render_row    - tiles (bank C4) + the part of every active overlay that
;                   falls in this row (sprites, bank C5).
;
; Overlays (cars, trees, coins, power-ups) are registered when their BOTTOM
; row is generated; rows are generated bottom-up, so each later row draws its
; slice and the overlay is freed after its top row.
; =============================================================================

; --- row descriptor -------------------------------------------------------------
ROW_SIZE        equ 16
RING_ROWS       equ 64                  ; power of two
D_FLAGS         equ 0                   ; bit0 forest tile set, bit6 overlay drawn, bit7 bridge
D_LEFT          equ 1                   ; side tile index (or bridge tile index)
D_RIGHT         equ 2                   ; side tile index (mirrored entries)
D_LANES         equ 3                   ; 3 track tile indices
D_COLL          equ 6                   ; 3 collision classes (see tools/mklevel.py)
D_ITEM          equ 9                   ; 3 items
F_FOREST        equ 1
F_OVERLAY       equ #40
F_BRIDGE        equ #80

; collision classes (low nibble), high nibble = ramp row
COL_NONE        equ 0
COL_STOP        equ 1
COL_SIGNAL      equ 2
COL_TRAIN       equ 3
COL_NOSE        equ 4
COL_RAMP_UP     equ 5
COL_RAMP_DOWN   equ 6

ITEM_COIN       equ 1
COIN_W          equ 4                   ; bytes
POWERUP_W       equ 6

; --- overlays -----------------------------------------------------------------------
OVERLAYS        equ 16
OV_SIZE         equ 8
OV_BOTTOM       equ 0                   ; world row (2)
OV_ROWS         equ 2                   ; 0 = free slot
OV_COLUMN       equ 3
OV_SPRITE       equ 4                   ; (2) sprite in bank C5

; --- layout ---------------------------------------------------------------------------
COL_LEFT        equ 0
COL_LANE1       equ 15
COL_RIGHT       equ 57
COL_HUD         equ 72
SIDE_BYTES      equ 15
LANE_BYTES      equ 14
PLAYFIELD_W     equ 72

ENV_URBAN       equ 0
ENV_FOREST      equ 1
SEGMENT_MIN     equ 96                  ; rows per environment: 96..159
BRIDGE_GAP_MIN  equ 80                  ; rows between bridges: 80..207
SCENERY_MARGIN  equ 6                   ; no scenery this close to a bridge/transition

WORLD_RING      equ #0400               ; 64 x 16 bytes (main RAM, below the code)
OVERLAY_LIST    equ #0800

; -----------------------------------------------------------------------------
; world_init: clears the ring, overlays and generator state.
; -----------------------------------------------------------------------------
world_init:
                ld hl,WORLD_RING
                ld de,WORLD_RING+1
                ld bc,RING_ROWS*ROW_SIZE+OVERLAYS*OV_SIZE-1
                ld (hl),0
                ldir
                ld hl,gen_state
                ld de,gen_state+1
                ld bc,GEN_STATE_SIZE-1
                ld (hl),0
                ldir
                ld hl,#ACE1
                ld (rng),hl
                ld hl,SEGMENT_MIN
                ld (seg_left),hl
                ld hl,BRIDGE_GAP_MIN/2
                ld (bridge_countdown),hl
                ld a,24
                ld (cross_countdown),a
                ld a,30
                ld (kiosk_countdown),a
                ld a,50
                ld (kiosk_countdown+1),a
                ret

; -----------------------------------------------------------------------------
; draw_world_row: HL = world row number, DE = destination plane 0 address.
; Rows must be generated in increasing order.
; -----------------------------------------------------------------------------
draw_world_row:
                push de
                push hl
                call generate_row
                pop hl
                pop de
                jp render_row

; HL = world row -> HL = its descriptor. Destroys A, DE.
desc_addr:
                ld a,l
                and RING_ROWS-1
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,WORLD_RING
                add hl,de
                ret

; -----------------------------------------------------------------------------
; random: A = next pseudo-random byte (xorshift16). Destroys nothing else.
; -----------------------------------------------------------------------------
random:
                push hl
                ld hl,(rng)
                ld a,h                      ; x ^= x << 7
                rra
                ld a,l
                rra
                xor h
                ld h,a
                ld a,l
                rra
                ld a,h                      ; x ^= x >> 9
                rra
                xor l
                ld l,a
                xor h                       ; x ^= x << 8
                ld h,a
                ld (rng),hl
                pop hl
                ret

; A = random number in 0..C-1 (C = 1..255). Destroys nothing else.
random_below:
                call random
                jp mod_c

; A = A mod C (C > 0). Destroys nothing else.
mod_c:
                sub c
                jr nc,mod_c
                add a,c
                ret

; HL = word at table HL + 2*A. Destroys A, DE.
table_entry:
                add a,a
                ld e,a
                ld d,0
                add hl,de
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ret

; =============================================================================
; generate_row: HL = world row number
; =============================================================================
generate_row:
                ld (gen_row),hl
                call desc_addr
                push hl
                pop ix
                ld b,ROW_SIZE               ; clear the descriptor
                xor a
.clear:         ld (hl),a
                inc hl
                djnz .clear

                ; difficulty 1..5 grows every 256 rows
                ld a,(gen_row+1)
                inc a
                cp 6
                jr c,.diff_ok
                ld a,5
.diff_ok:       ld (difficulty),a

                call tick_busy_counters

                ; --- environment ---
                ld a,(trans_left)
                or a
                jr z,.no_transition
                call transition_sides
                jr .lanes
.no_transition: ld hl,(seg_left)
                dec hl
                ld (seg_left),hl
                ld a,h
                or l
                jr nz,.sides
                ld a,2                      ; next two rows: transition
                ld (trans_left),a
                call random
                and 63
                add SEGMENT_MIN
                ld l,a
                ld h,0
                ld (seg_left),hl
.sides:         ld a,(env)
                or a
                call z,urban_sides
                ld a,(env)
                or a
                call nz,forest_sides

                ; --- track ---
.lanes:         ld hl,(bridge_countdown)
                ld a,h
                or l
                jr z,.countdown_done
                dec hl
                ld (bridge_countdown),hl
.countdown_done:
                ld a,(bridge_left)
                or a
                jp nz,bridge_row
                ld a,(chunk_left)
                or a
                jr nz,chunk_row
                ld hl,(bridge_countdown)    ; chunk boundary: bridge due?
                ld a,h
                or l
                jp z,start_bridge
                call pick_chunk
                ; fall through

; --- next row of the current chunk (bank C5) ------------------------------------
chunk_row:
                MAP_RAM GA_RAM_C5
                ld hl,(chunk_ptr)
                xor a
                ld (.lane_no),a
.lane:          ld a,(.lane_no)
                ld e,a
                ld d,0
                push ix
                pop iy
                add iy,de
                ld a,(hl)                   ; tile
                ld (iy+D_LANES),a
                inc hl
                ld a,(hl)                   ; collision
                ld (iy+D_COLL),a
                inc hl
                ld a,(hl)                   ; item
                ld (iy+D_ITEM),a
                inc hl
                or a
                jr z,.next_lane
                push hl
                call spawn_item
                pop hl
.next_lane:     ld a,(.lane_no)
                inc a
                ld (.lane_no),a
                cp 3
                jr nz,.lane
                ld (chunk_ptr),hl
                ld hl,chunk_left
                dec (hl)
                MAP_RAM GA_RAM_C0
                ret
.lane_no:       defb 0

; A = item, (chunk_row.lane_no) = lane: registers the item overlay
spawn_item:
                ld c,a
                ld a,(chunk_row.lane_no)
                ld b,a
                add a,a                     ; lane * 14
                add a,b
                add a,a
                add a,a
                add a,b
                add a,b
                add COL_LANE1
                ld b,a                      ; B = lane column
                ld a,c
                cp ITEM_COIN
                jr nz,.powerup
                ld a,b
                add (LANE_BYTES-COIN_W)>>1
                ld c,a
                ld hl,gfx_items_coin0
                ld a,1
                jp add_overlay
.powerup:       add IDX_ITEMS_PU_MAGNET-2   ; item 2.. -> power-up frames
                ld hl,gfx_items_table
                push bc
                call table_entry
                pop bc
                ld a,b
                add (LANE_BYTES-POWERUP_W)>>1
                ld c,a
                ld a,2
                jp add_overlay

; --- bridges ------------------------------------------------------------------------
start_bridge:
                call random
                and 127
                add BRIDGE_GAP_MIN
                ld l,a
                ld h,0
                ld (bridge_countdown),hl
                ; road bridge in the city half of the time, footbridge otherwise
                ld hl,footbridge_rows
                ld a,(env)
                or a
                jr nz,.chosen
                call random
                rra
                jr nc,.chosen
                ld hl,roadbridge_rows
.chosen:        ld a,(hl)
                inc hl
                ld (bridge_left),a
                ld (bridge_ptr),hl
                ; fall through

bridge_row:
                ld hl,(bridge_ptr)
                ld a,(hl)
                inc hl
                ld (bridge_ptr),hl
                ld (ix+D_LEFT),a
                ld a,(ix+D_FLAGS)
                or F_BRIDGE
                ld (ix+D_FLAGS),a
                ld a,IDX_TRACK_RAIL_A
                ld (ix+D_LANES),a
                ld (ix+D_LANES+1),a
                ld (ix+D_LANES+2),a
                ld hl,bridge_left
                dec (hl)
                ret

; bottom to top: shadow, then the deck rows
footbridge_rows:
                defb 4
                defb IDX_BRIDGES_FOOTBRIDGE_SHADOW,IDX_BRIDGES_FOOTBRIDGE_0
                defb IDX_BRIDGES_FOOTBRIDGE_1,IDX_BRIDGES_FOOTBRIDGE_2
roadbridge_rows:
                defb 7
                defb IDX_BRIDGES_ROADBRIDGE_SHADOW,IDX_BRIDGES_ROADBRIDGE_0
                defb IDX_BRIDGES_ROADBRIDGE_1,IDX_BRIDGES_ROADBRIDGE_2,IDX_BRIDGES_ROADBRIDGE_3
                defb IDX_BRIDGES_ROADBRIDGE_4,IDX_BRIDGES_ROADBRIDGE_5

; --- weighted chunk choice among those allowed at this difficulty/env -------------
pick_chunk:
                MAP_RAM GA_RAM_C5
                ld hl,chunk_table           ; pass 1: total weight
                ld b,CHUNK_COUNT
                ld c,0
.sum:           call chunk_weight
                add a,c
                ld c,a
                inc hl
                inc hl
                djnz .sum
                ld a,c
                or a
                jr nz,.have
                inc c                       ; nothing eligible: take chunk 0
.have:          call random_below
                ld c,a                      ; C = pick
                ld hl,chunk_table           ; pass 2: find it
                ld b,CHUNK_COUNT
.find:          call chunk_weight
                or a
                jr z,.not_this
                ld e,a
                ld a,c
                sub e
                jr c,.found
                ld c,a
.not_this:      inc hl
                inc hl
                djnz .find
                ld hl,chunk_table           ; (rounding safety) chunk 0
.found:         ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                ld a,(hl)
                ld (chunk_left),a
                ld de,4
                add hl,de
                ld (chunk_ptr),hl
                MAP_RAM GA_RAM_C0
                ret

; HL = chunk table entry -> A = its weight if eligible now, else 0.
; Preserves BC, HL.
chunk_weight:
                push hl
                push bc
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                inc hl                      ; minimum difficulty
                ld a,(difficulty)
                cp (hl)
                jr c,.no
                inc hl
                ld c,(hl)                   ; weight
                inc hl
                ld a,(hl)                   ; env: 0 any, 1 urban, 2 forest
                or a
                jr z,.yes
                dec a
                ld b,a
                ld a,(env)
                cp b
                jr nz,.no
.yes:           ld a,c
                jr .out
.no:            xor a
.out:           pop bc
                pop hl
                ret

; --- busy counters: rows until a car lane / tree spot / side feature is free ------
tick_busy_counters:
                ld hl,busy_counters
                ld b,BUSY_COUNT
.next:          ld a,(hl)
                or a
                jr z,.zero
                dec (hl)
.zero:          inc hl
                djnz .next
                ret

; scenery may only start where it cannot reach a transition or a bridge
; returns NZ if allowed for C rows
scenery_allowed:
                ld a,(trans_left)
                or a
                jr nz,.no
                ld a,(bridge_left)
                or a
                jr nz,.no
                ld hl,(seg_left)
                ld a,h
                or a
                jr nz,.seg_ok
                ld a,l
                sub SCENERY_MARGIN
                jr c,.no
                cp c
                jr c,.no
.seg_ok:        ld hl,(bridge_countdown)
                ld a,h
                or a
                jr nz,.yes
                ld a,l
                sub SCENERY_MARGIN
                jr c,.no
                cp c
                jr c,.no
.yes:           or 1
                ret
.no:            xor a
                ret

; =============================================================================
; Sides
; =============================================================================

; --- avenue ---------------------------------------------------------------------
urban_sides:
                ; base: dashed lane lines every 16 lines (road_a, road_b)
                ld a,(gen_row)
                and 1
                add a,a                     ; road_a = 0, road_b = 2
                ld (ix+D_LEFT),a
                inc a
                ld (ix+D_RIGHT),a

                ; zebra crossing over both sides
                ld a,(cross_phase)
                or a
                jr nz,.crossing
                ld hl,cross_countdown
                dec (hl)
                jr nz,.kiosks
                call random
                and 63
                add 40
                ld (hl),a
                ld a,2
                ld (cross_phase),a
.crossing:      ld hl,cross_phase           ; phase 2 = bottom row, 1 = top row
                ld a,(hl)
                dec (hl)
                cp 2
                ld a,IDX_URBAN_ROAD_CROSS_0
                jr z,.cross_tile
                ld a,IDX_URBAN_ROAD_CROSS_1
.cross_tile:    ld (ix+D_LEFT),a
                inc a
                ld (ix+D_RIGHT),a
                jr .cars

                ; kiosks on the outer lane, each side on its own
.kiosks:        ld b,0
                call .kiosk
                ld b,1
                call .kiosk

.cars:          ld b,0
                call spawn_car
                ld b,1
                jp spawn_car

; B = side
.kiosk:         ld hl,kiosk_phase
                call add_b_hl
                ld a,(hl)
                or a
                jr nz,.kiosk_row
                ld hl,kiosk_countdown
                call add_b_hl
                dec (hl)
                ret nz
                ld (hl),40                  ; retry later if the outer lane is busy
                push hl
                ld a,b                      ; outer car lane of this side
                add a,a
                add a,b
                ld hl,car_busy
                call add_a_hl
                ld a,(hl)
                or a
                pop de                      ; DE = countdown
                ret nz
                ld (hl),3                   ; keep cars away from the kiosk
                call random
                and 127
                add 60
                ld (de),a
                ld hl,kiosk_phase
                call add_b_hl
                ld (hl),2
.kiosk_row:     ld a,(hl)                   ; 2 = bottom row, 1 = top row
                dec (hl)
                cp 2
                ld a,IDX_URBAN_ROAD_KIOSK_0
                jr z,.kiosk_tile
                ld a,IDX_URBAN_ROAD_KIOSK_1
.kiosk_tile:    bit 0,b
                jr z,.left
                inc a                       ; mirrored copy
                ld (ix+D_RIGHT),a
                ret
.left:          ld (ix+D_LEFT),a
                ret

; HL += B / HL += A. Destroy A.
add_b_hl:
                ld a,b
add_a_hl:
                add a,l
                ld l,a
                ret nc
                inc h
                ret

; B = side: maybe start a vehicle in a free lane of that side
spawn_car:
                call random
                and 7
                ret nz
                push bc
                ld c,4                      ; longest vehicle: 4 rows
                call scenery_allowed
                pop bc
                ret z
                ld c,3
                call random_below           ; lane 0..2
                ld c,a
                ld a,b                      ; busy index = side*3 + lane
                add a,a
                add a,b
                add a,c
                ld e,a
                ld d,0
                ld hl,car_busy
                add hl,de
                ld a,(hl)
                or a
                ret nz
                push hl                     ; HL = busy counter
                ; column: left lanes 0,5,9; right lanes 68,63,59
                ld a,b
                add a,a
                add a,b
                add a,c
                ld e,a
                ld hl,car_columns
                add hl,de
                ld a,(hl)
                ld (.column),a
                ; vehicle: 1/8 bus, 1/8 trolley, else a car (2 rows)
                call random
                and 7
                ld c,4
                ld e,IDX_URBAN_OV_BUS
                jr z,.picked
                dec a
                ld e,IDX_URBAN_OV_TROLLEY
                jr z,.picked
                and 3
                add a,a                     ; car frames are pairs (original, mirror)
                ld e,a
                ld c,2
.picked:        ld a,e
                bit 0,b
                jr z,.unmirrored
                inc a                       ; right side: mirrored copy
.unmirrored:    ld e,a
                pop hl
                call random
                and 3
                add c
                inc a
                ld (hl),a                   ; busy for rows + gap
                ld a,e
                MAP_RAM GA_RAM_C5
                ld hl,gfx_urban_ov_table
                call table_entry
                MAP_RAM GA_RAM_C0
                ld a,(.column)
                ld b,c
                ld c,a
                ld a,b
                jp add_overlay
.column:        defb 0

car_columns:    defb 0,5,9,68,63,59

; --- transition rows (2): forest tile set ------------------------------------------
transition_sides:
                ld a,(ix+D_FLAGS)
                or F_FOREST
                ld (ix+D_FLAGS),a
                ld a,(env)
                or a
                ld a,IDX_FOREST_TRANS_URBAN_FOREST_0
                jr z,.from_urban
                ld a,IDX_FOREST_TRANS_FOREST_URBAN_0
.from_urban:    ld b,a
                ld a,(trans_left)           ; 2 = bottom row, 1 = top row
                cp 2
                ld a,b
                jr z,.tile
                add 2                       ; next frame (pairs with mirrors)
.tile:          ld (ix+D_LEFT),a
                inc a
                ld (ix+D_RIGHT),a
                ld hl,trans_left
                dec (hl)
                ret nz
                ld a,(env)                  ; transition done
                xor 1
                ld (env),a
                ret

; --- forest -------------------------------------------------------------------------
forest_sides:
                ld a,(ix+D_FLAGS)
                or F_FOREST
                ld (ix+D_FLAGS),a
                ld b,0
                call .side
                ld b,1
                call .side
                ld b,0
                call spawn_tree
                ld b,1
                jp spawn_tree

; B = side
.side:          ld e,b
                ld d,0
                ld hl,path_left
                add hl,de
                ld a,(hl)
                or a
                jr z,.no_path
                dec (hl)
                ld a,IDX_FOREST_PATH
                jr .store
.no_path:       ld hl,fence_left
                add hl,de
                ld a,(hl)
                or a
                jr z,.no_fence
                dec (hl)
                ld a,IDX_FOREST_FENCE
                jr .store
.no_fence:      call random                 ; start a path or a fence now and then
                and 31
                jr nz,.ground
                call random
                and 3
                add 3
                ld c,a
                call random
                rra
                ld hl,path_left
                jr c,.run
                ld hl,fence_left
.run:           add hl,de
                ld (hl),c
.ground:        call random
                and 2                       ; ground_a = 0, ground_b = 2
.store:         bit 0,b
                jr z,.left
                inc a
                ld (ix+D_RIGHT),a
                ret
.left:          ld (ix+D_LEFT),a
                ret

; B = side: maybe plant a tree / bush / rock
spawn_tree:
                ld e,b
                ld d,0
                ld hl,tree_busy
                add hl,de
                ld a,(hl)
                or a
                ret nz
                call random
                and 3
                ret nz
                push hl
                push bc
                ld c,3
                call scenery_allowed
                pop bc
                pop hl
                ret z
                push hl
                ld c,5
                call random_below
                ld e,a
                ld d,0
                ld hl,tree_info             ; width (bytes), rows
                add hl,de
                add hl,de
                ld a,(hl)
                ld (.width),a
                inc hl
                ld a,(hl)
                ld (.rows),a
                pop hl
                inc a                       ; busy rows + 1
                ld (hl),a
                ; column: left 0..(14-w), right 58..(72-w)
                ld a,(.width)
                neg
                add 15
                ld c,a                      ; choices
                call random_below
                bit 0,b
                jr z,.col
                add 58
.col:           ld c,a
                push bc
                ld a,e
                MAP_RAM GA_RAM_C5
                ld hl,gfx_forest_ov_table
                call table_entry
                MAP_RAM GA_RAM_C0
                pop bc
                ld a,(.rows)
                jp add_overlay
.width:         defb 0
.rows:          defb 0

tree_info:      defb 8,3, 12,3, 4,3, 4,1, 4,1     ; pine, oak, cypress, bush, rock

; -----------------------------------------------------------------------------
; add_overlay: HL = sprite (bank C5), C = column, A = rows; bottom = gen_row.
; Silently dropped if the list is full.
; -----------------------------------------------------------------------------
add_overlay:
                ld b,a
                push hl
                ld hl,OVERLAY_LIST+OV_ROWS
                ld de,OV_SIZE
                ld a,OVERLAYS
.find:          ex af,af'
                ld a,(hl)
                or a
                jr z,.free
                add hl,de
                ex af,af'
                dec a
                jr nz,.find
                pop hl
                ret
.free:          ld (hl),b                   ; rows
                inc hl
                ld (hl),c                   ; column
                inc hl
                pop de
                ld (hl),e                   ; sprite
                inc hl
                ld (hl),d
                ld de,-OV_SPRITE-1
                add hl,de                   ; back to the slot start
                ld de,(gen_row)
                ld (hl),e
                inc hl
                ld (hl),d
                ret

; =============================================================================
; render_row: HL = world row, DE = plane 0 address of the screen row
; =============================================================================
render_row:
                ld (.dest),de
                ld (.row),hl
                call desc_addr
                push hl
                pop ix
                MAP_RAM GA_RAM_C4

                bit 7,(ix+D_FLAGS)
                jr z,.normal
                ld a,(ix+D_LEFT)            ; bridge: one 72-byte tile
                ld hl,gfx_bridges_table
                call table_entry
                ld b,COL_LEFT
                ld c,PLAYFIELD_W
                call .blit
                jr .hud

.normal:        ld hl,gfx_urban_table
                bit 0,(ix+D_FLAGS)
                jr z,.set
                ld hl,gfx_forest_table
.set:           ld (.sides),hl
                ld a,(ix+D_LEFT)
                call table_entry
                ld b,COL_LEFT
                ld c,SIDE_BYTES
                call .blit
                ld hl,(.sides)
                ld a,(ix+D_RIGHT)
                call table_entry
                ld b,COL_RIGHT
                ld c,SIDE_BYTES
                call .blit
                ld a,(ix+D_LANES)
                ld b,COL_LANE1
                call .lane
                ld a,(ix+D_LANES+1)
                ld b,COL_LANE1+LANE_BYTES
                call .lane
                ld a,(ix+D_LANES+2)
                ld b,COL_LANE1+LANE_BYTES*2
                call .lane

.hud:           ld hl,gfx_hud_bg_hud_bg
                ld b,COL_HUD
                ld c,GFX_HUD_BG_WIDTH
                call .blit

                MAP_RAM GA_RAM_C5
                call draw_overlays
                MAP_RAM GA_RAM_C0
                ret

; A = track tile, B = column
.lane:          ld hl,gfx_track_table
                call table_entry
                ld c,LANE_BYTES
; HL = tile, B = column, C = width
.blit:          push hl
                ld de,(.dest)
                ld a,b
                call ring_column
                pop hl
                jp blit_tile

.dest:          defw 0
.row:           defw 0
.sides:         defw 0

; --- slices of the active overlays that fall in render_row.row ---------------------
draw_overlays:
                ld iy,OVERLAY_LIST
                ld b,OVERLAYS
.slot:          push bc
                ld a,(iy+OV_ROWS)
                or a
                jr z,.next
                ; top = bottom + rows - 1; slice if bottom <= row <= top
                ld hl,(render_row.row)
                ld e,(iy+OV_BOTTOM)
                ld d,(iy+OV_BOTTOM+1)
                or a
                sbc hl,de                   ; HL = row - bottom
                jr c,.next
                ld a,h
                or a
                jr nz,.expired
                ld a,l
                cp (iy+OV_ROWS)
                jr nc,.expired
                ; rows above this one inside the overlay = rows-1-(row-bottom)
                ld b,a
                ld a,(iy+OV_ROWS)
                dec a
                sub b
                ld (.above),a
                call draw_overlay_slice
                set 6,(ix+D_FLAGS)
                ld a,(.above)
                or a
                jr nz,.next
.expired:       ld (iy+OV_ROWS),0           ; top row drawn: free the slot
.next:          ld de,OV_SIZE
                add iy,de
                pop bc
                djnz .slot
                ret
.above:         defb 0

; IY = overlay, (draw_overlays.above) = rows above this row inside it
draw_overlay_slice:
                ld l,(iy+OV_SPRITE)
                ld h,(iy+OV_SPRITE+1)
                ld a,(hl)
                ld (.width),a
                inc hl
                ld a,(hl)                   ; height in lines
                inc hl
                ld b,a
                ld a,(draw_overlays.above)
                add a,a
                add a,a
                add a,a                     ; first line of the slice
                ld c,a
                ld a,b
                sub c
                ret c                       ; sprite shorter than its rows
                ret z
                cp 8
                jr c,.lines
                ld a,8
.lines:         ld (.count),a
                ; skip first*width*2 bytes of (mask, data) pairs
                ld a,(.width)
                add a,a
                ld e,a
                ld d,0
                ld b,c
                inc b
                jr .skip_test
.skip:          add hl,de
.skip_test:     djnz .skip
                ld (.src),hl
                ld de,(render_row.dest)
                ld a,(iy+OV_COLUMN)
                call ring_column
                ex de,hl                    ; HL = plane 0 address
                ld a,(.count)
                ld b,a
.line:          push bc
                push hl
                ld de,(.src)
                ld a,(.width)
                ld b,a
.byte:          ld a,(de)
                and (hl)
                inc de
                ld c,a
                ld a,(de)
                or c
                inc de
                ld (hl),a
                call next_ring_byte
                djnz .byte
                ld (.src),de
                pop hl
                ld a,h                      ; next plane
                add 8
                ld h,a
                pop bc
                djnz .line
                ret
.width:         defb 0
.count:         defb 0
.src:           defw 0

; --- generator state (cleared by world_init) ---------------------------------------
gen_state:
rng:            defw 0
gen_row:        defw 0
difficulty:     defb 0
env:            defb 0
seg_left:       defw 0
trans_left:     defb 0
chunk_left:     defb 0
chunk_ptr:      defw 0
bridge_left:    defb 0
bridge_ptr:     defw 0
bridge_countdown: defw 0
cross_countdown: defb 0
cross_phase:    defb 0
kiosk_countdown: defb 0,0
kiosk_phase:    defb 0,0
path_left:      defb 0,0
fence_left:     defb 0,0
busy_counters:
car_busy:       defs 6
tree_busy:      defs 2
BUSY_COUNT      equ $-busy_counters
GEN_STATE_SIZE  equ $-gen_state
