; =============================================================================
; platform.asm - the stations' platforms (bank C4, called by render_row)
;
; From a station row on (world.asm: plat_left, D_PLAT = rows left), after
; a few rows the sides get a platform next to the track: 7 bytes a side
; (pixels 16-29 of the left side tile, 0-13 of the right). Each kind of
; platform row is a block per side (src/data/gfx_platform.asm, from
; assets.PLATFORM_KINDS): its lines, 7 LDIs each; at the two ends some
; lines are left to the side tile under it.
; =============================================================================

PLAT_ROWS       equ GFX_PLATFORM_SEQ_LEN

; A = D_PLAT
platform_strip:
                ld hl,gfx_platform_seq-1
                call add_a_hl
                ld a,(hl)                   ; its kind, #FF none
                cp #FF
                ret z
                ld l,a
                add a,a
                add a,l
                add a,a                     ; * 6
                ld hl,gfx_platform_kinds
                call add_a_hl
                ld e,(hl)                   ; left block
                inc hl
                ld d,(hl)
                inc hl
                push de
                ld e,(hl)                   ; right block
                inc hl
                ld d,(hl)
                inc hl
                ld a,(hl)
                ld (plat_first),a
                inc hl
                ld a,(hl)
                ld (plat_lines),a
                ex de,hl
                ld a,COL_RIGHT
                call .put
                pop hl
                ld a,COL_LEFT+SIDE_BYTES-GFX_PLATFORM_WIDTH
; HL = block, A = column: its lines from plat_first down
.put:           ld de,(render_row.dest)
                call ring_column
                ld a,(plat_first)
                add a,a
                add a,a
                add a,a
                add a,d
                ld d,a
                push hl
                ex de,hl
                ld c,GFX_PLATFORM_WIDTH
                call ring_fits              ; NZ: across a plane end
                ex de,hl
                pop hl
                ld a,(plat_lines)
                ld b,a
                jr nz,.wrap
                ld c,#FF                    ; (LDI counts BC down: B stays)
.line:          push de
                repeat GFX_PLATFORM_WIDTH
                ldi
                rend
                pop de
                ld a,d                      ; the next line: a plane on
                add 8
                ld d,a
                djnz .line
                ret
.wrap:          push bc
                push de
                ld c,GFX_PLATFORM_WIDTH
                call ring_put
                pop de
                ld a,d
                add 8
                ld d,a
                pop bc
                djnz .wrap
                ret

plat_first:     defb 0                      ; the kind's first line
plat_lines:     defb 0                      ; and its lines
