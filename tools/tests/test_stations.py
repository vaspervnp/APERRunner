"""Stations (src/platform.asm): from each station row on, after a few rows,
platforms beside the track on both sides (concrete, benches, a canopy with
name boards), over the avenue or the forest, with no scenery on them."""

from harness import boot_game, load_symbols, sync_game_frame
from test_world import _check_screen, _pause
from world_model import (F_BRIDGE, F_FOREST, F_OVERLAY, F_PLATFORM, F_STATION, PLATFORM_SEQ, Sheets,
                         read_desc, visible_rows)


def _boot(speed):
    sym = load_symbols()
    cpc = boot_game()
    cpc.write_ram(sym["no_crash"], bytes([1]))
    cpc.write_ram(sym["scroll_speed"], bytes([speed]))
    return sym, cpc


def test_platform_rows_follow_each_station_row():
    """The station row starts the count (D_PLAT = 22, down to 1 a row
    further each row); those rows carry F_PLATFORM and no scenery."""
    sym, cpc = _boot(7)
    rows, stations = {}, 0
    for _ in range(3000):
        sync_game_frame(cpc, sym)
        for row, _, _ in visible_rows(cpc, sym):
            rows[row] = read_desc(cpc, sym, row)
    for row in sorted(rows):
        desc = rows[row]
        if not desc["flags"] & F_STATION:
            continue
        stations += 1
        for k in range(len(PLATFORM_SEQ) - 1):
            above = rows.get(row + k)
            if above is None:
                break
            assert above["plat"] == len(PLATFORM_SEQ) - 1 - k, (row, k, above)
            assert above["flags"] & F_PLATFORM or above["flags"] & F_BRIDGE, (row, k, above)
            # overlays only from items (the first rows: scenery from before ends there)
            below = rows.get(row + k - 1, {"items": [0, 0, 0]})
            if PLATFORM_SEQ[above["plat"]] and above["flags"] & F_OVERLAY:
                assert any(above["items"]) or any(below["items"]), ("scenery on a platform", row, k, above)
        assert rows.get(row + len(PLATFORM_SEQ) - 1, {"plat": 0})["plat"] == 0
    print(f"    {stations} stations")
    assert stations >= 3


def test_platforms_are_drawn():
    """With the scroll stopped over a station, its rows equal the side tiles
    with the platform lines over pixels 16-29 (left) and 0-13 (right)."""
    sheets = Sheets()
    sym, cpc = _boot(6)
    compared, envs = 0, set()
    for _ in range(6000):
        sync_game_frame(cpc, sym)
        shown = [(index, read_desc(cpc, sym, row)) for index, (row, _, _) in enumerate(visible_rows(cpc, sym))]
        platform = [index for index, desc in shown if PLATFORM_SEQ[desc["plat"]]]
        if len(platform) < 14 or max(platform) > 27:
            continue
        _pause(cpc, sym)
        _check_screen(cpc, sym, sheets)
        for index, (row, _, _) in enumerate(visible_rows(cpc, sym)):
            desc = read_desc(cpc, sym, row)
            if PLATFORM_SEQ[desc["plat"]] and not desc["flags"] & F_BRIDGE:
                compared += 1
                envs.add("forest" if desc["flags"] & F_FOREST else "urban")
        cpc.write_ram(sym["scroll_speed"], bytes([6]))
        for _ in range(60):
            sync_game_frame(cpc, sym)
        if compared >= 40 and len(envs) == 2:
            break
    print(f"    {compared} platform rows compared, over {sorted(envs)}")
    assert compared >= 40, compared
