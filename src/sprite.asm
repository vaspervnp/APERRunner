; =============================================================================
; Screen-fixed masked sprites (player, HUD items) on the scrolling screen.
;
; Screen line s (0..264) is shown by picture line s + cur_j, which lives in
; picture row (s+j)>>3 (rows 0-16 = D1, 17-33 = D2) at plane (s+j)&7.
; row_table holds plane-0 addresses of the 34 picture rows for the state that
; irq0 applied at the start of this game frame.
;
; A sprite line can only cross the end of a 2K plane when its row offset is
; in the last 256 bytes, so the wrap check is done once per char row and
; lines take a fast LDIR path otherwise.
;
; Sprite format: width (bytes), height (lines), then height*width
; (mask, data) pairs: screen = (screen AND mask) OR data.
; Save buffer: width, height, then per line: address (2) + width bytes.
; =============================================================================

PICTURE_ROWS    equ ROWS_PER_BLOCK*2

; -----------------------------------------------------------------------------
; build_row_table: row_table[r] for r = 0..33 from cur_d1/cur_d2.
; Destroys A, BC, DE, HL.
; -----------------------------------------------------------------------------
build_row_table:
                ld de,row_table
                ld hl,(cur_d1)
                ld c,D1_BANK_HI
                call .block
                ld hl,(cur_d2)
                ld c,D2_BANK_HI
.block:         ld b,ROWS_PER_BLOCK
.row:           ld a,l
                ld (de),a
                inc de
                ld a,h
                or c
                ld (de),a
                inc de
                ld a,l
                add ROW_BYTES
                ld l,a
                ld a,h
                adc 0
                and RING_MASK>>8
                ld h,a
                djnz .row
                ret

; -----------------------------------------------------------------------------
; row_base: HL = plane 0 address of picture row A at column C.
; Sets spr_wrap to non-zero if a line of spr_width bytes crosses a plane end.
; Destroys A, DE.
; -----------------------------------------------------------------------------
row_base:
                add a,a
                ld l,a
                ld h,0
                ld de,row_table
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,e
                add a,c
                ld l,a
                ld a,d
                adc 0
                and RING_MASK>>8
                ld h,a
                ld a,d
                and #C0
                or h
                ld h,a
                ; wrap if (H&7)=7 and 256-L < width
                xor a
                ld (spr_wrap),a
                ld a,h
                and 7
                cp 7
                ret nz
                ld a,l
                or a
                ret z
                neg
                ld e,a
                ld a,(spr_width)
                cp e
                ret c
                ret z
                ld (spr_wrap),a
                ret

; -----------------------------------------------------------------------------
; draw_sprite: IX = sprite, IY = save buffer, HL = screen line, C = column.
; Saves the background under the sprite, then draws it. The wrap test and
; the bridge clip (spr_clip_on + row_clip) are evaluated once per char row;
; the width is patched into the line loop (self-modifying code).
; Destroys everything except IX, IY.
; -----------------------------------------------------------------------------
draw_sprite:
                ld a,(ix+0)
                ld (spr_width),a
                ld (iy+0),a
                ld (.save_width+1),a        ; SMC: ld bc,width
                ld (.draw_width+1),a        ; SMC: ld b,width
                add a,a
                ld (.skip_width+1),a        ; SMC: ld bc,width*2
                ld a,(ix+1)
                ld (spr_lines),a
                ld (iy+1),a
                push ix
                pop de
                inc de
                inc de
                ld (spr_src),de
                push iy
                pop de
                inc de
                inc de
                ld (spr_save),de
                ld a,c
                ld (spr_column),a

                ld a,(cur_j)                ; picture line -> row, plane
                add a,l
                ld l,a
                jr nc,.no_carry
                inc h
.no_carry:      ld a,l
                and 7
                ld (spr_plane),a
                srl h
                rr l
                srl l
                srl l
                ld a,l
                ld (spr_row),a

.row:           ld a,(spr_column)           ; per char row: base, wrap, clip
                ld c,a
                ld a,(spr_row)
                call row_base
                ld (spr_base),hl
                call spr_clipped
                ld (spr_hidden),a

.line:          ld a,(spr_plane)            ; HL = line address
                add a,a
                add a,a
                add a,a
                ld hl,(spr_base)
                or h
                ld h,a
                ld de,(spr_save)            ; record the address
                ex de,hl
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ex de,hl
                ld a,(spr_wrap)
                or a
                jr nz,.slow

                push hl                     ; save background: screen -> buffer
.save_width:    ld bc,0
                ldir
                ld (spr_save),de
                pop hl
                ld a,(spr_hidden)
                or a
                jr nz,.hidden
                ld de,(spr_src)             ; draw: (screen AND mask) OR data
.draw_width:    ld b,0
.fast_byte:     ld a,(de)
                and (hl)
                inc de
                ld c,a
                ld a,(de)
                or c
                inc de
                ld (hl),a
                inc hl
                djnz .fast_byte
                ld (spr_src),de
                jr .next_line

.hidden:        ld hl,(spr_src)             ; under a bridge deck: skip the pairs
.skip_width:    ld bc,0
                add hl,bc
                ld (spr_src),hl
                jr .next_line

.slow:          ld a,(spr_width)            ; line crosses the plane end
                ld b,a
                push ix
                ld ix,(spr_src)
                ld a,(spr_hidden)
                or a
                jr nz,.slow_hidden
.slow_byte:     ld a,(hl)
                ld (de),a
                inc de
                and (ix+0)
                or (ix+1)
                ld (hl),a
                inc ix
                inc ix
                call next_ring_byte
                djnz .slow_byte
                jr .slow_done
.slow_hidden:   ld a,(hl)                   ; save only
                ld (de),a
                inc de
                inc ix
                inc ix
                call next_ring_byte
                djnz .slow_hidden
.slow_done:     ld (spr_save),de
                ld (spr_src),ix
                pop ix

.next_line:     ld hl,spr_lines
                dec (hl)
                ret z
                ld hl,spr_plane
                inc (hl)
                ld a,(hl)
                cp 8
                jp nz,.line
                ld (hl),0                   ; next char row
                ld hl,spr_row
                inc (hl)
                jp .row

; -----------------------------------------------------------------------------
; restore_sprite: HL = save buffer filled by draw_sprite (width 0 = empty).
; Destroys A, BC, DE, HL.
; -----------------------------------------------------------------------------
restore_sprite:
                ld a,(hl)
                or a
                ret z
                ld (spr_width),a
                ld (hl),0
                inc hl
                ld a,(hl)
                ld (spr_lines),a
                inc hl
.line:          ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld a,(spr_width)
                ld c,a
                ld b,0
                ld a,d                      ; can this line cross a plane end?
                and 7
                cp 7
                jr nz,.fast
                ld a,e
                or a
                jr z,.fast
                neg
                cp c
                jr nc,.fast
                ld b,c
.slow_byte:     ld a,(hl)
                ld (de),a
                inc hl
                inc de
                ld a,d
                and 7
                or e
                jr nz,.slow_next
                ld a,d
                sub 8
                ld d,a
.slow_next:     djnz .slow_byte
                jr .next_line
.fast:          ldir
.next_line:     ld a,(spr_lines)
                dec a
                ld (spr_lines),a
                jr nz,.line
                ret

; A = non-zero if clipping is on (spr_clip_on: runner and shadow only) and
; picture row spr_row is hidden by row_clip. Destroys BC.
spr_clipped:
                ld a,(spr_clip_on)
                or a
                ret z
                push hl
                ld a,(spr_row)
                ld c,a
                ld b,0
                ld hl,row_clip
                add hl,bc
                ld a,(hl)
                pop hl
                ret

; HL = next byte of a screen line, wrapping at the end of a 2K plane.
next_ring_byte:
                inc hl
                ld a,h
                and 7
                or l
                ret nz
                ld a,h
                sub 8
                ld h,a
                ret

; --- work variables ------------------------------------------------------------
spr_width:      defb 0
spr_lines:      defb 0
spr_plane:      defb 0
spr_row:        defb 0
spr_column:     defb 0
spr_wrap:       defb 0
spr_base:       defw 0
spr_src:        defw 0
spr_save:       defw 0
spr_clip_on:    defb 0                  ; 1 = honour row_clip (runner and shadow)
spr_hidden:     defb 0                  ; current char row is hidden

row_table:      defs PICTURE_ROWS*2
row_clip:       defs PICTURE_ROWS           ; non-zero: sprites are not drawn in that picture row
