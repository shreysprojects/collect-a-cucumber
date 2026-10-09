"""Neon: the Electro Cucumber - a standard cucumber orbited by two glowing cyan rings."""
import bmesh, math

COLLECTION = "NeonElectroCucumber"
NOTES = (
    "The set's standard upright cucumber (cuke_green, h 4.0, r 0.68, the (0.30, 0.30) "
    "stem nub, top z 4.30) with the standard 21 raised cuke_stud speckles (rows 7 x 3, "
    "zf 0.11-0.90, size 0.28) - the tile's lighter checker of squares - circled by TWO "
    "glowing cyan rings (neo_cyan, Neon, emit 0.6) that float clear of the skin like "
    "electron orbits.  Ring 1 (the lower one): centred on the body axis at z 1.45 "
    "(zf 0.36), radius 1.05, tube 0.09, 16 x 6 segments.  Ring 2 (the upper one): centred "
    "at z 2.50 (zf 0.62), radius 1.02, tube 0.09, 16 x 6.  Both are tipped so their FRONT "
    "(+Y) arc sits lower than the back and their screen-RIGHT (-X) side lower than the "
    "screen-left (+X) side, the lower ring more steeply: ring 1 = rot_euler(-14, -10, 0) "
    "(17 deg off level), ring 2 = rot_euler(-12, -4, 0) (13 deg), so they are not parallel.  "
    "Ring 1 spans z 1.05-1.85 and ring 2 z 2.19-2.81, so they never meet; each ring's "
    "inner edge stays >= 0.89 from the axis, at least 0.15 clear of the skin and speckles "
    "(which reach r ~0.70).  Footprint ~2.25 x 2.2 (the rings), height 4.30, centred on "
    "x = 0, y = 0, lowest point the body's base on z = 0.  The rings are placed with "
    "rot=, so dryrun's transform-blind bbox is only approximate.  3 parts: Body, Studs, "
    "Rings.  DEVIATIONS from the brief (the tile wins): the brief tipped ring 1 +14 about "
    "X (front RAISED) and ring 2 +8 about Y (which lowers +X = screen-LEFT, the +X trap).  "
    "In the tile both rings are open ellipses seen from above, and both dip toward "
    "screen-right, the lower one more.  Under the set's cuke hero camera (pitched 12 "
    "down) a front-raised ring 1 would show edge-on as a flat bar.  So both rings now "
    "tip front-down, and their Y turns are negative (-X side lower).  The centres, radii, "
    "tube, segment counts and colour are exactly as briefed.  Per the REV3 rule the body "
    "stands upright instead of leaning like the tile.  The tile's small blossom-end tip "
    "under the body is left off: on an upright body it would sit hidden under the base "
    "and would lift the standard body off z = 0."
)

RING_TUBE = 0.09
RING_SEG_MAJOR, RING_SEG_MINOR = 16, 6

# (centre z, ring radius, tilt about X, tilt about Y) - rot_euler degrees, XYZ order.
# Negative X tilt drops the FRONT (+Y) arc so the camera (pitched 12 deg down) sees the
# ring from above, as in the tile.  Negative Y tilt drops the -X side, which is the
# screen RIGHT: the tile's rings both dip that way, the lower one more steeply.
RINGS = [
    (1.45, 1.05, -14.0, -10.0),  # ring 1, zf 0.36 - the lower, steeper one
    (2.50, 1.02, -12.0, -4.0),   # ring 2, zf 0.62 - the upper, flatter one
]


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    h, r = D.CUKE_H, D.CUKE_R

    # ---- the cucumber: the set's reference body, stem nub on top ----------
    bm = bmesh.new()
    D.cuke_body(bm, h=h, r=r, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---- the standard speckles: the tile's lighter checker ----------------
    bm = bmesh.new()
    D.cuke_studs(bm, h=h, r=r, rows=7, per_row=3, z0=0.11, z1=0.90,
                 size=0.28, rise=0.055, seed=7)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- the two electric rings, floating clear of the skin ---------------
    bm = bmesh.new()
    for z, major, tilt_x, tilt_y in RINGS:
        D.torus(bm, (0.0, 0.0, z), major, RING_TUBE, rot=D.rot_euler(tilt_x, tilt_y, 0.0),
                seg_major=RING_SEG_MAJOR, seg_minor=RING_SEG_MINOR)
    D.new_obj("Rings", bm, c, D.C("neo_cyan"), rbx_material="Neon", emit=0.6)

    return c
