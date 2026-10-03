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
; ring_copy: copies C bytes (1-96) from HL to DE. Either pointer may wrap at
; the end of a 2K plane. A linear source must not sit in the last 256 bytes
; of a 2K-aligned block (H&7 = 7) nor end exactly on a 2K boundary.
; Destroys A, BC, HL, DE.
; -----------------------------------------------------------------------------
ring_copy:
.segment:       ld b,c                      ; B = bytes this segment
                ld a,h
                and 7
                cp 7
                jr nz,.src_ok
                ld a,l
                or a
                jr z,.src_ok
                neg                         ; room before the plane end
                cp b
                jr nc,.src_ok
                ld b,a
.src_ok:        ld a,d
                and 7
                cp 7
                jr nz,.dst_ok
                ld a,e
                or a
                jr z,.dst_ok
                neg
                cp b
                jr nc,.dst_ok
                ld b,a
.dst_ok:        ld a,c
                sub b
                ld (.remaining),a
                ld c,b
                ld b,0
                ldir
                ; a pointer that reached a 2K boundary wraps to its plane start
                ld a,h
                and 7
                or l
                jr nz,.src_in
                ld a,h
                sub 8
                ld h,a
.src_in:        ld a,d
                and 7
                or e
                jr nz,.dst_in
                ld a,d
                sub 8
                ld d,a
.dst_in:        ld a,(.remaining)
                ld c,a
                or a
                jr nz,.segment
                ret
.remaining:     defb 0

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
.slow:          ld a,8
.plane:         push af
                push hl
                push de
                ld c,ROW_BYTES
                call ring_copy
                pop de
                pop hl
                pop af
                ld bc,PLANE_SIZE
                add hl,bc
                ex de,hl
                add hl,bc
                ex de,hl
                dec a
                jr nz,.plane
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
