"""Underwater: Kelp Tree - a stepped teal stalk under a crown of long drooping kelp blades."""
import bmesh, math, random

COLLECTION = "UnderwaterKelpTree"
NOTES = ("Giant kelp as a toy tree, ~7.2 x 7.1 x 11.2 and facing +Y.  A dark teal "
         "three-step holdfast plinth (1.7 tall) carries a blocky teal stipe that tapers "
         "1.55 -> 0.95 up to z 7.4, where NINE long kelp blades sprout every 40 degrees.  "
         "They leave the crown almost flat (pitch ~10) and then fall hard (droop ~3.05 "
         "over a 3.4 blade), so every tip ends around z 4.7 - 5.4, well under its root at "
         "z ~7.5: they HANG like kelp rather than sticking out like a palm.  Six are "
         "sea_kelp, the three back-facing ones sea_kelp_dk so the crown has depth.  The "
         "stipe keeps climbing through that "
         "crown, swaying slightly to screen-left, to a rounded head at z 11.2 with a "
         "small top tuft of five short blades and three dark float bladders under it.  "
         "sea_stalk_dk speckles up the stipe.  Nothing sits below z = 0; centred on "
         "x = 0, y = 0.  Five parts: Base, Stalk, StalkStuds, Fronds, FrondsDark.")

# ---- the stalk -----------------------------------------------------------
BASE_H = 1.70                       # stepped_base(top_w=1.6, h=1.7, steps=3, grow=1.3)
TRUNK_Z0, TRUNK_Z1 = 1.70, 7.40     # the briefed trunk: blocky, teal, up to z ~ 7.4
TRUNK_W0, TRUNK_W1 = 1.55, 0.95
TRUNK_BLOCKS = 4

# the stipe carries on above the crown, leaning gently: (cx, cy, width, z0, z1)
STIPE = [
    (0.00, 0.00, 0.86, 7.40, 8.52),
    (0.10, -0.05, 0.68, 8.50, 9.62),
    (0.22, -0.11, 0.50, 9.60, 10.72),
]
HEAD = (0.24, -0.12, 10.80)         # the rounded head knob on top of the stipe
HEAD_R = 0.40

CROWN_Z = 7.52                      # the nine main blades sprout here
CROWN_N = 9
CROWN_STEP = 40.0                   # ... one every 40 degrees
CROWN_PHASE = 10.0
CROWN_DARK = (5, 6, 7)              # yaw 210/250/290 - the blades facing away from camera
CROWN_ROOT = 0.20                   # how far off the axis each blade roots

TUFT_Z = 10.66                      # the little top tuft on the head
TUFT_N = 5
TUFT_DARK = (2, 4)


def _trunk_block(i):
    """The (lo, hi) box blocky_trunk builds for block `i` - so the speckles land on it."""
    sh = (TRUNK_Z1 - TRUNK_Z0) / float(TRUNK_BLOCKS)
    t = (i + 0.5) / float(TRUNK_BLOCKS)
    w = TRUNK_W0 + (TRUNK_W1 - TRUNK_W0) * t
    z0 = TRUNK_Z0 + i * sh
    return (-w / 2.0, -w / 2.0, z0), (w / 2.0, w / 2.0, z0 + sh + 0.014)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    rng = random.Random(24)

    # ---- holdfast plinth ---------------------------------------------------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=1.6, h=BASE_H, steps=3, grow=1.3, bevel=0.09)
    D.new_obj("Base", bm, c, D.C("sea_stalk_dk"), rbx_material="Rock")

    # ---- stipe -------------------------------------------------------------
    bm = bmesh.new()
    D.blocky_trunk(bm, TRUNK_Z0, TRUNK_Z1, TRUNK_W0, TRUNK_W1, blocks=TRUNK_BLOCKS,
                   bevel=0.08)
    for (cx, cy, w, z0, z1) in STIPE:
        D.beveled_box(bm, (cx - w / 2.0, cy - w / 2.0, z0),
                      (cx + w / 2.0, cy + w / 2.0, z1), bevel=0.07)
    D.uvsphere(bm, HEAD, HEAD_R, segs=8, rings=5)
    D.new_obj("Stalk", bm, c, D.C("sea_stalk"), rbx_material="Grass")

    # ---- speckles up the stipe ---------------------------------------------
    bm = bmesh.new()
    for i in range(TRUNK_BLOCKS):
        lo, hi = _trunk_block(i)
        D.box_studs(bm, lo, hi, faces=("+y", "+x", "-x"), per_face=1, size=0.30,
                    rise=0.06, seed=31 + i, margin=0.32)
    for j, (cx, cy, w, z0, z1) in enumerate(STIPE):
        D.box_studs(bm, (cx - w / 2.0, cy - w / 2.0, z0),
                    (cx + w / 2.0, cy + w / 2.0, z1), faces=("+y", "+x"), per_face=1,
                    size=0.24, rise=0.05, seed=51 + j, margin=0.30)
    D.new_obj("StalkStuds", bm, c, D.C("sea_stalk_dk"), rbx_material="Grass")

    # ---- the crown of kelp blades ------------------------------------------
    bm = bmesh.new()            # sea_kelp
    bmd = bmesh.new()           # sea_kelp_dk - the back blades and the float bladders

    for i in range(CROWN_N):
        yaw = CROWN_PHASE + CROWN_STEP * i
        a = math.radians(yaw)
        base = (math.cos(a) * CROWN_ROOT, math.sin(a) * CROWN_ROOT,
                CROWN_Z + rng.uniform(-0.10, 0.12))
        D.palm_frond(bmd if i in CROWN_DARK else bm, base=base, yaw_deg=yaw,
                     pitch_deg=10.0 + rng.uniform(-2.0, 2.0),
                     length=3.4 * rng.uniform(0.93, 1.00), width=0.70, thick=0.11,
                     droop=3.05 * rng.uniform(0.94, 1.06), n=6, teeth=0.18)

    for i in range(TUFT_N):
        yaw = 34.0 + (360.0 / TUFT_N) * i
        a = math.radians(yaw)
        base = (HEAD[0] + math.cos(a) * 0.18, HEAD[1] + math.sin(a) * 0.18,
                TUFT_Z + rng.uniform(-0.05, 0.05))
        D.palm_frond(bmd if i in TUFT_DARK else bm, base=base, yaw_deg=yaw,
                     pitch_deg=34.0, length=1.70 * rng.uniform(0.90, 1.10), width=0.46,
                     thick=0.09, droop=1.20, n=5, teeth=0.12)

    for i in range(3):
        a = math.radians(50.0 + 120.0 * i)
        D.uvsphere(bmd, (HEAD[0] + math.cos(a) * 0.42, HEAD[1] + math.sin(a) * 0.42,
                         10.44), 0.22, segs=6, rings=4)

    D.new_obj("Fronds", bm, c, D.C("sea_kelp"), rbx_material="LeafyGrass")
    D.new_obj("FrondsDark", bmd, c, D.C("sea_kelp_dk"), rbx_material="LeafyGrass")
    return c
