"""Boot splash: a real ancient papyrus lying on the game's desert sand, the full painting
(icons/icon_1024.png, at its native size, no resampling) painted onto it, its edges
fading into the sheet and the fibres showing through, and the title
written beneath in black ink (Papyrus font) between red-ochre glyphs from the board.

The papyrus is a photograph of a real blank sheet: The Metropolitan Museum of Art,
26.3.317, "Blank sheet of papyrus", released CC0 (tools/source/). Its two strips are laid
the way scroll sheets were pasted, the upper strip's worn, arch-bitten edge overlapping the
lower one, running off both sides of the screen like an unrolled scroll. It is given a
gentle curl lit by the same low sun as the sand, a shadow that grows where it lifts, and
wind-blown sand drifted over its windward edge and scattered across it.

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
PAPYRUS = ROOT / "tools" / "source" / "met_blank_papyrus_26.3.317.jpg"
FONT = "/System/Library/Fonts/Supplemental/Papyrus.ttc"
FONT_INDEX = 1  # the wide cut of Papyrus

W, H = 3200, 1800
TITLE = "The Royal Game of Ur"
CREDIT = "Designed by Parth Parikh"
CREDIT_SIZE = 64
RIGHT_MARGIN = 110  # the credit sits at the bottom right, this far from the edge
FONT_SIZE = 150
SUN = np.array([-0.55, -0.45, 0.70])  # low sun from the upper left (x right, y down, z up)
WIND = (0.94, 0.34)  # main.gd SAND_WIND: ripples run across it

# In the scan (4000x1973): the two strips, and where they are cut from it.
STRIP_A = (0, 200, 4000, 990)      # upper strip, worn arches along its bottom edge
STRIP_B = (0, 990, 4000, 1800)     # lower strip
B_TUCK = 262                       # B slides this far up under A's bitten edge
SCALE = 1.23                       # scan px -> canvas px
# The strips are longer than the screen, so the scroll is shortened the way scrolls were
# made: its real left-end sheet (each strip's own left end) pasted onto the main length,
# whose real right end is kept. Scan x ranges: (left-end sheet), (main length).
A_SHEETS = ((210, 510), (1840, 3820))
B_SHEETS = ((1260, 1560), (1840, 3820))


# ------------------------------------------------------------------------- noise
def rng_noise(h, w, scale, seed):
    """Smooth value noise in 0..1 with features about `scale` px across."""
    r = np.random.default_rng(seed)
    gh, gw = h // scale + 3, w // scale + 3
    g = Image.fromarray((r.random((gh, gw)) * 255).astype(np.uint8))
    g = g.resize((gw * scale, gh * scale), Image.BICUBIC).crop((scale, scale, scale + w, scale + h))
    return np.asarray(g, np.float32) / 255.0


def blurred(a, radius):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(radius)), np.float32) / 255.0


def tiled(img, scale, offset=(0, 0)):
    """img tiled over the canvas at `scale`, shifted by `offset` (fraction of a tile)."""
    t = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    out = Image.new(img.mode, (W, H))
    ox, oy = int(offset[0] * t.width), int(offset[1] * t.height)
    for y in range(-oy, H, t.height):
        for x in range(-ox, W, t.width):
            out.paste(t, (x, y))
    return np.asarray(out, np.float32) / 255.0


# -------------------------------------------------------------------------- sand
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

    # long dune swells across the wind
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    along = xx * WIND[0] + yy * WIND[1]
    warp = rng_noise(H, W, 500, 4) * 260
    swell = np.sin((along + warp) / 360.0 * 2 * math.pi)
    col *= (1.0 + 0.07 * swell)[..., None]
    return np.clip(col, 0, 1)


def vignette(col):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    r = np.hypot((xx - W / 2) / (W / 2), (yy - H / 2) / (H / 2))
    return col * (1.0 - 0.38 * np.clip(r - 0.35, 0, 1) ** 1.6)[..., None]


# ----------------------------------------------------------------------- papyrus
def cut_out(scan, box):
    """A strip of the scan and its mask: papyrus is darker and more saturated than the
    museum's cream mount. The mask is pulled in a pixel and softened so no mount fringe."""
    a = np.asarray(scan.crop(box), np.float32) / 255.0
    lum = a @ np.array([0.3, 0.59, 0.11])
    mx, mn = a.max(-1), a.min(-1)
    sat = (mx - mn) / (mx + 1e-6)
    m = Image.fromarray(((lum < 0.80) & (sat > 0.2)).astype(np.uint8) * 255)
    m = m.filter(ImageFilter.MedianFilter(5)).filter(ImageFilter.MinFilter(5))
    m = m.filter(ImageFilter.GaussianBlur(1.2))
    return a, np.asarray(m, np.float32) / 255.0


def join(a, m, sheets):
    """Paste the strip's left-end sheet onto its main length (scan x ranges)."""
    (l0, l1), (r0, r1) = sheets
    return np.concatenate([a[:, l0:l1], a[:, r0:r1]], 1), np.concatenate([m[:, l0:l1], m[:, r0:r1]], 1)


def place(a, m, x0, y0):
    """Scale a scan strip to the canvas and position its top-left at (x0, y0)."""
    w, h = round(a.shape[1] * SCALE), round(a.shape[0] * SCALE)
    img = Image.fromarray((a * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS)
    msk = Image.fromarray((m * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS)
    ox, oy = round(x0), round(y0)
    col = np.zeros((H, W, 3), np.float32)
    alpha = np.zeros((H, W), np.float32)
    # paste the overlap of the strip and the canvas
    sx0, sy0 = max(0, -ox), max(0, -oy)
    dx0, dy0 = max(0, ox), max(0, oy)
    cw, ch = min(w - sx0, W - dx0), min(h - sy0, H - dy0)
    col[dy0:dy0 + ch, dx0:dx0 + cw] = np.asarray(img, np.float32)[sy0:sy0 + ch, sx0:sx0 + cw] / 255.0
    alpha[dy0:dy0 + ch, dx0:dx0 + cw] = np.asarray(msk, np.float32)[sy0:sy0 + ch, sx0:sx0 + cw] / 255.0
    return col, alpha


def shade_from_height(hgt, strength):
    """Diffuse light from the sun on a height field, 1.0 where flat."""
    gy, gx = np.gradient(hgt)
    n = np.dstack([-gx * strength, -gy * strength, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    sun = SUN / np.linalg.norm(SUN)
    return np.clip((n * sun).sum(-1), 0, 1) / sun[2]


def ink(col, mask, colour, strength, seed):
    """Ink soaked into the papyrus: multiplied in, so the fibres show through, unevenly."""
    m = np.asarray(mask.filter(ImageFilter.GaussianBlur(0.9)), np.float32) / 255.0
    patchy = rng_noise(H, W, 40, seed) * 0.5 + rng_noise(H, W, 9, seed + 1) * 0.5
    a = (m * strength * (0.75 + 0.25 * patchy))[..., None]
    return col * (1 - a + a * np.array(colour))


def grain_noise(sx, sy, seed):
    """Value noise in 0..1, streaked: features `sx` px across in x and `sy` px in y."""
    r = np.random.default_rng(seed)
    gh, gw = H // sy + 3, W // sx + 3
    g = Image.fromarray((r.random((gh, gw)) * 255).astype(np.uint8))
    g = g.resize((gw * sx, gh * sy), Image.BICUBIC).crop((sx, sy, sx + W, sy + H))
    return np.asarray(g, np.float32) / 255.0


def pigment(col, mask, colour, strength, seed):
    """Brush-painted pigment worked into the papyrus, centuries old: the stroke's edge
    frays along the grain of the fibres; pigment settles in the grooves and skips the
    raised fibres; a faint stain wicks out along the fibres; and it has worn away in
    patches. Multiplied in, so the sheet shows through everywhere."""
    soft = np.asarray(mask.filter(ImageFilter.GaussianBlur(1.6)), np.float32) / 255.0
    # frayed edge: the cut-off wanders with streaky noise along both fibre directions
    grain = grain_noise(2, 26, seed) * 0.5 + grain_noise(26, 2, seed + 1) * 0.5
    lumpy = rng_noise(H, W, 14, seed + 2)
    thr = 0.5 + (grain - 0.5) * 0.5 + (lumpy - 0.5) * 0.2
    m = np.clip((soft - thr + 0.02) / 0.24, 0, 1)
    m = m * m * (3 - 2 * m)
    # how the sheet takes the pigment: more in its grooves, less on raised fibres
    lum = col @ np.array([0.3, 0.59, 0.11])
    detail = lum / np.maximum(blurred(lum, 5), 1e-3)
    take = np.clip(1.0 - (detail - 1.0) * 3.0, 0.45, 1.25)
    # loaded brush vs. dry: slow variation in density, and worn, flaked patches
    load = 0.78 + 0.22 * rng_noise(H, W, 60, seed + 3)
    wear = np.clip((rng_noise(H, W, 22, seed + 4) - 0.6) * 3.5, 0, 1)
    flake = np.clip((rng_noise(H, W, 4, seed + 5) - 0.8) * 6, 0, 1)
    dens = take * load * (1 - 0.55 * wear) * (1 - 0.6 * flake)
    # a faint stain wicked out along the fibres around the stroke
    wick = np.asarray(mask.filter(ImageFilter.BoxBlur(6)), np.float32) / 255.0
    a = np.clip(m * dens + 0.10 * wick * (1 - m), 0, 1) * strength
    a = a[..., None]
    return col * (1 - a + a * np.array(colour))


def credit_mask(alpha, clear=22, bottom_margin=22):
    """The credit line's mask, at the bottom right on the sand below the papyrus: entirely below the
    sheet's lowest point (arches, lifted edges and its shadow) under the text, by `clear`
    px, shrinking the text until it fits above the bottom of the screen."""
    for size in range(CREDIT_SIZE, 30, -2):
        f = ImageFont.truetype(FONT, size, index=FONT_INDEX)
        x0, y0, x1, y1 = f.getbbox(CREDIT, stroke_width=2)
        left = W - RIGHT_MARGIN - (x1 - x0)  # bottom right
        cols = alpha[:, max(0, left - clear): left + (x1 - x0) + clear + 40]  # +40: shadow falls right
        rows = np.nonzero((cols > 0.02).any(1))[0]
        y = int(rows.max()) + clear + 14  # + the shadow's reach below the sheet
        if y + (y1 - y0) <= H - bottom_margin:
            m = Image.new("L", (W, H), 0)
            ImageDraw.Draw(m).text((left - x0, y - y0), CREDIT, font=f, fill=255,
                                   stroke_width=2, stroke_fill=255)
            print(f"credit: size {size}, top y {y}")
            return m
    raise SystemExit("credit does not fit below the papyrus")


def carve(base, mask):
    """Press `mask` (L, 255 = cut) into the sand: a shaded floor, a dark wall on the side
    away from the sun, a lit lip on the side facing it."""
    m = np.asarray(mask.filter(ImageFilter.GaussianBlur(1.0)), np.float32)[..., None] / 255.0

    def shifted(dx, dy, blur):
        s = mask.transform(mask.size, Image.AFFINE, (1, 0, -dx, 0, 1, -dy))
        return np.asarray(s.filter(ImageFilter.GaussianBlur(blur)), np.float32)[..., None] / 255.0

    inner_shadow = np.clip(m - shifted(4, 5, 2), 0, 1)
    lip = np.clip(shifted(3, 4, 2) - m, 0, 1)
    floor = base * np.array([0.42, 0.31, 0.22])
    out = base * (1 - m) + floor * m
    out = out * (1 - 0.5 * inner_shadow)
    return out + (1 - out) * 0.4 * lip


def paint_on(col, logo, lx, top):
    """The painting as if painted onto the papyrus rather than stuck on: its edges fade
    out unevenly, like a brushed edge, with a faint darker rim where the pigment pooled;
    the papyrus fibres show through it (lightly in the middle, more toward the edges);
    the sheet's curl and shading carry across it; and it has aged a touch into the sheet."""
    S = logo.width
    R = col[top:top + S, lx:lx + S]
    P = np.asarray(logo, np.float32) / 255.0
    lum = R @ np.array([0.3, 0.59, 0.11])
    fibre = np.clip(lum / np.maximum(blurred(lum, 10), 1e-3), 0.7, 1.3)
    light = blurred(lum, 60)
    light = np.clip(light / light.mean(), 0.85, 1.15)

    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    u = np.minimum(np.minimum(xx, S - 1 - xx), np.minimum(yy, S - 1 - yy))
    n = rng_noise(S, S, 48, 61) * 0.75 + rng_noise(S, S, 16, 62) * 0.25
    m = np.clip((u + (n - 0.5) * 46 - 4) / 70, 0, 1)
    m = m * m * (3 - 2 * m)

    P = P * 0.94 + R * 0.06                                      # aged into the sheet
    P = P * (fibre ** (0.6 + 0.9 * (1 - m)))[..., None]          # fibres through the paint
    P = P * (light ** 0.8)[..., None]                            # the sheet's own light
    out = R * (1 - m[..., None]) + P * m[..., None]
    out *= (1 - 0.06 * (4 * m * (1 - m)))[..., None]             # pigment pooled at the edge
    col[top:top + S, lx:lx + S] = out
    painted = np.zeros((H, W), np.float32)
    painted[top:top + S, lx:lx + S] = m
    return col, painted


# -------------------------------------------------------------------------- main
def main() -> None:
    logo = Image.open(LOGO).convert("RGB")
    scan = Image.open(PAPYRUS).convert("RGB")
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)

    # --- the papyrus: strip B underneath, strip A's bitten edge lying over it
    sheet_top = 80  # high enough to leave a band of sand below for the credit
    a_col, a_m = join(*cut_out(scan, STRIP_A), A_SHEETS)
    b_col, b_m = join(*cut_out(scan, STRIP_B), B_SHEETS)
    ya = sheet_top - 25 * SCALE  # STRIP_A starts a little above the papyrus's top edge
    yb = ya + (STRIP_B[1] - STRIP_A[1] - B_TUCK) * SCALE
    # centred: the same papyrus margin of sand either side
    x0 = (W - a_col.shape[1] * SCALE) / 2
    A, Aa = place(a_col, a_m, x0, ya)
    B, Ba = place(b_col, b_m, x0, yb)
    alpha = np.maximum(Aa, Ba)
    # museum flat light -> warm low desert sun: a touch warmer and darker
    pap = (A * Aa[..., None] + B * Ba[..., None] * (1 - Aa[..., None])) / np.maximum(alpha, 1e-4)[..., None]
    pap = pap * np.array([1.04, 0.99, 0.92]) * 0.97
    # where A lies on B, A casts a thin shadow onto B just past its edge
    a_shadow = np.roll(np.roll(blurred(Aa, 5), 6, 0), 5, 1)
    pap *= (1 - 0.35 * np.clip(a_shadow - Aa, 0, 1) * Ba)[..., None]
    # the sheet join: the main length overlaps the end sheet, a band of double thickness
    # a little darker, its raised edge catching the sun
    seam = x0 + (A_SHEETS[0][1] - A_SHEETS[0][0]) * SCALE
    dx = xx - seam
    band = (dx >= 0) & (dx < 34)
    pap *= (1 - 0.07 * band - 0.12 * np.exp(-((dx - 34) / 2.5) ** 2))[..., None]
    pap += (1 - pap) * (0.22 * np.exp(-(dx / 2.0) ** 2))[..., None]

    # --- curl: papyrus never lies flat; long waves along the fibres, lifted edges
    wave = rng_noise(H, W, 420, 41) * 0.6 + rng_noise(H, W, 160, 42) * 0.4
    edge_dist = blurred(alpha, 40)  # ~1 deep inside, falls to 0.5 at the edges
    lift = np.clip(1 - edge_dist, 0, 1) ** 1.5
    hgt = (wave * 14 + lift * 26 + Aa * 3) * alpha  # canvas px
    pap *= (0.78 + 0.22 * shade_from_height(blurred(hgt / 40, 6) * 40, 0.9))[..., None]

    # --- onto the sand: a soft shadow, offset and blurred more where the sheet lifts
    ground = sand()
    sh_near = np.roll(np.roll(blurred(alpha, 4), 7, 0), 6, 1)
    sh_far = np.roll(np.roll(blurred(alpha, 24), 34, 0), 28, 1)
    shadow = np.clip(0.6 * sh_near + 0.55 * sh_far * (0.6 + lift), 0, 1)
    ground *= (1 - 0.62 * shadow * (1 - alpha))[..., None]
    # the sheet has a thickness: its edges facing the sun catch it, the far ones fall dark
    lit_lip = np.clip(alpha - np.roll(np.roll(alpha, 3, 0), 3, 1), 0, 1)
    dark_lip = np.clip(alpha - np.roll(np.roll(alpha, -3, 0), -3, 1), 0, 1)
    pap = pap * (1 - 0.3 * dark_lip)[..., None] + (1 - pap) * 0.18 * lit_lip[..., None]
    col = ground * (1 - alpha[..., None]) + pap * alpha[..., None]

    # --- the painting, painted onto the sheet
    lx, top = (W - logo.width) // 2, sheet_top + 70
    col, painted = paint_on(col, logo, lx, top)

    # --- wind-blown sand: banked against the windward (top) edge and lying in its hollows,
    # a fine dusting across the sheet, thicker toward the top
    sand_col = ground / np.maximum(1 - 0.5 * shadow * (1 - alpha), 0.3)[..., None]
    near_edge = np.clip((1 - blurred(alpha, 14)) * 2.2, 0, 1) * alpha
    windward = np.clip((1 - yy / (H * 0.55)), 0, 1)  # the top edge faces into the wind
    drift = near_edge * windward * np.clip((rng_noise(H, W, 70, 51) - 0.35) * 2.5, 0, 1)
    grains = rng_noise(H, W, 3, 52)
    dust = np.clip((grains - (0.86 - 0.08 * windward)) * 12, 0, 1) * alpha * 0.55
    over = np.clip(drift * 0.9 + dust * (1 - 0.85 * painted), 0, 1)[..., None]
    col = col * (1 - over) + sand_col * over

    # --- the title, in ink on the papyrus, glyphs in red ochre either side
    font = ImageFont.truetype(FONT, FONT_SIZE, index=FONT_INDEX)
    tx0, ty0, tx1, ty1 = font.getbbox(TITLE)
    text_w, text_h = tx1 - tx0, ty1 - ty0
    tx, ty = (W - text_w) // 2, top + logo.height + 58
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).text((tx - tx0, ty - ty0), TITLE, font=font, fill=255)
    mask = mask.filter(ImageFilter.MaxFilter(3))
    col = ink(col, mask, (0.16, 0.12, 0.10), 0.95, 21)
    gmask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(gmask)
    gy = ty + text_h / 2 - 6
    for g, off in zip([g_eye, g_ankh], [150, 310]):
        g(d, tx - off, gy, 58, 9)
    for g, off in zip([g_ankh, g_scarab], [150, 310]):
        g(d, tx + text_w + off, gy, 58, 9)
    # red ochre, aged: darker and browner than fresh, painted into the fibres
    col = pigment(col, gmask, (0.56, 0.24, 0.15), 0.88, 31)

    # --- the credit, pressed into the sand below the papyrus, clear of its arches
    # (Papyrus has no bold: strokes thickened)
    col = carve(col, credit_mask(alpha))

    col = vignette(col)
    out = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")

    out.save(OUT, optimize=True)
    print(f"wrote {OUT} ({W}x{H})")


if __name__ == "__main__":
    main()
