"""Shared helpers for headless tests on top of ~/cpcemu (floooh/chips CPC)."""

import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BUILD = os.path.join(ROOT, "build")
DSK = os.path.join(BUILD, "aper.dsk")
SYM = os.path.join(BUILD, "aper.sym")
ARTIFACTS = os.path.join(BUILD, "test-artifacts")

sys.path.insert(0, os.environ.get("CPCEMU", os.path.expanduser("~/cpcemu")))
from cpc import CPC  # noqa: E402

BOOT_FRAMES = 150       # cold boot to the BASIC prompt


def load_symbols(path=SYM):
    """Parses rasm '-s' output: 'LABEL #ADDR B0 L' -> {'label': addr}."""
    symbols = {}
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2 and parts[1].startswith("#"):
                symbols[parts[0].lower()] = int(parts[1][1:], 16)
    return symbols


def boot_game(max_frames=1500):
    """Cold-boots a 6128, inserts build/aper.dsk, RUN"DISC (loads the banks
    and the game) and waits until the game's main loop is running."""
    sym = load_symbols()
    cpc = CPC()
    cpc.run_frames(BOOT_FRAMES)
    cpc.insert_disc(DSK)
    cpc.type_text('RUN"DISC\n')
    for _ in range(max_frames // 25):
        cpc.run_frames(25)
        if sym["start"] <= cpc.pc < sym["end_of_code"] and peek16(cpc, sym["frame_counter"]) > 2:
            return cpc
    raise AssertionError(f"game did not start (PC #{cpc.pc:04X})")


def peek16(cpc, addr):
    lo, hi = cpc.read_ram(addr, 2)
    return lo | (hi << 8)


def border_rgb(cpc):
    """Colour of the top-left corner, which is always border."""
    return cpc.image().getpixel((2, 2))


FRAME_US = 19968         # one PAL frame


def peek8(cpc, addr):
    return cpc.read_ram(addr, 1)[0]


def sync_frame(cpc, sym):
    """Runs to the next VSYNC interrupt, then one whole frame: the returned
    image is a complete picture (not two half frames). Returns (image, tick)."""
    tick = peek8(cpc, sym["vbl_tick"])
    while peek8(cpc, sym["vbl_tick"]) == tick:
        cpc.run_us(64)
    tick = peek8(cpc, sym["vbl_tick"])
    cpc.run_us(FRAME_US - 128)
    return cpc.image(full_framebuffer=True), tick


def sync_game_frame(cpc, sym):
    """Like sync_frame, for a frame that starts a game frame (every 2nd VSYNC):
    the scroll state and the sprites shown belong to the same game frame."""
    while True:
        img, tick = sync_frame(cpc, sym)
        if peek8(cpc, sym["last_tick"]) == tick:
            return img


def is_white(p):
    return min(p) > 200


def is_bright_yellow(p):
    return p[0] > 200 and p[1] > 200 and p[2] < 100


def is_pastel_yellow(p):
    """Pen 14 (coin glint): only the test sprite uses it on screen."""
    return p[0] > 200 and p[1] > 200 and 80 < p[2] < 200


def save_screenshot(cpc, name):
    os.makedirs(ARTIFACTS, exist_ok=True)
    return cpc.screenshot(os.path.join(ARTIFACTS, name), aspect=True)
