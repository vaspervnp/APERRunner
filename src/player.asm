; =============================================================================
; The runner: lane changes, jumps, animation and drawing.
;
; Height levels z (plan.md 1.2): 0 ground, 1 low jump, 2 train roof,
; 3 jump over a train / from the roof, 4 highest jump. player_base is the
; level the runner stands on (0 ground, 2 roof; set by ramps in phase 5).
; The sprite grows with z (sizes s1..s5) and is lifted 2 lines per level;
; its feet stay centred on the lane. A shadow marks the ground while airborne.
; =============================================================================

FOOT_Y          equ 256                 ; screen line of the feet at z = 0
LANE_CENTRE1    equ COL_LANE1+LANE_BYTES/2
MOVE_STEPS      equ 4

player_init:
                ld hl,player_state
                ld de,player_state+1
                ld bc,PLAYER_STATE_SIZE-1
                ld (hl),0
                ldir
                ld a,1
                ld (player_lane),a
                ld a,LANE_CENTRE1+LANE_BYTES
                ld (player_centre),a
                xor a
                ld (player_save),a
                ld (shadow_save),a
                ret

; -----------------------------------------------------------------------------
; player_update: one game frame of movement from keys_pressed/keys_held.
; -----------------------------------------------------------------------------
player_update:
                ; --- lane change: queue a press made while moving ---
                ld a,(keys_pressed)
                ld c,0
                bit 0,a                     ; KEY_LEFT
                jr z,.not_left
                ld c,-1
.not_left:      bit 1,a                     ; KEY_RIGHT
                jr z,.not_right
                ld c,1
.not_right:     ld a,c
                or a
                jr z,.no_press
                ld (move_queued),a
.no_press:      ld a,(move_steps_left)
                or a
                jr nz,.moving
                ld a,(move_queued)          ; start a queued move if possible
                or a
                jr z,.jump
                ld c,a
                xor a
                ld (move_queued),a
                ld a,(player_lane)
                add a,c
                cp 3                        ; -1 or 3 = off the track
                jr nc,.jump
                ld (player_lane),a
                ld a,c
                ld (move_dir),a
                ld a,MOVE_STEPS
                ld (move_steps_left),a
.moving:        ld hl,move_step_sizes-1     ; step = sizes[4 - left]
                ld a,(move_steps_left)
                ld e,a
                ld d,0
                add hl,de
                ld b,(hl)
                ld a,(move_dir)
                or a
                ld a,(player_centre)
                jp p,.move_right
                sub b
                jr .moved
.move_right:    add a,b
.moved:         ld (player_centre),a
                ld hl,move_steps_left
                dec (hl)

                ; --- jumps ---
.jump:          ld hl,(arc_ptr)
                ld a,h
                or l
                jr nz,.in_air
                ld a,(keys_pressed)
                and KEY_JUMP
                jr z,.on_ground
                ld hl,arc_ground
                ld a,(player_base)
                or a
                jr z,.start_arc
                ld hl,arc_roof
.start_arc:     ld (arc_ptr),hl
                xor a
                ld (arc_index),a
.in_air:        ld a,(arc_index)            ; last arc frame shown: back on the base
                cp (hl)
                jr c,.airborne
                ld hl,0
                ld (arc_ptr),hl
                jr .on_ground
.airborne:      ld a,(keys_pressed)         ; fast landing: skip to the descent
                and KEY_DOWN
                jr z,.arc_step
                ld a,(hl)
                sub 2
                ld b,a
                ld a,(arc_index)
                cp b
                jr nc,.arc_step
                ld a,b
                ld (arc_index),a
.arc_step:      ld a,(arc_index)
                ld e,a
                ld d,0
                inc hl
                add hl,de
                ld a,(hl)
                ld (player_z),a
                ld hl,arc_index
                inc (hl)
                jr .animate
.on_ground:     ld a,(player_base)
                ld (player_z),a

                ; --- run cycle: 4 frames, 2 game frames each ---
.animate:       ld hl,anim_tick
                inc (hl)
                ret

move_step_sizes: defb 3,3,4,4           ; indexed by steps left (4 first)

; arcs: length, then z per game frame
arc_ground:     defb 12, 1,1,1,1,1,1,1,1,1,1,1,1
arc_roof:       defb 12, 3,3,4,4,4,4,4,4,4,4,3,3

; -----------------------------------------------------------------------------
; player_sprite: A = frame index in gfx_player_table for the current state.
; -----------------------------------------------------------------------------
player_sprite:
                ld a,(game_state)           ; crashed: tumble (crash0/crash1)
                or a
                jr z,.alive
                ld a,(anim_tick)
                rra
                rra
                and 1
                ld b,a
                ld a,(player_base)
                or a
                ld a,IDX_PLAYER_S1_CRASH0
                jr z,.crash
                ld a,IDX_PLAYER_S3_CRASH0
.crash:         add a,b
                ret
.alive:         ld hl,(arc_ptr)
                ld a,h
                or l
                jr z,.running
                ; airborne: size from z, up/down from the arc half
                ld a,(hl)
                srl a
                ld b,a
                ld a,(arc_index)
                cp b                        ; C = first half (rising)
                ld a,(player_z)
                ld hl,jump_frames_up
                jr c,.table
                ld hl,jump_frames_down
.table:         ld e,a
                ld d,0
                add hl,de
                ld a,(hl)
                ret
.running:       ld a,(move_steps_left)
                or a
                jr z,.run
                ld a,(move_dir)
                or a
                ld a,IDX_PLAYER_S1_LEAN_L
                jp m,.lean
                ld a,IDX_PLAYER_S1_LEAN_R
.lean:          ld b,a
                ld a,(player_base)
                or a
                ld a,b
                ret z
                add IDX_PLAYER_S3_RUN0-IDX_PLAYER_S1_RUN0
                ret
.run:           ld a,(anim_tick)
                rra
                and 3
                ld b,a
                ld a,(player_base)
                or a
                ld a,IDX_PLAYER_S1_RUN0
                jr z,.frame
                ld a,IDX_PLAYER_S3_RUN0
.frame:         add a,b
                ret

; by z (0..4)
jump_frames_up:
                defb IDX_PLAYER_S1_RUN0,IDX_PLAYER_S2_JUMP_UP,IDX_PLAYER_S3_JUMP_UP
                defb IDX_PLAYER_S4_JUMP_UP,IDX_PLAYER_S5_JUMP
jump_frames_down:
                defb IDX_PLAYER_S1_RUN0,IDX_PLAYER_S2_JUMP_DOWN,IDX_PLAYER_S3_JUMP_DOWN
                defb IDX_PLAYER_S4_JUMP_DOWN,IDX_PLAYER_S5_JUMP

; -----------------------------------------------------------------------------
; build_clip_table: row_clip for the picture rows the runner can reach:
; bridge decks hide it (their shadow rows do not).
; -----------------------------------------------------------------------------
CLIP_FIRST_ROW  equ 22

build_clip_table:
                ld hl,(scr_top_row)
                ld de,-CLIP_FIRST_ROW
                add hl,de                   ; world row of picture row 22
                ld ix,row_clip+CLIP_FIRST_ROW
                ld b,PICTURE_ROWS-CLIP_FIRST_ROW
.row:           push bc
                push hl
                call desc_addr
                ld c,0
                bit 7,(hl)                  ; F_BRIDGE
                jr z,.store
                inc hl                      ; D_LEFT: shadow rows stay visible
                ld a,(hl)
                cp IDX_BRIDGES_FOOTBRIDGE_SHADOW
                jr z,.store
                cp IDX_BRIDGES_ROADBRIDGE_SHADOW
                jr z,.store
                dec c
.store:         ld (ix+0),c
                inc ix
                pop hl
                dec hl                      ; next picture row = world row below
                pop bc
                djnz .row
                ret

; -----------------------------------------------------------------------------
; player_draw: restores the old runner/shadow, draws the new ones.
; Needs build_row_table for this frame.
; -----------------------------------------------------------------------------
player_draw:
                ld hl,player_save           ; restore in reverse drawing order
                call restore_sprite
                ld hl,shadow_save
                call restore_sprite

                ld a,(invuln)               ; blinking while protected
                and 2
                ret nz
                MAP_RAM GA_RAM_C5
                ld a,1                      ; hidden under bridge decks
                ld (spr_clip_on),a
                ; shadow while airborne, on the level the runner left
                ld hl,(arc_ptr)
                ld a,h
                or l
                jr z,.runner
                ld a,(player_base)
                or a
                ld a,IDX_SHADOWS_SH2
                jr z,.shadow_size
                ld a,IDX_SHADOWS_SH3
.shadow_size:   ld hl,gfx_shadows_table
                call table_entry
                push hl
                pop ix
                ld a,(player_base)          ; centre of the shadow on the feet line
                add a,a
                neg
                add FOOT_Y-2 & #FF
                ld l,a
                ld h,FOOT_Y-2 >> 8
                ld a,(ix+0)
                srl a
                neg
                ld b,a
                ld a,(player_centre)
                add a,b
                ld c,a
                ld iy,shadow_save
                call draw_sprite

.runner:        call player_sprite
                ld (player_frame),a
                ld hl,gfx_player_table
                call table_entry
                push hl
                pop ix
                ; bottom line = FOOT_Y - 2z, top = bottom - height + 1
                ld a,(player_z)
                add a,a
                ld b,a
                ld hl,FOOT_Y+1
                ld e,(ix+1)
                ld d,0
                or a
                sbc hl,de
                ld e,b
                sbc hl,de
                ld (player_top),hl
                ld a,(ix+0)                 ; column = centre - width/2
                srl a
                neg
                ld b,a
                ld a,(player_centre)
                add a,b
                ld c,a
                ld (player_column),a
                ld iy,player_save
                call draw_sprite
                xor a
                ld (spr_clip_on),a
                MAP_RAM GA_RAM_C0
                ret

; --- state ---------------------------------------------------------------------
player_state:
player_lane:    defb 0
player_centre:  defb 0                  ; byte column of the feet
move_dir:       defb 0                  ; -1 left, +1 right
move_steps_left: defb 0
move_queued:    defb 0
player_base:    defb 0                  ; 0 ground, 2 roof
player_z:       defb 0
arc_ptr:        defw 0                  ; 0 = not jumping
arc_index:      defb 0
anim_tick:      defb 0
player_frame:   defb 0                  ; last drawn frame (gfx_player_table index)
player_top:     defw 0                  ; last drawn top screen line
player_column:  defb 0                  ; last drawn column
PLAYER_STATE_SIZE equ $-player_state

PLAYER_SAVE_SIZE equ 2+24*(2+9)
player_save:    defs PLAYER_SAVE_SIZE
shadow_save:    defs 2+6*(2+7)
