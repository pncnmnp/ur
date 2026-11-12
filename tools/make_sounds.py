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


# ------------------------------------------------------------------- air
# Everything below that loops is made periodic: noise is shaped in the frequency domain
# (which wraps round), and every envelope laid on it is itself periodic noise, so the end
# of a loop runs into its beginning with no seam to hear.
def unit(x):
    return x / (x.std() + 1e-12)


def pnoise(rng, n, lo=None, hi=None, order=2):
    return band(rng.standard_normal(n), lo, hi, order)


def spectrum(rng, n, pts):
    """Periodic noise whose spectrum runs through the points [(Hz, dB), ...]."""
    f = np.fft.rfftfreq(n, 1 / SR)
    db = np.interp(np.log(np.maximum(f, 1.0)), np.log([q[0] for q in pts]), [q[1] for q in pts], left=-90, right=-90)
    return unit(np.fft.irfft(np.fft.rfft(rng.standard_normal(n)) * 10 ** (db / 20), n=n))


def resonance(f, f0, q):
    return 1 / np.sqrt(1 + (q * (f / f0 - f0 / np.maximum(f, 1.0))) ** 2)


def formant(y, peaks, floor=0.2):
    """Colour a sound with the resonances of a cavity (a mouth, a nose): [(Hz, Q, gain)]."""
    f = np.fft.rfftfreq(len(y), 1 / SR)
    g = np.full_like(f, floor)
    for f0, q, a in peaks:
        g += a * resonance(f, f0, q)
    return np.fft.irfft(np.fft.rfft(y) * g, n=len(y))


def cconv(x, k):
    """Convolution that wraps round (for loops)."""
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(k, len(x)), n=len(x))


def grains(rng, n, rate, make, spread=0.7, kinds=8):
    """Many tiny events at `rate` a second (an array: it may vary). make() gives the sound
    of one; several different ones are made and dealt out, so that no single grain's
    colour is stamped on the whole."""
    y = np.zeros(n)
    for _ in range(kinds):
        imp = np.zeros(n)
        hits = rng.random(n) < rate / kinds / SR
        imp[hits] = rng.lognormal(0.0, spread, hits.sum()) * rng.choice([-1.0, 1.0], hits.sum())
        y += cconv(imp, make())
    return y


def wind_voice(rng, n, centre, lo=280.0, hi=1500.0, k=10, q=2.6):
    """Noise through one broad resonance whose centre (Hz, an array) wanders: the hollow
    note of air pouring over an edge, which rises as it blows harder."""
    F = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    cs = np.geomspace(lo, hi, k)
    width = np.log(cs[1] / cs[0])
    y = np.zeros(n)
    for ck in cs:
        w = np.exp(-0.5 * ((np.log(centre) - np.log(ck)) / width) ** 2)
        y += np.fft.irfft(F * resonance(f, ck, q), n=n) * w
    return y


WIND_LOW = [(25, -40), (50, -16), (95, -4), (170, 0), (320, -5), (650, -18), (1400, -40)]
WIND_MID = [(120, -40), (300, -8), (520, 0), (900, -3), (1700, -11), (3200, -22), (6500, -40)]
WIND_HIGH = [(900, -40), (2200, -8), (3800, 0), (6000, -4), (9000, -14), (12000, -30)]


def wind(rng, dur, calm, buffet, hiss, voice):
    """Open-desert wind at a low table, in stereo. There are no trees or wires to sing: what
    is heard is the air itself tumbling past the ears (a low, uneven buffeting), a soft
    broad rush off the sand and the things on it, and a thin hiss on top. All three follow
    the wind's speed, and not equally: as it blows harder the rush grows faster than the
    rumble and the hiss faster still, so a swell is heard as the sound brightening, not as
    a volume knob. It blows from the left, so each swell reaches the left ear first."""
    n = int(dur * SR) // 2 * 2
    s = 0.85 * unit(pnoise(rng, n, hi=0.16, order=3)) + 0.4 * unit(pnoise(rng, n, lo=0.25, hi=1.3))
    low_both = spectrum(rng, n, WIND_LOW)          # the rumble is much the same in both ears
    out = []
    for ch in range(2):
        sc = np.roll(s, int(0.3 * SR) * ch) + 0.25 * unit(pnoise(rng, n, hi=0.8))
        v = calm + (1 - calm) / (1 + np.exp(-1.4 * sc))                 # speed, calm..1
        low = 0.75 * low_both + 0.65 * spectrum(rng, n, WIND_LOW)
        buf = np.clip(unit(pnoise(rng, n, lo=1.5, hi=11)), -2.0, 3.0)   # buffets: a few a second
        low *= np.maximum(1 + 0.5 * buffet * v * buf, 0.15)
        mid = spectrum(rng, n, WIND_MID) * np.maximum(1 + 0.22 * unit(pnoise(rng, n, lo=0.5, hi=5)), 0.2)
        high = spectrum(rng, n, WIND_HIGH)
        centre = 520 * np.exp(0.3 * unit(pnoise(rng, n, hi=0.3, order=3)) + 1.1 * (v - 0.75))
        vo = unit(wind_voice(rng, n, centre))
        out.append(0.75 * low * v ** 1.5 + 0.6 * mid * v ** 2.5 + hiss * high * v ** 4 + voice * vo * v ** 3)
    return np.stack(out, 1)


def wind_air(rng):
    """The air that is always there: a light, steady breeze (24 s loop)."""
    return wind(rng, 24.0, calm=0.5, buffet=0.5, hiss=0.05, voice=0.12)


def wind_gust(rng):
    """A gust at its height (16 s loop; the game brings it up and lets it die away, as a
    cloud's edge comes over or of its own accord): fuller, brighter, buffeting harder."""
    return wind(rng, 16.0, calm=0.72, buffet=0.9, hiss=0.13, voice=0.3)


def sand_drift(rng):
    """Sand on the move in a strong gust (12 s stereo loop): grains hopping low over the
    ground in streamers that snake past, left to right. A fine dry hiss made of countless
    separate ticks of grain on grain, and now and then a grain striking the wood of the
    board or the leather of the tray."""
    n = int(12.0 * SR)
    st = 0.55 + 0.33 * unit(pnoise(rng, n, hi=0.45, order=3)) + 0.22 * unit(pnoise(rng, n, lo=0.6, hi=3.0))
    out = []
    for ch in range(2):
        sc = np.clip(np.roll(st, int(0.35 * SR) * ch) * (1 + 0.2 * unit(pnoise(rng, n, hi=2.0))), 0.04, 1.4)
        fine = grains(rng, n, 2600 * sc, lambda: burst(rng, 0.002, rng.uniform(0.0002, 0.0004), lo=rng.uniform(1800, 3200), hi=rng.uniform(6500, 9500)))
        wash = pnoise(rng, n, lo=1800, hi=6500) * sc ** 1.5
        wood = grains(rng, n, 40 * sc ** 2, lambda: contact(modes(0.02, jit(rng, [1700, 2600, 3900], 0.2), [0.0014, 0.001, 0.0007], [1, 0.7, 0.4]), 0.0002), 0.6)
        hide = grains(rng, n, 22 * sc ** 2, lambda: burst(rng, 0.006, 0.0011, lo=500, hi=2600), 0.6)
        out.append(unit(fine) + 0.45 * unit(wash) + 0.3 * unit(wood) + 0.22 * unit(hide))
    y = np.stack(out, 1)
    top = 9.0 * y.std()        # no one grain stands out of the rest as a click
    return np.tanh(y / top) * top


# ----------------------------------------------------------------- cloth
def lumps(rng, t, spans):
    """A movement's loudness: a few overlapping swells [(centre, width, height)]."""
    e = np.zeros_like(t)
    for c, w, a in spans:
        e += a * np.cos(np.clip((t - c) / w, -0.5, 0.5) * np.pi) ** 2
    return e


CLOTH_SOFT = [(110, -34), (280, -10), (650, -2), (1100, 0), (2000, -5), (3600, -15), (6500, -32)]
CLOTH_BRIGHT = [(700, -34), (1600, -4), (2600, 0), (4200, -8), (7000, -26)]


def cloth_body(rng, n, e, wrap=False):
    """Coarse wool or linen rubbing on itself, moving as e (0..1) says. Heavy cloth is a
    soft, dull sound: nearly all of it below 3 kHz, nothing crisp (that is paper, or silk).
    What makes it cloth is how it moves. Thread rides over thread, so the rub has the
    weave in it: a faint purr at the rate the threads pass (a hundred or two a second,
    following the speed), never steady, from two layers that are not quite in step. And it
    comes in soft rushes, a few to a dozen a second, as one fold after another slides and
    stops. Under it, the low breath of air the moving folds push out of their way."""
    soft = spectrum(rng, n, CLOTH_SOFT)
    bright = spectrum(rng, n, CLOTH_BRIGHT)
    # the weave: threads passing, faster as the cloth moves faster
    purr = np.ones(n)
    for depth in (0.3, 0.2):
        f = rng.uniform(120, 190) * (0.35 + 0.65 * e) * np.exp(0.12 * unit(pnoise(rng, n, lo=1.0 if wrap else None, hi=9)))
        ph = np.cumsum(f) / SR
        if wrap:
            ph *= np.round(ph[-1]) / ph[-1]          # a whole number of threads in the loop
        purr *= 1 + depth * np.sin(2 * np.pi * ph + rng.uniform(0, 6.28))
    # the rushes: folds sliding and stopping, each a soft swell of a few hundredths of a second
    rush = np.zeros(n)
    for width in (0.03, 0.055, 0.09, 0.14):
        k = np.hanning(int(width * SR))
        hits = np.where(rng.random(n) < 3.2 * (0.4 + e) / SR, rng.lognormal(0, 0.6, n), 0.0)
        rush += cconv(hits, k)
    rush /= rush.mean() + 1e-9
    rub = (soft * e + 0.3 * bright * e ** 2.2) * purr * (0.3 + 0.7 * np.minimum(rush, 3.5))
    de = np.abs(np.gradient(e))
    de /= de.max() + 1e-9
    air = unit(pnoise(rng, n, lo=90, hi=420)) * (0.4 * e + 0.6 * de) * (0.5 + 0.5 * np.minimum(rush, 3.5))
    return band(rub + 0.6 * air, lo=80, hi=4200)


def cloth_move(rng):
    """A robe shifting as its wearer leans in and reaches (one movement, ~0.7 s)."""
    dur = rng.uniform(0.6, 0.95)
    t = taxis(dur + 0.08)
    n = len(t)
    spans = [(rng.uniform(0.22, 0.32) * dur, rng.uniform(0.45, 0.6) * dur, 1.0)]
    for _ in range(rng.choice([1, 2])):
        spans.append((rng.uniform(0.45, 0.85) * dur, rng.uniform(0.2, 0.4) * dur, rng.uniform(0.3, 0.7)))
    e = lumps(rng, t, spans)
    return cloth_body(rng, n, e / e.max())


def cloth_rub(rng):
    """A sleeve in motion, for as long as the arm moves (4 s loop: the game makes it as
    loud as the arm is fast)."""
    n = int(4.0 * SR)
    e = np.clip(0.7 + 0.22 * unit(pnoise(rng, n, lo=0.4, hi=4.0)), 0.25, 1.2)
    return cloth_body(rng, n, e, True)


def sleeve_sand(rng):
    """The hem of a sleeve dragged over dry sand (3 s loop, as loud as the drag is fast):
    grains rolled along under the cloth, a soft close "shhh" with a fine grit in it."""
    n = int(3.0 * SR)
    e = np.clip(0.75 + 0.2 * unit(pnoise(rng, n, lo=0.5, hi=5.0)), 0.3, 1.2)
    grit = grains(rng, n, 5200 * e, lambda: burst(rng, 0.002, rng.uniform(0.00025, 0.0004), lo=rng.uniform(1600, 2800), hi=rng.uniform(6000, 9000)))
    shh = pnoise(rng, n, lo=700, hi=3200) * e
    drag = pnoise(rng, n, lo=180, hi=700) * e                 # the weight of the cloth on it
    return band(unit(grit) + 0.7 * unit(shh) + 0.3 * unit(drag), lo=150, hi=10000)


# ------------------------------------------------------------------ hands
def hand_wood(rng):
    """A hand coming to rest on the wooden rim of the tray. Flesh is soft, so the contact
    is long (a few milliseconds) and takes all the brightness out of it: a small dull pat,
    two or three finger pads landing one after another, the heavy plank barely answering."""
    dur = 0.16
    n = len(taxis(dur))
    y = np.zeros(n)
    at = 0
    for k in range(rng.integers(2, 5)):
        f0 = rng.uniform(380, 480)
        fs = jit(rng, [f0, f0 * 1.9, f0 * 2.9], 0.06)
        wood = contact(modes(dur, fs, [q_tau(f, rng.uniform(4, 7)) for f in fs], [1.0, 0.5, 0.2]), rng.uniform(0.0022, 0.0036))
        pad = contact(modes(dur, [rng.uniform(170, 250)], [0.006], [1.0]), 0.004)       # the flesh itself
        skin = burst(rng, dur, 0.004, lo=350, hi=2400)                                  # skin meeting dry wood
        tap = (0.9 * wood / (np.abs(wood).max() + 1e-9) + 0.45 * pad / (np.abs(pad).max() + 1e-9)
               + 0.4 * skin / (np.abs(skin).max() + 1e-9)) * rng.uniform(0.4, 1.0)
        y[at:] += tap[: n - at]
        at += int(rng.uniform(0.008, 0.03) * SR)
    return band(y, lo=110, hi=3000)


def hand_leather(rng):
    """Fingertips coming down on the leather floor of the tray: duller still, a soft low
    pat and the faint dry rub of skin on hide."""
    dur = 0.16
    n = len(taxis(dur))
    t = taxis(dur)
    y = np.zeros(n)
    at = 0
    for k in range(rng.integers(1, 4)):
        f0 = rng.uniform(110, 150)
        fs = jit(rng, [f0, f0 * 2.1, f0 * 3.4], 0.08)
        hide = contact(modes(dur, fs, [q_tau(f, rng.uniform(2.5, 4)) for f in fs], [0.5, 1.0, 0.7]), rng.uniform(0.003, 0.0045))
        slap = burst(rng, dur, 0.003, lo=300, hi=1800)
        tap = (hide / (np.abs(hide).max() + 1e-9) + 0.5 * slap / (np.abs(slap).max() + 1e-9)) * rng.uniform(0.4, 1.0)
        y[at:] += tap[: n - at]
        at += int(rng.uniform(0.008, 0.03) * SR)
    rub = pnoise(rng, n, lo=500, hi=2200) * np.exp(-((t - 0.05) / 0.03) ** 2)
    y += 0.2 * np.abs(y).max() * rub / (np.abs(rub).max() + 1e-9)
    return band(y, lo=100, hi=2600)


# ------------------------------------------------------------------ mouth
def wet_pop(rng, f, tau, rise):
    """One tiny wet pop: a film of spit or sticky fruit letting go. A bubble's note, very
    short, sliding up a little as it opens."""
    t = taxis(0.02)
    ph = 2 * np.pi * f * (t + rise * t * t / (2 * 0.008))
    return contact(np.sin(ph) * np.exp(-t / tau), 0.0004)


def chew(rng):
    """One chew of a dried date, mouth closed, heard across the table. The jaw closes
    through soft, sticky flesh (a dull low squash, mostly felt), and as it opens again the
    fruit peels off the teeth: a short run of tiny wet pops, quickening, coloured by the
    hollow of the mouth and muffled by the lips."""
    dur = 0.5
    t = taxis(dur)
    n = len(t)
    tc = rng.uniform(0.03, 0.06)
    # closing
    squash = 0.35 * unit(pnoise(rng, n, lo=180, hi=1100)) * np.exp(-((t - tc - 0.03) / 0.028) ** 2)
    for k in range(rng.integers(5, 12)):          # the flesh giving: small soft squelches, low
        at = int(np.clip(rng.normal(tc + 0.03, 0.02), 0.002, 0.2) * SR)
        p = wet_pop(rng, np.exp(rng.normal(np.log(620), 0.3)), rng.uniform(0.002, 0.004), rng.uniform(-0.25, 0.1))
        squash[at: at + len(p)] += p * rng.lognormal(0.0, 0.5) * 1.6
    squash = formant(squash, [(rng.uniform(360, 460), 4, 1.0), (rng.uniform(950, 1250), 5, 0.5)])
    thud = np.zeros(n)
    at = int((tc + 0.035) * SR)
    th = contact(modes(0.12, [rng.uniform(105, 145), rng.uniform(200, 260)], [0.012, 0.008], [1.0, 0.5]), 0.007)
    thud[at: at + len(th)] += th[: n - at]
    # opening
    pops = np.zeros(n)
    at_t = tc + rng.uniform(0.15, 0.24)
    t_open = at_t
    gap = rng.uniform(0.012, 0.03)
    for k in range(rng.integers(3, 10)):
        p = wet_pop(rng, np.exp(rng.normal(np.log(1350), 0.38)), rng.uniform(0.0012, 0.003), rng.uniform(0.0, 0.4))
        at = int(at_t * SR)
        if at + len(p) >= n:
            break
        pops[at: at + len(p)] += p * rng.lognormal(0.0, 0.5)
        at_t += gap
        gap *= rng.uniform(0.55, 0.95)
    wet = pops + 0.1 * np.abs(pops).max() * unit(pnoise(rng, n, lo=1200, hi=3500)) * np.exp(-((t - (t_open + at_t) / 2) / 0.04) ** 2)
    wet = formant(wet, [(rng.uniform(520, 720), 4, 1.0), (rng.uniform(1300, 1800), 5, 0.8), (2600, 4, 0.3)])
    nm = lambda x: x / (np.abs(x).max() + 1e-9)
    y = 0.4 * nm(squash) + 0.55 * nm(thud) + rng.uniform(0.55, 1.0) * nm(wet)
    return band(y, lo=110, hi=rng.uniform(2200, 3200))


def breath_noise(rng, n, e, peaks, lo, hi, bright):
    """Air through the nose: turbulence coloured by the nasal passages, brighter the faster
    it flows (e: the flow, 0..1)."""
    a = formant(pnoise(rng, n, lo=lo, hi=hi), peaks, floor=0.12)
    b = pnoise(rng, n, lo=hi * 0.55, hi=hi * 1.5)
    return unit(a) * e + bright * unit(b) * e ** 2.5


def one_sniff(rng, d, snuffle):
    t = taxis(d + 0.12)
    n = len(t)
    tr = rng.uniform(0.04, 0.07)
    tf = rng.uniform(0.03, 0.05)
    u = np.clip(t / d, 0, 1)
    e = np.clip(t / tr, 0, 1) ** 1.5 * np.clip((d - t) / tf, 0, 1) * (0.35 + u ** 0.7 * (1.02 - u) ** 0.3)
    e *= np.maximum(1 + 0.15 * unit(band(rng.standard_normal(n), hi=25)), 0.3)
    if snuffle > 0:           # a nostril not quite clear: the flow flutters
        f = rng.uniform(45, 80) * (1 + 0.12 * unit(band(rng.standard_normal(n), hi=12)))
        e *= 1 - snuffle * (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(f) / SR)) ** 3
    peaks = [(rng.uniform(850, 1100), 3, 0.7), (rng.uniform(2100, 2700), 3.5, 1.0), (rng.uniform(3800, 4600), 4, 0.6)]
    return breath_noise(rng, n, e / e.max(), peaks, 500, 7000, 0.4)


def sniff(rng):
    """A sniff: a short, sharp breath in through the nose. Sometimes two, a small one
    and then the real one; sometimes with a slight snuffle in it."""
    snuffle = rng.choice([0.0, 0.0, rng.uniform(0.25, 0.55)])
    y = one_sniff(rng, rng.uniform(0.24, 0.4), snuffle)
    if rng.random() < 0.4:
        first = one_sniff(rng, rng.uniform(0.12, 0.18), snuffle) * rng.uniform(0.45, 0.7)
        gap = np.zeros(int(rng.uniform(0.03, 0.09) * SR))
        y = np.concatenate([first, gap, y])
    return band(y, lo=350, hi=8000)


def nose_out(rng):
    """A breath let out through the nose, mouth busy: soft, darker than a sniff, quick to
    come and slow to go."""
    d = rng.uniform(0.8, 1.3)
    t = taxis(d + 0.1)
    n = len(t)
    e = np.clip(t / rng.uniform(0.09, 0.15), 0, 1) ** 1.3 * np.exp(-t / (d * rng.uniform(0.3, 0.42))) * np.clip((d - t) / 0.2, 0, 1)
    e *= np.maximum(1 + 0.12 * unit(band(rng.standard_normal(n), hi=18)), 0.3)
    peaks = [(rng.uniform(600, 800), 2.5, 1.0), (rng.uniform(1600, 2100), 3, 0.6), (rng.uniform(3200, 3900), 3.5, 0.25)]
    return band(breath_noise(rng, n, e / e.max(), peaks, 250, 4200, 0.2), lo=200, hi=5000)


def save_loop(name, y, half=False, peak=0.9):
    """Write a seamless loop (mono, or stereo as an (n, 2) array), at half the sample rate
    where there is nothing above ~10 kHz in it."""
    y = np.atleast_2d(y.T).T
    sr = SR
    if half:      # halve the rate in the frequency domain, which keeps it periodic
        m = len(y) // 2
        y = np.stack([np.fft.irfft(np.fft.rfft(y[:, c])[: m // 2 + 1], n=m) * 0.5 for c in range(y.shape[1])], 1)
        sr = SR // 2
    y = y / (np.abs(y).max() + 1e-9) * peak
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(y.shape[1])
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())



SOUNDS = {"date_pick": date_pick, "pit_drop": pit_drop, "die_wall": die_wall, "die_floor": die_floor, "die_die": die_die, "dice_shake": dice_shake,
          "stone_place": stone_place, "stone_stone": stone_stone, "stone_lift": stone_lift,
          "stone_slide": stone_slide, "cloth_move": cloth_move, "hand_wood": hand_wood, "hand_leather": hand_leather,
          "chew": chew, "sniff": sniff, "nose_out": nose_out}
VARIANTS = 6
COUNT = {"dice_shake": 3, "chew": 10}
# the sounds that go on and on: name -> (maker, written at half the sample rate)
LOOPS = {"wind_air": (wind_air, True), "wind_gust": (wind_gust, True), "sand_drift": (sand_drift, False),
         "cloth_rub": (cloth_rub, True), "sleeve_sand": (sleeve_sand, False)}

if __name__ == "__main__":
    import sys
    only = sys.argv[1:]       # e.g. stone_slide: write just these
    for name, fn in SOUNDS.items():
        if only and name not in only:
            continue
        for v in range(COUNT.get(name, VARIANTS)):
            rng = np.random.default_rng(zlib.crc32(("%s%d" % (name, v)).encode()))
            save("%s_%d" % (name, v), fn(rng))
        print("wrote", name)
    for name, (fn, half) in LOOPS.items():
        if only and name not in only:
            continue
        save_loop(name, fn(np.random.default_rng(zlib.crc32(name.encode()))), half)
        print("wrote", name)
