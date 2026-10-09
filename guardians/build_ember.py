"""Volcano biome guardian 7/10: EMBER, the magma golem that stands up out of its own
rock pile.

Reference sheet: a HANDFUL OF HUGE basalt masses standing upright, held together by
nothing but light.  Each mass floats a little clear of its neighbours and a wide network
of lava seams fills the gaps between them, so the whole figure looks cracked open and lit
from inside, with a hotter ember core burning in the slot at the top of a dense, heavy
chest.  The head is a single boulder with two glowing hexagonal eye pits and a zigzag
crack for a mouth, set down in between the shoulders.  Two enormous shoulder boulders sit
high and wide and are the biggest single pieces on the model; each arm is one boulder
upper, one boulder forearm and one massive block of a fist, and the right fist carries a
loose throwing rock with a seam of its own.  Each leg is one boulder thigh, one boulder
shin and one flat slab of a foot.  A few loose chips drift free around the body.  It
sleeps as a heap of dead grey basalt with ash blown into the cracks and no glow at all.
"""
import bmesh, math

COLLECTION = "Ember"
GUARDIAN = "Ember"
SEAT = "Ember_Seat"

NOTES = (
    "11.05 studs to the crown of the head boulder (the basalt column on top carries on to "
    "11.1), 7.4 across the two shoulder boulders and 5.6 x 5.3 through the body, which is "
    "what the Hitbox covers - the shoulders and the hanging arms deliberately overhang it, "
    "the same way Strawman's arms overhang its; the pile it sleeps on is 5.3 x 4.8 x 2.6. "
    "3 788 tris for the guardian, 730 for the pile.  Faces +Y, and the "
    "character's RIGHT is +X, which is screen-LEFT in a render.  Ember is built from A FEW "
    "ENORMOUS MASSES, never a chain of pebbles: ONE boulder per limb segment (one upper "
    "arm, one forearm, one massive block of a fist, one thigh, one shin, one slab foot), "
    "ONE boulder per shoulder at r 1.26 - 2.52 x 2.42 x 2.17, bigger than the head at 1.78 "
    "and bigger than the back plate of the chest at 2.24, so the shoulders are the biggest "
    "single masses on the model - and FIVE big interpenetrating lumps in the core so the "
    "torso reads as dense rock rather than a cage.  31 boulders in all at a median radius "
    "of 0.84, where the first pass had 58 at 0.44 and the limbs read as beaded necklaces. "
    "Between those masses every joint carries a LIT GAP of 0.2-0.5 studs, and the light in "
    "it is a SEAM, not a bead: _gap_seam lays a four-point Lava run right across the mouth "
    "of the gap, bulged forward in +Y so it wraps the front of the limb, puts the same line "
    "round the back, and at the waist sends branches climbing out of both ends into the hip "
    "crevice.  The chest carries a 2.9-stud band of light from flank to flank in the gap "
    "between the low front plate and the deck, branching down to the waist on both sides "
    "and up into the neck, and a long diagonal crack runs from the chest out to each "
    "floating shoulder.  If a gap looks closed in the render, the boulder either side of it "
    "needs moving, not the seam.  Rig: Root at the "
    "hip cluster carries Hips; Hips carries the chest (Core) and both legs; Core carries "
    "the head, both shoulder boulders and the loose Chips.  Every seam part hangs off the "
    "piece it must travel with - SeamLeg off the thigh, SeamAnkle off the shin, SeamArm "
    "off the upper arm, SeamFist off the forearm, CoreSeams off the chest - so the glow "
    "follows the limb instead of being left behind by it.  CoreHeart is the hotter "
    "EmberGlow lump caged inside the chest mass: it shows through the one slot the five "
    "lumps leave, between the top of the low front plate (8.39) and the deck, right under "
    "the chin, with the chest band of Lava burning across the front of it.  The head sits "
    "DOWN IN the shoulders - crown 10.85 against their 10.56, a 0.21 neck gap - so it no "
    "longer reads as a rock parked in the air above them.  The eyes are hexagonal PITS - a "
    "hollow six-sided BasaltLight rim standing "
    "0.12 proud of the boulder with the EmberGlow hex sunk 0.05 inside it, under a heavy "
    "brow - and the mouth is a Lava zigzag crack. "
    "ThrowRock is a loose seamed boulder parented to the right fist so a throw can let go "
    "of it.  Poses: Sit drops the Root 3.1 studs into the saddle of the pile and uses "
    "POSE_LOC on Core, Head, the Chips and both shoulders as well, because asleep this "
    "guardian does not slump - it COLLAPSES INTO ITSELF and becomes one more heap of rock "
    "(about 6.1 studs tall against a SPEC of 5.0: a 5.0-stud leg and a 6.2-stud arm "
    "cannot fold onto a 2.6 pile and go lower without something ending up underground, so "
    "the legs fold away inside the heap, the forearms come up over the knees and the "
    "chips have fallen and lie round the base).  In the pose signs used here - checked "
    "against the Strawman_Sit render, where Torso +28 leans BACK - a positive rx swings a "
    "hanging limb FORWARD and tips an upright part BACKWARD, which is why the sleep fold "
    "is Core -26 and the thighs +86, and why Awake raises the rock with a POSITIVE upper "
    "arm and a deep positive elbow rather than a negative one."
)

# ---------------------------------------------------------------- the skeleton
# Every JOINT below sits in the GAP between two boulders, never inside either of them -
# that hole is where the lava seam lives and where the limb has to be free to turn.
FOOT_C     = (1.06,  0.30,  0.55)    # the flat slab foot, +X = the character's right
ANKLE      = (1.06,  0.12,  1.15)
SHIN_C     = (1.07,  0.04,  2.16)
KNEE       = (1.07,  0.06,  3.14)
THIGH_C    = (1.06,  0.02,  4.10)
HIP        = (1.06,  0.00,  5.04)
HIPS_C     = (0.00, -0.12,  5.88)    # the hip cluster; Root sits in the middle of it
ROOT_Z     = 5.88
WAIST      = (0.00, -0.02,  6.78)    # hips / chest gap - the widest seam on the body
CORE_Z     = 8.00
HEART_C    = (0.00,  0.62,  8.72)    # the ember, burning in the slot at the top of the chest
NECK       = (0.00,  0.00,  9.15)
HEAD_C     = (0.00,  0.06, 10.05)
HEAD_R     = 0.84
EYE        = (0.36,  0.74, 10.23)
MOUTH_Z    = 9.61
SHOULDER_C = (2.02, -0.08,  9.20)    # ONE enormous boulder - the biggest mass on the model
SHOULDER_J = (1.34,  0.08,  8.52)    # where it hangs off the chest, in the gap
ARM_J      = (2.26,  0.14,  8.16)    # shoulder joint, in the gap under the boulder
ELBOW      = (2.24,  0.26,  5.84)
WRIST      = (2.22,  0.46,  3.88)
FIST_C     = (2.18,  0.56,  2.88)
GRIP       = (2.26,  1.26,  3.08)    # where the right fist closes on the loose rock
ROCK_C     = (2.32,  1.72,  3.20)

# the chest: FIVE big overlapping masses, not a cage of pebbles.  They interpenetrate on
# purpose - the core has to read as dense rock with light leaking out of it, so the only
# hole left is the slot at the TOP of the chest where the ember shows through.
# (x, y, z, r, subdiv)
CORE_SLOTS = (
    ( 0.00, -0.56, 7.92, 1.00, 1),   # the back plate, the biggest lump in the chest
    ( 0.72,  0.06, 7.74, 0.80, 1),   # right flank, overlapping the back plate
    (-0.72,  0.06, 7.74, 0.80, 1),   # left flank
    ( 0.00,  0.76, 7.62, 0.80, 1),   # the front plate sits LOW so the ember shows above
    ( 0.00, -0.06, 8.24, 0.84, 1),   # the deck the head sits down between the shoulders on
)
CORE_SCALE = (1.12, 0.92, 0.96)

# the pelvis block itself is HIPS_C, built wide and flat; these are the lumps on it
HIP_SLOTS = (
    ( 1.26,  0.02, 5.82, 0.60, 0),   # right hip knuckle
    (-1.26,  0.02, 5.82, 0.60, 0),   # left hip knuckle
)

CHIP_SLOTS = (                       # loose chips floating free around the body
    ( 2.35,  1.75,  9.20, 0.28),
    (-2.55, -1.95,  8.00, 0.30),
    ( 1.25, -2.20,  6.70, 0.26),
    (-1.70,  1.90,  7.20, 0.28),
    ( 1.10,  1.45, 10.80, 0.24),
    (-1.50, -0.25, 10.95, 0.26),
)

PILE_SLOTS = (                       # the seat: a dead heap 5.3 x 4.8 x 2.5
    ( 0.00, -0.45, 1.36, 1.34, 1),   # the block the whole heap is built on
    (-1.34,  0.30, 1.05, 1.02, 1),
    ( 1.34,  0.30, 1.05, 1.02, 1),
    ( 0.00,  1.30, 0.86, 0.86, 0),
    (-1.05, -1.40, 0.92, 0.92, 0),
    ( 1.05, -1.40, 0.92, 0.92, 0),
    (-1.85, -0.70, 0.66, 0.66, 0),
    ( 1.85, -0.70, 0.66, 0.66, 0),
    ( 0.00, -0.20, 1.98, 0.64, 0),   # the crown the sleeping hips settle into
    (-0.78,  0.72, 1.62, 0.56, 0),
    ( 0.78,  0.72, 1.62, 0.56, 0),
)
PILE_SCALE = (1.00, 1.00, 0.82)


# ---------------------------------------------------------------- the five states
# Sign convention, worked out on the rest pose and used everywhere below: +rx swings a
# HANGING limb forward (+Y) and tips an UPRIGHT part backward; +rz twists the body to
# its left; +ry on a hanging arm swings it in toward the ribs on the +X side.
POSES = {
    # asleep: the stack has collapsed into itself.  The thighs are folded forward flat
    # and the shins folded straight back under them, so both feet tuck away INSIDE the
    # heap (0.4 clear of the floor); the forearms come up over the knees and the fists
    # and the throwing rock rest on them.  Nothing in this pose reaches below z = 0 -
    # the arms are the tight constraint, since shoulder-to-knuckle is 5.6 studs and the
    # sleeping shoulder is only 3.5 up, which is why the elbows carry the fold.
    "Sit": {
        "Hips": (6, 0, 0),
        "Core": (-26, 0, 0), "Head": (-22, 0, 0),
        "Shoulder_R": (-14, 0, 0), "Shoulder_L": (-14, 0, 0),
        "ArmUpper_R": (42, -22, 0), "ArmUpper_L": (42, 22, 0),
        "ArmLower_R": (84, 0, 0), "ArmLower_L": (84, 0, 0),
        "Fist_R": (8, 0, 0), "Fist_L": (8, 0, 0),
        "ThrowRock": (-16, 0, 0),
        "LegUpper_R": (86, 0, -14), "LegUpper_L": (86, 0, 14),
        "LegLower_R": (-172, 0, 0), "LegLower_L": (-172, 0, 0),
        "Foot_R": (86, 0, 0), "Foot_L": (86, 0, 0),
    },
    # the sheet's hero pose: risen to full height, chest open, head up, shoulders rolled
    # out, the throwing rock carried HIGH - the right elbow comes up and out and the
    # forearm folds back over it, so the rock rides at z 7.6-10.3 beside the head instead
    # of trailing behind the back (a hanging arm swings FORWARD on +rx, so raising it in
    # front of the body is positive; negative takes it behind, which is the Throw).
    "Awake": {
        "Core": (4, 0, 0), "Head": (6, 0, 0),
        "Shoulder_R": (2, -8, 0), "Shoulder_L": (2, 8, 0),
        "ArmUpper_R": (40, -26, 0), "ArmUpper_L": (-8, 6, 0),
        "ArmLower_R": (100, 0, 0), "ArmLower_L": (18, 0, 0),
        "Fist_R": (-20, 0, 0), "Fist_L": (10, 0, 0),
        "ThrowRock": (0, 0, 0),
        "LegUpper_R": (-5, 0, -5), "LegUpper_L": (7, 0, 5),
        "LegLower_R": (5, 0, 0), "LegLower_L": (-7, 0, 0),
        "Foot_R": (2, 0, 0), "Foot_L": (-2, 0, 0),
    },
    # the slow relentless walk-run of SPEC: leaning in, one leg driving, arms swinging
    # like loose masonry - half a swing, not a sprinter's, or the fists end up further
    # behind the body than the body is deep.
    "Run": {
        "Core": (-16, 0, 0), "Head": (12, 0, 0),
        "Shoulder_R": (-4, -6, 0), "Shoulder_L": (-4, 6, 0),
        "LegUpper_R": (48, 0, -4), "LegLower_R": (-40, 0, 0), "Foot_R": (16, 0, 0),
        "LegUpper_L": (-30, 0, 4), "LegLower_L": (-16, 0, 0), "Foot_L": (-10, 0, 0),
        "ArmUpper_R": (-26, -8, 0), "ArmLower_R": (-14, 0, 0),
        "ArmUpper_L": (32, 8, 0), "ArmLower_L": (-22, 0, 0),
    },
    # the signature: hips and chest wound to the left, the right arm taken back and the
    # forearm folded UP off it so the rock is cocked behind the shoulder at head height,
    # the left arm thrown out at the target.
    "Throw": {
        "Hips": (0, 0, -12),
        "Core": (-6, 0, -24), "Head": (2, 0, 20),
        "Shoulder_R": (-10, -16, 0), "Shoulder_L": (6, 14, 0),
        "ArmUpper_R": (-92, -20, 0), "ArmLower_R": (150, 0, 0), "Fist_R": (-20, 0, 0),
        "ThrowRock": (-10, 0, 0),
        "ArmUpper_L": (48, 18, 0), "ArmLower_L": (-26, 0, 0),
        "LegUpper_R": (-20, 0, -6), "LegLower_R": (14, 0, 0),
        "LegUpper_L": (26, 0, 6), "LegLower_L": (-18, 0, 0),
    },
    # both fists coming down on the spot it last saw the player: chest folded over them,
    # arms swung through to the front and hanging low, knees taking the shock.
    "Slam": {
        "Core": (-34, 0, 0), "Head": (-16, 0, 0),
        "Shoulder_R": (-14, -8, 0), "Shoulder_L": (-14, 8, 0),
        "ArmUpper_R": (40, -6, 0), "ArmUpper_L": (40, 6, 0),
        "ArmLower_R": (18, 0, 0), "ArmLower_L": (18, 0, 0),
        "Fist_R": (16, 0, 0), "Fist_L": (16, 0, 0),
        "ThrowRock": (-14, 0, 0),
        "LegUpper_R": (28, 0, -10), "LegLower_R": (-32, 0, 0),
        "LegUpper_L": (28, 0, 10), "LegLower_L": (-32, 0, 0),
    },
}

# Asleep the whole stack sinks: the Root drops into the saddle of the pile and the chest,
# head and shoulders each settle further down INTO the piece below them.  That collapse
# is the sleep silhouette - a heap of rock, not a seated figure.  The Chips drop with it:
# awake they orbit the body, asleep they have fallen and lie around the heap.
POSE_LOC = {
    "Sit": {
        "Root": (0.00, -0.25, -3.10),
        "Core": (0.00, -0.12, -0.80),
        "Head": (0.00,  0.06, -1.05),
        "Chips": (0.00,  0.00, -2.30),
        "Shoulder_R": (-0.30, 0.0, -0.30),
        "Shoulder_L": (0.30, 0.0, -0.30),
    },
}


def build(G):
    _guardian(G)
    _seat(G)
    return G.coll(COLLECTION)


# ================================================================= shared helpers
def _m(s, p):
    """Mirror a point onto the side `s` (+1 = the character's right, +X)."""
    return (s * p[0], p[1], p[2])


def _boulders(G, bm, slots, seed=1, jitter=0.22, scale=(1.0, 1.0, 1.0)):
    """A table of (x, y, z, radius, subdiv) lumps in one mesh.  subdiv 0 is a 20-tri
    chunk of basalt, subdiv 1 an 80-tri boulder - the big masses only."""
    for i, (x, y, z, r, sd) in enumerate(slots):
        G.rock(bm, (x, y, z), r, seed=seed * 37 + i * 7 + 3, jitter=jitter,
               subdiv=sd, scale=scale)


def _seam_run(G, bm, pts, width, taper=0.24):
    """ONE CONTINUOUS BRANCH of light: seam_strips chained end to end along a polyline,
    fattest in the middle and tapering to the ends, so what the eye gets is a long crack
    with a hot centre.  Every glow on this model is built from runs - a seam that is one
    short strip at one point reads as a BEAD, and a string of beads is exactly what a
    boulder golem must not look like."""
    n = max(1, len(pts) - 1)
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        k = 1.0 - taper * abs(2.0 * (i + 0.5) / n - 1.0)
        G.seam_strip(bm, a, b, width=width * k, segs=4)


def _gap_seam(G, bm, c, half, width, depth=0.62, rise=0.10, back=0, branch=0.0):
    """Fill a JOINT GAP with a seam that FOLLOWS THE GAP LINE.  A four-point run crosses
    the whole mouth of the joint and bulges forward in +Y, so the light wraps the front of
    the limb instead of sitting in a dot at its centre; `back` puts the same line round the
    back (2 = the full run, 1 = one strip, 0 = none) and `branch` sends a crack climbing
    out of each END of the gap into the rock beside it, which is what makes the biggest
    seams look like a network rather than a hoop.

    `half` is HOW FAR THE JOINT REACHES OUT from its centre - pass the radius of the
    boulders the gap separates.

    It is scaled DOWN hard here on purpose.  A run that spanned the full width of every
    joint, front and back, drew a complete ring of light round each limb, and a column of
    rings reads as a stack of discs with bars between them - which is exactly what the
    sheet's golem must not look like.  The sheet has SHORT, irregular cracks where light
    leaks out of one spot, with dark rock either side of them."""
    half *= 0.58
    x, y, z = c
    _seam_run(G, bm, [(x - half, y - 0.26 * depth, z - rise),
                      (x - 0.42 * half, y + 0.88 * depth, z + rise),
                      (x + 0.42 * half, y + 0.88 * depth, z + rise * 0.55),
                      (x + half, y - 0.26 * depth, z - rise)], width)
    if back >= 2:
        _seam_run(G, bm, [(x - half, y + 0.20 * depth, z - rise),
                          (x - 0.42 * half, y - 0.88 * depth, z + rise),
                          (x + 0.42 * half, y - 0.88 * depth, z + rise * 0.55),
                          (x + half, y + 0.20 * depth, z - rise)], width)
    elif back >= 1:
        G.seam_strip(bm, (x - 0.74 * half, y - 0.74 * depth, z - rise * 0.5),
                     (x + 0.74 * half, y - 0.74 * depth, z - rise * 0.5),
                     width=width * 0.86, segs=4)
    for i in range(2 if branch else 0):
        s = 1.0 - 2.0 * i
        G.seam_strip(bm, (x + s * 1.02 * half, y - 0.10 * depth, z - 0.04),
                     (x + s * 1.32 * half, y - 0.36 * depth, z + branch),
                     width=width * 0.74, segs=4)


# ================================================================= the guardian
def _guardian(G):
    c = G.begin(COLLECTION, GUARDIAN)

    G.root_part(c, (-0.80, -0.70, ROOT_Z - 0.66), (0.80, 0.70, ROOT_Z + 0.66))
    G.hitbox(c, (-2.80, -2.55, 0.0), (2.80, 2.75, 11.10), pivot=(0.0, 0.0, ROOT_Z),
             parent="Root")

    _hips(G, c)
    _core(G, c)
    _head(G, c)
    _face(G, c)
    _chips(G, c)
    for side in (+1, -1):
        _shoulder(G, c, side)
        _arm(G, c, side)
        _leg(G, c, side)
    _throw_rock(G, c)


def _hips(G, c):
    """The pelvis: one wide flat block with a lump either side of it and one behind."""
    bm = bmesh.new()
    G.rock(bm, HIPS_C, 1.00, seed=11, jitter=0.18, subdiv=1, scale=(1.52, 1.12, 0.76))
    _boulders(G, bm, HIP_SLOTS, seed=3, jitter=0.22)
    G.part("Hips", bm, c, "Basalt", (0.0, 0.0, ROOT_Z), parent="Root")


def _core(G, c):
    """The chest: FIVE big overlapping boulders - a back plate, two flanks, a low front
    plate and the deck the head sits on.  They interlock into one dense mass (the core is
    the heaviest thing on the model, not a skeleton) and the ember burns in the one slot
    they leave, at the top of the chest under the chin."""
    bm = bmesh.new()
    _boulders(G, bm, CORE_SLOTS, seed=5, jitter=0.20, scale=CORE_SCALE)
    G.part("Core", bm, c, "Basalt", WAIST, parent="Hips")

    bm = bmesh.new()                                   # the ember caged inside the mass
    G.blob(bm, HEART_C, (0.66, 0.46, 0.44), seed=7, jitter=0.20, subdiv=1)
    for s in (+1, -1):                                 # two sparks out in the flank slot
        G.diamond(bm, (s * 0.74, 0.86, 8.16), radius=0.15, length=0.50,
                  axis=(s * 0.6, 1.0, 0.2), sides=4)
    G.part("CoreHeart", bm, c, "EmberGlow", (0.0, 0.30, CORE_Z), parent="Core")

    bm = bmesh.new()
    # 1. the chest band: ONE run of light 2.9 studs wide, flank to flank, filling the gap
    #    between the low front plate and the deck so the whole torso reads cracked open
    _seam_run(G, bm, [(-1.45, 0.30, 8.30), (-0.66, 0.92, 8.62), (0.00, 1.12, 8.52),
                      (0.66, 0.92, 8.62), (1.45, 0.30, 8.30)], 0.36)
    for s in (+1, -1):                                 # ... branching down to the waist
        G.seam_strip(bm, (s * 0.72, 0.90, 8.60), (s * 1.00, 1.05, 7.95), width=0.14,
                     segs=4)
    G.seam_strip(bm, (0.00, 1.12, 8.52), (0.08, 0.98, 9.00), width=0.14, segs=4)
    # 2. the waist, the widest gap on the body: the hips stop at 6.64, the chest starts
    #    at 6.87, and the crack climbs out of both ends into the hip crevice
    _gap_seam(G, bm, WAIST, 1.22, 0.20, depth=0.95, rise=0.12, back=1, branch=0.46)
    # 3. the neck, under the head
    _gap_seam(G, bm, NECK, 0.74, 0.15, depth=0.66, rise=0.08, back=0)
    # 4. the long diagonal crack out to each shoulder boulder, which hangs off nothing
    #    else at all - it has to be a run, not a dot, or the shoulder looks unattached
    for s in (+1, -1):
        _seam_run(G, bm, [(s * 1.00, 0.70, 8.22), (s * 1.40, 0.32, 8.52),
                          (s * 1.70, -0.30, 8.46)], 0.32)
    G.part("CoreSeams", bm, c, "Lava", (0.0, 0.05, CORE_Z), parent="Core")


def _head(G, c):
    """One boulder.  It sits DOWN IN the shoulders now - crown at 10.85 against theirs at
    10.56, and only a 0.21 neck gap above the chest deck - so it reads as the top of the
    pile rather than as a rock parked in the air above it.  One stubby basalt column."""
    bm = bmesh.new()
    G.rock(bm, HEAD_C, HEAD_R, seed=21, jitter=0.20, subdiv=1, scale=(1.06, 0.96, 0.95))
    G.rock(bm, (0.0, 0.42, 9.47), 0.40, seed=22, jitter=0.22, subdiv=0,
           scale=(1.25, 0.85, 0.75))                              # the jaw block
    G.hex_prism(bm, (0.20, -0.26, 10.76), 0.22, 0.58, axis=(0.22, -0.24, 1.0), sides=6,
                taper=0.74)
    G.part("Head", bm, c, "Basalt", NECK, parent="Core")


def _face(G, c):
    """Two hexagonal pits burning under a heavy brow, and a zigzag crack for a mouth."""
    bm = bmesh.new()
    # the brow is 1.32 wide against a head 1.76 across, so its ends stay ON the boulder
    G.plate(bm, G.chevron_pts(1.32, 0.30, 0.22, tip_at=-1), 0.34, at=(0.0, 0.60, 10.49),
            normal=(0, 1, 0))                                     # the brow ridge
    for s in (+1, -1):
        # a six-sided RIM, not a plate: the socket has to be hollow or the glow it is
        # meant to contain is buried behind it.  The barnacle profile leaves a floor
        # 0.08 in from the head, which is what the ember below sits on.
        G.barnacle(bm, (s * EYE[0], EYE[1] - 0.10, EYE[2]), normal=(s * 0.30, 1.0, 0.12),
                   r_out=0.36, r_in=0.21, height=0.26, segs=6)
    G.part("Brow", bm, c, "BasaltLight", (0.0, 0.64, 10.41), parent="Head")

    for s, tag in ((+1, "R"), (-1, "L")):
        bm = bmesh.new()                       # the ember, sunk 0.05 inside the rim
        G.hex_prism(bm, (s * (EYE[0] + 0.04), EYE[1] + 0.03, EYE[2] + 0.02), 0.19, 0.14,
                    axis=(s * 0.30, 1.0, 0.12), sides=6)
        G.part("Eye_" + tag, bm, c, "EmberGlow", _m(s, EYE), parent="Head")

    bm = bmesh.new()
    crack = G.zigzag((-0.54, 0.70, MOUTH_Z), (0.54, 0.70, MOUTH_Z), n=7, amp=0.13,
                     axis=(0.0, 0.10, 1.0))
    for a, b in zip(crack, crack[1:]):
        G.seam_strip(bm, a, b, width=0.10, segs=4)
    G.part("Mouth", bm, c, "Lava", (0.0, 0.70, MOUTH_Z), parent="Head")


def _chips(G, c):
    """The loose chips that never settle - they orbit the body while it is awake."""
    bm = bmesh.new()
    for i, (x, y, z, r) in enumerate(CHIP_SLOTS):
        G.rock(bm, (x, y, z), r, seed=61 + i, jitter=0.34, subdiv=0,
               scale=(1.0, 0.85, 0.75))
    for i, (bx, by, bz, tx, ty, tz) in enumerate(
            ((1.55, -1.95, 10.05, 1.80, -2.25, 10.50),
             (-1.95, 1.60, 9.85, -2.20, 1.90, 10.25),
             (0.70, 2.10, 8.60, 0.88, 2.42, 8.95),
             (-0.80, -2.10, 9.90, -1.00, -2.40, 10.28))):
        G.spike_shard(bm, (bx, by, bz), (tx, ty, tz), 0.22, thick=0.13,
                      roll_deg=28 * i)
    G.part("Chips", bm, c, "BasaltLight", (0.0, 0.0, CORE_Z), parent="Core")


def _shoulder(G, c, s):
    """ONE ENORMOUS BOULDER, and nothing else.  At r 1.26 it measures 2.52 x 2.42 x 2.17,
    which makes it the biggest single mass on the model - bigger than the head (1.78) and
    bigger than the back plate of the chest (2.24) - exactly as the sheet has it.  No
    satellite chunks and no crust columns on it: anything stuck to a boulder this size
    only turns it back into a cluster of pebbles."""
    tag = "R" if s > 0 else "L"
    bm = bmesh.new()
    G.rock(bm, _m(s, SHOULDER_C), 1.26, seed=31 + (s > 0), jitter=0.16, subdiv=1,
           scale=(1.00, 0.96, 0.86))
    G.part("Shoulder_" + tag, bm, c, "Basalt", _m(s, SHOULDER_J), parent="Core")


def _arm(G, c, s):
    """Boulder upper arm, boulder forearm, one huge boulder fist - each floating off the
    last, each gap welded by its own seam part so the light travels with the swing."""
    tag = "R" if s > 0 else "L"
    arm_j = _m(s, ARM_J)
    elbow = _m(s, ELBOW)
    wrist = _m(s, WRIST)

    bm = bmesh.new()                                   # ONE boulder, 1.67 x 1.64 x 1.97
    G.rock(bm, (s * 2.26, 0.14, 6.94), 0.95, seed=41 + (s > 0), jitter=0.20, subdiv=1,
           scale=(1.02, 1.00, 1.20))
    G.part("ArmUpper_" + tag, bm, c, "Basalt", arm_j, parent="Shoulder_" + tag)

    bm = bmesh.new()                                   # ONE boulder, 1.52 x 1.52 x 1.73
    G.rock(bm, (s * 2.24, 0.34, 4.86), 0.88, seed=45 + (s > 0), jitter=0.20, subdiv=1,
           scale=(1.00, 1.00, 1.14))
    G.part("ArmLower_" + tag, bm, c, "Basalt", elbow, parent="ArmUpper_" + tag)

    bm = bmesh.new()                                   # ONE massive block, 1.88 x 1.95
    G.rock(bm, _m(s, FIST_C), 1.00, seed=49 + (s > 0), jitter=0.20, subdiv=1,
           scale=(1.02, 1.06, 0.96))
    G.part("Fist_" + tag, bm, c, "Basalt", wrist, parent="ArmLower_" + tag)

    bm = bmesh.new()                                   # shoulder gap, then elbow gap
    _gap_seam(G, bm, (s * 2.26, 0.14, 8.16), 0.86, 0.17, depth=0.66, rise=0.10)
    _gap_seam(G, bm, (s * 2.24, 0.26, 5.88), 0.78, 0.15, depth=0.64, rise=0.09)
    G.part("SeamArm_" + tag, bm, c, "Lava", arm_j, parent="ArmUpper_" + tag)

    bm = bmesh.new()                                   # the wrist
    _gap_seam(G, bm, (s * 2.20, 0.50, 3.88), 0.82, 0.14, depth=0.70, rise=0.08)
    G.part("SeamFist_" + tag, bm, c, "Lava", wrist, parent="ArmLower_" + tag)


def _leg(G, c, s):
    """Boulder thigh, boulder shin, a flat slab of a foot with a toe and a heel chip."""
    tag = "R" if s > 0 else "L"
    hip = _m(s, HIP)
    knee = _m(s, KNEE)
    ankle = _m(s, ANKLE)

    bm = bmesh.new()                                   # ONE boulder, 1.89 x 1.82 x 1.69
    G.rock(bm, _m(s, THIGH_C), 0.99, seed=71 + (s > 0), jitter=0.20, subdiv=1,
           scale=(1.10, 1.06, 0.98))
    G.part("LegUpper_" + tag, bm, c, "Basalt", hip, parent="Hips")

    bm = bmesh.new()                                   # ONE boulder, 1.56 x 1.56 x 1.75
    G.rock(bm, _m(s, SHIN_C), 0.90, seed=77 + (s > 0), jitter=0.20, subdiv=1,
           scale=(1.00, 1.00, 1.12))
    G.part("LegLower_" + tag, bm, c, "Basalt", knee, parent="LegUpper_" + tag)

    bm = bmesh.new()                                   # ONE slab, 1.75 x 2.44 x 0.95
    G.rock(bm, _m(s, FOOT_C), 0.86, seed=81 + (s > 0), jitter=0.11, subdiv=1,
           scale=(1.02, 1.42, 0.55))
    G.part("Foot_" + tag, bm, c, "Basalt", ankle, parent="LegLower_" + tag)

    bm = bmesh.new()                                   # the hip gap, then the knee gap
    _gap_seam(G, bm, _m(s, HIP), 0.92, 0.17, depth=0.72, rise=0.09)
    _gap_seam(G, bm, _m(s, KNEE), 0.80, 0.16, depth=0.66, rise=0.09)
    G.part("SeamLeg_" + tag, bm, c, "Lava", hip, parent="LegUpper_" + tag)

    bm = bmesh.new()                                   # the ankle
    _gap_seam(G, bm, _m(s, ANKLE), 0.80, 0.14, depth=0.80, rise=0.07, back=0)
    G.part("SeamAnkle_" + tag, bm, c, "Lava", ankle, parent="LegLower_" + tag)


def _throw_rock(G, c):
    """The loose rock in the right fist: its own little stack of basalt with its own
    seams, parented to the fist so a throw can let go of it."""
    bm = bmesh.new()                                   # ONE rock, 1.60 x 1.54 x 1.54
    G.rock(bm, ROCK_C, 0.80, seed=91, jitter=0.24, subdiv=1, scale=(1.00, 0.96, 0.96))
    G.part("ThrowRock", bm, c, "Basalt", GRIP, parent="Fist_R")

    bm = bmesh.new()                                   # one long crack right over it
    _seam_run(G, bm, [(2.04, 1.18, 3.62), (2.36, 1.42, 3.92), (3.00, 2.10, 3.30)], 0.26)
    G.seam_strip(bm, (1.96, 2.24, 2.86), (2.56, 1.34, 2.72), width=0.12, segs=4)
    G.part("ThrowSeams", bm, c, "Lava", GRIP, parent="ThrowRock")


# ================================================================= the rock pile
def _seat(G):
    """The heap it sleeps as: dead basalt, ash blown into the cracks, NO glow anywhere -
    asleep the guardian is just two more boulders on top of this."""
    c = G.begin(SEAT, GUARDIAN, prefix="EmberSeat")

    bm = bmesh.new()
    _boulders(G, bm, PILE_SLOTS, seed=101, jitter=0.18, scale=PILE_SCALE)
    G.part("Pile", bm, c, "Basalt", (0.0, 0.0, 0.0), parent=None)

    bm = bmesh.new()                                   # paler chunks broken off the heap
    for i, (x, y, z, r) in enumerate(((-0.62, -1.70, 0.54, 0.44), (1.62, 1.08, 0.58, 0.48),
                                      (-2.02, 0.62, 0.50, 0.40), (0.42, 0.34, 2.34, 0.36))):
        G.rock(bm, (x, y, z), r, seed=111 + i, jitter=0.26, subdiv=0,
               scale=(1.0, 1.0, 0.85))
    for (x, y, z, r, h, ax) in ((-1.52, -0.30, 1.86, 0.20, 0.54, (-0.30, -0.12, 1.0)),
                                (1.18, -0.92, 1.72, 0.17, 0.46, (0.26, -0.30, 1.0))):
        G.hex_prism(bm, (x, y, z), r, h, axis=ax, sides=6, taper=0.78)
    G.part("Crust", bm, c, "BasaltLight", (0.0, 0.0, 0.60), parent="Pile")

    bm = bmesh.new()                                   # ash drifted into the crevices
    for i, (x, y, z, r) in enumerate(((0.00, -0.20, 2.44, 0.52), (-1.10, 0.42, 1.78, 0.46),
                                      (1.10, 0.42, 1.78, 0.46), (0.00, 1.26, 1.62, 0.40),
                                      (-1.70, -0.90, 1.26, 0.38), (1.70, -0.90, 1.26, 0.38))):
        G.patch(bm, (x, y, z), normal=(0.12 * (i % 3 - 1), 0.1, 1.0), radius=r,
                height=0.10, seed=121 + i, jitter=0.26, segs=6)
    G.part("Dust", bm, c, "Ash", (0.0, 0.0, 1.60), parent="Pile")

    bm = bmesh.new()                                   # shards flaked off onto the floor
    for i in range(9):
        a = math.radians(40.0 * i + 17.0)
        r = 2.35 + 0.42 * ((i * 7) % 5) / 4.0
        bx, by = math.cos(a) * r, math.sin(a) * r * 0.92
        G.spike_shard(bm, (bx, by, 0.09), (bx + math.cos(a) * 0.34,
                                           by + math.sin(a) * 0.30, 0.42), 0.26,
                      thick=0.12, roll_deg=24 * i)
    for i, (x, y, z, r) in enumerate(((2.58, 1.38, 0.24, 0.22), (-2.72, 0.42, 0.26, 0.24),
                                      (0.30, -2.62, 0.22, 0.20))):
        G.rock(bm, (x, y, z), r, seed=131 + i, jitter=0.22, subdiv=0,
               scale=(1.0, 1.0, 0.72))
    G.part("Shards", bm, c, "Ash", (0.0, 0.0, 0.12), parent="Pile")
    return c
