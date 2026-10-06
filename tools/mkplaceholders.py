"""Writes simple stand-in art for every sheet in tools/assets.py to
gfx/placeholder/<sheet>.png + .json, so code can be built and tested before
the real Aseprite art exists. Real sheets in gfx/png/ take precedence."""

import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import assets  # noqa: E402
from cpcpalette import ROOT, editor_rgb  # noqa: E402

OUT = os.path.join(ROOT, "gfx", "placeholder")
CLEAR = (0, 0, 0, 0)

# pens (plan.md 2.5)
BLACK, BLUE, GREY, WHITE, RED, ORANGE, OLIVE, YELLOW = range(8)
GREEN, LIME, SKY, BBLUE, PINK, BRED, GLINT, LAMP = range(8, 16)

TRAIN_COLOURS = {1: (GREEN, LIME), 2: (WHITE, BBLUE), 3: (RED, YELLOW)}


def c(pen):
    return editor_rgb(pen) + (255,)


class Frame:
    def __init__(self, w, h, background=None):
        self.img = Image.new("RGBA", (w, h), CLEAR if background is None else c(background))
        self.d = ImageDraw.Draw(self.img)
        self.w, self.h = w, h

    def rect(self, x0, y0, x1, y1, pen):
        self.d.rectangle((x0, y0, x1, y1), fill=c(pen))

    def px(self, x, y, pen):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.img.putpixel((x, y), c(pen))

    def ellipse(self, x0, y0, x1, y1, pen, outline=None):
        self.d.ellipse((x0, y0, x1, y1), fill=c(pen), outline=None if outline is None else c(outline))

    def checker(self, x0, y0, x1, y1, pen_a, pen_b):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.px(x, y, pen_a if (x + y) % 2 else pen_b)


# --- track (28x8) ------------------------------------------------------------
def rails(f, sleeper_phase=0):
    f.checker(0, 0, 27, 7, OLIVE, GREY)
    for y in (sleeper_phase, sleeper_phase + 4):
        f.rect(3, y, 24, y, RED)
    for x in (6, 20):
        f.rect(x, 0, x + 1, 7, GREY)
        f.rect(x, 0, x, 7, WHITE)


def train_body(f, t, top_round=False, bottom_round=False):
    body, stripe = TRAIN_COLOURS[t]
    rails(f)
    f.rect(2, 0, 25, 7, body)
    f.rect(2, 0, 2, 7, BLACK)
    f.rect(25, 0, 25, 7, BLACK)
    f.rect(4, 0, 4, 7, stripe)
    f.rect(23, 0, 23, 7, stripe)
    if top_round:
        f.rect(2, 0, 25, 0, BLACK)
        for x in (2, 3, 24, 25):
            f.px(x, 1, OLIVE)
    if bottom_round:
        f.rect(2, 7, 25, 7, BLACK)
        for x in (2, 3, 24, 25):
            f.px(x, 6, OLIVE)


def track_frame(name):
    f = Frame(28, 8)
    if name.startswith("rail"):
        rails(f, 1 if name.endswith("a") else 3)
    elif name.startswith("stop"):
        rails(f)
        for x in range(2, 26):
            f.rect(x, 2 if name.endswith("0") else 0, x, 7 if name.endswith("0") else 5,
                   BRED if (x // 3) % 2 else WHITE)
        f.rect(2, 7 if name.endswith("1") else 2, 25, 7 if name.endswith("1") else 2, BLACK)
    elif name.startswith("signal"):
        rails(f)
        if name.endswith("0"):
            f.rect(0, 3, 27, 5, GREY)
            f.rect(0, 3, 27, 3, BLACK)
            f.rect(12, 2, 15, 6, BLACK)
            f.rect(13, 3, 14, 5, LAMP)
        else:
            f.rect(0, 2, 1, 7, GREY)
            f.rect(26, 2, 27, 7, GREY)
    elif name.startswith("wagon") or name.startswith("loco"):
        t = int(name[5] if name.startswith("wagon") else name[4])
        part = name.split("_", 1)[1]
        if part == "coupler":
            rails(f)
            f.rect(12, 0, 15, 7, BLACK)
        else:
            train_body(f, t, top_round=part in ("end_top",), bottom_round=part in ("end_bottom", "nose"))
            if part == "body_a":
                f.rect(9, 2, 18, 5, GREY)
                f.rect(9, 5, 18, 5, BLACK)
            elif part == "body_b":
                for y in (2, 5):
                    f.rect(8, y, 19, y, BLACK)
            elif part == "nose":
                f.rect(6, 3, 21, 5, SKY)
                f.rect(6, 5, 21, 5, BLUE)
                f.px(5, 6, YELLOW)
                f.px(22, 6, YELLOW)
            elif part == "body":
                f.rect(8, 1, 19, 6, GREY)
                for y in (2, 4):
                    f.rect(9, y, 18, y, BLACK)
            elif part == "pantograph":
                for i in range(4):
                    f.px(13 - i, 3 + i, BLACK)
                    f.px(14 + i, 3 + i, BLACK)
                    f.px(13 - i, 3 - i, BLACK)
                    f.px(14 + i, 3 - i, BLACK)
    elif name.startswith("ramp"):
        rails(f)
        index = int(name[-1])
        up = name.startswith("ramp_up")
        level = index if up else 2 - index          # 0 = ground end, 2 = roof end
        for y in range(8):
            shade = (level * 8 + (7 - y)) // 8      # brighter towards the roof
            f.rect(3, y, 24, y, (BLUE, GREY, WHITE)[min(shade, 2)] if up else (WHITE, GREY, BLUE)[min(2 - shade, 2)])
        f.rect(2, 0, 2, 7, BLACK)
        f.rect(25, 0, 25, 7, BLACK)
        if level == 0:
            y = 7 if up else 0
            for x in range(3, 25):
                f.px(x, y, YELLOW if (x // 2) % 2 else BLACK)
    return f


# --- side tiles (30x8, left side; the right side is mirrored) -----------------
def road(f, dash_on):
    f.rect(0, 0, 26, 7, GREY)
    f.rect(27, 0, 27, 7, WHITE)
    f.rect(28, 0, 29, 7, GREEN)
    if dash_on:
        f.rect(9, 0, 9, 3, WHITE)
        f.rect(18, 0, 18, 3, WHITE)
    f.rect(0, 0, 0, 7, BLACK)


def ground(f, variant):
    f.checker(0, 0, 29, 7, GREEN, LIME if variant else GREEN)


def side_frame(name):
    f = Frame(30, 8)
    if name in ("road_a", "road_b"):
        road(f, name == "road_a")
    elif name.startswith("road_cross"):
        road(f, False)
        for x in range(1, 27, 3):
            f.rect(x, 0, x + 1, 7, WHITE)
    elif name.startswith("road_kiosk"):
        road(f, False)
        f.rect(20, 0, 27, 7, BRED if name.endswith("0") else YELLOW)
        f.rect(20, 0, 20, 7, BLACK)
    elif name.startswith("ground"):
        ground(f, name.endswith("a"))
    elif name == "path":
        ground(f, True)
        f.checker(8, 0, 21, 7, OLIVE, RED)
    elif name == "fence":
        ground(f, False)
        f.rect(27, 0, 27, 7, RED)
        f.rect(26, 3, 29, 3, RED)
    elif name.startswith("trans_"):
        urban_first = name.startswith("trans_urban")
        part = int(name[-1])
        road(f, False)
        g = Frame(30, 8)
        ground(g, True)
        split = 4 if part == 0 else 0
        for y in range(8):
            forest_line = (y < split) if urban_first else (y >= 8 - split)
            if (part == 1) == urban_first or forest_line:
                for x in range(30):
                    f.img.putpixel((x, y), g.img.getpixel((x, y)))
    return f


# --- overlays and sprites ------------------------------------------------------
def vehicle(w, h, body):
    f = Frame(w, h)
    f.rect(1, 0, w - 2, h - 1, body)
    f.rect(0, 1, w - 1, h - 2, body)
    f.rect(2, 2, w - 3, 3, SKY)
    f.rect(2, h - 3, w - 3, h - 3, SKY)
    f.rect(0, 1, 0, h - 2, BLACK)
    f.rect(w - 1, 1, w - 1, h - 2, BLACK)
    return f


def overlay_frame(name, w, h):
    if name.startswith("car_") or name == "taxi":
        return vehicle(w, h, {"car_red": BRED, "car_blue": BBLUE, "car_white": WHITE, "taxi": YELLOW}[name])
    if name == "bus":
        return vehicle(w, h, BBLUE)
    if name == "trolley":
        f = vehicle(w, h, YELLOW)
        f.rect(2, 8, 2, 20, BLACK)
        f.rect(5, 8, 5, 20, BLACK)
        return f
    f = Frame(w, h)
    if name == "pine":
        for y in range(h - 4):
            half = 1 + y * (w // 2 - 1) // (h - 5)
            f.rect(w // 2 - half, y, w // 2 + half - 1, y, GREEN if y % 4 else LIME)
        f.rect(w // 2 - 1, h - 4, w // 2, h - 1, RED)
    elif name in ("oak", "bush"):
        f.ellipse(0, 0, w - 1, h - 1, GREEN, outline=BLACK)
        f.ellipse(w // 4, h // 4, w // 2, h // 2, LIME)
    elif name == "cypress":
        f.ellipse(1, 0, w - 2, h - 1, GREEN, outline=BLACK)
    elif name == "rock":
        f.ellipse(0, 1, w - 1, h - 1, GREY, outline=BLACK)
        f.px(2, 3, WHITE)
    return f


def player_frame(name, w, h):
    f = Frame(w, h)
    pose = name.split("_", 1)[1]
    cx = w // 2
    head = max(3, w // 3)
    f.ellipse(cx - head // 2 - 1, 0, cx + head // 2, head, PINK, outline=BLACK)
    f.rect(cx - head // 2, 0, cx + head // 2 - 1, 1, RED)                  # hair
    body_top, body_bottom = head + 1, h * 2 // 3
    f.rect(1, body_top, w - 2, body_bottom, BRED)
    f.rect(cx - 2, body_top + 1, cx + 1, body_bottom - 1, ORANGE)          # backpack
    leg = (h - body_bottom) - 1
    if pose.startswith("crash"):
        f.rect(0, body_top, w - 1, body_bottom, BRED)
        f.rect(0, body_bottom + 1, w - 1, h - 1, BBLUE)
    elif pose.startswith("jump") or pose.startswith("lean"):
        f.rect(0, body_top + 1, w - 1, body_top + 2, PINK)                 # arms out
        f.rect(cx - 3, body_bottom + 1, cx - 2, h - 2, BBLUE)
        f.rect(cx + 1, body_bottom + 1, cx + 2, h - 2, BBLUE)
    else:
        step = int(pose[-1]) % 2
        left_len = leg if step else leg // 2
        right_len = leg // 2 if step else leg
        f.rect(cx - 3, body_bottom + 1, cx - 2, body_bottom + left_len, BBLUE)
        f.rect(cx + 1, body_bottom + 1, cx + 2, body_bottom + right_len, BBLUE)
        f.rect(cx - 3, body_bottom + left_len, cx - 2, body_bottom + left_len, WHITE)
        f.rect(cx + 1, body_bottom + right_len, cx + 2, body_bottom + right_len, WHITE)
    return f


def shadow_frame(w, h):
    f = Frame(w, h)
    for y in range(h):
        for x in range(w):
            inside = ((x - (w - 1) / 2) / (w / 2)) ** 2 + ((y - (h - 1) / 2) / (h / 2)) ** 2 <= 1
            if inside and (x + y) % 2 == 0:
                f.px(x, y, BLACK)
    return f


def item_frame(name, w, h):
    f = Frame(w, h)
    if name.startswith("coin"):
        widths = (8, 6, 2, 6)
        cw = widths[int(name[-1])]
        x0 = (w - cw) // 2
        f.ellipse(x0, 0, x0 + cw - 1, h - 1, YELLOW, outline=OLIVE)
        if cw > 2:
            f.px(x0 + 1, 2, GLINT)
        return f
    f.ellipse(0, 0, w - 1, h - 1, BLACK)
    f.ellipse(1, 1, w - 2, h - 2, WHITE)
    icon = {"pu_magnet": BRED, "pu_turbo": ORANGE, "pu_slow": GREEN, "pu_spring": GREY,
            "pu_helmet": BBLUE, "pu_ticket": BRED}[name]
    f.rect(3, 3, w - 4, h - 4, icon)
    if name == "pu_magnet":
        f.rect(5, 3, w - 6, h - 6, WHITE)
    if name == "pu_turbo":
        f.rect(5, 4, 6, 7, YELLOW)
    return f


def hud_frame(name, w, h):
    if name == "hud_bg":
        f = Frame(w, h)
        columns = [BLACK, WHITE] + [BLUE] * 2 + [GREY] + [BLUE] * 38 + [GREY] + [BLUE] * 2 + [WHITE, BLACK]
        for x, pen in enumerate(columns):
            f.rect(x, 0, x, h - 1, pen)
        return f
    if name.startswith("bar"):
        f = Frame(w, h, YELLOW if name == "bar_full" else BLUE)
        return f
    if name.startswith("d") and name[1:].isdigit():    # digit: bar of its value's height
        f = Frame(w, h, BLUE)
        f.rect(0, 6 - int(name[1:]) * 6 // 9, 2, 6, WHITE)
        return f
    f = Frame(w, h)
    pen = {"ic_coin": YELLOW, "ic_magnet": BRED, "ic_turbo": ORANGE, "ic_slow": GREEN,
           "ic_spring": GREY, "ic_helmet": BBLUE, "ic_ticket": WHITE, "ic_life": PINK,
           "ic_dist": LIME}[name]
    f.ellipse(0, 0, w - 1, h - 1, pen, outline=BLACK)
    return f


def bridge_frame(name):
    f = Frame(144, 8)
    if name.endswith("shadow"):
        f.checker(0, 0, 143, 7, BLACK, BLUE)
        return f
    part = int(name[-1])
    if name.startswith("footbridge"):
        f.rect(0, 0, 143, 7, RED)
        f.checker(0, 2, 143, 5, RED, OLIVE)
        if part == 0:
            f.rect(0, 0, 143, 1, GREY)
            f.rect(0, 0, 143, 0, WHITE)
        if part == 2:
            f.rect(0, 6, 143, 7, GREY)
            f.rect(0, 7, 143, 7, BLACK)
    else:
        f.rect(0, 0, 143, 7, GREY)
        if part == 0:
            f.rect(0, 0, 143, 2, WHITE)
            f.rect(0, 2, 143, 2, BLACK)
        elif part == 5:
            f.rect(0, 5, 143, 7, WHITE)
            f.rect(0, 7, 143, 7, BLACK)
        elif part in (2, 3):
            for x in range(0, 144, 16):
                f.rect(x, 3 if part == 2 else 4, x + 7, 3 if part == 2 else 4, WHITE)
    return f


def make_frame(sheet, name, w, h):
    if sheet == "track":
        return track_frame(name)
    if sheet in ("urban", "forest"):
        return side_frame(name)
    if sheet in ("urban_ov", "forest_ov"):
        return overlay_frame(name, w, h)
    if sheet == "bridges":
        return bridge_frame(name)
    if sheet == "platform":                             # grey concrete, white edge
        f = Frame(w, h, GREY)
        f.rect(w - 2, 0, w - 2, h - 1, WHITE)
        return f
    if sheet == "player":
        return player_frame(name, w, h)
    if sheet == "shadows":
        return shadow_frame(w, h)
    if sheet == "items":
        return item_frame(name, w, h)
    if sheet == "hud":
        return hud_frame(name, w, h)
    if sheet in ("font", "logo"):                       # a white box / a framed panel
        f = Frame(w, h, None if sheet == "font" else BLUE)
        if sheet == "font" and name != "space":
            f.rect(0, 0, w - 2, h - 2, WHITE)
        return f
    raise KeyError(sheet)


def write_sheet(sheet):
    spec = assets.SHEETS[sheet]
    width = sum(w for _, w, _ in spec)
    height = max(h for _, _, h in spec)
    image = Image.new("RGBA", (width, height), CLEAR)
    frames, x = [], 0
    for name, w, h in spec:
        frame = make_frame(sheet, name, w, h)
        assert frame.img.size == (w, h), (sheet, name, frame.img.size)
        image.paste(frame.img, (x, 0))
        frames.append({"filename": name, "frame": {"x": x, "y": 0, "w": w, "h": h}})
        x += w
    os.makedirs(OUT, exist_ok=True)
    image.save(os.path.join(OUT, sheet + ".png"))
    with open(os.path.join(OUT, sheet + ".json"), "w") as f:
        json.dump({"frames": frames, "meta": {"app": "tools/mkplaceholders.py", "size": {"w": width, "h": height}}},
                  f, indent=1)


if __name__ == "__main__":
    for sheet in assets.SHEETS:
        write_sheet(sheet)
        print(f"placeholder {sheet}")
