"""Phase 1: overscan + vertical hardware scroll + screen-fixed sprites.

Pictures are read from the emulator framebuffer (one row per scanline,
4 framebuffer pixels per mode 0 pixel). Screen-fixed elements on the
scrolling screen are tested with the HUD (test_hud.py) and the runner.
"""

from harness import boot_game, load_symbols, peek8, sync_game_frame

PLAYFIELD_RIGHT = 576    # framebuffer x where the HUD starts
HUD_X = 588              # framebuffer x in the HUD frame (the green stripe), left of the panel
COMPARE_LINES = range(40, 200)   # below the top edge, above the runner (7 lines down too)
SPEEDS = range(1, 8)                 # up to 7: hard + turbo


COIN = (255, 255, 0)     # stands for every coin colour


def _steady(p):
    """Pens 14 (coin glint) and 15 (signal lamp) cycle their colours, and
    coins turn (coin_spin): map the coin colours to one value, a wildcard
    in the comparison, and the lamp colours to one other."""
    if p[0] > 200 and p[1] > 200 and p[2] > 80:          # pastel yellow / bright white
        return COIN
    if p[0] > 100 and abs(p[0] - p[1]) < 30 and p[2] < 50:  # bright yellow, yellow
        return COIN
    if p[0] < 50 and p[1] > 200 and p[2] < 50:            # lamp green -> lamp red
        return (255, 0, 0)
    if p[0] > 200 and 80 < p[1] < 180 and p[2] < 50:     # lamp amber -> lamp red
        return (255, 0, 0)
    return p


COIN_SPAN = 32           # framebuffer pixels: a coin is 4 bytes wide


def same_row(a, b):
    """Equal lines, but where a coin is (a coin colour within a coin's
    width, in either line) anything goes: it may have turned."""
    if a == b:
        return True
    coins = [x for x in range(len(a)) if COIN in (a[x], b[x])]
    return all(any(abs(x - c) < COIN_SPAN for c in coins)
               for x in range(len(a)) if a[x] != b[x])


def _rows(img):
    return [tuple(_steady(p) for p in img.crop((0, y, PLAYFIELD_RIGHT, y + 1)).getdata())
            for y in range(img.height)]


def _shift_between(before, after):
    """Lines the playfield moved down from `before` to `after` (None if no match)."""
    for shift in range(0, 9):
        if all(same_row(after[y + shift], before[y]) for y in COMPARE_LINES):
            return shift
    return None


def _set_speed(cpc, sym, speed):
    cpc.write_ram(sym["scroll_speed"], bytes([speed]))


def test_no_missed_frames_at_any_speed():
    sym = load_symbols()
    cpc = boot_game()
    for speed in SPEEDS:
        _set_speed(cpc, sym, speed)
        cpc.run_frames(250)
    missed = peek8(cpc, sym["missed_frames"])
    max_load = peek8(cpc, sym["max_load"])
    print(f"    max load {max_load}/12 interrupt periods")
    assert missed == 0, f"{missed} game frames missed"
    assert max_load < 12, f"work does not fit in a game frame (load {max_load})"


def test_scroll_moves_exactly_speed_lines_per_game_frame():
    sym = load_symbols()
    cpc = boot_game()
    for speed in SPEEDS:
        _set_speed(cpc, sym, speed)
        sync_game_frame(cpc, sym)                    # let the new speed settle
        before = _rows(sync_game_frame(cpc, sym))
        for i in range(16):
            after = _rows(sync_game_frame(cpc, sym))
            moved = _shift_between(before, after)
            assert moved == speed, f"speed {speed}, frame {i}: moved {moved} lines"
            before = after


def test_hud_panel_is_static():
    sym = load_symbols()
    cpc = boot_game()
    _set_speed(cpc, sym, 3)
    reference = None
    for _ in range(16):
        img = sync_game_frame(cpc, sym)
        # skip the top 8 lines: the picture edge moves with the fine scroll
        # (and the black border below the picture's last line, 268)
        column = [img.getpixel((HUD_X, y)) for y in range(8, 268)]
        assert len(set(column)) == 1, "HUD panel column is not uniform"
        if reference is None:
            reference = column[0]
        assert column[0] == reference
