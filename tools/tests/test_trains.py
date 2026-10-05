"""Moving trains (src/trains.asm): the right lane comes towards the runner,
the left lane goes the same way more slowly, the middle lane stands still.
Easy: none move; medium: only the left lane; hard: both."""

from harness import boot_game, load_symbols, peek8, peek16, sync_game_frame
from world_model import F_BRIDGE, F_OVERLAY, Sheets, read_desc, screen_row, visible_rows

import cpc as cpcmod  # noqa: E402  (path set up by harness)

RUNNER_ROWS = range(28, 34)          # picture rows the runner (and its shadow) can touch


def _boot(skill, speed):
    sym = load_symbols()
    cpc = boot_game()
    cpc.write_ram(sym["skill"], bytes([skill]))
    cpc.write_ram(sym["no_crash"], bytes([1]))
    cpc.write_ram(sym["scroll_speed"], bytes([speed]))
    return sym, cpc


def _train(cpc, sym):
    if not peek8(cpc, sym["train_on"]):
        return None
    return {"lane": peek8(cpc, sym["train_lane"]), "lo": peek16(cpc, sym["train_lo"]),
            "hi": peek16(cpc, sym["train_hi"]), "stop": peek16(cpc, sym["train_stop"]),
            "anchor": peek16(cpc, sym["train_anchor"]), "livery": peek8(cpc, sym["train_livery"])}


def _picture_lines(cpc, sym):
    """[lo, hi) world lines of the picture shown."""
    top = peek16(cpc, sym["cur_top_row"])
    return (top - 33) * 8, (top + 1) * 8


def test_easy_none_move_medium_only_left_hard_both():
    for skill, lanes_wanted in ((0, set()), (1, {0}), (2, {0, 2})):
        sym, cpc = _boot(skill, 5)
        lanes = set()
        for _ in range(3000):
            sync_game_frame(cpc, sym)
            train = _train(cpc, sym)
            if train:
                lanes.add(train["lane"])
        print(f"    skill {skill}: moving trains in lanes {sorted(lanes)}")
        assert lanes == lanes_wanted, (skill, lanes)


def test_right_comes_on_fast_left_goes_ahead_slowly():
    """Each frame the oncoming train drops 2 world lines, the one ahead climbs
    1 (it never passes its stop); at higher speeds a frame with a coarse step
    may leave the move to the next one: never more than a frame late, the
    same pace on average."""
    for speed in (4, 7):
        sym, cpc = _boot(2, speed)
        steps = {0: [], 2: []}
        prev = None
        for _ in range(4000):
            sync_game_frame(cpc, sym)
            train = _train(cpc, sym)
            if train and prev and train["anchor"] == prev["anchor"]:
                moved = train["lo"] - prev["lo"]
                assert train["hi"] - train["lo"] == prev["hi"] - prev["lo"], "the train keeps its length"
                # room before the stop, in lines (negative: a stop already inside it)
                room = prev["lo"] - prev["stop"] if train["lane"] == 2 else prev["stop"] - prev["hi"]
                if train["stop"] != prev["stop"]:
                    pass                            # a new stop (before or after the move)
                elif room < 0:
                    assert moved == 0, ("a stop inside it: it stands", train)
                elif room < 4:
                    assert abs(moved) <= room, ("never past its stop", moved, train)
                else:
                    steps[train["lane"]].append(moved)
            prev = train
        for lane, pace in ((2, -2), (0, 1)):
            moves = steps[lane]
            assert len(moves) > 60, (speed, lane, len(moves))
            average = sum(moves) / len(moves)
            print(f"    speed {speed}, lane {lane}: {len(moves)} frames, {average:+.2f} lines a frame")
            if speed < sym["train_lazy"]:
                assert set(moves) == {pace}, (speed, lane, set(moves))
            else:
                assert set(moves) <= {0, pace, 2 * pace}, (speed, lane, set(moves))
                assert abs(average - pace) < 0.25 * abs(pace), (speed, lane, average)


def _expected_lane(sheets, sym, desc, row, train):
    """The 8 lines of the train's lane in a world row, line by line."""
    wagon = sym["tile_wagons"] + 5 * train["livery"]
    loco = sym["tile_locos"] + 4 * train["livery"]
    low, high = (loco, wagon + 3) if train["lane"] == 2 else (wagon, loco + 3)
    lines = []
    for y in range(8):
        w = row * 8 + 7 - y
        if w < train["lo"] or w >= train["hi"]:
            tile = desc["lanes"][train["lane"]]
            if sym["tile_wagons"] <= tile < sym["tile_ramps"]:
                tile = sym["tile_rail_a"]
            line = y
        elif w < train["lo"] + 8:
            tile, line = low, 7 - (w - train["lo"])
        elif w >= train["hi"] - 8:
            tile, line = high, 7 - (w - (train["hi"] - 8))
        else:
            part = (row - train["anchor"]) & 7
            tile = wagon + (4 if part == 7 else 1 if part & 3 == 1 else 2)
            line = y
        lines.append(sheets.track[sheets.track_names[tile]][line])
    return lines


def _which(sheets, line):
    return [(name, y) for name in sheets.track_names for y in range(8) if sheets.track[name][y] == line][:3]


def test_moving_train_is_drawn_where_it_is():
    """With the scroll stopped the train still moves: its lane shows the ends
    line by line, the body between them and the rail around them."""
    sheets = Sheets()
    for skill in (1, 2):
        sym, cpc = _boot(skill, 4)
        checked, lanes = 0, set()
        for _ in range(4000):
            if checked >= 120 and (skill == 1 or lanes == {0, 2}):
                break
            sync_game_frame(cpc, sym)
            train = _train(cpc, sym)
            if not train:
                continue
            pic_lo, pic_hi = _picture_lines(cpc, sym)
            if train["hi"] <= pic_lo or train["lo"] >= pic_hi:
                continue
            cpc.write_ram(sym["scroll_speed"], bytes([0]))
            sync_game_frame(cpc, sym)                # the picture shown catches up
            for _ in range(3):
                sync_game_frame(cpc, sym)
                assert peek16(cpc, sym["scr_top_row"]) == peek16(cpc, sym["cur_top_row"])
                train = _train(cpc, sym)
                if not train:
                    break
                lanes.add(train["lane"])
                column = 15 + 14 * train["lane"]
                for index, (row, bank, ring) in enumerate(visible_rows(cpc, sym)):
                    if index in RUNNER_ROWS or row * 8 + 16 <= train["lo"] or row * 8 - 8 >= train["hi"]:
                        continue
                    desc = read_desc(cpc, sym, row)
                    below = read_desc(cpc, sym, row - 1)
                    if desc["flags"] & (F_BRIDGE | F_OVERLAY) or desc["items"][train["lane"]] \
                            or below["items"][train["lane"]] > 1:
                        continue
                    want = _expected_lane(sheets, sym, desc, row, train)
                    got = screen_row(cpc, bank, ring, column, 14)
                    assert got == want, f"skill {skill}, row {row}, train {train}: lines " \
                        f"{[y for y in range(8) if got[y] != want[y]]} differ, they look like " \
                        f"{[_which(sheets, got[y]) for y in range(8) if got[y] != want[y]]}, desc {desc}\n{got}\n{want}"
                    checked += 1
            cpc.write_ram(sym["scroll_speed"], bytes([4]))
            for _ in range(20):
                sync_game_frame(cpc, sym)
        print(f"    skill {skill}: {checked} rows of moving trains compared, lanes {sorted(lanes)}")
        assert checked >= 60 and lanes == ({0} if skill == 1 else {0, 2})


def test_no_ramps_on_a_moving_train():
    """A train with ramps stands still; the moving one has rail or its own
    body under it in the descriptors, never a ramp, a stop or a signal."""
    sym, cpc = _boot(2, 6)
    trains = 0
    for _ in range(3000):
        sync_game_frame(cpc, sym)
        train = _train(cpc, sym)
        if not train or train["anchor"] == trains:
            continue
        trains = train["anchor"]
        for row in range(train["lo"] // 8 - 1, (train["hi"] + 7) // 8 + 1):
            if row > peek16(cpc, sym["gen_row"]) or row < peek16(cpc, sym["gen_row"]) - 60:
                continue
            tile = read_desc(cpc, sym, row)["lanes"][train["lane"]]
            assert tile < 2 or sym["tile_wagons"] <= tile < sym["tile_ramps"], (row, tile, train)


def test_oncoming_train_crashes_the_runner():
    """Standing in the right lane in front of an oncoming train ends badly
    (with the scroll stopped only the train moves)."""
    sym = load_symbols()
    cpc = boot_game(collisions=True)
    cpc.write_ram(sym["no_crash"], bytes([1]))
    cpc.write_ram(sym["skill"], bytes([2]))
    cpc.write_ram(sym["scroll_speed"], bytes([5]))
    for _ in range(4000):
        sync_game_frame(cpc, sym)
        train = _train(cpc, sym)
        feet = peek16(cpc, sym["feet_row"]) * 8
        if train and train["lane"] == 2 and train["stop"] < feet and feet + 80 < train["lo"] < feet + 200:
            break
    else:
        raise AssertionError("no oncoming train with the way clear")
    cpc.write_ram(sym["scroll_speed"], bytes([0]))
    cpc.tap_key(cpcmod.KEY_RIGHT)
    cpc.tap_key(cpcmod.KEY_RIGHT)
    for _ in range(10):
        sync_game_frame(cpc, sym)
    assert peek8(cpc, sym["player_lane"]) == 2 and peek8(cpc, sym["crashes"]) == 0
    cpc.write_ram(sym["no_crash"], bytes([0]))
    for frame in range(200):
        sync_game_frame(cpc, sym)
        if peek8(cpc, sym["crashes"]):
            break
    train = _train(cpc, sym)
    print(f"    crash after {frame} frames, the cab at line {train['lo'] - feet} above the feet")
    assert peek8(cpc, sym["crashes"]) == 1 and train["lo"] > feet - 16
