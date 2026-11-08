#!/usr/bin/env python3
"""Wind-blown sand lying on the wooden pieces and the clay tablet, as decal textures
(RGBA, straight alpha) in ../assets: dust_<name>.png.

Needs numpy + pillow:   python3 tools/make_dust.py

Nothing left out on desert sand stays clean. Sand is blown onto everything lying on it
and collects where the wind drops it: in uneven clumps along the edges, deepest on the
edges facing the wind, as single grains thinning out toward the middle, and in faint
streaks running with the wind. In the dice tray it also settles inside the walls,
mostly just inside the windward one, where sand blown over the rim falls.

Each texture covers its object's top from above (u along the object's x, v along its
z), at PPU pixels per world unit; the game lays it on as a decal (main.gd, add_dust).
"""
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
PPU = 160
WIND = np.array([0.94, 0.34])        # the way the wind blows (x, z): main.gd SAND_WIND
SAND = os.path.join(OUT, "sand_albedo.png")


def fnoise(h, w, sx, sy, rng):
    """Smooth noise, unit std, correlation length sx (along x) / sy (along y) pixels."""
    r = rng.standard_normal((h, w))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    g = np.exp(-2 * np.pi ** 2 * ((sx * fx) ** 2 + (sy * fy) ** 2))
    n = np.fft.irfft2(np.fft.rfft2(r) * g, s=(h, w))
    return (n - n.mean()) / (n.std() + 1e-9)


def edge_bands(h, w, box, blot, well):
    """Sand along the inside of each edge of box = (x0, z0, x1, z1) (pixels), each edge
    on its own (so corners blend): how much collects there (0..1)."""
    z, x = np.mgrid[0:h, 0:w].astype(float)
    x0, z0, x1, z1 = box
    inside = (x >= x0) & (x <= x1) & (z >= z0) & (z <= z1)
    out = np.zeros((h, w))
    for d, n in [(x - x0, (-1, 0)), (x1 - x, (1, 0)), (z - z0, (0, -1)), (z1 - z, (0, 1))]:
        face = float(np.clip(-(np.array(n) @ WIND), 0, 1))
        if well:
            face = float(np.clip(np.array(n) @ WIND, 0, 1))   # piles at the foot of the wall it blew over
        width = (0.03 + 0.1 * face) * PPU * np.clip(1.0 + 0.6 * blot, 0.2, 2.4)
        out = np.maximum(out, np.exp(-np.maximum(d, 0) / width) * (0.35 + 0.65 * face))
    return np.where(inside, out, 0.0)


def dust(w_world, h_world, seed, edges, wells=()):
    """edges: rectangles (world, from the texture's corner) whose edges collect sand on
    the inside; wells: rectangles sunk below (the tray's floor) that collect it at the
    foot of their walls, mostly the windward one."""
    rng = np.random.default_rng(seed)
    W, H = int(round(w_world * PPU)), int(round(h_world * PPU))
    blot = fnoise(H, W, 0.07 * PPU, 0.07 * PPU, rng)          # clumps along an edge
    fine = fnoise(H, W, 0.02 * PPU, 0.02 * PPU, rng)
    amt = np.zeros((H, W))
    for box in edges:
        amt = np.maximum(amt, edge_bands(H, W, [c * PPU for c in box], blot, False))
    for box in wells:
        amt = np.maximum(amt, edge_bands(H, W, [c * PPU for c in box], blot, True))
    amt *= np.clip(0.8 + 0.35 * blot, 0, 1.3)
    # faint streaks running with the wind (sheared along it)
    z, x = np.mgrid[0:H, 0:W].astype(float)
    ang = np.arctan2(WIND[1], WIND[0])
    st = fnoise(H, W, 0.8 * PPU, 0.04 * PPU, rng)
    shift = (x * np.tan(ang)).astype(int) % H
    st = st[(z.astype(int) + shift) % H, x.astype(int)]
    amt = np.maximum(amt, np.clip(st - 1.1, 0, None) * 0.18)
    # the sand is grains: where there is a lot they nearly cover the wood, where there is
    # a little they are scattered; under them only a thin film of fine dust
    u = rng.random((H, W))
    grains = (u < 0.004 + 0.75 * amt ** 1.3).astype(float) * rng.uniform(0.6, 1.0, (H, W))
    grains = np.maximum(grains, np.roll(grains, 1, 1) * (rng.random((H, W)) < 0.3))
    film = 0.3 * np.clip(amt, 0, 1) ** 1.5
    a = np.clip(np.maximum(grains * np.clip(0.55 + 0.6 * amt, 0, 1), film), 0, 1)
    # colour: the sand's own, grain by grain a little lighter or darker
    s = np.asarray(Image.open(SAND).convert("RGB"), float) / 255.0
    base = s.reshape(-1, 3).mean(0)
    tone = 1.0 + 0.08 * fine + np.where(grains > 0, rng.uniform(-0.2, 0.15, (H, W)), 0.0)
    rgb = np.clip(base[None, None, :] * tone[..., None] * 1.08, 0, 1)
    return np.dstack([rgb, a])


def save(name, rgba):
    Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name))


if __name__ == "__main__":
    # main.gd: board 8.5 x 3.5, strips 7.4 x 0.9, home plates HOME_SIZE 1.7 x 2.8,
    # tray TRAY 3.6 x 4.8 inside rim boards 0.3 thick, tablet TABLET_SIZE 2.8 x 1.2
    save("dust_board.png", dust(8.5, 3.5, 11, [(0, 0, 8.5, 3.5)]))
    save("dust_strip.png", dust(7.4, 0.9, 12, [(0, 0, 7.4, 0.9)]))
    save("dust_plate.png", dust(1.7, 2.8, 13, [(0, 0, 1.7, 2.8)]))
    save("dust_tray.png", dust(4.2, 5.4, 14, [(0, 0, 4.2, 5.4)], wells=[(0.3, 0.3, 3.9, 5.1)]))
    save("dust_tablet.png", dust(2.8, 1.2, 15, [(0, 0, 2.8, 1.2)]))
    print("wrote dust textures")
