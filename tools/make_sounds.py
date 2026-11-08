#!/usr/bin/env python3
"""Synthesises the game's sound effects into ../assets/sfx (16-bit mono WAV).

Needs numpy:   python3 tools/make_sounds.py

Each impact is modelled physically: a contact force pulse (a half sine whose length
sets how hard the contact is: ivory on wood is a fraction of a millisecond, a die
landing on leather is a couple of milliseconds) excites a set of exponentially
decaying resonant modes of the two objects, plus a short broadband contact noise.
Several random variants of every sound are written so repeats never sound identical.
"""
import os
import wave
import zlib

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
os.makedirs(OUT, exist_ok=True)
BEAM = [1.0, 2.756, 5.404, 8.933, 13.34]          # free-free beam (plank) mode ratios
PLATE = [1.0, 1.59, 2.14, 2.65, 3.17, 3.9, 4.6]   # rough thin-plate mode ratios


def taxis(dur):
    return np.arange(int(dur * SR)) / SR


def modes(dur, freqs, taus, amps):
    t = taxis(dur)
    y = np.zeros_like(t)
    for f, tau, a in zip(freqs, taus, amps):
        if f < SR * 0.45:
            y += a * np.exp(-t / tau) * np.sin(2 * np.pi * f * t)
    return y


def q_tau(f, q):
    """Decay time constant of a mode with quality factor q."""
    return q / (np.pi * f)


def contact(y, tc):
    """Convolve with a half-sine force pulse of length tc seconds (softer = longer)."""
    n = max(1, int(tc * SR))
    k = np.sin(np.pi * (np.arange(n) + 0.5) / n)
    return np.convolve(y, k / k.sum())[: len(y)]


def band(y, lo=None, hi=None, order=2):
    f = np.fft.rfftfreq(len(y), 1 / SR)
    g = np.ones_like(f)
    if hi:
        g /= np.sqrt(1 + (f / hi) ** (2 * order))
    if lo:
        g /= np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    return np.fft.irfft(np.fft.rfft(y) * g, n=len(y))


def burst(rng, dur, tau, lo=None, hi=None):
    t = taxis(dur)
    return band(rng.standard_normal(len(t)) * np.exp(-t / tau), lo, hi)


def fade(y, ms=4):
    n = int(ms * SR / 1000)
    y[-n:] *= np.linspace(1, 0, n)
    return y


def save(name, y, peak=0.9):
    y = fade(y.copy())
    y = y / (np.abs(y).max() + 1e-9) * peak
    data = (np.clip(y, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def jit(rng, xs, amt):
    return [x * rng.uniform(1 - amt, 1 + amt) for x in xs]


# ------------------------------------------------------------------ dice
def ivory(rng, dur):
    """Ring of a small bone/ivory die: high, very short modes."""
    fs = jit(rng, [4300, 6100, 8200, 10900, 13500], 0.12)
    return modes(dur, fs, [q_tau(f, rng.uniform(35, 70)) for f in fs], [1, 0.8, 0.6, 0.4, 0.25])


def die_wall(rng):
    """Die striking the thick wooden rim: a short, solid "tock". The rim is a heavy
    plank sitting in sand, so its modes are strongly damped (low Q) - no boxy ring."""
    dur = 0.14
    f0 = rng.uniform(380, 480)
    fs = jit(rng, [f0, f0 * 1.9, f0 * 2.9, f0 * 4.2, f0 * 5.6], 0.06)
    taus = [q_tau(f, rng.uniform(5, 9)) for f in fs]
    wood = modes(dur, fs, taus, [1.0, 0.8, 0.55, 0.35, 0.2])
    y = contact(wood, rng.uniform(0.00025, 0.00035))
    y += 0.15 * contact(ivory(rng, dur), 0.0001)
    y += 0.45 * burst(rng, dur, 0.0009, lo=600, hi=5000)
    # weight of the die itself: a short low push under the knock
    y += 0.5 * contact(modes(dur, [140], [0.006], [1.0]), 0.002)
    return band(y, lo=70)


def die_floor(rng):
    """Die dropping onto leather laid over solid wood bedded in sand: a dead, heavy
    thud with almost no resonance, and a soft leathery slap on top."""
    dur = 0.12
    f0 = rng.uniform(110, 150)
    fs = jit(rng, [f0, f0 * 2.1, f0 * 3.4, f0 * 5.2], 0.08)
    taus = [q_tau(f, rng.uniform(2.5, 4.5)) for f in fs]
    y = contact(modes(dur, fs, taus, [1.0, 0.7, 0.45, 0.25]), rng.uniform(0.0016, 0.0024))
    y += 0.6 * burst(rng, dur, 0.0018, lo=250, hi=2200)       # leather slap
    y += 0.05 * contact(ivory(rng, dur), 0.0003)
    return band(y, lo=55, hi=4000)


def die_die(rng):
    """Two ivory dice knocking together: a bright, dry click."""
    dur = 0.08
    y = contact(ivory(rng, dur) + 0.7 * ivory(rng, dur), 0.00005)
    y += 0.35 * burst(rng, dur, 0.00035, lo=2500)
    return y


def dice_shake(rng):
    """Four dice rattled in cupped hands before the throw (~0.5 s)."""
    dur = 0.62
    n = len(taxis(dur))
    y = np.zeros(n)
    # two shakes; dice bunch up at each reversal
    for centre, spread, count in ((0.07, 0.05, 6), (0.24, 0.05, 7), (0.40, 0.06, 7)):
        for _ in range(count):
            at = int(np.clip(rng.normal(centre, spread), 0.0, dur - 0.1) * SR)
            c = die_die(rng) * rng.uniform(0.25, 1.0)
            y[at: at + len(c)] += c[: n - at]
        at = int(centre * SR)
        thump = burst(rng, 0.08, 0.012, lo=60, hi=350) * 0.8   # palms
        y[at: at + len(thump)] += thump[: n - at]
    y = band(y, hi=6500)  # cupped hands muffle the top end
    y += 0.02 * band(rng.standard_normal(n), lo=1500, hi=6000) * np.exp(-((taxis(dur) - 0.25) / 0.2) ** 2)
    return y


# ----------------------------------------------------------------- stones
def stone_ring(rng, dur, q=(40, 90)):
    fs = jit(rng, [2100, 3050, 4400, 5900, 7600], 0.12)
    return modes(dur, fs, [q_tau(f, rng.uniform(*q)) for f in fs], [1, 0.75, 0.55, 0.35, 0.2])


def stone_tap(rng, dur, hard=1.0):
    """One stone-on-hardwood contact: a crisp "tok". Stone is far harder than wood,
    so the contact is short and the sound is mostly the wood's local surface modes
    (mid-high, quickly damped), the pebble's own brief ring and a dry click.
    The whole board only adds a faint, short low body - it lies in sand."""
    local = jit(rng, [900, 1350, 1900, 2600, 3400], 0.12)
    y = modes(dur, local, [q_tau(f, rng.uniform(9, 16)) for f in local], [1.0, 0.9, 0.7, 0.45, 0.3])
    body = jit(rng, [240, 390, 560], 0.1)
    y += modes(dur, body, [q_tau(f, rng.uniform(4, 7)) for f in body], [0.35, 0.3, 0.25])
    y = contact(y, rng.uniform(0.00012, 0.00018) / hard)
    y += 0.3 * contact(stone_ring(rng, dur, (18, 32)), 0.00008)
    y += 0.4 * burst(rng, dur, 0.0004, lo=1800, hi=12000)
    return y


def stone_place(rng):
    """Stone set down on the wooden board. A pebble is never perfectly flat, so it
    often rocks and settles with one or two smaller taps just after the first."""
    dur = 0.2
    n = len(taxis(dur))
    y = stone_tap(rng, dur)
    at = 0
    for k in range(rng.choice([0, 1, 1, 2])):
        at += int(rng.uniform(0.012, 0.03) * SR)
        t2 = stone_tap(rng, dur, hard=0.8) * rng.uniform(0.15, 0.35) / (k + 1)
        y[at:] += t2[: n - at]
    return band(y, lo=150)


def stone_stone(rng):
    """Stone knocking against stone: a sharp clack that rings briefly."""
    dur = 0.3
    y = contact(stone_ring(rng, dur) + 0.6 * stone_ring(rng, dur), 0.00009)
    y += 0.3 * burst(rng, dur, 0.0004, lo=1800)
    y += 0.35 * contact(modes(dur, [170, 270, 360], [0.02, 0.014, 0.01], [1, 0.7, 0.5]), 0.0004)
    return y


def stone_lift(rng):
    """Stone picked up off the board: almost silent in reality - fingertips close on
    it and it leaves the wood with a tiny soft tick. No scraping."""
    dur = 0.08
    y = 0.6 * burst(rng, dur, 0.004, lo=200, hi=1200)                   # fingertips on stone
    at = int(rng.uniform(0.012, 0.025) * SR)
    tick = contact(modes(dur, jit(rng, [700, 1100, 1600], 0.1), [0.004, 0.003, 0.002], [1, 0.6, 0.3]), 0.0006)
    y[at:] += 0.5 * tick[: len(y) - at]
    return band(y, lo=150, hi=2500)


G_GRIT = 1.1       # how much of the dry grain of the catches is heard, against the wood


def stone_slide(rng):
    """A pebble pushed along the old wooden board (2.4 s, played for as long as the slide
    lasts; the game swells and fades it with the stone's speed). Rough stone dragged over
    wood is a dry, low grinding rumble, not a hiss: it sticks and slips, many hundreds of
    tiny catches a second, bunched where the grain is rougher, and each catch knocks the
    board's low, heavily damped wood modes (it lies in sand, so nothing rings on). The
    stone's own ring barely shows, and above ~2 kHz there is almost nothing."""
    dur = 2.4
    t = taxis(dur)
    n = len(t)
    # roughness of the wood under the stone as it travels: slow, uneven swells
    rough = band(rng.standard_normal(n), hi=14, order=2)
    rough = np.clip(0.55 + rough / (np.abs(rough).max() + 1e-9) * 0.45, 0.1, 1.0)
    # stick-slip catches: a Poisson train, denser and harder where it is rough
    rate = rng.uniform(180, 260) * (0.6 + 0.9 * rough)
    imp = np.zeros(n)
    hits = rng.random(n) < rate / SR
    imp[hits] = rng.lognormal(0.0, 0.55, hits.sum()) * rough[hits]
    # the wood answers each catch: low local modes, heavily damped
    wood = jit(rng, [210, 330, 470, 640, 880, 1150], 0.1)
    k = modes(0.04, wood, [q_tau(f, rng.uniform(4, 8)) for f in wood], [0.45, 0.75, 1.0, 0.95, 0.7, 0.45])
    k += 0.12 * stone_ring(rng, 0.04, (6, 10))[: len(k)]
    k = contact(k, 0.00035)           # rough stone on old wood: a blunt contact
    catches = np.convolve(imp, k)[:n]
    # the continuous rub underneath: a low rough rumble
    rub = band(rng.standard_normal(n), lo=70, hi=520, order=3) * (0.4 + 0.6 * rough)
    # and each catch is itself a tiny dry "tk" as the stone's grit lets go: the grain
    # of the sound, a little brighter than the wood but still well short of a squeak
    tk = burst(rng, 0.004, 0.0006, lo=600, hi=2000)
    grit = np.convolve(imp, tk)[:n]
    y = (catches / (np.abs(catches).max() + 1e-9) + G_GRIT * grit / (np.abs(grit).max() + 1e-9)
         + 0.3 * rub / (np.abs(rub).max() + 1e-9))
    y = band(y, lo=80, hi=2300, order=4)   # nothing shrill
    y *= np.clip(t / 0.03, 0, 1) * np.clip((dur - t) / 0.05, 0, 1)
    return y


# ------------------------------------------------------------------ dates
def date_pick(rng):
    """A date taken out of the earthen bowl: fingertips press into soft, sticky skin
    (nothing to hear but a faint tacky "tk" as it lets go of the one beside it), the
    dates under it shift a little against each other, a dull, soft knock, and the odd
    one touches the clay: a tiny low "tok" of thick, porous earthenware, quickly dead."""
    dur = 0.3
    t = taxis(dur)
    y = 0.35 * burst(rng, dur, 0.03, lo=250, hi=1800) * np.clip(t / 0.01, 0, 1)        # skins rubbing
    at = int(rng.uniform(0.01, 0.03) * SR)
    tack = burst(rng, dur, 0.0015, lo=900, hi=4000)
    y[at:] += 0.45 * tack[: len(y) - at]                                              # sticky skin letting go
    for k in range(rng.choice([1, 2])):                                               # soft fruit settling
        at2 = int(rng.uniform(0.04, 0.16) * SR)
        f = jit(rng, [180, 310, 520], 0.15)
        knock = contact(modes(dur, f, [0.006, 0.004, 0.003], [1, 0.6, 0.3]), 0.003)
        y[at2:] += rng.uniform(0.3, 0.6) * knock[: len(y) - at2]
    if rng.random() < 0.5:                                                           # a date against the clay
        at3 = int(rng.uniform(0.05, 0.15) * SR)
        f = jit(rng, [620, 1150, 1900, 2700], 0.1)
        clay = contact(modes(dur, f, [q_tau(x, rng.uniform(6, 10)) for x in f], [1, 0.7, 0.4, 0.2]), 0.0012)
        y[at3:] += 0.35 * clay[: len(y) - at3]
    return band(y, lo=120, hi=5000)


def pit_drop(rng):
    """A date stone dropped onto sand from a few centimetres: sand takes almost all of it,
    a short, soft, dull thud and a whisper of grains, with the stone's own faint click."""
    dur = 0.18
    t = taxis(dur)
    f = jit(rng, [140, 260, 420], 0.15)
    y = contact(modes(dur, f, [0.01, 0.006, 0.004], [1, 0.6, 0.35]), 0.004)
    y += 0.5 * burst(rng, dur, 0.012, lo=1500, hi=7000) * np.clip(t / 0.002, 0, 1)    # sand grains
    f2 = jit(rng, [2600, 3900, 5200], 0.1)
    y += 0.12 * contact(modes(dur, f2, [0.002, 0.0015, 0.001], [1, 0.6, 0.3]), 0.0003)
    if rng.random() < 0.5:                                                           # it rolls over once
        at = int(rng.uniform(0.03, 0.06) * SR)
        y[at:] += 0.3 * contact(modes(dur, f, [0.006, 0.004, 0.003], [1, 0.6, 0.35]), 0.005)[: len(y) - at]
    return band(y, lo=90, hi=8000)


SOUNDS = {"date_pick": date_pick, "pit_drop": pit_drop, "die_wall": die_wall, "die_floor": die_floor, "die_die": die_die, "dice_shake": dice_shake,
          "stone_place": stone_place, "stone_stone": stone_stone, "stone_lift": stone_lift,
          "stone_slide": stone_slide}
VARIANTS = 6

if __name__ == "__main__":
    import sys
    only = sys.argv[1:]       # e.g. stone_slide: write just these
    for name, fn in SOUNDS.items():
        if only and name not in only:
            continue
        for v in range(VARIANTS if name != "dice_shake" else 3):
            rng = np.random.default_rng(zlib.crc32(("%s%d" % (name, v)).encode()))
            save("%s_%d" % (name, v), fn(rng))
        print("wrote", name)
