#!/usr/bin/env python3
"""Generates the players' hand: one continuous, skinned mesh of a man's right hand
and forearm, built from an anatomical signed-distance description and polygonised
with surface nets.

Needs numpy:   python3 tools/make_hand.py
Writes assets/hand_mesh.json (bones, layout) + assets/hand_mesh.bin (vertex data).

Model space is centimetres: wrist at the origin, fingers along +z, back of the hand
up (+y), thumb on +x (a right hand, palm down). Per vertex it stores, besides the
position/normal and 4 bone weights:
  CUSTOM0 = rest position (cm) + region (0 forearm, 1 palm, 2 finger, 3 thumb)
  COLOR   = nail mask, joint-wrinkle mask, dorsal (back of hand) factor, nail tip (dirt)
  UV      = distance along the finger to the nearest joint (cm), angle round the finger
so the skin shader can place wrinkles, nails, hair, veins and the tattoo.
"""
import json
import math
import os

import numpy as np

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
VOX = 0.2  # cm


def norm(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def ydir(yaw, pitch):
    y, p = math.radians(yaw), math.radians(pitch)
    return norm([math.sin(y) * math.cos(p), math.sin(p), math.cos(y) * math.cos(p)])


def frame(axis, roll=0.0):
    """Bone frame: z along the bone, y 'up' (back of the finger), x = y cross z."""
    a = norm(axis)
    u0 = np.array([0.0, 1.0, 0.0]) - a * a[1]
    u0 = norm(u0)
    s0 = np.cross(a, u0)
    r = math.radians(roll)
    u = math.cos(r) * u0 + math.sin(r) * s0
    x = np.cross(u, a)
    return x, u, a


# ------------------------------------------------------------------ anatomy
# bones: name, parent, head, axis, length, (r0, r1), flatten, roll
BONES = []


def bone(name, parent, head, axis, length, r0, r1, flat=0.86, roll=0.0):
    BONES.append(dict(name=name, parent=parent, head=np.asarray(head, float), axis=norm(axis),
                      length=length, r0=r0, r1=r1, flat=flat, roll=roll))
    return len(BONES) - 1


HAND = bone("hand", -1, (0, 0, 0), (0, 0, 1), 9.6, 3.6, 3.6)
FOREARM = bone("forearm", HAND, (0, 0, 0), (0, 0, -1), 16.0, 2.75, 3.35, flat=0.7)

FINGERS = {  # knuckle, yaw, pitch, lengths, base radius
    "index": ((2.85, 0.15, 9.9), 6, -3, (3.9, 2.3, 1.5), 1.0),
    "middle": ((0.9, 0.25, 10.25), 1, -3, (4.3, 2.6, 1.6), 1.03),
    "ring": ((-1.1, 0.15, 9.85), -4, -3, (4.0, 2.5, 1.55), 0.95),
    "pinky": ((-3.0, -0.05, 8.9), -11, -3, (3.1, 1.9, 1.4), 0.82),
}
FINGER_BONES = {}
for fname, (k, yaw, pitch, lens, r0) in FINGERS.items():
    d = ydir(yaw, pitch)
    head = np.asarray(k, float)
    ids = []
    radii = [(r0, r0 * 0.88), (r0 * 0.88, r0 * 0.8), (r0 * 0.8, r0 * 0.74)]
    parent = HAND
    for seg in range(3):
        b = bone("%s_%d" % (fname, seg), parent, head, d, lens[seg], *radii[seg])
        ids.append(b)
        head = head + d * lens[seg]
        parent = b
    FINGER_BONES[fname] = ids

head = np.array([2.6, -0.25, 1.4])
THUMB = []
for seg, (yaw, pitch, L, r0, r1, fl) in enumerate([(36, -5, 4.4, 1.5, 1.25, 0.9), (24, -3, 3.2, 1.12, 1.02, 0.82),
                                                   (17, -2, 2.0, 1.0, 0.85, 0.78)]):
    d = ydir(yaw, pitch)
    b = bone("thumb_%d" % seg, THUMB[-1] if THUMB else HAND, head, d, L, r0, r1, flat=fl, roll=-55)
    THUMB.append(b)
    head = head + d * L
DISTALS = [ids[2] for ids in FINGER_BONES.values()] + [THUMB[2]]


# ------------------------------------------------------------------ SDF parts
def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


def sd_bone(P, b, pad=0.0):
    """Tapered, slightly flattened capsule along a bone."""
    B = BONES[b]
    x, u, a = frame(B["axis"], B["roll"])
    q = P - B["head"]
    t = q @ a
    tc = np.clip(t, 0, B["length"])
    r = B["r0"] + (B["r1"] - B["r0"]) * tc / B["length"] + pad
    ry = q @ u
    rx = q @ x
    ax = t - tc                      # beyond either end: rounded caps
    e = np.sqrt(rx ** 2 + (ry / B["flat"]) ** 2 + ax ** 2)
    return (e - r) * (0.5 + 0.5 * B["flat"])


def sd_ellipsoid(P, c, r):
    q = (P - np.asarray(c)) / np.asarray(r)
    return (np.linalg.norm(q, axis=-1) - 1.0) * min(r)


def sd_sphere(P, c, r):
    return np.linalg.norm(P - np.asarray(c), axis=-1) - r


def sd_palm(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    w = 3.3 + 0.95 * np.clip(z / 9.0, 0, 1)
    h = 1.3 + 0.25 * np.clip(1 - (x / w) ** 2, 0, 1)        # back of the hand is domed
    r = 1.1
    qx = np.abs(x) - w + r
    qy = np.abs(y + 0.05) - h + r
    qz = np.abs(z - 4.8) - 4.85 + r
    q = np.stack([qx, qy, qz], -1)
    return np.linalg.norm(np.maximum(q, 0), axis=-1) + np.minimum(q.max(-1), 0) - r


def sd_nail(P, b):
    B = BONES[b]
    x, u, a = frame(B["axis"], B["roll"])
    L, r1 = B["length"], B["r1"]
    t0, t1 = 0.3 * L, L + 0.45 * r1
    rm = (B["r0"] + r1) / 2
    c = B["head"] + a * (t0 + t1) / 2 + u * rm * B["flat"] * 0.83
    q = P - c
    lx, ly, lz = np.abs(q @ x), np.abs(q @ u), np.abs(q @ a)
    hx, hy, hz, rr = rm * 0.66, 0.1, (t1 - t0) / 2, 0.09
    qq = np.stack([lx - hx + rr, ly - hy + rr, lz - hz + rr], -1)
    return np.linalg.norm(np.maximum(qq, 0), axis=-1) + np.minimum(qq.max(-1), 0) - rr


# each part: (bone it moves with, sdf fn, blend k, kind, group). Parts blend smoothly
# within their group; each finger group then blends into the palm group only, so the
# fingers stay separate from one another instead of webbing together.
PARTS = [(HAND, sd_palm, 0.9, "palm", "palm"),
         (FOREARM, lambda P: sd_bone(P, FOREARM), 1.2, "forearm", "palm"),
         (FOREARM, lambda P: sd_sphere(P, (-2.2, 0.75, -0.7), 0.45), 0.6, "forearm", "palm"),   # wrist bone
         (HAND, lambda P: sd_ellipsoid(P, (2.9, -0.55, 3.0), (1.9, 1.25, 2.9)), 0.9, "palm", "palm"),   # thumb pad
         (HAND, lambda P: sd_ellipsoid(P, (-3.0, -0.45, 4.6), (1.25, 1.05, 3.0)), 0.8, "palm", "palm")]
for fname, ids in FINGER_BONES.items():
    k = np.asarray(FINGERS[fname][0], float)
    r0 = FINGERS[fname][4]
    PARTS.append((HAND, (lambda kk, rr: lambda P: sd_sphere(P, kk + np.array([0, 0.35, -0.45]), rr))(k, r0), 0.6, "palm", "palm"))
    for i, b in enumerate(ids):
        PARTS.append((b, (lambda bb: lambda P: sd_bone(P, bb))(b), 0.45, "finger", fname))
        if i > 0:  # slightly knobbly joints
            jh = BONES[b]["head"]
            PARTS.append((b, (lambda c, r: lambda P: sd_sphere(P, c, r))(jh, BONES[b]["r0"] * 0.92), 0.35, "finger", fname))
    PARTS.append((ids[2], (lambda bb: lambda P: sd_nail(P, bb))(ids[2]), 0.12, "nail", fname))
for i, b in enumerate(THUMB):
    PARTS.append((b, (lambda bb: lambda P: sd_bone(P, bb))(b), 0.6, "thumb", "thumb"))
PARTS.append((THUMB[2], lambda P: sd_nail(P, THUMB[2]), 0.12, "nail", "thumb"))
ATTACH_K = {"index": 0.7, "middle": 0.7, "ring": 0.7, "pinky": 0.7, "thumb": 1.0}


def sdf(P, parts=False):
    ds = [fn(P) for (_, fn, _, _, _) in PARTS]
    groups = {}
    for (_, _, k, _, g), di in zip(PARTS, ds):
        groups[g] = di if g not in groups else smin(groups[g], di, k)
    palm = groups.pop("palm")
    d = palm
    for g, gd in groups.items():
        d = np.minimum(d, smin(palm, gd, ATTACH_K[g]))
    return (d, ds) if parts else d


# ------------------------------------------------------------------ surface nets
def surface_nets(lo, hi):
    xs = np.arange(lo[0], hi[0] + VOX, VOX)
    ys = np.arange(lo[1], hi[1] + VOX, VOX)
    zs = np.arange(lo[2], hi[2] + VOX, VOX)
    G = np.stack(np.meshgrid(xs, ys, zs, indexing="ij"), -1)
    F = sdf(G.reshape(-1, 3)).reshape(G.shape[:3])
    ins = F < 0
    nx, ny, nz = F.shape
    corners = [(i, j, k) for i in (0, 1) for j in (0, 1) for k in (0, 1)]
    cin = np.stack([ins[i:nx - 1 + i, j:ny - 1 + j, k:nz - 1 + k] for i, j, k in corners], -1)
    active = cin.any(-1) & ~cin.all(-1)
    ci, cj, ck = np.nonzero(active)
    M = len(ci)
    idx = -np.ones(active.shape, np.int64)
    idx[ci, cj, ck] = np.arange(M)
    # vertex = mean of the edge crossings in the cell
    acc = np.zeros((M, 3))
    cnt = np.zeros(M)
    edges = [(a, b) for a in range(8) for b in range(a + 1, 8)
             if sum(abs(np.subtract(corners[a], corners[b]))) == 1]
    for a, b in edges:
        ia, ib = corners[a], corners[b]
        fa = F[ci + ia[0], cj + ia[1], ck + ia[2]]
        fb = F[ci + ib[0], cj + ib[1], ck + ib[2]]
        m = (fa < 0) != (fb < 0)
        t = np.where(m, fa / np.where(m, fa - fb, 1), 0)
        pa = np.stack([xs[ci + ia[0]], ys[cj + ia[1]], zs[ck + ia[2]]], -1)
        pb = np.stack([xs[ci + ib[0]], ys[cj + ib[1]], zs[ck + ib[2]]], -1)
        acc += (pa + (pb - pa) * t[:, None]) * m[:, None]
        cnt += m
    V = acc / cnt[:, None]
    # quads across every sign-changing grid edge
    quads = []
    shape = (nx, ny, nz)
    for ax in range(3):
        a1, a2 = [d for d in range(3) if d != ax]
        # grid edges from point p to p + e_ax, skipping the outer layer on the other axes
        sl0 = [slice(0, shape[d] - 1) if d == ax else slice(1, shape[d] - 1) for d in range(3)]
        sl1 = [slice(1, shape[d]) if d == ax else slice(1, shape[d] - 1) for d in range(3)]
        s0 = ins[tuple(sl0)]
        s1 = ins[tuple(sl1)]
        ch = s0 != s1
        I = np.stack(np.nonzero(ch), -1)
        I[:, a1] += 1
        I[:, a2] += 1
        cells = []
        for d1, d2 in ((0, 0), (1, 0), (1, 1), (0, 1)):
            c = I.copy()
            c[:, a1] -= 1 - d1
            c[:, a2] -= 1 - d2
            cells.append(idx[c[:, 0], c[:, 1], c[:, 2]])
        q = np.stack(cells, -1)
        quads.append(q[(q >= 0).all(-1)])
    Q = np.concatenate(quads)
    return V, Q


def grad(P, e=0.03):
    g = np.zeros_like(P)
    for i in range(3):
        d = np.zeros(3)
        d[i] = e
        g[:, i] = (sdf(P + d) - sdf(P - d)) / (2 * e)
    return g


def main():
    V, Q = surface_nets((-5.8, -3.6, -16.4), (9.8, 3.2, 21.6))
    # forearm is cut off well inside the sleeve: drop that end's cap
    for _ in range(3):  # project onto the true surface (small, clamped steps)
        g = grad(V)
        step = (sdf(V) / np.maximum((g ** 2).sum(1), 0.25))[:, None] * g
        ln = np.linalg.norm(step, axis=1, keepdims=True)
        V = V - step * np.minimum(1.0, 0.6 * VOX / np.maximum(ln, 1e-9))
    N = grad(V)
    N /= np.linalg.norm(N, axis=1, keepdims=True)
    T = np.concatenate([Q[:, [0, 1, 2]], Q[:, [0, 2, 3]]])
    # Godot front faces: cross(b - a, c - a) points into the surface
    a, b, c = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
    cr = np.cross(b - a, c - a)
    nmean = N[T[:, 0]] + N[T[:, 1]] + N[T[:, 2]]
    flip = (cr * nmean).sum(1) > 0
    T[flip] = T[flip][:, [0, 2, 1]]
    # drop the far end of the forearm (hidden in the sleeve)
    keep_v = V[:, 2] > -15.5
    keep_t = keep_v[T].all(1)
    T = T[keep_t]
    used = np.unique(T)
    remap = -np.ones(len(V), np.int64)
    remap[used] = np.arange(len(used))
    V, N, T = V[used], N[used], remap[T]

    # bone weights: soft-min over the parts each vertex is closest to
    _, ds = sdf(V, parts=True)
    D = np.stack(ds, -1)
    bone_of = np.array([p[0] for p in PARTS])
    groups_of = [p[4] for p in PARTS]
    kinds = [p[3] for p in PARTS]
    W = np.exp(-(D - D.min(1, keepdims=True)) / 0.35)
    BW = np.zeros((len(V), len(BONES)))
    for j, bidx in enumerate(bone_of):
        BW[:, bidx] += W[:, j]
    top = np.argsort(-BW, 1)[:, :4]
    tw = np.take_along_axis(BW, top, 1)
    tw /= tw.sum(1, keepdims=True)

    # shader masks
    # on the nail where the nail plate is the outermost surface of that fingertip
    nail = np.zeros(len(V))
    for j, k in enumerate(kinds):
        if k != "nail":
            continue
        jf = [i for i, p in enumerate(PARTS) if p[3] in ("finger", "thumb") and p[0] == PARTS[j][0] and i != j][0]
        nail = np.maximum(nail, np.clip((D[:, jf] - D[:, j]) / 0.12 + 0.5, 0, 1) * (D[:, j] < 0.25))
    region = np.zeros(len(V))
    part_kind = np.array(kinds)[np.argmin(D, 1)]
    region[part_kind == "palm"] = 1
    region[(part_kind == "finger") | (part_kind == "nail")] = 2
    region[part_kind == "thumb"] = 3
    main_bone = top[:, 0]
    dorsal = np.zeros(len(V))
    along = np.zeros(len(V))
    ang = np.zeros(len(V))
    tip = np.zeros(len(V))
    wrinkle = np.zeros(len(V))
    for bi, B in enumerate(BONES):
        m = main_bone == bi
        if not m.any():
            continue
        x, u, a = frame(B["axis"], B["roll"])
        q = V[m] - B["head"]
        t = q @ a
        dorsal[m] = np.clip(0.5 + 0.7 * (N[m] @ u), 0, 1)
        ang[m] = np.arctan2(q @ x, q @ u)
        if bi in (HAND, FOREARM):
            along[m] = 0
            continue
        # distance to the nearer joint of this bone
        dj = np.where(t < B["length"] / 2, t, t - B["length"])
        along[m] = dj
        wrinkle[m] = np.exp(-(dj / 0.55) ** 2)
        if bi in DISTALS:
            tip[m] = np.clip((t - B["length"]) / (0.3 * B["r1"]) - 0.1, 0, 1) * nail[m]
            wrinkle[m] *= (t < B["length"] / 2)
    dorsal[(region == 0) | (region == 1)] = np.clip(0.5 + 0.7 * N[(region == 0) | (region == 1), 1], 0, 1)
    uv = np.stack([along, ang], 1)
    uv[(region <= 1)] = V[(region <= 1)][:, [0, 2]]
    custom0 = np.concatenate([V, region[:, None]], 1)
    color = np.stack([nail, wrinkle, dorsal, tip], 1)

    arrays = [("pos", V, "f"), ("nrm", N, "f"), ("custom0", custom0, "f"), ("color", color, "f"),
              ("uv", uv, "f"), ("weights", tw, "f"), ("bones", top, "i"), ("index", T.reshape(-1), "i")]
    layout = {}
    blob = bytearray()
    for name, arr, kind in arrays:
        a = np.ascontiguousarray(arr, dtype="<f4" if kind == "f" else "<i4").reshape(-1)
        layout[name] = [len(blob), int(a.size)]
        blob += a.tobytes()
    meta = {"vertex_count": int(len(V)), "layout": layout, "bones": []}
    for B in BONES:
        x, u, a = frame(B["axis"], B["roll"])
        meta["bones"].append(dict(name=B["name"], parent=B["parent"], head=B["head"].tolist(),
                                  x=x.tolist(), y=u.tolist(), z=a.tolist(), length=B["length"],
                                  r0=B["r0"], r1=B["r1"]))
    with open(os.path.join(OUT, "hand_mesh.bin"), "wb") as f:
        f.write(blob)
    with open(os.path.join(OUT, "hand_mesh.json"), "w") as f:
        json.dump(meta, f, indent=1)
    print("hand: %d vertices, %d triangles" % (len(V), len(T)))


if __name__ == "__main__":
    main()
