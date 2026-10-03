"""Phase 0: the disc boots and the program runs its own main loop."""

from harness import boot_game, load_symbols, peek16


def test_boot_runs_game_loop():
    sym = load_symbols()
    cpc = boot_game()

    pc = cpc.pc
    assert sym["start"] <= pc < sym["end_of_code"], f"PC #{pc:04X} is outside the game code"

    before = peek16(cpc, sym["frame_counter"])
    cpc.run_frames(50)
    elapsed = (peek16(cpc, sym["frame_counter"]) - before) & 0xFFFF
    assert 24 <= elapsed <= 26, f"expected ~25 game frames per second, got {elapsed}"
