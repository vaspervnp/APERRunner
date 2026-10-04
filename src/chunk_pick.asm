; =============================================================================
; Track chunks in bank C5 (src/world.asm pick_chunk / chunk_row map it).
;
; pick_chunk_c5: the next track chunk, weighted random among the chunks the
; difficulty and the environment allow (src/data/chunks.asm). One pass
; works out the weights into chunk_weights, the second only subtracts.
; Each chunk then gets a random lane order (any of the 6, or only as it is /
; mirrored when it has trains side by side: hops between roofs) and a random
; livery for its trains, so the same chunk looks and plays differently.
; =============================================================================
pick_chunk_c5:
                ld hl,chunk_table
                ld de,chunk_weights
                ld b,CHUNK_COUNT
                ld c,0                      ; C = total weight
.weigh:         push hl
                ld a,(hl)                   ; HL = chunk: rows, difficulty,
                inc hl                      ; weight, environment
                ld h,(hl)
                ld l,a
                inc hl
                ld a,(difficulty)
                cp (hl)
                jr c,.no                    ; too early for it
                inc hl
                inc hl
                ld a,(hl)                   ; environment: 0 any, 1 urban, 2 forest
                and CHUNK_ENV
                dec hl
                or a
                jr z,.yes
                dec a
                push bc
                ld b,a
                ld a,(env)
                cp b
                pop bc
                jr nz,.no
.yes:           ld a,(hl)                   ; its weight
                jr .store
.no:            xor a
.store:         ld (de),a
                inc de
                add a,c
                ld c,a
                pop hl
                inc hl
                inc hl
                djnz .weigh
                ld a,c
                or a
                jr nz,.pick
                inc c                       ; nothing eligible: the first one
.pick:          call random_below           ; A = 0 .. total-1
                ld hl,chunk_weights
                ld de,chunk_table
                ld b,CHUNK_COUNT
.find:          sub (hl)
                jr c,.found
                inc hl
                inc de
                inc de
                djnz .find
                ld de,chunk_table           ; (rounding safety) chunk 0
.found:         ex de,hl
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ld a,(hl)
                ld (chunk_left),a
                inc hl
                inc hl
                inc hl
                ld a,(hl)                   ; env | CHUNK_SIDE_BY_SIDE | CHUNK_RAMP
                inc hl
                ld (chunk_ptr),hl
                ld b,a
                and CHUNK_RAMP
                ld (roofs_reachable),a      ; power-ups on its roofs too
                ld a,b
                ld c,6                      ; lane order: any
                and CHUNK_SIDE_BY_SIDE
                jr z,.order
                ld c,2                      ; as it is or mirrored
.order:         call random_below
                ld b,a
                add a,a
                add a,b
                ld hl,lane_orders
                call add_a_hl
                ld de,chunk_lanes
                ld bc,3
                ldir
                ld hl,chunk_lanes           ; and back: chunk_src[chunk_lanes[k]] = k
                ld b,0
.back:          ld a,(hl)
                push hl
                ld hl,chunk_src
                call add_a_hl
                ld (hl),b
                pop hl
                inc hl
                inc b
                ld a,b
                cp 3
                jr nz,.back
                ld c,3                      ; livery shift 0-2: its livery_tiles
                call random_below
                rrca
                rrca
                ld (livery),a               ; 0, 64, 128
                ret

; chunk lane k goes to lane chunk_lanes[k]; the first two keep neighbours
lane_orders:    defb 0,1,2, 2,1,0, 1,0,2, 0,2,1, 1,2,0, 2,0,1


; --- next row of the current chunk: the 3 cells in the chunk's lane order ---------
; IX = descriptor. Destroys AF, BC, DE, HL, IY.
chunk_row_c5:
                ld hl,(chunk_ptr)
                ld a,(chunk_lanes)
                call .cell
                ld a,(chunk_lanes+1)
                call .cell
                ld a,(chunk_lanes+2)
                call .cell
                call place_powerup
                ld (chunk_ptr),hl
                ld hl,chunk_left
                dec (hl)
                ret
; A = lane the cell at HL goes to; HL += 3
.cell:          ld (row_lane),a
                ld e,a
                ld d,0
                push ix
                pop iy
                add iy,de
                ld a,(livery)               ; tile, in the chunk's livery
                add a,(hl)
                ld e,a
                ld d,livery_tiles>>8
                ld a,(de)
                ld (iy+D_LANES),a
                inc hl
                ld a,(hl)                   ; collision
                ld (iy+D_COLL),a
                inc hl
                ld a,(hl)                   ; item
                ld (iy+D_ITEM),a
                inc hl
                or a
                ret z
                push hl
                call spawn_item
                pop hl
                ret

; -----------------------------------------------------------------------------
; place_powerup (bank C5): when pu_gap is 0, a power-up on a free lane of this row
; (IX = descriptor, HL = the chunk's next row, bank C5): plain rail and no
; item here and on the next row (it covers 2 rows), no obstacle in the
; PU_CLEAR rows ahead of it nor in the PU_CLEAR rows behind it (rail or
; ramps). Or on a wagon roof (not a coupler) in a chunk with a ramp, with the
; train going on PU_CLEAR rows ahead and behind (src/world.asm obstacle). Turbo PU_TURBO_ODDS/256,
; the other five share the rest. Then 50-150 rows to the next one.
; Preserves HL.
; -----------------------------------------------------------------------------
place_powerup:
                ld de,(pu_gap)
                ld a,d
                or e
                ret nz
                ld a,(chunk_left)           ; rows ahead in this chunk, then the
                dec a                       ; empty ones after it: PU_CLEAR
                ret z
                ld c,a
                ld a,(spacer_len)
                add a,c
                cp PU_CLEAR
                ret c
                ld a,c                      ; the chunk rows to check
                cp PU_CLEAR
                jr c,.rows
                ld a,PU_CLEAR
.rows:          ld (.check),a
                push hl
                ld c,3
                call random_below
                ld b,3                      ; B = lanes to try from lane A
.try:           ld (row_lane),a
                ld e,a
                ld d,0
                push ix
                pop iy
                add iy,de                   ; this row
                ld a,(iy+D_ITEM)
                or a
                jr nz,.next
                ld a,(iy+D_COLL)            ; on the ground (rail) or, in a chunk
                and 15                      ; with a ramp, on a wagon roof
                jr z,.surface
                cp COL_TRAIN
                jr nz,.next
                ld a,(roofs_reachable)
                or a
                jr z,.next
.surface:       ld (pu_roof),a
                ld a,e                      ; the rows behind
                call clear_behind
                jr nz,.next
                ld hl,chunk_src             ; the lane in the chunk's data
                add hl,de
                ld e,(hl)
                pop hl
                push hl
                add hl,de                   ; next row: lane * 3 + collision
                add hl,de
                add hl,de
                inc hl
                inc hl
                ld a,(hl)                   ; no item next to it (2 rows)
                dec hl
                or a
                jr nz,.next
                ld a,(pu_roof)              ; on a roof: not over a coupler
                or a
                jr z,.rows_ahead
                ld a,(hl)
                and 15
                cp COL_TRAIN
                jr nz,.next
.rows_ahead:    ld a,(.check)               ; and no obstacle in the rows ahead
                ld c,a
.ahead:         ld a,(hl)
                call obstacle
                jr nz,.next
                ld a,9                      ; the row above in the chunk
                call add_a_hl
                dec c
                jr nz,.ahead
                jr .found
.next:          ld a,(row_lane)
                inc a
                cp 3
                jr c,.lane_ok
                xor a
.lane_ok:       djnz .try
                pop hl
                ret                         ; none free: try the next row
.found:         call put_powerup
                pop hl
                ret
.check:         defb 0


chunk_weights:  defs CHUNK_COUNT
chunk_lanes:    defb 0,1,2
chunk_src:      defb 0,1,2
livery:         defb 0                  ; offset of its table in livery_tiles
roofs_reachable: defb 0                 ; the chunk has a ramp up: roofs reachable
