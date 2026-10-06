"""Phase 3: world generation, environments, bridges, scenery."""

from harness import boot_game, load_symbols, peek8, peek16, save_screenshot, sync_game_frame
from world_model import F_BRIDGE, F_FOREST, F_OVERLAY, Sheets, read_desc, screen_row, visible_rows

TRACK_TILES = 39
HUD_PANEL = range(74, 92)            # bytes where the HUD draws its elements
RUNNER_ROWS = range(28, 34)          # picture rows the runner (and its shadow) can touch


def _pause(cpc, sym):
    cpc.write_ram(sym["scroll_speed"], bytes([0]))
    sync_game_frame(cpc, sym)
    sync_game_frame(cpc, sym)


def _check_screen(cpc, sym, sheets):
    """Visible rows equal their tiles wherever no overlay can cover them:
    lanes without an item (nor a power-up reaching up from the row below),
    sides only in rows without overlays, the HUD always.
    Returns the number of row parts compared."""
    checked = 0
    cars = []                                # moving cars (move_cars): their rows and column
    for i in range(2):
        m = cpc.read_ram(sym["movers"] + 8 * i, 8)
        if m[0] == 2:
            lo = m[2] | m[3] << 8
            cars.append((lo // 8, (lo + 15) // 8, m[1]))
    for index, (row, bank, ring) in enumerate(visible_rows(cpc, sym)):
        desc = read_desc(cpc, sym, row)
        below = read_desc(cpc, sym, row - 1)
        for column, width, pens in sheets.expected(desc, row):
            if column == 72:                 # HUD: only the frame around the panel
                got = screen_row(cpc, bank, ring, column, width)
                keep = [x for x in range(48) if 72 + x // 2 not in HUD_PANEL]
                assert [[line[x] for x in keep] for line in got] == [[line[x] for x in keep] for line in pens], \
                    f"world row {row}: HUD frame differs"
                if index < 9 or index > 26:      # away from the slots (lines 80-203): plain panel
                    panel = [x for x in range(48) if 72 + x // 2 in HUD_PANEL]
                    assert all(line[x] == 1 for line in got for x in panel), \
                        f"world row {row} (picture row {index}): HUD panel not plain"
                checked += 1
                continue
            elif width == 14:
                if index in RUNNER_ROWS:
                    continue
                lane = (column - 15) // 14
                if desc["items"][lane] or below["items"][lane] > 1:
                    continue
            elif desc["flags"] & F_OVERLAY or (column == 0 and width == 72 and index in RUNNER_ROWS):
                continue
            elif any(low <= row <= high and column <= col < column + width for low, high, col in cars):
                continue
            assert screen_row(cpc, bank, ring, column, width) == pens, \
                f"world row {row}: bytes {column}..{column + width - 1} differ from the tiles"
            checked += 1
    return checked


def _check_desc(desc, row):
    if desc["flags"] & F_BRIDGE:
        assert desc["left"] < 11 and desc["lanes"] == [0, 0, 0], f"row {row}: bad bridge row {desc}"
        return
    count = 16 if desc["flags"] & F_FOREST else 12
    assert desc["left"] < count and desc["left"] % 2 == 0, f"row {row}: left side {desc}"
    assert desc["right"] < count and desc["right"] % 2 == 1, f"row {row}: right side {desc}"
    assert all(t < TRACK_TILES for t in desc["lanes"]), f"row {row}: lane tiles {desc}"
    assert all((c & 15) <= 7 for c in desc["coll"]), f"row {row}: collision {desc}"
    assert all(i <= 7 for i in desc["items"]), f"row {row}: items {desc}"


def test_trains_vary_in_lane_livery_and_length():
    """Every chunk gets a random lane order and livery: over a long run the
    trains turn up in all three lanes, in all three liveries, 2-4 wagons long."""
    import sys
    import os
    from collections import Counter
    from harness import ROOT
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import assets
    names = assets.TRACK_TILES
    sym = load_symbols()
    cpc = boot_game()
    cpc.write_ram(sym["scroll_speed"], bytes([6]))
    seen = {}
    for _ in range(4000):
        sync_game_frame(cpc, sym)
        top = peek16(cpc, sym["scr_top_row"])
        for r in range(top - 20, top):
            if r not in seen:
                seen[r] = read_desc(cpc, sym, r)["lanes"]
    lanes, liveries, lengths = Counter(), Counter(), Counter()
    for lane in range(3):
        run = 0
        for r in sorted(seen):
            name = names[seen[r][lane]] if seen[r][lane] < len(names) else ""
            if name.startswith(("wagon", "loco")):
                lanes[lane] += 1
                liveries[name[4] if name.startswith("loco") else name[5]] += 1
                run += name.endswith("coupler")
            elif run:
                lengths[run] += 1
                run = 0
    print(f"    train rows by lane {dict(lanes)}, by livery {dict(liveries)}, wagons {dict(lengths)}")
    assert all(lanes[lane] > 0.15 * sum(lanes.values()) for lane in range(3)), lanes
    assert all(liveries[t] > 0.15 * sum(liveries.values()) for t in "123"), liveries
    assert {2, 3, 4} <= set(lengths), lengths


def test_rows_on_screen_match_their_descriptors():
    sym = load_symbols()
    sheets = Sheets()
    cpc = boot_game()
    checked = 0
    for stop in range(6):
        _pause(cpc, sym)
        checked += _check_screen(cpc, sym, sheets)
        cpc.write_ram(sym["scroll_speed"], bytes([6]))
        cpc.run_frames(400)
    print(f"    {checked} row parts compared")
    assert checked > 600


def test_five_minute_flight():
    """~5 minutes of play at mixed speeds: no missed frames, valid rows,
    both environments, transitions, both bridge types, varied track."""
    sym = load_symbols()
    cpc = boot_game()
    seen_rows = {}
    for minute in range(5):
        for speed in (2, 4, 6):
            cpc.write_ram(sym["scroll_speed"], bytes([speed]))
            for _ in range(8):
                cpc.run_frames(125)                  # 2.5 s
                top = peek16(cpc, sym["scr_top_row"])
                assert sym["start"] <= cpc.pc < 0x8000 or cpc.pc < 0x40, f"PC #{cpc.pc:04X}"   # code, banks
                for row in range(top - 33, top):     # the top row may be mid-generation
                    desc = read_desc(cpc, sym, row)
                    _check_desc(desc, row)
                    seen_rows[row] = desc
        save_screenshot(cpc, f"flight_{minute}.png")

    missed = peek8(cpc, sym["missed_frames"])
    max_load = peek8(cpc, sym["max_load"])
    rows = [seen_rows[r] for r in sorted(seen_rows)]
    forest = [bool(d["flags"] & F_FOREST) and not d["flags"] & F_BRIDGE for d in rows]
    switches = sum(1 for a, b in zip(forest, forest[1:]) if a != b)
    bridge_tiles = {d["left"] for d in rows if d["flags"] & F_BRIDGE}
    track_tiles = {t for d in rows if not d["flags"] & F_BRIDGE for t in d["lanes"]}
    print(f"    {len(rows)} rows, {switches} env switches, bridge tiles {sorted(bridge_tiles)}, "
          f"{len(track_tiles)} track tiles, max load {max_load}/12")
    assert missed == 0, f"{missed} game frames missed"
    assert max_load < 12
    assert len(rows) > 2000
    assert switches >= 4
    assert {0, 4} <= bridge_tiles, "both bridge types (shadow rows 3 and 10, deck rows 0/4) expected"
    assert len(track_tiles) >= 25


def test_power_ups_one_every_50_to_150_rows_turbo_most():
    """The generator places the power-ups (chunks hold coins only): one at a
    time, 50-150 rows apart, never close to an obstacle (8 clear rows ahead
    and behind in its lane; on a roof the train goes on 8 rows both ways),
    turbo ~30%, the other five sharing the rest."""
    from collections import Counter
    sym = load_symbols()
    cpc = boot_game()
    cpc.write_ram(sym["scroll_speed"], bytes([6]))
    seen, coll, lanes = {}, {}, {}
    for _ in range(6000):
        sync_game_frame(cpc, sym)
        top = peek16(cpc, sym["scr_top_row"])
        for r in range(top - 20, top):
            if r not in seen:
                desc = cpc.read_ram(sym["world_ring"] + (r & 63) * sym["row_size"] + 6, 6)
                coll[r] = [c & 15 for c in desc[:3]]
                seen[r] = [x for x in desc[3:] if x > 1]
                lanes[r] = [lane for lane in range(3) if desc[3 + lane] > 1]
    rows = sorted(r for r, items in seen.items() if items)
    roofs = 0
    for r in rows:                              # 8 rows without an obstacle around it
        lane = lanes[r][0]
        near = [coll[r + k][lane] for k in range(-8, 9) if k and r + k in coll]
        if coll[r][lane] == 3:                  # on a wagon roof: the train goes on
            roofs += 1
            assert coll.get(r + 1, [3] * 3)[lane] == 3, (r, lane, "over a coupler")
            assert all(c in (3, 5, 6, 7) for c in near), (r, lane, near)
        else:
            assert all(c in (0, 5, 6) for c in near), (r, lane, near)
    kinds = Counter(seen[r][0] for r in rows)
    gaps = [b - a for a, b in zip(rows, rows[1:])]
    print(f"    {len(rows)} power-ups in {len(seen)} rows ({roofs} on roofs), gaps {min(gaps)}-{max(gaps)}, "
          f"kinds {dict(kinds)}")
    assert roofs >= 2, "power-ups on the train roofs too"
    assert all(len(items) <= 1 for items in seen.values()), "one power-up at a time"
    assert all(50 <= g <= 200 for g in gaps), gaps          # no safe spot: a little later
    assert sum(g <= 151 for g in gaps) >= 0.9 * len(gaps), gaps
    assert set(kinds) == {2, 3, 4, 5, 6, 7}, "every kind turns up"
    assert kinds.most_common(1)[0][0] == 3, "turbo is the most common"
    assert 0.18 <= kinds[3] / len(rows) <= 0.45            # 30% of ~50 samples


def _obstacle_share(skill, rows_wanted=1600):
    """(share of rows with an obstacle in the first and the last 300 rows,
    empty rows left after each chunk 800 rows in)."""
    sym = load_symbols()
    cpc = boot_game()
    cpc.write_ram(sym["skill"], bytes([skill]))
    cpc.write_ram(sym["scroll_speed"], bytes([6]))
    seen, gap = {}, None
    while len(seen) < rows_wanted:
        sync_game_frame(cpc, sym)
        top = peek16(cpc, sym["scr_top_row"])
        for r in range(top - 20, top):
            if r not in seen and r >= 0:
                coll = cpc.read_ram(sym["world_ring"] + (r & 63) * sym["row_size"] + 6, 3)
                seen[r] = any((c & 15) in (1, 2, 3, 4, 7) for c in coll)
        if gap is None and len(seen) >= 800:
            gap = peek8(cpc, sym["spacer_len"])
    rows = sorted(seen)
    first = [seen[r] for r in rows[:300]]
    last = [seen[r] for r in rows[-300:]]
    return sum(first) / 300, sum(last) / 300, gap


def test_obstacles_get_denser_and_faster_on_hard():
    easy_first, easy_last, easy_gap = _obstacle_share(0)
    hard_first, hard_last, hard_gap = _obstacle_share(2)
    print(f"    rows with obstacles: easy {easy_first:.0%} -> {easy_last:.0%} (gap at 800: {easy_gap}), "
          f"hard {hard_first:.0%} -> {hard_last:.0%} (gap at 800: {hard_gap})")
    assert easy_last > easy_first and hard_last > hard_first
    assert hard_gap < easy_gap, "the empty stretches shrink faster on hard"


def test_easy_at_most_two_obstacles_a_lane_on_a_screen():
    """Easy: a buffer stop or a signal never has two other obstacles before it
    in its lane within a screen (34 rows); trains (ramps, roofs) stay as
    they are. Medium keeps the chunks as written."""
    sym = load_symbols()
    picture = sym["picture_rows"]
    for skill in (0, 1):
        cpc = boot_game()
        cpc.write_ram(sym["skill"], bytes([skill]))
        cpc.write_ram(sym["scroll_speed"], bytes([6]))
        classes = {}
        while len(classes) < 2500:
            sync_game_frame(cpc, sym)
            top = peek16(cpc, sym["scr_top_row"])
            for r in range(max(top - 20, 0), top):
                if r not in classes:
                    coll = cpc.read_ram(sym["world_ring"] + (r & 63) * sym["row_size"] + 6, 3)
                    classes[r] = [c & 15 for c in coll]
        crowded = 0
        for lane in range(3):
            starts = [(r, classes[r][lane]) for r in sorted(classes)
                      if classes[r][lane] in (1, 2, 3, 4, 7) and classes.get(r - 1, [0] * 3)[lane] in (0, 5, 6)]
            for i, (row, cls) in enumerate(starts):
                before = [s for s, _ in starts[:i] if row - s < picture]
                if cls in (1, 2) and len(before) >= 2:
                    crowded += 1
        print(f"    skill {skill}: {crowded} stops or signals with two obstacles before them on a screen")
        if skill == 0:
            assert crowded == 0
        else:
            assert crowded > 0, "medium keeps the dense chunks"
