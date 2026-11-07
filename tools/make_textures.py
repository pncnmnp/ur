#!/usr/bin/env python3
"""Procedurally generates every texture used by the game into ../assets.

Needs numpy + pillow:   python3 tools/make_textures.py
Outputs albedo / normal / roughness maps for: the carved board, reserve strips,
home plates, plain wood, white marble, black basalt and felt.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
os.makedirs(OUT, exist_ok=True)
PPU = 256  # board pixels per world unit


# ----------------------------------------------------------------- noise utils
def blur(a, sigma):
    """Periodic gaussian blur (FFT)."""
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    g = np.exp(-2 * (np.pi * sigma) ** 2 * (fx ** 2 + fy ** 2))
    return np.fft.irfft2(np.fft.rfft2(a) * g, s=a.shape)


def fnoise(h, w, sx, sy, seed):
    """Tileable noise, unit std, correlation length sx (along x) / sy (along y) pixels."""
    r = np.random.default_rng(seed).standard_normal((h, w))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    g = np.exp(-2 * np.pi ** 2 * ((sx * fx) ** 2 + (sy * fy) ** 2))
    n = np.fft.irfft2(np.fft.rfft2(r) * g, s=(h, w))
    return (n - n.mean()) / (n.std() + 1e-9)


def normal_map(hgt, strength):
    gx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * 0.5
    gy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * 0.5
    n = np.dstack([-gx * strength, gy * strength, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def scratches(h, w, n, rng, maxlen, wrap=True):
    """Thin, slightly curved scratch lines with varying depth. Drawn wrapped so tiling
    textures stay seamless."""
    im = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(im)
    offs = [(ox, oy) for ox in (-w, 0, w) for oy in (-h, 0, h)] if wrap else [(0, 0)]
    for _ in range(n):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        ang = rng.uniform(0, math.pi)
        ln = rng.uniform(0.2, 1.0) * maxlen
        bend = rng.uniform(-0.3, 0.3)
        pts = []
        for k in range(8):
            t = k / 7
            a = ang + bend * t
            pts.append((x + math.cos(a) * ln * t, y + math.sin(a) * ln * t))
        val = int(rng.uniform(70, 255))
        wd = int(rng.choice([1, 1, 1, 2]))
        for ox, oy in offs:
            d.line([(px + ox, py + oy) for px, py in pts], fill=val, width=wd)
    return blur(np.asarray(im, dtype=np.float32) / 255.0, 0.5)


def save_rgb(name, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, name))


def save_l(name, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "L").save(os.path.join(OUT, name))


# ----------------------------------------------------------------------- wood
def wood(h, w, seed, light=(0.66, 0.45, 0.24), dark=(0.33, 0.19, 0.09), rings=10):
    y = (np.arange(h)[:, None] / h) * np.ones((1, w))
    warp = fnoise(h, w, w / 6, h / 5, seed)
    r = y * rings + warp * 0.45 + fnoise(h, w, w / 3, 2, seed + 1) * 0.08
    ring = (0.5 + 0.5 * np.sin(2 * np.pi * r)) ** 1.5
    fib = fnoise(h, w, w / 8, 1.0, seed + 2)
    fib2 = fnoise(h, w, w / 20, 0.7, seed + 3)
    tone = fnoise(h, w, w / 4, h / 4, seed + 4)
    t = np.clip(0.50 * ring + 0.18 * fib + 0.10 * fib2 + 0.06 * tone + 0.15, 0, 1)
    light = np.array(light)
    dark = np.array(dark)
    alb = light * (1 - t[..., None]) + dark * t[..., None]
    pores = np.clip((fnoise(h, w, w / 25, 0.6, seed + 5) - 1.6) * 0.5, 0, 1)
    alb *= (1 - 0.35 * pores)[..., None]
    fh = 0.5 * fib + 0.5 * fib2
    return alb, fh, fib


# --------------------------------------------------------------- drawing layer
class Layers:
    NAMES = ["recess", "carve", "lapis", "carn", "gold"]

    def __init__(self, W, H):
        self.W, self.H = W, H
        self.im = {n: Image.new("L", (W, H), 0) for n in self.NAMES}
        self.d = {n: ImageDraw.Draw(self.im[n]) for n in self.NAMES}

    def arr(self, n):
        return np.asarray(self.im[n], dtype=np.float32) / 255.0


def stroke(d, pts, w):
    d.line(pts, fill=255, width=w, joint="curve")
    r = w / 2.0
    for (x, y) in (pts[0], pts[-1]):
        d.ellipse((x - r, y - r, x + r, y + r), fill=255)


def ell_poly(cx, cy, a, b, rot=0.0, n=56):
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        x, y = a * math.cos(t), b * math.sin(t)
        pts.append((cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)))
    return pts


def closed(pts):
    return pts + [pts[0]]


def disc(d, cx, cy, r):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)


# --------------------------------------------------------------------- glyphs
def g_ankh(d, cx, cy, s, w):
    stroke(d, closed(ell_poly(cx, cy - 0.38 * s, 0.26 * s, 0.34 * s)), w)
    stroke(d, [(cx, cy - 0.04 * s), (cx, cy + 0.85 * s)], w)
    stroke(d, [(cx - 0.45 * s, cy + 0.2 * s), (cx + 0.45 * s, cy + 0.2 * s)], w)


def g_eye(d, cx, cy, s, w):
    ts = np.linspace(-1, 1, 40)
    top = [(cx + t * 0.78 * s, cy - 0.3 * s * (1 - t * t)) for t in ts]
    bot = [(cx + t * 0.78 * s, cy + 0.16 * s * (1 - t * t)) for t in ts]
    brow = [(cx + t * 0.82 * s, cy - 0.58 * s - 0.14 * s * (1 - t * t)) for t in ts]
    stroke(d, top, w)
    stroke(d, bot, w)
    stroke(d, brow, w)
    disc(d, cx + 0.04 * s, cy - 0.06 * s, 0.17 * s)
    stroke(d, [(cx + 0.15 * s, cy + 0.15 * s), (cx + 0.15 * s, cy + 0.55 * s), (cx - 0.08 * s, cy + 0.7 * s)], w)
    stroke(d, [(cx + 0.5 * s, cy + 0.1 * s), (cx + 0.62 * s, cy + 0.45 * s), (cx + 0.82 * s, cy + 0.55 * s)], w)


def g_lotus(d, cx, cy, s, w):
    stroke(d, closed(ell_poly(cx, cy - 0.3 * s, 0.17 * s, 0.45 * s)), w)
    stroke(d, closed(ell_poly(cx - 0.32 * s, cy - 0.15 * s, 0.15 * s, 0.4 * s, -0.55)), w)
    stroke(d, closed(ell_poly(cx + 0.32 * s, cy - 0.15 * s, 0.15 * s, 0.4 * s, 0.55)), w)
    stroke(d, [(cx - 0.6 * s, cy + 0.28 * s), (cx, cy + 0.5 * s), (cx + 0.6 * s, cy + 0.28 * s)], w)
    stroke(d, [(cx, cy + 0.5 * s), (cx, cy + 0.88 * s)], w)


def g_sun(d, cx, cy, s, w):
    stroke(d, closed(ell_poly(cx, cy, 0.28 * s, 0.28 * s)), w)
    disc(d, cx, cy, 0.09 * s)
    for k in range(16):
        a = k * math.pi / 8
        r1, r2 = 0.42 * s, (0.8 if k % 2 == 0 else 0.62) * s
        stroke(d, [(cx + r1 * math.cos(a), cy + r1 * math.sin(a)), (cx + r2 * math.cos(a), cy + r2 * math.sin(a))], w)


def g_water(d, cx, cy, s, w):
    for k in range(3):
        y0 = cy + (k - 1) * 0.36 * s
        stroke(d, [(cx + x * 0.85 * s, y0 + 0.1 * s * math.sin(x * 4.5 * math.pi / 2)) for x in np.linspace(-1, 1, 40)], w)


def g_dots(d, cx, cy, s, w):
    for dx, dy in ((0, 0), (-1, -1), (1, -1), (-1, 1), (1, 1)):
        disc(d, cx + dx * 0.5 * s, cy + dy * 0.5 * s, 0.13 * s)
    stroke(d, closed(ell_poly(cx, cy, 0.3 * s, 0.3 * s)), max(3, w - 3))


def g_diamond(d, cx, cy, s, w):
    for k in (0.8, 0.5):
        stroke(d, closed([(cx, cy - k * s), (cx + k * s, cy), (cx, cy + k * s), (cx - k * s, cy)]), w)
    disc(d, cx, cy, 0.11 * s)


def g_scarab(d, cx, cy, s, w):
    stroke(d, closed(ell_poly(cx, cy + 0.1 * s, 0.28 * s, 0.4 * s)), w)
    stroke(d, [(cx, cy - 0.3 * s), (cx, cy + 0.5 * s)], w)
    stroke(d, closed(ell_poly(cx, cy - 0.5 * s, 0.14 * s, 0.1 * s)), max(3, w - 2))
    for sg in (-1, 1):
        stroke(d, [(cx + sg * 0.28 * s, cy - 0.05 * s), (cx + sg * 0.62 * s, cy - 0.5 * s), (cx + sg * 0.85 * s, cy - 0.22 * s)], w)
        stroke(d, [(cx + sg * 0.27 * s, cy + 0.14 * s), (cx + sg * 0.68 * s, cy + 0.2 * s)], w)
        stroke(d, [(cx + sg * 0.25 * s, cy + 0.38 * s), (cx + sg * 0.62 * s, cy + 0.6 * s)], w)


def g_djed(d, cx, cy, s, w):
    stroke(d, [(cx, cy - 0.8 * s), (cx, cy + 0.82 * s)], w)
    for i, ln in enumerate((0.42, 0.36, 0.3, 0.24)):
        y = cy - 0.55 * s + i * 0.2 * s
        stroke(d, [(cx - ln * s, y), (cx + ln * s, y)], w)
    stroke(d, [(cx - 0.45 * s, cy + 0.82 * s), (cx + 0.45 * s, cy + 0.82 * s)], w)
    stroke(d, [(cx - 0.3 * s, cy - 0.8 * s), (cx + 0.3 * s, cy - 0.8 * s)], w)


def g_feather(d, cx, cy, s, w):
    stroke(d, closed(ell_poly(cx, cy, 0.2 * s, 0.7 * s)), w)
    stroke(d, [(cx, cy - 0.7 * s), (cx, cy + 0.95 * s)], w)
    for k in range(-3, 4):
        y = cy + k * 0.17 * s
        for sg in (-1, 1):
            stroke(d, [(cx, y + 0.06 * s), (cx + sg * 0.17 * s, y - 0.07 * s)], max(3, w - 3))


GLYPHS = {"ankh": g_ankh, "eye": g_eye, "lotus": g_lotus, "sun": g_sun, "water": g_water,
          "dots": g_dots, "diamond": g_diamond, "scarab": g_scarab, "djed": g_djed, "feather": g_feather}

# motif for each non-rosette square, indexed [row][col]
MOTIFS = [
    [None, "eye", "lotus", "dots", None, None, None, "water"],
    ["ankh", "dots", "scarab", None, "sun", "djed", "dots", "eye"],
    [None, "lotus", "eye", "diamond", None, None, None, "feather"],
]
ROSETTES = {(0, 0), (0, 2), (3, 1), (6, 0), (6, 2)}  # (col,row)


def rosette(L, cx, cy, R):
    for k in range(8):
        a = k * math.pi / 4
        pts = ell_poly(cx + 0.52 * R * math.cos(a), cy + 0.52 * R * math.sin(a), 0.42 * R, 0.2 * R, a)
        L.d["lapis" if k % 2 == 0 else "carn"].polygon(pts, fill=255)
        stroke(L.d["carve"], closed(pts), 4)
    disc(L.d["gold"], cx, cy, 0.2 * R)
    stroke(L.d["carve"], closed(ell_poly(cx, cy, 0.2 * R, 0.2 * R)), 4)
    for k in range(16):
        a = k * math.pi / 8
        disc(L.d["carve"], cx + 0.93 * R * math.cos(a), cy + 0.93 * R * math.sin(a), 4)


def rrect(d, box, r, fill=None, outline=None, width=1):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)


def frame_border(L, inset, pitch, width=4):
    """Carved double border with a diamond frieze between the two lines."""
    W, H = L.W, L.H
    c = L.d["carve"]
    rrect(c, (inset, inset, W - inset, H - inset), 10, outline=255, width=width)
    i2 = inset + 40
    rrect(c, (i2, i2, W - i2, H - i2), 8, outline=255, width=width)
    mid = inset + 20
    for x in range(int(i2 + 10), int(W - i2), pitch):
        for y in (mid, H - mid):
            stroke(c, closed([(x, y - 9), (x + 9, y), (x, y + 9), (x - 9, y)]), 3)
    for y in range(int(i2 + 10), int(H - i2), pitch):
        for x in (mid, W - mid):
            stroke(c, closed([(x, y - 9), (x + 9, y), (x, y + 9), (x - 9, y)]), 3)


# ----------------------------------------------------------------- composition
def compose(name, L, seed, rings=10, nstr=8.0, tile_only=False):
    H, W = L.H, L.W
    rng = np.random.default_rng(seed + 900)
    alb, fh, fib = wood(H, W, seed, rings=rings)
    alb2, _, _ = wood(H, W, seed + 50, light=(0.8, 0.6, 0.36), dark=(0.47, 0.29, 0.15), rings=rings + 2)
    rec_m = L.arr("recess")
    rec = blur(rec_m, 2.2)
    rec_wide = blur(rec_m, 7)
    carve = blur(L.arr("carve"), 1.2)
    lap, car, gold = (blur(L.arr(n), 0.9) for n in ("lapis", "carn", "gold"))
    inl = np.clip(lap + car + gold, 0, 1)

    # ---- age: centuries of handling, sun and blown sand
    def unit(n):
        return np.clip(0.5 + 0.5 * n, 0, 1)
    stain = np.clip(fnoise(H, W, 110, 110, seed + 901) * 0.8 + fnoise(H, W, 28, 28, seed + 902) * 0.35 - 0.55, 0, 1)
    bleach = unit(fnoise(H, W, 220, 220, seed + 903))
    grime_n = unit(fnoise(H, W, 14, 14, seed + 904))
    chip = np.clip(blur((fnoise(H, W, 2.5, 2.5, seed + 905) > 1.7).astype(float), 0.6) * 1.5, 0, 1) * inl
    inl_crack = np.exp(-(fnoise(H, W, 9, 9, seed + 906) / 0.07) ** 2) * inl
    # sand dust settles into the corners of recesses and patches of the carved lines
    dust_n = unit(fnoise(H, W, 18, 18, seed + 907) * 1.5)
    dust = np.clip((rec_m - blur(rec_m, 4)) * 2.0, 0, 1) * dust_n * 0.6
    dust = np.clip(dust + 0.4 * carve * np.clip(dust_n * 2.5 - 1.6, 0, 1), 0, 1)
    sc = scratches(H, W, int(W * H / 9000), rng, 70, wrap=tile_only)
    sc_light = scratches(H, W, int(W * H / 16000), rng, 50, wrap=tile_only)
    # stones slid in and out of the squares for centuries: rubbed paler there
    rub = rec_m * blur(rec_m, 30) * unit(fnoise(H, W, 40, 40, seed + 908))

    a = alb * (1 - rec[..., None]) + alb2 * rec[..., None]
    ao = 1 - 0.45 * np.clip(rec * (1 - rec_wide) * 2.2, 0, 1)
    a *= ao[..., None]
    a *= (1 - 0.62 * carve * (0.75 + 0.5 * grime_n))[..., None] * np.array([0.93, 0.97, 1.0])
    speck = 0.88 + 0.12 * (0.5 + 0.5 * np.tanh(fnoise(H, W, 1.2, 1.2, seed + 9)))
    fade_n = unit(fnoise(H, W, 20, 20, seed + 909))
    for m, col, faded in ((lap, (0.08, 0.15, 0.4), (0.2, 0.24, 0.32)),
                          (car, (0.66, 0.2, 0.12), (0.52, 0.32, 0.24)),
                          (gold, (0.88, 0.68, 0.24), (0.6, 0.5, 0.32))):
        c = np.array(col) * (1 - 0.6 * fade_n[..., None]) + np.array(faded) * 0.6 * fade_n[..., None]
        a = a * (1 - m[..., None]) + c * speck[..., None] * m[..., None]
    a = a * (1 - chip[..., None]) + np.array([0.13, 0.08, 0.05]) * chip[..., None]   # inlay chipped out
    a *= (1 - 0.55 * inl_crack)[..., None]
    a = a * (1 + 0.1 * rub)[..., None]
    grey = a.mean(axis=2, keepdims=True) * np.array([1.08, 1.0, 0.88])
    a = a * (1 - 0.3 * bleach[..., None]) + grey * 0.3 * bleach[..., None]           # sun-bleached
    a = a * (1 - 0.35 * stain[..., None]) + np.array([0.18, 0.11, 0.06]) * 0.35 * stain[..., None]
    a *= (0.9 + 0.1 * grime_n)[..., None]
    a *= (1 - 0.28 * sc)[..., None]
    a = a * (1 - 0.25 * sc_light[..., None]) + np.array([0.7, 0.56, 0.4]) * 0.25 * sc_light[..., None]
    a = a * (1 - 0.65 * dust[..., None]) + np.array([0.72, 0.6, 0.43]) * 0.65 * dust[..., None]

    hgt = fh * 0.012 - 0.30 * rec - 0.24 * carve - 0.10 * inl - 0.12 * chip - 0.05 * inl_crack \
        - 0.035 * sc - 0.02 * sc_light + 0.08 * dust
    rough = np.clip(0.56 + 0.06 * fib + 0.2 * carve + 0.05 * rec - 0.2 * inl + 0.25 * chip
                    + 0.12 * stain + 0.2 * dust - 0.1 * rub + 0.08 * sc, 0.15, 1)
    save_rgb(name + "_albedo.png", a)
    save_rgb(name + "_normal.png", normal_map(hgt, nstr))
    save_l(name + "_rough.png", rough)
    print("wrote", name, W, H)


def blank(W, H):
    return Layers(W, H)


# ---------------------------------------------------------------------- board
def make_board():
    W, H = int(8.5 * PPU), int(3.5 * PPU)
    L = blank(W, H)
    ox = oy = int(0.25 * PPU)
    w_line = 8
    for r in range(3):
        for c in range(8):
            if r != 1 and c in (4, 5):
                continue
            x0, y0 = ox + c * PPU, oy + r * PPU
            cx, cy = x0 + PPU / 2, y0 + PPU / 2
            rrect(L.d["recess"], (x0 + 8, y0 + 8, x0 + PPU - 8, y0 + PPU - 8), 12, fill=255)
            rrect(L.d["carve"], (x0 + 22, y0 + 22, x0 + PPU - 22, y0 + PPU - 22), 8, outline=255, width=4)
            if (c, r) in ROSETTES:
                rosette(L, cx, cy, 88)
            else:
                GLYPHS[MOTIFS[r][c]](L.d["carve"], cx, cy, 78, w_line)
    # cartouches in the two raised gaps
    seq = {0: ["ankh", "eye", "feather", "djed"], 2: ["lotus", "scarab", "ankh", "sun"]}
    for r in (0, 2):
        x0, y0 = ox + 4 * PPU, oy + r * PPU
        rrect(L.d["carve"], (x0 + 14, y0 + 44, x0 + 2 * PPU - 14, y0 + PPU - 44), 40, outline=255, width=5)
        rrect(L.d["carve"], (x0 + 26, y0 + 56, x0 + 2 * PPU - 26, y0 + PPU - 56), 32, outline=255, width=3)
        for i, g in enumerate(seq[r]):
            GLYPHS[g](L.d["carve"], x0 + 64 + i * 128, y0 + PPU / 2, 40, 6)
    frame_border(L, 14, 34)
    compose("board", L, seed=11)


def make_strip():
    W, H = int(7.4 * PPU), int(0.9 * PPU)
    L = blank(W, H)
    c = L.d["carve"]
    rrect(c, (8, 8, W - 8, H - 8), 8, outline=255, width=4)
    rrect(c, (20, 20, W - 20, H - 20), 6, outline=255, width=3)
    names = ["ankh", "eye", "feather", "djed", "lotus", "scarab", "sun", "water"]
    for i in range(14):
        x = 60 + i * (W - 120) / 13
        if i % 2 == 0:
            GLYPHS[names[(i // 2) % len(names)]](c, x, H / 2, 38, 5)
        else:
            stroke(c, closed([(x, H / 2 - 18), (x + 14, H / 2), (x, H / 2 + 18), (x - 14, H / 2)]), 4)
    compose("strip", L, seed=21, rings=3, nstr=8.0)


def make_plate():
    W, H = int(1.7 * PPU), int(2.8 * PPU)  # matches HOME_SIZE in main.gd
    L = blank(W, H)
    c = L.d["carve"]
    rrect(c, (8, 8, W - 8, H - 8), 10, outline=255, width=4)
    rrect(c, (22, 22, W - 22, H - 22), 8, outline=255, width=3)
    g_sun(c, W / 2, H / 2, 120, 7)
    compose("plate", L, seed=31, rings=4, nstr=8.0)


def make_wood_tile():
    compose("wood", blank(512, 512), seed=41, rings=6, nstr=5.0, tile_only=True)


# ---------------------------------------------------------------------- stone
def make_stone():
    S = 512
    n1 = fnoise(S, S, 70, 70, 101)
    n2 = fnoise(S, S, 14, 14, 102)
    n3 = fnoise(S, S, 2.5, 2.5, 103)
    n4 = fnoise(S, S, 1.0, 1.0, 104)
    n5 = fnoise(S, S, 0.7, 0.7, 108)
    yy = (np.arange(S)[:, None] / S) * np.ones((1, S))
    strata = 0.5 + 0.5 * np.sin(2 * np.pi * (yy * 9 + n1 * 0.25 + n2 * 0.05))

    # white limestone: warm white, faint strata, fine grey speckles, a few soft veins
    vein = np.exp(-(fnoise(S, S, 45, 45, 105) / 0.12) ** 2) * 0.6
    base = np.array([0.92, 0.9, 0.84])
    col = base * (1 + 0.03 * n1 + 0.02 * n3)[..., None]
    col *= (1 - 0.07 * strata)[..., None] * np.array([1.0, 0.985, 0.95])
    col = col * (1 - 0.3 * vein)[..., None] + np.array([0.55, 0.53, 0.5]) * (0.3 * vein)[..., None]
    speck = np.clip((n4 - 1.5) * 0.9, 0, 1) + np.clip((n5 - 1.9) * 1.2, 0, 1)
    col = col * (1 - 0.45 * np.clip(speck, 0, 1))[..., None]
    pits = np.clip((n3 - 1.7) * 0.8, 0, 1)
    col *= (1 - 0.18 * pits)[..., None]
    # dirt: iron/soil stains, grime in the pits, scratches, a film of dust
    stain = np.clip(fnoise(S, S, 60, 60, 110) * 0.9 + fnoise(S, S, 12, 12, 111) * 0.3 - 0.45, 0, 1)
    grime = np.clip(0.5 + 0.5 * fnoise(S, S, 6, 6, 112), 0, 1)
    rng = np.random.default_rng(113)
    sc = scratches(S, S, 90, rng, 90)
    dustf = np.clip(fnoise(S, S, 35, 35, 114) - 0.2, 0, 1)
    col = col * (1 - 0.55 * stain[..., None]) + np.array([0.58, 0.44, 0.28]) * 0.55 * stain[..., None]
    col *= (1 - 0.5 * pits * (0.5 + grime))[..., None]
    col *= (0.88 + 0.1 * grime)[..., None] * np.array([1.0, 0.97, 0.9])  # yellowed with handling
    col *= (1 - 0.3 * sc)[..., None]
    save_rgb("stone_white_albedo.png", col)

    # black slate / basalt: near black, grey strata streaks, mica flecks
    base = np.array([0.07, 0.07, 0.08])
    col = base * (1 + 0.5 * n1 + 0.25 * n2)[..., None]
    col += np.array([0.1, 0.1, 0.11]) * (strata ** 3 * (0.5 + 0.5 * np.tanh(n2)))[..., None]
    gv = np.exp(-(fnoise(S, S, 40, 40, 107) / 0.14) ** 2)
    col += np.array([0.3, 0.3, 0.32]) * (0.4 * gv)[..., None]
    fleck = np.clip((n4 - 1.8) * 1.0, 0, 1) + np.clip((n5 - 2.0) * 1.3, 0, 1)
    col += np.array([0.42, 0.42, 0.44]) * np.clip(fleck, 0, 1)[..., None]
    stain_b = np.clip(fnoise(S, S, 50, 50, 115) * 0.9 - 0.5, 0, 1)
    col = col * (1 - 0.45 * dustf[..., None]) + np.array([0.33, 0.28, 0.22]) * 0.45 * dustf[..., None]  # dusty film
    col = col * (1 - 0.35 * stain_b[..., None]) + np.array([0.24, 0.17, 0.11]) * 0.35 * stain_b[..., None]
    col = col * (1 - 0.5 * sc[..., None]) + np.array([0.4, 0.38, 0.36]) * 0.5 * sc[..., None]  # pale scratches
    col *= (0.9 + 0.1 * grime)[..., None]
    col = np.clip(col, 0.02, 1)
    save_rgb("stone_black_albedo.png", col)

    hgt = 0.35 * n2 + 0.35 * n3 + 0.3 * n4 - 0.4 * pits - 0.6 * sc
    save_rgb("stone_normal.png", normal_map(hgt * 0.05, 3.5))
    save_l("stone_rough.png", np.clip(0.55 + 0.25 * dustf + 0.1 * stain + 0.15 * grime + 0.1 * sc, 0.3, 1))


def make_felt():
    S = 512
    n = fnoise(S, S, 0.8, 0.8, 201)
    m = fnoise(S, S, 4, 4, 202)
    col = np.array([0.07, 0.27, 0.18]) * (1 + 0.10 * n + 0.06 * m)[..., None]
    save_rgb("felt_albedo.png", col)
    save_rgb("felt_normal.png", normal_map(n * 0.03, 3.0))


def wrapd(a, c, n):
    """Periodic signed distance from c along an axis of length n."""
    return (a - c + n / 2) % n - n / 2


# --------------------------------------------------------------- tray planks
def make_plank():
    """Weathered, oiled plank for the dice tray rim. Tileable, 4 x 1 world units,
    grain running along x: flat-sawn rings, knots, raised latewood, checking cracks."""
    W, H = 1024, 256
    rng = np.random.default_rng(301)
    x = np.arange(W)[None, :] * np.ones((H, 1))
    y = np.arange(H)[:, None] * np.ones((1, W))
    warp = fnoise(H, W, W / 4, H / 2, 302) * 0.7 + fnoise(H, W, W / 12, H / 10, 303) * 0.08
    r = y / H * 22 + warp
    knot_core = np.zeros((H, W))
    for k in range(3):
        kx, ky = rng.uniform(0, W), rng.uniform(0, H)
        s = rng.uniform(9, 15)
        d2 = (wrapd(x, kx, W) / (s * 2.6)) ** 2 + (wrapd(y, ky, H) / s) ** 2
        r += rng.choice([-1, 1]) * 3.0 * np.exp(-d2 * 0.35)
        knot_core = np.maximum(knot_core, np.exp(-d2 * 3.0))
    f = r % 1.0
    # earlywood darkens gradually into a narrow latewood band, then ends abruptly
    late = np.clip((f - 0.5) / 0.45, 0, 1) ** 2.5 * np.clip((1.0 - f) / 0.05, 0, 1)
    late = blur(late, 0.5) * (0.75 + 0.25 * fnoise(H, W, W / 9, 3, 309))
    fib = fnoise(H, W, W / 7, 0.6, 304)
    fib2 = fnoise(H, W, W / 30, 0.5, 305)
    pores = np.clip((fnoise(H, W, W / 40, 0.45, 306) - 1.7) * 0.7, 0, 1)
    grime = fnoise(H, W, W / 3, H / 1.5, 307)
    weather = np.clip(0.5 + 0.5 * fnoise(H, W, W / 6, H / 3, 308), 0, 1)

    # checking cracks along the grain
    crack = np.zeros((H, W))
    for c in range(12):
        x0, yc = rng.uniform(0, W), rng.uniform(0, H)
        L, wmax = rng.uniform(70, 320), rng.uniform(0.7, 1.6)
        s = ((x - x0) % W) / L
        inside = s < 1.0
        wig = fnoise(1, W, W / 10, 1, 320 + c)[0] * 2.5
        width = wmax * np.sin(np.pi * np.clip(s, 0, 1)) ** 0.6 + 1e-3
        crack = np.maximum(crack, inside * np.exp(-(wrapd(y, yc + wig[None, :], H) / width) ** 2))

    light = np.array([0.50, 0.35, 0.21])
    mid = np.array([0.38, 0.25, 0.14])
    dark = np.array([0.17, 0.10, 0.05])
    t = np.clip(0.35 + 0.3 * fib + 0.15 * fib2 + 0.12 * grime, 0, 1)
    alb = light * (1 - t[..., None]) + mid * t[..., None]
    alb = alb * (1 - 0.75 * late[..., None]) + dark * 0.75 * late[..., None] * 1.3
    alb *= (1 - 0.4 * pores)[..., None]
    alb *= (0.9 + 0.08 * grime)[..., None]
    grey = np.array([0.46, 0.43, 0.39])  # sun-bleached
    g = (0.22 * weather)[..., None]
    alb = alb * (1 - g) + grey * alb.mean(axis=2, keepdims=True) / 0.3 * g * 0.33
    alb = alb * (1 - 0.6 * knot_core[..., None]) + np.array([0.16, 0.08, 0.04]) * 0.6 * knot_core[..., None]
    alb *= (1 - 0.85 * crack)[..., None]

    # weathered wood: soft earlywood erodes, latewood stays proud
    hgt = 0.55 * late + 0.14 * fib + 0.06 * fib2 - 0.3 * pores - 2.2 * crack + 0.25 * knot_core
    rough = np.clip(0.74 + 0.07 * fib - 0.14 * late + 0.15 * crack + 0.08 * weather - 0.1 * knot_core, 0.35, 1)
    save_rgb("plank_albedo.png", alb)
    save_rgb("plank_normal.png", normal_map(blur(hgt, 0.6), 2.2))
    save_l("plank_rough.png", rough)
    print("wrote plank")


# ------------------------------------------------------------------- leather
def worley(X, Y, cell, seed):
    """Cellular noise on (float pixel) coordinates: distances to the nearest and
    second-nearest feature point, for a grid of jittered points every `cell` px."""
    rng = np.random.default_rng(seed)
    gh, gw = int(Y.max() // cell) + 3, int(X.max() // cell) + 3
    jx, jy = rng.random((gh, gw)), rng.random((gh, gw))
    cx = np.floor(X / cell).astype(int)
    cy = np.floor(Y / cell).astype(int)
    f1 = np.full(X.shape, 1e9, np.float32)
    f2 = np.full(X.shape, 1e9, np.float32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ny = np.clip(cy + dy, 0, gh - 1)
            nx = np.clip(cx + dx, 0, gw - 1)
            px = (nx + jx[ny, nx]) * cell
            py = (ny + jy[ny, nx]) * cell
            d = np.sqrt((X - px) ** 2 + (Y - py) ** 2)
            f2 = np.where(d < f1, f1, np.minimum(f2, d))
            f1 = np.minimum(f1, d)
    return f1, f2


def make_leather():
    """Old tanned hide lining the dice tray (covers 3.76 x 4.96 world units, not tiled;
    the outer 0.08 on each side is tucked under the rim). Glued down with bitumen, as
    Mesopotamian craftsmen did: a patchy line of old tar shows where it meets the wood.
    Pebbled grain, soft folds, gentle pillowing, a worn landing zone full of little dents
    and scuffs, tide-mark stains, dry cracked patches, sand in the creases, oily edges.
    Where the glue has failed the hide has shrunk back from the wall and lifts in a soft
    bulge; that lift is also written to leather_lift.png to displace the real mesh."""
    W, H = 1152, 1520
    ppu = W / 3.76
    rng = np.random.default_rng(410)
    x = np.arange(W)[None, :] * np.ones((H, 1))
    y = np.arange(H)[:, None] * np.ones((1, W))
    u, v = x / W, y / H

    def unit(n):
        return np.clip(0.5 + 0.5 * n, 0, 1)

    big = fnoise(H, W, 160, 160, 401)
    midn = fnoise(H, W, 40, 40, 402)
    fine = fnoise(H, W, 1.0, 1.0, 403)

    # where the dice land (thrown from the left, they come to rest right of centre)
    land = np.exp(-(((u - 0.62) / 0.28) ** 2 + ((v - 0.5) / 0.36) ** 2))
    ex = np.minimum(x, W - 1 - x) / ppu
    ey = np.minimum(y, H - 1 - y) / ppu
    edge_d = np.minimum(ex, ey)
    edge = np.exp(-edge_d / 0.3)

    # pebbled grain: cells at two scales, domain-warped, flattened where worn
    wx = x + fnoise(H, W, 30, 30, 404) * 5
    wy = y + fnoise(H, W, 30, 30, 405) * 5
    f1, f2 = worley(wx, wy, 11.0, 406)
    g1 = np.exp(-((f2 - f1) / 2.2) ** 2)
    pebble1 = np.clip((f2 - f1) / 7.0, 0, 1) ** 0.5
    f1b, f2b = worley(wx * 1.0, wy * 1.0, 5.0, 407)
    g2 = np.exp(-((f2b - f1b) / 1.1) ** 2)
    wear = np.clip(0.75 * land + 0.4 * unit(midn) * land, 0, 1)
    grain_depth = 1.0 - 0.7 * wear
    groove = np.clip(0.75 * g1 + 0.3 * g2, 0, 1) * grain_depth * unit(fnoise(H, W, 20, 20, 408) * 1.5)

    # long folds and creases, more of them near the walls where the hide bunches
    folds = np.zeros((H, W))
    for k in range(3):
        n = fnoise(H, W, 260, 110, 420 + k)
        folds = np.maximum(folds, np.exp(-(n / 0.16) ** 2) * unit(fnoise(H, W, 200, 200, 430 + k) * 2) * 0.8)
    creases = np.exp(-(fnoise(H, W, 25, 70, 440) / 0.09) ** 2) * np.clip(edge * 1.6, 0, 1) * 0.7
    pillow = blur(fnoise(H, W, 120, 120, 441), 4)

    # glue line: distance (world units) from the inner face of the rim
    TUCK = 0.08
    w = edge_d - TUCK
    # which wall is nearest, and the position along it (world units), for the lifts
    side = np.argmin(np.stack([x, W - 1 - x, y, H - 1 - y]), axis=0)
    along = np.where(side < 2, y / ppu, x / ppu)
    # glue failures: (wall 0=left 1=right 2=top 3=bottom, centre along it, length)
    lifts = [(2, 1.15, 0.9), (1, 3.2, 1.1), (3, 2.6, 0.7), (0, 1.0, 0.6)]
    env = np.zeros((H, W))
    for sd, c0, ln in lifts:
        e = np.clip(1 - ((along - c0) / (ln / 2)) ** 2, 0, 1) ** 1.5 * (side == sd)
        env = np.maximum(env, e)
    gap = 0.06 * env                                          # hide shrunk back from the wall
    bare = np.clip((gap - w) / 0.004 + 0.5, 0, 1) * (env > 0.02)
    lip = np.exp(-((w - gap) / 0.016) ** 2) * env              # curled edge of the hide
    lift = env * np.exp(-np.clip(w - gap, 0, None) / 0.32)    # bulge rising toward the wall
    # loose hide buckles into ripples running away from the wall
    buckle = 0.5 + 0.5 * np.cos(2 * np.pi * along / 0.22 + 2.0 * fnoise(H, W, 60, 60, 464))
    lift_wr = blur(lift * (0.55 + 0.45 * buckle) * (1 + 0.15 * fnoise(H, W, 18, 60, 460)), 1.5)
    # bitumen: a patchy dark line at the rim with the odd smear onto the hide
    patch = unit(fnoise(H, W, 70, 70, 461) * 2.2)
    reach = 0.012 + 0.035 * np.clip(fnoise(H, W, 30, 30, 462) - 0.3, 0, None) * patch
    tar = np.clip((reach - w) / 0.006, 0, 1) * np.clip(patch * 1.8 - 0.25, 0, 1)
    tar = np.maximum(tar, bare)
    soak = np.exp(-np.clip(w, 0, None) / 0.07) * (0.4 + 0.6 * patch)  # tar wicked into the edge

    # dice dents: little corner impressions, thickest where the dice land
    dents = np.zeros((H, W))
    dent_rim = np.zeros((H, W))
    n_d = 0
    while n_d < 420:
        px, py = rng.uniform(0, W), rng.uniform(0, H)
        if rng.random() > 0.08 + 0.92 * np.exp(-(((px / W - 0.62) / 0.28) ** 2 + ((py / H - 0.5) / 0.36) ** 2)):
            continue
        n_d += 1
        r = rng.uniform(1.6, 4.5)
        x0, x1 = int(max(px - 4 * r, 0)), int(min(px + 4 * r, W))
        y0, y1 = int(max(py - 4 * r, 0)), int(min(py + 4 * r, H))
        dd = np.sqrt((x[y0:y1, x0:x1] - px) ** 2 + (y[y0:y1, x0:x1] - py) ** 2) / r
        depth = rng.uniform(0.4, 1.0)
        dents[y0:y1, x0:x1] = np.maximum(dents[y0:y1, x0:x1], depth * np.exp(-dd ** 2))
        dent_rim[y0:y1, x0:x1] = np.maximum(dent_rim[y0:y1, x0:x1], depth * np.exp(-((dd - 1.4) / 0.4) ** 2))

    # scuffs: abraded, lighter streaks along the throw direction
    sw = fnoise(H, W, 60, 60, 459)
    scuff = np.clip((fnoise(H, W, 16, 4, 450) + 0.6 * sw - 1.7) * 0.8, 0, 1) * np.clip(land * 1.4, 0, 1)
    scuff = blur(scuff, 1.2)
    scuff = np.clip(scuff + 0.5 * np.clip((fnoise(H, W, 14, 14, 451) - 1.4), 0, 1) * land, 0, 1)
    # tide marks from old spills: a darker blot with a sharper rim
    blot_n = fnoise(H, W, 85, 85, 452)
    region = np.clip(fnoise(H, W, 300, 300, 453) - 0.2, 0, 1)
    tide_in = np.clip((blot_n - 1.0) * 3, 0, 1) * region
    tide_rim = np.exp(-((blot_n - 1.0) / 0.035) ** 2) * region
    # dried-out patches with fine cracking
    dry = np.clip((fnoise(H, W, 130, 130, 454) - 0.7) * 1.5, 0, 1) * (1 - 0.6 * land)
    cf1, cf2 = worley(wx * 0.8 + 500, wy * 0.8, 16.0, 455)
    crack = np.exp(-((cf2 - cf1) / 0.9) ** 2) * dry
    # sand: caught in the grain near the walls/tacks, plus loose grains
    sand_m = np.clip(groove * (np.exp(-np.clip(w, 0, None) / 0.1) + 0.8 * lip) * unit(fnoise(H, W, 10, 10, 456) * 1.5), 0, 1)
    gr = rng.random((H, W))
    grains = np.clip(blur(((gr < 0.0002 + 0.0025 * edge)).astype(float), 0.5) * 2.0, 0, 1)
    # hands: oily darkening and burnish along the rim
    oil = np.clip(edge * 1.3 * unit(fnoise(H, W, 50, 50, 457) * 1.4), 0, 1)

    # ---------------- colour
    base = np.array([0.42, 0.25, 0.12])
    red = np.array([0.47, 0.25, 0.12])
    yel = np.array([0.46, 0.31, 0.15])
    hue = unit(fnoise(H, W, 180, 180, 458))
    col = base * (1 - hue[..., None] * 0.6) + (red * unit(big)[..., None] + yel * (1 - unit(big))[..., None]) * hue[..., None] * 0.6
    col = col * (1 + 0.1 * big + 0.06 * midn + 0.035 * fine)[..., None]
    col *= (1 + 0.1 * (pebble1 - 0.5) * grain_depth)[..., None]   # tops of pebbles catch a little more colour
    col *= (1 - 0.1 * groove)[..., None]
    col *= (1 - 0.12 * folds - 0.15 * creases)[..., None]
    col *= (1 - 0.3 * oil)[..., None]
    col = col * (1 - 0.25 * tide_in[..., None]) + np.array([0.24, 0.13, 0.06]) * 0.25 * tide_in[..., None]
    col *= (1 - 0.35 * tide_rim)[..., None]
    worn_col = np.array([0.56, 0.4, 0.26])
    col = col * (1 - 0.18 * wear[..., None]) + worn_col * 0.18 * wear[..., None]
    col = col * (1 - 0.35 * scuff[..., None]) + np.array([0.56, 0.42, 0.29]) * 0.35 * scuff[..., None]
    col = col * (1 - 0.25 * dry[..., None]) + np.array([0.5, 0.37, 0.25]) * 0.25 * dry[..., None]
    col *= (1 - 0.35 * crack)[..., None]
    col *= (1 - 0.3 * dents)[..., None]
    col *= (1 - 0.35 * soak)[..., None]
    col *= (1 + 0.12 * lift_wr - 0.25 * lip)[..., None]   # lifted hide is drier and paler, its torn-up edge dark
    sand_col = np.array([0.74, 0.6, 0.42])
    col = col * (1 - 0.4 * sand_m[..., None]) + sand_col * 0.4 * sand_m[..., None]
    col = col * (1 - 0.6 * grains[..., None]) + sand_col * 0.6 * grains[..., None]

    tar_col = np.array([0.05, 0.035, 0.025]) * (0.8 + 0.4 * unit(fnoise(H, W, 6, 6, 463)))[..., None]
    col = col * (1 - tar[..., None]) + tar_col * tar[..., None]

    # ---------------- height (0..1 for parallax) and normals
    hgt = (0.5 * pillow + 0.35 * pebble1 * grain_depth - 0.55 * groove - 0.25 * g2 * grain_depth
           - 1.2 * blur(folds, 2) - 0.8 * creases + 0.5 * blur(folds, 9)
           - 1.4 * dents + 0.3 * dent_rim - 0.6 * crack + 0.08 * fine
           + blur(1.0 * lip - 0.5 * bare + 0.1 * tar, 3))
    hgt = blur(hgt, 0.6)
    rough = np.clip(0.6 + 0.12 * groove - 0.18 * oil * pebble1 - 0.1 * wear * (1 - scuff) + 0.25 * scuff
                    + 0.2 * dry + 0.25 * sand_m + 0.2 * grains - 0.1 * tide_in + 0.04 * midn + 0.15 * lift_wr, 0.28, 1)
    rough = rough * (1 - tar) + 0.22 * tar   # bitumen stays glossy

    save_rgb("leather_albedo.png", col)
    save_rgb("leather_normal.png", normal_map(hgt, 1.6))
    lo, hi = np.percentile(hgt, 0.5), np.percentile(hgt, 99.5)
    save_l("leather_height.png", (hgt - lo) / (hi - lo))
    save_l("leather_rough.png", rough)
    # low-res displacement for the mesh: pillowing plus the lifted areas, 1.0 = LEATHER_LIFT_MAX in main.gd
    geo = np.clip(0.06 * (blur(pillow, 6) + 1.5) / 3.0 + 0.94 * lift_wr, 0, 1)
    Image.fromarray((blur(geo, 3) * 255 + 0.5).astype(np.uint8), "L").resize((192, 254), Image.LANCZOS).save(
        os.path.join(OUT, "leather_lift.png"))
    print("wrote leather")


# ---------------------------------------------------------------------- sand
def make_sand():
    """Tileable desert sand, 4 x 4 world units: wind ripples, coloured grains."""
    S = 1024
    rng = np.random.default_rng(501)
    x = np.arange(S)[None, :] * np.ones((S, 1))
    y = np.arange(S)[:, None] * np.ones((1, S))
    low = fnoise(S, S, 200, 200, 502)
    warp = fnoise(S, S, 160, 220, 503) * 1.1 + fnoise(S, S, 40, 40, 504) * 0.12
    ph = (34 * x / S + 9 * y / S + warp) % 1.0
    # asymmetric ripple: long gentle stoss side, short steep lee side
    rip = np.where(ph < 0.72, ph / 0.72, (1 - ph) / 0.28)
    rip = blur(rip, 2.5)
    amp = np.clip(0.55 + 0.45 * low, 0.15, 1.0)
    rip = (rip - 0.5) * amp

    grain = fnoise(S, S, 0.55, 0.55, 505)
    grain2 = fnoise(S, S, 1.6, 1.6, 506)
    u = rng.random((S, S))
    base = np.array([0.74, 0.57, 0.38])
    col = base * (1 + 0.07 * low + 0.05 * grain2 + 0.06 * grain)[..., None] * np.ones((S, S, 3))
    for lo_, hi_, c in ((0.0, 0.025, (0.30, 0.25, 0.21)), (0.025, 0.07, (0.93, 0.86, 0.72)),
                        (0.07, 0.1, (0.66, 0.38, 0.22)), (0.1, 0.115, (0.52, 0.48, 0.44))):
        m = ((u >= lo_) & (u < hi_)).astype(float)
        m = np.clip(blur(m, 0.45) * 1.6, 0, 1)
        col = col * (1 - m[..., None]) + np.array(c) * m[..., None]
    # coarser, darker grains gather in the troughs; crests are paler
    col *= (1 + 0.16 * rip)[..., None]
    tint = np.clip(0.5 + 0.5 * fnoise(S, S, 120, 120, 507), 0, 1)
    col *= (np.array([1.03, 0.98, 0.93]) * tint[..., None] + np.array([0.97, 1.0, 1.04]) * (1 - tint[..., None]))

    hgt = 6.0 * rip + 0.35 * grain + 0.25 * grain2
    save_rgb("sand_albedo.png", col)
    save_rgb("sand_normal.png", normal_map(hgt, 0.8))
    print("wrote sand")



# ------------------------------------------------------------------------- UI
def stepped(x0, y0, x1, y1, s):
    return [(x0 + 2 * s, y0), (x1 - 2 * s, y0), (x1 - 2 * s, y0 + s), (x1 - s, y0 + s), (x1 - s, y0 + 2 * s),
            (x1, y0 + 2 * s), (x1, y1 - 2 * s), (x1 - s, y1 - 2 * s), (x1 - s, y1 - s), (x1 - 2 * s, y1 - s),
            (x1 - 2 * s, y1), (x0 + 2 * s, y1), (x0 + 2 * s, y1 - s), (x0 + s, y1 - s), (x0 + s, y1 - 2 * s),
            (x0, y1 - 2 * s), (x0, y0 + 2 * s), (x0 + s, y0 + 2 * s), (x0 + s, y0 + s), (x0 + 2 * s, y0 + s)]


def make_ui():
    """Carved wood plaque with stepped corners, gold inlay lines and lapis studs.
    One 9-slice texture serves buttons, plaques and the title banner."""
    W, H, SS = 280, 76, 4
    variants = {
        "normal": dict(interior=(0.11, 0.07, 0.04), gold=1.0, flip=False, dim=1.0),
        "hover": dict(interior=(0.21, 0.125, 0.06), gold=1.15, flip=False, dim=1.05),
        "pressed": dict(interior=(0.06, 0.04, 0.025), gold=0.85, flip=True, dim=0.9),
        "disabled": dict(interior=(0.1, 0.085, 0.075), gold=0.45, flip=False, dim=0.6),
    }

    def layer(draw_fn):
        im = Image.new("L", (W * SS, H * SS), 0)
        draw_fn(ImageDraw.Draw(im))
        im = im.resize((W, H), Image.LANCZOS)
        return np.asarray(im, dtype=np.float32) / 255.0

    stp = 7 * SS
    outer = layer(lambda d: d.polygon(stepped(2 * SS, 2 * SS, (W - 2) * SS, (H - 2) * SS, 6 * SS), fill=255))
    inner = layer(lambda d: d.polygon(stepped(15 * SS, 15 * SS, (W - 15) * SS, (H - 15) * SS, 4 * SS), fill=255))

    def gold_lines(d):
        d.line(stepped(6 * SS, 6 * SS, (W - 6) * SS, (H - 6) * SS, 5 * SS) + [stepped(6 * SS, 6 * SS, (W - 6) * SS, (H - 6) * SS, 5 * SS)[0]], fill=255, width=3 * SS, joint="curve")
        pts = stepped(12 * SS, 12 * SS, (W - 12) * SS, (H - 12) * SS, 4 * SS)
        d.line(pts + [pts[0]], fill=255, width=2 * SS, joint="curve")

    gold_m = layer(gold_lines)

    def studs(d):
        for (x, y) in ((27, 27), (W - 27, 27), (27, H - 27), (W - 27, H - 27)):
            d.ellipse(((x - 3.2) * SS, (y - 3.2) * SS, (x + 3.2) * SS, (y + 3.2) * SS), fill=255)

    lapis_m = layer(studs)

    def diamonds(d):
        for x in (20, W - 20):
            y = H / 2
            d.polygon([(x * SS, (y - 7) * SS), ((x + 5) * SS, y * SS), (x * SS, (y + 7) * SS), ((x - 5) * SS, y * SS)], fill=255)

    dia_m = layer(diamonds)

    frame = np.clip(outer - inner, 0, 1)
    alb, fh, _ = wood(H, W, 77, light=(0.5, 0.31, 0.16), dark=(0.24, 0.13, 0.06), rings=3)
    ygrad = np.linspace(0, 1, H)[:, None] * np.ones((1, W))
    gold_col = np.array([1.0, 0.82, 0.42])[None, None, :] * (1 - ygrad[..., None]) + np.array([0.68, 0.46, 0.15])[None, None, :] * ygrad[..., None]
    speck = 0.9 + 0.1 * fnoise(H, W, 1.0, 1.0, 78)

    for name, v in variants.items():
        interior = np.array(v["interior"])[None, None, :] * speck[..., None]
        col = alb * frame[..., None] + interior * inner[..., None]
        height = frame * 1.0 + inner * 0.45 + gold_m * 0.25 + dia_m * 0.2 + lapis_m * 0.25
        hb = blur(height, 0.9)
        gy, gx = np.gradient(hb)
        lit = np.clip(-(gx + gy) * 2.4, -0.55, 0.55)
        if v["flip"]:
            lit = -lit
        gm = np.clip(gold_m + dia_m, 0, 1)[..., None]
        col = col * (1 - gm) + gold_col * v["gold"] * gm
        lm = lapis_m[..., None]
        col = col * (1 - lm) + np.array([0.08, 0.2, 0.55]) * lm
        col = col * (1 + lit)[..., None] * v["dim"]
        if name == "disabled":
            g = col.mean(axis=2, keepdims=True)
            col = col * 0.5 + g * 0.5
        rgba = np.dstack([np.clip(col, 0, 1), outer])
        Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, "ui_%s.png" % name))
    print("wrote ui")


ALL = {"board": make_board, "strip": make_strip, "plate": make_plate, "wood": make_wood_tile,
       "stone": make_stone, "plank": make_plank, "leather": make_leather, "sand": make_sand, "ui": make_ui}

if __name__ == "__main__":
    import sys
    # optional args pick which sets to regenerate, e.g. `make_textures.py sand plank`
    for name in sys.argv[1:] or ALL:
        ALL[name]()
