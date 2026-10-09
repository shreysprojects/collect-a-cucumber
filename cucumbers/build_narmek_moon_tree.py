"""Narmek: Moon Tree - a cratered grey moon-rock stalk topped by two glowing purple saucers."""
import bmesh, math, random

COLLECTION = "NarmekMoonTree"
NOTES = ("An 11.5-stud moon tree, footprint about 6.0 x 4.7.  A two-step moon-rock plinth "
         "and a four-block tapering stalk (1.45 -> 0.95 across) climb to z 10.86, pitted "
         "with eight dark sunken craters.  One short fork leaves the stalk at z 6.4 and "
         "reaches out to the RIGHT of the frame (negative x) to (-2.25, 0.18, 8.40).  A big "
         "domed saucer (r 2.3) caps the stalk at z 10.95 and a small one (r 1.35) caps the "
         "fork at z 8.62; both are purple-grey (nar_ufo_dk) with lighter panel speckles.  "
         "Each hangs a fat purple neon disc (r 1.88 / 1.08, 0.16 thick, 0.8x the saucer) "
         "just clear of its belly so the glow reads in silhouette, and wears a row of "
         "glowing portholes round its rim.  Faces +Y.  Five parts: Trunk, Craters, "
         "Saucers, SaucerStuds, Glow.")

# ---- the stalk --------------------------------------------------------------
BASE_TOP_W, BASE_H, BASE_STEPS, BASE_GROW = 1.7, 1.6, 2, 1.35
TRUNK_Z0, TRUNK_Z1 = BASE_H, 10.85
TRUNK_W0, TRUNK_W1, TRUNK_BLOCKS = 1.45, 0.95, 4

FORK_A = (0.0, 0.0, 6.40)
FORK_B = (-2.25, 0.18, 8.40)

GLOW_T = 0.16                                  # glow-disc thickness, both saucers

# (centre, radius, thick, rim, dome, glow radius, glow z, portholes)
SAUCERS = [
    ((0.0, 0.0, 10.95), 2.30, 0.42, 0.26, 0.35, 1.88, 10.67, 10),
    ((FORK_B[0], FORK_B[1], 8.62), 1.35, 0.34, 0.20, 0.28, 1.08, 8.38, 6),
]

# craters: (z, face, offset along the face, size)
CRATERS = [
    (0.35, "+y", -0.42, 0.50),
    (1.15, "+x", 0.18, 0.36),
    (2.55, "+y", 0.22, 0.44),
    (3.60, "-x", -0.14, 0.38),
    (4.85, "+y", -0.20, 0.34),
    (6.10, "+x", 0.10, 0.46),
    (7.45, "+y", 0.18, 0.40),
    (9.30, "-x", -0.08, 0.36),
]


def _half_at(z):
    """Half-width of the stalk (plinth step or trunk block) at height z."""
    if z < BASE_H:
        sh = BASE_H / float(BASE_STEPS)
        i = min(BASE_STEPS - 1, max(0, int(z / sh)))
        k = BASE_STEPS - 1 - i
        return BASE_TOP_W * (BASE_GROW ** k) / 2.0
    t = (z - TRUNK_Z0) / (TRUNK_Z1 - TRUNK_Z0)
    i = min(TRUNK_BLOCKS - 1, max(0, int(t * TRUNK_BLOCKS)))
    tt = (i + 0.5) / float(TRUNK_BLOCKS)
    return (TRUNK_W0 + (TRUNK_W1 - TRUNK_W0) * tt) / 2.0


def _face_point(z, face, offset):
    """A point on the stalk's flat face and the normal out of it."""
    hw = _half_at(z)
    if face == "+y":
        return (offset, hw, z), (0.0, 1.0, 0.0)
    if face == "-y":
        return (offset, -hw, z), (0.0, -1.0, 0.0)
    if face == "+x":
        return (hw, offset, z), (1.0, 0.0, 0.0)
    return (-hw, offset, z), (-1.0, 0.0, 0.0)


def _dome_ring(centre, radius, thick, dome, n, frac=0.56, phase=0.0):
    """Points + normals on the sloping top dome of a disc_canopy, for speckles."""
    cx, cy, cz = centre
    r = radius * frac
    t = (0.72 - frac) / 0.32                       # 0 at the shoulder, 1 at the dome ring
    z = cz + thick * 0.5 + t * 0.7 * dome
    nr, nz = 0.7 * dome, 0.32 * radius             # outward normal of that slope
    L = math.hypot(nr, nz) or 1.0
    out = []
    for i in range(n):
        a = phase + 2.0 * math.pi * i / float(n)
        ca, sa = math.cos(a), math.sin(a)
        out.append(((cx + r * ca, cy + r * sa, z),
                    (nr / L * ca, nr / L * sa, nz / L)))
    return out


def _rim_ring(centre, radius, n, phase=0.0):
    """Points + normals round the outer rim band of a disc_canopy."""
    cx, cy, cz = centre
    out = []
    for i in range(n):
        a = phase + 2.0 * math.pi * i / float(n)
        ca, sa = math.cos(a), math.sin(a)
        out.append(((cx + radius * ca, cy + radius * sa, cz), (ca, sa, 0.0)))
    return out


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    rng = random.Random(9021)

    # ---- stalk: plinth, tapering blocks, one fork out to the right ----------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=BASE_TOP_W, h=BASE_H, steps=BASE_STEPS, grow=BASE_GROW,
                   bevel=0.08)
    D.blocky_trunk(bm, TRUNK_Z0, TRUNK_Z1, TRUNK_W0, TRUNK_W1, blocks=TRUNK_BLOCKS,
                   bevel=0.08)
    D.branch_box(bm, FORK_A, FORK_B, 0.62, 0.44, bevel=0.05)
    D.new_obj("Trunk", bm, c, D.C("nar_moon"), rbx_material="Rock")

    # ---- craters sunk into the stone ---------------------------------------
    bm = bmesh.new()
    for (z, face, off, size) in CRATERS:
        p, n = _face_point(z, face, off)
        D.stud_patch(bm, p, n, size=size, rise=0.012, sink=0.13, bevel=0.035,
                     aspect=rng.uniform(0.82, 1.18), spin=rng.uniform(-14.0, 14.0))
    D.new_obj("Craters", bm, c, D.C("nar_moon_dk"), rbx_material="Rock")

    # ---- the two saucers ----------------------------------------------------
    bm = bmesh.new()
    for (ctr, rad, thick, rim, dome, _gr, _gz, _n) in SAUCERS:
        D.disc_canopy(bm, center=ctr, radius=rad, thick=thick, rim=rim, segs=12, dome=dome)
    D.new_obj("Saucers", bm, c, D.C("nar_ufo_dk"), rbx_material="Metal")

    # ---- panel speckles over the saucer domes -------------------------------
    bm = bmesh.new()
    for i, (ctr, rad, thick, rim, dome, _gr, _gz, _n) in enumerate(SAUCERS):
        for (p, nrm) in _dome_ring(ctr, rad, thick, dome, 6 - 2 * i, frac=0.58,
                                   phase=0.26 + 0.7 * i):
            D.stud_patch(bm, p, nrm, size=0.30 - 0.06 * i, rise=0.055, bevel=0.035,
                         spin=rng.uniform(-10.0, 10.0))
        for (p, nrm) in _dome_ring(ctr, rad, thick, dome, 3 - i, frac=0.44,
                                   phase=1.1 - 0.4 * i):
            D.stud_patch(bm, p, nrm, size=0.24 - 0.04 * i, rise=0.05, bevel=0.03)
    D.new_obj("SaucerStuds", bm, c, D.C("nar_ufo"), rbx_material="Metal")

    # ---- purple glow: a ring under each belly + a row of portholes ----------
    bm = bmesh.new()
    for (ctr, rad, thick, rim, dome, gr, gz, nport) in SAUCERS:
        D.disc_canopy(bm, center=(ctr[0], ctr[1], gz), radius=gr, thick=GLOW_T,
                      rim=GLOW_T, segs=12)
        psize = 0.22 if rim > 0.22 else 0.17
        for (p, nrm) in _rim_ring(ctr, rad, nport, phase=math.pi / float(nport)):
            D.stud_patch(bm, p, nrm, size=psize, rise=0.05, bevel=0.03, aspect=0.78)
    D.new_obj("Glow", bm, c, D.C("nar_glow_pur"), rbx_material="Neon", emit=0.65)

    return c
