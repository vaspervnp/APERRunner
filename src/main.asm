; =============================================================================
; Runner A.P.E.R - Athens Piraeus Electric Railways
; Amstrad CPC 6128 - Z80 (rasm)
;
; Memory: code + variables from &1000 (main RAM); graphics in the 6128's
; extra banks, mapped at &4000 when needed:
;   C4 - tiles (track, sides, bridges, HUD)      -> build/aperb4.bin
;   C5 - sprites (scenery, items, player) + track chunks -> build/aperb5.bin
;   C6 - compiled sprites (runner)              -> build/aperb6.bin
;   C7 - menus: font, logo, texts               -> build/aperb7.bin
; DISC (BASIC) loads both banks, then APER.BIN at &4000 (BASIC only loads
; above HIMEM) and calls it: a stub moves the code down to &1000.
; =============================================================================

                ifndef DEBUG
DEBUG           equ 0
                endif

LOAD_ADDR       equ #1000
STACK_TOP       equ LOAD_ADDR

; sprite save buffers below the code (the code must end below &4000: it runs
; while banks are mapped there). &0400-&087F: world ring and overlays.
PLAYER_SAVE_SIZE equ 2+24*(2+9)
SHADOW_SAVE_SIZE equ 2+6*(2+7)
player_save     equ #0040
shadow_save     equ player_save+PLAYER_SAVE_SIZE
flyer_saves     equ shadow_save+SHADOW_SAVE_SIZE    ; FLYER_COUNT*FLY_SAVE_SIZE
text_ptrs       equ flyer_saves+FLYER_COUNT*FLY_SAVE_SIZE ; TXT_COUNT*2 (set_language)
text_buf        equ text_ptrs+TXT_COUNT*2       ; 24
blank_line      equ text_buf+24                 ; 72 zeros (start)
label_buf       equ #0880                           ; LABEL_BUF_SIZE (stack: &0E00-&0FFF)
hud_buf_score   equ label_buf+LABEL_BUF_SIZE        ; HUD slot buffers (src/hud.asm)

VBLS_PER_FRAME  equ 2               ; 25 fps
DEFAULT_SPEED   equ 4               ; lines per game frame

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
SCORES_LOAD     equ #7F00           ; the loader puts SCORES (high scores) here

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
                ld hl,SCORES_LOAD           ; high scores saved on the disc
                ld de,score_magic           ; (the loader read them there)
                ld b,4
.magic:         ld a,(de)
                cp (hl)
                jr nz,.no_scores
                inc hl
                inc de
                djnz .magic
                ld de,hiscore_table
                ld bc,HISCORES*HS_SIZE
                ldir
.no_scores:     call crtc_init
                ld hl,game_palette
                call set_palette
                ld hl,blank_line            ; (below the code: not loaded)
                ld de,blank_line+1
                ld bc,71
                ld (hl),0
                ldir
                xor a                       ; English
                call set_language
                call new_run
                call go_menu

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
                BORDER #12                  ; bright green: HUD, runner, sprites
                call hud_update             ; top to bottom, ahead of the beam
                ld a,(sound_due)            ; then this VSYNC's sound tick
                or a
                call nz,sound_late
                call read_input
                ld a,(game_mode)            ; menus: a still screen
                cp MODE_MENU
                jr c,.playing
                call screen_frame
                jr .frame_done
.playing:       call play_input             ; ESC, pause, demo keys
                jr nz,main_loop

                ; sprites first: the beam is still above the bottom of the picture
                call restore_flyers         ; reverse drawing order
                call player_restore
                call game_state_update
                jr nz,.not_playing
                call move_trains            ; before collide: it sees them where they are
                call player_update
                call collide
                ld a,(game_state)
                or a
                jr nz,.not_playing
                call pickups                ; erases picked-up items: no sprite on screen now
                call magnet
                call tick_powerups
                call late_erase             ; a picked-up power-up off the screen
                call stations               ; a station's name, the Piraeus bonus
                call draw_label             ; a power-up's name on the track
.not_playing:   call move_flyers
                call effects
                call build_clip_table
                call player_draw
                call draw_flyers
                ; then the scroll for the next game frame (off-screen rows only)
                BORDER #0C                  ; bright red: scroll work
                ld a,(game_state)           ; the world stops while crashed
                or a
                ld a,0
                jr nz,.scroll
                call current_speed          ; turbo / slow / normal
.scroll:        call scroll_step
                call hud_prepare            ; next frame's HUD contents
.frame_done:    BORDER #14                  ; black
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
                call hud_init
                xor a
                ld (gap_hard),a             ; (start_game: the difficulty)
                ld (game_state),a
                ld (invuln),a
                ld (was_airborne),a
                ld a,LIVES_START
                ld (lives),a
                ld a,DEFAULT_SPEED
                ld (scroll_speed),a
                ei
                ret

; sound_late: the sound tick irq0 left for after the HUD (bank C7)
sound_late:
                xor a
                ld (sound_due),a
                MAP_RAM GA_RAM_C7
                call sound_tick
                MAP_RAM GA_RAM_C0
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
                include "hud.asm"
                include "screens.asm"
                include "data/palette.asm"

; --- variables (fixed labels, read by tools/tests) ---------------------------
frame_counter:  defw 0              ; game frames
missed_frames:  defb 0              ; saturates at 255
last_tick:      defb 0
frame_load:     defb 0              ; see measure_load
max_load:       defb 0
scroll_speed:   defb DEFAULT_SPEED
paused:         defb 0

end_of_code:
                print "END_OF_CODE ",{hex4}end_of_code
                assert end_of_code <= #4000
                assert FILE_ADDR+BOOT_STUB_SIZE+end_of_code-LOAD_ADDR <= SCORES_LOAD
                assert blank_line+72 <= WORLD_RING
                assert HUD_BUF_END <= #0E00         ; the stack: &0E00-&0FFF
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
                include "trains.asm"                ; moving trains (code)
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
                include "data/chunks.asm"
                include "chunk_pick.asm"
bank5_end:
                assert bank5_end <= #8000
                save "build/aperb5.bin",bank5_start,bank5_end-bank5_start

; =============================================================================
; Bank C6 (compiled sprites: code that runs mapped at &4000)
; =============================================================================
                bank
                org #4000
bank6_start:
                include "data/gfx_player_code.asm"
bank6_end:
                assert bank6_end <= #8000
                save "build/aperb6.bin",bank6_start,bank6_end-bank6_start

; =============================================================================
; Bank C7 (menus: font, logo, texts)
; =============================================================================
                bank
                org #4000
bank7_start:
                include "data/gfx_font.asm"
                include "data/gfx_logo.asm"
                include "data/text.asm"
                include "sound.asm"
                include "data/gfx_hud_icons.asm"    ; (hud_prepare maps C7)
                include "hud_slots.asm"
                include "data/gfx_urban_ov_code.asm"    ; (render_row: overlays)
                include "data/gfx_forest_ov_code.asm"
                include "scores_save.asm"
                include "data/music.asm"
bank7_end:
                assert bank7_end <= #8000
                save "build/aperb7.bin",bank7_start,bank7_end-bank7_start
