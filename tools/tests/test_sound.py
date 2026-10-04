"""Phase 9: music and sound effects on the AY, from the VSYNC interrupt.

The AY registers are read from the emulator's sound chip.
"""

import os
import sys
import tempfile

from harness import ROOT, boot_game, load_symbols, peek8, sync_frame, sync_game_frame
import cpc as cpcmod  # noqa: E402  (path set up by harness)
import test_collisions as tc

sys.path.insert(0, os.path.join(ROOT, "tools"))
import mkmusic  # noqa: E402

NOISE_C_OFF = 0x20                       # mixer bit: 1 = no noise on channel C


def period(regs, channel):
    return regs[2 * channel] | regs[2 * channel + 1] << 8


def note_period(name):
    return mkmusic.periods()[mkmusic.note_index(name) - 1]


def sample(cpc, sym, frames):
    """AY registers at every VSYNC frame (50 a second)."""
    out = []
    for _ in range(frames):
        sync_frame(cpc, sym)
        out.append(cpc.psg_regs())
    return out


def test_menu_music_plays_and_moves_at_50_hz():
    sym = load_symbols()
    cpc = boot_game(menu=True)
    regs = sample(cpc, sym, 200)
    melody = {period(r, 0) for r in regs if r[8]}
    bass = {period(r, 1) for r in regs if r[9]}
    assert len(melody) >= 5 and len(bass) >= 3, (melody, bass)
    # a note decays one volume step per 1/50 s: three falling steps in a row
    vols = [r[8] for r in regs]
    assert any(vols[i] > vols[i + 1] > vols[i + 2] > vols[i + 3] for i in range(len(vols) - 3))
    assert all(r[7] & 0x40 == 0 for r in regs), "AY port A stays an input (keyboard)"


def test_game_has_its_own_tune():
    sym = load_symbols()
    menu = {period(r, 0) for r in sample(boot_game(menu=True), sym, 300) if r[8]}
    game = {period(r, 0) for r in sample(boot_game(), sym, 300) if r[8]}
    assert game and game != menu
    assert note_period("G#4") in game or note_period("G#5") in game, "the game tune (A hijaz)"


def test_sound_off_and_pause_are_silent():
    sym = load_symbols()
    cpc = boot_game(menu=True)
    cpc.write_ram(sym["sound_on"], bytes([0]))
    for r in sample(cpc, sym, 20)[2:]:
        assert r[8] == r[9] == r[10] == 0
    cpc.write_ram(sym["sound_on"], bytes([1]))
    assert any(r[8] for r in sample(cpc, sym, 50))
    cpc.write_ram(sym["paused"], bytes([1]))
    for r in sample(cpc, sym, 20)[2:]:
        assert r[8] == r[9] == r[10] == 0


def _effect(sc, until, frames=200):
    """AY registers from now until `until(state)`, then 10 frames more."""
    regs = []
    for _ in range(frames):
        st = sc.frame()
        regs.append(sc.cpc.psg_regs())
        if until(st):
            break
    else:
        raise AssertionError("never happened")
    for _ in range(10):
        sync_frame(sc.cpc, sc.sym)
        regs.append(sc.cpc.psg_regs())
    return regs


def test_coin_plays_its_effect_on_channel_c():
    sc = tc.Scenario(pickups=True)
    sc.plant_item(3, 1, 1)
    sc.go()
    regs = _effect(sc, lambda st: peek8(sc.cpc, sc.sym["coins"]) > 0)
    tones = {period(r, 2) for r in regs if r[10]}
    assert note_period("E6") in tones, tones


def test_crash_plays_noise():
    sc = tc.Scenario()
    sc.plant_lane(0, 1, tc.stop())
    sc.go()
    regs = _effect(sc, lambda st: st["crashes"] > 0)
    assert any(r[7] & NOISE_C_OFF == 0 and r[10] for r in regs), "noise on channel C"


def test_jump_plays_its_effect():
    sym = load_symbols()
    cpc = boot_game()
    sample(cpc, sym, 4)
    cpc.write_ram(sym["sfx_request"], bytes([0]))
    cpc.key_down(cpcmod.KEY_SPACE)
    regs = sample(cpc, sym, 6)
    cpc.key_up(cpcmod.KEY_SPACE)
    assert any(period(r, 2) == note_period("C4") and r[10] for r in regs)


def test_higher_priority_effect_is_not_cut():
    sym = load_symbols()
    cpc = boot_game()
    sync_game_frame(cpc, sym)
    cpc.write_ram(sym["sfx_request"], bytes([5]))      # crash (3)
    sample(cpc, sym, 2)
    cpc.write_ram(sym["sfx_request"], bytes([1]))      # coin (1): ignored
    regs = sample(cpc, sym, 3)
    assert all(r[7] & NOISE_C_OFF == 0 for r in regs), "the crash goes on"


def test_music_tool():
    assert note_period("A4") == round(1_000_000 / (16 * 440))
    tunes, effects = mkmusic.load_all()
    assert {t["name"] for t in tunes} == {"game", "menu", "over"}
    assert {e["name"] for e in effects} >= {"coin", "jump", "powerup", "crash", "signal"}
    for t in tunes:                         # whole bars of 4 quarters per channel
        for ch, events in t["streams"].items():
            assert sum(d for _, d in events) % (4 * t["quarter"]) == 0, (t["name"], ch)
    for text in ("A: H4/4\n", "A: A9/4\n", "A: A4/3\n", "A: A4/16\n", "C: A4/4\n"):
        path = os.path.join(tempfile.mkdtemp(), "x.txt")
        with open(path, "w") as f:
            f.write("# tune: x\n# quarter: 6\n" + text)
        try:
            mkmusic.load_tune(path)
        except mkmusic.MusicError:
            pass
        else:
            raise AssertionError(f"accepted {text!r}")
