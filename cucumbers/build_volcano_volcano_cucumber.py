"""Volcano: Volcano Cucumber - a cucumber-green volcano CONE erupting lava."""
import bmesh, math, random

COLLECTION = "VolcanoVolcanoCucumber"
NOTES = ("An actual VOLCANO built out of cucumber, not a cucumber wearing a lava hat.  "
         "A broad, slightly concave 10-sided mountain lathed in cuke_green - 1.75 studs "
         "of base radius on the ground, narrowing to a crater rim of 0.55 at z = 3.50 - "
         "whose profile then folds back DOWN inside itself to a bowl floor at z = 3.06, "
         "so the summit is genuinely hollow.  Fifteen cuke_stud speckles, the set's "
         "signature, are placed by hand on the sloping flanks with normals that lean "
         "outward AND up, so they lie flat on the slope instead of standing off it; the "
         "green skin with its speckles is what makes this read as the same cucumber as "
         "every other model in the set.  A pool of lava brims in the crater exactly to "
         "the rim (vol_lava_hot, Neon) leaving a ring of green rim showing round it, and "
         "FIVE flows pour over the lip and run down the outside as 4-point tubes hugging "
         "the facets (vol_lava, Neon), fat at the top and tapering to a point between "
         "z 0.62 and z 1.55 - the long one comes straight down the front facet, which "
         "faces +Y.  Three lava lumps are thrown clear of the vent, floating at "
         "z 4.08 / 4.40 / 4.62 in vol_ember (Neon) at three sizes and three random "
         "tumbles so they read as ejecta.  Most of the mountain is still GREEN.  "
         "Five parts: Cone, Studs, Crater, Flows, Ejecta; about 3.5 x 3.3 x 4.9 studs, "
         "centred on x = 0, y = 0, nothing below z = 0.  dryrun cannot see a lathe's "
         "(radius, z) profile, so the width it prints is an under-estimate; the real "
         "footprint is 2 x 1.75 across.")

SEGS = 10
PHASE = 0.0             # with segs 10 this puts a flat FACET (facet 2) square on +Y

# The mountain, as (radius, z): up the outside, over the crater rim, and back DOWN
# inside into a shallow bowl, so D.lathe closes it as a hollow-topped cone.
CONE = [
    (0.00, 0.00),       # the ground pole - the flat base
    (1.75, 0.00),       # the skirt
    (1.52, 0.55),
    (1.24, 1.25),
    (0.98, 2.00),       # the flanks, slightly concave like a real cone
    (0.78, 2.70),
    (0.62, 3.22),
    (0.55, 3.50),       # the crater rim - the highest green
    (0.42, 3.42),       # over the lip, heading back down
    (0.28, 3.16),       # the inner wall
    (0.00, 3.06),       # the bowl floor
]

# The lava that fills the bowl, brimming level with the rim at z 3.46.
CRATER = [
    (0.00, 3.08), (0.30, 3.10), (0.46, 3.28), (0.56, 3.46),
    (0.50, 3.56), (0.22, 3.57), (0.00, 3.55),
]

# Speckles on the flanks: (z, facet).  Facet 2 faces +Y, so 1/2/3 are the front.
STUD_SLOTS = [
    (0.44, 1), (0.52, 4), (0.40, 7), (0.66, 9),
    (1.08, 2), (1.18, 5), (0.98, 0), (1.30, 7),
    (1.75, 3), (1.84, 6), (1.66, 9),
    (2.42, 2), (2.50, 5),
    (2.98, 3), (2.90, 0),
]

# (facet, z the flow reaches, sideways wobble deg, radius where it is fattest)
FLOWS = [
    (2, 0.62, -7.0, 0.23),      # the long one straight down the front
    (0, 1.18, 6.0, 0.20),
    (4, 0.92, -5.0, 0.21),
    (6, 1.55, 7.0, 0.17),       # one round the back so it reads from every side
    (8, 1.06, -6.0, 0.19),
]

# (centre, size across, tumble in degrees)
EJECTA = [
    ((0.16, -0.26, 4.08), 0.40, (18.0, 24.0, 12.0)),
    ((-0.40, 0.14, 4.40), 0.32, (-22.0, 14.0, 30.0)),
    ((0.30, 0.22, 4.62), 0.26, (10.0, -28.0, -16.0)),
]


def _flank(z):
    """(radius, (radial normal, z normal)) on the cone's OUTER slope at height z."""
    for i in range(len(CONE) - 1):
        r0, z0 = CONE[i]
        r1, z1 = CONE[i + 1]
        if z1 - z0 <= 1e-9:                 # the base ring and every inner, descending run
            continue
        if z0 - 1e-9 <= z <= z1 + 1e-9:
            dr, dz = r1 - r0, z1 - z0
            L = math.hypot(dr, dz)
            return r0 + dr * (z - z0) / dz, (dz / L, -dr / L)
    return CONE[7][0], (1.0, 0.0)


def _facet_deg(facet):
    """Outward angle (degrees) of the centre of facet `facet`.  Facet 2 -> +Y."""
    return math.degrees(PHASE + (2.0 * facet + 1.0) * math.pi / SEGS)


def _skin(z, angle_deg, offset=0.0):
    """(point, outward normal) on the cone's FACET plane - what the 10-gon really is."""
    r, (nr, nz) = _flank(z)
    a = math.radians(angle_deg)
    rr = r * math.cos(math.pi / SEGS) + offset
    return ((math.cos(a) * rr, math.sin(a) * rr, z),
            (math.cos(a) * nr, math.sin(a) * nr, nz))


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- the mountain: cucumber skin, hollow summit -----------------------
    bm = bmesh.new()
    D.lathe(bm, CONE, segs=SEGS, phase=PHASE)
    D.new_obj("Cone", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---- the set's speckles, lying flat on the slope ----------------------
    bm = bmesh.new()
    rng = random.Random(21)
    for z, facet in STUD_SLOTS:
        p, n = _skin(z, _facet_deg(facet))
        D.stud_patch(bm, p, n, size=0.30 + rng.uniform(-0.04, 0.05), rise=0.05,
                     spin=rng.uniform(-8.0, 8.0))
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- lava brimming in the crater --------------------------------------
    bm = bmesh.new()
    D.lathe(bm, CRATER, segs=SEGS, phase=PHASE)
    D.new_obj("Crater", bm, c, D.C("vol_lava_hot"), rbx_material="Neon", emit=0.65)

    # ---- what pours over the rim and runs down the flanks ------------------
    bm = bmesh.new()
    for facet, end_z, wob, rr in FLOWS:
        deg = _facet_deg(facet)
        a = math.radians(deg)
        top = (math.cos(a) * 0.48, math.sin(a) * 0.48, 3.54)        # in the pool
        lip = _skin(3.26, deg + wob * 0.15, 0.07)[0]                # over the lip
        mid = _skin(end_z + (3.26 - end_z) * 0.52, deg + wob * 0.55, 0.06)[0]
        tip = _skin(end_z, deg + wob, 0.05)[0]
        D.tube(bm, [top, lip, mid, tip], [rr * 0.85, rr, rr * 0.62, 0.08], segs=6)
    D.new_obj("Flows", bm, c, D.C("vol_lava"), rbx_material="Neon", emit=0.65)

    # ---- three lumps thrown clear of the vent ------------------------------
    bm = bmesh.new()
    for (x, y, z), s, (rx, ry, rz) in EJECTA:
        hs = s / 2.0
        D.beveled_box(bm, (x - hs, y - hs, z - hs), (x + hs, y + hs, z + hs),
                      bevel=s * 0.18, rot=D.rot_euler(rx, ry, rz))
    D.new_obj("Ejecta", bm, c, D.C("vol_ember"), rbx_material="Neon", emit=0.65)

    return c
