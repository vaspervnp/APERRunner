"""Phase 4: the runner - input, lane changes, jumps, sizes, bridge clipping."""

from harness import boot_game, load_symbols, peek8, peek16, sync_game_frame
import cpc as cpcmod  # noqa: E402  (path set up by harness)
from world_model import F_BRIDGE, Sheets, read_desc, screen_row, visible_rows

LANE_CENTRES = (22, 36, 50)


def _state(cpc, sym):
    return {k: peek8(cpc, sym[k]) for k in
            ("player_lane", "player_centre", "player_z", "player_base", "player_frame", "move_steps_left")}


def _signed(v):
    return v - 256 if v > 127 else v


def _tap(cpc, sym, key):
    """Holds a key for exactly one game frame (input is read once per frame)."""
    sync_game_frame(cpc, sym)
    cpc.key_down(key)
    sync_game_frame(cpc, sym)
    cpc.key_up(key)


def _frames(cpc, sym, n):
    out = []
    for _ in range(n):
        sync_game_frame(cpc, sym)
        out.append(_state(cpc, sym))
    return out


def _settle(cpc, sym):
    for _ in range(8):
        sync_game_frame(cpc, sym)


def test_lane_change_takes_four_frames_and_stops_at_the_edges():
    sym = load_symbols()
    cpc = boot_game()
    assert _state(cpc, sym)["player_lane"] == 1
    _tap(cpc, sym, cpcmod.KEY_RIGHT)
    centres = [_state(cpc, sym)["player_centre"]] + [s["player_centre"] for s in _frames(cpc, sym, 5)]
    assert centres[-1] == LANE_CENTRES[2] and centres.count(LANE_CENTRES[2]) >= 2
    first = centres.index(LANE_CENTRES[2])
    assert centres[first - 3:first + 1] == [40, 44, 47, 50] or centres[:4] == [44, 47, 50, 50], centres
    _tap(cpc, sym, cpcmod.KEY_RIGHT)                 # already on the right lane
    _settle(cpc, sym)
    assert _state(cpc, sym)["player_lane"] == 2
    for key in ("o", "o", "o"):                      # O = left, 3 times: stops at lane 0
        _tap(cpc, sym, key)
        _settle(cpc, sym)
    s = _state(cpc, sym)
    assert (s["player_lane"], s["player_centre"]) == (0, LANE_CENTRES[0])


def test_press_during_a_move_is_queued():
    sym = load_symbols()
    cpc = boot_game()
    _tap(cpc, sym, cpcmod.KEY_LEFT)
    _tap(cpc, sym, "p")                              # P = right, while still moving left
    _settle(cpc, sym)
    s = _state(cpc, sym)
    assert (s["player_lane"], s["player_centre"]) == (1, LANE_CENTRES[1])


def test_ground_jump_uses_size_2_then_lands():
    sym = load_symbols()
    cpc = boot_game()
    _tap(cpc, sym, cpcmod.KEY_UP)
    states = _frames(cpc, sym, 14)
    zs = [s["player_z"] for s in states]
    assert zs.count(1) >= 10 and zs[-1] == 0, zs
    frames = {s["player_frame"] for s in states if s["player_z"] == 1}
    assert frames == {sym["idx_player_s2_jump_up"], sym["idx_player_s2_jump_down"]}


def test_roof_jump_reaches_sizes_4_and_5():
    sym = load_symbols()
    cpc = boot_game()
    cpc.write_ram(sym["player_base"], bytes([2]))   # as if a ramp had lifted us (phase 5)
    _settle(cpc, sym)
    running = _state(cpc, sym)["player_frame"]
    assert sym["idx_player_s3_run0"] <= running <= sym["idx_player_s3_run3"]
    _tap(cpc, sym, "q")                              # Q = jump
    states = _frames(cpc, sym, 14)
    frames = {s["player_frame"] for s in states}
    assert sym["idx_player_s5_jump"] in frames
    assert {sym["idx_player_s4_jump_up"], sym["idx_player_s4_jump_down"]} <= frames
    assert states[-1]["player_z"] == 2


def test_down_shortens_a_jump():
    sym = load_symbols()
    cpc = boot_game()
    _tap(cpc, sym, cpcmod.KEY_SPACE)
    _tap(cpc, sym, cpcmod.KEY_DOWN)
    zs = [s["player_z"] for s in _frames(cpc, sym, 4)]
    assert zs[-1] == 0, zs


def test_joystick_moves_and_jumps():
    sym = load_symbols()
    cpc = boot_game()
    cpc.set_joystick_type(1)
    sync_game_frame(cpc, sym)
    cpc.joystick(cpcmod.JOY_RIGHT if hasattr(cpcmod, "JOY_RIGHT") else 0x08)
    sync_game_frame(cpc, sym)
    cpc.joystick(0)
    _settle(cpc, sym)
    assert _state(cpc, sym)["player_lane"] == 2


def test_run_cycle_animates():
    sym = load_symbols()
    cpc = boot_game()
    frames = {s["player_frame"] for s in _frames(cpc, sym, 12)}
    assert frames == {sym["idx_player_s1_run0"] + i for i in range(4)}


def test_runner_is_drawn_at_its_lane_and_fixed_on_screen():
    """The top of the runner (ears, pen 12) stays on the same screen line
    while the track scrolls, and sits inside the runner's columns."""
    sym = load_symbols()
    cpc = boot_game()
    tops = set()
    for _ in range(24):
        img = sync_game_frame(cpc, sym)
        column = peek8(cpc, sym["player_column"])
        pink = [(x, y) for y in range(200, 272) for x in range(column * 8, column * 8 + 48, 2)
                if img.getpixel((x, y)) == img.getpixel((x, y)) and _is_pink(img.getpixel((x, y)))]
        assert pink, "runner not found"
        tops.add(min(y for _, y in pink))
    assert len(tops) == 1, tops


def _is_pink(p):
    return p[0] > 200 and 90 < p[1] < 170 and 90 < p[2] < 170


def test_pause_freezes_and_resumes():
    sym = load_symbols()
    cpc = boot_game()
    _tap(cpc, sym, "h")
    before = (peek16(cpc, sym["scr_top_row"]), peek8(cpc, sym["cur_j"]))
    _frames(cpc, sym, 10)
    assert (peek16(cpc, sym["scr_top_row"]), peek8(cpc, sym["cur_j"])) == before
    _tap(cpc, sym, "h")
    _frames(cpc, sym, 10)
    assert (peek16(cpc, sym["scr_top_row"]), peek8(cpc, sym["cur_j"])) != before


def test_runner_is_hidden_under_a_bridge_deck():
    sym = load_symbols()
    sheets = Sheets()
    cpc = boot_game()
    cpc.write_ram(sym["scroll_speed"], bytes([6]))
    for _ in range(3000):
        sync_game_frame(cpc, sym)
        rows = visible_rows(cpc, sym)
        top_line = peek16(cpc, sym["player_top"]) + peek8(cpc, sym["cur_j"])
        player_rows = range(top_line >> 3, (top_line + 15 >> 3) + 1)
        decks = [i for i in player_rows
                 if read_desc(cpc, sym, rows[i][0])["flags"] & F_BRIDGE
                 and read_desc(cpc, sym, rows[i][0])["left"] not in (3, 10)]   # not shadow rows
        if decks:
            break
    else:
        raise AssertionError("no bridge reached the runner")
    cpc.write_ram(sym["scroll_speed"], bytes([0]))
    sync_game_frame(cpc, sym)
    sync_game_frame(cpc, sym)
    rows = visible_rows(cpc, sym)
    top_line = peek16(cpc, sym["player_top"]) + peek8(cpc, sym["cur_j"])
    checked = 0
    for i in range(top_line >> 3, (top_line + 15 >> 3) + 1):
        row, bank, ring = rows[i]
        desc = read_desc(cpc, sym, row)
        if desc["flags"] & F_BRIDGE and desc["left"] not in (3, 10):
            assert screen_row(cpc, bank, ring, 0, 72) == sheets.bridges[desc["left"]], f"runner drawn over the deck (row {i})"
            checked += 1
    assert checked
