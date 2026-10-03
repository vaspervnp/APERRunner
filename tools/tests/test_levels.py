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
    assert all(row[1] == mklevel.COL_TRAIN for row in chunk["rows"])


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


def test_coins_side_by_side_are_rejected():
    _compile("..c  ...  ...\n" * 3 + "...  ..c  ...\n" * 3)   # zig-zag across rows is fine
    for line in ("..c  ..c  ...", "...  ..c  ..c", "..c  ...  ..c", "..c  ..c  ..c"):
        try:
            _compile((line + "\n") * 3)
        except mklevel.LevelError as e:
            assert "one lane only" in str(e)
        else:
            raise AssertionError(f"accepted {line!r}")


def test_coins_are_sparse():
    # 40% fewer coins than the original layouts (0.40 per row): at most 0.24 per row overall
    chunks = mklevel.load_all()
    coins = sum(1 for c in chunks for row in c["rows"] for lane in range(3) if row[lane * 3 + 2] == mklevel.ITEMS["c"])
    rows = sum(len(c["rows"]) for c in chunks)
    assert coins <= 0.24 * rows, f"{coins} coins in {rows} rows"


def test_coins_come_in_runs_of_three_or_more():
    coin = mklevel.ITEMS["c"]
    for chunk in mklevel.load_all():
        for lane in range(3):
            column = [row[lane * 3 + 2] == coin for row in chunk["rows"]] + [False]
            run = 0
            for r, has in enumerate(column):
                if has:
                    run += 1
                    continue
                assert run == 0 or run >= 3, f"{chunk['name']}: lane {lane + 1}: run of {run} ending at row {r}"
                run = 0


def test_short_coin_runs_are_rejected():
    _compile("..c  ...  ...\n..c  ...  ...\n..c  ...  ...\n")
    for text in ("..c  ...  ...\n", "..c  ...  ...\n..c  ...  ...\n...  ...  ...\n"):
        try:
            _compile(text)
        except mklevel.LevelError as e:
            assert "runs of at least 3" in str(e)
        else:
            raise AssertionError(f"accepted {text!r}")
