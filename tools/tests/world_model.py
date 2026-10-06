"""Reads the game's world state (src/world.asm) from emulator RAM and
rebuilds the expected screen rows from the converted sheets."""

import os
import sys

from harness import ROOT, peek16

sys.path.insert(0, os.path.join(ROOT, "tools"))
import assets  # noqa: E402
import png2cpc  # noqa: E402

F_FOREST, F_STATION, F_PLATFORM, F_OVERLAY, F_BRIDGE = 0x01, 0x02, 0x10, 0x40, 0x80

# station platforms (src/platform.asm): the lines of each kind of row, top to
# bottom (None: the side tile's line), and the kind by D_PLAT (1 = the top row)
_C, _J, _R = "concrete", "joint", "ramp"
_A, _B = "roof_a", "roof_b"
PLATFORM_KINDS = {
    "end_lo": [_C, _C, _C, _C, _C, _R, None, None],
    "end_hi": [None, None, _R, _C, _C, _C, _C, _J],
    "plain": [_C, _C, _C, _C, _J, _C, _C, _C],
    "bench": [_C, _C, "bench_back", "bench_seat", "bench_shadow", _C, _C, _J],
    "sign": [_A, _B, "sign_edge", "sign_text", "sign_text", "sign_edge", _B, _A],
    "roof": [_B, _A, _B, _A, _B, _A, _B, _A],
    "roof_lo": [_A, _B, _A, _B, _A, _B, _A, "roof_shadow"],
}
PLATFORM_SEQ = [None, "end_hi", "plain", "bench", "plain", "plain", "bench", "plain",
                "roof", "sign", "roof", "roof", "sign", "roof", "roof_lo",
                "plain", "bench", "plain", "end_lo", None, None, None, None]


def read_desc(cpc, sym, row):
    base = sym["world_ring"] + (row & (sym["ring_rows"] - 1)) * sym["row_size"]
    raw = cpc.read_ram(base, sym["row_size"])
    return {"flags": raw[0], "left": raw[1], "right": raw[2], "lanes": list(raw[3:6]),
            "coll": list(raw[6:9]), "items": list(raw[9:12]), "plat": raw[12]}


def visible_rows(cpc, sym):
    """[(world row, bank, ring offset of the row)] top to bottom (34 rows)."""
    top = peek16(cpc, sym["scr_top_row"])
    out = []
    for block, (bank, key) in enumerate(((0x8000, "cur_d1"), (0xC000, "cur_d2"))):
        offset = peek16(cpc, sym[key])
        for r in range(17):
            out.append((top - block * 17 - r, bank, offset + r * 96))
    return out


def screen_row(cpc, bank, ring_offset, column, width_bytes):
    lines = []
    for plane in range(8):
        row = []
        for b in range(width_bytes):
            address = bank + plane * 0x800 + ((ring_offset + column + b) & 0x7FF)
            row += png2cpc.decode_byte(cpc.read_ram(address, 1)[0])
        lines.append(row)
    return lines


class Sheets:
    def __init__(self):
        self.track = png2cpc.load_sheet("track")
        self.track_names = [n for n, _, _ in assets.SHEETS["track"]]
        self.sides = {}
        for sheet in ("urban", "forest"):
            frames = png2cpc.load_sheet(sheet)
            names = [n for n, _, _ in assets.SHEETS[sheet]]
            # converted tables interleave original and mirrored copies
            self.sides[sheet] = [frames[names[i // 2]] if i % 2 == 0 else png2cpc.mirror(frames[names[i // 2]])
                                 for i in range(2 * len(names))]
        bridges = png2cpc.load_sheet("bridges")
        self.bridges = [bridges[n] for n, _, _ in assets.SHEETS["bridges"]]
        self.platform = png2cpc.load_sheet("platform")
        hud = png2cpc.load_sheet("hud")
        self.hud, self.hud_sleeper, self.hud_station = hud["hud_bg"], hud["hud_bg_t"], hud["hud_station"]

    def expected(self, desc, row=0):
        """Expected pens for (column, width, lines) parts of a row."""
        parts = []
        if desc["flags"] & F_BRIDGE:
            parts.append((0, 72, self.bridges[desc["left"]]))
        else:
            sides = self.sides["forest" if desc["flags"] & F_FOREST else "urban"]
            left, right = sides[desc["left"]], sides[desc["right"]]
            kind = PLATFORM_SEQ[desc.get("plat", 0)]
            if kind:                     # a platform: pixels 16-29 left, 0-13 right
                lines = PLATFORM_KINDS[kind]
                left = [side if name is None else side[:16] + self.platform[name][0]
                        for side, name in zip(left, lines)]
                right = [side if name is None else self.platform[name][0][::-1] + side[14:]
                         for side, name in zip(right, lines)]
            parts.append((0, 15, left))
            parts.append((57, 15, right))
            for lane in range(3):
                parts.append((15 + lane * 14, 14, self.track[self.track_names[desc["lanes"][lane]]]))
        # the HUD frame: a station board, or the little track's sleeper on odd rows
        parts.append((72, 24, self.hud_station if desc["flags"] & F_STATION
                       else self.hud_sleeper if row & 1 else self.hud))
        return parts
