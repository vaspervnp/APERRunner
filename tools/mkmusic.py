"""Compiles the tunes and sound effects (music/*.txt) into src/data/music.asm.

Tune file:

    # tune: game          (name: TUNE_GAME)
    # quarter: 16         (player ticks per quarter note; 50 ticks a second)
    # loop: yes           (yes: back to the start, no: once, then silence)
    A: A4/8 Bb4/8 C#5/4 r/4 | ...     channel A (melody), lines join up
    B: A2/4 E3/4 ...                  channel B (bass)

A note is <name><octave>/<length>, name C D E F G A B with # or b, octave
2-7, length 1 2 4 8 16 (whole .. sixteenth), a trailing '.' makes it
dotted; r/<length> is a rest. '|' marks bars and is ignored.

Sound effect file (music/sfx.txt), one effect per line:

    coin 1: B5:13 E6:13 n12:8 A2+n31:15 r

name, priority, then one step per tick: note:volume (tone), nNN:volume
(noise, period NN 0-31), note+nNN:volume (both), r (silence).

Output (bank C7):
  note_periods       AY tone periods (1 MHz clock) of notes 1.. (C2 = 1)
  tune_table         per tune: channel A stream, channel B stream, quarter
  tune streams       (note, ticks) pairs; note 0 = rest; then TUNE_LOOP or
                     TUNE_STOP
  sfx_table          per effect: steps address, priority
  sfx steps          period (2), volume | SFX_TONE_OFF | SFX_NOISE_ON,
                     noise period; SFX_END ends
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpcpalette import ROOT  # noqa: E402

MUSIC_DIR = os.path.join(ROOT, "music")
OUT = os.path.join(ROOT, "src", "data", "music.asm")

AY_CLOCK = 1_000_000
FIRST_OCTAVE, LAST_OCTAVE = 2, 7
SEMITONES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
LENGTHS = (1, 2, 4, 8, 16)
TUNE_LOOP, TUNE_STOP = 0xFF, 0xFE
SFX_END = 0xFF
SFX_TONE_OFF, SFX_NOISE_ON = 0x80, 0x40
MAX_TICKS = 250
CHANNELS = ("A", "B")

NOTE_RE = re.compile(r"^([A-G])([#b]?)([0-9])$")


class MusicError(Exception):
    pass


def note_index(name, where=""):
    """'C#5' -> 1-based index from C2."""
    m = NOTE_RE.match(name)
    if not m:
        raise MusicError(f"{where}: bad note {name!r}")
    letter, accidental, octave = m.group(1), m.group(2), int(m.group(3))
    semitone = SEMITONES[letter] + {"#": 1, "b": -1, "": 0}[accidental]
    index = (octave - FIRST_OCTAVE) * 12 + semitone + 1
    if not FIRST_OCTAVE <= octave <= LAST_OCTAVE or not 1 <= index <= note_count():
        raise MusicError(f"{where}: note {name!r} out of range (C{FIRST_OCTAVE}-B{LAST_OCTAVE})")
    return index


def note_count():
    return (LAST_OCTAVE - FIRST_OCTAVE + 1) * 12


def periods():
    """AY period of every note index (1..note_count())."""
    out = []
    for index in range(1, note_count() + 1):
        midi = 36 + index - 1                    # C2 = MIDI 36
        freq = 440.0 * 2 ** ((midi - 69) / 12)
        out.append(round(AY_CLOCK / (16 * freq)))
    return out


def ticks_of(length, quarter, where):
    dotted = length.endswith(".")
    value = int(length.rstrip(".")) if length.rstrip(".").isdigit() else 0
    if value not in LENGTHS:
        raise MusicError(f"{where}: length must be one of {LENGTHS}, got {length!r}")
    ticks = quarter * 4 / value * (1.5 if dotted else 1)
    if ticks != int(ticks) or not 1 <= ticks <= MAX_TICKS:
        raise MusicError(f"{where}: /{length} is not a whole number of ticks at quarter {quarter}")
    return int(ticks)


def parse_stream(text, quarter, where):
    events = []
    for token in text.split():
        if token == "|":
            continue
        name, sep, length = token.partition("/")
        if not sep:
            raise MusicError(f"{where}: expected note/length, got {token!r}")
        note = 0 if name == "r" else note_index(name, where)
        events.append((note, ticks_of(length, quarter, where)))
    return events


def load_tune(path):
    header, streams = {}, {ch: [] for ch in CHANNELS}
    with open(path, encoding="utf-8") as f:
        lines = list(enumerate(f, 1))
    for number, line in lines:
        line = line.strip()
        if line.startswith("#") and ":" in line:
            key, value = line[1:].split(":", 1)
            header[key.strip()] = value.strip()
    quarter = int(header.get("quarter", 16))
    for number, line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        channel, sep, text = line.partition(":")
        if not sep or channel.strip() not in CHANNELS:
            raise MusicError(f"{path}:{number}: expected 'A: ...' or 'B: ...'")
        streams[channel.strip()] += parse_stream(text, quarter, f"{path}:{number}")
    name = header.get("tune")
    if not name or not name.isidentifier():
        raise MusicError(f"{path}: needs '# tune: <name>'")
    loop = header.get("loop", "yes")
    if loop not in ("yes", "no"):
        raise MusicError(f"{path}: loop is yes or no")
    if not any(streams.values()):
        raise MusicError(f"{path}: no notes")
    return {"name": name, "quarter": quarter, "loop": loop == "yes", "streams": streams}


def parse_step(step, where):
    if step == "r":
        return (0, 0, 0)                         # period, volume|flags, noise
    body, sep, volume = step.rpartition(":")
    if not sep or not volume.isdigit() or not 0 <= int(volume) <= 15:
        raise MusicError(f"{where}: step {step!r}: expected <sound>:<volume 0-15>")
    flags, period, noise = SFX_TONE_OFF, 0, 0
    for part in body.split("+"):
        if part.startswith("n") and part[1:].isdigit():
            noise = int(part[1:])
            if not 0 <= noise <= 31:
                raise MusicError(f"{where}: noise period 0-31, got {noise}")
            flags |= SFX_NOISE_ON
        else:
            period = periods()[note_index(part, where) - 1]
            flags &= ~SFX_TONE_OFF
    return (period, int(volume) | flags, noise)


def load_sfx(path):
    effects = []
    with open(path, encoding="utf-8") as f:
        for number, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            head, sep, steps = line.partition(":")
            parts = head.split()
            if not sep or len(parts) != 2 or not parts[0].isidentifier() or not parts[1].isdigit():
                raise MusicError(f"{path}:{number}: expected '<name> <priority>: steps'")
            where = f"{path}:{number}"
            effects.append({"name": parts[0], "prio": int(parts[1]),
                            "steps": [parse_step(s, where) for s in steps.split()]})
    if not effects:
        raise MusicError(f"{path}: no effects")
    return effects


def load_all(music_dir=MUSIC_DIR):
    tunes = [load_tune(p) for p in sorted(glob.glob(os.path.join(music_dir, "*.txt")))
             if os.path.basename(p) != "sfx.txt"]
    names = [t["name"] for t in tunes]
    if len(set(names)) != len(names):
        raise MusicError("tune names must be unique")
    return tunes, load_sfx(os.path.join(music_dir, "sfx.txt"))


def asm_source(tunes, effects):
    lines = ["; generated by tools/mkmusic.py from music/*.txt - do not edit",
             f"TUNE_LOOP equ #{TUNE_LOOP:02X}", f"TUNE_STOP equ #{TUNE_STOP:02X}",
             f"SFX_END equ #{SFX_END:02X}", f"SFX_TONE_OFF equ #{SFX_TONE_OFF:02X}",
             f"SFX_NOISE_ON equ #{SFX_NOISE_ON:02X}"]
    for i, t in enumerate(tunes):
        lines.append(f"TUNE_{t['name'].upper()} equ {i}")
    for i, e in enumerate(effects):
        lines.append(f"SFX_{e['name'].upper()} equ {i + 1}")      # 0 = no request
    lines.append("note_periods:                       ; note 1 = C2")
    p = periods()
    for i in range(0, len(p), 12):
        lines.append("                defw " + ",".join(str(v) for v in p[i:i + 12]))
    lines.append("tune_table:                         ; channel A, channel B")
    for t in tunes:
        lines.append(f"                defw tune_{t['name']}_a,tune_{t['name']}_b")
    for t in tunes:
        end = TUNE_LOOP if t["loop"] else TUNE_STOP
        for ch in CHANNELS:
            lines.append(f"tune_{t['name']}_{ch.lower()}:")
            events = t["streams"][ch]
            for i in range(0, len(events), 8):
                lines.append("                defb " + ",".join(f"{n},{d}" for n, d in events[i:i + 8]))
            lines.append(f"                defb #{end:02X}")
    lines.append("sfx_table:                          ; steps, priority")
    for e in effects:
        lines.append(f"                defw sfx_steps_{e['name']}")
        lines.append(f"                defb {e['prio']}")
    for e in effects:
        lines.append(f"sfx_steps_{e['name']}:")
        for period, volume, noise in e["steps"]:
            lines.append(f"                defw {period}")
            lines.append(f"                defb #{volume:02X},{noise}")
        lines.append(f"                defw 0")
        lines.append(f"                defb #{SFX_END:02X},0")
    return "\n".join(lines) + "\n"


def main():
    try:
        tunes, effects = load_all()
    except MusicError as e:
        print(f"mkmusic: {e}", file=sys.stderr)
        return 1
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    source = asm_source(tunes, effects)
    with open(OUT, "w") as f:
        f.write(source)
    events = sum(len(s) for t in tunes for s in t["streams"].values())
    print(f"music      {len(tunes):3d} tunes {events:4d} notes, {len(effects)} effects -> "
          f"{os.path.relpath(OUT, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
