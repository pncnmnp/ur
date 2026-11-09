"""Boot splash: an old, worn papyrus sheet lying on the game's desert sand, the full
painting (icons/icon_1024.png, pixel-for-pixel, no resampling) attached to it, and the
title written beneath in black ink (Papyrus font) between red-ochre glyphs from the board.

The sand is built the way the game's sand shader does it (main.gd SAND_SHADER): the
sand albedo tiled and mixed with a larger copy of itself, slow light/dark patches, and
the ripples of assets/sand_normal.png lit by a low sun, plus long dune swells.

Canvas is 3200x1800: twice the 1600x900 window, so on a Retina screen the painting is
shown at its native 1024 px. Written as lossless PNG to icons/splash.png.

    venv/bin/python tools/make_splash.py      (needs numpy + pillow)
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_textures import g_ankh, g_eye, g_scarab  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "icons" / "icon_1024.png"
OUT = ROOT / "icons" / "splash.png"
SAND_ALB = ROOT / "assets" / "sand_albedo.png"
SAND_NRM = ROOT / "assets" / "sand_normal.png"
FONT = "/System/Library/Fonts/Supplemental/Papyrus.ttc"
FONT_INDEX = 1  # the wide cut of Papyrus

W, H = 3200, 1800
TITLE = "The Royal Game of Ur"
FONT_SIZE = 160
SUN = np.array([-0.55, -0.45, 0.70])  # low sun from the upper left (x right, y down, z up)
WIND = (0.94, 0.34)  # main.gd SAND_WIND: ripples run across it


def rng_noise(h, w, scale, seed):
    """Smooth value noise in 0..1 with features about `scale` px across."""
    r = np.random.default_rng(seed)
    gh, gw = h // scale + 3, w // scale + 3
    g = Image.fromarray((r.random((gh, gw)) * 255).astype(np.uint8))
    g = g.resize((gw * scale, gh * scale), Image.BICUBIC).crop((scale, scale, scale + w, scale + h))
    return np.asarray(g, np.float32) / 255.0


def tiled(img, scale, offset=(0, 0)):
    """img tiled over the canvas at `scale`, shifted by `offset` (fraction of a tile)."""
    t = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    out = Image.new(img.mode, (W, H))
    ox, oy = int(offset[0] * t.width), int(offset[1] * t.height)
    for y in range(-oy, H, t.height):
        for x in range(-ox, W, t.width):
            out.paste(t, (x, y))
    return np.asarray(out, np.float32) / 255.0


def sand() -> np.ndarray:
    alb = Image.open(SAND_ALB).convert("RGB")
    nrm = Image.open(SAND_NRM).convert("RGB")
    a = tiled(alb, 1.0)
    b = tiled(alb, 3.4, (0.37, 0.71))
    macro = rng_noise(H, W, 700, 1) * 0.6 + rng_noise(H, W, 230, 2) * 0.4
    col = (a * 0.7 + b * 0.3) * (0.9 + 0.17 * macro)[..., None]
    warm = rng_noise(H, W, 1100, 3)[..., None] * 0.6
    col = col * (1 - warm) + col * np.array([1.06, 0.96, 0.88]) * warm

    # ripples: the normal map, lit by the sun
    n = tiled(nrm, 1.0) * 2.0 - 1.0
    n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-6
    sun = SUN / np.linalg.norm(SUN)
    lit = np.clip((n * sun).sum(-1), 0, 1) / sun[2]
    col *= (0.55 + 0.45 * lit)[..., None] * 1.08

    # long dune swells across the wind, lit on the windward face
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    along = xx * WIND[0] + yy * WIND[1]
    warp = rng_noise(H, W, 500, 4) * 260
    swell = np.sin((along + warp) / 360.0 * 2 * math.pi)
    col *= (1.0 + 0.07 * swell)[..., None]

    # vignette: the light falls off toward the edges
    r = np.hypot((xx - W / 2) / (W / 2), (yy - H / 2) / (H / 2))
    col *= (1.0 - 0.38 * np.clip(r - 0.35, 0, 1) ** 1.6)[..., None]
    return np.clip(col, 0, 1)


def aniso(h, w, sx, sy, seed):
    """Value noise in 0..1, features `sx` px across in x and `sy` px in y."""
    r = np.random.default_rng(seed)
    gh, gw = max(2, h // sy + 3), max(2, w // sx + 3)
    g = Image.fromarray((r.random((gh, gw)) * 255).astype(np.uint8))
    g = g.resize((gw * sx, gh * sy), Image.BICUBIC).crop((sx, sy, sx + w, sy + h))
    return np.asarray(g, np.float32) / 255.0


def blurred(a, radius):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(radius)), np.float32) / 255.0


def strips(h, w, axis, seed):
    """Papyrus is two layers of pith strips laid crosswise. Returns, for strips running
    along `axis` (0 = vertical strips, 1 = horizontal): per-pixel tone, and per-pixel strip
    index (for ragged strip ends at the sheet's edges)."""
    r = np.random.default_rng(seed)
    n = w if axis == 0 else h
    edges, x = [0], 0
    while x < n:
        x += int(r.integers(38, 78))
        edges.append(min(x, n))
    idx = np.zeros(n, int)
    tone = np.zeros(n, np.float32)
    for k in range(len(edges) - 1):
        a, b = edges[k], edges[k + 1]
        idx[a:b] = k
        # each strip a touch lighter or darker, darker at its overlapping edges
        u = np.linspace(0, 1, b - a)
        tone[a:b] = r.normal(0, 0.03) - 0.025 * np.exp(-((u * (1 - u)) / 0.01)) * r.uniform(0.3, 1)
    # fibres: long, slightly wavering streaks along the strip, some darker, some paler
    dark = fibre_lines(h, w, axis, n // 5, seed + 1)
    pale = fibre_lines(h, w, axis, n // 9, seed + 2)
    if axis == 0:
        streak = aniso(h, w, 2, 220, seed + 3)
        t = tone[None, :] - 0.20 * dark + 0.10 * pale + (streak - 0.5) * 0.10
        return t, idx[None, :].repeat(h, 0), len(edges)
    streak = aniso(h, w, 220, 2, seed + 3)
    t = tone[:, None] - 0.20 * dark + 0.10 * pale + (streak - 0.5) * 0.10
    return t, idx[:, None].repeat(w, 1), len(edges)


def fibre_lines(h, w, axis, count, seed):
    """Thin wavering fibre lines running along `axis` (0 = vertical), 0..1."""
    r = np.random.default_rng(seed)
    im = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(im)
    n_across, n_along = (w, h) if axis == 0 else (h, w)
    for _ in range(count):
        p = r.uniform(0, n_across)
        a = r.uniform(-200, n_along)
        length = r.uniform(250, 1600)
        pts, t = [], a
        while t < a + length:
            p += r.normal(0, 1.2)
            pts.append((p, t) if axis == 0 else (t, p))
            t += 40
        if len(pts) > 1:
            d.line(pts, fill=int(r.uniform(60, 230)), width=int(r.choice([1, 1, 2, 2, 3])))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(0.7)), np.float32) / 255.0


def papyrus_sheet(sw, sh, seed=7):
    """An old, worn papyrus sheet: RGB (0..1) and an alpha mask with frayed, torn edges."""
    r = np.random.default_rng(seed)
    v_tone, v_idx, nv = strips(sh, sw, 0, seed)
    h_tone, h_idx, nh = strips(sh, sw, 1, seed + 10)
    tone = v_tone * 0.55 + h_tone * 0.75  # the top (horizontal) layer shows more
    col = np.array([0.84, 0.73, 0.52]) * (1 + tone)[..., None]

    # age: blotchy stains, a few water marks with darker tide lines, foxing specks
    stain = aniso(sh, sw, 260, 260, seed + 3) * 0.6 + aniso(sh, sw, 90, 90, seed + 4) * 0.4
    stain = np.clip((stain - 0.5) * 2.4, 0, 1)
    col *= (1 - 0.22 * stain)[..., None] * np.array([1.0, 0.96, 0.9])
    yy, xx = np.mgrid[0:sh, 0:sw].astype(np.float32)
    for _ in range(3):
        cx, cy, rad = r.uniform(0, sw), r.uniform(0, sh), r.uniform(180, 380)
        d = np.hypot(xx - cx, yy - cy) / rad + (aniso(sh, sw, 80, 80, int(r.integers(1e6))) - 0.5) * 0.3
        inside = blurred((d < 1).astype(np.float32), 30)
        col *= (1 - 0.05 * inside - 0.06 * np.exp(-((d - 1) / 0.06) ** 2))[..., None]
    specks = aniso(sh, sw, 4, 4, seed + 5)
    col *= (1 - 0.3 * np.clip((specks - 0.965) * 20, 0, 1))[..., None]

    # creases where it was folded: a dark line with a pale lip
    for x in (sw * 0.5 + r.uniform(-40, 40),):
        dx = xx - x - (aniso(sh, sw, 400, 300, seed + 6) - 0.5) * 30
        col *= (1 - 0.13 * np.exp(-(dx / 3) ** 2) + 0.05 * np.exp(-((dx - 6) / 4) ** 2))[..., None]
    for y in (sh * 0.36 + r.uniform(-30, 30),):
        dy = yy - y - (aniso(sh, sw, 300, 400, seed + 7) - 0.5) * 30
        col *= (1 - 0.11 * np.exp(-(dy / 3) ** 2) + 0.04 * np.exp(-((dy - 6) / 4) ** 2))[..., None]

    # frayed outline: each strip ends at its own ragged length, the edge wanders
    v_off = r.uniform(0, 1, nv)[v_idx] ; h_off = r.uniform(0, 1, nh)[h_idx]
    wob = aniso(sh, sw, 140, 140, seed + 8) - 0.5
    fine = aniso(sh, sw, 9, 9, seed + 9) - 0.5
    inset_tb = 18 + 34 * v_off + 40 * wob + 10 * fine  # top/bottom: ends of the vertical strips
    inset_lr = 18 + 34 * h_off + 40 * wob + 10 * fine  # left/right: ends of the horizontal strips
    alpha = ((yy > inset_tb) & (sh - 1 - yy > inset_tb) & (xx > inset_lr) & (sw - 1 - xx > inset_lr))
    alpha = alpha.astype(np.float32)
    # bites out of the edge: torn and crumbled away
    for _ in range(9):
        side = r.integers(4)
        cx = r.uniform(0, sw) if side < 2 else (0 if side == 2 else sw)
        cy = r.uniform(0, sh) if side >= 2 else (0 if side == 0 else sh)
        rad = r.uniform(40, 130)
        d = np.hypot(xx - cx, yy - cy) / rad + (aniso(sh, sw, 25, 25, int(r.integers(1e6))) - 0.5) * 0.5
        alpha *= d > 1
    # a corner gone
    cx, cy = sw * r.choice([0, 1]), sh * r.choice([0, 1])
    alpha *= (np.abs(xx - cx) + np.abs(yy - cy) + (fine * 40)) > r.uniform(150, 230)
    # a few worm holes
    for _ in range(40):
        cx, cy, rad = r.uniform(80, sw - 80), r.uniform(80, sh - 80), r.uniform(6, 16)
        if 160 < cx < sw - 160 and cy > 160:
            continue  # only along the sides and top, clear of the painting and title
        d = np.hypot(xx - cx, yy - cy) / rad + fine * 0.6
        alpha *= d > 1
        col *= (1 - 0.35 * np.exp(-((d - 1.2) / 0.5) ** 2))[..., None]

    # the edges are darker, brittle and browned
    near = 1 - blurred(alpha, 30)
    col *= (1 - 0.45 * np.clip(near * 1.6, 0, 1))[..., None] * np.array([1.0, 0.94, 0.86])
    col *= (1 - 0.2 * np.clip((1 - blurred(alpha, 6)) * 3, 0, 1))[..., None]
    alpha = np.clip(blurred(alpha, 1.0), 0, 1)
    return np.clip(col, 0, 1), alpha


def ink(col, mask, colour, strength, seed):
    """Brush ink on the papyrus: soaked unevenly, the fibres showing through."""
    m = np.asarray(mask.filter(ImageFilter.GaussianBlur(0.9)), np.float32) / 255.0
    h, w = m.shape
    patchy = aniso(h, w, 50, 50, seed) * 0.5 + aniso(h, w, 6, 30, seed + 1) * 0.5
    a = (m * strength * (0.72 + 0.28 * patchy))[..., None]
    return col * (1 - a) + (col * np.array(colour) * 1.6).clip(0, 1) * a * 0.35 + np.array(colour) * a * 0.65


def main() -> None:
    logo = Image.open(LOGO).convert("RGB")
    font = ImageFont.truetype(FONT, FONT_SIZE, index=FONT_INDEX)
    tx0, ty0, tx1, ty1 = font.getbbox(TITLE)
    text_w, text_h = tx1 - tx0, ty1 - ty0

    # the sheet: the painting, then the title, with old-book margins
    m_top, m_side, m_bot, gap = 95, 200, 115, 85
    gx = [150, 315]  # glyph centres, out from the title's ends
    sw = text_w + 2 * (gx[-1] + 70 + m_side - 80)
    sh = m_top + logo.height + gap + text_h + m_bot
    sx, sy = (W - sw) // 2, (H - sh) // 2
    lx, top = (W - logo.width) // 2, sy + m_top
    tx, ty = (W - text_w) // 2, top + logo.height + gap

    canvas = sand()
    pcol, palpha = papyrus_sheet(sw, sh)

    # the sheet's shadow on the sand, away from the sun, then the sheet
    shadow = np.zeros((H, W), np.float32)
    shadow[sy + 22: sy + 22 + sh, sx + 26: sx + 26 + sw] = palpha
    shadow = blurred(shadow, 18)
    canvas *= (1 - 0.45 * shadow)[..., None]
    region = canvas[sy: sy + sh, sx: sx + sw]
    canvas[sy: sy + sh, sx: sx + sw] = region * (1 - palpha[..., None]) + pcol * palpha[..., None]

    # title in black ink, glyphs in red ochre, the way scribes wrote
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).text((tx - tx0, ty - ty0), TITLE, font=font, fill=255)
    mask = mask.filter(ImageFilter.MaxFilter(3))
    canvas = ink(canvas, mask, (0.13, 0.08, 0.05), 0.92, 21)
    gmask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(gmask)
    gy = ty + text_h / 2 - 6
    for g, off in zip([g_eye, g_ankh], gx):
        g(d, tx - off, gy, 60, 8)
    for g, off in zip([g_ankh, g_scarab], gx):
        g(d, tx + text_w + off, gy, 60, 8)
    canvas = ink(canvas, gmask, (0.52, 0.17, 0.08), 0.85, 31)

    out = Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8), "RGB")

    # the painting attached to the sheet: a faint shadow where it sits proud, pasted 1:1
    sh_l = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sh_l).rectangle([lx + 6, top + 9, lx + logo.width + 8, top + logo.height + 12], fill=150)
    sh_l = sh_l.filter(ImageFilter.GaussianBlur(9))
    out.paste(Image.new("RGB", (W, H), (60, 38, 18)), (0, 0), sh_l)
    out.paste(logo, (lx, top))

    out.save(OUT, optimize=True)
    print(f"wrote {OUT} ({W}x{H})")


if __name__ == "__main__":
    main()
