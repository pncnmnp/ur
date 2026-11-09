"""Boot splash: the full painting (icons/icon_1024.png, pixel-for-pixel, no resampling)
lying on the game's desert sand, with the title and a row of the board's glyphs carved
into the sand beneath it in Papyrus.

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
from make_textures import g_ankh, g_djed, g_eye, g_lotus, g_scarab, g_sun  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "icons" / "icon_1024.png"
OUT = ROOT / "icons" / "splash.png"
SAND_ALB = ROOT / "assets" / "sand_albedo.png"
SAND_NRM = ROOT / "assets" / "sand_normal.png"
FONT = "/System/Library/Fonts/Supplemental/Papyrus.ttc"
FONT_INDEX = 1  # the wide cut of Papyrus

W, H = 3200, 1800
TITLE = "The Royal Game of Ur"
FONT_SIZE = 184
GAP = 175
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


def carve(base: np.ndarray, mask: Image.Image) -> np.ndarray:
    """Cut `mask` (L, 255 = cut) into the sand: a shaded floor, a dark wall on the side
    facing away from the sun, a lit wall on the side facing it."""
    m = np.asarray(mask.filter(ImageFilter.GaussianBlur(1.2)), np.float32)[..., None] / 255.0
    def shifted(dx, dy, blur):
        s = mask.transform(mask.size, Image.AFFINE, (1, 0, -dx, 0, 1, -dy))
        return np.asarray(s.filter(ImageFilter.GaussianBlur(blur)), np.float32)[..., None] / 255.0
    # inside the cut, the upper-left wall casts a shadow across the floor
    inner_shadow = np.clip(m - shifted(7, 8, 3), 0, 1)
    # just outside, below-right, the lip of the cut catches the sun
    lip = np.clip(shifted(4, 5, 2.5) - m, 0, 1)
    # the floor of the cut is shaded, darker brown sand
    floor = base * np.array([0.52, 0.40, 0.30])
    out = base * (1 - m) + floor * m
    out = out * (1 - 0.55 * inner_shadow)
    out = out + (1 - out) * 0.45 * lip
    return out


def main() -> None:
    logo = Image.open(LOGO).convert("RGB")
    font = ImageFont.truetype(FONT, FONT_SIZE, index=FONT_INDEX)
    tx0, ty0, tx1, ty1 = font.getbbox(TITLE)
    text_w, text_h = tx1 - tx0, ty1 - ty0

    block_h = logo.height + GAP + text_h
    top = (H - block_h) // 2 - 40
    lx = (W - logo.width) // 2
    ty = top + logo.height + GAP

    col = sand()

    # carved: title, glyphs either side, an incised rule above and below
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    tx = (W - text_w) // 2
    d.text((tx - tx0, ty - ty0), TITLE, font=font, fill=255)
    mask = mask.filter(ImageFilter.MaxFilter(5))  # Papyrus is thin: cut the strokes wider
    d = ImageDraw.Draw(mask)
    gy = ty + text_h / 2 - 6
    s, w = 62, 9
    left = [g_ankh, g_eye, g_lotus]
    right = [g_lotus, g_scarab, g_djed]
    for i, g in enumerate(left):
        g(d, tx - 120 - i * 165, gy, s, w)
    for i, g in enumerate(right):
        g(d, tx + text_w + 120 + i * 165, gy, s, w)
    rule_x0, rule_x1 = tx - 120 - 2 * 165 - 40, tx + text_w + 120 + 2 * 165 + 40
    for yr in (ty - 70, ty + text_h + 62):
        d.line([(rule_x0, yr), (rule_x1, yr)], fill=255, width=6)
    for xr in (rule_x0, rule_x1):  # small sun discs closing the rules
        g_sun(d, xr, ty - 70, 34, 5)
        g_sun(d, xr, ty + text_h + 62, 34, 5)
    col = carve(col, mask)

    canvas = Image.fromarray((col * 255).astype(np.uint8), "RGB")

    # the painting lies on the sand: a soft shadow down-right of it, away from the sun
    shade = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shade).rectangle(
        [lx + 18, top + 26, lx + logo.width + 30, top + logo.height + 40], fill=190
    )
    shade = shade.filter(ImageFilter.GaussianBlur(26))
    canvas.paste(Image.new("RGB", (W, H), (40, 22, 8)), (0, 0), shade)

    # dark wooden frame with a gilt inner line, then the painting pasted 1:1
    d = ImageDraw.Draw(canvas)
    d.rectangle([lx - 26, top - 26, lx + logo.width + 25, top + logo.height + 25], fill=(58, 34, 16))
    d.rectangle([lx - 26, top - 26, lx + logo.width + 25, top + logo.height + 25], outline=(30, 16, 6), width=3)
    d.rectangle([lx - 9, top - 9, lx + logo.width + 8, top + logo.height + 8], outline=(176, 136, 70), width=4)
    canvas.paste(logo, (lx, top))

    canvas.save(OUT, optimize=True)
    print(f"wrote {OUT} ({W}x{H})")


if __name__ == "__main__":
    main()
