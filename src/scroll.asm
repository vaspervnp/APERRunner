; =============================================================================
; Vertical scroll: the world moves down the screen by scroll_speed lines per
; game frame. Fine steps change j (picture position), every 8 lines a coarse
; step moves both blocks' start addresses up one row:
;   - D1 gets a freshly drawn row at its new top,
;   - D2's new top row is a copy of the row that just left D1's bottom.
; Rows are drawn by draw_world_row (src/world.asm: row number in HL,
; destination plane 0 in DE), always in increasing row order.
; =============================================================================

; -----------------------------------------------------------------------------
; scroll_init: fills both blocks with world rows and publishes the state.
; World row 0 is at the bottom of the screen, numbers grow upwards; rows are
; generated in that order (D2 bottom first, D1 top last).
; -----------------------------------------------------------------------------
scroll_init:
                xor a
                ld (scr_j),a
                ld hl,0
                ld (scr_d1),hl
                ld (scr_d2),hl
                ld hl,ROWS_PER_BLOCK*2-1
                ld (scr_top_row),hl

                ld hl,0                     ; world row n
.row:           push hl
                ld a,l
                cp ROWS_PER_BLOCK
                jr nc,.in_d1
                neg                         ; D2 row 16-n
                add ROWS_PER_BLOCK-1
                ld de,(scr_d2)
                ld c,D2_BANK_HI
                jr .addr
.in_d1:         neg                         ; D1 row 33-n
                add ROWS_PER_BLOCK*2-1
                ld de,(scr_d1)
                ld c,D1_BANK_HI
.addr:          call row_addr
                ex de,hl
                pop hl
                push hl
                call draw_world_row
                pop hl
                inc hl
                ld a,l
                cp ROWS_PER_BLOCK*2
                jr nz,.row
                jp publish_scroll

; -----------------------------------------------------------------------------
; scroll_step: advances the scroll by A lines (1-8) and publishes it.
; -----------------------------------------------------------------------------
scroll_step:
                ld b,a
                ld a,(scr_j)
                sub b
                jr nc,.fine_only
                add 8
                ld (scr_j),a
                call coarse_step
                jp publish_scroll
.fine_only:     ld (scr_j),a
                jp publish_scroll

coarse_step:
                ; D1 moves up one row in its ring, new row 0 = next world row
                ld hl,(scr_d1)
                ld bc,-ROW_BYTES
                add hl,bc
                ld a,h
                and RING_MASK>>8
                ld h,a
                ld (scr_d1),hl

                ld hl,(scr_top_row)
                inc hl
                ld (scr_top_row),hl

                xor a
                ld de,(scr_d1)
                ld c,D1_BANK_HI
                call row_addr
                ex de,hl
                ld hl,(scr_top_row)
                call draw_world_row

                ; D2 moves up one row, its new row 0 = D1's old bottom row (now 17)
                ld hl,(scr_d2)
                ld bc,-ROW_BYTES
                add hl,bc
                ld a,h
                and RING_MASK>>8
                ld h,a
                ld (scr_d2),hl

                xor a
                ld de,(scr_d2)
                ld c,D2_BANK_HI
                call row_addr
                push hl
                ld a,ROWS_PER_BLOCK
                ld de,(scr_d1)
                ld c,D1_BANK_HI
                call row_addr
                pop de
                jp copy_row

; --- state (work copy; irq0 uses the published one) ---------------------------
scr_j:          defb 0
scr_d1:         defw 0
scr_d2:         defw 0
scr_top_row:    defw 0              ; world row number shown in D1 row 0
