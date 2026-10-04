"""Phase 2: graphics pipeline - palette, converter and tiles on screen."""

import os
import sys

from harness import ROOT, boot_game, load_symbols, peek8, peek16, sync_game_frame

sys.path.insert(0, os.path.join(ROOT, "tools"))
import assets  # noqa: E402
import cpcpalette  # noqa: E402
import png2cpc  # noqa: E402


def test_palette_has_16_distinct_editor_colours():
    colours = [cpcpalette.editor_rgb(pen) for pen in range(16)]
    assert len(set(colours)) == 16
    assert cpcpalette.hardware_colour(15) == cpcpalette.hardware_colour(13)   # lamp starts red


def test_mode0_encoding_round_trips():
    for left in range(16):
        for right in range(16):
            byte = png2cpc.encode_pixel(left, 0) | png2cpc.encode_pixel(right, 1)
            assert png2cpc.decode_byte(byte) == (left, right)


def test_every_asset_converts_with_the_manifest_sizes():
    for asset, (sheet, kind, wanted, mirror) in assets.ASSETS.items():
        _, encoded = png2cpc.convert(asset)
        sizes = {name: (w, h) for name, w, h in assets.SHEETS[sheet]}
        for name, data, rows in encoded:
            w, h = sizes[name[:-2] if name.endswith("_m") else name]
            assert (len(rows[0]), len(rows)) == (w, h)
            expected = w // 2 * h if kind in ("tile", "panel", "tile0") else 2 + w * h
            assert len(data) == expected, f"{asset}/{name}"


def test_sprite_masks_match_transparency():
    _, encoded = png2cpc.convert("items")
    name, data, rows = encoded[0]
    pairs = data[2:]
    for y, row in enumerate(rows):
        for x in range(0, len(row), 2):
            mask, value = pairs[2 * (y * len(row) // 2 + x // 2):][:2]
            for position, pen in enumerate(row[x:x + 2]):
                bits = png2cpc.PIXEL_MASK[position]
                if pen is None:
                    assert mask & bits == bits and value & bits == 0
                else:
                    assert mask & bits == 0 and png2cpc.decode_byte(value)[position] == pen


def test_off_palette_colour_is_rejected(tmp_path=None):
    import tempfile
    from PIL import Image
    folder = tempfile.mkdtemp()
    Image.new("RGBA", (28 * len(assets.SHEETS["track"]), 8), (1, 2, 3, 255)).save(os.path.join(folder, "track.png"))
    saved = png2cpc.GFX_DIRS
    png2cpc.GFX_DIRS = [folder]
    try:
        png2cpc.load_sheet("track")
    except png2cpc.GfxError as e:
        assert "not in the game palette" in str(e)
    else:
        raise AssertionError("off-palette colour accepted")
    finally:
        png2cpc.GFX_DIRS = saved


def test_every_sheet_has_real_art():
    for sheet in assets.SHEETS:
        png, _ = png2cpc.find_sheet(sheet)
        assert os.sep + os.path.join("gfx", "png") + os.sep in png, f"{sheet} still uses a placeholder"


def test_hud_background_is_vertically_uniform():
    rows = png2cpc.load_sheet("hud")["hud_bg"]
    for x in range(len(rows[0])):
        assert len({row[x] for row in rows}) == 1, f"HUD column {x} changes colour"
