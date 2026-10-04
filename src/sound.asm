; =============================================================================
; Sound: music on AY channels A (melody) and B (bass), effects on channel C.
;
; sound_tick runs from irq2 (50 times a second, whatever the game's frame
; rate), with bank C7 mapped: this file, the tunes and the effects
; (src/data/music.asm, tools/mkmusic.py) live in C7. The game asks for an
; effect by writing its number to sfx_request (main RAM); a higher priority
; effect interrupts a lower one.
;
; The tune follows game_mode: TUNE_GAME while playing (and in the demo),
; TUNE_OVER once on the game over screen, TUNE_MENU on the other screens.
; sound_on = 0 or a pause silences everything; music_on = 0 (M while
; playing, MUSIC in the menu) only the tunes.
;
; AY registers are kept in ay_shadow and only the ones that changed are
; written (ay_flush). Mixer: tones A-C on, noise only on C when an effect
; asks for it, I/O port A input (the keyboard is read through it).
; =============================================================================

MIXER_BASE      equ %00111000           ; tones on, noise off, port A input
MIXER_TONE_C    equ %00000100           ; 1 = tone C off
MIXER_NOISE_C   equ %00100000           ; 0 = noise C on
AY_REGS         equ 11                  ; R0-R10 (no envelope)

; channel record (IX)
CH_PTR          equ 0                   ; (2) next event
CH_START        equ 2                   ; (2) loop point
CH_TICKS        equ 4                   ; ticks left of the note
CH_VOL          equ 5
CH_PERIOD       equ 6                   ; (2)
CH_REG          equ 8                   ; its period register (0 / 2)
CH_VOLREG       equ 9                   ; its volume register (8 / 9)
CH_TOP          equ 10                  ; volume at the start of a note
CH_FLOOR        equ 11                  ; decays down to this

; -----------------------------------------------------------------------------
; sound_tick: one 1/50 s step (irq2, bank C7). Destroys AF, BC, DE, HL, IX.
; -----------------------------------------------------------------------------
sound_tick:
                ld b,TUNE_GAME              ; the tune for this screen
                ld a,(game_mode)
                cp MODE_MENU
                jr c,.chosen
                ld b,TUNE_OVER
                cp MODE_OVER
                jr z,.chosen
                ld b,TUNE_MENU
.chosen:        ld a,(snd_tune)
                cp b
                call nz,start_tune
                ld ix,chan_a
                call channel_tick
                ld ix,chan_b
                call channel_tick
                call sfx_tick
                ld a,(sound_on)
                or a
                jr z,.mute
                ld a,(paused)
                or a
                jr nz,.mute
                ld a,(music_on)             ; M: music off, effects on
                or a
                jr nz,ay_flush
                ld (ay_shadow+8),a
                ld (ay_shadow+9),a
                jr ay_flush
.mute:          xor a
                ld (ay_shadow+8),a
                ld (ay_shadow+9),a
                ld (ay_shadow+10),a
                ; fall through

; ay_shadow -> AY, only the registers that changed since the last flush
ay_flush:
                ld hl,ay_shadow
                ld ix,ay_last
                ld d,0                      ; D = register
.reg:           ld a,(hl)
                cp (ix+0)
                jr z,.same
                ld (ix+0),a
                ld e,a
                ld b,PPI_A                  ; select register D
                out (c),d
                ld bc,PPI_C*256+#C0
                out (c),c
                ld bc,PPI_C*256+#00
                out (c),c
                ld b,PPI_A                  ; write E
                out (c),e
                ld bc,PPI_C*256+#80
                out (c),c
                ld bc,PPI_C*256+#00
                out (c),c
.same:          inc hl
                inc ix
                inc d
                ld a,d
                cp AY_REGS
                jr nz,.reg
                ret

; B = tune: both channels from its start
start_tune:
                ld a,b
                ld (snd_tune),a
                add a,a
                add a,a
                ld hl,tune_table
                call add_a_hl
                ld ix,chan_a
                call .channel
                ld ix,chan_b
.channel:       ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld (ix+CH_PTR),e
                ld (ix+CH_PTR+1),d
                ld (ix+CH_START),e
                ld (ix+CH_START+1),d
                ld (ix+CH_TICKS),1          ; the first note on this tick
                ret

; IX = channel: next note when the current one ends, volume decay, shadow
channel_tick:
                dec (ix+CH_TICKS)
                jr z,.next
                ld a,(ix+CH_TICKS)          ; last tick of a note: half volume
                dec a                       ; (notes do not run together)
                ld a,(ix+CH_VOL)
                jr nz,.decay
                srl a
                jr .set_vol
.decay:         cp (ix+CH_FLOOR)
                jr c,.shadow
                jr z,.shadow
                dec a
.set_vol:       ld (ix+CH_VOL),a
                jr .shadow
.next:          ld l,(ix+CH_PTR)
                ld h,(ix+CH_PTR+1)
                ld a,(hl)
                cp TUNE_LOOP
                jr nz,.not_loop
                ld l,(ix+CH_START)
                ld h,(ix+CH_START+1)
                ld a,(hl)
.not_loop:      cp TUNE_STOP
                jr nz,.note
                ld (ix+CH_TICKS),1          ; stays on the end mark, silent
                ld (ix+CH_VOL),0
                jr .shadow
.note:          inc hl
                ld c,a                      ; C = note (0 = rest)
                ld a,(hl)
                inc hl
                ld (ix+CH_TICKS),a
                ld (ix+CH_PTR),l
                ld (ix+CH_PTR+1),h
                ld a,c
                or a
                jr z,.rest
                dec a
                add a,a
                ld hl,note_periods
                call add_a_hl
                ld a,(hl)
                ld (ix+CH_PERIOD),a
                inc hl
                ld a,(hl)
                ld (ix+CH_PERIOD+1),a
                ld a,(ix+CH_TOP)
                ld (ix+CH_VOL),a
                jr .shadow
.rest:          ld (ix+CH_VOL),0
.shadow:        ld hl,ay_shadow
                ld a,(ix+CH_REG)
                call add_a_hl
                ld a,(ix+CH_PERIOD)
                ld (hl),a
                inc hl
                ld a,(ix+CH_PERIOD+1)
                ld (hl),a
                ld hl,ay_shadow
                ld a,(ix+CH_VOLREG)
                call add_a_hl
                ld a,(ix+CH_VOL)
                ld (hl),a
                ret

; effects on channel C: takes sfx_request, plays one step per tick
sfx_tick:
                ld a,(sfx_request)
                or a
                jr z,.run
                ld c,a
                xor a
                ld (sfx_request),a
                ld a,c                      ; entry = sfx_table + 3 * (n - 1)
                dec a
                ld b,a
                add a,a
                add a,b
                ld hl,sfx_table
                call add_a_hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld b,(hl)                   ; B = priority
                ld hl,(sfx_ptr)             ; one playing with a higher one?
                ld a,h
                or l
                jr z,.take
                ld a,(sfx_prio)
                ld c,a
                ld a,b
                cp c
                jr c,.run
.take:          ld (sfx_ptr),de
                ld a,b
                ld (sfx_prio),a
.run:           ld hl,(sfx_ptr)
                ld a,h
                or l
                jr z,.quiet
                ld e,(hl)                   ; DE = period
                inc hl
                ld d,(hl)
                inc hl
                ld a,(hl)                   ; A = volume | flags
                inc hl
                ld c,(hl)                   ; C = noise period
                inc hl
                cp SFX_END
                jr z,.done
                ld (sfx_ptr),hl
                ld (ay_shadow+4),de
                ld b,a
                and 15
                ld (ay_shadow+10),a
                ld a,c
                ld (ay_shadow+6),a
                ld a,MIXER_BASE
                bit 7,b                     ; SFX_TONE_OFF
                jr z,.tone
                or MIXER_TONE_C
.tone:          bit 6,b                     ; SFX_NOISE_ON
                jr z,.mixer
                and MIXER_NOISE_C^#FF
.mixer:         ld (ay_shadow+7),a
                ret
.done:          ld hl,0
                ld (sfx_ptr),hl
.quiet:         xor a
                ld (ay_shadow+10),a
                ld a,MIXER_BASE
                ld (ay_shadow+7),a
                ret

; --- state (bank C7; initial values come with the bank file) -------------------
snd_tune:       defb #FF                ; tune playing (#FF: none yet)
chan_a:         defw 0,0                ; ptr, start
                defb 1,0                ; ticks, volume
                defw 0                  ; period
                defb 0,8,13,9           ; period reg, volume reg, top, floor
chan_b:         defw 0,0
                defb 1,0
                defw 0
                defb 2,9,12,8
sfx_ptr:        defw 0                  ; 0: no effect
sfx_prio:       defb 0
ay_shadow:      defs 7,0                ; R0-R6
                defb MIXER_BASE         ; R7
                defs 3,0                ; R8-R10
ay_last:        defs AY_REGS,#FF        ; what the AY holds (#FF: write it)
