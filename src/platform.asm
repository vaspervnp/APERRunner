; =============================================================================
; platform.asm - the stations' platforms (bank C4, called by render_row)
;
; From a station row on (world.asm: plat_left, D_PLAT = rows left), after
; a few rows the sides get a platform next to the track: 7 bytes a side
; (pixels 16-29 of the left side tile, 0-13 of the right), built line by
; line from the platform sheet (src/data/gfx_platform.asm, left and
; mirrored lines back to back) or, at the two ends, from the side tile.
; =============================================================================

PLAT_BUF        equ hud_buf_end             ; 8 lines x 7 bytes (below the stack)
plat_env        equ PLAT_BUF+8*7            ; the side tile, at its first kept byte
plat_side       equ plat_env+2              ; 0 left, 7 right (mirrored lines)
plat_base       equ plat_side+1             ; the row's 8 lines (plat_kinds)
                assert plat_base+2 <= #0E00

; A = D_PLAT, IX = row descriptor (render_row.sides: its side tiles)
platform_strip:
                ld hl,plat_seq-1
                call add_a_hl
                ld a,(hl)                   ; offset in plat_kinds, #FF none
                inc a
                ret z
                dec a
                ld hl,plat_kinds
                call add_a_hl
                ld (plat_base),hl
                ld a,(ix+D_LEFT)
                ld bc,8*256+0               ; its bytes 8-14, left lines
                call .build
                ld b,COL_LEFT+8
                call .put
                ld a,(ix+D_RIGHT)
                ld bc,0*256+7               ; its bytes 0-6, mirrored lines
                call .build
                ld b,COL_RIGHT
.put:           ld hl,PLAT_BUF
                ld c,7
                jp render_row.blit

; A = side tile, B = its first byte, C = plat_side: PLAT_BUF
.build:         ld hl,(render_row.sides)
                push bc
                call table_entry
                pop bc
                ld a,b
                call add_a_hl
                ld (plat_env),hl
                ld a,c
                ld (plat_side),a
                ld iy,(plat_base)
                ld de,PLAT_BUF
                ld b,8
.line:          ld hl,(plat_env)
                ld a,(iy+0)
                inc iy
                inc a
                jr z,.copy                  ; #FF: the side tile shows
                dec a
                ld hl,plat_side
                add a,(hl)
                ld hl,gfx_platform
                call add_a_hl
.copy:          push bc
                ld bc,7
                ldir
                ld hl,(plat_env)
                ld c,SIDE_BYTES
                add hl,bc
                ld (plat_env),hl
                pop bc
                djnz .line
                ret

; line offsets in gfx_platform (left; the mirrored line follows)
PL_CONCRETE     equ IDX_PLATFORM_CONCRETE*7
PL_JOINT        equ IDX_PLATFORM_JOINT*7
PL_SEAT         equ IDX_PLATFORM_BENCH_SEAT*7
PL_BACK         equ IDX_PLATFORM_BENCH_BACK*7
PL_BSHADOW      equ IDX_PLATFORM_BENCH_SHADOW*7
PL_ROOF_A       equ IDX_PLATFORM_ROOF_A*7
PL_ROOF_B       equ IDX_PLATFORM_ROOF_B*7
PL_SIGN_EDGE    equ IDX_PLATFORM_SIGN_EDGE*7
PL_SIGN_TEXT    equ IDX_PLATFORM_SIGN_TEXT*7
PL_RAMP         equ IDX_PLATFORM_RAMP*7
PL_RSHADOW      equ IDX_PLATFORM_ROOF_SHADOW*7
PL_SIDE         equ #FF                     ; the side tile's line

; the kinds of platform rows: 8 lines, top to bottom, as windows on one
; stream (they overlap)
plat_kinds:
PK_END_LO       equ $-plat_kinds            ; the near end: a ramp
                defb PL_CONCRETE,PL_CONCRETE,PL_CONCRETE,PL_CONCRETE,PL_CONCRETE,PL_RAMP
PK_END_HI       equ $-plat_kinds            ; the far end
                defb PL_SIDE,PL_SIDE,PL_RAMP,PL_CONCRETE
PK_PLAIN        equ PK_END_HI+3
                defb PL_CONCRETE,PL_CONCRETE,PL_CONCRETE,PL_JOINT,PL_CONCRETE
PK_BENCH        equ $-plat_kinds
                defb PL_CONCRETE,PL_CONCRETE,PL_BACK,PL_SEAT,PL_BSHADOW,PL_CONCRETE,PL_CONCRETE,PL_JOINT
PK_SIGN         equ $-plat_kinds            ; a name board on the canopy
                defb PL_ROOF_A,PL_ROOF_B,PL_SIGN_EDGE,PL_SIGN_TEXT,PL_SIGN_TEXT,PL_SIGN_EDGE
PK_ROOF         equ $-plat_kinds
                defb PL_ROOF_B
PK_ROOF_LO      equ $-plat_kinds            ; the canopy, its shadow below
                defb PL_ROOF_A,PL_ROOF_B,PL_ROOF_A,PL_ROOF_B,PL_ROOF_A,PL_ROOF_B,PL_ROOF_A,PL_RSHADOW

; by D_PLAT (1 = the top row .. PLAT_ROWS = the station row)
plat_seq:       defb PK_END_HI,PK_PLAIN,PK_BENCH,PK_PLAIN,PK_PLAIN,PK_BENCH,PK_PLAIN
                defb PK_ROOF,PK_SIGN,PK_ROOF,PK_ROOF,PK_SIGN,PK_ROOF,PK_ROOF_LO
                defb PK_PLAIN,PK_BENCH,PK_PLAIN,PK_END_LO
                defb #FF,#FF,#FF,#FF            ; the station row and 3 more: none
PLAT_ROWS       equ $-plat_seq
