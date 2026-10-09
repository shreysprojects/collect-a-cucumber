"""Spawn biome guardian 1/10: STRAWMAN, the hay scarecrow that climbs down off its pole.

Reference sheet: burlap sack head with glowing orange X button eyes and a stitched X
mouth, a dented straw hat with a red band, a torn red shirt, blue denim overalls with a
tan patch, stick-thin wooden arms and legs with straw bursting at the neck, wrists and
ankles, blocky brown boots, and a wooden cross pole carried like a staff with a red
ribbon knotted to it.  It sits slumped on a hay bale.
"""
import bmesh, math

COLLECTION = "Strawman"
GUARDIAN = "Strawman"
SEAT = "Strawman_Seat"
EXTRA = "Strawman_Extra"

NOTES = (
    "7.15 studs to the top of the hat (the staff carries on to 7.7), 4.6 across the "
    "outstretched arms and 3.0 x 2.2 through the body, which is what the Hitbox covers. "
    "Faces +Y.  Humanoid rig: Root at hip height carries Hips, Hips carries Torso and "
    "both legs, Torso carries the head, the straw ruff and both arms, and the cross pole "
    "hangs off the right forearm so a Wake animation can plant it.  The character's "
    "RIGHT is +X, which is screen-LEFT in a render.  Eyes are one Neon X each (not a "
    "dot) so the wake tell reads at 100 studs; SLEEP_LOOK darkens them to 5e4322.  The "
    "seat is a bound hay bale with a broken rail behind it; the extra collection is one "
    "crow, which the runtime clones and flings off the hat when it wakes."
)

# ---------------------------------------------------------------- the skeleton
HIP_Z = 3.30
SHOULDER_Z = 4.80
SHOULDER_X = 0.78
ELBOW = (1.52, 0.06, 4.70)
WRIST = (2.18, 0.12, 4.58)
HIP_X = 0.46
KNEE_Z = 1.88
ANKLE_Z = 0.50
HEAD_PIVOT = (0.0, 0.0, 5.32)
HEAD_C = (0.0, 0.0, 6.03)
HEAD_R = (0.84, 0.78, 0.76)
HAT_Z = 6.52
EYE = (0.37, 0.70, 6.14)
MOUTH = (0.0, 0.70, 5.66)

# the staff leans out past the hat brim, gripped where the right hand closes on it
GRIP = (2.18, 0.30, 4.58)
POLE_DIR = (0.092, -0.052, 1.0)
POLE_BASE = tuple(GRIP[i] - POLE_DIR[i] * 4.53 for i in range(3))
POLE_TOP = tuple(GRIP[i] + POLE_DIR[i] * 3.12 for i in range(3))
POLE_CROSS_Z = 6.58
POLE_CROSS_W = 1.36


def _pole_at(z):
    t = (z - GRIP[2]) / POLE_DIR[2]
    return (GRIP[0] + POLE_DIR[0] * t, GRIP[1] + POLE_DIR[1] * t, z)


# ---------------------------------------------------------------- the two states
# Axis reminder (see GUARDIAN-BUILD.md): a limb pointing DOWN swings forward on +rx, but a
# piece standing UP above its pivot (torso, head, hat) tips BACK on +rx and slumps on -rx.
# An arm held out along +X drops on +ry and swings forward on +rz; the -X arm mirrors both.
POSES = {
    # slumped on the hay bale: thighs along the bale, shins hanging off the front edge,
    # back rounded, chin on its chest, arms dangling and the staff hanging from one hand
    "Sit": {
        "Hips": (8, 0, 0), "Torso": (-30, 0, 0), "Head": (-18, 0, 0), "Hat": (-7, 0, 0),
        "LegUpper_R": (58, 0, -9), "LegUpper_L": (58, 0, 9),
        "LegLower_R": (-66, 0, 0), "LegLower_L": (-66, 0, 0),
        "ArmUpper_R": (0, 74, 12), "ArmUpper_L": (0, -74, -12),
        "ArmLower_R": (0, 18, 8), "ArmLower_L": (0, -18, -8),
        "Staff": (0, -74, 0),          # counter the dropped arm so the pole stays upright
    },
    # up on its feet, shoulders back, head raised, the staff swung up and planted
    "Awake": {
        "Torso": (6, 0, 0), "Head": (4, 0, 0),
        "ArmUpper_R": (0, -34, 14), "ArmUpper_L": (0, 22, -10),
        "ArmLower_R": (0, -12, 6), "ArmLower_L": (0, 16, -8),
        "LegUpper_R": (9, 0, -4), "LegUpper_L": (-7, 0, 4),
        "LegLower_R": (-5, 0, 0), "LegLower_L": (6, 0, 0),
        "Staff": (0, 44, -8),          # ... and here, so it is planted, not across its face
    },
    # mid-stride, the clumsy run the brief asks for
    "Run": {
        "Torso": (-14, 0, 0), "Head": (9, 0, 0),
        "LegUpper_R": (38, 0, -3), "LegLower_R": (-34, 0, 0),
        "LegUpper_L": (-26, 0, 3), "LegLower_L": (-16, 0, 0),
        "ArmUpper_R": (0, 26, 34), "ArmUpper_L": (0, -30, 26),
        "ArmLower_R": (0, 10, 14), "ArmLower_L": (0, -14, 10),
    },
}
POSE_LOC = {"Sit": {"Root": (0.0, 0.30, -1.02)}}   # down onto the 1.52-tall bale


def build(G):
    _guardian(G)
    _seat(G)
    _crow(G)
    return G.coll(COLLECTION)


# ================================================================= the guardian
def _guardian(G):
    c = G.begin(COLLECTION, GUARDIAN)

    G.root_part(c, (-0.55, -0.42, HIP_Z - 0.55), (0.55, 0.42, HIP_Z + 0.55))
    G.hitbox(c, (-1.50, -1.10, 0.0), (1.50, 1.10, 7.20), pivot=(0, 0, HIP_Z), parent="Root")

    _hips(G, c)
    _torso(G, c)
    _head(G, c)
    _hat(G, c)
    _face(G, c)
    for side in (+1, -1):
        _arm(G, c, side)
        _leg(G, c, side)
    _staff(G, c)


def _hips(G, c):
    """Baggy denim overalls from the belt down to the top of the thighs."""
    bm = bmesh.new()
    G.beveled_box(bm, (-0.76, -0.50, 2.84), (0.76, 0.50, 3.92), bevel=0.18)
    G.beveled_box(bm, (-0.70, -0.46, 2.56), (-0.08, 0.46, 2.92), bevel=0.10)
    G.beveled_box(bm, (0.08, -0.46, 2.56), (0.70, 0.46, 2.92), bevel=0.10)
    G.part("Hips", bm, c, "Denim", (0.0, 0.0, HIP_Z), parent="Root")

    bm = bmesh.new()                                    # the straw rope round the waist
    G.torus(bm, (0.0, 0.0, 3.78), 0.80, 0.13, rot=None, seg_major=12, seg_minor=5)
    G.tuft(bm, (0.14, 0.56, 3.72), direction=(0.2, 0.7, -0.68), n=5, length=0.62,
           width=0.10, spread_deg=46, seed=3)
    G.part("Belt", bm, c, "Straw", (0.0, 0.0, 3.78), parent="Hips")

    bm = bmesh.new()                                    # the tan patch on the +x thigh
    G.patch(bm, (0.77, 0.16, 3.16), normal=(1, 0.1, 0), radius=0.34, height=0.05, seed=4,
            jitter=0.10, segs=4)
    G.part("Patch", bm, c, "Burlap", (0.77, 0.16, 3.16), parent="Hips")


def _torso(G, c):
    """The torn red shirt, its collar, and the denim straps over it."""
    bm = bmesh.new()
    G.beveled_box(bm, (-0.76, -0.50, 3.86), (0.76, 0.50, 4.98), bevel=0.18)
    G.beveled_box(bm, (-0.50, -0.40, 4.92), (0.50, 0.40, 5.22), bevel=0.10)     # collar
    for x in (-0.54, -0.18, 0.18, 0.54):                                        # torn hem
        G.spike_shard(bm, (x, 0.0, 3.98), (x + 0.05, 0.0, 3.50), 0.34, thick=1.02)
    for i, x in enumerate((-0.80, 0.80)):                                       # rag sleeves
        G.blob(bm, (x, 0.0, 4.74), (0.30, 0.46, 0.30), seed=11 + i, jitter=0.20)
    G.part("Torso", bm, c, "Shirt", (0.0, 0.0, 3.92), parent="Hips")

    bm = bmesh.new()                                    # the overalls bib and its straps
    G.beveled_box(bm, (-0.46, 0.44, 3.86), (0.46, 0.54, 4.60), bevel=0.06)
    for s in (+1, -1):
        G.plank(bm, (s * 0.36, 0.50, 4.52), (s * 0.40, 0.44, 4.92), w=0.24, t=0.11,
                bevel=0.03)
        G.plank(bm, (s * 0.40, 0.44, 4.92), (s * 0.36, -0.44, 4.94), w=0.24, t=0.11,
                bevel=0.03)                              # over the shoulder
        G.plank(bm, (s * 0.36, -0.44, 4.90), (s * 0.34, -0.50, 3.90), w=0.24, t=0.11,
                bevel=0.03)
        G.hex_prism(bm, (s * 0.34, 0.56, 4.44), 0.11, 0.08, axis=(0, 1, 0), sides=6)
    G.part("Straps", bm, c, "Denim", (0.0, 0.0, 4.20), parent="Torso")

    bm = bmesh.new()                                    # straw bursting out of the collar
    for a in range(9):
        ang = math.radians(360.0 * a / 9.0)
        G.tuft(bm, (math.cos(ang) * 0.42, math.sin(ang) * 0.34, 5.14),
               direction=(math.cos(ang) * 0.85, math.sin(ang) * 0.85, 0.42),
               n=5, length=0.66, width=0.095, spread_deg=38, seed=20 + a, vary=0.4)
    G.part("Ruff", bm, c, "Straw", (0.0, 0.0, 5.10), parent="Torso")


def _head(G, c):
    bm = bmesh.new()
    G.blob(bm, HEAD_C, HEAD_R, seed=7, jitter=0.08, subdiv=1)
    G.cyl(bm, (0.0, 0.0, 5.18), (0.0, 0.0, 5.66), 0.34, segs=8, r2=0.52)     # gathered neck
    G.part("Head", bm, c, "Burlap", HEAD_PIVOT, parent="Torso")

    bm = bmesh.new()                                    # the seam stitching up the sack
    for i in range(5):
        z = 5.52 + 0.28 * i
        y = 0.40 + 0.22 * math.sin(0.9 * i)
        G.box(bm, (-0.035, y, z), (0.035, y + 0.20, z + 0.09))
    G.part("Seam", bm, c, "BurlapDark", (0.0, 0.50, 6.00), parent="Head")


def _hat(G, c):
    """A dented straw hat: wide notched brim, low crown, red band."""
    bm = bmesh.new()
    G.lathe(bm, [(0.0, 0.0), (1.26, 0.07), (1.20, 0.20), (0.62, 0.15), (0.66, 0.21),
                 (0.60, 0.46), (0.40, 0.58), (0.0, 0.62)], segs=10,
            matrix=G.place((0.0, 0.0, HAT_Z)))
    for i in range(7):                                  # ragged straw off the brim edge
        a = math.radians(24 + 52 * i)
        p = (math.cos(a) * 1.21, math.sin(a) * 1.21, HAT_Z + 0.12)
        G.spike_shard(bm, p, (p[0] * 1.20, p[1] * 1.20, p[2] - 0.14), 0.24, thick=0.08)
    G.part("Hat", bm, c, "Burlap", (0.0, 0.0, HAT_Z), parent="Head")

    bm = bmesh.new()
    G.lathe(bm, [(0.63, 0.0), (0.70, 0.0), (0.70, 0.19), (0.63, 0.19)], segs=10,
            matrix=G.place((0.0, 0.0, HAT_Z + 0.19)))
    G.part("HatBand", bm, c, "Shirt", (0.0, 0.0, HAT_Z + 0.19), parent="Hat")

    bm = bmesh.new()                                    # hair of straw under the brim
    for a in range(9):
        ang = math.radians(360.0 * a / 9.0 + 20)
        if abs(math.sin(ang)) > 0.72 and math.sin(ang) > 0:
            continue                                    # keep the face clear
        G.tuft(bm, (math.cos(ang) * 0.74, math.sin(ang) * 0.68, HAT_Z - 0.04),
               direction=(math.cos(ang) * 0.72, math.sin(ang) * 0.72, -0.66),
               n=5, length=0.70, width=0.09, spread_deg=32, seed=40 + a, vary=0.45)
    G.part("Fringe", bm, c, "Straw", (0.0, 0.0, HAT_Z - 0.04), parent="Head")


def _face(G, c):
    """Two dark buttons, an orange X burning in each, and a stitched X for a mouth."""
    bm = bmesh.new()
    for s in (+1, -1):
        G.hex_prism(bm, (s * EYE[0], EYE[1], EYE[2]), 0.28, 0.10, axis=(s * 0.35, 1, 0.10),
                    sides=8)
    G.part("Buttons", bm, c, "Stitch", (0.0, EYE[1], EYE[2]), parent="Head")

    for s, tag in ((+1, "R"), (-1, "L")):
        bm = bmesh.new()
        G.cross_glyph(bm, (s * EYE[0] + s * 0.03, EYE[1] + 0.08, EYE[2]),
                      normal=(s * 0.35, 1, 0.10), arm=0.20, thick=0.085, depth=0.08,
                      spin_deg=45)
        G.part("Eye_" + tag, bm, c, "EyeGlow", (s * EYE[0], EYE[1] + 0.08, EYE[2]),
               parent="Head")

    bm = bmesh.new()
    G.cross_glyph(bm, MOUTH, normal=(0, 1, -0.14), arm=0.17, thick=0.075, depth=0.07,
                  spin_deg=45)
    G.part("Mouth", bm, c, "Stitch", MOUTH, parent="Head")


def _arm(G, c, s):
    """Stick-thin wooden arms held out wide, straw bursting at the wrist."""
    tag = "R" if s > 0 else "L"
    sh = (s * SHOULDER_X, 0.0, SHOULDER_Z)
    el = (s * ELBOW[0], ELBOW[1], ELBOW[2])
    wr = (s * WRIST[0], WRIST[1], WRIST[2])

    bm = bmesh.new()
    G.limb(bm, sh, el, 0.25, 0.21, segs=6, bow=(0, 0.04, 0.04))
    G.hex_prism(bm, sh, 0.29, 0.20, axis=(1, 0, 0), sides=6)             # shoulder peg
    G.part("ArmUpper_" + tag, bm, c, "Pole", sh, parent="Torso")

    bm = bmesh.new()
    G.limb(bm, el, wr, 0.21, 0.17, segs=6, bow=(0, 0.03, -0.03))
    G.plank(bm, (el[0] + s * 0.12, el[1] - 0.02, el[2] - 0.03),
            (el[0] + s * 0.40, el[1] - 0.02, el[2] - 0.07), w=0.14, t=0.14, bevel=0.02)
    G.part("ArmLower_" + tag, bm, c, "Pole", el, parent="ArmUpper_" + tag)

    bm = bmesh.new()
    for a in range(6):
        ang = math.radians(360.0 * a / 6.0)
        G.tuft(bm, (wr[0] - s * 0.08, wr[1] + math.sin(ang) * 0.12,
                    wr[2] + math.cos(ang) * 0.12),
               direction=(s * 0.80, math.sin(ang) * 0.52, math.cos(ang) * 0.52),
               n=5, length=0.68, width=0.095, spread_deg=32,
               seed=60 + a + 6 * (s > 0), vary=0.45)
    G.part("Cuff_" + tag, bm, c, "Straw", wr, parent="ArmLower_" + tag)


def _leg(G, c, s):
    tag = "R" if s > 0 else "L"
    hip = (s * HIP_X, 0.0, 2.90)
    knee = (s * (HIP_X + 0.04), 0.02, KNEE_Z)
    ankle = (s * (HIP_X + 0.06), 0.04, ANKLE_Z)

    bm = bmesh.new()
    G.limb(bm, hip, knee, 0.34, 0.29, segs=6)
    G.beveled_box(bm, (min(hip[0], knee[0]) - 0.36, -0.36, KNEE_Z - 0.12),
                  (max(hip[0], knee[0]) + 0.36, 0.36, 2.94), bevel=0.14)   # baggy trouser
    G.part("LegUpper_" + tag, bm, c, "Denim", hip, parent="Hips")

    bm = bmesh.new()
    G.limb(bm, knee, ankle, 0.26, 0.21, segs=6)
    G.beveled_box(bm, (min(knee[0], ankle[0]) - 0.30, -0.30, ANKLE_Z + 0.30),
                  (max(knee[0], ankle[0]) + 0.30, 0.30, KNEE_Z + 0.08), bevel=0.12)
    G.part("LegLower_" + tag, bm, c, "Denim", knee, parent="LegUpper_" + tag)

    bm = bmesh.new()
    for a in range(5):
        ang = math.radians(360.0 * a / 5.0 + 36)
        G.tuft(bm, (ankle[0] + math.cos(ang) * 0.18, ankle[1] + math.sin(ang) * 0.18,
                    ankle[2] + 0.26),
               direction=(math.cos(ang) * 0.62, math.sin(ang) * 0.62, -0.72),
               n=4, length=0.52, width=0.085, spread_deg=34, seed=80 + a + 5 * (s > 0))
    G.part("Ankle_" + tag, bm, c, "Straw", (ankle[0], ankle[1], ankle[2] + 0.26),
           parent="LegLower_" + tag)

    bm = bmesh.new()
    G.beveled_box(bm, (ankle[0] - 0.34, -0.38, 0.10), (ankle[0] + 0.34, 0.58, 0.48),
                  bevel=0.12)
    G.beveled_box(bm, (ankle[0] - 0.38, -0.44, 0.0), (ankle[0] + 0.38, 0.64, 0.14),
                  bevel=0.05)                            # the sole, proud of the upper
    G.part("Boot_" + tag, bm, c, "Boot", (ankle[0], 0.04, ANKLE_Z - 0.16),
           parent="LegLower_" + tag)


def _staff(G, c):
    """The cross pole it used to hang from, now carried like a staff."""
    bm = bmesh.new()
    G.plank(bm, POLE_BASE, POLE_TOP, w=0.22, t=0.22, bevel=0.03)
    cx = _pole_at(POLE_CROSS_Z)
    G.plank(bm, (cx[0] - POLE_CROSS_W / 2, cx[1] - 0.04, POLE_CROSS_Z - 0.04),
            (cx[0] + POLE_CROSS_W / 2, cx[1] + 0.04, POLE_CROSS_Z + 0.04),
            w=0.18, t=0.18, bevel=0.03)
    for z in (POLE_CROSS_Z - 0.66, POLE_CROSS_Z + 0.52):     # cord bindings
        G.torus(bm, _pole_at(z), 0.19, 0.055, rot=G.aim(POLE_DIR), seg_major=8, seg_minor=4)
    G.part("Staff", bm, c, "Pole", GRIP, parent="ArmLower_R")

    bm = bmesh.new()                                         # the red ribbon
    knot = (cx[0] - POLE_CROSS_W / 2 + 0.18, cx[1], POLE_CROSS_Z)
    G.torus(bm, knot, 0.17, 0.065, rot=G.aim((1, 0, 0)), seg_major=8, seg_minor=4)
    G.tassel(bm, (knot[0], knot[1], knot[2] - 0.12), length=0.96, n=3, width=0.11,
             spread=0.14, seed=5)
    G.part("Ribbon", bm, c, "Shirt", knot, parent="Staff")


# ================================================================= the hay bale
def _seat(G):
    """A bound hay bale with a broken rail behind it - what it sits on, asleep."""
    c = G.begin(SEAT, GUARDIAN, prefix="StrawmanSeat")

    bm = bmesh.new()
    G.beveled_box(bm, (-1.40, -1.00, 0.0), (1.40, 1.00, 1.52), bevel=0.24)
    for i in range(16):                                  # loose straw all over it
        a = math.radians(22.5 * i)
        G.tuft(bm, (math.cos(a) * 1.28, math.sin(a) * 0.92, 0.26 + 0.10 * (i % 9)),
               direction=(math.cos(a), math.sin(a), 0.22), n=3, length=0.38, width=0.08,
               spread_deg=40, seed=100 + i, vary=0.5)
    G.part("Bale", bm, c, "Straw", (0.0, 0.0, 0.0), parent=None)

    bm = bmesh.new()
    for x in (-0.58, 0.58):                              # the two binding cords
        G.box(bm, (x - 0.08, -1.04, 0.02), (x + 0.08, 1.04, 1.54))
    G.part("Cords", bm, c, "StrawDark", (0.0, 0.0, 0.76), parent="Bale")

    bm = bmesh.new()                                     # the broken rail behind it
    for x in (-1.82, 1.74):
        G.plank(bm, (x, -1.40, 0.0), (x + 0.06, -1.36, 2.02), w=0.26, t=0.26, bevel=0.03)
    G.plank(bm, (-1.96, -1.38, 1.58), (1.50, -1.36, 1.50), w=0.22, t=0.17, bevel=0.03)
    G.plank(bm, (-1.90, -1.38, 0.92), (0.46, -1.36, 0.84), w=0.20, t=0.15, bevel=0.03)
    G.part("Rail", bm, c, "Pole", (0.0, -1.38, 0.0), parent="Bale")

    bm = bmesh.new()                                     # a few blades at its foot
    for i in range(8):
        a = math.radians(45 * i)
        G.tuft(bm, (math.cos(a) * 1.8, math.sin(a) * 1.4, 0.04), direction=(0, 0, 1), n=3,
               length=0.46, width=0.07, spread_deg=26, seed=130 + i)
    G.part("Grass", bm, c, "StrawDark", (0.0, 0.0, 0.0), parent="Bale")
    return c


# ================================================================= the crow
def _crow(G):
    """One crow.  The runtime clones six of these and flings them off the hat on Wake."""
    c = G.begin(EXTRA, GUARDIAN, prefix="StrawmanCrow")

    bm = bmesh.new()
    G.blob(bm, (0.0, 0.0, 0.0), (0.22, 0.40, 0.20), seed=3, jitter=0.12)
    G.blob(bm, (0.0, 0.42, 0.10), (0.15, 0.17, 0.15), seed=4, jitter=0.10)      # head
    G.spike_shard(bm, (0.0, 0.54, 0.08), (0.0, 0.80, 0.04), 0.10, thick=0.09)   # beak
    for s in (+1, -1):                                                          # wings
        G.plate(bm, [(-0.05, -0.20), (0.92, -0.06), (0.74, 0.10), (-0.05, 0.16)], 0.06,
                at=(s * 0.16, 0.0, 0.06), normal=(0, 0, 1), spin_deg=90 if s > 0 else -90)
    G.plate(bm, [(-0.10, 0.0), (0.10, 0.0), (0.06, -0.52), (-0.06, -0.52)], 0.06,
            at=(0.0, -0.30, 0.02), normal=(0, 0, 1))
    G.part("Crow", bm, c, "Crow", (0.0, 0.0, 0.0), parent=None)

    bm = bmesh.new()
    G.hex_prism(bm, (0.10, 0.48, 0.14), 0.05, 0.05, axis=(0.4, 1, 0.2), sides=6)
    G.hex_prism(bm, (-0.10, 0.48, 0.14), 0.05, 0.05, axis=(-0.4, 1, 0.2), sides=6)
    G.part("CrowEye", bm, c, "EyeGlow", (0.0, 0.48, 0.14), parent="Crow")
    return c
