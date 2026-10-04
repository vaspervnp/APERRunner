"""Phase 8.6: the high score table is saved to the disc (sector #C5 of
track 0: the SCORES file) and read back at the next start."""

import os
import tempfile

from harness import DSK, boot_game, load_symbols, peek8, sync_game_frame
import cpc as cpcmod  # noqa: E402  (path set up by harness)
import test_collisions as tc
import test_screens as ts

SECTOR = 0xC5


def _first_entry(cpc, sym):
    lo, mid, hi, a, b, c = cpc.read_ram(sym["hiscore_table"], 6)
    return f"{hi:02X}{mid:02X}{lo:02X}", "".join(chr(65 + x) for x in (a, b, c))


def test_scores_file_is_the_first_record_on_the_disc():
    data = open(DSK, "rb").read()
    entry = data[0x200:0x200 + 32]                  # first directory entry (sector #C1)
    assert entry[1:9] == b"SCORES  " and entry[16] == 2, entry     # block 2 = sector #C5
    cpc = cpcmod.CPC()
    cpc.insert_disc(DSK)
    assert cpc.disc_sector(0, SECTOR)[:4] == b"APR0", "nothing saved yet"


def test_a_new_record_is_saved_and_loaded_again():
    sc = tc.Scenario()
    cpc, sym = sc.cpc, sc.sym
    cpc.write_ram(sym["score"], bytes([0x00, 0x00, 0x13]))   # 130000: first place
    cpc.write_ram(sym["lives"], bytes([1]))
    sc.plant_lane(0, 1, tc.stop())
    sc.go()
    for _ in range(300):
        sync_game_frame(cpc, sym)
        if ts.mode(cpc, sym) == ts.MODE_OVER:
            break
    ts.frames(cpc, sym, 3)
    ts.press(cpc, sym, cpcmod.KEY_UP)                       # B
    for _ in range(3):
        ts.press(cpc, sym, cpcmod.KEY_SPACE)                # B A A
    ts.frames(cpc, sym, 40)                                  # motor, write
    record = _first_entry(cpc, sym)
    assert record[1] == "BAA" and int(record[0]) >= 130000, record
    sector = cpc.disc_sector(0, SECTOR)
    table = cpc.read_ram(sym["hiscore_table"], 48)
    assert sector[:4] == b"APER" and sector[4:52] == table and set(sector[52:]) == {0x1A}
    assert peek8(cpc, sym["missed_frames"]) < 4, "the save holds the game only briefly"

    # a new start from that disc has the record
    path = os.path.join(tempfile.mkdtemp(), "saved.dsk")
    with open(path, "wb") as f:
        f.write(cpc.disc_image())
    sym = load_symbols()
    again = boot_game(menu=True, disc=path)
    assert _first_entry(again, sym) == record
