; =============================================================================
; save_scores_c7: the high score table back to the disc, straight through
; the uPD765 (the firmware is gone). SCORES is the first file on the disc:
; its record is sector #C5 of track 0 (tools/tests/test_scores.py checks).
; Written: "APER", the table, #1A padding (a text file for the loader).
; Runs in bank C7. The drive motor gets half a second to spin up (the
; interrupts run meanwhile); the 512 data bytes go with interrupts off
; (about 16 ms: the still screen may show one odd frame). Gives up quietly
; if the controller does not answer (no drive) or reports an error.
; =============================================================================

FDC_MOTOR       equ #FA7E
FDC_STATUS      equ #FB7E
FDC_DATA        equ #FB7F
SCORES_TRACK    equ 0
SCORES_SECTOR   equ #C5
SPIN_UP_VBLS    equ 25

save_scores_c7:
                ld bc,FDC_MOTOR
                ld a,1
                out (c),a
                ld a,(vbl_tick)             ; spin up
                add SPIN_UP_VBLS
                ld e,a
.spin:          ld a,(vbl_tick)
                cp e
                jr nz,.spin
                ld a,7                      ; recalibrate: head to track 0
                call fdc_out
                jr c,.off
                xor a
                call fdc_out
                jr c,.off
.sense:         ld a,8                      ; sense interrupt until it is there
                call fdc_out
                jr c,.off
                call fdc_in                 ; ST0
                jr c,.off
                ld d,a
                call fdc_in                 ; track
                jr c,.off
                bit 5,d                     ; seek end
                jr z,.sense
                di
                ld hl,write_command         ; write data, MFM
                ld b,9
.command:       ld a,(hl)
                call fdc_out
                jr c,.done
                inc hl
                djnz .command
                ld hl,score_magic           ; "APER"
                ld b,4
                call fdc_bytes
                jr c,.done
                ld hl,hiscore_table         ; the table
                ld b,HISCORES*HS_SIZE
                call fdc_bytes
                jr c,.done
                ld de,512-4-HISCORES*HS_SIZE
.pad:           ld a,#1A                    ; text file padding
                call fdc_out
                jr c,.done
                dec de
                ld a,d
                or e
                jr nz,.pad
                ld b,7                      ; result phase
.result:        call fdc_in
                jr c,.done
                djnz .result
.done:          ei
.off:           ld bc,FDC_MOTOR
                xor a
                out (c),a
                ret

write_command:  defb #45,0,SCORES_TRACK,0,SCORES_SECTOR,2,SCORES_SECTOR,#2A,#FF

; HL = bytes, B = count -> the controller. CY: no answer.
fdc_bytes:
                ld a,(hl)
                call fdc_out
                ret c
                inc hl
                djnz fdc_bytes
                ret

; A -> the controller when it asks for a byte. CY: no answer. Keeps BC, DE, HL.
fdc_out:
                push de
                push bc
                ld c,a
                ld de,0                     ; timeout
.wait:          push bc
                ld bc,FDC_STATUS
                in a,(c)
                pop bc
                and #C0
                cp #80                      ; ready, CPU -> controller
                jr z,.send
                dec de
                ld a,d
                or e
                jr nz,.wait
                pop bc
                pop de
                scf
                ret
.send:          ld a,c
                ld bc,FDC_DATA
                out (c),a
                pop bc
                pop de
                or a
                ret

; A <- the controller. CY: no answer. Keeps BC, DE, HL.
fdc_in:
                push de
                push bc
                ld de,0
.wait:          ld bc,FDC_STATUS
                in a,(c)
                and #C0
                cp #C0                      ; ready, controller -> CPU
                jr z,.take
                dec de
                ld a,d
                or e
                jr nz,.wait
                pop bc
                pop de
                scf
                ret
.take:          ld bc,FDC_DATA
                in a,(c)
                pop bc
                pop de
                or a                        ; (NC)
                ret
