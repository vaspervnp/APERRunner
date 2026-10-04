"""Takes the release screenshots (docs/screenshots/*.png) from the headless
emulator: loading screen, menus, story, controls, the game in the city and
the forest, a power-up, the hard mode countdown, game over and high scores.

    python3 tools/screenshots.py        (after make)
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "tests"))
from harness import ROOT, boot_game, load_symbols, peek8, sync_game_frame  # noqa: E402
import cpc as cpcmod  # noqa: E402

OUT = os.path.join(ROOT, "docs", "screenshots")
MODE_PLAY, MODE_MENU, MODE_CONTROLS, MODE_SCORES, MODE_OVER, MODE_STORY = 0, 2, 3, 4, 5, 6


def shot(cpc, name):
    os.makedirs(OUT, exist_ok=True)
    cpc.screenshot(os.path.join(OUT, name), aspect=True)
    print(f"  {name}")


def frames(cpc, sym, n):
    for _ in range(n):
        sync_game_frame(cpc, sym)


def press(cpc, sym, key):
    cpc.key_down(key)
    frames(cpc, sym, 2)
    cpc.key_up(key)
    frames(cpc, sym, 3)


def screen(cpc, sym, mode, name):
    cpc.write_ram(sym["game_mode"], bytes([mode]))
    cpc.write_ram(sym["screen_dirty"], bytes([1]))
    frames(cpc, sym, 8)
    shot(cpc, name)


def main():
    sym = load_symbols()

    # loading screen: while the loader brings in the banks
    from harness import BOOT_FRAMES, DSK
    from cpc import CPC
    cpc = CPC()
    cpc.run_frames(BOOT_FRAMES)
    cpc.insert_disc(DSK)
    cpc.type_text('RUN"DISC\n')
    cpc.run_frames(300)
    shot(cpc, "01_loading.png")

    cpc = boot_game(menu=True)
    frames(cpc, sym, 6)
    shot(cpc, "02_menu.png")
    screen(cpc, sym, MODE_STORY, "03_story.png")
    screen(cpc, sym, MODE_CONTROLS, "04_controls.png")
    screen(cpc, sym, MODE_SCORES, "05_scores.png")
    screen(cpc, sym, MODE_MENU, "02_menu.png")
    press(cpc, sym, ord("l"))
    frames(cpc, sym, 6)
    shot(cpc, "06_menu_greek.png")
    press(cpc, sym, ord("l"))
    frames(cpc, sym, 6)

    # hard: the wagons hint and the countdown
    cpc.write_ram(sym["skill"], bytes([2]))
    cpc.key_down(cpcmod.KEY_SPACE)
    while peek8(cpc, sym["game_mode"]) != MODE_PLAY:
        sync_game_frame(cpc, sym)
    cpc.key_up(cpcmod.KEY_SPACE)
    while peek8(cpc, sym["countdown"]) > 45:
        sync_game_frame(cpc, sym)
    shot(cpc, "07_hard_countdown.png")

    # the game: a city stretch, a power-up, the forest
    cpc = boot_game(pickups=True)
    frames(cpc, sym, 120)
    shot(cpc, "08_city.png")
    for _ in range(3000):
        sync_game_frame(cpc, sym)
        if peek8(cpc, sym["label_wait"]) == 2:
            frames(cpc, sym, 4)
            shot(cpc, "09_power_up.png")
            break
    for _ in range(4000):
        sync_game_frame(cpc, sym)
        if peek8(cpc, sym["env"]) == 1 and peek8(cpc, sym["trans_left"]) == 0:
            frames(cpc, sym, 60)
            shot(cpc, "10_forest.png")
            break

    # game over with a new record
    cpc.write_ram(sym["no_crash"], bytes([0]))
    cpc.write_ram(sym["lives"], bytes([1]))
    cpc.write_ram(sym["score"], bytes([0x50, 0x47, 0x02]))      # 24750
    for _ in range(3000):
        sync_game_frame(cpc, sym)
        if peek8(cpc, sym["game_mode"]) == MODE_OVER:
            frames(cpc, sym, 10)
            shot(cpc, "11_game_over.png")
            break
    print(f"screenshots -> {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
