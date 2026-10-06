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
F_STATION       equ 2                   ; a station on the route (HUD board, name)
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
COL_GAP         equ 7                   ; between two wagons (hard: a gap on the roof)

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
OV_WIDTH        equ 6                   ; its width in bytes (add_scenery)
OVERLAY_W_MAX   equ 12                  ; the widest overlay (oak)

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
                ld hl,PU_GAP_MIN            ; the first power-up
                ld (pu_gap),hl
                ld a,SPACER_START           ; an empty start, then denser
                ld (spacer_len),a
                ld (spacer_left),a
                ld hl,spacer_tick
                call spacer_step
                ld hl,BRIDGE_GAP_MIN/2
                ld (bridge_countdown),hl
                ld a,24
                ld (cross_countdown),a
                ld a,30
                ld (kiosk_countdown),a
                ld a,50
                ld (kiosk_countdown+1),a
                ld hl,ROUTE_SEG             ; the route: Kiato to Piraeus
                ld (route_left),hl
                ld a,1
                ld (station_next),a
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

                ; difficulty 1..5 grows every 256 rows (easy), 171 (medium),
                ; 128 (hard)
                ld hl,(gen_row)
                ld d,h
                ld e,l
                srl d
                rr e                        ; DE = rows / 2
                ld a,(skill)
                or a
                ld b,a
                inc b
                ld a,h
                jr nz,.diff_add
                rra                         ; easy: every 512 rows
                jr .diff_add
.diff_more:     add hl,de
                ld a,h
                jr c,.diff_max
.diff_add:      djnz .diff_more
                inc a
                cp 6
                jr c,.diff_ok
.diff_max:      ld a,5
.diff_ok:       ld (difficulty),a

                ; empty rows between chunks: SPACER_START at first, one less
                ; every spacer_steps[skill] rows
                ld hl,spacer_tick
                dec (hl)
                call z,spacer_step

                call tick_busy_counters
                ld hl,(route_left)          ; the route: a station every
                dec hl                      ; ROUTE_SEG rows, Piraeus the 6th,
                ld a,h                      ; then from Kiato again
                or l
                jr nz,.route
                set 1,(ix+D_FLAGS)          ; F_STATION
                ld a,(route_station)
                inc a
                cp ROUTE_STATIONS-1
                jr c,.station
                xor a
.station:       ld (route_station),a
                ld hl,ROUTE_SEG
.route:         ld (route_left),hl
                ld hl,(pu_gap)              ; rows until the next power-up
                ld a,h
                or l
                jr z,.pu_due
                dec hl
                ld (pu_gap),hl
.pu_due:

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
                ld a,(spacer_left)          ; empty rows after a chunk
                or a
                jr nz,spacer_row
                ld hl,(bridge_countdown)    ; chunk boundary: bridge due?
                ld a,h
                or l
                jp z,start_bridge
                call pick_chunk
                ld a,(spacer_len)           ; and the empty rows after it: a
                ld hl,(pu_gap)              ; power-up overdue gets a clear
                ld b,a                      ; stretch long enough for it
                ld a,h
                or l
                ld a,b
                jr nz,.spacer
                cp PU_CLEAR*2+1
                jr nc,.spacer
                ld a,PU_CLEAR*2+1
.spacer:        ld (spacer_left),a
                ; fall through

; --- next row of the current chunk (src/chunk_pick.asm, bank C5) ------------------
chunk_row:
                MAP_RAM GA_RAM_C5
                call chunk_row_c5
                MAP_RAM GA_RAM_C0
                ret
row_lane:       defb 0                      ; lane of the cell being placed

; --- empty track between chunks --------------------------------------------------
spacer_row:
                dec a
                ld (spacer_left),a
                ld b,a
                ld a,TILE_RAIL_A
                ld (ix+D_LANES),a
                ld (ix+D_LANES+1),a
                ld (ix+D_LANES+2),a
                ld hl,(pu_gap)              ; a power-up due and PU_CLEAR more
                ld a,h                      ; empty rows: any lane
                or l
                ret nz
                ld a,b
                cp PU_CLEAR
                ret c
                ld c,3
                call random_below
                ld (row_lane),a
                xor a                       ; (on the ground)
                ld (pu_roof),a
                ld a,(row_lane)
                call clear_behind           ; and none in the rows behind
                ret nz
                ld e,a
                ld d,0
                push ix
                pop iy
                add iy,de
                MAP_RAM GA_RAM_C5           ; (spawn_item: the sprite table)
                call put_powerup
                MAP_RAM GA_RAM_C0
                ret

; HL = spacer_tick: reloads it, one empty row less (down to the fewest)
SPACER_START    equ 24
spacer_step:
                push hl
                ld a,(skill)
                ld hl,spacer_steps
                call add_a_hl
                ld a,(hl)
                inc hl
                inc hl
                inc hl
                ld b,(hl)                   ; B = the fewest
                pop hl
                ld (hl),a
                ld hl,spacer_len
                ld a,b
                cp (hl)
                ret nc
                dec (hl)
                ret
spacer_steps:   defb 96,40,24               ; rows per step: easy, medium, hard
                defb 8,0,0                  ; the fewest empty rows

ROUTE_SEG       equ 320                     ; rows between two stations (5 route pixels)
ROUTE_STATIONS  equ 7                       ; Kiato .. Piraeus

PU_GAP_MIN      equ 50
PU_GAP_RANGE    equ 70                      ; 50-120 rows, ~50-150 with the wait
PU_CLEAR        equ 8                       ; rows ahead and behind without an obstacle
PU_TURBO_ODDS   equ 77                      ; 30%

; A = lane: Z if none of the PU_CLEAR rows below gen_row has an obstacle
; there. Preserves A, BC, DE, HL.
clear_behind:
                push hl
                push de
                push bc
                ld c,a
                ld hl,(gen_row)
                dec hl
                call desc_addr
                ld a,D_COLL
                add a,c
                call add_a_hl               ; HL = its class in the row below
                ld de,-ROW_SIZE
                ld b,PU_CLEAR
.row:           ld a,(hl)
                call obstacle
                jr nz,.done
                add hl,de                   ; the row below, round the ring
                ld a,h
                cp WORLD_RING>>8
                jr nc,.in_ring
                ld h,(WORLD_RING+RING_ROWS*ROW_SIZE-1)>>8
.in_ring:       djnz .row
                xor a                       ; Z: all clear
.done:          ld a,c
                pop bc
                pop de
                pop hl
                ret

; A = collision byte: Z if it keeps a power-up spot clear. On the ground
; (pu_roof 0): rail and ramps. On a roof: the train (wagons, couplers, ramps).
obstacle:
                and 15
                push bc
                ld b,a
                ld a,(pu_roof)
                or a
                ld a,b
                pop bc
                jr nz,.roof
                or a
                ret z
                cp COL_GAP
                jr z,.yes
.ramps:         cp COL_RAMP_UP
                jr c,.yes                   ; 1-4: stop, signal, train, nose
                xor a                       ; ramps (and couplers on a roof)
                ret
.roof:          cp COL_TRAIN
                ret z
                jr .ramps                   ; 0-4: off the train
.yes:           or #80                      ; NZ
                ret
pu_roof:        defb 0                      ; the power-up spot being checked

; IY = descriptor + lane, (row_lane) = lane: a power-up there (not on the
; track of the moving train: it would run it over)
put_powerup:
                ld a,(train_on)
                or a
                jr z,.free
                ld a,(train_lane)
                ld hl,row_lane
                cp (hl)
                ret z
.free:
                call random                 ; the kind
                cp PU_TURBO_ODDS
                ld a,ITEM_TURBO
                jr c,.kind
.other:         call random
                and 7
                cp 5
                jr nc,.other
                ld hl,pu_kinds
                call add_a_hl
                ld a,(hl)
.kind:          ld (iy+D_ITEM),a
                call spawn_item
                ld c,PU_GAP_RANGE+1         ; (finding a safe spot adds some)
                call random_below
                add PU_GAP_MIN&#FF
                ld l,a
                ld h,0
                ld (pu_gap),hl
                ret
pu_kinds:       defb ITEM_MAGNET,ITEM_SLOW,ITEM_SPRING,ITEM_HELMET,ITEM_TICKET

; A = item, (row_lane) = lane: registers the item overlay
spawn_item:
                ld c,a
                ld a,(row_lane)
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
pick_chunk:                                 ; (src/chunk_pick.asm, bank C5)
                MAP_RAM GA_RAM_C5
                call pick_chunk_c5
                MAP_RAM GA_RAM_C0
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
                MAP_RAM GA_RAM_C5           ; (add_scenery reads its width)
                ld hl,gfx_urban_ov_table
                call table_entry
                ld a,(.column)
                ld b,c
                ld c,a
                ld a,b
                call add_scenery
                MAP_RAM GA_RAM_C0
                ret
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

; --- forest (src/chunk_pick.asm, bank C5) ----------------------------------------------
forest_sides:
                MAP_RAM GA_RAM_C5
                call forest_sides_c5
                MAP_RAM GA_RAM_C0
                ret

; -----------------------------------------------------------------------------
; add_scenery: as add_overlay, for scenery (cars, trees), unless the
; overlays in the row (items too) would grow wider than SCENERY_W_MAX bytes:
; render_row draws them all with the new row, in a coarse step.
; -----------------------------------------------------------------------------
SCENERY_W_MAX   equ 20

add_scenery:
                push af
                ld a,(scenery_width)
                add a,(hl)
                cp SCENERY_W_MAX+1
                jr c,.room
                pop af                      ; too wide: not this time
                ret
.room:          pop af
                ; fall through

; -----------------------------------------------------------------------------
; add_overlay: HL = sprite (bank C5, mapped), C = column, A = rows; bottom =
; gen_row. Silently dropped if the list is full.
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
                inc hl
                ld a,(de)
                ld (hl),a                   ; its width
                push hl
                ld hl,scenery_width
                add a,(hl)
                ld (hl),a
                pop hl
                ld de,-OV_WIDTH
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

.hud:           ld hl,gfx_hud_bg_hud_station ; the HUD frame: a station board,
                bit 1,(ix+D_FLAGS)          ; or the little track's sleeper on
                jr nz,.hud_tile             ; every other row
                ld hl,gfx_hud_bg_hud_bg
                ld a,(.row)
                rra
                jr nc,.hud_tile
                ld hl,gfx_hud_bg_hud_bg_t
.hud_tile:      ld b,COL_HUD
                ld c,GFX_HUD_BG_WIDTH
                call .blit

                MAP_RAM GA_RAM_C5
                call draw_overlays
                MAP_RAM GA_RAM_C4           ; a moving train over it all
                call train_render
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
                ld a,(scenery_width)
                sub (iy+OV_WIDTH)
                ld (scenery_width),a
.next:          ld de,OV_SIZE
                add iy,de
                pop bc
                djnz .slot
                ret
.above:         defb 0

; IY = overlay, (draw_overlays.above) = rows above this row inside it.
; Bank C5 mapped. An overlay with code (its sprite's prefix, src/data/
; gfx_*_ov_code.asm in C7): that slice's routine, unless the row crosses a
; plane end; else the masked pairs.
draw_overlay_slice:
                ld l,(iy+OV_SPRITE)
                ld h,(iy+OV_SPRITE+1)
                dec hl
                ld a,(hl)
                dec hl
                ld l,(hl)
                ld h,a                      ; HL = its slices (bank C7), 0: none
                or l
                jr z,.masked
                push hl
                ld de,(render_row.dest)
                ld a,(iy+OV_COLUMN)
                call ring_column
                ld a,(iy+OV_WIDTH)
                ld c,a
                ex de,hl                    ; HL = plane 0 address
                call ring_fits
                pop de
                jr nz,.masked
                ld a,(draw_overlays.above)  ; DE = its slice's entry
                add a,a
                add a,e
                ld e,a
                jr nc,.slice
                inc d
.slice:         MAP_RAM GA_RAM_C7
                ex de,hl
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ld (.code+1),hl
                ex de,hl
.code:          call 0                      ; SMC
                MAP_RAM GA_RAM_C5
                ret
.masked:
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
                ld a,l                      ; bytes before the plane end
                neg
                ld (.part),a
                ld a,(.width)               ; same offset in every plane: test once
                ld c,a
                call ring_fits
                ld de,(.src)                ; source pointer kept in DE across planes
                jr z,.fast
                push hl                     ; a line crossing the plane end: up
                ld a,(.part)                ; to it, then from the plane start
                call .entry
                ld (.s1+1),hl
                ld a,(.part)
                ld b,a
                ld a,(.width)
                sub b
                call .entry
                ld (.s2+1),hl
                pop hl
                ld a,(.count)
.split:         push hl
                push af
.s1:            call 0                      ; SMC
                ld bc,-PLANE_SIZE
                add hl,bc
.s2:            call 0                      ; SMC
                pop af
                pop hl
                ld bc,PLANE_SIZE
                add hl,bc
                dec a
                jr nz,.split
                ret
.fast:          ld a,(.width)
                push hl
                call .entry
                ld (.f1+1),hl
                pop hl
                ld a,(.count)
.fast_line:     push hl
                push af
.f1:            call 0                      ; SMC
                pop af
                pop hl
                ld bc,PLANE_SIZE
                add hl,bc
                dec a
                jr nz,.fast_line
                ret
; A = bytes: HL = the entry into the chain below for them
.entry:         ld b,a
                add a,a
                add a,a
                add a,a
                add a,b                     ; 9 bytes a step
                ld c,a
                ld b,0
                ld hl,.chain_end
                or a
                sbc hl,bc
                ret
; (mask, data) pairs DE -> screen HL
.chain:         repeat OVERLAY_W_MAX
                ld a,(de)
                and (hl)
                inc de
                ld c,a
                ld a,(de)
                or c
                inc de
                ld (hl),a
                inc hl
                rend
.chain_end:     ret
.part:          defb 0
.width:         defb 0
.count:         defb 0
.src:           defw 0

; --- generator state (cleared by world_init) ---------------------------------------
; a game frame of the moving train (src/trains.asm, bank C4)
move_trains:
                MAP_RAM GA_RAM_C4
                call move_trains_c4
                MAP_RAM GA_RAM_C0
                ret

; -----------------------------------------------------------------------------
; time_of_day: first thing in a frame (the beam at the top). While playing,
; the picture's distance sets the step of a day-night cycle (time_steps,
; src/data/palette.asm: 2048 rows, 64 a step); the menus are by day. A new
; step: pens 0-13 from time_palettes (14 and 15 cycle: glint, lamp).
; -----------------------------------------------------------------------------
time_of_day:
                xor a
                ld b,a
                ld a,(game_mode)
                cp MODE_MENU
                jr nc,.step                 ; menus: day
                ld hl,(cur_top_row)         ; (row / 64) & 31
                ld a,l
                rlca
                rlca
                and 3
                ld b,a
                ld a,h
                add a,a
                add a,a
                or b
                and 31
                ld hl,time_steps
                call add_a_hl
                ld b,(hl)                   ; B = offset of its palette
.step:          ld hl,time_now
                ld a,b
                cp (hl)
                ret z
                ld (hl),a
                ld hl,time_palettes
                call add_a_hl
                ld e,0
.pen:           ld bc,GA_PORT*256
                out (c),e
                ld a,(hl)
                or GA_COLOUR
                out (c),a
                inc hl
                inc e
                ld a,e
                cp TIME_PENS
                jr nz,.pen
                ret
time_now:       defb 0                      ; offset of the palette shown

; -----------------------------------------------------------------------------
; stations: once a game frame. When the runner reaches a station row its
; name is written on the track (and the bell rings); Piraeus gives 1000
; points and the route starts over.
; -----------------------------------------------------------------------------
stations:
                ld hl,(feet_row)
                ld de,(station_seen)
                or a
                sbc hl,de
                ret z
                add hl,de
                ld (station_seen),hl
                call desc_addr
                bit 1,(hl)                  ; F_STATION
                ret z
                ld a,(station_next)         ; 1 Corinth .. 6 Piraeus
                ld b,a
                inc a
                cp ROUTE_STATIONS
                jr c,.next
                ld a,1
.next:          ld (station_next),a
                ld a,SFX_SIGNAL
                ld (sfx_request),a
                ld a,b
                cp ROUTE_STATIONS-1
                call z,piraeus_bonus
                ld a,b
                add LABEL_STATION-1
                jp make_label

piraeus_bonus:                              ; 1000 points
                push bc
                ld hl,score+1
                ld a,(hl)
                add #10
                daa
                ld (hl),a
                inc hl
                ld a,(hl)
                adc 0
                daa
                ld (hl),a
                pop bc
                ret nc
                jp score_add.full
station_seen:   defw 0                  ; the runner's row when last checked
station_next:   defb 1                  ; the next station's number

gen_state:
scenery_width:  defb 0                  ; bytes of the active overlays (add_scenery)
rng:            defw 0
gen_row:        defw 0
pu_gap:         defw 0                  ; rows until the next power-up
spacer_len:     defb 0                  ; empty rows after each chunk
spacer_left:    defb 0                  ; empty rows still to come
spacer_tick:    defb 0                  ; rows until spacer_len shrinks
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
train_on:       defb 0                  ; a moving train (src/trains.asm)
train_lane:     defb 0                  ; 0: goes on ahead, 2: comes at the runner
train_lo:       defw 0                  ; its world lines [lo, hi)
train_hi:       defw 0
train_stop:     defw 0                  ; how far it may go (lowest lo / highest hi)
train_anchor:   defw 0                  ; its first row (where its wagons are)
train_livery:   defb 0
train_left:     defb 0                  ; rows of it its chunk still has to come
train_movable:  defb 0                  ; the chunk's trains may move
route_left:     defw 0                  ; rows to the next station
route_station:  defb 0                  ; stations passed on this lap (0-5)
busy_counters:
car_busy:       defs 6
tree_busy:      defs 2
BUSY_COUNT      equ $-busy_counters
GEN_STATE_SIZE  equ $-gen_state
