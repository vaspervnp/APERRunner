"""Phase 6: coins, power-ups, magnet, score."""

from harness import boot_game, load_symbols, peek8, peek16, save_screenshot, sync_game_frame
from world_model import Sheets
import cpc as cpcmod  # noqa: E402  (path set up by harness)
import test_collisions as tc
import test_world as tw

COIN, MAGNET, TURBO, SLOW, SPRING, HELMET, TICKET = range(1, 8)
DURATIONS = {MAGNET: 250, TURBO: 200, SLOW: 200, SPRING: 250, TICKET: 375}
TIMER = {MAGNET: "pu_magnet", TURBO: "pu_turbo", SLOW: "pu_slow", SPRING: "pu_spring", TICKET: "pu_ticket"}
FLYERS, FLY_SIZE = 8, 4


def bcd(cpc, addr, size):
    value = 0
    for byte in reversed(cpc.read_ram(addr, size)):
        value = value * 100 + (byte >> 4) * 10 + (byte & 15)
    return value


def counters(sc):
    c, s = sc.cpc, sc.sym
    return {"coins": bcd(c, s["coins"], 2), "score": bcd(c, s["score"], 3),
            "distance": peek16(c, s["distance"]), "helmet": peek8(c, s["helmet"]),
            **{k: peek16(c, s[v]) for k, v in TIMER.items()}}


def poke16(sc, name, value):
    sc.cpc.write_ram(sc.sym[name], bytes([value & 255, value >> 8]))


def flying(cpc, sym):
    return sum(cpc.read_ram(sym["flyers"] + i * FLY_SIZE, 1)[0] for i in range(FLYERS))


def test_coin_under_the_feet_is_collected():
    sc = tc.Scenario(pickups=True)
    sc.plant_item(2, 1, COIN)
    sc.plant_item(4, 0, COIN)                           # another lane: stays
    sc.go()
    before = counters(sc)
    sc.past(sc.base_row + 5)
    after = counters(sc)
    assert after["coins"] == 1, after
    rows = after["distance"] - before["distance"]
    assert after["score"] - before["score"] == 10 + rows, (before, after)
    assert sc.cpc.read_ram(sc._desc(sc.base_row + 2) + 9, 3) == bytes(3), "the item is gone"
    assert sc.cpc.read_ram(sc._desc(sc.base_row + 4) + 9, 3) == bytes([COIN, 0, 0])


def test_ticket_doubles_the_coin_points():
    sc = tc.Scenario(pickups=True)
    sc.plant_item(2, 1, TICKET)
    sc.plant_item(6, 1, COIN)
    sc.go()
    sc.past(sc.base_row + 3)
    before = counters(sc)
    assert 0 < before[TICKET] <= DURATIONS[TICKET]
    sc.past(sc.base_row + 7)
    after = counters(sc)
    rows = after["distance"] - before["distance"]
    assert after["coins"] == 1 and after["score"] - before["score"] == 20 + rows, (before, after)


def test_powerups_start_and_expire():
    for item in (MAGNET, SPRING, TICKET):
        sc = tc.Scenario(pickups=True)
        sc.plant_item(2, 1, item)
        sc.go()
        sc.past(sc.base_row + 3)
        left = counters(sc)[item]
        assert DURATIONS[item] - 40 < left <= DURATIONS[item], (item, left)
        poke16(sc, TIMER[item], 5)
        sc.run(6)
        assert counters(sc)[item] == 0, item


def test_power_up_on_a_roof_is_taken_from_the_roof():
    """A power-up on a wagon roof: up the ramp, along the roof, taken."""
    sc = tc.Scenario(speed=4, pickups=True)
    sc.plant_lane(0, 1, tc.ramp_up() + [tc.COL_TRAIN] * 24 + tc.ramp_down())
    sc.plant_item(16, 1, TURBO)
    sc.go()
    states = sc.past(sc.base_row + 18)
    assert all(st["crashes"] == 0 for st in states)
    assert max(st["base"] for st in states) == 2, "on the roof"
    assert counters(sc)[TURBO] > 0, "taken on the roof"


def test_turbo_and_slow_change_the_speed():
    sc = tc.Scenario(speed=4, pickups=True)
    sc.plant_item(2, 1, TURBO)
    sc.plant_item(40, 1, SLOW)
    sc.go()
    sc.past(sc.base_row + 3)

    def position():
        """The picture shown (the next one may still be in the making)."""
        return peek16(sc.cpc, sc.sym["cur_top_row"]) * 8 - peek8(sc.cpc, sc.sym["cur_j"])

    def lines_per_frame():
        start = position()
        sc.run(8)
        return (position() - start) / 8

    assert counters(sc)[TURBO] > 0
    assert lines_per_frame() == 6
    sc.past(sc.base_row + 41)
    st = counters(sc)
    assert st[SLOW] > 0 and st[TURBO] == 0, "slow cancels turbo"
    sc.run(1)
    assert lines_per_frame() == 2
    poke16(sc, "pu_slow", 2)
    sc.run(3)
    assert lines_per_frame() == 4, "back to the normal speed"


def test_turbo_doubles_the_distance_points():
    sc = tc.Scenario(pickups=True)
    sc.go()
    sc.run(4)
    poke16(sc, "pu_turbo", 200)
    before = counters(sc)
    sc.run(20)
    after = counters(sc)
    rows = after["distance"] - before["distance"]
    assert rows > 0 and after["score"] - before["score"] == 2 * rows


def test_helmet_absorbs_one_crash():
    sc = tc.Scenario(pickups=True)
    sc.plant_item(2, 1, HELMET)
    sc.plant_lane(8, 1, tc.stop())
    sc.plant_lane(40, 1, tc.stop())                     # after the protection
    sc.go()
    sc.past(sc.base_row + 3)
    assert counters(sc)["helmet"]
    states = sc.past(sc.base_row + 10)
    assert all(s["crashes"] == 0 and s["lives"] == 3 for s in states)
    assert counters(sc)["helmet"] == 0 and any(s["invuln"] for s in states)
    sc.until_front(sc.base_row + 40)
    states = sc.run(4)
    assert states[-1]["crashes"] == 1, "only one crash is absorbed"


def test_springs_jump_onto_a_train():
    sc = tc.Scenario(pickups=True)
    poke16(sc, "pu_spring", 250)
    sc.plant_lane(6, 1, [tc.COL_NOSE] + [tc.COL_TRAIN] * 24)
    sc.go()
    sc.until_front(sc.base_row + 4)
    sc.tap(cpcmod.KEY_UP)
    states = sc.run(24)
    zs = [s["z"] for s in states]
    assert max(zs) == 4, zs
    assert all(s["crashes"] == 0 for s in states), zs
    assert states[-1]["base"] == 2 and states[-1]["z"] == 2, "landed on the roof"


def test_magnet_pulls_coins_from_the_next_lanes():
    sc = tc.Scenario(pickups=True)
    poke16(sc, "pu_magnet", 250)
    for offset, lane in ((8, 0), (10, 2), (12, 0), (14, 1), (16, 2)):
        sc.plant_item(offset, lane, COIN)
    sc.go()
    most = 0
    for _ in range(120):
        sc.frame()
        most = max(most, flying(sc.cpc, sc.sym))
    assert counters(sc)["coins"] == 5
    assert 1 <= most <= FLYERS
    assert flying(sc.cpc, sc.sym) == 0


def test_magnet_far_lane_is_out_of_reach():
    sc = tc.Scenario(pickups=True)
    poke16(sc, "pu_magnet", 250)
    sc.tap(cpcmod.KEY_LEFT)                             # runner in lane 0
    sc.plant_item(10, 2, COIN)
    sc.go()
    sc.run(100)
    assert counters(sc)["coins"] == 0


def test_magnet_run_keeps_the_frame_budget_and_erases_coins():
    """A real run at top speed (7) with the magnet always on: no missed frames,
    coins fly in, and every picked-up item is erased from the screen."""
    sym = load_symbols()
    cpc = boot_game(pickups=True)
    cpc.write_ram(sym["scroll_speed"], bytes([7]))           # top speed: hard + turbo
    cpc.write_ram(sym["max_load"], bytes([0]))
    missed = peek8(cpc, sym["missed_frames"])
    most = 0
    for frame in range(400):
        if frame % 50 == 0:
            cpc.write_ram(sym["pu_magnet"], bytes([250, 0]))
            cpc.write_ram(sym["pu_slow"], bytes([0, 0]))
        sync_game_frame(cpc, sym)
        most = max(most, flying(cpc, sym))
    coins = bcd(cpc, sym["coins"], 2)
    load = peek8(cpc, sym["max_load"])
    print(f"    {coins} coins, up to {most} flying, max load {load}/12")
    assert coins >= 10 and most >= 2
    assert peek8(cpc, sym["missed_frames"]) == missed, "missed frames with the magnet"
    assert load < 12, "a game frame has 12 interrupt periods"
    # stop everything, let the last coins land, compare the screen with the tiles
    for name in ("pu_magnet", "pu_turbo", "pu_slow"):
        cpc.write_ram(sym[name], bytes([0, 0]))
    cpc.write_ram(sym["no_pickups"], bytes([1]))
    cpc.write_ram(sym["scroll_speed"], bytes([0]))
    for _ in range(30):
        sync_game_frame(cpc, sym)
    assert flying(cpc, sym) == 0
    save_screenshot(cpc, "magnet_run.png")
    assert tw._check_screen(cpc, sym, Sheets()) > 100


def test_a_jump_goes_over_the_items():
    sc = tc.Scenario(pickups=True)
    sc.plant_item(8, 1, COIN)
    sc.plant_item(10, 1, COIN)
    sc.plant_item(12, 1, COIN)
    sc.go()
    for _ in range(300):
        st = sc.frame()
        if st["feet"] >= sc.base_row + 7:
            break
    sc.tap(cpcmod.KEY_SPACE)
    sc.past(sc.base_row + 13)
    assert counters(sc)["coins"] == 0, "in the air: no coins"
