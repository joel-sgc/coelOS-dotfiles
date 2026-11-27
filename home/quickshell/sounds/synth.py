#!/usr/bin/env python3
"""Synthesize coelOS's UI sound pack (pure Python, deterministic).

    python3 home/quickshell/sounds/synth.py                  write the pack
    python3 home/quickshell/sounds/synth.py --play           write it, play all
    python3 home/quickshell/sounds/synth.py --play lock ...  write it, play some

Writes 48 kHz mono 16-bit WAVs into ../assets/sounds/synth/, one file per
event. A pack is just a folder of these names, so another one (e.g. a CC0
download, converted to WAV) replaces this by providing the same file names;
any it lacks fall back to these.

Events:
  volume-0 .. volume-100 tick per 5% volume step (volume-0, volume-5, ...), pitch
                         rising with the level. A pack may instead give one
                         volume.wav for every step.
  toggle-on, toggle-off  switch clack (on is brighter than off)
  launcher               launcher open tick
  lock, unlock           lock thunk / lighter two-step release
  chime                  the one tonal sound: print finished
  alert                  island interrupt tier (print failed, class starting, ...)
"""

import math
import os
import random
import struct
import subprocess
import sys
import time
import wave

RATE = 48000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds", "synth")


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def offset(track, seconds):
    return silence(seconds) + track


def damped(freq, decay, length, amp=1.0, sweep=0.0, phase=0.0, attack=0.0005):
    """A sine at `freq` Hz decaying with time constant `decay` s; `sweep`
    multiplies the frequency over the length (e.g. -0.3 drops 30%). `attack`
    is a linear fade-in (s): tonal sounds need a few ms or their start clicks."""
    out = []
    ph = phase
    n = int(RATE * length)
    for i in range(n):
        t = i / RATE
        f = freq * (1 + sweep * t / length)
        ph += 2 * math.pi * f / RATE
        env = min(1.0, t / attack) if attack else 1.0
        env *= min(1.0, (n - i) / (0.2 * n))   # fade the last 20%: no cut-off tick
        out.append(amp * env * math.exp(-t / decay) * math.sin(ph))
    return out


def noise_burst(length, decay, amp=1.0, seed=1, smooth=0.0):
    """Decaying white noise; `smooth` (0..1) is a one-pole lowpass amount."""
    rnd = random.Random(seed)
    out = []
    prev = 0.0
    for i in range(int(RATE * length)):
        t = i / RATE
        x = rnd.uniform(-1, 1)
        prev = smooth * prev + (1 - smooth) * x
        out.append(amp * math.exp(-t / decay) * prev)
    return out


def highpass(track, amount=0.97):
    out, prev_x, prev_y = [], 0.0, 0.0
    for x in track:
        y = amount * (prev_y + x - prev_x)
        out.append(y)
        prev_x, prev_y = x, y
    return out


def fade_edges(track, ms=2.0):
    n = min(len(track) // 2, int(RATE * ms / 1000))
    track = list(track)
    for i in range(n):
        track[i] *= i / n
    for i in range(n):
        track[-1 - i] *= i / n
    return track


def normalize(track, peak_db):
    peak = max(abs(v) for v in track) or 1.0
    gain = 10 ** (peak_db / 20) / peak
    return [v * gain for v in track]


def write(name, track, peak_db):
    track = normalize(fade_edges(track), peak_db)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in track))
    return path


# ---- the sounds ----------------------------------------------------------

def tick(pitch):
    # A small detent: a bright click on a short woody body.
    body = mix(damped(pitch, 0.006, 0.04), damped(pitch * 2.76, 0.003, 0.03, 0.4))
    click = highpass(noise_burst(0.01, 0.0015, 0.7, seed=3))
    return mix(click, body)


def clack(bright):
    # Two contacts a few ms apart (a switch's lever, then its seat).
    base = 1900 if bright else 1300
    first = mix(highpass(noise_burst(0.02, 0.002, 0.9, seed=5)), damped(base, 0.008, 0.05, 0.8))
    second = mix(highpass(noise_burst(0.02, 0.0015, 0.5, seed=7)), damped(base * 1.5, 0.005, 0.04, 0.5))
    return mix(first, offset(second, 0.014))


def launcher():
    # Lighter and airier than a tick: a quick upward flick.
    return mix(highpass(noise_burst(0.03, 0.004, 0.6, seed=11, smooth=0.3)),
               damped(2300, 0.01, 0.06, 0.7, sweep=0.25))


def lock():
    # A solid thunk: low body dropping in pitch, a muffled contact on top.
    body = damped(110, 0.06, 0.25, 1.0, sweep=-0.35)
    knock = damped(420, 0.012, 0.08, 0.5, sweep=-0.2)
    contact = noise_burst(0.05, 0.006, 0.5, seed=13, smooth=0.6)
    return mix(body, knock, contact)


def unlock():
    # Release: two light clicks rising, the second one higher.
    a = mix(damped(700, 0.012, 0.08, 0.8), noise_burst(0.02, 0.003, 0.4, seed=17, smooth=0.5))
    b = mix(damped(1050, 0.012, 0.08, 0.8), noise_burst(0.02, 0.003, 0.4, seed=19, smooth=0.5))
    return mix(a, offset(b, 0.07))


def chime():
    # A small bell: inharmonic partials, long gentle decay. Two strikes, a fifth up.
    def bell(f):
        a = 0.004
        return mix(damped(f, 0.6, 1.6, 1.0, attack=a), damped(f * 2.0, 0.35, 1.2, 0.35, attack=a),
                   damped(f * 2.76, 0.2, 0.9, 0.25, attack=a), damped(f * 5.4, 0.08, 0.4, 0.12, attack=a))
    return mix(bell(880), offset(bell(1318.5), 0.14))


def alert():
    # Wants attention without alarm: two quick firm pings, a step up.
    def ping(f):
        return mix(damped(f, 0.07, 0.25, 1.0, attack=0.003), damped(f * 3, 0.03, 0.15, 0.3, attack=0.003))
    return mix(ping(740), offset(ping(988), 0.11))


def build():
    os.makedirs(OUT, exist_ok=True)
    out = []
    for pct in range(0, 101, 5):
        # Rising in pitch over about an octave and a half (900 Hz -> 2.5 kHz).
        out.append(write(f"volume-{pct}", tick(900 * 2 ** (1.5 * pct / 100)), -9))
    out.append(write("toggle-on", clack(True), -8))
    out.append(write("toggle-off", clack(False), -8))
    out.append(write("launcher", launcher(), -12))
    out.append(write("lock", lock(), -6))
    out.append(write("unlock", unlock(), -9))
    out.append(write("chime", chime(), -10))
    out.append(write("alert", alert(), -8))
    return out


if __name__ == "__main__":
    paths = build()
    print(f"wrote {len(paths)} sounds to {os.path.normpath(OUT)}")
    if "--play" in sys.argv:
        wanted = sys.argv[sys.argv.index("--play") + 1:]
        for p in paths:
            name = os.path.basename(p)[:-4]
            if wanted and name not in wanted:
                continue
            print(name)
            subprocess.run(["pw-play", p], check=False)
            time.sleep(0.25)
