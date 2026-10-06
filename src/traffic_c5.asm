; =============================================================================
; traffic_c5.asm - a moving car drawn (bank C5, with its sprite): world.asm
; move_cars calls draw_car, which maps this bank.
; =============================================================================

; IY = mover: its 16 lines, opaque, row by row (car_line: the address of
; each row once), a line up a plane back.
draw_car_c5:
                ld l,(iy+MV_LO)
                ld h,(iy+MV_LO+1)
                ld (car_at),hl
                ld a,CAR_LINES
                ld (car_left),a
                bit 7,(iy+MV_DIR)           ; sprite line at the bottom: going
                ld a,0                      ; up its last, coming down its
                ld hl,8                     ; first (front down); a line up:
                jr nz,.first                ; the next pair row, or the one
                                            ; before
                ld a,CAR_LINES-1
                ld hl,-8
.first:         ld (car_step),hl
                add a,a
                add a,a
                add a,a                     ; * 8 bytes (pairs), + width, height
                add a,3                     ; and mask: the data byte of the
                ld l,(iy+MV_SPR)            ; first pair
                ld h,(iy+MV_SPR+1)
                call add_a_hl
                ld (car_src),hl
.row:           ld hl,(car_at)               ; B = its lines in this row
                ld a,l
                and 7
                xor 7
                inc a
                ld b,a
                ld a,(car_left)
                cp b
                jr nc,.lines
                ld b,a
.lines:         sub b
                ld (car_left),a
                push bc
                call car_line               ; DE = its bottom line here
                pop bc
                jr nz,.skip
.line:          ld hl,(car_src)
                push de
                ld a,(car_wrap)
                or a
                jr nz,.wrap
                ld a,(hl)                   ; CAR_W = 4 data bytes
                ld (de),a
                inc hl
                inc hl
                inc de
                ld a,(hl)
                ld (de),a
                inc hl
                inc hl
                inc de
                ld a,(hl)
                ld (de),a
                inc hl
                inc hl
                inc de
                ld a,(hl)
                ld (de),a
                jr .drawn
.wrap:          push bc
                ld c,2
                call car_bytes
                pop bc
.drawn:         pop de
                ld a,d                      ; the line above: a plane back
                sub 8
                ld d,a
                call .next
                djnz .line
                jr .row_done
.skip:          call .next
                djnz .skip
.row_done:      ld a,(car_left)
                or a
                jr nz,.row
                ret
.next:          ld hl,(car_src)             ; a line up: source and world line
                push de
                ld de,(car_step)
                add hl,de
                ld (car_src),hl
                pop de
                ld hl,(car_at)
                inc hl
                ld (car_at),hl
                ret
