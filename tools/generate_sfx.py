#!/usr/bin/env python3
"""Generates every sound effect in audio/sfx/ from code.

Run from the project root:  python3 tools/generate_sfx.py
Pure standard library (no numpy). Output: 44.1 kHz, 16-bit mono WAV.
Each sound is a small "recipe" below. Tweak a recipe, re-run, and Godot re-imports the file.
"""
import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio", "sfx")


# --- Building blocks -------------------------------------------------------

def _osc(kind, phase):
    p = phase % 1.0
    if kind == "sine":
        return math.sin(2 * math.pi * p)
    if kind == "square":
        return 1.0 if p < 0.5 else -1.0
    if kind == "tri":
        return 4.0 * abs(p - 0.5) - 1.0
    return 2.0 * p - 1.0  # saw


def tone(dur, f0, f1=None, kind="square", attack=0.003, decay=2.0, vibrato=0.0, vib_rate=0.0, lowpass=1.0):
    """A pitched blip. Pitch glides exponentially from f0 to f1; amplitude decays as (1-t)^decay."""
    f1 = f0 if f1 is None else f1
    n = int(dur * SR)
    out, phase, y = [], 0.0, 0.0
    for i in range(n):
        t = i / n
        f = f0 * (f1 / f0) ** t
        if vibrato:
            f *= 1.0 + vibrato * math.sin(2 * math.pi * vib_rate * i / SR)
        phase += f / SR
        env = min(1.0, i / (attack * SR + 1)) * (1.0 - t) ** decay
        y += lowpass * (_osc(kind, phase) - y)
        out.append(y * env)
    return out


def noise(dur, attack=0.002, decay=2.0, lowpass=(1.0, 1.0)):
    """Filtered noise. `lowpass` sweeps a one-pole filter coefficient from start to end (1 = open)."""
    n = int(dur * SR)
    out, y = [], 0.0
    for i in range(n):
        t = i / n
        a = lowpass[0] + (lowpass[1] - lowpass[0]) * t
        y += a * (random.uniform(-1.0, 1.0) - y)
        env = min(1.0, i / (attack * SR + 1)) * (1.0 - t) ** decay
        out.append(y * env)
    return out


def swell(dur, f0, f1, kind="sine", lowpass=1.0):
    """Rises in pitch and volume, then cuts off: used for charge-ups."""
    n = int(dur * SR)
    out, phase, y = [], 0.0, 0.0
    for i in range(n):
        t = i / n
        f = f0 * (f1 / f0) ** t
        phase += f / SR
        env = (t ** 1.5) * min(1.0, (1.0 - t) * 40.0)
        y += lowpass * (_osc(kind, phase) - y)
        out.append(y * env)
    return out


def mix(*layers):
    """layers: (samples, gain, start_seconds)"""
    length = max(int(start * SR) + len(s) for s, _, start in layers)
    out = [0.0] * length
    for samples, gain, start in layers:
        o = int(start * SR)
        for i, v in enumerate(samples):
            out[o + i] += v * gain
    return out


def write(name, samples, peak=0.85):
    top = max(1e-9, max(abs(v) for v in samples))
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for v in samples:
            v = math.tanh(1.2 * v / top) / math.tanh(1.2) * peak  # gentle saturation
            frames += struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767))
        w.writeframes(bytes(frames))


# --- Recipes ---------------------------------------------------------------

def recipes():
    return {
        # Player movement
        "jump": mix((tone(0.11, 330, 700, "square", lowpass=0.3), 0.6, 0)),
        "double_jump": mix((tone(0.16, 520, 1180, "tri"), 0.7, 0), (tone(0.12, 1040, 2100, "sine"), 0.25, 0.03)),
        "land": mix((noise(0.09, decay=3, lowpass=(0.35, 0.05)), 1.0, 0), (tone(0.1, 140, 50, "sine"), 0.8, 0)),
        "wall_touch": mix((noise(0.05, decay=3, lowpass=(0.5, 0.1)), 0.7, 0), (tone(0.05, 220, 120, "tri"), 0.4, 0)),
        "drop": mix((tone(0.09, 500, 260, "tri"), 0.5, 0)),
        "dash": mix((noise(0.17, attack=0.01, decay=1.6, lowpass=(0.9, 0.08)), 1.0, 0), (tone(0.12, 900, 300, "sine"), 0.25, 0)),
        "dash_ready": mix((tone(0.06, 1600, 1900, "sine", decay=3), 0.5, 0)),
        # Player combat
        "swing": mix((noise(0.08, attack=0.004, decay=2.2, lowpass=(0.95, 0.25)), 1.0, 0)),
        "hit": mix((tone(0.1, 260, 70, "square", lowpass=0.4), 0.9, 0), (noise(0.06, decay=3, lowpass=(1.0, 0.3)), 0.8, 0)),
        "pogo": mix((tone(0.13, 320, 760, "tri"), 0.8, 0), (noise(0.04, decay=3), 0.3, 0)),
        "deflect": mix((tone(0.08, 1500, 2300, "tri", decay=3), 0.6, 0), (tone(0.08, 3000, 3400, "sine", decay=3), 0.25, 0)),
        "charge_ready": mix((tone(0.18, 880, 880, "sine", decay=2.5), 0.6, 0), (tone(0.18, 1320, 1320, "sine", decay=2.5), 0.4, 0.04)),
        "charge_max": mix(*[(tone(0.14, f, f, "tri", decay=2), 0.5, i * 0.045) for i, f in enumerate([660, 880, 1320, 1760])]),
        "shot": mix((tone(0.13, 1100, 280, "square", lowpass=0.35), 0.8, 0)),
        "shot_big": mix((tone(0.28, 700, 110, "square", lowpass=0.3), 0.9, 0), (noise(0.2, decay=2, lowpass=(0.8, 0.05)), 0.7, 0)),
        "fizzle": mix((noise(0.1, decay=2, lowpass=(0.3, 0.05)), 0.5, 0)),
        # Health
        "hurt": mix((tone(0.28, 420, 110, "square", vibrato=0.08, vib_rate=40, lowpass=0.35), 0.8, 0),
                    (noise(0.12, decay=2, lowpass=(1.0, 0.2)), 0.8, 0)),
        "heal_charge": mix((swell(1.3, 220, 660, "tri", lowpass=0.5), 0.7, 0), (swell(1.3, 440, 1320, "sine"), 0.3, 0)),
        "heal_done": mix(*[(tone(0.7, f, f, "sine", decay=2.5), 0.4, i * 0.03) for i, f in enumerate([523, 659, 784, 1047, 1568])]),
        "heal_gain": mix((tone(0.2, 784, 1175, "sine", decay=2), 0.5, 0), (tone(0.2, 1175, 1568, "sine", decay=2), 0.3, 0.06)),
        "player_death": mix((tone(0.9, 600, 55, "square", lowpass=0.25), 0.8, 0), (noise(0.6, decay=1.5, lowpass=(0.6, 0.02)), 0.8, 0)),
        # Boss
        "boss_telegraph": mix((swell(0.45, 90, 220, "saw", lowpass=0.12), 1.0, 0)),
        "boss_shot": mix((tone(0.1, 520, 210, "square", lowpass=0.3), 0.7, 0)),
        "boss_ring": mix((tone(0.3, 300, 80, "saw", lowpass=0.15), 0.9, 0), (noise(0.2, decay=2, lowpass=(0.6, 0.05)), 0.6, 0)),
        "boss_lunge": mix((noise(0.35, attack=0.02, decay=1.2, lowpass=(0.15, 0.6)), 1.0, 0), (tone(0.3, 70, 140, "saw", lowpass=0.1), 0.6, 0)),
        "boss_hit": mix((tone(0.08, 180, 70, "square", lowpass=0.3), 0.8, 0), (noise(0.07, decay=3, lowpass=(0.9, 0.2)), 0.9, 0)),
        "wall_slam": mix((tone(0.3, 110, 38, "sine"), 1.0, 0), (noise(0.25, decay=2, lowpass=(0.4, 0.02)), 0.9, 0)),
        "slam": mix((tone(0.5, 90, 30, "sine"), 1.0, 0), (noise(0.4, decay=1.8, lowpass=(0.5, 0.02)), 1.0, 0),
                    (tone(0.2, 220, 60, "square", lowpass=0.2), 0.4, 0)),
        "boss_rise": mix((swell(0.5, 120, 480, "tri", lowpass=0.4), 0.8, 0)),
        "phase_shift": mix((swell(0.9, 55, 220, "saw", lowpass=0.1), 1.0, 0), (noise(0.8, attack=0.3, decay=1, lowpass=(0.05, 0.4)), 0.6, 0),
                           (tone(1.0, 110, 55, "sine", decay=1.5), 0.6, 0.85)),
        "boss_death": mix((tone(1.6, 120, 25, "sine", decay=1.2), 1.0, 0), (noise(1.5, decay=1.3, lowpass=(0.7, 0.01)), 1.0, 0),
                          *[(tone(0.5, f, f * 0.5, "tri", decay=2), 0.3, 0.2 + i * 0.12) for i, f in enumerate([880, 660, 440])]),
        "fan": mix((tone(0.16, 640, 190, "square", lowpass=0.3), 0.8, 0), (noise(0.1, decay=2.5, lowpass=(0.8, 0.1)), 0.5, 0)),
        "needle": mix((tone(0.14, 2200, 800, "sine", decay=1.5), 0.6, 0), (noise(0.05, decay=3, lowpass=(1.0, 0.5)), 0.2, 0)),
        "summon": mix((swell(0.6, 80, 330, "saw", lowpass=0.12), 1.0, 0), (tone(0.4, 660, 330, "tri", decay=2), 0.4, 0.5)),
        # Minions
        "minion_spawn": mix((tone(0.25, 300, 900, "tri", lowpass=0.5), 0.7, 0)),
        "minion_hop": mix((tone(0.08, 200, 420, "tri", decay=2.5), 0.7, 0)),
        "minion_death": mix((tone(0.18, 500, 80, "square", lowpass=0.35), 0.8, 0), (noise(0.14, decay=2, lowpass=(1.0, 0.15)), 0.8, 0)),
        "victory": mix(*[(tone(0.5, f, f, "tri", decay=2), 0.4, i * 0.11) for i, f in enumerate([523, 659, 784, 1047])]),
    }


if __name__ == "__main__":
    random.seed(7)  # deterministic output so regenerating doesn't churn git
    os.makedirs(OUT, exist_ok=True)
    for name, samples in recipes().items():
        write(name, samples)
        print(f"  {name}.wav  ({len(samples) / SR:.2f}s)")
