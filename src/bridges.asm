; =============================================================================
; bridges.asm - a bridge row (bank C4, called by render_row)
;
; The bridge tiles (src/data/gfx_bridges.asm, png2cpc kind "lines") are 8
; line pointers each; a line is a run of ops: n (1-127) and n bytes to copy
; (through ldi_chain), or #80 + n and a byte to fill n times (br_fill, a
; byte for 4 NOPs). A row across a plane end goes line by line through
; BR_BUF and ring_put.
; =============================================================================

BR_BUF          equ hud_buf_end             ; a line (below the stack)
                assert BR_BUF+GFX_BRIDGES_WIDTH <= #0E00

; HL = tile, DE = plane 0 ring address of the row
bridge_tile:
                ld (br_line),hl
                xor a
                call ring_column
                ld (br_dest),de
                ex de,hl
                ld c,GFX_BRIDGES_WIDTH
                call ring_fits              ; NZ: a plane end on the way
                ld a,0
                jr z,.mode
                inc a
.mode:          ld (br_wrap),a
                ld b,GFX_BRIDGES_HEIGHT
.line:          push bc
                ld hl,(br_line)
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld (br_line),hl
                ex de,hl                    ; HL = its ops
                ld de,(br_dest)
                ld a,(br_wrap)
                or a
                jr nz,.wrap
                call br_ops
                jr .next
.wrap:          ld de,BR_BUF
                call br_ops
                ld hl,BR_BUF
                ld de,(br_dest)
                ld c,GFX_BRIDGES_WIDTH
                call ring_put
.next:          ld a,(br_dest+1)            ; the next line: a plane on
                add 8
                ld (br_dest+1),a
                pop bc
                djnz .line
                ret

; HL = ops, DE = where they go (no plane end)
br_ops:         ld a,(hl)
                inc hl
                or a
                ret z
                jp m,.fill
                add a,a                     ; copy: n LDIs of ldi_chain
                ld c,a
                ld b,0
                push hl
                ld hl,ldi_chain_end
                sbc hl,bc                   ; (no carry: n <= 72)
                ld (.copy+1),hl
                pop hl
.copy:          call 0
                jr br_ops
.fill:          add a,a                     ; fill: n of br_fill
                ld c,a
                ld b,0
                ld a,(hl)
                inc hl
                push hl
                ld hl,br_fill_end
                or a
                sbc hl,bc
                ld (.call+1),hl
                pop hl
.call:          call 0
                jr br_ops

br_fill:        repeat GFX_BRIDGES_WIDTH
                ld (de),a
                inc de
                rend
br_fill_end:    ret

br_line:        defw 0                      ; the tile's next line pointer
br_dest:        defw 0                      ; ring address of the line
br_wrap:        defb 0                      ; 1: across a plane end
