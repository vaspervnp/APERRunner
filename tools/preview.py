"""Builds a preview PNG of tile columns as they appear on the track
(top of the list = top of the screen), scaled with the 2:1 mode 0 aspect.

  python3 tools/preview.py out.png "rail_a,ramp_down_2,..." "..." ...
"""

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png2cpc  # noqa: E402
from cpcpalette import editor_rgb  # noqa: E402


def column_image(sheet, frames, names):
    rows = []
    for name in names:
        rows += frames[name]
    w = len(rows[0])
    img = Image.new("RGB", (w, len(rows)), (255, 0, 255))
    for y, row in enumerate(rows):
        for x, pen in enumerate(row):
            if pen is not None:
                img.putpixel((x, y), editor_rgb(pen))
    return img


def main(out, sheet, columns, scale=4):
    frames = png2cpc.load_sheet(sheet)
    images = [column_image(sheet, frames, c.split(",")) for c in columns]
    gap = 4
    width = sum(i.width + gap for i in images)
    height = max(i.height for i in images)
    sheet_img = Image.new("RGB", (width, height), (40, 40, 40))
    x = 0
    for i in images:
        sheet_img.paste(i, (x, height - i.height))
        x += i.width + gap
    sheet_img.resize((width * scale * 2, height * scale), Image.NEAREST).save(out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
