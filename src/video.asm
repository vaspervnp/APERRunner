; =============================================================================
; Screen memory primitives for the 2K-per-plane rings of D1/D2.
;
; Line y (0-7) of a char row lives at bank + y*#800 + ring offset, and the
; ring offset wraps inside each 2K plane (96 does not divide 2048, so a row
; can be split at the wrap point). Addresses below are absolute.
; =============================================================================

; -----------------------------------------------------------------------------
; row_addr: HL = address of plane 0 of row A (0-17) in a block.
;   DE = block ring offset (bytes), C = bank high byte (#80/#C0).
; Destroys A, DE.
; -----------------------------------------------------------------------------
row_addr:
                add a,a
                ld l,a
                ld h,0
                push bc
                ld bc,row_offsets
                add hl,bc
                pop bc
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                add hl,de
                ld a,h
                and RING_MASK>>8
                or c
                ld h,a
                ret

row_offsets:
                repeat ROWS_PER_BLOCK+1,row
                defw (row-1)*ROW_BYTES
                rend

; -----------------------------------------------------------------------------
; copy_row: copies a full char row (8 planes x 96 bytes).
;   HL = source plane 0, DE = destination plane 0.
; The ring offset is the same in every plane, so the wrap test is done once:
; rows that do not cross a plane end are copied with the LDI chain.
; Destroys A, BC, DE, HL.
; -----------------------------------------------------------------------------
copy_row:
                ld c,ROW_BYTES
                call ring_fits
                jr nz,.slow
                ex de,hl
                call ring_fits
                ex de,hl
                jr nz,.slow
                ld a,8
.fast_plane:    push hl
                push de
                call ldi_chain_end-2*ROW_BYTES
                pop de
                pop hl
                ld bc,PLANE_SIZE
                add hl,bc
                ex de,hl
                add hl,bc
                ex de,hl
                dec a
                jr nz,.fast_plane
                ret
; a plane end cuts the lines at the same offsets in every plane: the cuts
; once, then per plane three LDI chains, a pointer at a plane end back to
; its plane start after each cut
.slow:          call .room
                ld b,a                      ; B = the source's cut
                ex de,hl
                call .room                  ; A = the destination's
                ex de,hl
                cp b
                jr c,.sorted
                ld c,b
                ld b,a
                ld a,c
.sorted:        ld c,a                      ; C = first cut, B = second
                cp b
                push hl
                push de
                ld hl,.fix                  ; both at once: the second fix
                jr nz,.two                  ; would take a plane start for
                ld hl,.nofix                ; a plane end
.two:           ld (.f2+1),hl
                ld a,c
                call .entry
                ld (.c1+1),hl
                ld a,b
                sub c
                call .entry
                ld (.c2+1),hl
                ld a,ROW_BYTES
                sub b
                call .entry
                ld (.c3+1),hl
                pop de
                pop hl
                ld a,8
.plane:         push af
                push hl
                push de
.c1:            call 0                      ; SMC: chain entries
                call .fix
.c2:            call 0
.f2:            call .fix                   ; SMC: .fix / .nofix
.c3:            call 0
                pop de
                pop hl
                ld bc,PLANE_SIZE
                add hl,bc
                ex de,hl
                add hl,bc
                ex de,hl
                pop af
                dec a
                jr nz,.plane
                ret
; a pointer that reached a 2K boundary wraps to its plane start
.fix:           ld a,h
                and 7
                or l
                jr nz,.fix_de
                ld a,h
                sub 8
                ld h,a
.fix_de:        ld a,d
                and 7
                or e
                ret nz
                ld a,d
                sub 8
                ld d,a
.nofix:         ret
; HL = ring address: A = bytes before its plane end, ROW_BYTES at most
.room:          ld a,h
                and 7
                cp 7
                jr nz,.whole
                ld a,l
                neg
                jr z,.whole
                cp ROW_BYTES
                ret c
.whole:         ld a,ROW_BYTES
                ret
; A = bytes: HL = the LDI chain entry for them
.entry:         add a,a
                ld e,a
                ld d,0
                ld hl,ldi_chain_end
                or a
                sbc hl,de
                ret

; -----------------------------------------------------------------------------
; ring_fits: Z if C bytes from ring address HL stay inside its 2K plane.
; Destroys A.
; -----------------------------------------------------------------------------
ring_fits:
                ld a,h
                and 7
                cp 7
                jr nz,.yes                  ; not in the last 256 bytes
                ld a,l
                or a
                ret z                       ; offset #700: 256 bytes of room
                neg
                cp c                        ; room - C: carry if it does not fit
                jr c,.no
.yes:           xor a                       ; Z = fits
                ret
.no:            or 1
                ret

; -----------------------------------------------------------------------------
; LDI chain: "call ldi_chain_end-2*n" copies n bytes (n <= 96) HL -> DE.
; BC is decremented (ignored), A is preserved.
; -----------------------------------------------------------------------------
ldi_chain:
                repeat ROW_BYTES
                ldi
                rend
ldi_chain_end:
                ret

; -----------------------------------------------------------------------------
; ring_column: DE = plane 0 ring address DE moved right by A bytes (wraps).
; Destroys A.
; -----------------------------------------------------------------------------
ring_column:
                add a,e
                ld e,a
                ld a,d
                adc 0
                and #C7                     ; keep bank + ring bits (plane 0)
                ld d,a
                ret

; -----------------------------------------------------------------------------
; ring_put: copies C bytes (1-255) from linear HL to ring address DE.
; HL ends after the source bytes. Destroys A, BC, DE.
; -----------------------------------------------------------------------------
ring_put:
                ld a,d
                and 7
                cp 7
                jr nz,.direct
                ld a,e
                or a
                jr z,.direct
                neg                         ; room before the plane end
                cp c
                jr nc,.direct
                ld b,a
                ld a,c
                sub b
                ld (.rest),a
                ld c,b
                ld b,0
                ldir
                ld a,d
                sub 8
                ld d,a
                ld a,(.rest)
                ld c,a
.direct:        ld b,0
                ldir
                ret
.rest:          defb 0

; -----------------------------------------------------------------------------
; blit_tile: draws a char-row tile (8 lines of C bytes, linear at HL)
; at plane 0 ring address DE. HL ends after the tile. Destroys A, BC, DE.
; -----------------------------------------------------------------------------
blit_tile:
                ex de,hl                    ; wrap test once for all planes
                call ring_fits
                ex de,hl
                jr nz,.slow
                push hl                     ; SMC: call the chain for C bytes
                ld a,c
                add a,a
                ld c,a
                ld b,0
                ld hl,ldi_chain_end
                or a
                sbc hl,bc
                ld (.call+1),hl
                pop hl
                ld a,8
.plane:         push de
.call:          call 0
                pop de
                ex de,hl
                ld bc,PLANE_SIZE
                add hl,bc
                ex de,hl
                dec a
                jr nz,.plane
                ret

.slow:          ld b,8
.slow_plane:    push bc
                push de
                call ring_put
                pop de
                ld a,d
                add 8
                ld d,a
                pop bc
                djnz .slow_plane
                ret
