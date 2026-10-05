; =============================================================================
; Screen-fixed masked sprites (player, HUD items) on the scrolling screen.
;
; Screen line s (0..264) is shown by picture line s + cur_j, which lives in
; picture row (s+j)>>3 (rows 0-16 = D1, 17-33 = D2) at plane (s+j)&7.
; row_base gives plane-0 addresses for the state that irq0 applied at the
; start of this game frame.
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
; row_base: HL = plane 0 address of picture row A (0-33) at column C, from
; the scroll state shown (cur_d1/cur_d2). Sets spr_wrap to non-zero if a
; line of spr_width bytes crosses a plane end. Destroys A, DE.
; -----------------------------------------------------------------------------
row_base:
                cp ROWS_PER_BLOCK
                jr nc,.d2
                ld hl,(cur_d1)
                ld e,D1_BANK_HI
                jr .block
.d2:            sub ROWS_PER_BLOCK
                ld hl,(cur_d2)
                ld e,D2_BANK_HI
.block:         push bc
                ld b,e                      ; B = bank
                add a,a                     ; + row * 96
                ld e,a
                ld d,0
                push hl
                ld hl,row_offsets
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                pop hl
                add hl,de
                ld a,c                      ; + column, inside the ring
                add a,l
                ld l,a
                ld a,h
                adc 0
                and RING_MASK>>8
                or b
                ld h,a
                pop bc
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
; draw_compiled: like draw_sprite, with the sprite's compiled code (png2cpc
; kind "compiled": saves and draws without reading the sprite data).
;   IX = sprite (width, height for the save buffer; bank C5 mapped: the data
;   is used if it falls back), IY = save buffer, HL = screen line, C = column,
;   DE = compiled code, A = bank that holds the code (GA_RAM_C5/C6...).
; Falls back to draw_sprite when a line would cross a plane end or a row is
; clipped. The code may be in a bank: C5 is mapped again afterwards.
; Destroys everything except IX, IY.
; -----------------------------------------------------------------------------
FC_MAX_ROWS     equ 4

draw_compiled:
                ld (.bank+1),a              ; SMC
                ld (.code+1),de             ; SMC
                ld a,c
                ld (fc_col),a
                ld a,(ix+0)
                ld (spr_width),a
                ld a,(ix+1)
                ld (fc_lines),a
                push hl                     ; (for the fallback)
                ld a,(cur_j)                ; picture line -> row, plane
                add a,l
                ld l,a
                jr nc,.nc
                inc h
.nc:            ld a,l
                and 7
                ld (fc_plane),a
                ld b,a
                srl h
                rr l
                srl l
                srl l
                ld a,l
                ld (spr_row),a
                ld a,(fc_lines)             ; char rows: (plane + lines - 1) / 8 + 1
                add a,b
                dec a
                rrca
                rrca
                rrca
                and #1F
                inc a
                ld b,a
                ld hl,fc_bases
                ld (fc_base_ptr),hl
.check:         push bc                     ; every row: base, no wrap, not clipped
                ld a,(fc_col)
                ld c,a
                ld a,(spr_row)
                call row_base
                call spr_clipped            ; hidden (bridge deck): drawn into a
                or a                        ; ring row nobody sees instead
                call nz,unseen_base
                ld a,(spr_wrap)
                or a
                jr nz,.fallback
                ex de,hl
                ld hl,(fc_base_ptr)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld (fc_base_ptr),hl
                ld hl,spr_row
                inc (hl)
                pop bc
                djnz .check
                pop hl
                ld a,(spr_width)            ; save buffer header
                ld (iy+0),a
                ld a,(fc_lines)
                ld (iy+1),a
                ld hl,fc_bases+2
                ld (fc_base_ptr),hl
                ld hl,(fc_bases)            ; first line
                ld a,(fc_plane)
                add a,a
                add a,a
                add a,a
                or h
                ld h,a
                ld (fc_line),hl
                push iy
                pop de
                inc de
                inc de
                ex de,hl
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ex de,hl
.bank:          ld bc,GA_PORT*256           ; SMC: code bank
                ld (cur_ram),bc
                out (c),c
.code:          call 0                      ; SMC
                MAP_RAM GA_RAM_C5
                ret
.fallback:      pop bc
                pop hl
                ld a,(fc_col)
                ld c,a
                jp draw_sprite

; HL = plane 0 address of D1 ring row 17 at column fc_col: never shown
; (D1 shows rows 0-16), not the row the next coarse step copies or draws.
; Sets spr_wrap like row_base. Destroys A, DE.
unseen_base:
                ld hl,(cur_d1)
                ld de,ROWS_PER_BLOCK*ROW_BYTES
                add hl,de
                ld a,(fc_col)
                add a,l
                ld l,a
                ld a,h
                adc 0
                and RING_MASK>>8
                or D1_BANK_HI
                ld h,a
                xor a
                ld (spr_wrap),a
                ld a,h                      ; wrap if (H&7)=7 and 256-L < width
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

; between the lines of a compiled sprite: HL = next line, its address
; written at DE (DE += 2). Destroys A.
compiled_next_line:
                ld hl,(fc_line)             ; the next plane, or past plane 7
                ld a,h                      ; (plane bits back to 0): the next
                add 8                       ; char row's base
                ld h,a
                and #38
                jr nz,.store
                push de
                ld hl,(fc_base_ptr)
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld (fc_base_ptr),hl
                ex de,hl
                pop de
.store:         ld (fc_line),hl
                ex de,hl
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ex de,hl
                ret

; -----------------------------------------------------------------------------
; restore_sprite: HL = save buffer filled by draw_sprite (width 0 = empty).
; Destroys A, BC, DE, HL.
; -----------------------------------------------------------------------------
restore_sprite:
                ld a,(hl)
                or a
                ret z
                ld (spr_width),a
                add a,a                     ; the LDI chain for a line
                neg
                ld c,a
                ld b,#FF                    ; BC = -2 * width
                push hl
                ld hl,ldi_chain_end
                add hl,bc
                ld (.chain+1),hl
                pop hl
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
.fast:
.chain:         call 0                      ; SMC
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
                inc l
                ret nz
                inc h
                ld a,h
                and 7
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
fc_col:         defb 0                  ; compiled sprites
fc_lines:       defb 0
fc_plane:       defb 0
fc_line:        defw 0
fc_base_ptr:    defw 0
fc_bases:       defs FC_MAX_ROWS*2

row_clip:       defs PICTURE_ROWS           ; non-zero: sprites are not drawn in that picture row
