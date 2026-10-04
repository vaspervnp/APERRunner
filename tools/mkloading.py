"""Placeholder loading screen (until the Blender render of
prompts/blender_loading_screen.md exists): sunset over the Acropolis, three
tracks in perspective, pines, the logo. Writes assets/loading/loading_cpc.png
(192x168 mode 0 pixels, indices = LOADING_PALETTE) - the same file the
Blender pipeline produces, so tools/scr2cpc.py takes either.
"""

import math
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cpcpalette  # noqa: E402
from cpcpalette import ROOT  # noqa: E402

W, H = 192, 168
OUT = os.path.join(ROOT, "assets", "loading", "loading_cpc.png")

# ink -> firmware colour
LOADING_PALETTE = [0, 1, 2, 5, 4, 3, 6, 15, 16, 24, 25, 9, 18, 13, 26, 12]
BLACK, BLUE, BBLUE, MAUVE, MAGENTA, RED, BRED, ORANGE, PINK, YELLOW, PYELLOW, GREEN, BGREEN, GREY, WHITE, OLIVE = range(16)
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
HORIZON = 100


def rgb(ink):
    return cpcpalette.rgb_tuple(cpcpalette.CPC_COLOURS[LOADING_PALETTE[ink]][1])


def draw():
    px = [[BLACK] * W for _ in range(H)]

    def put(x, y, ink):
        if 0 <= x < W and 0 <= y < H:
            px[y][x] = ink

    # sky: bands with ordered dither between neighbours
    bands = [BLUE, MAUVE, MAGENTA, PINK, ORANGE, YELLOW]
    for y in range(HORIZON):
        t = y / HORIZON * (len(bands) - 1)
        i, frac = int(t), t - int(t)
        for x in range(W):
            hi = bands[min(i + 1, len(bands) - 1)]
            put(x, y, hi if frac * 16 > BAYER[y % 4][x % 4] else bands[i])
    # sun (pixels are twice as wide as tall)
    for y in range(HORIZON - 30, HORIZON):
        for x in range(W):
            if ((x - 96) * 2) ** 2 + (y - HORIZON + 4) ** 2 < 26 ** 2:
                put(x, y, PYELLOW)
    # hill + Parthenon in silhouette
    for x in range(40, 152):
        top = HORIZON - 12 + int(((x - 96) / 56) ** 2 * 12)
        for y in range(top, HORIZON):
            put(x, y, RED if y < top + 2 else BLACK)
    for y in range(HORIZON - 24, HORIZON - 12):
        for x in range(76, 117):
            if y < HORIZON - 21 or y >= HORIZON - 14 or (x - 76) % 4 < 2:
                put(x, y, BLACK)
    for y in range(HORIZON - 30, HORIZON - 24):
        half = (y - (HORIZON - 30)) * 4
        for x in range(96 - half, 96 + half + 1):
            put(x, y, BLACK)
    # ground: dark, city blocks left, pines right
    for y in range(HORIZON, H):
        for x in range(W):
            put(x, y, BLUE if (x + y) % 2 else BLACK)
    for i, (x0, w, h) in enumerate([(0, 14, 18), (14, 10, 26), (24, 16, 14), (40, 12, 22), (52, 8, 12)]):
        for y in range(HORIZON - h, HORIZON + 6):
            for x in range(x0, x0 + w):
                lit = (x - x0) % 4 == 1 and (y - HORIZON + h) % 5 == 2
                put(x, y, YELLOW if lit else BLACK)
    for x0 in range(140, 192, 9):
        h = 14 + (x0 * 7) % 10
        for y in range(HORIZON - h, HORIZON + 6):
            half = (y - HORIZON + h) // 3
            for x in range(x0 - half, x0 + half + 1):
                put(x, y, GREEN if x < x0 else BLACK)
    # three tracks converging at the sun
    vx, vy = 96, HORIZON + 2

    def lerp_x(xb, y):
        return int(round(vx + (xb - vx) * (y - vy) / (H - 1 - vy)))

    for centre in (24, 96, 168):
        for y in range(vy + 1, H):
            l, r = lerp_x(centre - 26, y), lerp_x(centre + 26, y)
            for x in range(l, r + 1):
                put(x, y, RED if (x + y) % 3 else BLACK)          # ballast
        depth = 1.0
        while True:                                                # sleepers
            y = int(vy + (H - vy) / depth)
            if y <= vy + 2:
                break
            for x in range(lerp_x(centre - 22, y), lerp_x(centre + 22, y) + 1):
                put(x, y, ORANGE)
            depth += 0.6
        for side in (-14, 14):                                     # rails
            for y in range(vy + 1, H):
                x = lerp_x(centre + side, y)
                put(x, y, WHITE)
                put(x + 1, y, GREY)
    # train on the middle track and coins in an arc
    for y in range(128, H):
        l, r = lerp_x(96 - 18, y), lerp_x(96 + 18, y)
        for x in range(l, r + 1):
            put(x, y, GREEN if (y - 128) % 12 else BGREEN)
        put(l, y, BLACK)
        put(r, y, BLACK)
    for y in range(131, 137):
        for x in range(lerp_x(96 - 12, y), lerp_x(96 + 12, y) + 1):
            put(x, y, OLIVE)
    for k in range(5):
        cx, cy = 78 + k * 9, 118 - int(10 * math.sin(math.pi * k / 4))
        for y in range(cy - 3, cy + 4):
            for x in range(cx - 1, cx + 2):
                put(x, y, YELLOW if (x, y) != (cx - 1, cy - 2) else WHITE)
    # logo (game palette -> nearest loading ink)
    logo = Image.open(os.path.join(ROOT, "gfx", "png", "logo.png")).convert("RGBA")
    inks = {ink: rgb(ink) for ink in range(16)}
    for y in range(logo.height):
        for x in range(logo.width):
            r, g, b, a = logo.getpixel((x, y))
            if a == 0 or (r, g, b) == (0, 0, 0):
                continue
            ink = min(inks, key=lambda i: sum((c - d) ** 2 for c, d in zip(inks[i], (r, g, b))))
            put(24 + x, 6 + y, ink)
    return px


def save(px, path=OUT):
    img = Image.new("P", (W, H))
    flat = []
    for ink in range(16):
        flat += rgb(ink)
    img.putpalette(flat + [0] * (768 - len(flat)))
    img.putdata([v for row in px for v in row])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    with open(os.path.join(os.path.dirname(path), "loading_palette.txt"), "w") as f:
        for ink, fw in enumerate(LOADING_PALETTE):
            name, value, _ = cpcpalette.CPC_COLOURS[fw]
            f.write(f"{ink:2d} fw {fw:2d} #{value:06X} {name}\n")


if __name__ == "__main__":
    save(draw())
    print(f"loading    placeholder -> {os.path.relpath(OUT, ROOT)}")
