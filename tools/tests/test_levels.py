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


def test_wagon_run_becomes_cars_with_coupler():
    chunk = _compile("\n".join(["W1.  ...  ..."] * 9) + "\n")
    tiles = {v: k for k, v in mklevel.TILE.items()}
    column = [tiles[row[0]] for row in chunk["rows"]]
    assert column == ["wagon1_end_bottom", "wagon1_body_a", "wagon1_body_b", "wagon1_end_top", "wagon1_coupler",
                      "wagon1_end_bottom", "wagon1_body_a", "wagon1_body_b", "wagon1_end_top"]
