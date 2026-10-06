; =============================================================================
; Collisions: what the runner stands on and what it runs into.
;
; Two probes on the runner's lane (the lane whose centre is nearest):
;   feet  (FOOT_Y-1)  - support level S of that cell:
;                       train/nose = 2, ramp up row k = k, ramp down row k = 2-k,
;                       anything else = 0
;   front (FOOT_Y-5)  - obstacles: stop needs z >= 1, train/nose z >= 2,
;                       red signal z >= 3
; On the ground the base follows S one step at a time (ramps); a drop of 2
; (end of a train) plays a short fall. Landing from a jump onto a higher
; level is only allowed if the jump was at least that high.
;
; Game states: RUN, CRASHED (crash animation, scroll stopped), GAME_OVER
; (then the score screen, src/screens.asm).
; =============================================================================

STATE_RUN       equ 0
STATE_CRASHED   equ 1
STATE_GAME_OVER equ 2

LIVES_START     equ 3
CRASH_FRAMES    equ 40                  ; 1.6 s
INVULN_FRAMES   equ 50                  ; 2 s
GAME_OVER_FRAMES equ 75                 ; 3 s
FEET_PROBE      equ FOOT_Y-1
FRONT_PROBE     equ FOOT_Y-5

; -----------------------------------------------------------------------------
; cell_at: HL = screen line, A = lane -> A = collision class (low nibble),
; B = ramp row (high nibble). Destroys C, DE, HL.
; -----------------------------------------------------------------------------
cell_at:
                ld c,a
                ld a,(cur_j)                ; picture line -> picture row
                add a,l
                ld l,a
                jr nc,.nc
                inc h
.nc:            and 7                       ; (the line in the row)
                ld (.y),a
                srl h
                rr l
                srl l
                srl l
                ex de,hl                    ; world row = top - picture row
                ld hl,(cur_top_row)
                or a
                sbc hl,de
                ld (probe_row),hl
                ld a,(train_on)             ; the moving train's lane?
                or a
                jr z,.desc
                ld a,(train_lane)
                cp c
                jr nz,.desc
                push hl
                add hl,hl                   ; world line: row * 8 + 7 - y
                add hl,hl
                add hl,hl
                ld a,(.y)
                cpl
                and 7
                call add_a_hl
                ld de,(train_lo)
                or a
                sbc hl,de
                jr c,.off                   ; below it
                ld a,h                      ; its cab coming at the runner
                or a
                jr nz,.body
                ld a,l
                cp 8
                jr nc,.body
                ld a,c
                cp 2
                ld a,COL_NOSE
                jr z,.on
.body:          add hl,de
                ld de,(train_hi)
                or a
                sbc hl,de
                jr nc,.off                  ; above it
                ld a,COL_TRAIN
.on:            pop hl
                ld b,0
                ret
.off:           pop hl
.desc:          call desc_addr
                ld a,D_COLL
                add a,c
                call add_a_hl
                ld a,(hl)
                ld b,a
                srl b
                srl b
                srl b
                srl b
                and 15
                ret
.y:             defb 0

; A = class, B = ramp row -> A = support level S
support_level:
                cp COL_GAP                  ; between two wagons: a roof, or
                jr nz,.not_gap              ; in hard mode a gap to jump
                ld a,(gap_hard)
                or a
                jr z,.roof
                xor a
                ret
.not_gap:       cp COL_TRAIN
                jr z,.roof
                cp COL_NOSE
                jr z,.roof
                cp COL_RAMP_UP
                jr z,.up
                cp COL_RAMP_DOWN
                jr z,.down
                xor a
                ret
.roof:          ld a,2
                ret
.up:            ld a,b
                ret
.down:          ld a,2
                sub b
                ret

; A = lane under the runner (nearest lane centre)
runner_lane:
                ld a,(player_centre)
                sub COL_LANE1
                ld c,LANE_BYTES
                ld b,0
.div:           sub c
                ret c                       ; (B returned in A below)
                inc b
                jr .div

; -----------------------------------------------------------------------------
; collide: after player_update. May change player_base/z, start a fall or
; a crash.
; -----------------------------------------------------------------------------
collide:
                MAP_RAM GA_RAM_C7           ; (src/collide_c7.asm)
                call collide_c7
                MAP_RAM GA_RAM_C0
                ret

; a signal turned red: its bell if one is in the 16 rows ahead of the runner
signal_bell:
                ld hl,(feet_row)
                call desc_addr
                ld a,D_COLL
                call add_a_hl               ; HL = its collision classes
                ld de,ROW_SIZE-3
                ld b,16
.row:           ld c,3                      ; (a row: 16 bytes, 16-aligned)
.lane:          ld a,(hl)
                and 15
                cp COL_SIGNAL
                jr z,.ring
                inc l
                dec c
                jr nz,.lane
                add hl,de                   ; the next row, round the ring
                ld a,h
                cp (WORLD_RING+RING_ROWS*ROW_SIZE)>>8
                jr c,.in_ring
                ld h,WORLD_RING>>8
.in_ring:       djnz .row
                ret
.ring:          ld a,SFX_SIGNAL
                ld (sfx_request),a
                ret

; fall from a roof: length, z per frame (base already lowered)
arc_fall:       defb 2, 1,1

; -----------------------------------------------------------------------------
; crash: lose a life, play the crash, stop the scroll.
; -----------------------------------------------------------------------------
crash:
                ld a,(no_crash)             ; test/debug switch
                or a
                ret nz
                ld a,SFX_CRASH              ; also when the helmet takes it
                ld (sfx_request),a
                ld a,(helmet)               ; helmet: absorbs this one
                or a
                jr z,.hurt
                xor a
                ld (helmet),a
                ld a,INVULN_FRAMES
                ld (invuln),a
                ret
.hurt:
                ld a,STATE_CRASHED
                ld (game_state),a
                ld a,CRASH_FRAMES
                ld (state_timer),a
                ld hl,0
                ld (arc_ptr),hl
                ld a,(move_steps_left)      ; hit while changing lanes: back
                or a                        ; to the lane without the obstacle
                jr z,.centre
                ld a,(probe_lane)
                ld b,a
                ld a,(player_lane)          ; (the lane moved to)
                cp b
                jr nz,.centre               ; hit in the lane left: go on to it
                ld a,(move_dir)
                ld b,a
                ld a,(player_lane)
                sub b
                ld (player_lane),a
.centre:        ld a,(player_lane)          ; on the lane's centre
                ld (probe_lane),a
                ld b,a
                ld a,LANE_CENTRE1
                inc b
                jr .times_test
.times:         add LANE_BYTES
.times_test:    djnz .times
                ld (player_centre),a
                xor a
                ld (was_airborne),a
                ld (move_steps_left),a
                ld (move_queued),a
                ld a,(player_base)
                ld (player_z),a
                ld hl,lives
                dec (hl)
                ld hl,crashes
                inc (hl)
                ret

; -----------------------------------------------------------------------------
; game_state_update: timers of CRASHED / GAME_OVER. Returns Z if the runner
; plays normally this frame.
; -----------------------------------------------------------------------------
game_state_update:
                ld a,(invuln)
                or a
                jr z,.no_invuln
                dec a
                ld (invuln),a
.no_invuln:     ld a,(game_state)
                or a
                ret z
                ld hl,state_timer
                dec (hl)
                jr nz,.busy
                cp STATE_GAME_OVER
                jr z,.new_run
                ld a,(lives)                ; crash over
                or a
                jr z,.game_over
                xor a
                ld (game_state),a
                ld a,INVULN_FRAMES
                ld (invuln),a
                ld a,(probe_lane)           ; stand on whatever is under us
                ld hl,FEET_PROBE
                call cell_at
                call support_level
                ld (player_base),a
                ld (player_z),a
.busy:          ld hl,anim_tick             ; keep the crash animation going
                inc (hl)
                or 1                        ; NZ: no normal play this frame
                ret
.game_over:     ld a,STATE_GAME_OVER
                ld (game_state),a
                ld a,GAME_OVER_FRAMES
                ld (state_timer),a
                or 1
                ret
.new_run:       call game_finished      ; score screen (or the menu after a demo)
                or 1
                ret

; -----------------------------------------------------------------------------
; effects: signal lamps (pen 15) and coin glint (pen 14) colour cycling.
; -----------------------------------------------------------------------------
effects:
                ld hl,signal_timer
                dec (hl)
                jr nz,.glint
                ld a,(signal_red)
                xor 1
                ld (signal_red),a
                ld b,a
                ld a,(difficulty)           ; red 30+6d, green 70-8d frames
                ld c,a
                add a,a
                add a,c
                add a,a                     ; 6d
                bit 0,b
                jr z,.green_time
                add 30
                jr .set_time
.green_time:    ld a,c
                add a,a
                add a,a
                add a,a                     ; 8d
                neg
                add 70
.set_time:      ld (hl),a
                ld a,b
                or a
                call nz,signal_bell
                ld a,(signal_red)
                or a
                ld a,HW_BRIGHT_RED
                jr nz,.lamp
                ld a,HW_BRIGHT_GREEN
.lamp:          ld bc,GA_PORT*256+PEN_LAMP
                out (c),c
                or GA_COLOUR
                out (c),a

.glint:         ld a,(anim_tick)
                and 3
                ret nz
                ld a,(anim_tick)
                and 4
                ld a,HW_PASTEL_YELLOW
                jr z,.glint_set
                ld a,HW_BRIGHT_WHITE
.glint_set:     ld bc,GA_PORT*256+PEN_GLINT
                out (c),c
                or GA_COLOUR
                out (c),a
                ret

; --- state ---------------------------------------------------------------------
game_state:     defb STATE_RUN
state_timer:    defb 0
lives:          defb LIVES_START
crashes:        defb 0                  ; total, for tests
invuln:         defb 0
support:        defb 0
probe_lane:     defb 0
was_airborne:   defb 0
prev_z:         defb 0
signal_red:     defb 0
signal_timer:   defb 1
no_crash:       defb 0                  ; debug: obstacles never crash the runner
probe_row:      defw 0                  ; world rows last probed (for tests)
feet_row:       defw 0
front_row:      defw 0
