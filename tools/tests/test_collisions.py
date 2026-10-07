"""Phase 5: obstacles and collisions.

Each scenario stops the scroll, clears every collision class in the world
ring (and every item) and plants its own obstacles a few rows ahead of the
runner (rows generated later appear above them, so nothing else can get in
the way). The drawn tiles do not change - collisions only read the descriptors.
"""

from harness import boot_game, load_symbols, peek8, peek16, sync_game_frame
import cpc as cpcmod  # noqa: E402  (path set up by harness)

COL_NONE, COL_STOP, COL_SIGNAL, COL_TRAIN, COL_NOSE, COL_RAMP_UP, COL_RAMP_DOWN, COL_GAP = range(8)
STATE_RUN, STATE_CRASHED, STATE_GAME_OVER = range(3)
MODE_OVER = 5
AHEAD = 6                       # rows below the top of the screen where planting starts


class Scenario:
    """Rows are planted when the game has generated them (generation clears
    a descriptor), so the plan is applied to every new row each frame."""

    def __init__(self, speed=4, pickups=False):
        self.sym = load_symbols()
        self.cpc = boot_game(collisions=True, pickups=pickups)
        self.speed = speed
        self.plan = {}
        self.applied = set()
        self._set_speed(0)
        sync_game_frame(self.cpc, self.sym)
        sync_game_frame(self.cpc, self.sym)
        self.top = peek16(self.cpc, self.sym["scr_top_row"])
        self.base_row = self.top - AHEAD
        self.clear_until = self.top + 80
        self._apply()
        if pickups:                 # forget what was picked up while booting
            self.cpc.write_ram(self.sym["score"], bytes(5))         # score, coins

    def _set_speed(self, speed):
        self.cpc.write_ram(self.sym["scroll_speed"], bytes([speed]))

    def _desc(self, row):
        return self.sym["world_ring"] + (row & 63) * self.sym["row_size"]

    def _apply(self):
        """Clears and plants every generated row (except the top one, which
        may still be in the middle of its generation)."""
        top = peek16(self.cpc, self.sym["scr_top_row"])
        for row in range(top - 60, top):
            if row in self.applied or row > self.clear_until:
                continue
            cells = self.plan.get(row, [COL_NONE] * 3 + [0] * 3)     # 3 classes, 3 items
            self.cpc.write_ram(self._desc(row) + 6, bytes(cells))
            self.applied.add(row)

    def plant_lane(self, offset, lane, classes):
        """classes listed bottom to top, starting `offset` rows above base_row."""
        for k, cls in enumerate(classes):
            row = self.base_row + offset + k
            assert row not in self.applied or row < self.top, "plant before go()"
            self.plan.setdefault(row, [COL_NONE] * 3 + [0] * 3)[lane] = cls
            self.applied.discard(row)
        self._apply()

    def plant_item(self, offset, lane, item):
        row = self.base_row + offset
        assert row not in self.applied or row < self.top, "plant before go()"
        self.plan.setdefault(row, [COL_NONE] * 3 + [0] * 3)[3 + lane] = item
        self.applied.discard(row)
        self._apply()

    def go(self):
        self._set_speed(self.speed)

    def frame(self):
        sync_game_frame(self.cpc, self.sym)
        self._apply()
        return self.state()

    def state(self):
        c, s = self.cpc, self.sym
        return {"state": peek8(c, s["game_state"]), "lives": peek8(c, s["lives"]),
                "crashes": peek8(c, s["crashes"]), "base": peek8(c, s["player_base"]),
                "z": peek8(c, s["player_z"]), "lane": peek8(c, s["player_lane"]),
                "front": peek16(c, s["front_row"]), "feet": peek16(c, s["feet_row"]),
                "top": peek16(c, s["scr_top_row"]), "invuln": peek8(c, s["invuln"])}

    def until_front(self, row, limit=200):
        for _ in range(limit):
            st = self.frame()
            if st["front"] >= row:
                return st
        raise AssertionError(f"front probe never reached row {row}")

    def run(self, frames):
        return [self.frame() for _ in range(frames)]

    def tap(self, key):
        self.cpc.key_down(key)
        self.frame()
        self.cpc.key_up(key)

    def past(self, row, limit=300):
        """Runs until the feet are past `row`; returns all states."""
        states = []
        for _ in range(limit):
            states.append(self.frame())
            if states[-1]["feet"] > row and states[-1]["state"] == STATE_RUN:
                return states
        raise AssertionError(f"runner never got past row {row}")


def stop():
    return [COL_STOP, COL_STOP]


def ramp_up():
    return [COL_RAMP_UP | (k << 4) for k in range(3)]


def ramp_down():
    return [COL_RAMP_DOWN | (k << 4) for k in range(3)]


def test_stop_crashes_and_the_world_waits():
    sc = Scenario()
    sc.plant_lane(0, 1, stop())
    sc.go()
    st = sc.until_front(sc.base_row, limit=200)
    states = sc.run(4)
    assert states[-1]["state"] == STATE_CRASHED and states[-1]["lives"] == 2 and states[-1]["crashes"] == 1
    top = states[-1]["top"]
    assert all(s["top"] == top for s in sc.run(20)), "the world must stop while crashed"
    states = sc.run(30)
    assert states[-1]["state"] == STATE_RUN and states[-1]["invuln"] > 0


def test_jump_clears_a_stop():
    sc = Scenario()
    sc.plant_lane(0, 1, stop())
    sc.go()
    sc.until_front(sc.base_row - 1)
    sc.tap(cpcmod.KEY_UP)
    states = sc.past(sc.base_row + 1)
    assert all(s["crashes"] == 0 for s in states)
    assert any(s["z"] == 1 for s in states)


def test_ramp_lifts_onto_the_roof_and_back_down():
    sc = Scenario()
    sc.plant_lane(0, 1, ramp_up() + [COL_TRAIN] * 8 + ramp_down())
    sc.go()
    states = sc.past(sc.base_row + 14)
    bases = [s["base"] for s in states]
    assert all(s["crashes"] == 0 for s in states), bases
    assert 2 in bases and 1 in bases and bases[-1] == 0, bases
    # the climb goes 0 -> 1 -> 2 and the descent 2 -> 1 -> 0, one step at a time
    steps = [b for i, b in enumerate(bases) if i == 0 or b != bases[i - 1]]
    assert steps == [0, 1, 2, 1, 0], steps


def test_train_end_without_ramp_drops_to_the_ground():
    sc = Scenario()
    sc.plant_lane(0, 1, ramp_up() + [COL_TRAIN] * 6)
    sc.go()
    states = sc.past(sc.base_row + 12)
    bases = [s["base"] for s in states]
    assert all(s["crashes"] == 0 for s in states)
    assert 2 in bases and bases[-1] == 0
    i = bases.index(2)
    after = [s["z"] for s in states[i:]]
    assert 1 in after[after.index(2):], "a short fall is shown"


def test_train_without_ramp_crashes():
    sc = Scenario()
    sc.plant_lane(0, 1, [COL_NOSE] + [COL_TRAIN] * 6)
    sc.go()
    sc.until_front(sc.base_row)
    states = sc.run(3)
    assert states[-1]["crashes"] == 1


def test_ground_jump_cannot_land_on_a_train():
    sc = Scenario()
    sc.plant_lane(0, 1, [COL_TRAIN] * 10)
    sc.go()
    sc.until_front(sc.base_row - 1)
    sc.tap(cpcmod.KEY_UP)
    states = sc.run(20)
    assert any(s["crashes"] == 1 for s in states)


def test_red_signal_crashes_green_and_amber_pass():
    for state, red, crashes in ((2, 1, 1), (0, 0, 0), (1, 0, 0)):
        sc = Scenario()
        sc.cpc.write_ram(sc.sym["signal_state"], bytes([state]))
        sc.cpc.write_ram(sc.sym["signal_red"], bytes([red]))
        sc.cpc.write_ram(sc.sym["signal_timer"], bytes([250]))
        sc.plant_lane(0, 1, [COL_NONE, COL_SIGNAL])
        sc.go()
        sc.until_front(sc.base_row + 1)
        states = sc.run(6)
        assert states[-1]["crashes"] == crashes, (state, states[-1])


def test_lane_change_into_a_train_crashes():
    sc = Scenario()
    sc.plant_lane(0, 2, [COL_TRAIN] * 20)
    sc.go()
    sc.until_front(sc.base_row + 5)
    sc.tap(cpcmod.KEY_RIGHT)
    states = sc.run(6)
    assert states[-1]["crashes"] == 1
    # thrown back to the middle of the lane it came from
    centre = 15 + 7 + 14                              # LANE_CENTRE1 + LANE_BYTES: lane 1
    for st in states + sc.run(60):
        if st["crashes"]:
            assert st["lane"] == 1
            assert peek8(sc.cpc, sc.sym["player_centre"]) == centre
    sc.tap(cpcmod.KEY_LEFT)                           # lane changes work as before
    sc.run(6)
    assert sc.state()["lane"] == 0
    assert peek8(sc.cpc, sc.sym["player_centre"]) == centre - 14


def test_roof_hop_between_parallel_trains():
    sc = Scenario()
    sc.plant_lane(0, 1, ramp_up() + [COL_TRAIN] * 16)
    sc.plant_lane(3, 2, [COL_TRAIN] * 16)
    sc.go()
    for _ in range(200):
        st = sc.frame()
        if st["base"] == 2 and st["feet"] >= sc.base_row + 6:
            break
    sc.tap(cpcmod.KEY_RIGHT)
    states = sc.run(8)
    assert states[-1]["lane"] == 2 and states[-1]["base"] == 2 and states[-1]["crashes"] == 0


def test_protected_after_a_crash():
    sc = Scenario()
    sc.plant_lane(0, 1, stop())
    sc.plant_lane(3, 1, stop())                      # right behind the first one
    sc.go()
    states = sc.past(sc.base_row + 6, limit=400)
    assert states[-1]["crashes"] == 1


def test_game_over_shows_the_score_screen():
    sc = Scenario()
    sc.cpc.write_ram(sc.sym["lives"], bytes([1]))
    sc.plant_lane(0, 1, stop())
    sc.go()
    sc.until_front(sc.base_row)
    states = sc.run(50)
    assert any(s["state"] == STATE_GAME_OVER for s in states)
    sc.run(90)
    assert peek8(sc.cpc, sc.sym["game_mode"]) == MODE_OVER


def test_signal_lamps_cycle():
    sym = load_symbols()
    cpc = boot_game()
    seen = []                                    # (state, red) as they change
    for _ in range(160):
        sync_game_frame(cpc, sym)
        now = (peek8(cpc, sym["signal_state"]), peek8(cpc, sym["signal_red"]))
        if not seen or seen[-1] != now:
            seen.append(now)
    assert seen[:4] == [(2, 1), (0, 0), (1, 0), (2, 1)], seen  # red, green, amber (open), red



def _wagons(hard, jump):
    """Up a ramp onto two wagons joined by a coupler (row 3 + 12)."""
    sc = Scenario()
    sc.cpc.write_ram(sc.sym["gap_hard"], bytes([1 if hard else 0]))
    sc.plant_lane(0, 1, ramp_up() + [COL_TRAIN] * 12 + [COL_GAP] + [COL_TRAIN] * 12)
    sc.go()
    if jump:                                     # jump from the roof just before the gap
        for _ in range(300):
            st = sc.frame()
            if st["base"] == 2 and st["feet"] >= sc.base_row + 3 + 12 - 2:
                break
        sc.tap(cpcmod.KEY_SPACE)
    return sc.past(sc.base_row + 3 + 20)


def test_gap_between_wagons_is_a_roof_except_in_hard_mode():
    states = _wagons(hard=False, jump=False)
    assert states[-1]["crashes"] == 0 and states[-1]["base"] == 2
    states = _wagons(hard=True, jump=False)
    assert states[-1]["crashes"] == 1, "walked into the gap"


def test_hard_mode_jump_over_the_gap():
    states = _wagons(hard=True, jump=True)
    assert states[-1]["crashes"] == 0 and states[-1]["base"] == 2, states[-1]
