; =============================================================================
; collide (src/collide.asm) in bank C7: the code only, its state stays in
; main RAM. Nothing in here maps a bank.
; =============================================================================
collide_c7:
                call runner_lane
                ld a,b
                ld (probe_lane),a

                ; --- support under the feet ---
                ld hl,FEET_PROBE
                call cell_at
                ld hl,(probe_row)
                ld (feet_row),hl
                call support_level
                ld (support),a

                ld hl,(arc_ptr)
                ld a,h
                or l
                jr nz,.airborne

                ld a,(was_airborne)         ; landing this frame?
                or a
                jr z,.walking
                xor a
                ld (was_airborne),a
                ld a,(support)              ; land on S if the jump reached it
                ld b,a
                ld a,(prev_z)
                cp b
                jp c,.crash_feet            ; jumped into the side of a train
                ld a,(player_base)
                cp b
                jp z,.front
                jr c,.set_base              ; landed higher (roof)
                ld a,b                      ; landed lower: fall the rest
                jr .drop

.walking:       ld a,(support)
                ld b,a
                ld a,(player_base)
                cp b
                jr z,.front
                jr nc,.lower
                inc a                       ; higher: one ramp step at a time
                cp b
                jp nz,.crash_feet           ; walked into a train
.set_base:      ld a,b
                ld (player_base),a
                ld (player_z),a
                jr .front
.lower:         ld a,b                      ; ground dropped away
.drop:          ld c,a
                ld a,(player_base)
                sub c
                ld b,a                      ; B = drop
                ld a,c
                ld (player_base),a
                ld a,b
                cp 2
                jr c,.small_drop
                ld hl,arc_fall              ; visible fall from the roof
                ld (arc_ptr),hl
                xor a
                ld (arc_index),a
                ld a,c
                add 2
                ld (player_z),a
                ld a,1
                ld (was_airborne),a
                jr .front
.small_drop:    ld a,c
                ld (player_z),a
                jr .front

.airborne:      ld a,(player_z)             ; descending onto a higher level
                ld b,a                      ; (springs: land on a roof)?
                ld a,(prev_z)
                cp b
                jr c,.rising
                jr z,.rising
                ld c,a                      ; C = prev_z > z
                ld a,(support)
                cp b
                jr c,.rising                ; still above the level
                ld d,a                      ; D = S >= z
                ld a,c
                cp d
                jr c,.rising                ; was below it last frame
                ld a,(player_base)
                cp d
                jr nc,.rising               ; not higher than the base
                ld hl,0
                ld (arc_ptr),hl
                xor a
                ld (was_airborne),a
                ld a,d
                ld (player_base),a
                ld (player_z),a
                jp .front
.rising:        ld a,1
                ld (was_airborne),a
                ld a,b
                ld (prev_z),a

                ; --- obstacles at the front ---
.front:         ld a,(invuln)
                or a
                ret nz
                ld a,(probe_lane)
                ld hl,FRONT_PROBE
                call cell_at
                ld hl,(probe_row)
                ld (front_row),hl
                ld b,a
                ld a,(player_z)
                ld c,a
                ld a,b
                cp COL_STOP
                jr z,.need1
                cp COL_TRAIN
                jr z,.need2
                cp COL_NOSE
                jr z,.need2
                cp COL_GAP
                jr z,.need2
                cp COL_SIGNAL
                ret nz
                ld a,(signal_red)
                or a
                ret z
                ld a,c                      ; red: only a jump from a roof clears it
                cp 3
                ret nc
                jp crash
.need2:         ld a,c
                cp 2
                ret nc
                jp crash
.need1:         ld a,c
                or a
                ret nz
                jp crash
.crash_feet:    ld a,(invuln)
                or a
                jp z,crash
                ld a,(support)              ; protected: just take that level
                ld (player_base),a
                ld (player_z),a
                ret

