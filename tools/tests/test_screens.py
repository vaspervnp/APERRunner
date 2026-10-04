"""Phase 8: menu, controls, high scores, game over and name entry, demo, ESC,
pause, languages."""

import os
import sys

from harness import IMAGE_Y, ROOT, boot_game, load_symbols, peek8, peek16, save_screenshot, start_from_menu, sync_game_frame
import cpc as cpcmod  # noqa: E402  (path set up by harness)
import test_collisions as tc

sys.path.insert(0, os.path.join(ROOT, "tools"))
import mktext  # noqa: E402

MODE_PLAY, MODE_DEMO, MODE_MENU, MODE_CONTROLS, MODE_SCORES, MODE_OVER, MODE_STORY = range(7)
WHITE = (255, 255, 255)


def mode(cpc, sym):
    return peek8(cpc, sym["game_mode"])


def frames(cpc, sym, n):
    for _ in range(n):
        sync_game_frame(cpc, sym)


def press(cpc, sym, key, hold=2):
    cpc.key_down(key)
    frames(cpc, sym, hold)
    cpc.key_up(key)
    frames(cpc, sym, 3)


def white_lines(img, x0, x1):
    """Image lines with white (text) pixels between framebuffer x0 and x1."""
    return [y for y in range(img.height)
            if any(min(img.getpixel((x, y))) > 200 for x in range(x0, x1, 4))]


def hiscores(cpc, sym):
    out = []
    for k in range(8):
        lo, mid, hi, a, b, c = cpc.read_ram(sym["hiscore_table"] + 6 * k, 6)
        out.append((f"{hi:02X}{mid:02X}{lo:02X}", "".join(chr(65 + x) for x in (a, b, c))))
    return out


def test_menu_navigation_and_screens():
    sym = load_symbols()
    cpc = boot_game(menu=True)
    frames(cpc, sym, 4)
    assert mode(cpc, sym) == MODE_MENU
    save_screenshot(cpc, "menu.png")
    press(cpc, sym, cpcmod.KEY_DOWN)
    assert peek8(cpc, sym["menu_sel"]) == 1
    press(cpc, sym, cpcmod.KEY_SPACE)
    assert mode(cpc, sym) == MODE_CONTROLS
    img = sync_game_frame(cpc, sym)
    save_screenshot(cpc, "controls.png")
    assert len(white_lines(img, 0, 576)) > 50, "the controls are written"
    press(cpc, sym, cpcmod.KEY_SPACE)
    assert mode(cpc, sym) == MODE_MENU
    press(cpc, sym, cpcmod.KEY_DOWN)
    press(cpc, sym, cpcmod.KEY_SPACE)
    assert mode(cpc, sym) == MODE_SCORES
    save_screenshot(cpc, "scores.png")
    press(cpc, sym, cpcmod.KEY_ESC)
    assert mode(cpc, sym) == MODE_MENU
    press(cpc, sym, cpcmod.KEY_DOWN)                     # the story
    press(cpc, sym, cpcmod.KEY_SPACE)
    assert mode(cpc, sym) == MODE_STORY
    img = sync_game_frame(cpc, sym)
    save_screenshot(cpc, "story.png")
    assert len(white_lines(img, 0, 576)) > 100, "the story is written"
    press(cpc, sym, cpcmod.KEY_ESC)
    assert mode(cpc, sym) == MODE_MENU
    press(cpc, sym, cpcmod.KEY_DOWN)                     # sound on/off
    sound = peek8(cpc, sym["sound_on"])
    press(cpc, sym, cpcmod.KEY_SPACE)
    assert peek8(cpc, sym["sound_on"]) == sound ^ 1
    for _ in range(4):
        press(cpc, sym, cpcmod.KEY_UP)
    assert peek8(cpc, sym["menu_sel"]) == 0
    press(cpc, sym, cpcmod.KEY_SPACE)
    assert mode(cpc, sym) == MODE_PLAY
    frames(cpc, sym, 10)
    assert peek8(cpc, sym["missed_frames"]) == 0


def test_esc_goes_back_to_the_menu_and_pause_shows_a_label():
    sym = load_symbols()
    cpc = boot_game()
    press(cpc, sym, ord("h"))
    assert peek8(cpc, sym["paused"]) == 1
    img = sync_game_frame(cpc, sym)
    label = white_lines(img, 608, 724)
    assert any(200 + IMAGE_Y <= y < 208 + IMAGE_Y for y in label), "ΠΑΥΣΗ in the HUD panel"
    press(cpc, sym, ord("h"))
    assert peek8(cpc, sym["paused"]) == 0
    img = sync_game_frame(cpc, sym)
    assert not any(200 + IMAGE_Y <= y < 208 + IMAGE_Y for y in white_lines(img, 608, 724)), "label erased"
    press(cpc, sym, cpcmod.KEY_ESC)
    assert mode(cpc, sym) == MODE_MENU


def test_demo_starts_by_itself_and_stops_with_a_key():
    sym = load_symbols()
    cpc = boot_game(menu=True)
    for _ in range(450):                                 # 16 s of menu
        sync_game_frame(cpc, sym)
        if mode(cpc, sym) == MODE_DEMO:
            break
    assert mode(cpc, sym) == MODE_DEMO
    top = peek16(cpc, sym["scr_top_row"])
    lanes = set()
    for _ in range(150):
        sync_game_frame(cpc, sym)
        lanes.add(peek8(cpc, sym["player_lane"]))
        if mode(cpc, sym) != MODE_DEMO:
            break
    save_screenshot(cpc, "demo.png")
    assert peek16(cpc, sym["scr_top_row"]) > top + 20, "the demo runs"
    press(cpc, sym, cpcmod.KEY_SPACE)
    assert mode(cpc, sym) == MODE_MENU


def test_new_record_takes_a_name():
    sc = tc.Scenario()
    cpc, sym = sc.cpc, sc.sym
    cpc.write_ram(sym["score"], bytes([0x00, 0x00, 0x13]))  # 130000: first place
    cpc.write_ram(sym["lives"], bytes([1]))
    sc.plant_lane(0, 1, tc.stop())
    sc.go()
    for _ in range(300):
        sync_game_frame(cpc, sym)
        if mode(cpc, sym) == MODE_OVER:
            break
    assert mode(cpc, sym) == MODE_OVER
    frames(cpc, sym, 3)
    assert peek8(cpc, sym["over_rank"]) == 0
    save_screenshot(cpc, "game_over.png")
    press(cpc, sym, cpcmod.KEY_DOWN)                    # A -> Z
    press(cpc, sym, cpcmod.KEY_SPACE)
    press(cpc, sym, cpcmod.KEY_UP)                      # A -> B
    press(cpc, sym, cpcmod.KEY_SPACE)
    press(cpc, sym, cpcmod.KEY_SPACE)                   # A
    table = hiscores(cpc, sym)
    assert table[0][1] == "ZBA" and int(table[0][0]) >= 130000, table
    assert table[1] == ("020000", "APE") and len(table) == 8
    press(cpc, sym, cpcmod.KEY_SPACE)
    assert mode(cpc, sym) == MODE_SCORES
    save_screenshot(cpc, "scores_new.png")
    press(cpc, sym, cpcmod.KEY_SPACE)
    assert mode(cpc, sym) == MODE_MENU


def test_language_files_have_the_same_texts():
    languages = mktext.load_all()
    assert list(languages) == ["en", "el"], "English is the default (language 0)"
    assert list(languages["en"]) == list(languages["el"])


def test_english_by_default_and_l_switches_the_language():
    sym = load_symbols()
    cpc = boot_game(menu=True)
    frames(cpc, sym, 4)
    assert peek8(cpc, sym["language"]) == 0
    cpc.write_ram(sym["menu_idle"], bytes([0, 0]))
    english = cpc.read_ram(sym["text_ptrs"], 2 * len(mktext.load_all()["en"]))
    before = sync_game_frame(cpc, sym).crop((0, 100, 576, 230)).tobytes()
    press(cpc, sym, ord("l"))
    frames(cpc, sym, 2)
    assert peek8(cpc, sym["language"]) == 1
    greek = cpc.read_ram(sym["text_ptrs"], len(english))
    assert greek != english
    img = sync_game_frame(cpc, sym)
    save_screenshot(cpc, "menu_el.png")
    assert img.crop((0, 100, 576, 230)).tobytes() != before, "the menu is drawn again in Greek"
    assert mode(cpc, sym) == MODE_MENU
    press(cpc, sym, ord("l"))
    assert peek8(cpc, sym["language"]) == 0
    assert cpc.read_ram(sym["text_ptrs"], len(english)) == english


def test_menu_after_a_game_has_no_track_left_at_the_top():
    """The fine scroll shows j picture lines above screen line 0: the menu
    clears them too."""
    sym = load_symbols()
    for frames_played in (30, 31):                       # j = 4 and j = 0
        cpc = boot_game()
        frames(cpc, sym, frames_played)
        press(cpc, sym, cpcmod.KEY_ESC)
        img = sync_game_frame(cpc, sym)
        assert mode(cpc, sym) == MODE_MENU
        top = [(x, y) for y in range(0, 16) for x in range(0, 576, 4) if max(img.getpixel((x, y))) > 40]
        assert not top, f"track left on the menu at {top[:3]}"


def test_story_in_greek():
    sym = load_symbols()
    cpc = boot_game(menu=True)
    frames(cpc, sym, 4)
    press(cpc, sym, ord("l"))
    for _ in range(3):
        press(cpc, sym, cpcmod.KEY_DOWN)
    press(cpc, sym, cpcmod.KEY_SPACE)
    assert mode(cpc, sym) == MODE_STORY
    sync_game_frame(cpc, sym)
    save_screenshot(cpc, "story_el.png")
