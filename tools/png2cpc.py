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
    if kind == "header":                       # drawn by compiled code: the size only
        encoded = [(name, [len(rows[0]) // 2, len(rows)], rows) for name, rows in entries]
    else:
        encoded = [(name, tile_bytes(name, rows) if kind in ("tile", "panel", "tile0", "rows", "lines") else sprite_bytes(rows), rows)
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


def slices_source(asset, encoded):
    """Overlays (masked sprites drawn a char row at a time by render_row) as
    code, one routine per slice of 8 lines: HL = plane 0 address of the row
    at the overlay's column (no plane end crossed), line j of the slice goes
    to plane j. Transparent bytes are skipped, opaque ones are ld (hl),n,
    mixed ones ld a,(hl) / and m / or d / ld (hl),a. HL moves on with inc hl
    (up to 3) or ld bc,n / add hl,bc. Destroys A, BC, HL.
    <prefix>_<name>: the slices' addresses, top slice first."""
    prefix = f"gfx_{asset}"
    lines = [f"; generated by tools/png2cpc.py from tools/assets.py - do not edit",
             f"; {asset}: {len(encoded)} overlays as code, a routine per char row"]
    for name, data, _ in encoded:
        width, height = data[0], data[1]
        pairs = data[2:]
        count = (height + 7) // 8
        lines.append(f"{prefix}_{name}:")
        lines += [f"                defw {prefix}_{name}_s{k}" for k in range(count)]
        for k in range(count):
            lines.append(f"{prefix}_{name}_s{k}:")
            at = 0
            for j, y in enumerate(range(8 * k, min(height, 8 * k + 8))):
                for x in range(width):
                    mask, value = pairs[2 * (y * width + x)], pairs[2 * (y * width + x) + 1]
                    if mask == 0xFF:
                        continue
                    offset = j * 0x800 + x
                    step = offset - at
                    if step > 3:
                        lines += [f"                ld bc,#{step:04X}", "                add hl,bc"]
                    else:
                        lines += ["                inc hl"] * step
                    at = offset
                    if mask == 0:
                        lines.append(f"                ld (hl),#{value:02X}")
                    else:
                        lines += ["                ld a,(hl)", f"                and #{mask:02X}"]
                        if value:
                            lines.append(f"                or #{value:02X}")
                        lines.append("                ld (hl),a")
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
    if kind == "rows":                         # back to back, no table
        lines += ["", f"{prefix}:"]
    else:
        lines += ["", f"{prefix}_table:"]
        lines += [f"                defw {prefix}_{name}" for name, _, _ in encoded]
    for name, data, _ in encoded:
        if kind == "sprite":                   # its code (kind "slices"), 0 if none
            code = f"gfx_{asset}_code_{name}" if f"{asset}_code" in assets.ASSETS else "0"
            lines.append(f"                defw {code}")
        lines.append(f"{prefix}_{name}:")
        for i in range(0, len(data), 16):
            lines.append("                defb " + ",".join(f"#{b:02X}" for b in data[i:i + 16]))
    return "\n".join(lines) + "\n"


FILL_MIN = 8                     # kind "lines": runs this long are fills


def line_ops(line):
    """One line of a "lines" tile as ops (src/bridges.asm): n (1-127) then
    n bytes to copy, or #80 + n then the byte to fill n times; 0 ends."""
    ops, literal, i = [], [], 0
    while i < len(line):
        j = i
        while j < len(line) and line[j] == line[i]:
            j += 1
        if j - i >= FILL_MIN:
            if literal:
                ops += [len(literal)] + literal
                literal = []
            ops += [0x80 | (j - i), line[i]]
        else:
            literal += line[i:j]
        i = j
    if literal:
        ops += [len(literal)] + literal
    return ops + [0]


def decode_line_ops(ops):
    out, i = [], 0
    while ops[i]:
        n = ops[i] & 0x7F
        if ops[i] & 0x80:
            out += [ops[i + 1]] * n
            i += 2
        else:
            out += ops[i + 1:i + 1 + n]
            i += 1 + n
    return out


def lines_tables(encoded):
    """Kind "lines": [(tile name, [line index] * height)], [ops of each distinct line]."""
    distinct, tiles = [], []
    for name, data, rows in encoded:
        width = len(rows[0]) // 2
        refs = []
        for y in range(len(rows)):
            line = tuple(data[y * width:(y + 1) * width])
            if line not in distinct:
                distinct.append(line)
            refs.append(distinct.index(line))
        tiles.append((name, refs))
    return tiles, [line_ops(list(line)) for line in distinct]


def lines_source(asset, encoded):
    """Tiles as lines: a tile is its line pointers, each distinct line a run
    of copy / fill ops (line_ops), drawn by src/bridges.asm."""
    prefix = f"gfx_{asset}"
    upper = prefix.upper()
    tiles, ops = lines_tables(encoded)
    _, data, rows = encoded[0]
    lines = [f"; generated by tools/png2cpc.py from tools/assets.py - do not edit",
             f"; {asset}: {len(encoded)} tiles of {len(rows)} lines, {len(ops)} distinct lines as ops",
             f"{upper}_WIDTH equ {len(rows[0]) // 2}            ; bytes",
             f"{upper}_HEIGHT equ {len(rows)}",
             f"{upper}_COUNT equ {len(encoded)}"]
    for index, (name, _) in enumerate(tiles):
        lines.append(f"IDX_{asset.upper()}_{name.upper()} equ {index}")
    lines += ["", f"{prefix}_table:"]
    lines += [f"                defw {prefix}_{name}" for name, _ in tiles]
    for name, refs in tiles:
        lines.append(f"{prefix}_{name}:")
        lines.append("                defw " + ",".join(f"{prefix}_line{k}" for k in refs))
    for k, line in enumerate(ops):
        lines.append(f"{prefix}_line{k}:")
        for i in range(0, len(line), 16):
            lines.append("                defb " + ",".join(f"#{b:02X}" for b in line[i:i + 16]))
    return "\n".join(lines) + "\n"


def lines_size(encoded):
    tiles, ops = lines_tables(encoded)
    return 2 * len(tiles) + sum(2 * len(refs) for _, refs in tiles) + sum(len(o) for o in ops)


def main(names):
    names = names or list(assets.ASSETS)
    os.makedirs(OUT_DIR, exist_ok=True)
    try:
        for asset in names:
            kind, encoded = convert(asset)
            path = os.path.join(OUT_DIR, f"gfx_{asset}.asm")
            with open(path, "w") as f:
                f.write(compiled_source(asset, encoded) if kind == "compiled"
                        else slices_source(asset, encoded) if kind == "slices"
                        else lines_source(asset, encoded) if kind == "lines"
                        else asm_source(asset, kind, encoded))
            size = lines_size(encoded) if kind == "lines" else sum(len(d) for _, d, _ in encoded)
            print(f"{asset:10s} {len(encoded):3d} {kind}s {size:6d} bytes -> {os.path.relpath(path, ROOT)}")
    except GfxError as e:
        print(f"png2cpc: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
