"""Underwater: Bubble Tree - deep-blue stepped stalk carrying four glassy bubbles."""
import bmesh, math, random

COLLECTION = "UnderwaterBubbleTree"
NOTES = ("An 11.8-stud undersea tree: the CucumberTree skeleton with bubbles instead of "
         "crown cubes.  A three-step deep-blue plinth, a tapering blocky trunk of three "
         "blocks speckled with darker blue squares, and FOUR square forks - one leader "
         "running straight up and three spreading out - every tip dying INSIDE a bubble "
         "so nothing floats.  The crown is four translucent glass bubbles (radii 1.55 / "
         "1.05 / 0.95 / 0.85, transparency 0.48, smooth), the biggest sitting on top at "
         "z 10.20, each wearing five white square glints snapped flat onto its facets "
         "over the camera-facing upper half.  Footprint ~6.1 x 5.2, 11.75 tall, nothing "
         "below z=0, centred on x=0/y=0, faces +Y.  Four parts: Trunk, TrunkStuds, "
         "Bubbles, BubbleStuds.")

# ---- the stalk -----------------------------------------------------------
BASE_TOP_W, BASE_H, BASE_STEPS, BASE_GROW = 1.55, 1.55, 3, 1.30
TRUNK_Z0, TRUNK_Z1 = BASE_H, 6.40
TRUNK_W0, TRUNK_W1, TRUNK_BLOCKS = 1.46, 1.00, 3

# (end x, end y, end z, start z, base width, tip width) - every end lands in a bubble
BRANCHES = [
    (0.05, 0.30, 9.55, 6.05, 0.72, 0.48),      # the leader, up into the big bubble
    (2.00, -0.50, 8.15, 5.25, 0.60, 0.40),     # screen-left
    (-1.95, 1.08, 7.95, 5.10, 0.58, 0.38),     # screen-right, set back
    (-0.27, -2.08, 7.60, 5.55, 0.56, 0.36),    # toward the viewer
]

# ---- the crown -----------------------------------------------------------
# (x, y, z, radius, stud count, stud size)
BUBBLES = [
    (0.05, 0.35, 10.20, 1.55, 5, 0.46),        # the big one on top
    (2.08, -0.56, 8.30, 1.05, 5, 0.34),
    (-2.04, 1.15, 8.10, 0.95, 5, 0.32),
    (-0.29, -2.20, 7.75, 0.85, 5, 0.30),
]
SPH_SEGS, SPH_RINGS = 12, 8


def _sphere_facets(center, radius, segs, rings):
    """(point, outward normal) at the centre of every QUAD facet of a uv sphere.

    The four corners of such a facet are coplanar, so their centroid lies exactly in
    the facet plane - which is what keeps a square speckle sitting flat on it."""
    cx, cy, cz = center
    out = []
    for k in range(1, rings - 1):                       # skip the two pole fans
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
            if sum(n[j] * u[j] for j in range(3)) < 0.0:        # face outward
                n = [-v for v in n]
            L = math.sqrt(sum(v * v for v in n)) or 1.0
            out.append(((cx + radius * u[0], cy + radius * u[1], cz + radius * u[2]),
                        (n[0] / L, n[1] / L, n[2] / L)))
    return out


def _spread(facets, count, gap, rng):
    """Pick `count` facets that are at least `gap` apart, so no two glints touch."""
    rng.shuffle(facets)
    picked, used = [], set()
    for g in (gap, gap * 0.5, 0.0):
        for j, (p, n) in enumerate(facets):
            if len(picked) >= count:
                break
            if j in used:
                continue
            if all((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2
                   >= g * g for (q, _) in picked):
                picked.append((p, n))
                used.add(j)
    return picked


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- plinth + trunk + forks, all one deep-blue object -----------------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=BASE_TOP_W, h=BASE_H, steps=BASE_STEPS, grow=BASE_GROW,
                   bevel=0.09)
    D.blocky_trunk(bm, TRUNK_Z0, TRUNK_Z1, TRUNK_W0, TRUNK_W1, blocks=TRUNK_BLOCKS,
                   bevel=0.08)
    for (bx, by, bz, z0, w0, w1) in BRANCHES:
        D.branch_box(bm, (0.0, 0.0, z0), (bx, by, bz), w0, w1, bevel=0.05)
    D.new_obj("Trunk", bm, c, D.C("sea_deep"), rbx_material="Slate")

    # ---- darker speckles up the trunk blocks and the top step -------------
    bm = bmesh.new()
    sh = (TRUNK_Z1 - TRUNK_Z0) / float(TRUNK_BLOCKS)
    for i in range(TRUNK_BLOCKS):
        w = TRUNK_W0 + (TRUNK_W1 - TRUNK_W0) * ((i + 0.5) / float(TRUNK_BLOCKS))
        lo = (-w / 2.0, -w / 2.0, TRUNK_Z0 + i * sh)
        hi = (w / 2.0, w / 2.0, TRUNK_Z0 + (i + 1) * sh + 0.014)
        D.box_studs(bm, lo, hi, faces=("+y", "+x", "-x"), grid=(1, 2), size=0.32,
                    rise=0.06, seed=11 + i, margin=0.30)
    step_h = BASE_H / float(BASE_STEPS)
    D.box_studs(bm, (-BASE_TOP_W / 2.0, -BASE_TOP_W / 2.0, BASE_H - step_h),
                (BASE_TOP_W / 2.0, BASE_TOP_W / 2.0, BASE_H),
                faces=("+y", "+x", "-x"), grid=(1, 1), size=0.34, rise=0.06,
                seed=17, margin=0.36)
    D.new_obj("TrunkStuds", bm, c, D.C("sea_deep_dk"), rbx_material="Slate")

    # ---- the four bubbles + their glints ----------------------------------
    bm = bmesh.new()
    bm2 = bmesh.new()
    for i, (x, y, z, rad, nstuds, ssize) in enumerate(BUBBLES):
        ctr = (x, y, z)
        D.uvsphere(bm, ctr, rad, segs=SPH_SEGS, rings=SPH_RINGS)

        rng = random.Random(40 + i)
        # glints belong on the camera-facing upper half of a bubble; keeping them
        # above the equator also keeps every recorded point clear of the ground
        facets = [f for f in _sphere_facets(ctr, rad, SPH_SEGS, SPH_RINGS)
                  if f[1][2] > -0.05 and f[1][1] > -0.55]
        for (p, n) in _spread(facets, nstuds, rad * 0.85, rng):
            D.stud_patch(bm2, p, n, size=ssize * rng.uniform(0.88, 1.12),
                         rise=0.055, bevel=0.045)
    D.new_obj("Bubbles", bm, c, D.C("sea_bubble_lt"), rbx_material="Glass",
              transparency=0.48, smooth=True, roughness=0.32)
    D.new_obj("BubbleStuds", bm2, c, D.C("snow_white"), rbx_material="Glass",
              transparency=0.2, roughness=0.32)

    return c
