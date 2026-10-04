; =============================================================================
; pick_chunk_c5: the next track chunk, weighted random among the chunks the
; difficulty and the environment allow (src/data/chunks.asm). Runs in bank
; C5 with the chunk table (src/world.asm pick_chunk maps it). One pass
; works out the weights into chunk_weights, the second only subtracts.
; =============================================================================
pick_chunk_c5:
                ld hl,chunk_table
                ld de,chunk_weights
                ld b,CHUNK_COUNT
                ld c,0                      ; C = total weight
.weigh:         push hl
                ld a,(hl)                   ; HL = chunk: rows, difficulty,
                inc hl                      ; weight, environment
                ld h,(hl)
                ld l,a
                inc hl
                ld a,(difficulty)
                cp (hl)
                jr c,.no                    ; too early for it
                inc hl
                inc hl
                ld a,(hl)                   ; environment: 0 any, 1 urban, 2 forest
                dec hl
                or a
                jr z,.yes
                dec a
                push bc
                ld b,a
                ld a,(env)
                cp b
                pop bc
                jr nz,.no
.yes:           ld a,(hl)                   ; its weight
                jr .store
.no:            xor a
.store:         ld (de),a
                inc de
                add a,c
                ld c,a
                pop hl
                inc hl
                inc hl
                djnz .weigh
                ld a,c
                or a
                jr nz,.pick
                inc c                       ; nothing eligible: the first one
.pick:          call random_below           ; A = 0 .. total-1
                ld hl,chunk_weights
                ld de,chunk_table
                ld b,CHUNK_COUNT
.find:          sub (hl)
                jr c,.found
                inc hl
                inc de
                inc de
                djnz .find
                ld de,chunk_table           ; (rounding safety) chunk 0
.found:         ex de,hl
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ld a,(hl)
                ld (chunk_left),a
                ld de,4
                add hl,de
                ld (chunk_ptr),hl
                ret

chunk_weights:  defs CHUNK_COUNT
