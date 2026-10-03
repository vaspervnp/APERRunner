"""Compiles track chunks (levels/chunks/*.txt) into src/data/chunks.asm.

Chunk file format:

    # chunk: train_mid_ramp
    # env: any            (any | urban | forest)
    # diff: 2             (1-5, minimum difficulty)
    # weight: 3           (relative probability)
    ..c  v..  ...
    ..c  W1c  ..c
    ...  W1.  ...
    ...  ^..  S..
    ...  ^..  S..

Grid rows are listed top to bottom as they appear on screen (the last line
is the first one the player meets). Each lane cell has 3 characters:

  object  '.' rail
          'T' train, locomotive first: its cab faces the player (bottom)
          'R' train, locomotive last: the player meets a wagon end first
          '^' ramp up (3 rows, below a train)   'v' ramp down (3 rows, above a train)
          'S' buffer stop (2 rows)   'F' signal (2 rows)
  type    train livery 1-3 for T/R, '.' otherwise
  item    '.' none  'c' coin  'M' magnet  'T' turbo  'Z' slow (turtle)
          'J' spring  'H' helmet  'X' ticket x2

A row has coins in one lane at most (never side by side in 2 or 3 lanes).

Trains are long: a locomotive of LOCO_ROWS rows and at least MIN_WAGONS
wagons of WAGON_ROWS rows, joined by 1-row couplers. A T/R run must be
exactly LOCO_ROWS + k * (1 + WAGON_ROWS) rows with k >= MIN_WAGONS
(38 rows for 2 wagons, 51 for 3, ...).
"""

import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import assets  # noqa: E402
from cpcpalette import ROOT  # noqa: E402

CHUNK_DIR = os.path.join(ROOT, "levels", "chunks")
OUT = os.path.join(ROOT, "src", "data", "chunks.asm")

TILE = {name: index for index, name in enumerate(assets.TRACK_TILES)}

# collision classes (low nibble) - see src/world.asm
COL_NONE, COL_STOP, COL_SIGNAL, COL_TRAIN, COL_NOSE, COL_RAMP_UP, COL_RAMP_DOWN = range(7)
ITEMS = {".": 0, "c": 1, "M": 2, "T": 3, "Z": 4, "J": 5, "H": 6, "X": 7}
ITEM_ROWS = {0: 0, 1: 1}                       # rows an item overlay covers (default 2)
ENVS = {"any": 0, "urban": 1, "forest": 2}

WAGON_ROWS = 12
LOCO_ROWS = 12
MIN_WAGONS = 2


def train_length(wagons):
    return LOCO_ROWS + wagons * (1 + WAGON_ROWS)


class LevelError(Exception):
    pass


def parse(path):
    header, grid = {}, []
    with open(path) as f:
        for number, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip():
                continue
            if line.startswith("#"):
                if ":" in line:
                    key, value = line[1:].split(":", 1)
                    header[key.strip()] = value.strip()
                continue
            cells = line.split()
            if len(cells) != 3 or any(len(c) != 3 for c in cells):
                raise LevelError(f"{path}:{number}: expected 3 cells of 3 characters, got {line!r}")
            grid.append((number, cells))
    if not grid:
        raise LevelError(f"{path}: empty chunk")
    return header, list(reversed(grid))        # bottom row first


def _runs(column):
    """[(start, length, object, type)] of consecutive equal object+type cells."""
    runs, start = [], 0
    for i in range(1, len(column) + 1):
        if i == len(column) or column[i][:2] != column[start][:2]:
            runs.append((start, i - start, column[start][0], column[start][1]))
            start = i
    return runs


def _train_type(path, row, t):
    if t not in "123":
        raise LevelError(f"{path}: row {row}: train cells need a livery 1-3, got {t!r}")
    return int(t)


def resolve_lane(path, column, lane):
    """column: cells bottom to top -> [(tile index, collision)]"""
    out = [None] * len(column)
    for start, length, obj, t in _runs(column):
        rows = range(start, start + length)
        where = f"lane {lane + 1}, rows {start}-{start + length - 1} from the bottom"
        if obj == ".":
            for r in rows:
                out[r] = (TILE["rail_b" if (r * 7 + lane * 3) % 11 == 0 else "rail_a"], COL_NONE)
        elif obj in "TR":
            tt = _train_type(path, start, t)
            wagons, rest = divmod(length - LOCO_ROWS, 1 + WAGON_ROWS)
            if length < LOCO_ROWS or rest or wagons < MIN_WAGONS:
                valid = ", ".join(str(train_length(k)) for k in range(MIN_WAGONS, MIN_WAGONS + 3))
                raise LevelError(f"{path}: {where}: a train needs a locomotive and at least {MIN_WAGONS} wagons: "
                                 f"{length} rows, valid lengths are {valid}, ...")
            parts = []                               # bottom to top, as (tile name, collision)
            wagon = ([f"wagon{tt}_end_bottom"]
                     + [f"wagon{tt}_body_{'a' if k % 3 == 1 else 'b'}" for k in range(WAGON_ROWS - 2)]
                     + [f"wagon{tt}_end_top"])
            if obj == "T":                           # cab at the bottom, back end at the top
                parts += ([(f"loco{tt}_nose", COL_NOSE)]
                          + [(f"loco{tt}_{'pantograph' if k in (2, LOCO_ROWS - 4) else 'body'}", COL_TRAIN)
                             for k in range(1, LOCO_ROWS - 1)]
                          + [(f"wagon{tt}_end_top", COL_TRAIN)])
                for _ in range(wagons):
                    parts += [(f"wagon{tt}_coupler", COL_TRAIN)] + [(n, COL_TRAIN) for n in wagon]
            else:                                    # wagons first, cab facing away at the top
                for _ in range(wagons):
                    parts += [(n, COL_TRAIN) for n in wagon] + [(f"wagon{tt}_coupler", COL_TRAIN)]
                parts += ([(f"wagon{tt}_end_bottom", COL_TRAIN)]
                          + [(f"loco{tt}_{'pantograph' if k in (3, LOCO_ROWS - 3) else 'body'}", COL_TRAIN)
                             for k in range(1, LOCO_ROWS - 1)]
                          + [(f"loco{tt}_nose_top", COL_TRAIN)])
            for r, (name, collision) in zip(rows, parts):
                out[r] = (TILE[name], collision)
        elif obj in "^v":
            if length != 3:
                raise LevelError(f"{path}: {where}: ramps are exactly 3 rows")
            neighbour = start + 3 if obj == "^" else start - 1
            if not (0 <= neighbour < len(column)) or column[neighbour][0] not in "TR":
                raise LevelError(f"{path}: {where}: ramp {'up must sit below' if obj == '^' else 'down must sit above'} a train")
            for k, r in enumerate(rows):
                name = f"ramp_{'up' if obj == '^' else 'down'}_{k}"
                out[r] = (TILE[name], (COL_RAMP_UP if obj == "^" else COL_RAMP_DOWN) | (k << 4))
        elif obj == "S":
            if length != 2:
                raise LevelError(f"{path}: {where}: a buffer stop is exactly 2 rows")
            out[start] = (TILE["stop_0"], COL_STOP)
            out[start + 1] = (TILE["stop_1"], COL_STOP)
        elif obj == "F":
            if length != 2:
                raise LevelError(f"{path}: {where}: a signal is exactly 2 rows")
            out[start] = (TILE["signal_1"], COL_NONE)      # stop line
            out[start + 1] = (TILE["signal_0"], COL_SIGNAL)  # gantry with the lamp
        else:
            raise LevelError(f"{path}: {where}: unknown object {obj!r}")
    return out


def compile_chunk(path):
    header, grid = parse(path)
    name = header.get("chunk") or os.path.splitext(os.path.basename(path))[0]
    env = header.get("env", "any")
    if env not in ENVS:
        raise LevelError(f"{path}: env must be one of {', '.join(ENVS)}")
    diff = int(header.get("diff", 1))
    weight = int(header.get("weight", 1))
    if not 1 <= diff <= 5 or not 1 <= weight <= 15:
        raise LevelError(f"{path}: diff 1-5 and weight 1-15")
    columns = [[cells[lane] for _, cells in grid] for lane in range(3)]
    lanes = [resolve_lane(path, col, lane) for lane, col in enumerate(columns)]
    rows = []
    for r in range(len(grid)):
        row = []
        for lane in range(3):
            item_char = columns[lane][r][2]
            if item_char not in ITEMS:
                raise LevelError(f"{path}: line {grid[r][0]}: unknown item {item_char!r}")
            item = ITEMS[item_char]
            if item > 1 and r == len(grid) - 1:
                raise LevelError(f"{path}: line {grid[r][0]}: power-ups cover 2 rows, not allowed on the top row")
            tile, collision = lanes[lane][r]
            row += [tile, collision, item]
        coin_lanes = sum(1 for lane in range(3) if row[lane * 3 + 2] == ITEMS["c"])
        if coin_lanes > 1:
            raise LevelError(f"{path}: line {grid[r][0]}: coins in {coin_lanes} lanes - a row has coins in one lane only")
        rows.append(row)
    return {"name": name, "env": ENVS[env], "diff": diff, "weight": weight, "rows": rows}


def asm_source(chunks):
    lines = ["; generated by tools/mklevel.py from levels/chunks/ - do not edit",
             f"CHUNK_COUNT equ {len(chunks)}",
             "; chunk: rows, min difficulty, weight, env (0 any, 1 urban, 2 forest),",
             ";        then per row bottom to top: 3 x (track tile, collision, item)",
             "chunk_table:"]
    lines += [f"                defw chunk_{c['name']}" for c in chunks]
    for c in chunks:
        lines.append(f"chunk_{c['name']}:")
        lines.append(f"                defb {len(c['rows'])},{c['diff']},{c['weight']},{c['env']}")
        for row in c["rows"]:
            lines.append("                defb " + ",".join(str(v) for v in row))
    return "\n".join(lines) + "\n"


def load_all():
    paths = sorted(glob.glob(os.path.join(CHUNK_DIR, "*.txt")))
    chunks = [compile_chunk(p) for p in paths]
    names = [c["name"] for c in chunks]
    if len(set(names)) != len(names):
        raise LevelError("chunk names must be unique")
    return chunks


def main():
    try:
        chunks = load_all()
    except LevelError as e:
        print(f"mklevel: {e}", file=sys.stderr)
        return 1
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write(asm_source(chunks))
    size = sum(4 + 9 * len(c["rows"]) for c in chunks)
    print(f"chunks     {len(chunks):3d} chunks  {size:6d} bytes -> {os.path.relpath(OUT, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
