"""Blender render -> CPC loading screen (prompts/blender_loading_screen.md).

Input:  assets/loading/loading_4x.png (tools/blender/loading_scene.py:
        1536x672 RGBA, transparent sky)
Output: assets/loading/loading_384x168.png  box-filtered, square pixels
        assets/loading/loading_cpc.png      192x168 mode 0 pixels, indexed with
                                            the 16 loading inks
        assets/loading/loading_palette.txt  the inks (tools/mkloading.py)

The sky (transparent in the render) gets the sunset bands with an ordered
Bayer 4x4 dither, the sun and the Acropolis silhouette; the scene is mapped to the nearest ink
without dither (clean silhouettes); the logo goes on top as in the
placeholder. tools/scr2cpc.py turns loading_cpc.png into screen memory.
"""

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkloading  # noqa: E402
from cpcpalette import ROOT  # noqa: E402

SRC = os.path.join(ROOT, "assets", "loading", "loading_4x.png")
SQUARE = os.path.join(ROOT, "assets", "loading", "loading_384x168.png")
W, H = mkloading.W, mkloading.H
BLUE, MAUVE, MAGENTA, PINK, ORANGE, YELLOW, PYELLOW = (
    mkloading.BLUE, mkloading.MAUVE, mkloading.MAGENTA, mkloading.PINK,
    mkloading.ORANGE, mkloading.YELLOW, mkloading.PYELLOW)
SKY_BANDS = [BLUE, MAUVE, MAGENTA, PINK, ORANGE, YELLOW]
INKS = {ink: mkloading.rgb(ink) for ink in range(16)}


def nearest(rgb):
    return min(INKS, key=lambda i: sum((c - d) ** 2 for c, d in zip(INKS[i], rgb)))


def acropolis(px, horizon, cx=44):
    """The hill and the Parthenon in silhouette behind the scene, left of
    the tracks (mode 0 pixels are twice as wide as tall)."""
    RED, BLACK = mkloading.RED, mkloading.BLACK
    for x in range(cx - 44, cx + 45):
        top = horizon - 11 + int(((x - cx) / 44) ** 2 * 11)
        for y in range(max(0, top), horizon):
            px[y][x] = RED if y < top + 2 else BLACK
    base = horizon - 10
    for y in range(base - 11, base):                            # columns, entablature
        for x in range(cx - 15, cx + 16):
            if y < base - 8 or y >= base - 2 or (x - cx + 15) % 4 < 2:
                px[y][x] = BLACK
    for k in range(4):                                          # pediment
        for x in range(cx - 15 + k * 4, cx + 16 - k * 4):
            px[base - 12 - k][x] = BLACK


def convert(src=SRC):
    render = Image.open(src).convert("RGBA")
    if render.size != (W * 8, H * 4):
        raise SystemExit(f"quantize_loading: {src}: expected {W * 8}x{H * 4}")
    square = render.reduce(4)                                   # box filter -> 384x168
    square.save(SQUARE)
    mode0 = square.reduce((2, 1))                               # 2 square pixels -> 1 mode 0 pixel
    sky = [[mode0.getpixel((x, y))[3] < 128 for x in range(W)] for y in range(H)]
    horizon = max(y for y in range(H) if any(sky[y][W // 3:2 * W // 3])) + 1

    px = [[0] * W for _ in range(H)]
    for y in range(H):                                          # the sky, dithered bands
        t = min(y / horizon, 0.999) * (len(SKY_BANDS) - 1)
        i, frac = int(t), t - int(t)
        for x in range(W):
            hi = SKY_BANDS[min(i + 1, len(SKY_BANDS) - 1)]
            px[y][x] = hi if frac * 16 > mkloading.BAYER[y % 4][x % 4] else SKY_BANDS[i]
    for y in range(max(0, horizon - 34), horizon):              # the sun behind the hill
        for x in range(W):
            if ((x - W // 2) * 2) ** 2 + (y - horizon + 6) ** 2 < 30 ** 2:
                px[y][x] = PYELLOW
    acropolis(px, horizon)
    for y in range(H):                                          # the scene, no dither
        for x in range(W):
            if not sky[y][x]:
                px[y][x] = nearest(mode0.getpixel((x, y))[:3])
    logo = Image.open(os.path.join(ROOT, "gfx", "png", "logo.png")).convert("RGBA")
    for y in range(logo.height):                                # the logo
        for x in range(logo.width):
            r, g, b, a = logo.getpixel((x, y))
            if a and (r, g, b) != (0, 0, 0):
                px[6 + y][24 + x] = nearest((r, g, b))
    mkloading.save(px)
    return horizon


if __name__ == "__main__":
    horizon = convert()
    print(f"loading    Blender render, horizon at line {horizon} -> "
          f"{os.path.relpath(mkloading.OUT, ROOT)}")
