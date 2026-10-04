"""Phase 3: track chunk compiler (tools/mklevel.py)."""

import os
import sys
import tempfile

from harness import ROOT

sys.path.insert(0, os.path.join(ROOT, "tools"))
import mklevel  # noqa: E402

BLOCKING = {mklevel.COL_STOP, mklevel.COL_SIGNAL, mklevel.COL_TRAIN, mklevel.COL_NOSE}


def test_all_chunks_compile():
    chunks = mklevel.load_all()
    assert len(chunks) >= 10
    assert {c["diff"] for c in chunks} >= {1, 2, 3}


def test_every_row_has_a_ground_lane():
    """At ground level at least one lane is never blocked (fairness)."""
    for chunk in mklevel.load_all():
        for r, row in enumerate(chunk["rows"]):
            classes = [row[lane * 3 + 1] & 15 for lane in range(3)]
            assert not all(c in BLOCKING for c in classes), f"{chunk['name']} row {r}: all lanes blocked"


def _train_runs(chunk):
    """[(lane, [tile names bottom to top])] for every train in a chunk."""
    names = {v: k for k, v in mklevel.TILE.items()}
    runs = []
    for lane in range(3):
        current = []
        for row in chunk["rows"] + [[0] * 9]:
            name = names[row[lane * 3]]
            if name.startswith(("wagon", "loco")):
                current.append(name)
            elif current:
                runs.append((lane, current))
                current = []
    return runs


def test_every_train_has_a_locomotive_and_two_long_wagons():
    trains = 0
    for chunk in mklevel.load_all():
        for lane, run in _train_runs(chunk):
            trains += 1
            cabs = [n for n in run if n.endswith(("nose", "nose_top"))]
            couplers = [n for n in run if n.endswith("coupler")]
            assert len(cabs) == 1, f"{chunk['name']} lane {lane}: {len(cabs)} locomotives"
            assert len(couplers) >= 2, f"{chunk['name']} lane {lane}: {len(couplers)} wagons"
            assert len(run) >= mklevel.train_length(2)
    assert trains >= 8


def test_trains_are_built_from_cars():
    tiles = {v: k for k, v in mklevel.TILE.items()}
    for chunk in mklevel.load_all():
        for lane in range(3):
            column = [tiles[row[lane * 3]] for row in chunk["rows"]]
            for below, above in zip(column, column[1:]):
                if above.endswith("end_bottom"):
                    assert not ("body" in below or below.endswith("end_bottom")), f"{chunk['name']}: {below} under {above}"
                if below.endswith("end_top") and above.startswith(("wagon", "loco")) and not above.endswith("coupler"):
                    assert False, f"{chunk['name']}: {above} on top of end_top"


def _compile(text):
    path = os.path.join(tempfile.mkdtemp(), "x.txt")
    with open(path, "w") as f:
        f.write(text)
    return mklevel.compile_chunk(path)


def test_ramp_without_train_is_rejected():
    try:
        _compile("...  ...  ...\n^..  ...  ...\n^..  ...  ...\n^..  ...  ...\n")
    except mklevel.LevelError as e:
        assert "ramp" in str(e)
    else:
        raise AssertionError("accepted")


def test_train_with_cab_first_layout():
    chunk = _compile("\n".join(["T1.  ...  ..."] * 38) + "\n")
    tiles = {v: k for k, v in mklevel.TILE.items()}
    column = [tiles[row[0]] for row in chunk["rows"]]
    assert column[0] == "loco1_nose" and column[11] == "wagon1_end_top"
    assert column[12] == "wagon1_coupler" and column[13] == "wagon1_end_bottom" and column[24] == "wagon1_end_top"
    assert column[25] == "wagon1_coupler" and column[37] == "wagon1_end_top"
    assert chunk["rows"][0][1] == mklevel.COL_NOSE and chunk["rows"][1][1] == mklevel.COL_TRAIN


def test_train_with_cab_last_layout():
    chunk = _compile("\n".join(["R2.  ...  ..."] * 51) + "\n")
    tiles = {v: k for k, v in mklevel.TILE.items()}
    column = [tiles[row[0]] for row in chunk["rows"]]
    assert column[0] == "wagon2_end_bottom" and column[12] == "wagon2_coupler"
    assert column[38] == "wagon2_coupler" and column[39] == "wagon2_end_bottom" and column[50] == "loco2_nose_top"
    couplers = {12, 25, 38}                      # a gap between wagons (hard mode)
    assert all(row[1] == (mklevel.COL_GAP if r in couplers else mklevel.COL_TRAIN)
               for r, row in enumerate(chunk["rows"]))


def _train_with_coins(rows):
    """51-row train in lane 1 with coins on the given rows (bottom first)."""
    return "\n".join("R2c  ...  ..." if r in rows else "R2.  ...  ..." for r in reversed(range(51))) + "\n"


def test_no_coins_between_wagons():
    _compile(_train_with_coins({14, 16, 18}))
    try:
        _compile(_train_with_coins({23, 25, 27}))               # row 25: a coupler
    except mklevel.LevelError as e:
        assert "between two wagons" in str(e)
    else:
        raise AssertionError("accepted a coin on a coupler")
    for chunk in mklevel.load_all():
        for row in chunk["rows"]:
            for lane in range(3):
                assert not (row[lane * 3 + 1] == mklevel.COL_GAP and row[lane * 3 + 2] == mklevel.ITEMS["c"]), chunk["name"]


def test_short_or_odd_trains_are_rejected():
    for length in (12, 25, 37, 40):
        try:
            _compile("\n".join(["T1.  ...  ..."] * length) + "\n")
        except mklevel.LevelError as e:
            assert "locomotive and at least 2 wagons" in str(e)
        else:
            raise AssertionError(f"a {length}-row train was accepted")


def test_coins_are_in_one_lane_per_row():
    coin = mklevel.ITEMS["c"]
    for chunk in mklevel.load_all():
        for r, row in enumerate(chunk["rows"]):
            lanes = [lane for lane in range(3) if row[lane * 3 + 2] == coin]
            assert len(lanes) <= 1, f"{chunk['name']}: row {r} has coins in lanes {lanes}"


def _coins(n, lane=0, gap=1):
    """n coins in a lane, `gap` empty rows between them."""
    cell = ["...  ...  ...", "...  ...  ...", "...  ...  ..."]
    coin = ["..c  ...  ...", "...  ..c  ...", "...  ...  ..c"][lane]
    return ((coin + "\n") + (cell[lane] + "\n") * gap) * (n - 1) + coin + "\n"


def test_coins_side_by_side_are_rejected():
    _compile(_coins(3, 0) + "...  ...  ...\n" + _coins(3, 1))   # zig-zag across rows is fine
    for line in ("..c  ..c  ...", "...  ..c  ..c", "..c  ...  ..c", "..c  ..c  ..c"):
        try:
            _compile((line + "\n...  ...  ...\n") * 3)
        except mklevel.LevelError as e:
            assert "one lane only" in str(e)
        else:
            raise AssertionError(f"accepted {line!r}")


def test_more_coins_on_screen():
    # one and a half times the earlier density (~6 coins on the 34 rows of
    # the screen, weighted by chunk probability): ~9 now
    chunks = mklevel.load_all()
    coin = mklevel.ITEMS["c"]
    coins = sum(c["weight"] * sum(1 for row in c["rows"] for lane in range(3) if row[lane * 3 + 2] == coin)
                for c in chunks)
    rows = sum(c["weight"] * len(c["rows"]) for c in chunks)
    on_screen = 34 * coins / rows
    print(f"    {on_screen:.1f} coins on screen on average")
    assert 8.5 <= on_screen <= 10.5, on_screen


def test_coins_come_in_runs_of_three_to_ten_with_gaps():
    coin = mklevel.ITEMS["c"]
    for chunk in mklevel.load_all():
        for lane in range(3):
            column = [row[lane * 3 + 2] == coin for row in chunk["rows"]]
            for r in range(len(column) - 1):
                assert not (column[r] and column[r + 1]), f"{chunk['name']}: lane {lane + 1}: coins on rows {r}, {r + 1}"
            for start, count in mklevel.coin_runs(column):
                assert 3 <= count <= 10, f"{chunk['name']}: lane {lane + 1}: run of {count} from row {start}"


def test_bad_coin_runs_are_rejected():
    _compile(_coins(3))
    _compile(_coins(10))
    _compile(_coins(3) + "...  ...  ...\n" * 2 + _coins(3))     # two runs
    for text, error in ((_coins(1), "runs of 3 to 10"), (_coins(2), "runs of 3 to 10"),
                        (_coins(11), "runs of 3 to 10"), (_coins(3, gap=0), "consecutive rows")):
        try:
            _compile(text)
        except mklevel.LevelError as e:
            assert error in str(e), str(e)
        else:
            raise AssertionError(f"accepted {text!r}")


def _ramp_chunk(kind, roof_coins, ground_coins, stops):
    """Lane 2: ramp + 38-row train; lane 1 coins on the ground, lane 3 stops."""
    rows = []                                   # bottom first
    for r in range(3 + 38):
        obj = "^.." if r < 3 else "R1."
        if r in (4, 6, 8, 10, 17, 19, 21, 23)[:roof_coins]:   # on the wagon roofs
            obj = "R1c"
        left = "..c" if r in (30, 32, 34, 36)[:ground_coins] else "..."
        right = "S.." if (r - 2) % 10 in (0, 1) and stops and r >= 2 else "..."
        if stops and (r - 7) % 10 in (0, 1) and r >= 7:
            left = "S.."
        rows.append(f"{left}  {obj}  {right}")
    return f"# ramp: {kind}\n" + "\n".join(reversed(rows)) + "\n"


def test_ramp_chunks_say_how_they_reward_the_ramp():
    for text, error in ((_ramp_chunk("coins", 0, 3, False).replace("# ramp: coins\n", ""), "needs 'ramp: coins'"),
                        (_ramp_chunk("coins", 4, 4, False), "of the coins on the train roofs"),
                        (_ramp_chunk("blocked", 0, 0, False), "a buffer stop every 12 rows")):
        try:
            _compile(text)
        except mklevel.LevelError as e:
            assert error in str(e), str(e)
        else:
            raise AssertionError(f"accepted: {error}")
    assert _compile(_ramp_chunk("coins", 8, 3, False))["ramp"] == "coins"
    assert _compile(_ramp_chunk("blocked", 0, 0, True))["ramp"] == "blocked"


def test_ramps_bring_coins_a_third_of_the_time():
    chunks = mklevel.load_all()
    ramps = [c for c in chunks if c["ramp"]]
    assert ramps
    for env in mklevel.ENVS.values():
        for diff in range(1, 6):
            group = [c for c in ramps if c["env"] == env and c["diff"] == diff]
            total = sum(c["weight"] for c in group)
            coins = sum(c["weight"] for c in group if c["ramp"] == "coins")
            assert 3 * coins == total, (env, diff, [c["name"] for c in group])


def test_chunks_hold_no_power_ups():
    for chunk in mklevel.load_all():
        assert all(row[lane * 3 + 2] <= 1 for row in chunk["rows"] for lane in range(3)), chunk["name"]
    try:
        _compile("..M  ...  ...\n...  ...  ...\n")
    except mklevel.LevelError as e:
        assert "places the power-ups" in str(e)
    else:
        raise AssertionError("accepted a power-up in a chunk")
