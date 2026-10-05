"""Phase 7: the HUD stays still on the scrolling screen and shows the values.

Pictures are read from the emulator framebuffer: screen line s is image
line s + IMAGE_Y, mode 0 pixel x is image x 4*x.
"""

import os
import sys

from harness import FRAME_US, IMAGE_Y, ROOT, boot_game, load_symbols, peek8, peek16, save_screenshot, sync_game_frame

sys.path.insert(0, os.path.join(ROOT, "tools"))
import cpcpalette  # noqa: E402
import png2cpc  # noqa: E402

SL_SIZE, SLOTS, SL_STATE = 15, 5, 14
PANEL_PEN, GLINT_PEN = 1, 14
BAND = range(80, 204)                   # screen lines the slots can reach


def _palette():
    return {pen: cpcpalette.CPC_COLOURS[cpcpalette.GAME_PALETTE[pen][0]][1] for pen in range(16)}


def _pen(rgb, palette):
    """Nearest game pen of an emulator colour."""
    def dist(value):
        r, g, b = cpcpalette.rgb_tuple(value)
        return (r - rgb[0]) ** 2 + (g - rgb[1]) ** 2 + (b - rgb[2]) ** 2
    return min(palette, key=lambda pen: dist(palette[pen]))


def slots(cpc, sym):
    out = []
    for k in range(SLOTS):
        y, x, w, h, lo, hi = cpc.read_ram(sym["hud_slots"] + k * SL_SIZE, 6)
        state = peek8(cpc, sym["hud_slots"] + k * SL_SIZE + SL_STATE)
        out.append({"y": y, "x": x, "w": w, "h": h, "buf": lo | hi << 8, "drawn": state & 1})
    return out


def buffer_pens(cpc, slot):
    lines = []
    for line in range(slot["h"]):
        row = []
        for b in cpc.read_ram(slot["buf"] + line * slot["w"], slot["w"]):
            row += png2cpc.decode_byte(b)
        lines.append(row)
    return lines


def snapshot(cpc, sym):
    """Slot buffers now."""
    return [buffer_pens(cpc, slot) for slot in slots(cpc, sym)]


def game_frame(cpc, sym):
    """(image, buffers): the picture of the first frame of the next game
    frame and the slot buffers it draws (read at its VSYNC, after the previous
    frame's hud_prepare and before the drawing)."""
    while True:
        tick = peek8(cpc, sym["vbl_tick"])
        while peek8(cpc, sym["vbl_tick"]) == tick:
            cpc.run_us(64)
        tick = peek8(cpc, sym["vbl_tick"])
        if (tick - peek8(cpc, sym["last_tick"])) & 255 >= 2:
            buffers = snapshot(cpc, sym)
            cpc.run_us(FRAME_US - 128)
            return cpc.image(full_framebuffer=True), buffers


def expected_panel(cpc, sym, buffers):
    """{(screen line, pixel x): pen} over the panel band: panel colour except
    where a slot is drawn (drawn flags now, contents from `buffers`)."""
    first = sym["hud_panel_first"] * 2
    last = sym["hud_panel_last"] * 2 + 1
    exp = {(y, x): PANEL_PEN for y in BAND for x in range(first, last + 1)}
    for slot, lines in zip(slots(cpc, sym), buffers):
        if not slot["drawn"]:
            continue
        for line, row in enumerate(lines):
            for i, pen in enumerate(row):
                exp[(slot["y"] + line, slot["x"] * 2 + i)] = pen
    return exp


def check_panel(img, exp, palette):
    bad = []
    for (y, x), pen in exp.items():
        got = _pen(img.getpixel((x * 4 + 1, y + IMAGE_Y)), palette)
        if got != pen and not (pen == GLINT_PEN and got in (3, 14)):
            bad.append((y, x, pen, got))
    return bad


def test_hud_is_still_at_every_speed():
    sym = load_symbols()
    cpc = boot_game()
    palette = _palette()
    cpc.write_ram(sym["helmet"], bytes([6]))            # 4 power-ups: two rows of cells
    cpc.write_ram(sym["pu_ticket"], (375).to_bytes(2, "little"))
    cpc.write_ram(sym["pu_magnet"], (250).to_bytes(2, "little"))
    cpc.write_ram(sym["pu_spring"], (250).to_bytes(2, "little"))
    for speed in (1, 2, 3, 4, 5, 6, 0):
        cpc.write_ram(sym["scroll_speed"], bytes([speed]))
        sync_game_frame(cpc, sym)
        for frame in range(12):
            img, buffers = game_frame(cpc, sym)
            bad = check_panel(img, expected_panel(cpc, sym, buffers), palette)
            if bad:
                save_screenshot(cpc, "hud_bad.png")
            assert not bad, f"speed {speed}, frame {frame}: {len(bad)} pixels differ, first {bad[:3]}"
    save_screenshot(cpc, "hud.png")
    assert peek8(cpc, sym["missed_frames"]) == 0


def _glyphs():
    sheet = png2cpc.load_sheet("hud")
    return {name: [[1 if p is None else p for p in row] for row in rows] for name, rows in sheet.items()}


def _cells(lines, start, width):
    return [row[start * 2:(start + width) * 2] for row in lines]


def test_hud_shows_the_values():
    sym = load_symbols()
    cpc = boot_game()
    cpc.write_ram(sym["scroll_speed"], bytes([0]))
    for _ in range(2):                                          # the world stands still
        sync_game_frame(cpc, sym)
    cpc.write_ram(sym["score"], bytes([0x56, 0x34, 0x12]))      # 123456: above the best
    cpc.write_ram(sym["coins"], bytes([0x42, 0x00]))            # 0042
    cpc.write_ram(sym["lives"], bytes([2]))
    cpc.write_ram(sym["pu_magnet"], (125).to_bytes(2, "little"))  # half of 250
    cpc.write_ram(sym["no_pickups"], bytes([1]))
    for _ in range(3):
        sync_game_frame(cpc, sym)
    glyph = _glyphs()
    score, best, coins, first, second = slots(cpc, sym)

    def digits(slot, offset, text, kind="d"):
        lines = buffer_pens(cpc, slot)[:8]
        for i, d in enumerate(text):
            assert _cells(lines, offset + 2 * i, 2) == glyph[f"{kind}{d}"], f"digit {i} of {text}"

    digits(score, 0, "123456")
    digits(best, 0, "123456", "h")                              # the best score: this one, in orange
    lines = buffer_pens(cpc, coins)
    assert _cells(lines[:8], 0, 4) == glyph["ic_coin"]
    digits(coins, 4, "0042")
    assert _cells(lines[:8], 12, 4) == glyph["ic_life"]
    digits(coins, 16, "2")
    route = lines[9:12]                                         # station ticks, the track
    assert [route[0][x] for x in (6, 12, 35)] == [3, 3, 3]
    assert 13 in route[1] and set(route[1]) <= {2, 7, 13}, "the runner on the grey track"
    # the six power-ups: lit with a time bar when running, dark otherwise
    shelf = buffer_pens(cpc, first)
    assert _cells(shelf[:7], 0, 4) == glyph["ic_magnet"][:7]
    assert shelf[7][:8] == [7] * 4 + [PANEL_PEN] * 4, "half of the magnet's time"
    assert _cells(shelf[:8], 4, 4) == glyph["ic_turbo_off"]
    assert _cells(shelf[:8], 8, 4) == glyph["ic_slow_off"]
    shelf = buffer_pens(cpc, second)
    for cell, name in enumerate(("ic_helmet_off", "ic_spring_off", "ic_ticket_off")):
        assert _cells(shelf[:8], 4 * cell, 4) == glyph[name], name
    cpc.write_ram(sym["coins"], bytes([0x43, 0x00]))            # one digit changes
    for _ in range(2):
        sync_game_frame(cpc, sym)
    digits(coins, 4, "0043")


def test_power_up_goes_dark_when_it_ends():
    sym = load_symbols()
    cpc = boot_game()
    palette = _palette()
    cpc.write_ram(sym["pu_spring"], (30).to_bytes(2, "little"))
    cpc.write_ram(sym["pu_ticket"], (200).to_bytes(2, "little"))
    glyph = _glyphs()
    lit = False
    sync_game_frame(cpc, sym)
    for _ in range(40):
        img, buffers = game_frame(cpc, sym)
        cells = buffer_pens(cpc, slots(cpc, sym)[4])
        lit |= _cells(cells[:7], 4, 4) == glyph["ic_spring"][:7]
        assert not check_panel(img, expected_panel(cpc, sym, buffers), palette)
    assert lit and peek16(cpc, sym["pu_spring"]) == 0
    cells = buffer_pens(cpc, slots(cpc, sym)[4])
    assert _cells(cells[:8], 4, 4) == glyph["ic_spring_off"], "the springs went dark"
    assert _cells(cells[:7], 8, 4) == glyph["ic_ticket"][:7], "the ticket still runs"


def test_route_and_stations():
    """A station every ROUTE_SEG rows: its board on the HUD's little track,
    its name on the track when the runner gets there, Piraeus' bonus."""
    sym = load_symbols()
    cpc = boot_game()
    cpc.write_ram(sym["scroll_speed"], bytes([6]))
    names, boards = [], 0
    seen = set()
    score_at = None
    last_next = peek8(cpc, sym["station_next"])
    score_now = 0

    def bcd(cpc, addr):
        value = 0
        for byte in reversed(cpc.read_ram(addr, 3)):
            value = value * 100 + (byte >> 4) * 10 + (byte & 15)
        return value
    for _ in range(4000):
        sync_game_frame(cpc, sym)
        top = peek16(cpc, sym["scr_top_row"])
        for r in range(top - 20, top):
            if r not in seen:
                seen.add(r)
                desc = cpc.read_ram(sym["world_ring"] + (r & 63) * sym["row_size"], 1)[0]
                boards += bool(desc & 2)
        last_score, score_now = score_now, bcd(cpc, sym["score"])
        nxt = peek8(cpc, sym["station_next"])
        if nxt != last_next:                    # a station passed: its name
            last_next = nxt
            names.append(peek8(cpc, sym["label_item"]))
            if names[-1] == 18:                 # Piraeus: 1000 points at once
                score_at = bcd(cpc, sym["score"]) - last_score
        if len(names) >= 7:
            break
    print(f"    {boards} station boards, labels {names}, Piraeus: +{score_at}")
    assert names[:7] == [13, 14, 15, 16, 17, 18, 13], names         # Corinth .. Piraeus, Corinth again
    assert boards >= 7
    assert 1000 <= score_at < 1100
