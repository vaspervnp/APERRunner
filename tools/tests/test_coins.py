"""Spinning coins (src/coins_c5.asm): the coins on the picture turn, a few a
frame, each drawn as one of the coin's frames over its lane tile."""

import os
import sys

from harness import ROOT, boot_game, load_symbols, peek16, sync_game_frame
from world_model import F_BRIDGE, read_desc, screen_row, visible_rows

sys.path.insert(0, os.path.join(ROOT, "tools"))
import png2cpc  # noqa: E402

COIN_X, COIN_W, LAST_ROW = 5, 4, 25          # coins_c5.asm: its bytes, the rows it turns


def _frames():
    """{track tile: [frame 0..3 as 8 lines of pens]}"""
    _, encoded = png2cpc.convert("coin_bg")
    out = {}
    for tile, data in png2cpc.coin_bg_blocks(encoded):
        frames = []
        for f in range(4):
            block = data[f * 32:(f + 1) * 32]
            frames.append([[p for b in block[y * 4:y * 4 + 4] for p in png2cpc.decode_byte(b)] for y in range(8)])
        out[tile] = frames
    return out


def test_coins_turn_and_stay_coins_over_their_tile():
    frames = _frames()
    sym = load_symbols()
    cpc = boot_game()
    cpc.write_ram(sym["no_crash"], bytes([1]))
    cpc.write_ram(sym["scroll_speed"], bytes([5]))
    seen, checked, turned = {}, 0, 0
    for frame in range(3000):
        sync_game_frame(cpc, sym)
        if frame % 50:
            continue
        cpc.write_ram(sym["scroll_speed"], bytes([0]))   # light frames: they all turn
        for _ in range(12):
            sync_game_frame(cpc, sym)
            cpc.run_us(15000)                    # (the frame done)
            label = (peek16(cpc, sym["label_line"]) - 112) // 8
            for index, (row, bank, ring) in enumerate(visible_rows(cpc, sym)):
                if index > LAST_ROW or abs(row - label - 1) <= 3:
                    continue
                desc = read_desc(cpc, sym, row)
                if desc["flags"] & F_BRIDGE:
                    continue
                for lane in range(3):
                    if desc["items"][lane] != 1 or desc["lanes"][lane] not in frames:
                        continue
                    got = screen_row(cpc, bank, ring, 15 + 14 * lane + COIN_X, COIN_W)
                    options = frames[desc["lanes"][lane]]
                    assert got in options, (frame, row, lane, desc)
                    key = (row, lane)
                    if seen.get(key, got) != got:
                        turned += 1
                    seen[key] = got
                    checked += 1
        cpc.write_ram(sym["scroll_speed"], bytes([5]))
        if turned >= 40:
            break
    print(f"    {checked} coins compared, {turned} turns seen")
    assert checked >= 100 and turned >= 40, (checked, turned)
