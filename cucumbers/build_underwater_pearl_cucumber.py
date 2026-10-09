"""Underwater: the PearlCucumber - a cream body with six big white pearls on its sides."""
import bmesh, math, random

COLLECTION = "UnderwaterPearlCucumber"
NOTES = ("A standard 4.0-tall cucumber body in cream `sea_pearl` with a (0.30, 0.30) stem "
         "nub, speckled with the set's raised squares in the slightly darker "
         "`sea_pearl_sh`.  Stuck down its sides are SIX big white pearls - smooth-shaded "
         "uvspheres of radius 0.30-0.34 buried about 40 %% of their radius into the skin, "
         "climbing the body at height fractions 0.20 / 0.33 / 0.46 / 0.59 / 0.72 / 0.85 "
         "on facets 0, 2, 1, 7, 2, 0, so three of them read on the front (+Y) half and "
         "none is hidden round the back.  Speckles that a pearl would swallow are dropped "
         "from the scatter, so no stud is wasted inside a sphere.  Footprint about "
         "2.3 x 2.3 studs, 4.3 tall to the top of the nub; nothing below z = 0; centred "
         "on x = 0, y = 0 and facing +Y.  3 parts: Body, Studs, Pearls.")

# How far each pearl's CENTRE stands out from the facet plane it sits on.  The pearls are
# radius ~0.32, so 0.185 leaves roughly 40 % of each sphere sunk into the body - enough to
# read as "stuck on" rather than floating, and it puts the widest point at x/y ~ 1.13.
PEARL_OFFSET = 0.185

# (height fraction, facet index, radius).  Facet 0 = +45 deg, 1 = +Y (the front),
# 2 = 135 deg, 7 = +X - so the six alternate sides as they climb and three face the camera.
PEARLS = [
    (0.20, 0, 0.33),
    (0.33, 2, 0.31),
    (0.46, 1, 0.34),
    (0.59, 7, 0.30),
    (0.72, 2, 0.32),
    (0.85, 0, 0.33),
]


# The scattered speckles that would land inside a pearl are dropped, and the front facets
# lose the most of them - these put a few back on the camera side, above and below the
# pearls.  They go through the same clearance test as the scattered ones.
EXTRA_SLOTS = [(0.28, 1), (0.70, 1), (0.24, 7)]


def _dist(a, b):
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R
    rng = random.Random(21)

    # where every pearl's centre lands, worked out once so the speckles can dodge them
    pearls = []
    for zf, facet, rad in PEARLS:
        ctr, _n = D.cuke_facet_point(h=H, r=R, zf=zf, facet=facet, offset=PEARL_OFFSET)
        pearls.append((ctr, rad))

    # ---------------------------------------------------------------- body
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("sea_pearl"), rbx_material="SmoothPlastic")

    # ------------------------------------------------------------ speckles
    scatter = D.cuke_stud_slots(rows=7, per_row=3, z0=0.11, z1=0.90, seed=7)
    slots = []
    for zf, facet in list(scatter) + EXTRA_SLOTS:
        p, _n = D.cuke_facet_point(h=H, r=R, zf=zf, facet=facet)
        if any(_dist(p, ctr) < rad + 0.17 for ctr, rad in pearls):
            continue                      # this one would sit inside a pearl
        slots.append((zf, facet))

    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, size=0.28, rise=0.055, slots=slots)
    D.new_obj("Studs", bm, c, D.C("sea_pearl_sh"), rbx_material="SmoothPlastic")

    # -------------------------------------------------------------- pearls
    bm = bmesh.new()
    for ctr, rad in pearls:
        D.uvsphere(bm, ctr, rad, segs=10, rings=7,
                   rot=D.rot_euler(rng.uniform(-20.0, 20.0),
                                   rng.uniform(-20.0, 20.0),
                                   rng.uniform(0.0, 360.0)))
    D.new_obj("Pearls", bm, c, D.C("snow_white"), rbx_material="SmoothPlastic",
              smooth=True, roughness=0.32)

    return c
