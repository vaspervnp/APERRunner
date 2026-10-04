"""Graphics manifest: which sheets exist, their frames and how they convert.

A sheet is one Aseprite file exported as gfx/png/<sheet>.png + .json
(frames left to right). Until the real art exists, tools/mkplaceholders.py
writes stand-ins to gfx/placeholder/. Sizes are in mode 0 pixels.

An asset converts frames of a sheet into src/data/gfx_<asset>.asm:
  kind "tile"   - opaque, width/2 bytes per line, lines top to bottom
  kind "sprite" - masked: width (bytes), height, then (mask, data) pairs
  kind "panel"  - opaque like a tile, transparent pixels become the HUD
                  panel colour (PANEL_PEN); for the HUD in main RAM
  kind "tile0"  - the same with black (pen 0): text on the menu screens
  kind "compiled" - masked sprite as code (see png2cpc.compiled_source):
                  saves the background and draws, no data reads
  kind "header" - width (bytes) and height only, for sprites drawn by
                  their compiled code
  mirror        - also emit horizontally mirrored copies (<frame>_m)
"""

TRAIN_TYPES = (1, 2, 3)
PANEL_PEN = 1                   # HUD panel background (gfx/src/items.lua)

TRACK_TILES = (
    ["rail_a", "rail_b", "stop_0", "stop_1", "signal_0", "signal_1"]
    + [f"wagon{t}_{part}" for t in TRAIN_TYPES
       for part in ("end_bottom", "body_a", "body_b", "end_top", "coupler")]
    + [f"loco{t}_{part}" for t in TRAIN_TYPES for part in ("nose", "body", "pantograph", "nose_top")]
    + [f"ramp_up_{i}" for i in range(3)]
    + [f"ramp_down_{i}" for i in range(3)]
)

URBAN_TILES = ["road_a", "road_b", "road_cross_0", "road_cross_1", "road_kiosk_0", "road_kiosk_1"]
FOREST_TILES = (["ground_a", "ground_b", "path", "fence"]
                + [f"trans_urban_forest_{i}" for i in range(2)]
                + [f"trans_forest_urban_{i}" for i in range(2)])
BRIDGE_ROWS = ([f"footbridge_{i}" for i in range(3)] + ["footbridge_shadow"]
               + [f"roadbridge_{i}" for i in range(6)] + ["roadbridge_shadow"])

PLAYER_FRAMES = (
    [(f"s1_{f}", 10, 16) for f in ("run0", "run1", "run2", "run3", "lean_l", "lean_r", "crash0", "crash1")]
    + [(f"s2_{f}", 12, 18) for f in ("jump_up", "jump_down")]
    + [(f"s3_{f}", 14, 20) for f in ("run0", "run1", "run2", "run3", "lean_l", "lean_r",
                                       "crash0", "crash1", "jump_up", "jump_down")]
    + [(f"s4_{f}", 16, 22) for f in ("jump_up", "jump_down")]
    + [("s5_jump", 18, 24)]
)

POWERUPS = ["pu_magnet", "pu_turbo", "pu_slow", "pu_spring", "pu_helmet", "pu_ticket"]
HUD_ICONS = ["ic_coin", "ic_magnet", "ic_turbo", "ic_slow", "ic_spring", "ic_helmet",
             "ic_ticket", "ic_life", "ic_dist"]
HUD_DIGITS = [f"d{d}" for d in range(10)]

# font sheet order (gfx/src/font.lua): frame name, characters it draws
FONT_GLYPHS = (
    [("space", " ")]
    + [(c.lower(), c + {"A": "Α", "B": "Β", "E": "Ε", "Z": "Ζ", "H": "Η", "I": "Ι", "K": "Κ", "M": "Μ",
                        "N": "Ν", "O": "Ο", "P": "Ρ", "T": "Τ", "Y": "Υ", "X": "Χ"}.get(c, ""))
       for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ"]
    + [(f"n{d}", str(d)) for d in range(10)]
    + [("gamma", "Γ"), ("delta", "Δ"), ("theta", "Θ"), ("lambda", "Λ"), ("xi", "Ξ"), ("pi", "Π"),
       ("sigma", "Σ"), ("phi", "Φ"), ("psi", "Ψ"), ("omega", "Ω")]
    + [("dot", ".,"), ("colon", ":"), ("minus", "-"), ("excl", "!"), ("quest", "?;"), ("slash", "/"),
       ("left", "←"), ("right", "→"), ("up", "↑"), ("down", "↓")]
)


def _fixed(names, w, h):
    return [(n, w, h) for n in names]


# sheet name -> list of (frame name, width, height)
SHEETS = {
    "track": _fixed(TRACK_TILES, 28, 8),
    "urban": _fixed(URBAN_TILES, 30, 8),
    "urban_ov": _fixed(["car_red", "car_blue", "car_white", "taxi"], 8, 16)
                + _fixed(["bus", "trolley"], 8, 32),
    "forest": _fixed(FOREST_TILES, 30, 8),
    "forest_ov": [("pine", 16, 24), ("oak", 24, 24), ("cypress", 8, 24), ("bush", 8, 8), ("rock", 8, 8)],
    "bridges": _fixed(BRIDGE_ROWS, 144, 8),
    "player": PLAYER_FRAMES,
    "shadows": [("sh1", 8, 4), ("sh2", 10, 4), ("sh3", 12, 6), ("sh4", 14, 6)],
    "items": _fixed([f"coin{i}" for i in range(4)], 8, 8) + _fixed(POWERUPS, 12, 12),
    "font": [(name, 6, 8) for name, _ in FONT_GLYPHS],
    "logo": [("logo", 144, 48)],
    "hud": ([("hud_bg", 48, 8)] + _fixed(HUD_ICONS, 8, 8) + [("bar_full", 2, 8), ("bar_empty", 2, 8)]
            + _fixed(HUD_DIGITS, 4, 8)),
}

# asset name -> (sheet, kind, frames or None for all, mirror)
ASSETS = {
    "track": ("track", "tile", None, False),
    "urban": ("urban", "tile", None, True),
    "urban_ov": ("urban_ov", "sprite", None, True),
    "forest": ("forest", "tile", None, True),
    "forest_ov": ("forest_ov", "sprite", None, False),
    "bridges": ("bridges", "tile", None, False),
    "player": ("player", "header", None, False),        # width, height (drawn by player_code)
    "shadows": ("shadows", "sprite", None, False),
    "items": ("items", "sprite", None, False),
    "hud_bg": ("hud", "tile", ["hud_bg"], False),
    "hud_icons": ("hud", "panel", HUD_ICONS + ["bar_full", "bar_empty"] + HUD_DIGITS, False),
    "coin_code": ("items", "compiled", [f"coin{i}" for i in range(4)], False),
    "player_code": ("player", "compiled", None, False),
    "font": ("font", "tile0", None, False),
    "logo": ("logo", "tile", None, False),
}
