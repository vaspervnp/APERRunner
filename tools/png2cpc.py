"""Converts sheets (PNG + Aseprite JSON) into mode 0 data for rasm.

  python3 tools/png2cpc.py            # every asset in tools/assets.py
  python3 tools/png2cpc.py track hud_bg

Images must use only the game palette (tools/cpcpalette.py) with no
anti-aliasing; transparent pixels (alpha < 128) are allowed in sprites only.
Sheets come from gfx/png/<sheet>.{png,json}, or gfx/placeholder/ when the
real art does not exist yet.
"""

import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import assets  # noqa: E402
from cpcpalette import ROOT, editor_rgb_to_pen  # noqa: E402

GFX_DIRS = [os.path.join(ROOT, "gfx", "png"), os.path.join(ROOT, "gfx", "placeholder")]
OUT_DIR = os.path.join(ROOT, "src", "data")

# mode 0 bit positions of pen bits 0-3 for the left and right pixel of a byte
PIXEL_BITS = ((7, 3, 5, 1), (6, 2, 4, 0))
PIXEL_MASK = (0xAA, 0x55)


class GfxError(Exception):
    pass


def encode_pixel(pen, position):
    byte = 0
    for bit_index, bit in enumerate(PIXEL_BITS[position]):
        if pen >> bit_index & 1:
            byte |= 1 << bit
    return byte


def decode_byte(byte):
    """Inverse of encode: byte -> (left pen, right pen)."""
    return tuple(sum(((byte >> bit) & 1) << i for i, bit in enumerate(PIXEL_BITS[pos]))
                 for pos in (0, 1))


def find_sheet(sheet):
    for directory in GFX_DIRS:
        png = os.path.join(directory, sheet + ".png")
        if os.path.exists(png):
            return png, os.path.join(directory, sheet + ".json")
    raise GfxError(f"sheet '{sheet}' not found in gfx/png or gfx/placeholder")


def _frame_rects(sheet, json_path, image):
    """Frame name -> (x, y, w, h), checked against the manifest."""
    spec = assets.SHEETS[sheet]
    if os.path.exists(json_path):
        with open(json_path) as f:
            data = json.load(f)
        frames = data["frames"]
        if isinstance(frames, dict):                 # Aseprite "hash" export
            frames = [dict(v, filename=k) for k, v in frames.items()]
        rects = [(fr["frame"]["x"], fr["frame"]["y"], fr["frame"]["w"], fr["frame"]["h"]) for fr in frames]
        names = [os.path.splitext(fr.get("filename", ""))[0] for fr in frames]
        if set(names) != {n for n, _, _ in spec}:
            # Aseprite names frames "<title> <n>": fall back to manifest order
            if len(rects) != len(spec):
                raise GfxError(f"{sheet}: {len(rects)} frames in JSON, manifest expects {len(spec)}")
            names = [n for n, _, _ in spec]
        by_name = dict(zip(names, rects))
    else:                                            # horizontal strip, manifest order
        by_name, x = {}, 0
        for name, w, h in spec:
            by_name[name] = (x, 0, w, h)
            x += w
    for name, w, h in spec:
        if name not in by_name:
            raise GfxError(f"{sheet}: frame '{name}' missing")
        x, y, fw, fh = by_name[name]
        if (fw, fh) != (w, h):
            # one Aseprite canvas per sheet: smaller frames sit at the top-left
            # of a larger cel and the rest must be transparent
            if fw < w or fh < h:
                raise GfxError(f"{sheet}/{name}: size {fw}x{fh}, expected {w}x{h}")
            for py in range(y, y + fh):
                for px in range(x, x + fw):
                    if (px >= x + w or py >= y + h) and image.getpixel((px, py))[3] >= 128:
                        raise GfxError(f"{sheet}/{name}: pixel ({px},{py}) outside the {w}x{h} frame is not transparent")
            by_name[name] = (x, y, w, h)
        if w % 2:
            raise GfxError(f"{sheet}/{name}: width {w} is odd (mode 0 needs whole bytes)")
    x1 = max(x + w for x, _, w, _ in by_name.values())
    y1 = max(y + h for _, y, _, h in by_name.values())
    if x1 > image.width or y1 > image.height:
        raise GfxError(f"{sheet}: frames exceed the {image.width}x{image.height} image")
    return by_name


def load_sheet(sheet):
    """Frame name -> rows of pens (None = transparent)."""
    png, json_path = find_sheet(sheet)
    image = Image.open(png).convert("RGBA")
    rects = _frame_rects(sheet, json_path, image)
    to_pen = editor_rgb_to_pen()
    frames = {}
    for name, (x0, y0, w, h) in rects.items():
        rows = []
        for y in range(y0, y0 + h):
            row = []
            for x in range(x0, x0 + w):
                r, g, b, a = image.getpixel((x, y))
                if a < 128:
                    row.append(None)
                elif (r, g, b) in to_pen:
                    row.append(to_pen[(r, g, b)])
                else:
                    raise GfxError(f"{os.path.relpath(png, ROOT)}: colour #{r:02X}{g:02X}{b:02X} at "
                                   f"({x},{y}) in frame '{name}' is not in the game palette")
            rows.append(row)
        frames[name] = rows
    return frames


def mirror(rows):
    return [list(reversed(row)) for row in rows]


def tile_bytes(name, rows):
    out = []
    for y, row in enumerate(rows):
        if None in row:
            raise GfxError(f"tile '{name}' has transparent pixels (line {y})")
        out += [encode_pixel(row[x], 0) | encode_pixel(row[x + 1], 1) for x in range(0, len(row), 2)]
    return out


def sprite_bytes(rows):
    out = [len(rows[0]) // 2, len(rows)]
    for row in rows:
        for x in range(0, len(row), 2):
            mask = data = 0
            for position, pen in enumerate(row[x:x + 2]):
                if pen is None:
                    mask |= PIXEL_MASK[position]
                else:
                    data |= encode_pixel(pen, position)
            out += [mask, data]
    return out


def convert(asset):
    sheet, kind, wanted, do_mirror = assets.ASSETS[asset]
    frames = load_sheet(sheet)
    order = wanted or [n for n, _, _ in assets.SHEETS[sheet]]
    entries = []
    for name in order:
        entries.append((name, frames[name]))
        if do_mirror:
            entries.append((name + "_m", mirror(frames[name])))
    if kind in ("panel", "tile0"):
        pen = assets.PANEL_PEN if kind == "panel" else 0
        entries = [(name, [[pen if p is None else p for p in row] for row in rows])
                   for name, rows in entries]
    encoded = [(name, tile_bytes(name, rows) if kind in ("tile", "panel", "tile0") else sprite_bytes(rows), rows)
               for name, rows in entries]
    return kind, encoded


def compiled_source(asset, encoded, bank_split=None):
    """Masked sprites as straight-line code. Each routine draws one frame:
    HL = address of its first line, DE = save buffer position after that
    line's address (restore_sprite format). Per line: the background is saved
    with one LDI per byte, HL goes back to the line start (fc_line), then each
    byte is drawn:
      transparent  (skipped)
      opaque       ld (hl),n
      mixed        ld a,(hl) / and m / or d / ld (hl),a
    with inc hl between bytes. Between lines "call compiled_next_line" sets HL
    to the next line and writes its address into the save buffer.
    bank_split: (frame count in the first bank) -> frames after it go to the
    second bank (label prefix ..._b2), see the generated _BANK table."""
    prefix = f"gfx_{asset}"
    lines = [f"; generated by tools/png2cpc.py from tools/assets.py - do not edit",
             f"; {asset}: {len(encoded)} compiled sprites"]
    for index, (name, _, _) in enumerate(encoded):
        lines.append(f"IDX_{asset.upper()}_{name.upper()} equ {index}")
    lines += ["", f"{prefix}_table:"]
    lines += [f"                defw {prefix}_{name}" for name, _, _ in encoded]
    for name, data, _ in encoded:
        width, height = data[0], data[1]
        pairs = data[2:]
        lines.append(f"{prefix}_{name}:")
        for y in range(height):
            if y:
                lines.append("                call compiled_next_line")
            row = [(pairs[2 * (y * width + x)], pairs[2 * (y * width + x) + 1]) for x in range(width)]
            drawn = [x for x, (mask, _) in enumerate(row) if mask != 0xFF]
            lines += ["                ldi"] * width
            if not drawn:
                continue
            lines.append("                ld hl,(fc_line)")
            at = 0
            for x in drawn:
                lines += ["                inc hl"] * (x - at)
                at = x
                mask, value = row[x]
                if mask == 0:
                    lines.append(f"                ld (hl),#{value:02X}")
                else:
                    lines += ["                ld a,(hl)", f"                and #{mask:02X}",
                              f"                or #{value:02X}", "                ld (hl),a"]
        lines.append("                ret")
    return "\n".join(lines) + "\n"


def asm_source(asset, kind, encoded):
    prefix = f"gfx_{asset}"
    upper = prefix.upper()
    lines = [f"; generated by tools/png2cpc.py from tools/assets.py - do not edit",
             f"; {asset}: {len(encoded)} {kind}s"]
    widths = {len(rows[0]) for _, _, rows in encoded}
    heights = {len(rows) for _, _, rows in encoded}
    if len(widths) == 1:
        lines.append(f"{upper}_WIDTH equ {widths.pop() // 2}            ; bytes")
    if len(heights) == 1:
        lines.append(f"{upper}_HEIGHT equ {heights.pop()}")
    lines.append(f"{upper}_COUNT equ {len(encoded)}")
    # rasm labels are case-insensitive: indices get their own prefix
    for index, (name, _, _) in enumerate(encoded):
        lines.append(f"IDX_{asset.upper()}_{name.upper()} equ {index}")
    lines += ["", f"{prefix}_table:"]
    lines += [f"                defw {prefix}_{name}" for name, _, _ in encoded]
    for name, data, _ in encoded:
        lines.append(f"{prefix}_{name}:")
        for i in range(0, len(data), 16):
            lines.append("                defb " + ",".join(f"#{b:02X}" for b in data[i:i + 16]))
    return "\n".join(lines) + "\n"


def main(names):
    names = names or list(assets.ASSETS)
    os.makedirs(OUT_DIR, exist_ok=True)
    try:
        for asset in names:
            kind, encoded = convert(asset)
            path = os.path.join(OUT_DIR, f"gfx_{asset}.asm")
            with open(path, "w") as f:
                f.write(compiled_source(asset, encoded) if kind == "compiled"
                        else asm_source(asset, kind, encoded))
            size = sum(len(d) for _, d, _ in encoded)
            print(f"{asset:10s} {len(encoded):3d} {kind}s {size:6d} bytes -> {os.path.relpath(path, ROOT)}")
    except GfxError as e:
        print(f"png2cpc: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
