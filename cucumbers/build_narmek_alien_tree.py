"""Narmek: Alien Tree - teal blocky trunk forking into a cluster of orange spheres."""
import bmesh, math, random

COLLECTION = "NarmekAlienTree"
NOTES = ("An 11.5-stud alien tree: the CucumberTree skeleton rebuilt in teal.  A two-step "
         "dark-teal plinth, a tapering blocky trunk of three teal blocks speckled with "
         "darker teal squares, and four straight square forks that run up and DIE INSIDE "
         "the crown spheres.  The crown is five orange spheres (radii 1.15-1.40) in a "
         "loose overlapping cluster, the biggest sitting on top at z 10.1, each speckled "
         "with darker amber squares snapped flat onto its facets.  Footprint 6.4 x 5.3, "
         "11.5 tall, nothing below z=0, faces +Y.  Five parts: Base, Trunk, TrunkStuds, "
         "Crown, CrownStuds.")

# ---- trunk ---------------------------------------------------------------
BASE_TOP_W, BASE_H, BASE_STEPS, BASE_GROW = 1.55, 1.35, 2, 1.38
TRUNK_Z0, TRUNK_Z1 = BASE_H, 6.10
TRUNK_W0, TRUNK_W1, TRUNK_BLOCKS = 1.42, 1.00, 3

# (end x, end y, end z, start z) - every end point lands INSIDE a crown sphere
BRANCHES = [
    (1.75, -0.15, 8.30, 5.05),
    (-1.70, 0.20, 8.40, 4.95),
    (-0.80, -1.30, 8.05, 5.50),
    (0.85, 1.35, 8.15, 5.50),
]

# ---- crown ---------------------------------------------------------------
CROWN_CTR = (0.05, 0.0, 8.70)
# (dx, dy, dz, radius, studs) around the crown centre
SPHERES = [
    (0.00, 0.05, 1.40, 1.40, 6),        # the big one on top
    (1.95, -0.20, -0.10, 1.28, 5),      # screen-left
    (-1.90, 0.25, 0.05, 1.22, 5),       # screen-right
    (-0.85, -1.45, -0.45, 1.15, 5),     # toward the viewer
    (0.95, 1.50, -0.35, 1.18, 4),       # behind
]
SPH_SEGS, SPH_RINGS = 10, 7


def _sphere_facets(center, radius, segs, rings):
    """(point, outward normal) at the centre of every QUAD facet of a uv sphere.

    The four corners of such a facet are coplanar, so their centroid lies exactly in
    the facet plane - which is what keeps a square speckle sitting flat on it."""
    cx, cy, cz = center
    out = []
    for k in range(1, rings - 1):                      # skip the two pole fans
        p0, p1 = math.pi * k / rings, math.pi * (k + 1) / rings
        for i in range(segs):
            t0, t1 = 2.0 * math.pi * i / segs, 2.0 * math.pi * (i + 1) / segs
            q = []
            for (t, p) in ((t0, p0), (t1, p0), (t1, p1), (t0, p1)):
                s = math.sin(p)
                q.append((s * math.cos(t), s * math.sin(t), math.cos(p)))
            u = [sum(v[j] for v in q) / 4.0 for j in range(3)]
            a = [q[1][j] - q[0][j] for j in range(3)]
            b = [q[3][j] - q[0][j] for j in range(3)]
            n = [a[1] * b[2] - a[2] * b[1],
                 a[2] * b[0] - a[0] * b[2],
                 a[0] * b[1] - a[1] * b[0]]
            if sum(n[j] * u[j] for j in range(3)) < 0.0:    # face outward
                n = [-v for v in n]
            L = math.sqrt(sum(v * v for v in n)) or 1.0
            out.append(((cx + radius * u[0], cy + radius * u[1], cz + radius * u[2]),
                        (n[0] / L, n[1] / L, n[2] / L)))
    return out


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- plinth ----------------------------------------------------------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=BASE_TOP_W, h=BASE_H, steps=BASE_STEPS, grow=BASE_GROW,
                   bevel=0.09)
    D.new_obj("Base", bm, c, D.C("nar_teal_dk"), rbx_material="Rock")

    # ---- trunk + forks ---------------------------------------------------
    bm = bmesh.new()
    D.blocky_trunk(bm, TRUNK_Z0, TRUNK_Z1, TRUNK_W0, TRUNK_W1, blocks=TRUNK_BLOCKS,
                   bevel=0.08)
    for (bx, by, bz, z0) in BRANCHES:
        D.branch_box(bm, (0.0, 0.0, z0), (bx, by, bz), 0.60, 0.40, bevel=0.05)
    D.new_obj("Trunk", bm, c, D.C("nar_teal"), rbx_material="Wood")

    # ---- speckles on the trunk blocks ------------------------------------
    bm = bmesh.new()
    sh = (TRUNK_Z1 - TRUNK_Z0) / float(TRUNK_BLOCKS)
    for i in range(TRUNK_BLOCKS):
        w = TRUNK_W0 + (TRUNK_W1 - TRUNK_W0) * ((i + 0.5) / float(TRUNK_BLOCKS))
        lo = (-w / 2.0, -w / 2.0, TRUNK_Z0 + i * sh)
        hi = (w / 2.0, w / 2.0, TRUNK_Z0 + (i + 1) * sh + 0.014)
        D.box_studs(bm, lo, hi, faces=("+y", "+x", "-x"), grid=(1, 2), size=0.32,
                    rise=0.06, seed=11 + i, margin=0.30)
    D.new_obj("TrunkStuds", bm, c, D.C("nar_teal_dk"), rbx_material="Wood")

    # ---- the five orange spheres ------------------------------------------
    cx, cy, cz = CROWN_CTR
    bm = bmesh.new()
    bm2 = bmesh.new()
    for i, (dx, dy, dz, rad, nstuds) in enumerate(SPHERES):
        ctr = (cx + dx, cy + dy, cz + dz)
        D.uvsphere(bm, ctr, rad, segs=SPH_SEGS, rings=SPH_RINGS)

        rng = random.Random(40 + i)
        # keep the speckles off the far back so they read from the +Y camera,
        # and spread them out so no two land on touching facets
        facets = [f for f in _sphere_facets(ctr, rad, SPH_SEGS, SPH_RINGS)
                  if f[1][1] > -0.55]
        rng.shuffle(facets)
        picked, used = [], set()
        for gap in (rad * 0.78, 0.0):
            for j, (p, n) in enumerate(facets):
                if len(picked) >= nstuds:
                    break
                if j in used:
                    continue
                if all((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2
                       >= gap * gap for (q, _) in picked):
                    picked.append((p, n))
                    used.add(j)
        for (p, n) in picked:
            D.stud_patch(bm2, p, n, size=rng.uniform(0.40, 0.50), rise=0.07, bevel=0.045)
    D.new_obj("Crown", bm, c, D.C("nar_amber"), rbx_material="SmoothPlastic")
    D.new_obj("CrownStuds", bm2, c, D.C("nar_amber_dk"), rbx_material="SmoothPlastic")

    return c
