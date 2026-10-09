"""Underwater: Coral Tree - a purple stepped stalk breaking into a staghorn coral thicket."""
import bmesh, math

COLLECTION = "UnderwaterCoralTree"
NOTES = ("An 11.5-stud coral tree: a three-step purple plinth and a tapering blocky stalk "
         "up to z 5.5, speckled with darker purple squares, that breaks into three "
         "branching staghorn coral arms (depth 3, two branches a level) reaching z 11.5 - "
         "two red, one orange, interleaved so the crown reads as a red-and-orange thicket. "
         "Footprint about 6.7 x 5.5 studs, stalk footprint 2.7.  No crown cubes, no "
         "leaves, no hanging fruit.  Faces +Y, centred on x=0/y=0, sits on z=0.  "
         "Four parts: Trunk, TrunkStuds, CoralRed, CoralOrange.")

# ---- trunk geometry (kept here so the speckles can be placed on the real boxes) ----
BASE_TOP_W, BASE_H, BASE_STEPS, BASE_GROW = 1.60, 1.70, 3, 1.30
TRUNK_Z0, TRUNK_Z1 = BASE_H, 5.50
TRUNK_W0, TRUNK_W1, TRUNK_BLOCKS = 1.50, 1.00, 3

# coral arms: (base point, growth direction, seed, colour key)
#   A grows toward +X (screen left), B back toward -X/-Y, C forward toward +Y,
#   so the three thickets interleave instead of stacking on top of each other.
ARMS = [
    ((0.34, 0.16, 5.20), (0.22, 0.08, 1.00), 79, "r"),
    ((-0.32, -0.18, 5.32), (-0.20, -0.18, 1.00), 15, "o"),
    ((0.02, 0.34, 5.00), (-0.05, 0.24, 1.00), 11, "r"),
]


def _base_boxes():
    """The stepped_base boxes, same maths the lib uses - for stud placement."""
    out, sh = [], BASE_H / float(BASE_STEPS)
    for i in range(BASE_STEPS):
        w = BASE_TOP_W * (BASE_GROW ** (BASE_STEPS - 1 - i))
        z = i * sh
        out.append(((-w / 2, -w / 2, z), (w / 2, w / 2, z + sh + 0.012)))
    return out


def _trunk_boxes():
    """The blocky_trunk boxes, same maths the lib uses - for stud placement."""
    out, sh = [], (TRUNK_Z1 - TRUNK_Z0) / float(TRUNK_BLOCKS)
    for i in range(TRUNK_BLOCKS):
        t = (i + 0.5) / float(TRUNK_BLOCKS)
        w = TRUNK_W0 + (TRUNK_W1 - TRUNK_W0) * t
        out.append(((-w / 2, -w / 2, TRUNK_Z0 + i * sh),
                    (w / 2, w / 2, TRUNK_Z0 + (i + 1) * sh + 0.014)))
    return out


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- stalk: plinth + tapering blocky trunk -----------------------------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=BASE_TOP_W, h=BASE_H, steps=BASE_STEPS, grow=BASE_GROW,
                   bevel=0.09)
    D.blocky_trunk(bm, TRUNK_Z0, TRUNK_Z1, TRUNK_W0, TRUNK_W1, blocks=TRUNK_BLOCKS,
                   bevel=0.08)
    D.new_obj("Trunk", bm, c, D.C("sea_coral_p"), rbx_material="Sandstone")

    # ---- polyp speckles up the stalk ---------------------------------------
    bm = bmesh.new()
    for i, (lo, hi) in enumerate(_trunk_boxes()):
        D.box_studs(bm, lo, hi, faces=("+x", "-x", "+y", "-y"), grid=(1, 2), size=0.30,
                    rise=0.06, seed=41 + i, margin=0.30)
    lo, hi = _base_boxes()[1]                      # the middle step of the plinth
    D.box_studs(bm, lo, hi, faces=("+x", "-x", "+y", "-y"), grid=(1, 1), size=0.36,
                rise=0.06, seed=61, margin=0.34)
    D.new_obj("TrunkStuds", bm, c, D.C("sea_coral_pd"), rbx_material="Sandstone")

    # ---- the staghorn thicket ----------------------------------------------
    red, orange = bmesh.new(), bmesh.new()
    for base, direction, seed, key in ARMS:
        D.coral_arm(red if key == "r" else orange, base=base, direction=direction,
                    length=2.60, radius=0.34, depth=3, branches=2, spread=38.0,
                    shrink=0.62, seed=seed, segs=5, curl=0.18)
    D.new_obj("CoralRed", red, c, D.C("sea_coral_r"), rbx_material="Pebble")
    D.new_obj("CoralOrange", orange, c, D.C("sea_coral_o"), rbx_material="Pebble")

    return c
