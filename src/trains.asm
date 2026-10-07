; =============================================================================
; Moving trains (bank C4, next to the track tiles they are drawn from).
;
; A train without a ramp in a side lane moves along its track: in the right
; lane it comes at the runner (TRAIN_FAST lines a frame faster than the
; world), in the left lane it goes on ahead (TRAIN_SLOW lines a frame
; slower). One at a time (src/chunk_pick.asm train_cell); the other trains
; stand still. The descriptors keep the ground under it (rail); the train is
; an extent of world lines [train_lo, train_hi) drawn over that lane.
;
; World line W = row * 8 + 7 - y (y = the line in the row, 0 at the top):
; it grows up the screen. Each frame only the train's two ends are drawn
; again, moved (8 + m lines each); its body is drawn by row from the world
; line (wagons of WAGON_PERIOD-1 rows + a coupler), so it stays in place while the
; ends move. render_row draws it into every new row (train_render), so the
; rows still to come show it where it is by then.
;
; It stops before anything on its own track (a train, a buffer stop, a
; signal) and before a row whose other two lanes are both closed, so a lane
; stays open (train_stop).
; =============================================================================

TRAIN_FAST      equ 2                   ; oncoming (right lane), lines a frame
TRAIN_SLOW      equ 1                   ; ahead (left lane), lines a frame
TRAIN_W         equ LANE_BYTES          ; bytes of a lane line
WAGON_PERIOD    equ 16                  ; a moving train's wagon and coupler, rows
TRAIN_LAZY      equ 5                   ; from this speed: not in two heavy frames

; -----------------------------------------------------------------------------
; move_trains_c4: one game frame of the moving train (bank C4 mapped).
; -----------------------------------------------------------------------------
move_trains_c4:
                ld a,(train_on)
                or a
                ret z
                ld hl,#FFFF                 ; the picture moved: no row known
                ld (tr_cache_row),hl
                ld hl,(train_anchor)        ; a new train: its tiles
                ld de,(tr_setup_for)
                or a
                sbc hl,de
                call nz,train_setup
                ld a,(train_lane)           ; the lines it owes: its speed a
                or a                        ; frame; at top speeds a frame with
                ld a,TRAIN_SLOW             ; a coarse step leaves it to the
                jr z,.owe                   ; next one (it moves and is drawn
                ld a,TRAIN_FAST             ; every other frame at most)
.owe:           ld hl,tr_owed
                add a,(hl)
                ld (hl),a
                call current_speed
                cp TRAIN_LAZY
                jr c,.now
                call coarse_ahead
                jr nc,.now
                ld a,(train_lane)           ; owes more than a frame: now
                or a
                ld b,TRAIN_SLOW+1
                jr z,.late
                ld b,TRAIN_FAST+1
.late:          ld a,(tr_owed)
                cp b
                jp c,.gone
.now:           ld a,(tr_owed)
                ld e,a
                ld d,0
                xor a
                ld (tr_owed),a
                ld a,(train_lane)
                or a
                jr z,.ahead
                ld hl,(train_lo)            ; oncoming: down, not below the stop
                or a
                sbc hl,de
                jr c,.clamp
                ld de,(train_stop)
                or a
                sbc hl,de
                add hl,de
                jr nc,.down
.clamp:         ld hl,(train_stop)
.down:          ex de,hl                    ; DE = new lo
                ld hl,(train_lo)
                or a
                sbc hl,de                   ; HL = lines it moved
                jr nc,.moved
                ld de,(train_lo)            ; (at its stop already)
                ld hl,0
.moved:         ld a,l
                ld (tr_moved),a
                ld (train_lo),de
                ld hl,(train_hi)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                ld (train_hi),hl
                ld hl,(train_lo)            ; front row: what it runs over is gone
                call clear_item
                ld de,0                     ; the ends: from the new ones up
                jr .ends

.ahead:         ld hl,(train_hi)            ; ahead: up, not above the stop
                add hl,de
                ld de,(train_stop)
                or a
                sbc hl,de
                add hl,de
                jr c,.up
                ex de,hl
.up:            ex de,hl                    ; DE = new hi
                ld hl,(train_hi)
                ex de,hl
                or a
                sbc hl,de                   ; HL = lines it moved
                jr nc,.moved_up
                ld hl,0                     ; (at its stop already)
.moved_up:      ld a,l
                ld (tr_moved),a
                ld e,a
                ld d,0
                ld hl,(train_hi)
                add hl,de
                ld (train_hi),hl
                ld hl,(train_lo)
                add hl,de
                ld (train_lo),hl
                ld hl,(train_hi)            ; front row
                dec hl
                call clear_item
                ld a,(tr_moved)             ; the ends: from the old ones up
                ld e,a
                ld d,0

.ends:          ld a,(tr_moved)
                or a
                jp z,.gone
                call picture_lines
                ld a,(train_lane)
                or a
                jr z,.ends_ahead
                ld hl,(train_lo)            ; oncoming: its cab, then the body
                ld de,(tr_low_end)          ; it moved onto; its back end, then
                call draw_end                ; the ground it left
                ld a,(tr_moved)
                ld b,a
                ld c,SEG_BODY
                call draw_seg
                ld hl,(train_hi)
                ld de,8
                or a
                sbc hl,de
                ld de,(tr_high_end)
                call draw_end
                ld a,(tr_moved)
                ld b,a
                ld c,SEG_GROUND
                call draw_seg
                jr .gone
.ends_ahead:    ld a,(tr_moved)             ; ahead: the ground it left, then
                ld e,a                      ; its back end; the body it moved
                ld d,0                      ; onto, then its cab
                ld hl,(train_lo)
                or a
                sbc hl,de
                ld b,a
                ld c,SEG_GROUND
                call draw_seg
                ld hl,(train_lo)
                ld de,(tr_low_end)
                call draw_end
                ld a,(tr_moved)
                ld e,a
                ld d,0
                ld hl,(train_hi)
                or a
                sbc hl,de
                ld de,8
                or a
                sbc hl,de
                ld b,a
                ld c,SEG_BODY
                call draw_seg
                ld hl,(train_hi)
                ld de,8
                or a
                sbc hl,de
                ld de,(tr_high_end)
                call draw_end

.gone:          ld hl,(cur_top_row)         ; off the bottom of the picture?
                ld de,PICTURE_ROWS
                or a
                sbc hl,de
                jr nc,.bottom
                ld hl,0
.bottom:        add hl,hl
                add hl,hl
                add hl,hl                   ; HL = world line at the bottom
                ld de,(train_hi)
                or a
                sbc hl,de
                ret c
                xor a
                ld (train_on),a
                ret

; the picture's world lines [tr_pic_lo, tr_pic_hi)
picture_lines:
                ld hl,(cur_top_row)
                inc hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld (tr_pic_hi),hl
                ld de,-PICTURE_ROWS*8
                add hl,de
                jr c,.lo
                ld hl,0
.lo:            ld (tr_pic_lo),hl
                ret

; HL = world line, DE = end tile: its 8 lines from the bottom one up
draw_end:
                push hl
                ld hl,7*TRAIN_W
                add hl,de
                ld (tr_src),hl
                pop hl
                ld b,8
                ld c,SEG_END
                ; fall through

; -----------------------------------------------------------------------------
; draw_seg: HL = world line, B = lines, C = what: SEG_GROUND, SEG_BODY (tiles
; by row) or SEG_END (tr_src = the end tile's line for the first one).
; Lines go up the screen: a line before in the source, a plane before on
; the screen; a new row every 8. Rows off the picture or under a bridge are
; left alone.
; -----------------------------------------------------------------------------
SEG_GROUND      equ 0
SEG_BODY        equ 1
SEG_END         equ 2

draw_seg:
                ld a,c
                ld (tr_kind),a
                ld (tr_w),hl
                push hl                     ; on the picture at all?
                ld de,(tr_pic_hi)
                or a
                sbc hl,de
                pop hl
                ret nc                      ; it starts above it
                ld a,b
                dec a
                call add_a_hl
                ld de,(tr_pic_lo)
                or a
                sbc hl,de
                ret c                       ; it ends below it
.row:           push bc
                call seg_row                ; this row: tr_dest, tr_src, tr_y
                pop bc
                ld a,(tr_y)                 ; C = its lines from here up
                inc a
                cp b
                jr c,.lines
                ld a,b
.lines:         ld c,a
                ld (tr_n),a
                push bc
                ld hl,(tr_src)
                ld a,(tr_skip)
                or a
                jr nz,.skip
                ld de,(tr_dest)
                ld a,(tr_wrap)
                or a
                jr nz,.slow
.line:          repeat TRAIN_W
                ldi
                rend
                ld bc,-2*TRAIN_W            ; the source's line before
                add hl,bc
                ex de,hl                    ; the screen's plane before
                ld bc,-#800-TRAIN_W
                add hl,bc
                ex de,hl
                ld a,(tr_n)
                dec a
                ld (tr_n),a
                jr nz,.line
                jr .row_done
.slow:          push de                     ; across the end of a 2K plane
                ld b,TRAIN_W
.byte:          ld a,(hl)
                inc hl
                ex de,hl
                ld (hl),a
                call next_ring_byte
                ex de,hl
                djnz .byte
                pop de
                ld bc,-2*TRAIN_W
                add hl,bc
                ld a,d
                sub 8
                ld d,a
                ld a,(tr_n)
                dec a
                ld (tr_n),a
                jr nz,.slow
                jr .row_done
.skip:          ld de,-TRAIN_W              ; not shown: the source moves on
.skip_line:     add hl,de
                dec c
                jr nz,.skip_line
.row_done:      ld (tr_src),hl
                pop bc
                ld a,c                      ; on to the next row
                ld hl,(tr_w)
                call add_a_hl
                ld (tr_w),hl
                ld a,b
                sub c
                ld b,a
                jp nz,.row
                ret

; the row of tr_w: tr_dest (that line on the screen), tr_wrap, tr_skip;
; for the body or the ground tr_src (that line of the row's tile)
seg_row:
                ld hl,(tr_w)
                ld a,l
                cpl
                and 7
                ld (tr_y),a
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld (tr_row),hl
                ld de,(tr_cache_row)        ; the row the last segment had?
                or a
                sbc hl,de
                jr z,.cached
                add hl,de
                ld (tr_cache_row),hl
                ex de,hl
                ld hl,(cur_top_row)
                or a
                sbc hl,de                   ; picture row
                ld a,h
                or a
                jr nz,.skip
                ld a,l
                cp PICTURE_ROWS
                jr nc,.skip
                ld (tr_p),a
                ld hl,(tr_row)
                call desc_addr
                bit 7,(hl)                  ; F_BRIDGE: under the deck
                jr nz,.skip
                ld (tr_desc),hl
                ld a,TRAIN_W
                ld (spr_width),a
                ld a,(tr_col)
                ld c,a
                ld a,(tr_p)
                call row_base
                ld (tr_base),hl
                ld a,(spr_wrap)
                ld (tr_wrap),a
                xor a
                ld (tr_skip),a
                jr .desc
.cached:        ld a,(tr_skip)
                or a
                ret nz
.desc:          ld hl,(tr_desc)
.source:        ld a,(tr_kind)
                cp SEG_END
                jr z,.place
                ld a,(train_lane)
                add D_LANES
                call add_a_hl
                ld a,(tr_kind)
                or a
                ld a,(hl)
                jr nz,.body
                call is_train_tile          ; ground (rail under its body)
                jr nc,.tile
                ld a,TILE_RAIL_A
                jr .tile
.body:          call body_tile
.tile:          ld hl,gfx_track_table
                call table_entry
                ld a,(tr_y)
                call add_lines
                ld (tr_src),hl
.place:         ld hl,(tr_base)             ; this line on the screen
                ld a,(tr_y)
                add a,a
                add a,a
                add a,a
                add a,h
                ld h,a
                ld (tr_dest),hl
                ret
.skip:          ld a,1
                ld (tr_skip),a
                ret

; tr_row: A = the train's body tile there (wagons of WAGON_PERIOD-1 rows and a coupler)
body_tile:
                ld a,(tr_row)
                ld hl,train_anchor
                sub (hl)
                and WAGON_PERIOD-1
                ld b,4                      ; coupler
                cp WAGON_PERIOD-1
                jr z,.part
                and 3
                cp 1
                ld b,1                      ; body a
                jr z,.part
                inc b                       ; body b
.part:          ld a,(tr_wagon)
                add a,b
                ret

; HL += A lines of a lane tile (A * 14)
add_lines:
                ld e,a
                add a,a
                add a,a
                add a,a
                sub e
                add a,a
                jp add_a_hl

; HL = world line: no item left in the train's lane on its row (once a row)
clear_item:
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld a,(tr_cleared)
                cp l
                ret z
                ld a,l
                ld (tr_cleared),a
                call desc_addr
                ld a,(train_lane)
                add D_ITEM
                call add_a_hl
                ld (hl),0
                ret

; -----------------------------------------------------------------------------
; train_render: render_row (bank C4) draws the train into its new row:
; IX = descriptor, render_row.row / render_row.dest. Rows all body are the
; descriptor's tile already; a row with an end of it is drawn here by
; segments (ground, an end, the body) at render_row's address.
; -----------------------------------------------------------------------------
train_render:
                ld a,(train_on)
                or a
                ret z
                bit 7,(ix+D_FLAGS)          ; under a bridge deck: hidden
                ret nz
                ld a,(train_lane)           ; all of it the body: render_row
                add D_LANES                 ; drew it from the descriptor
                ld e,a
                ld d,0
                push ix
                pop hl
                add hl,de
                ld a,(hl)
                call is_train_tile
                ret c
                ld hl,(render_row.row)      ; does the row meet [lo, hi)?
                ld (tr_row),hl
                ld (tr_cache_row),hl
                add hl,hl
                add hl,hl
                add hl,hl                   ; HL = its lowest line
                ld (tr_w0),hl
                ld de,(train_hi)
                or a
                sbc hl,de
                ret nc                      ; above the train
                ld hl,(tr_w0)
                ld de,7
                add hl,de
                ld de,(train_lo)
                or a
                sbc hl,de
                ret c                       ; below it
                ld hl,(train_anchor)        ; its tiles
                ld de,(tr_setup_for)
                or a
                sbc hl,de
                call nz,train_setup
                ld a,(train_lane)           ; what it covers is gone
                add D_ITEM
                ld e,a
                ld d,0
                push ix
                pop hl
                add hl,de
                ld (hl),0
                ld (tr_desc),ix             ; the row: render_row's address
                ld de,(render_row.dest)
                ld a,(tr_col)
                call ring_column
                ex de,hl
                ld (tr_base),hl
                ld c,TRAIN_W
                call ring_fits
                ld a,0
                jr z,.fits
                inc a
.fits:          ld (tr_wrap),a
                xor a
                ld (tr_skip),a
                ld h,a                      ; no picture limits (not shown yet)
                ld l,a
                ld (tr_pic_lo),hl
                dec hl
                ld (tr_pic_hi),hl
                ld hl,(tr_w0)
                ld b,8
.seg:           push bc                     ; HL = line, B = lines left
                push hl
                ld de,(train_lo)
                or a
                sbc hl,de                   ; W - lo
                jr c,.below
                ld a,h
                or a
                jr nz,.above_low
                ld a,l
                cp 8
                jr nc,.above_low
                ld c,a                      ; the low end: 8 - (W - lo) lines
                cpl
                and 7
                ld hl,(tr_low_end)
                call add_lines
                ld (tr_src),hl
                ld a,8
                sub c
                ld c,SEG_END
                jr .count
.below:         ld a,l                      ; ground up to lo
                neg
                ld c,SEG_GROUND
                jr .count
.above_low:     add hl,de
                ld de,(train_hi)
                or a
                sbc hl,de                   ; W - hi
                jr nc,.ground
                ld a,h
                inc a
                jr nz,.body_far             ; (more than 256 lines below hi)
                ld a,l
                cp -8
                jr c,.body
                cpl                         ; the high end: hi - W lines
                ld hl,(tr_high_end)
                call add_lines
                ld (tr_src),hl
                ld a,l                      ; (recompute: hi - W)
                pop hl
                push hl
                ld de,(train_hi)
                ex de,hl
                or a
                sbc hl,de
                ld a,l
                ld c,SEG_END
                jr .count
.body:          add a,8                     ; the body up to hi - 8
                neg
                ld c,SEG_BODY
                jr .count
.body_far:      ld a,8
                ld c,SEG_BODY
                jr .count
.ground:        ld a,8
                ld c,SEG_GROUND
.count:         pop hl                      ; A = lines of it, at most B
                pop de
                cp d
                jr c,.fewer
                ld a,d
.fewer:         ld b,a
                push de
                push hl
                push bc
                call draw_seg
                pop bc
                pop hl
                ld a,b
                call add_a_hl
                pop de
                ld a,d
                sub b
                ld b,a
                jp nz,.seg
                ret

; A = track tile: C if a train's (wagon or locomotive)
is_train_tile:
                cp TILE_WAGONS
                ccf
                ret nc
                cp TILE_RAMPS
                ret

; the train's lane column and its end tiles: oncoming (right lane) the cab
; at the bottom, ahead (left lane) the cab at the top
train_setup:
                xor a                       ; nothing owed from the last one
                ld (tr_owed),a
                ld a,(train_lane)
                ld b,a
                add a,a                     ; column: COL_LANE1 + lane * 14
                add a,b
                add a,a
                add a,a
                add a,b
                add a,b
                add COL_LANE1
                ld (tr_col),a
                ld a,(train_livery)
                ld c,a
                add a,a
                add a,a
                ld e,a                      ; E = livery * 4
                add a,c
                add TILE_WAGONS
                ld (tr_wagon),a             ; its first wagon tile
                ld a,e
                add TILE_LOCOS
                ld d,a                      ; D = its first locomotive tile
                ld a,b
                or a
                jr nz,.oncoming
                ld c,d                      ; ahead: wagon end at the bottom,
                inc c                       ; the cab facing away at the top
                inc c                       ; (end_bottom, nose_top)
                inc c
                ld a,(tr_wagon)
                jr .ends
.oncoming:      ld a,(tr_wagon)             ; oncoming: the cab (nose) at the
                add 3                       ; bottom, a wagon end_top at the top
                ld c,a
                ld a,d
.ends:          ld hl,gfx_track_table
                push bc
                call table_entry
                ld (tr_low_end),hl
                pop bc
                ld a,c
                ld hl,gfx_track_table
                call table_entry
                ld (tr_high_end),hl
                ld hl,(train_anchor)
                ld (tr_setup_for),hl
                ret

; --- work variables (bank C4) ---------------------------------------------------
tr_w:           defw 0                  ; world line being drawn
tr_y:           defb 0                  ; its line in the row (plane)
tr_row:         defw #FFFF              ; the row being drawn
tr_base:        defw 0                  ; its plane 0 address in the lane
tr_wrap:        defb 0                  ; a line crosses a 2K plane end
tr_skip:        defb 0                  ; not shown: leave it
tr_low_end:     defw 0
tr_high_end:    defw 0
tr_col:         defb 0
tr_wagon:       defb 0
tr_moved:       defb 0
tr_owed:        defb 0                  ; lines it has still to move
tr_setup_for:   defw #FFFF              ; the train train_setup was done for
tr_kind:        defb 0                  ; draw_seg: SEG_*
tr_w0:          defw 0                  ; train_render: the row's lowest line
tr_cache_row:   defw #FFFF              ; seg_row: the row of tr_base, tr_desc
tr_desc:        defw 0
tr_cleared:     defb #FF                ; clear_item: the last row (low byte)
tr_n:           defb 0                  ; lines left in the row
tr_src:         defw 0
tr_dest:        defw 0
tr_p:           defb 0
tr_pic_lo:      defw 0
tr_pic_hi:      defw 0
