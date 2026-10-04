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
BAND = range(56, 168)                   # screen lines the slots can reach


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
    cpc.write_ram(sym["score"], bytes([0x56, 0x34, 0x12]))      # 123456
    cpc.write_ram(sym["coins"], bytes([0x42, 0x00]))            # 0042
    cpc.write_ram(sym["lives"], bytes([2]))
    cpc.write_ram(sym["pu_magnet"], (125).to_bytes(2, "little"))  # half of 250
    cpc.write_ram(sym["no_pickups"], bytes([1]))
    for _ in range(3):
        sync_game_frame(cpc, sym)
    glyph = _glyphs()
    score, coins, lives, cells, more_cells = slots(cpc, sym)

    def digits(slot, offset, text):
        lines = buffer_pens(cpc, slot)
        for i, d in enumerate(text):
            assert _cells(lines, offset + 2 * i, 2) == glyph[f"d{d}"], f"digit {i} of {text}"

    digits(score, 0, "123456")
    assert _cells(buffer_pens(cpc, coins), 0, 4) == glyph["ic_coin"]
    digits(coins, 4, "0042")
    assert _cells(buffer_pens(cpc, lives), 0, 4) == glyph["ic_life"]
    digits(lives, 4, "2")
    assert not more_cells["drawn"], "one power-up: one row of cells"
    lines = buffer_pens(cpc, cells)
    assert _cells(lines[:8], 0, 4) == glyph["ic_magnet"]
    bar = lines[8][:8]                                           # 122/250 of 8 pixels -> 4
    assert bar == [7] * 4 + [PANEL_PEN] * 4 and lines[9][:8] == bar, bar
    assert all(p == PANEL_PEN for row in lines for p in row[8:]), "other cells empty"
    cpc.write_ram(sym["coins"], bytes([0x43, 0x00]))            # one digit changes
    for _ in range(2):
        sync_game_frame(cpc, sym)
    digits(coins, 4, "0043")


def test_power_up_row_disappears_when_it_ends():
    sym = load_symbols()
    cpc = boot_game()
    palette = _palette()
    cpc.write_ram(sym["pu_spring"], (30).to_bytes(2, "little"))
    cpc.write_ram(sym["pu_ticket"], (200).to_bytes(2, "little"))
    seen = False
    sync_game_frame(cpc, sym)
    for _ in range(40):
        img, buffers = game_frame(cpc, sym)
        spring = slots(cpc, sym)[3]
        seen |= bool(spring["drawn"])
        assert not check_panel(img, expected_panel(cpc, sym, buffers), palette)
    assert seen and slots(cpc, sym)[3]["drawn"], "the ticket stays"
    assert peek16(cpc, sym["pu_spring"]) == 0
    lines = buffer_pens(cpc, slots(cpc, sym)[3])
    assert _cells(lines[:8], 0, 4) == _glyphs()["ic_ticket"], "the ticket moved to the first cell"
