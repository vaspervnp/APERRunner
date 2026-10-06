"""The avenue's traffic (src/world.asm, move_cars): some parked cars drive
off, up the right side, down the left (drawn turned round). They move in
frames without a coarse step, two lines at a time, one car a frame, and
stop before a forest, a bridge, a kiosk or rows not drawn yet."""

import os
import sys

from harness import ROOT, boot_game, load_symbols, sync_game_frame
from world_model import F_BRIDGE, F_OVERLAY, Sheets, read_desc, screen_row, visible_rows

sys.path.insert(0, os.path.join(ROOT, "tools"))
import png2cpc  # noqa: E402

MOVERS, MV_SIZE, CAR_LINES = 2, 8, 16
RUNNER_ROWS = 27                     # picture rows from here on: the runner's


def _movers(cpc, sym):
    out = []
    for i in range(MOVERS):
        m = cpc.read_ram(sym["movers"] + i * MV_SIZE, MV_SIZE)
        out.append({"on": m[0], "col": m[1], "lo": m[2] | m[3] << 8, "spr": m[4] | m[5] << 8,
                    "dir": 1 if m[6] == 1 else -1, "lane": m[7]})
    return out


def _boot(speed):
    sym = load_symbols()
    cpc = boot_game()
    cpc.write_ram(sym["scroll_speed"], bytes([speed]))
    return sym, cpc


def test_cars_drive_both_ways_two_lines_one_car_a_frame():
    sym, cpc = _boot(4)
    prev = _movers(cpc, sym)
    travel = {1: 0, -1: 0}
    for _ in range(3000):
        sync_game_frame(cpc, sym)
        now = _movers(cpc, sym)
        moved = 0
        for a, b in zip(prev, now):
            if a["on"] == 2 and b["on"] == 2 and a["spr"] == b["spr"] and a["col"] == b["col"]:
                step = b["lo"] - a["lo"]
                assert step in (0, b["dir"], 2 * b["dir"]), (a, b)
                travel[b["dir"]] += abs(step)
                moved += step != 0
        assert moved <= 1, ("one car a frame", prev, now)
        prev = now
    print(f"    {travel[1]} lines driven up, {travel[-1]} down")
    assert travel[1] > 200 and travel[-1] > 200, travel


def test_moving_car_is_drawn_where_it_is_and_leaves_no_trail():
    """With the scroll stopped: the car's 16 lines show its sprite (turned
    round going down), the road around it shows the side tile."""
    sheets = Sheets()
    bank5 = open(os.path.join(ROOT, "build", "aperb5.bin"), "rb").read()
    sym, cpc = _boot(4)
    road = car = 0
    start = {}                               # where each mover started: until it
    for frame in range(2500):                # moves, the parked car shows
        sync_game_frame(cpc, sym)
        for i, m in enumerate(_movers(cpc, sym)):
            if m["on"] != 2:
                start.pop(i, None)
            else:
                start.setdefault(i, m["lo"])
        if frame % 37 or not any(m["on"] == 2 for m in _movers(cpc, sym)):
            continue
        cpc.write_ram(sym["scroll_speed"], bytes([0]))
        sync_game_frame(cpc, sym)
        sync_game_frame(cpc, sym)
        cpc.run_us(15000)                    # the frame done (move_cars comes last)
        for i, m in enumerate(_movers(cpc, sym)):
            if m["on"] != 2 or start.get(i, m["lo"]) == m["lo"]:
                continue
            right = m["lane"] >= 3
            offset = (m["col"] - (57 if right else 0)) * 2
            for index, (row, bank, ring) in enumerate(visible_rows(cpc, sym)):
                desc = read_desc(cpc, sym, row)
                if index >= RUNNER_ROWS or desc["flags"] & (F_BRIDGE | 0x01):
                    continue
                got = screen_row(cpc, bank, ring, m["col"], 4)
                tile = sheets.sides["urban"][desc["right" if right else "left"]]
                for y in range(8):
                    w = row * 8 + 7 - y
                    if m["lo"] <= w < m["lo"] + CAR_LINES:
                        line = w - m["lo"] if m["dir"] == -1 else CAR_LINES - 1 - (w - m["lo"])
                        data = [bank5[m["spr"] - 0x4000 + 2 + (line * 4 + b) * 2 + 1] for b in range(4)]
                        want = [p for v in data for p in png2cpc.decode_byte(v)]
                        assert got[y] == want, (frame, row, y, m, got[y], want)
                        car += 1
                    elif not desc["flags"] & F_OVERLAY:
                        assert got[y] == tile[y][offset:offset + 8], ("a trail", frame, row, y, m)
                        road += 1
        cpc.write_ram(sym["scroll_speed"], bytes([4]))
    print(f"    {car} car lines and {road} road lines compared")
    assert car >= 100 and road >= 1000, (car, road)
