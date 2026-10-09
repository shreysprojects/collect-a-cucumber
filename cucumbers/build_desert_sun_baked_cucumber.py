"""Desert: the Sun-Baked Cucumber - a drab khaki pillar split by dark dried cracks."""
import bmesh, math, random

COLLECTION = "DesertSunBakedCucumber"
NOTES = (
    "A standard 4.0-tall cucumber pillar (1.36 across) that has sat in the sun until it "
    "went drab: the body is olive-khaki `des_baked` on Sand, its 23 speckles are "
    "`des_baked_dk` - DARKER than the skin, so it reads baked rather than fresh - and its "
    "top 0.56 studs are a darker dried shoulder cap carrying a two-stage stem nub, taking "
    "the model to 4.40 tall.  The signature is four `des_crack` splits drawn on the front "
    "half of the skin: an X centred on the front facet at zf 0.545, a long zig-zag split "
    "running zf 0.15-0.75 down the +45 degree facet, and a short fork on the 135 degree "
    "facet.  Every crack stays between 72 and 138 degrees so the whole story is told from "
    "the +Y camera; the speckles are hand-slotted around the cracks so nothing sits on "
    "top of a split.  Footprint ~1.37 x 1.37, nothing below z = 0, centred on x=0,y=0.  "
    "4 parts: Body, Studs, Cracks, Shoulder."
)

H, R = 4.0, 0.68

# --- the cracks: [(height fraction, angle_deg)], +Y is 90 deg, front half only ---------
CRACKS = [
    # the X on the front facet - the arm climbing toward screen-right ...
    [(0.42, 72), (0.47, 80), (0.545, 90), (0.62, 100), (0.68, 108)],
    # ... and the arm falling the other way, through exactly the same crossing point
    [(0.69, 73), (0.62, 81), (0.545, 90), (0.47, 99), (0.41, 107)],
    # the long vertical split zig-zagging down the 45-degree facet
    [(0.15, 43), (0.27, 36), (0.39, 45), (0.51, 37), (0.63, 46), (0.75, 40)],
    # a short fork on the 135-degree facet
    [(0.33, 130), (0.41, 138), (0.49, 129), (0.57, 137), (0.63, 131)],
]

# --- speckle slots: (height fraction, facet).  facet 1 = +Y, 0 = +45, 2 = 135, 7 = +X --
# Deliberately hand-placed so no speckle lands on a crack run.
STUD_SLOTS = [
    (0.17, 1), (0.29, 1), (0.80, 1),                       # front, above and below the X
    (0.10, 0), (0.84, 0),                                  # either end of the long split
    (0.15, 2), (0.28, 2), (0.80, 2),                       # around the fork
    (0.13, 7), (0.36, 7), (0.58, 7), (0.79, 7),            # +X flank (screen-left)
    (0.21, 3), (0.44, 3), (0.66, 3), (0.85, 3),            # -X flank (screen-right)
    (0.25, 6), (0.63, 6),
    (0.33, 4), (0.71, 4),
    (0.19, 5), (0.52, 5), (0.78, 5),                       # the back
]


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---------------------------------------------------------------- body
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=None)
    D.new_obj("Body", bm, c, D.C("des_baked"), rbx_material="Sand", roughness=0.78)

    # ---------------------------------------------------------------- speckles
    # Placed one by one rather than through cuke_studs so the sizes can vary a little:
    # baked skin is blotchy, not gridded.
    rng = random.Random(31)
    bm = bmesh.new()
    for zf, facet in STUD_SLOTS:
        p, n = D.cuke_facet_point(h=H, r=R, zf=zf, facet=facet)
        D.stud_patch(bm, p, n,
                     size=rng.uniform(0.22, 0.30),
                     rise=0.05,
                     aspect=rng.uniform(0.82, 1.22),
                     spin=rng.uniform(-9.0, 9.0))
    D.new_obj("Studs", bm, c, D.C("des_baked_dk"), rbx_material="SmoothPlastic",
              roughness=0.7)

    # ---------------------------------------------------------------- the cracks
    # `thick` is given explicitly: the body is an 8-gon, so a strip laid on the facet
    # PLANE has to be thick enough to still break the skin where the run wanders out
    # toward a facet edge (0.68 there against 0.628 at the facet centre).  The visible
    # rise stays 0.015-0.06.
    bm = bmesh.new()
    for line in CRACKS:
        D.surface_line(bm, line, h=H, r=R, width=0.075, rise=0.015, thick=0.12)
    D.new_obj("Cracks", bm, c, D.C("des_crack"), rbx_material="Slate", roughness=0.9)

    # ---------------------------------------------------------------- dried shoulder + nub
    # A darker cap shelled 0.02 over the body's top chamfer, so the head reads as the
    # driest part, plus the shrivelled two-stage stem on top of it.
    bm = bmesh.new()
    shoulder = [
        (0.00, 0.860 * H),
        (0.970 * R + 0.022, 0.860 * H),
        (0.970 * R + 0.022, 0.872 * H),
        (0.880 * R + 0.020, 0.922 * H),
        (0.700 * R + 0.018, 0.964 * H),
        (0.480 * R + 0.014, 1.000 * H),
        (0.00, 1.005 * H),
    ]
    D.lathe(bm, shoulder, segs=8, phase=D.cuke_phase(8), cap=True)
    D.beveled_box(bm, (-0.15, -0.15, 3.97), (0.15, 0.15, 4.24), bevel=0.045)
    D.beveled_box(bm, (-0.09, -0.09, 4.21), (0.09, 0.09, 4.40), bevel=0.03)
    D.new_obj("Shoulder", bm, c, D.C("des_baked_dk"), rbx_material="Sand", roughness=0.8)

    return c
