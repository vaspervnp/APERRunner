"""Painted loading screen art -> CPC loading screen.

Input:  assets/loading/loading_art.jpg (any size; the scene the game's
        logo goes on, with empty sky at the top)
Output: assets/loading/loading_cpc.png      192x168 mode 0 pixels, indexed with
                                            the 16 loading inks
        assets/loading/loading_palette.txt  the inks (tools/mkloading.py)

The art's own lettering is painted over with the sky, the art is cropped
(CROP) and scaled to 192x168 (mode 0 pixels are twice as wide as tall, so the
picture is squashed vertically less than it looks), its colours are made
stronger (SATURATION) and each pixel is a mix of two inks picked through an
ordered Bayer 4x4 dither (the dither of 8-bit loading screens); the game's
logo goes on top. tools/scr2cpc.py turns loading_cpc.png into screen memory.
"""

import os
import sys

from PIL import Image, ImageEnhance

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkloading  # noqa: E402
from cpcpalette import ROOT  # noqa: E402

SRC = os.path.join(ROOT, "assets", "loading", "loading_art.jpg")
W, H = mkloading.W, mkloading.H
CROP = (0.0, 0.03, 1.0, 0.97)           # left, top, right, bottom (fractions)
SATURATION = 1.8
LOGO_AT = (24, 4)
ART_LETTERING = (0.30, 0.02, 0.70, 0.19)  # the art's own title: painted over with the sky
SKY_SAMPLE_X = 0.15                       # a column of clear sky beside it
LEVELS = 8                               # mixes of two inks: 0/8 .. 8/8
INKS = [mkloading.rgb(ink) for ink in range(16)]


def error(c, d):
    """Weighted RGB distance (eye: G > B > R) plus the difference in hue
    (blue-ish sky must not become grey)."""
    hue = ((c[2] - c[0]) - (d[2] - d[0])) ** 2 + ((c[1] - c[0]) - (d[1] - d[0])) ** 2
    return 2 * (c[0] - d[0]) ** 2 + 4 * (c[1] - d[1]) ** 2 + 3 * (c[2] - d[2]) ** 2 + 2 * hue


# mixing two far-apart inks looks noisy: a penalty, small in the sky (smooth
# dithered bands) and larger in the scene (clean shapes)
SKY_LINES, SKY_NOISE, SCENE_NOISE = 64, 0.05, 0.15
MIXES = []
for a in range(16):
    for b in range(a, 16):
        for r in range(LEVELS + 1 if a != b else 1):
            t = r / LEVELS
            mix = [INKS[a][i] * (1 - t) + INKS[b][i] * t for i in range(3)]
            noise = 0 if r in (0, LEVELS) else error(INKS[a], INKS[b])
            MIXES.append((mix, noise, a, b, r))
_cache = {}


def mix_for(c, noise):
    """Two inks and how much of the second (r / LEVELS) for colour c."""
    key = (c[0] >> 3, c[1] >> 3, c[2] >> 3, noise)
    if key not in _cache:
        _cache[key] = min(MIXES, key=lambda m: error(c, m[0]) + noise * m[1])[2:]
    return _cache[key]


def convert(src=SRC):
    art = Image.open(src).convert("RGB")
    w, h = art.size
    x0, y0, x1, y1 = (round(f * n) for f, n in zip(ART_LETTERING, (w, h, w, h)))
    for y in range(y0, y1):
        art.paste(art.getpixel((round(SKY_SAMPLE_X * w), y)), (x0, y, x1, y + 1))
    box = (round(CROP[0] * w), round(CROP[1] * h), round(CROP[2] * w), round(CROP[3] * h))
    art = art.crop(box).resize((W, H), Image.LANCZOS)
    art = ImageEnhance.Color(art).enhance(SATURATION)
    px = [[0] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            a, b, r = mix_for(art.getpixel((x, y)), SKY_NOISE if y < SKY_LINES else SCENE_NOISE)
            px[y][x] = b if r * 16 > mkloading.BAYER[y % 4][x % 4] * LEVELS else a
    logo = Image.open(os.path.join(ROOT, "gfx", "png", "logo.png")).convert("RGBA")
    nearest = {}
    for y in range(logo.height):
        for x in range(logo.width):
            rgba = logo.getpixel((x, y))
            if rgba[3] and rgba[:3] != (0, 0, 0):
                if rgba[:3] not in nearest:
                    nearest[rgba[:3]] = min(range(16), key=lambda i: error(INKS[i], rgba[:3]))
                px[LOGO_AT[1] + y][LOGO_AT[0] + x] = nearest[rgba[:3]]
    mkloading.save(px)


if __name__ == "__main__":
    convert()
    print(f"loading    {os.path.relpath(SRC, ROOT)} -> {os.path.relpath(mkloading.OUT, ROOT)}")
