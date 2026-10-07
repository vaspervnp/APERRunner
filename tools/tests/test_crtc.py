"""Phase 10: the overscan scroll on CRTC types 0, 1 and 2 (as the emulator
models them): the picture moves by the speed every game frame, its edges
stay put, the HUD stays still, no frame is missed."""

from collections import Counter

from harness import boot_game, load_symbols, peek8, save_screenshot, sync_frame
import test_scroll as ts

PLAYFIELD = range(0, 576, 8)
COMPARE = range(40, 200)                 # above the runner even 7 lines down


def _shift(before, after):
    for shift in range(9):
        if all(ts.same_row(after[y + shift], before[y]) for y in COMPARE):
            return shift
    return None


def _edges(img):
    def black(y):
        return all(max(img.getpixel((x, y))) < 40 for x in PLAYFIELD)
    return next(y for y in range(312) if not black(y)), max(y for y in range(272) if not black(y))


def test_scroll_on_every_crtc_type():
    sym = load_symbols()
    for crtc in (0, 1, 2):
        cpc = boot_game(crtc=crtc)
        for speed in (4, 7):
            cpc.write_ram(sym["scroll_speed"], bytes([speed]))
            sync_frame(cpc, sym)
            sync_frame(cpc, sym)
            prev, shifts, edges, hud = None, [], set(), set()
            for _ in range(40):
                img, _ = sync_frame(cpc, sym)
                rows = ts._rows(img)
                if prev:
                    shifts.append(_shift(prev, rows))
                prev = rows
                edges.add(_edges(img))
                hud.add(tuple(img.getpixel((ts.HUD_X, y)) for y in range(8, 260, 16)))
            counts = Counter(shifts)
            print(f"    CRTC {crtc}, speed {speed}: shifts {dict(counts)}, edges {edges}")
            assert set(counts) == {0, speed} and abs(counts[0] - counts[speed]) <= 1, counts
            assert len(edges) == 1, f"CRTC {crtc}: the edges move {edges}"
            assert len(hud) == 1, f"CRTC {crtc}: the HUD frame moves"
        save_screenshot(cpc, f"crtc{crtc}.png")
        assert peek8(cpc, sym["missed_frames"]) == 0
