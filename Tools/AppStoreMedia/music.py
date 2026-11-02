#!/usr/bin/env python3
"""Writes the music bed for the App Preview.

    Tools/AppStoreMedia/music.py <out.wav> [seconds]

Wordwander ships with no audio files: its letter, word and reward sounds are
synthesised on the device, so there is no track in the bundle to put under the
preview. App Store Connect nevertheless *requires* stereo AAC at 256 kbps on an
App Preview, and a silent track does not satisfy it — AAC compresses digital
silence to about 2 kbps, two orders of magnitude under the rate asked for, and
Connect reports a file with no usable audio as an unsupported audio
configuration. So the bed is synthesised here and looped under the cut by
Tools/AppStoreMedia/conform.swift.

Stdlib only (`wave`, `math`, `random`) so it runs on a stock macOS Python. The
instrument is the Sudoku project's (github.com/RobertLib/sudoku), which is the
chess project's; only the harmony and the tune are this game's.

What it plays: IV-V-iii-vi in F major at 72 BPM — struck felt-piano notes over a
sustained open fifth, no percussion. The progression never lands on the tonic,
which is what makes it feel like travelling rather than arriving, and a few
pentatonic notes wander above it the way the game wanders through its
landscapes. Mixed quiet and dull on purpose: the crossword filling in is what
the preview is about.
"""

import math
import random
import struct
import sys
import wave

RATE = 48_000
CHANNELS = 2
BPM = 72.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT

# IV-V-iii-vi in F major, one chord per bar. Semitones from A0 (27.5 Hz), so the
# root sits where a bass actually plays.
A0 = 27.5
PROGRESSION = [
    (25, [37, 41, 44, 49]),  # Bb    Bb3 D4 F4 Bb4
    (27, [39, 43, 46, 51]),  # C     C4 E4 G4 C5
    (24, [36, 39, 43, 48]),  # Am    A3 C4 E4 A4
    (29, [41, 44, 48, 53]),  # Dm    D4 F4 A4 D5
]

# The tune: F-major pentatonic notes above the chords, (beat in the bar, semitone).
# One phrase per bar, so it answers the chord rather than leading it.
TUNE = [
    [(1.0, 56), (2.5, 53)],   # over Bb:  F5  D5
    [(1.0, 58), (2.5, 56)],   # over C:   G5  F5
    [(1.0, 51), (2.0, 53)],   # over Am:  C5  D5
    [(1.5, 48), (2.5, 51)],   # over Dm:  A4  C5
]

# The drone: the tonic and its fifth, held under everything. Two octaves below
# the voicings, so it reads as the room rather than as a part.
DRONE = [20, 27]  # F2, C3


def hz(semitone: float) -> float:
    return A0 * 2 ** (semitone / 12.0)


def felt(t: float, freq: float) -> float:
    """One struck note: a soft hammer over a long decay.

    A felt-covered hammer is mostly fundamental — the upper partials are there
    for the first fraction of a second and then gone, which is the difference
    between this and a bright nylon pluck. The slight detune on the second
    partial is what keeps it from sounding like an organ.
    """
    if t < 0:
        return 0.0
    attack = min(1.0, t / 0.014)
    body = math.exp(-t * 0.62)
    edge = math.exp(-t * 5.5)
    w = 2 * math.pi * freq * t
    return attack * (
        body * math.sin(w)
        + 0.16 * edge * math.sin(2 * w * 1.002)
        + 0.05 * math.exp(-t * 11.0) * math.sin(3 * w)
    )


def pad(t: float, freq: float, length: float) -> float:
    """A breathing chord underneath: two detuned sines that swell and fall."""
    if t < 0 or t > length:
        return 0.0
    env = math.sin(math.pi * t / length) ** 1.6
    w = 2 * math.pi * freq * t
    return env * (math.sin(w) + 0.5 * math.sin(w * 1.0035 + 0.6))


def drone(t: float, freq: float, length: float) -> float:
    """A held low note with a slow tremolo, so it moves without arriving."""
    if t < 0 or t > length:
        return 0.0
    # Only the ends are shaped; the middle just sits there, which is the point.
    env = min(1.0, t / 2.5) * min(1.0, max(0.0, (length - t) / 2.5))
    w = 2 * math.pi * freq * t
    breath = 1.0 + 0.12 * math.sin(2 * math.pi * 0.13 * t)
    return env * breath * (math.sin(w) + 0.22 * math.sin(2 * w))


def render(seconds: float, seed: int = 20261102):
    """Returns interleaved float samples for `seconds` of music."""
    jitterer = random.Random(seed)
    total = int(seconds * RATE)
    left = [0.0] * total
    right = [0.0] * total

    def add(start: float, dur: float, gen, gain: float, pan: float):
        """Mixes one voice in. `pan` is -1 hard left, +1 hard right."""
        i0 = max(0, int(start * RATE))
        i1 = min(total, int((start + dur) * RATE))
        gl = gain * math.sqrt((1.0 - pan) / 2.0)
        gr = gain * math.sqrt((1.0 + pan) / 2.0)
        # A voice cut off mid-swing clicks; its last 40 ms fade out instead.
        release = max(1, min(int(0.04 * RATE), i1 - i0))
        for i in range(i0, i1):
            value = gen((i - start * RATE) / RATE) * min(1.0, (i1 - i) / release)
            left[i] += value * gl
            right[i] += value * gr

    # The drone runs the whole length rather than being restruck each bar: a
    # bass that re-attacks on every chord turns into a pulse, and this bed is
    # deliberately without one.
    for semitone in DRONE:
        add(0.0, seconds, lambda t, f=hz(semitone): drone(t, f, seconds), 0.26, 0.0)

    bar = 0
    while bar * BAR < seconds:
        root, voicing = PROGRESSION[bar % len(PROGRESSION)]
        t0 = bar * BAR

        # The chord's own root, struck once on the downbeat an octave under the
        # voicing. Quiet: the drone is already holding the bottom of the mix.
        add(t0, BAR, lambda t, f=hz(root): felt(t, f), 0.15, 0.0)

        # The pad: the same voicing an octave down, swelling across the bar.
        for semitone in voicing:
            add(t0, BAR, lambda t, f=hz(semitone - 12): pad(t, f, BAR), 0.04, 0.0)

        # The chord, rolled upwards across the first beat and the stereo field.
        # Each note is a little late and a little uneven, so the loop point does
        # not stand out as a mechanical repeat.
        for index, semitone in enumerate(voicing):
            pan = -0.5 + index * (1.0 / max(1, len(voicing) - 1))
            at = t0 + index * BEAT * 0.25 + jitterer.uniform(-0.015, 0.015)
            level = 0.14 * (1.0 + jitterer.uniform(-0.1, 0.1))
            add(at, BAR, lambda t, f=hz(semitone): felt(t, f), level, pan)

        # The tune, high and to one side.
        for beat, semitone in TUNE[bar % len(TUNE)]:
            at = t0 + beat * BEAT + jitterer.uniform(-0.02, 0.02)
            add(at, 2.2 * BEAT, lambda t, f=hz(semitone): felt(t, f), 0.07, 0.3)

        bar += 1

    # Soft-knee limiter, then a fade at both ends so the loop join is inaudible.
    peak = max(1e-6, max(max(abs(v) for v in left), max(abs(v) for v in right)))
    scale = 0.70 / peak
    fade = int(0.4 * RATE)
    out = []
    for i in range(total):
        env = 1.0
        if i < fade:
            env = i / fade
        elif i > total - fade:
            env = max(0.0, (total - i) / fade)
        out.append(math.tanh(left[i] * scale) * env)
        out.append(math.tanh(right[i] * scale) * env)
    return out


def main() -> int:
    if not 2 <= len(sys.argv) <= 3:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    path = sys.argv[1]
    # Eight bars is two turns of the progression; conform loops it to the cut's
    # length, so the default only has to be long enough not to loop audibly often.
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 8 * BAR

    samples = render(seconds)
    with wave.open(path, "wb") as f:
        f.setnchannels(CHANNELS)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(
            struct.pack("<h", max(-32768, min(32767, int(v * 32767)))) for v in samples))
    print(f"→ {path}  {seconds:.1f}s  {RATE} Hz stereo")
    return 0


if __name__ == "__main__":
    sys.exit(main())
