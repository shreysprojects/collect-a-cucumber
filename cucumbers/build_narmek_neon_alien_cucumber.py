"""Narmek: the Neon Alien Cucumber - a green alien saguaro grown over with neon crystals."""
import bmesh, math, random

COLLECTION = "NarmekNeonAlienCucumber"
NOTES = ("An alien saguaro: the standard 4.0-tall cucumber body with TWO elbowed arms - a "
         "short horizontal stub out of each side that turns up into a slim column.  The "
         "left arm (POSITIVE x, screen-left) reaches z 3.15, the right one only z 2.38, so "
         "the silhouette is lopsided.  Body and arms in bright nar_alien_grn with cuke_stud "
         "speckles.  Where the desert cactus has thorns this one is grown over with 14 "
         "faceted MAGENTA CRYSTALS - ten nar_gem (Neon, emit 1.0) and four darker "
         "nar_gem_dk (Neon, emit 0.75) for depth - each aimed out along the skin normal "
         "with a little random tilt and spin, over the body, up both arm columns and one "
         "standing on the head.  Footprint ~3.3 x 1.7, height ~4.5.  Five parts: Body, "
         "Arms, Studs, Gems, GemsDark.")

AR = 0.30           # arm radius, both segments
GEM_R = 0.20        # crystal radius
GEM_SQ = 1.30       # ... and how far it is drawn out along its axis
GEM_SINK = 0.045    # how far the crystal's waist sits inside the skin

# root x, root z, tilt of the horizontal stub about Y (deg, signed), stub length,
# upright column height.  +tilt swings the stub out to +x and slightly up.
ARMS = [
    (0.38, 1.78, 74.0, 0.82, 1.44),     # LEFT arm  (+x / screen-left) - the tall one
    (-0.38, 1.32, -74.0, 0.78, 1.14),   # RIGHT arm (-x) - the short one
]
ELBOW_DROP = 0.30   # the column starts this far under the elbow, so the joint is solid

# speckles: (height fraction, facet) on each arm's column and on each stub
COL_STUDS = [(0.46, 1)]
STUB_STUDS = [(0.48, 1)]

# crystals on the trunk: (height fraction, facet).  Facet 1 = +Y (the camera),
# 0 = +45, 2 = 135, 3 = -X, 7 = +X.
BODY_GEMS = [(0.16, 1), (0.31, 0), (0.44, 2), (0.60, 7), (0.85, 1)]
BODY_GEMS_DK = [(0.20, 3), (0.71, 0)]

# crystals on the arm columns, one list per arm: outward facets differ per side
COL_GEMS = [[(0.32, 1), (0.70, 7)],     # left  column: front, then +X outward
            [(0.34, 1), (0.68, 3)]]     # right column: front, then -X outward
COL_GEMS_DK = [[(0.52, 0)], [(0.50, 2)]]

HEAD_GEM = (0.0, 0.0, 4.24)             # the one standing on the stem nub
HEAD_DIR = (0.16, 0.10, 1.0)


def _arms(D):
    """Per arm: the two placement matrices, the column's world base, and its sizes."""
    out = []
    for x0, z0, tilt, hlen, colh in ARMS:
        a = math.radians(tilt)
        ex = x0 + math.sin(a) * hlen         # the elbow, where the stub hands over
        ez = z0 + math.cos(a) * hlen
        base = (ex, 0.0, ez - ELBOW_DROP)
        out.append({"hlen": hlen, "colh": colh, "col_loc": base,
                    "stub_m": D.place((x0, 0.0, z0), D.rot_euler(0.0, tilt, 0.0)),
                    "col_m": D.place(base)})
    return out


def _tilt(n, az_deg, el_deg):
    """Swing a surface normal `az_deg` round Z and `el_deg` up out of the surface."""
    a, e = math.radians(az_deg), math.radians(el_deg)
    ca, sa = math.cos(a), math.sin(a)
    x, y = n[0] * ca - n[1] * sa, n[0] * sa + n[1] * ca
    ce, se = math.cos(e), math.sin(e)
    return (x * ce, y * ce, n[2] * ce + se)


def _crystal(D, bm, rng, point, normal):
    """One faceted crystal sitting in the skin, aimed out along `normal` but never
    quite square to it - the wonk is what makes the cluster read as grown, not glued."""
    d = _tilt(normal, rng.uniform(-16.0, 16.0), rng.uniform(-8.0, 24.0))
    c = (point[0] - normal[0] * GEM_SINK,
         point[1] - normal[1] * GEM_SINK,
         point[2] - normal[2] * GEM_SINK)
    D.gem(bm, c, radius=GEM_R * rng.uniform(0.88, 1.12), segs=6, squash=GEM_SQ,
          rot=D.aim(d) @ D.rot_euler(0.0, 0.0, rng.uniform(0.0, 60.0)))


def _gems(D, bm, rng, H, R, arms, body_slots, col_slots, head=False):
    """Crystals on the trunk, then up both arm columns, then optionally on the head."""
    for zf, facet in body_slots:
        p, n = D.cuke_facet_point(h=H, r=R, zf=zf, facet=facet)
        _crystal(D, bm, rng, p, n)
    for i, a in enumerate(arms):
        loc = a["col_loc"]
        for zf, facet in col_slots[i]:
            p, n = D.cuke_facet_point(h=a["colh"], r=AR, zf=zf, facet=facet)
            _crystal(D, bm, rng, (p[0] + loc[0], p[1] + loc[1], p[2] + loc[2]), n)
    if head:
        D.gem(bm, HEAD_GEM, radius=GEM_R * 1.06, segs=6, squash=GEM_SQ,
              rot=D.aim(HEAD_DIR) @ D.rot_euler(0.0, 0.0, 18.0))


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R
    arms = _arms(D)

    # ---- trunk -------------------------------------------------------------
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("nar_alien_grn"), rbx_material="SmoothPlastic")

    # ---- the two arms: a stub out of the side, then a column turning up -----
    bm = bmesh.new()
    for a in arms:
        D.cuke_body(bm, h=a["hlen"], r=AR, profile=D.CUKE_PROFILE_STUB, nub=None,
                    matrix=a["stub_m"])
        D.cuke_body(bm, h=a["colh"], r=AR, nub=None, matrix=a["col_m"])
    D.new_obj("Arms", bm, c, D.C("nar_alien_grn"), rbx_material="SmoothPlastic")

    # ---- speckles: trunk + both arms, one object ---------------------------
    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, rows=5, per_row=3, z0=0.12, z1=0.90,
                 size=0.27, rise=0.05, seed=11)
    for a in arms:
        D.cuke_studs(bm, h=a["colh"], r=AR, slots=COL_STUDS, size=0.17, rise=0.035,
                     matrix=a["col_m"])
        D.cuke_studs(bm, h=a["hlen"], r=AR, slots=STUB_STUDS, size=0.17, rise=0.035,
                     profile=D.CUKE_PROFILE_STUB, matrix=a["stub_m"])
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- the crystals: ten bright, four dark among them --------------------
    bm = bmesh.new()
    _gems(D, bm, random.Random(21), H, R, arms, BODY_GEMS, COL_GEMS, head=True)
    D.new_obj("Gems", bm, c, D.C("nar_gem"), rbx_material="Neon", emit=0.65)

    bm = bmesh.new()
    _gems(D, bm, random.Random(34), H, R, arms, BODY_GEMS_DK, COL_GEMS_DK)
    D.new_obj("GemsDark", bm, c, D.C("nar_gem_dk"), rbx_material="Neon", emit=0.65)

    return c
