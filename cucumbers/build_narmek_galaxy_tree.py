"""Narmek: Galaxy Tree - a purple stepped trunk carrying three flat spiral-galaxy discs."""
import bmesh, math, random

COLLECTION = "NarmekGalaxyTree"
NOTES = ("An 11.8-stud cosmic tree.  A three-step purple plinth and a four-block tapering "
         "trunk in nar_galaxy, speckled nar_galaxy_dk, with two short forks reaching out "
         "left (+x) and right (-x).  Each fork and the trunk head carries a flat "
         "nar_galaxy_dk saucer disc (radius 2.2 on top at z 10.70, 1.35 and 1.15 on the "
         "forks).  Every disc top carries a spiral galaxy painted FLAT on it: two pale "
         "nar_star arms lofted along a 1.05-turn spiral at opposite phases, lying 0.03 "
         "proud of the face, sweeping out of a small glowing nar_galaxy_c core - a "
         "squashed neon dome at most 0.35 across and 0.24 tall, no spire - with tiny "
         "neon nar_star squares scattered between them.  Faces +Y, footprint ~6.7 x 4.7. "
         "Six parts: Trunk, TrunkStuds, Discs, Arms, Cores, Stars.")

# ---- trunk -----------------------------------------------------------------
BASE_TOP_W = 1.50
BASE_H = 1.70
BASE_STEPS = 3
BASE_GROW = 1.30

TRUNK_Z1 = 10.65
TRUNK_W0, TRUNK_W1 = 1.45, 0.82
TRUNK_BLOCKS = 4

# (start point, end point, base width, tip width) - the two short forks
FORKS = [
    ((0.30, 0.05, 7.05), (2.15, -1.15, 8.40), 0.62, 0.40),
    ((-0.28, -0.06, 6.05), (-2.05, 0.90, 7.25), 0.58, 0.38),
]

# ---- galaxy discs ----------------------------------------------------------
DISC_T = 0.34
DISC_RIM = 0.20
DISC_SEGS = 14

# (cx, cy, cz, radius, arm r0, arm r1, arm points, core r, core height, core segs, stars)
DISCS = [
    (0.00, 0.00, 10.70, 2.20, 0.130, 0.055, 14, 0.175, 0.24, 10, 5),
    (2.15, -1.15, 8.52, 1.35, 0.100, 0.050, 13, 0.150, 0.20, 8, 3),
    (-2.05, 0.90, 7.37, 1.15, 0.100, 0.050, 12, 0.130, 0.18, 8, 2),
]

CORE_SINK = 0.03      # how far the core lump beds into the disc's top face


def _trunk_boxes():
    """The same block boxes `blocky_trunk` builds - so the speckles land on them."""
    out = []
    sh = (TRUNK_Z1 - BASE_H) / float(TRUNK_BLOCKS)
    for i in range(TRUNK_BLOCKS):
        t = (i + 0.5) / float(TRUNK_BLOCKS)
        w = TRUNK_W0 + (TRUNK_W1 - TRUNK_W0) * t
        z0 = BASE_H + i * sh
        out.append(((-w / 2.0, -w / 2.0, z0), (w / 2.0, w / 2.0, z0 + sh + 0.014)))
    return out


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- trunk: plinth, stacked blocks, two short forks ---------------------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=BASE_TOP_W, h=BASE_H, steps=BASE_STEPS, grow=BASE_GROW,
                   bevel=0.09)
    D.blocky_trunk(bm, BASE_H, TRUNK_Z1, TRUNK_W0, TRUNK_W1, blocks=TRUNK_BLOCKS,
                   bevel=0.09)
    for (a, b, w0, w1) in FORKS:
        D.branch_box(bm, a, b, w0, w1, bevel=0.05)
    D.new_obj("Trunk", bm, c, D.C("nar_galaxy"), rbx_material="Slate", roughness=0.62)

    # ---- the raised squares up the trunk ------------------------------------
    bm = bmesh.new()
    for i, (lo, hi) in enumerate(_trunk_boxes()):
        D.box_studs(bm, lo, hi, faces=("+y", "-y", "+x", "-x"), grid=(1, 2), size=0.30,
                    rise=0.055, seed=61 + i, margin=0.34)
    D.new_obj("TrunkStuds", bm, c, D.C("nar_galaxy_dk"), rbx_material="Slate",
              roughness=0.62)

    # ---- the three flat galaxy discs ----------------------------------------
    bm = bmesh.new()
    for d in DISCS:
        D.disc_canopy(bm, center=(d[0], d[1], d[2]), radius=d[3], thick=DISC_T,
                      rim=DISC_RIM, segs=DISC_SEGS)
    D.new_obj("Discs", bm, c, D.C("nar_galaxy_dk"), rbx_material="SmoothPlastic")

    # ---- two spiral arms lying on each disc's top face -----------------------
    bm = bmesh.new()
    for d in DISCS:
        cx, cy, cz, R, a0, a1, an = d[0], d[1], d[2], d[3], d[4], d[5], d[6]
        armz = cz + DISC_T * 0.5 + 0.03
        radii = [a0 + (a1 - a0) * (i / float(an - 1)) for i in range(an)]
        for phase in (0.0, 180.0):
            pts = D.spiral_pts(center=(cx, cy, armz), r0=0.12, r1=0.90 * R, turns=1.05,
                               n=an, plane="XY", phase_deg=phase)
            D.tube(bm, pts, radii, segs=5)
    D.new_obj("Arms", bm, c, D.C("nar_star"), rbx_material="SmoothPlastic")

    # ---- the small glowing core lump at each galaxy's middle ------------------
    # A squashed dome, NOT a spire: it has to read as a bright nucleus lying on the
    # disc, so it stays under 0.25 tall and 0.35 across.
    bm = bmesh.new()
    for d in DISCS:
        top = d[2] + DISC_T * 0.5
        gr, gh, gsegs = d[7], d[8], d[9]
        D.lathe(bm, [(0.0, -CORE_SINK), (gr * 0.74, -CORE_SINK), (gr, gh * 0.34),
                     (gr * 0.60, gh * 0.76), (0.0, gh)],
                segs=gsegs, phase=math.pi / gsegs,
                matrix=D.place((d[0], d[1], top)))
    D.new_obj("Cores", bm, c, D.C("nar_galaxy_c"), rbx_material="Neon", emit=0.65)

    # ---- tiny stars scattered over the discs ---------------------------------
    rng = random.Random(4131)
    bm = bmesh.new()
    for d in DISCS:
        cx, cy, R, n = d[0], d[1], d[3], d[10]
        top = d[2] + DISC_T * 0.5
        for k in range(n):
            ang = rng.uniform(0.0, 2.0 * math.pi)
            rr = R * rng.uniform(0.40, 0.90)
            D.stud_patch(bm, (cx + math.cos(ang) * rr, cy + math.sin(ang) * rr, top),
                         (0.0, 0.0, 1.0), size=rng.uniform(0.13, 0.20), rise=0.05,
                         bevel=0.025, spin=rng.uniform(0.0, 90.0))
    D.new_obj("Stars", bm, c, D.C("nar_star"), rbx_material="Neon", emit=0.65)

    return c
