; =============================================================================
; Runner A.P.E.R - Athens Piraeus Electric Railways
; Amstrad CPC 6128 - Z80 (rasm)
;
; Memory: code + variables from &1000 (main RAM); graphics in the 6128's
; extra banks, mapped at &4000 when needed:
;   C4 - tiles (track, sides, bridges, HUD)      -> build/aperb4.bin
;   C5 - sprites (scenery, items, player) + track chunks -> build/aperb5.bin
; DISC (BASIC) loads both banks, then APER.BIN at &4000 (BASIC only loads
; above HIMEM) and calls it: a stub moves the code down to &1000.
; =============================================================================

                ifndef DEBUG
DEBUG           equ 0
                endif

LOAD_ADDR       equ #1000           ; temporary until the loader exists (Phase 8)
STACK_TOP       equ LOAD_ADDR

VBLS_PER_FRAME  equ 2               ; 25 fps
DEFAULT_SPEED   equ 2               ; lines per game frame

                include "hw.asm"

; BORDER hwcolour : debug-only raster timing marker. Destroys BC.
macro BORDER colour
                if DEBUG
                ld bc,GA_PORT*256+GA_SELECT_BORDER
                out (c),c
                ld c,GA_COLOUR|{colour}
                out (c),c
                endif
mend

FILE_ADDR       equ #4000           ; where DISC loads APER.BIN

                org FILE_ADDR
boot_stub:
                di
                ld hl,FILE_ADDR+BOOT_STUB_SIZE
                ld de,LOAD_ADDR
                ld bc,end_of_code-LOAD_ADDR
                ldir
                jp start
BOOT_STUB_SIZE  equ $-boot_stub

                org LOAD_ADDR,$             ; runs at &1000, stored after the stub
start:
                di
                ld sp,STACK_TOP
                call crtc_init
                ld hl,game_palette
                call set_palette
                call new_run

                xor a
                ld (missed_frames),a
                ld (frame_counter),a
                ld (frame_counter+1),a
                ei
                halt
                ld a,(vbl_tick)
                ld (last_tick),a

main_loop:
                call wait_game_frame
                call read_input
                ld a,(keys_pressed)         ; H toggles the pause
                and KEY_PAUSE
                jr z,.pause_ok
                ld a,(paused)
                xor 1
                ld (paused),a
.pause_ok:      ld a,(paused)
                or a
                jr nz,main_loop

                ; sprites first: the beam is still above the bottom of the picture
                BORDER #12                  ; bright green: runner + sprites
                call build_row_table
                call restore_flyers         ; reverse drawing order
                call player_restore
                call game_state_update
                jr nz,.not_playing
                call player_update
                call collide
                ld a,(game_state)
                or a
                jr nz,.not_playing
                call pickups                ; erases picked-up items: no sprite on screen now
                call magnet
                call tick_powerups
.not_playing:   call move_flyers
                call effects
                call build_clip_table
                call player_draw
                call draw_flyers
                ld hl,test_sprite_save      ; screen-fixed test item in the HUD
                call restore_sprite
                ld ix,test_sprite
                ld iy,test_sprite_save
                ld hl,(test_sprite_y)
                ld a,(test_sprite_x)
                ld c,a
                call draw_sprite
                ; then the scroll for the next game frame (off-screen rows only)
                BORDER #0C                  ; bright red: scroll work
                ld a,(game_state)           ; the world stops while crashed
                or a
                ld a,0
                jr nz,.scroll
                call current_speed          ; turbo / slow / normal
.scroll:        call scroll_step
                BORDER #14                  ; black
                call measure_load
                ld hl,(frame_counter)
                inc hl
                ld (frame_counter),hl
                jr main_loop

; -----------------------------------------------------------------------------
; new_run: fresh world, screen and runner (start and after a game over).
; -----------------------------------------------------------------------------
new_run:
                di
                call world_init
                call scroll_init
                call player_init
                call pickups_init
                xor a
                ld (game_state),a
                ld (invuln),a
                ld (was_airborne),a
                ld a,LIVES_START
                ld (lives),a
                ei
                ret

; -----------------------------------------------------------------------------
; wait_game_frame: waits until VBLS_PER_FRAME VSYNCs passed since the last
; game frame; counts the extra ones as missed frames.
; -----------------------------------------------------------------------------
wait_game_frame:
.wait:          ld a,(last_tick)
                ld b,a
                ld a,(vbl_tick)
                sub b
                cp VBLS_PER_FRAME
                jr c,.wait
                sub VBLS_PER_FRAME
                jr z,.on_time
                ld b,a
                ld a,(missed_frames)
                add b
                jr nc,.store
                ld a,255
.store:         ld (missed_frames),a
.on_time:       ld a,(vbl_tick)
                ld (last_tick),a
                ret

; -----------------------------------------------------------------------------
; measure_load: how far into the game frame the work got, in interrupt
; periods (52 lines, ~3300 NOPs): (VSYNCs since frame start)*6 + irq_index.
; A game frame has 12; keeps the maximum in max_load.
; -----------------------------------------------------------------------------
measure_load:
                di
                ld a,(last_tick)
                ld b,a
                ld a,(vbl_tick)
                sub b
                ld b,a
                add a,a
                add a,b
                add a,a                     ; *6
                ld b,a
                ld a,(irq_index)
                ei
                add a,b
                ld (frame_load),a
                ld b,a
                ld a,(max_load)
                cp b
                ret nc
                ld a,b
                ld (max_load),a
                ret

                include "crtc.asm"
                include "video.asm"
                include "scroll.asm"
                include "sprite.asm"
                include "world.asm"
                include "input.asm"
                include "player.asm"
                include "collide.asm"
                include "pickups.asm"
                include "data/palette.asm"

; 4x12 screen-fixed test item (HUD icon size): red frame, bright yellow
; (pen 7) inside, transparent corners. Replaced by the HUD in phase 7.
TEST_SPRITE_W   equ 4
TEST_SPRITE_H   equ 12
test_sprite:    defb TEST_SPRITE_W,TEST_SPRITE_H
                repeat TEST_SPRITE_H,ln
                repeat TEST_SPRITE_W,bx
                if (ln==1 || ln==TEST_SPRITE_H) && (bx==1 || bx==TEST_SPRITE_W)
                defb #FF,#00
                elseif ln==1 || ln==TEST_SPRITE_H || bx==1 || bx==TEST_SPRITE_W
                defb #00,#F3
                else
                defb #00,#FC
                endif
                rend
                rend
test_sprite_save: defb 0
                defs 1+TEST_SPRITE_H*(2+TEST_SPRITE_W)

; --- variables (fixed labels, read by tools/tests) ---------------------------
frame_counter:  defw 0              ; game frames
missed_frames:  defb 0              ; saturates at 255
last_tick:      defb 0
frame_load:     defb 0              ; see measure_load
max_load:       defb 0
scroll_speed:   defb DEFAULT_SPEED
paused:         defb 0
test_sprite_x:  defb 80             ; byte column (in the HUD: nothing else draws there)
test_sprite_y:  defw 232            ; screen line

end_of_code:
                assert end_of_code < B_ROWS_ADDR
                save "build/aper.bin",FILE_ADDR,BOOT_STUB_SIZE+end_of_code-LOAD_ADDR

; =============================================================================
; Bank C4 (tiles)
; =============================================================================
                bank
                org #4000
bank4_start:
                include "data/gfx_track.asm"
                include "data/gfx_urban.asm"
                include "data/gfx_forest.asm"
                include "data/gfx_bridges.asm"
                include "data/gfx_hud_bg.asm"
bank4_end:
                assert bank4_end <= #8000
                save "build/aperb4.bin",bank4_start,bank4_end-bank4_start

; =============================================================================
; Bank C5 (sprites, track chunks)
; =============================================================================
                bank
                org #4000
bank5_start:
                include "data/gfx_urban_ov.asm"
                include "data/gfx_forest_ov.asm"
                include "data/gfx_items.asm"
                include "data/gfx_player.asm"
                include "data/gfx_shadows.asm"
                include "data/gfx_hud_icons.asm"
                include "data/chunks.asm"
bank5_end:
                assert bank5_end <= #8000
                save "build/aperb5.bin",bank5_start,bank5_end-bank5_start
