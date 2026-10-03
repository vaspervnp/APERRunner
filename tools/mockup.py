"""Composes a typical in-game screen (192x272 mode 0 pixels) from the
converted sheets, as a readability check of the art:

  python3 tools/mockup.py out.png

Urban rows at the bottom, a road bridge, a train with ramps in the middle
lane, a buffer stop and a signal, coins, a power-up, trees in the forest
part, the runner (size 1) at the bottom, HUD on the right.
"""

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png2cpc  # noqa: E402
from cpcpalette import editor_rgb  # noqa: E402

LANE_X = (30, 58, 86)
RIGHT_X = 114
HUD_X = 144


def main(out):
    s = {name: png2cpc.load_sheet(name) for name in
         ("track", "urban", "urban_ov", "forest", "forest_ov", "bridges", "player",
          "shadows", "items", "hud")}
    screen = [[0] * 192 for _ in range(272)]

    def put(frame, x0, y0, mirror=False):
        rows = png2cpc.mirror(frame) if mirror else frame
        for dy, row in enumerate(rows):
            for dx, pen in enumerate(row):
                if pen is not None and 0 <= y0 + dy < 272 and 0 <= x0 + dx < 192:
                    screen[y0 + dy][x0 + dx] = pen

    # 34 rows, listed top to bottom: (side tile, env, lane tiles)
    rows = []
    for i in range(8):
        rows.append(("ground_a" if i % 2 else "ground_b", "forest", ["rail_a", "rail_b", "rail_a"]))
    rows[2] = ("path", "forest", rows[2][2])
    rows += [("trans_urban_forest_1", "forest", ["rail_a", "rail_a", "rail_b"]),
             ("trans_urban_forest_0", "forest", ["rail_b", "rail_a", "rail_a"])]
    train = ["ramp_down_2", "ramp_down_1", "ramp_down_0", "wagon1_end_top", "wagon1_body_a",
             "wagon1_body_b", "wagon1_end_bottom", "wagon1_coupler", "loco1_body",
             "loco1_pantograph", "loco1_nose"]
    for i in range(24):
        side = ("road_cross_1", "road_cross_0")[i - 18] if i in (18, 19) else ("road_a" if i % 2 else "road_b")
        lanes = ["rail_a" if i % 2 else "rail_b"] * 3
        if i < len(train):
            lanes[1] = train[i]
        if i in (14, 15):
            lanes[0] = ("stop_1", "stop_0")[i - 14]
        if i == 19:
            lanes[2] = "signal_0"
        if i == 20:
            lanes[2] = "signal_1"
        rows.append((side, "urban", lanes))
    for r, (side, env, lanes) in enumerate(rows):
        y = r * 8
        put(s[env][side], 0, y)
        put(s[env][side], RIGHT_X, y, mirror=True)
        for lane, name in zip(LANE_X, lanes):
            put(s["track"][name], lane, y)
        put(s["hud"]["hud_bg"], HUD_X, y)

    bridge = ["roadbridge_5", "roadbridge_4", "roadbridge_3", "roadbridge_2", "roadbridge_1",
              "roadbridge_0", "roadbridge_shadow"]
    for i, name in enumerate(bridge):
        put(s["bridges"][name], 0, (1 + i) * 8)

    # scenery and objects
    put(s["forest_ov"]["oak"], 2, 4)
    put(s["forest_ov"]["pine"], RIGHT_X + 10, 20, mirror=True)
    put(s["forest_ov"]["cypress"], 14, 40)
    put(s["forest_ov"]["bush"], RIGHT_X + 16, 54)
    put(s["urban_ov"]["bus"], 10, 152)
    put(s["urban_ov"]["taxi"], RIGHT_X + 12, 172, mirror=True)
    put(s["urban_ov"]["car_red"], 1, 200)
    put(s["urban_ov"]["car_blue"], RIGHT_X + 21, 230, mirror=True)
    for y in range(24, 64, 12):
        put(s["items"]["coin0"], LANE_X[0] + 10, y)
    for y, frame in zip(range(170, 230, 12), ("coin0", "coin1", "coin2", "coin3", "coin0")):
        put(s["items"][frame], LANE_X[2] + 10, y)
    put(s["items"]["pu_magnet"], LANE_X[0] + 8, 112)
    put(s["items"]["coin0"], LANE_X[1] + 10, 50)          # coin on the train roof

    # runner in lane 1, shadow under a jumper in lane 2
    put(s["player"]["s1_run0"], LANE_X[1] + 9, 244)
    put(s["shadows"]["sh2"], LANE_X[0] + 9, 258)
    put(s["player"]["s2_jump_up"], LANE_X[0] + 8, 236)

    # HUD items
    for i, name in enumerate(("ic_coin", "ic_magnet", "ic_turbo", "ic_life", "ic_life", "ic_life")):
        put(s["hud"][name], HUD_X + 10 + (i % 3) * 10, 20 + (i // 3) * 140)
    for i in range(12):
        put(s["hud"]["bar_full" if i < 8 else "bar_empty"], HUD_X + 10 + i * 2, 40)

    image = Image.new("RGB", (192, 272))
    for y, row in enumerate(screen):
        for x, pen in enumerate(row):
            image.putpixel((x, y), editor_rgb(pen))
    image.resize((192 * 4, 272 * 2), Image.NEAREST).save(out)


if __name__ == "__main__":
    main(sys.argv[1])
