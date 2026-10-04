"""Phase 0: the disc boots and the program runs its own main loop."""

from harness import boot_game, load_symbols, peek8, peek16


def test_boot_runs_game_loop():
    sym = load_symbols()
    cpc = boot_game()

    pc = cpc.pc
    assert sym["start"] <= pc < 0x8000, f"PC #{pc:04X} is outside the game code"

    before = peek16(cpc, sym["frame_counter"])
    cpc.run_frames(50)
    elapsed = (peek16(cpc, sym["frame_counter"]) - before) & 0xFFFF
    assert 24 <= elapsed <= 26, f"expected ~25 game frames per second, got {elapsed}"


def test_loader_shows_the_loading_screen():
    """While the banks load, the screen shows the converted picture."""
    import os
    import sys
    from harness import BOOT_FRAMES, DSK, ROOT
    from cpc import CPC
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import scr2cpc

    screen, rows = scr2cpc.convert()
    cpc = CPC()
    cpc.run_frames(BOOT_FRAMES)
    cpc.insert_disc(DSK)
    cpc.type_text('RUN"DISC\n')
    cpc.run_frames(300)                                  # banks loading
    assert 0x8000 <= cpc.pc or cpc.pc < 0x4000, f"PC #{cpc.pc:04X}: still loading"
    used = [a for line in range(rows * 8) for a in range((line & 7) * 0x800 + (line >> 3) * 96,
                                                          (line & 7) * 0x800 + (line >> 3) * 96 + 96)]
    assert all(cpc.read_ram(0xC000 + a, 1)[0] == screen[a] for a in used[::7]), "picture unpacked at &C000"
    cpc.screenshot(os.path.join(ROOT, "build", "test-artifacts", "loading.png"), aspect=True)


def test_run_runner_shows_the_revive8bit_screen_first():
    """RUNNER.BAS: REVIVE8B.SCR with its inks; SPACE (or 10 s) goes on to DISC."""
    import os
    from harness import BOOT_FRAMES, DSK, ROOT
    from cpc import CPC
    import cpc as cpcmod
    with open(os.path.join(ROOT, "assets", "revive8b.scr"), "rb") as f:
        scr = f.read()

    def shown(cpc):
        return all(cpc.read_ram(0xC000 + a, 1)[0] == scr[a] for a in range(0, 16384, 97))

    cpc = CPC()
    cpc.run_frames(BOOT_FRAMES)
    cpc.insert_disc(DSK)
    cpc.type_text('RUN"RUNNER\n')
    cpc.run_frames(300)
    assert shown(cpc), "REVIVE8B.SCR at &C000"
    cpc.run_frames(100)
    assert shown(cpc), "still waiting"
    cpc.key_down(cpcmod.KEY_SPACE)
    cpc.run_frames(10)
    cpc.key_up(cpcmod.KEY_SPACE)
    cpc.run_frames(75)
    assert not shown(cpc), "SPACE: on to the game"


def test_run_runner_starts_the_game_too():
    """RUNNER.BAS on the disc: RUN"RUNNER does RUN"DISC."""
    sym = load_symbols()
    cpc = boot_game(menu=True, command='RUN"RUNNER', max_frames=2500)   # after the 10 s splash
    assert peek8(cpc, sym["game_mode"]) == 2
