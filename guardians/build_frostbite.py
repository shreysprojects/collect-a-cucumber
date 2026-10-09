"""Snow biome guardian 5/10: FROSTBITE, the shaggy yeti that sleeps on a block of ice.

Reference sheet: a hunched, immensely shaggy giant whose whole silhouette is made of
overlapping triangular fur shards - bright FurWhite on top, FurShadow blue-white
underneath and in every recess, so no surface anywhere is smooth.  A pear body with NO
neck: the head is a bump on the front of the shoulder mass, under a hunched ruff that is
the highest point of the whole guardian.  The face is a dark blue-grey oval set deep in
the fur, with a heavy brow, two tiny glowing ice-blue eyes, and two cream fangs hanging
down over an underbite jaw.  Arms as thick as tree trunks reach the ground and rest on
big dark palms; the feet are big dark flat slabs.  It breathes frost - a few pale ice
shards hang in the air in front of its mouth.  It sleeps slumped on a cracked ice block.
"""
import bmesh, math, random

COLLECTION = "Frostbite"
GUARDIAN = "Frostbite"
SEAT = "Frostbite_Seat"

NOTES = (
    "9.8 studs to the tips of the hunched ruff (the head bump tops out at 8.4, well "
    "below the hunch, exactly as the sheet shows).  It is a PEAR, not a column: the "
    "white coat measures 4.9 across at the hip skirt and 3.3 at the shoulder cap, and "
    "the FurShadow core under it tapers the same way, x 1.76 at the belly to 1.14 at the "
    "hunch.  With the two ground-planted palms it is 6.4 wide overall; the Hitbox is the "
    "5.2 x 5.05 x 9.85 BODY box, the same convention the worked example uses (its box "
    "covers the torso, not the outstretched arms).  Faces +Y, and the character's RIGHT "
    "is +X, which is screen-LEFT in a render.  Rig: Root at the waist carries Body; Body "
    "carries the head, both arms and both legs (there is no neck and no separate hips - "
    "the pear mass IS the torso).  THE COAT is built as SHINGLE COURSES, not as "
    "fur_coat's radiating needles: _fur_row() lays n large FLAT triangular shards (thick "
    "fixed at 0.22) round an ellipse at one height, tipped DOWN and only 0.24-0.44 of "
    "their length outward, and every course drops past the ROOTS of the course below it "
    "- 8.75 to 7.59 over a course starting at 7.55, 7.55 to 6.32 over one starting at "
    "6.28, and so on to the hip skirt at 3.58.  n * width is ~1.3x the ring "
    "circumference at every call, so neighbours overlap sideways too.  The body coat is "
    "39 shards where a radiating coat needed 56, each about 1.8x as wide (1.36-1.85 "
    "against 0.62-0.92), and the FurShadow core is a shrunken volume that the coat "
    "covers rather than a silhouette of its own - that is what stops the animal reading "
    "pale blue.  Every fur layer is still a separate FurWhite part parented to the "
    "segment it grows on - FurBody, FurHead, FurShoulder_R/L and FurArm_R/L on the upper "
    "arms, FurFore_R/L on the forearms, FurLeg_R/L - so the shards travel with their "
    "joint; the shoulder ruff is parented to ArmUpper, pauldron-style, so it caps the "
    "joint when the arm swings.  ARMS REACH THE FLOOR and are a defining part of the "
    "silhouette: shoulder x 1.62 raking out and forward to wrist x 2.30 / y 1.62, so "
    "they stand clear of the belly instead of drowning in it, and each ends in a "
    "1.64 x 1.28 x 1.28 dark Face palm whose underside IS z 0.00 - it rests on the "
    "ground, dark against the white coat, with four heavy fingers and a thumb.  The legs "
    "are tucked to x 0.80 so the knuckles plant outside and ahead of the feet like a "
    "gorilla's.  The FACE is a small dark OVAL - 1.40 wide by 2.00 tall, taller than it "
    "is wide so it can never read as a horizontal visor bar - plus a muzzle lump for the "
    "two big Fangs (0.42 thick, 0.94 long) to hang out of a quarter-stud clear below it, "
    "over the jutting underbite.  The brow is a 1.12-wide RIDGE narrower than the oval, "
    "with a small angled ridge ABOVE each eye, never across it.  The eyes are two TINY "
    "Neon pips, 0.19 across and 0.18 apart against the 0.31-across, 0.66-apart hexes "
    "they replaced; SLEEP_LOOK darkens them to 3f5470 and they are the whole wake tell, "
    "so they must not be buried.  Jaw is a real hinge (pivot behind the lip) so a roar "
    "drops the underbite under the fixed upper fangs; Frost is the five floating breath "
    "shards, pivoted at the mouth so they swing with the head.  Legs are one segment per "
    "the brief; the ankle carries the flex.  Nothing is below z = 0 - the palms and the "
    "soles BOTTOM OUT at exactly 0.00, and the dry run's min_z -0.78 is its scan reading "
    "the armpit fur's direction tuple axis=(s * 0.62, 0.0, -0.78) as a point, the same "
    "artefact the worked example reports.  The seat is a 4.6 x 3.3 x 1.8 "
    "cracked ice block, 3.5 deep counting the lip its top slab throws over the front "
    "face, with dark seams sunk into five faces, two crystal shards leaning out of the "
    "top, five icicles hanging under that lip and a low snow drift banked round the base "
    "- 5.6 x 4.5 all told.  It is set back of centre because the legs are only 2.2 long "
    "on a 1.8-tall block: Sit drops the rig 0.68 down and 0.35 FORWARD, which lands the "
    "belly on the block top, both soles flat on the floor clear of the block's front "
    "face at y 0.70, and both sets of knuckles on the floor outside the feet.  Awake, "
    "Run and Roar were solved the same way; the Sit and Awake arm ry values were pulled "
    "in by 8-10 degrees when the arms moved out, so the hands land where they used to."
)

# ---------------------------------------------------------------- the skeleton
# THE PEAR.  The silhouette has to taper the other way from a column: the FurShadow core
# runs x 1.76 at the belly down to 1.14 at the hunch, and the white coat that shingles
# over it reaches x 2.44 at the hip skirt and only 1.62 at the shoulder cap - 4.9 wide at
# the bottom, 3.3 at the top.  The core is deliberately SMALLER than the coat everywhere
# (it is volume, not silhouette); every course of shards roots just outside it and is
# wide enough to overlap its neighbours sideways, so no blue shows between them.
HIP_Z = 2.95
BODY_PIVOT = (0.0, 0.0, HIP_Z)
BELLY_C, BELLY_R = (0.0, 0.22, 4.25), (1.76, 1.44, 1.86)
WAIST_C, WAIST_R = (0.0, 0.10, 5.85), (1.58, 1.24, 1.05)
CHEST_C, CHEST_R = (0.0, -0.06, 7.00), (1.42, 1.14, 1.72)
HUMP_C, HUMP_R = (0.0, -0.34, 8.40), (1.14, 0.94, 0.96)

# no neck: the head is a bump hung off the FRONT of the shoulder mass
HEAD_PIVOT = (0.0, 0.62, 6.98)
HEAD_C, HEAD_R = (0.0, 1.28, 7.35), (1.14, 0.98, 1.02)
FACE_PIVOT = (0.0, 1.30, 7.35)
FACE_C, FACE_R = (0.0, 1.68, 7.35), (0.70, 0.70, 1.00)   # 1.4 wide x 2.0 tall: an OVAL
MUZZLE_C, MUZZLE_R = (0.0, 2.20, 7.00), (0.50, 0.40, 0.30)   # the upper lip the fangs
BROW_AT = (0.0, 1.88, 7.82)                                  # hang out of
EYE = (0.185, 2.34, 7.42)                # +X = its right = screen LEFT
JAW_PIVOT = (0.0, 1.30, 7.00)
FANG_AT = (0.0, 2.56, 6.98)              # the upper gum line the fangs hang from
MOUTH = (0.0, 2.80, 6.60)                # where the breath leaves it

# Arms to the FLOOR, knuckles down like a gorilla - planted FORWARD of the feet as well
# as outside them, and raked OUTWARD as they fall (shoulder x 1.62, wrist x 2.30) so they
# widen the bottom of the pear instead of the top.  A 1.6-wide forearm hanging at y 0.7
# beside the thigh would put its axis inside the leg, so the wrist also rakes forward to
# y 1.62 while the leg stays at y 0.04.  The palm is 1.64 x 1.28 and starts at z 0.00 -
# it RESTS on the floor, which is what makes the arms read in the silhouette.
SHOULDER = (1.88, -0.06, 7.30)
ELBOW = (2.62, 0.74, 4.20)
WRIST = (2.78, 1.62, 1.24)
HAND_C = (2.92, 1.70, 0.58)

# stubby legs, well inboard of the arms, on big flat feet
HIP = (0.80, 0.04, 2.86)
ANKLE = (0.80, 0.14, 0.62)

# The ice block it sleeps on: 4.6 x 3.3 x 1.8 (3.5 counting the lip the icicles hang
# from), set BACK of centre.  Its legs are only 2.2 long and the block is 1.8 tall, so a
# seated yeti has to perch near the front edge for its folded legs to put the soles on
# the floor clear of the block - hence the -0.95 and the front face at y 0.70.
SEAT_C = (0.0, -0.95)
SEAT_HALF = (2.30, 1.65)
SEAT_TOP = 1.80
SEAT_LIP = 0.20                          # how far the top slab overhangs the front face


def _m(p, s):
    """Mirror a right-side (+X) point onto side `s`."""
    return (p[0] * s, p[1], p[2])


def _fur_row(G, bm, center, radii, n, width, length, drop=0.82, out=0.42, phase=0.0,
             span=360.0, thick=0.22, roll=7.0, side=1):
    """ONE SHINGLE COURSE of fur - the shape the sheet actually has.

    `fur_coat` radiates needles off an ellipsoid in every direction, which reads as a
    dandelion clock, so this builds the coat by hand instead: n LARGE, FLAT triangular
    shards rooted on an ellipse at one height and laid DOWN and only slightly out, each
    course dropping far enough to bury the roots of the course below it.

    `spike_shard` takes its width across `d x Z`, which for a shard pointing down-and-out
    is the ring TANGENT - so `width` is exactly the arc each shard covers, and n * width
    is set to ~1.3 x the ring circumference at every call site.  `thick` runs radially
    and is held at 0.22 so the shard is a flat scale, not a wedge.  `out` is the analogue
    of fur_coat's out_bias: 0.24-0.44 here against the 0.68-0.72 that made the halo.

    `side` mirrors the ring in x, so the two arms/legs are exact mirrors of each other and
    the model stays centred on x = 0.  For a ring ON the centre line, keep n EVEN: an odd
    full ring has no antipodal pair and pulls the bounding box off centre."""
    cx, cy, cz = center
    rx, ry = radii
    full = abs(span - 360.0) < 1e-6
    # Courses of IDENTICAL shards at IDENTICAL spacing tile into obvious horizontal bands -
    # the first build of this read as a pinecone. A deterministic wobble on the angle, the
    # height and the size of every shard breaks the grid without moving the silhouette.
    rng = random.Random(int(abs(cz) * 977) + n * 31 + int(abs(cx) * 131) + 7)
    for i in range(n):
        step = i / float(n) if full else i / float(max(n - 1, 1))
        jog = (span / float(n)) * 0.34 * (rng.random() * 2.0 - 1.0)
        a = math.radians(phase + span * step + jog)
        L = length * (0.82 + 0.36 * rng.random())
        w = width * (0.86 + 0.30 * rng.random())
        dz = length * 0.10 * (rng.random() * 2.0 - 1.0)
        ux, uy = math.cos(a) * side, math.sin(a)
        root = (cx + ux * rx, cy + uy * ry, cz + dz)
        nx, ny = ux * ry, uy * rx                   # true outward normal of the ellipse
        m = math.hypot(nx, ny) or 1.0
        tip = (root[0] + nx / m * out * L,
               root[1] + ny / m * out * L,
               root[2] - drop * L)
        G.spike_shard(bm, root, tip, w, thick=thick,
                      roll_deg=roll * (1 if i % 2 else -1) + 9.0 * (rng.random() - 0.5))


# ---------------------------------------------------------------- the states
POSES = {
    # Asleep: dropped onto the ice block, rounded forward, legs stretched out over the
    # front edge with both soles flat on the floor, knuckles down outside them, and the
    # head - which hangs off the FRONT of the shoulder mass, so a nod swings it out as
    # well as down - lolling forward over its own knees.  Belly z 1.79 on a 1.80 top.
    "Sit": {
        "Body": (-13, 0, 0), "Head": (-18, 0, 0), "Jaw": (-5, 0, 0),
        "ArmUpper_R": (-8, -12, 0), "ArmUpper_L": (-8, 12, 0),   # less splay than before:
        "ArmLower_R": (42, 10, 0), "ArmLower_L": (42, -10, 0),   # the arms START out wide
        "Hand_R": (-22, 0, 0), "Hand_L": (-22, 0, 0),
        "Leg_R": (58, -6, 0), "Leg_L": (58, 6, 0),
        "Foot_R": (-44, 0, 0), "Foot_L": (-44, 0, 0),
    },
    # The sheet's hero pose - and the sheet's yeti still has its knuckles down: the hunch
    # rocks back, the head comes up, the jaw opens on a roar.  The arms cancel the body's
    # +8 so they hang dead vertical and both sets of knuckles land at z 0.07, not in the
    # air, which is the whole point of a gorilla stance.
    "Awake": {
        "Body": (8, 0, 0), "Head": (14, 0, 0), "Jaw": (-36, 0, 0),
        "ArmUpper_R": (-8, -4, 0), "ArmUpper_L": (-8, 4, 0),     # -8 cancels the body's
        "ArmLower_R": (0, 2, 0), "ArmLower_L": (0, -2, 0),       # +8 so the arm hangs
        "Hand_R": (0, 0, 0), "Hand_L": (0, 0, 0),                # dead vertical
        "Leg_R": (-8, -6, 0), "Leg_L": (-8, 6, 0),   # cancel the body's rock: legs stay
    },                                               # vertical, so the soles stay flat
    # knuckle-run: pitched forward, one arm planted ahead, the other pushing off behind
    "Run": {
        "Body": (-18, 0, 0), "Head": (26, 0, 0), "Jaw": (-16, 0, 0),
        "ArmUpper_R": (22, -14, 0), "ArmLower_R": (-10, 6, 0), "Hand_R": (8, 0, 0),
        "ArmUpper_L": (-30, 14, 0), "ArmLower_L": (28, -6, 0), "Hand_L": (12, 0, 0),
        "Leg_R": (-26, -4, 0), "Foot_R": (22, 0, 0),
        "Leg_L": (44, 4, 0), "Foot_L": (-32, 0, 0),
    },
    # The signature: reared back on straight legs, head thrown back, jaw wide, and both
    # FISTS thrown up beside the head - the elbow folds hard (ry -128 on top of the
    # shoulder's -42) instead of the arm swinging out straight, which is what keeps a
    # six-stud arm from throwing the hands seven studs off the centre line.
    "Roar": {
        "Body": (16, 0, 0), "Head": (30, 0, 0), "Jaw": (-48, 0, 0),
        "ArmUpper_R": (8, -34, 0), "ArmUpper_L": (8, 34, 0),
        "ArmLower_R": (-4, -122, 0), "ArmLower_L": (-4, 122, 0),
        "Hand_R": (34, 0, 0), "Hand_L": (34, 0, 0),
        "Leg_R": (-14, -8, 0), "Leg_L": (-14, 8, 0),
        "Foot_R": (-2, 0, 0), "Foot_L": (-2, 0, 0),
    },
}
# Sit: 0.68 down onto the 1.80-tall ice block and 0.35 FORWARD, so its backside settles
# on the block's front half (belly underside at z 1.79) and its stretched legs put both
# soles on the floor at z 0.03-0.06, clear of the block's front face at y 0.70.
# Roar: leaning the torso back 16 degrees barely moves the hips once the legs counter it,
# so the rig only needs 0.02 back to keep both soles flat on the floor.
POSE_LOC = {"Sit": {"Root": (0.0, 0.35, -0.68)},
            "Roar": {"Root": (0.0, 0.0, 0.02)}}


def build(G):
    _guardian(G)
    _seat(G)
    return G.coll(COLLECTION)


# ================================================================= the guardian
def _guardian(G):
    c = G.begin(COLLECTION, GUARDIAN)

    G.root_part(c, (-0.95, -0.75, HIP_Z - 0.62), (0.95, 0.75, HIP_Z + 0.62))
    G.hitbox(c, (-2.60, -2.10, 0.0), (2.60, 2.95, 9.85), pivot=BODY_PIVOT, parent="Root")

    _body(G, c)
    _body_fur(G, c)
    _head(G, c)
    _face(G, c)
    _jaw(G, c)
    _frost(G, c)
    for s in (+1, -1):
        _arm(G, c, s)
        _leg(G, c, s)


def _body(G, c):
    """The FurShadow volume: belly, waist, shoulder mass and the hunch over them, with
    shadow shards hanging in the recesses the white coat cannot reach."""
    bm = bmesh.new()
    G.blob(bm, BELLY_C, BELLY_R, seed=3, jitter=0.13)
    G.blob(bm, WAIST_C, WAIST_R, seed=4, jitter=0.11)
    G.blob(bm, CHEST_C, CHEST_R, seed=5, jitter=0.13)
    G.blob(bm, HUMP_C, HUMP_R, seed=6, jitter=0.15)

    # the underside of the belly, hanging straight down over the top of the legs
    _fur_row(G, bm, (0.0, 0.26, 3.30), (1.44, 1.24), 6, 1.34, 1.10, drop=0.90, out=0.16,
             phase=30.0)
    # the armpit shadow under each shoulder - fewer and wider, same as the white coat
    for s in (+1, -1):
        G.fur_coat(bm, (s * 1.18, 0.06, 6.10), (0.50, 0.92, 0.78), n=4, length=0.74,
                   width=1.15, seed=10 + s, cone_deg=120, axis=(s * 0.62, 0.0, -0.78),
                   out_bias=0.34, droop=0.30)
    G.part("Body", bm, c, "FurShadow", BODY_PIVOT, parent="Root")


def _body_fur(G, c):
    """The white coat, as SIX SHINGLE COURSES rather than a cloud of needles.

    39 shards where there were 56, each ~1.8x as wide (1.36-1.85 against 0.62-0.92) and
    laid flat against the body instead of standing off it.  Every course drops past the
    ROOTS of the course below (8.75 -> 7.59 over a course starting at 7.55, and so on all
    the way down), so the FurShadow core is covered top to bottom and the animal reads
    white.  The radii also carry the pear: 0.88 at the ruff, 1.10 at the shoulder cap,
    1.72 at the hip skirt."""
    bm = bmesh.new()
    # the hunched ruff: the only course that sweeps UP, and the top of the whole model at
    # z 9.77.  It is an arc, not a ring - the front 80 degrees is left to the head.
    _fur_row(G, bm, (0.0, -0.34, 9.05), (0.88, 0.76), 5, 1.40, 1.20, drop=-0.60, out=0.72,
             phase=130.0, span=280.0)
    _fur_row(G, bm, (0.0, -0.30, 8.75), (1.10, 0.92), 6, 1.36, 1.45, phase=18.0,
             drop=0.80, out=0.40)                   # shoulder cap   -> tips z 7.59
    _fur_row(G, bm, (0.0, -0.14, 7.55), (1.40, 1.14), 6, 1.73, 1.50, phase=-8.0,
             drop=0.82, out=0.40)                   # upper chest    -> tips z 6.32
    _fur_row(G, bm, (0.0, 0.00, 6.28), (1.50, 1.22), 6, 1.85, 1.55, phase=18.0,
             drop=0.82, out=0.42)                   # lower chest    -> tips z 5.01
    _fur_row(G, bm, (0.0, 0.16, 4.95), (1.70, 1.40), 8, 1.58, 1.62, phase=-6.0,
             drop=0.80, out=0.42)                   # belly          -> tips z 3.65
    _fur_row(G, bm, (0.0, 0.22, 3.58), (1.72, 1.42), 8, 1.60, 1.58, phase=16.0,
             drop=0.84, out=0.44)                   # hip skirt      -> tips z 2.25
    G.part("FurBody", bm, c, "FurWhite", BODY_PIVOT, parent="Body")


def _head(G, c):
    """A bump on the front of the shoulder mass, and the white shards that bury it."""
    bm = bmesh.new()
    G.blob(bm, HEAD_C, HEAD_R, seed=31, jitter=0.11)
    G.blob(bm, (0.0, 0.52, 7.10), (0.92, 0.70, 0.86), seed=32, jitter=0.10)   # no neck
    G.part("Head", bm, c, "FurShadow", HEAD_PIVOT, parent="Body")

    bm = bmesh.new()
    # one shingle course over the crown and down the back of the skull (the front 96
    # degrees left open for the face), then a mane RING closing round the oval so it sits
    # at the bottom of a shaggy funnel.  8 shards at 1.05 wide where there were 11 at 0.48.
    _fur_row(G, bm, (0.0, 1.12, 7.98), (0.98, 0.86), 6, 1.42, 1.30, drop=0.80, out=0.40,
             phase=138.0, span=264.0)
    for i in range(8):
        a = math.radians(360.0 * i / 8.0 + 18.0)
        ux, uz = math.cos(a), math.sin(a)
        root = (ux * (FACE_R[0] + 0.36), 1.52, FACE_C[2] + uz * (FACE_R[2] + 0.10))
        tip = (ux * (FACE_R[0] + 1.02), 2.14, FACE_C[2] + uz * (FACE_R[2] + 0.64))
        G.spike_shard(bm, root, tip, 1.05, thick=0.22, roll_deg=24 * i)
    G.part("FurHead", bm, c, "FurWhite", HEAD_PIVOT, parent="Head")


def _face(G, c):
    """A small dark OVAL set deep in the fur - 1.40 wide and 2.00 tall, taller than it is
    wide so it can never read as a horizontal visor bar - with a brow ridge NARROWER than
    the oval above it, two tiny eye pips set close together under that brow, and two big
    fangs hanging clear below it."""
    bm = bmesh.new()
    G.blob(bm, FACE_C, FACE_R, seed=41, jitter=0.07)
    G.blob(bm, MUZZLE_C, MUZZLE_R, seed=43, jitter=0.08, subdiv=0)   # the upper lip - the
    G.blob(bm, (0.0, 2.50, 7.10), (0.34, 0.28, 0.24), seed=42, jitter=0.09,
           subdiv=0)                            # fangs must hang out of SOMETHING, and the
    for s in (+1, -1):                          # face oval alone stops 0.25 short of them
        G.stud_bump(bm, (s * 0.13, 2.66, 7.08), normal=(s * 0.25, 1, -0.2), radius=0.08,
                    height=0.05, segs=5, taper=0.4)                   # flat nose, nostrils
    G.part("Face", bm, c, "Face", FACE_PIVOT, parent="Head")

    bm = bmesh.new()            # a heavy brow RIDGE - 1.12 across, inside the 1.40 oval,
    G.beveled_box(bm, (-0.56, 1.88, 7.72), (0.56, 2.38, 7.98), bevel=0.12)   # not a bar
    for s in (+1, -1):                                  # and an angry ridge over each eye
        bx0, bx1 = sorted((s * 0.02, s * 0.46))         # mirrored corners must stay sorted
        G.box(bm, (bx0, 2.00, 7.56), (bx1, 2.40, 7.74))  # ABOVE the eye, never across it
    G.part("Brow", bm, c, "FaceDark", BROW_AT, parent="Head")

    for s, tag in ((+1, "R"), (-1, "L")):    # two TINY Neon pips: 0.19 across and 0.18
        bm = bmesh.new()                     # apart, against 0.31 across and 0.66 apart
        eye = _m(EYE, s)
        G.hex_prism(bm, eye, 0.095, 0.11, axis=(s * 0.22, 1, -0.10), sides=6)
        G.part("Eye_" + tag, bm, c, "EyeGlow", eye, parent="Head")

    bm = bmesh.new()                # two BIG fangs - 0.42 thick and 0.94 long, hanging a
    for s in (+1, -1):              # quarter-stud clear BELOW the oval and in front of the
        G.horn(bm, (s * 0.27, 2.54, 6.98), (s * 0.31, 2.70, 6.04), r0=0.21, r1=0.03,
               bow=(0, 0.06, 0), n=4, segs=5, power=1.15)      # jutting underbite lip
    G.part("Fangs", bm, c, "Fangs", FANG_AT, parent="Head")


def _jaw(G, c):
    """The underbite: a heavy lower lip that juts out past the fangs, hinged at the back
    so a roar drops it."""
    bm = bmesh.new()
    G.beveled_box(bm, (-0.54, 1.66, 6.24), (0.54, 2.42, 6.84), bevel=0.14)
    G.box(bm, (-0.42, 2.30, 6.34), (0.42, 2.58, 6.70))     # the lip, out past the fangs
    for s in (+1, -1):                                  # the corners of the mouth
        G.stud_bump(bm, (s * 0.44, 2.26, 6.78), normal=(s * 0.7, 0.7, 0.1), radius=0.12,
                    height=0.08, segs=5)
    G.part("Jaw", bm, c, "FaceDark", JAW_PIVOT, parent="Head")


def _frost(G, c):
    """The breath: a few pale ice shards hanging in the air in front of the mouth."""
    bm = bmesh.new()
    # pushed 0.3 further out than they were: the fangs are twice the size they used to be
    slots = ((0.14, 3.02, 6.66, 0.26), (-0.34, 3.14, 6.38, 0.22), (0.42, 3.06, 6.22, 0.20),
             (-0.10, 3.22, 6.04, 0.17), (0.28, 2.96, 5.98, 0.16))
    for i, (x, y, z, L) in enumerate(slots):
        G.diamond(bm, (x, y, z), radius=L * 0.42, length=L * 2.0,
                  axis=(0.25 * (1 if i % 2 else -1), 1.0, -0.45), sides=4)
    G.part("Frost", bm, c, "Ice", MOUTH, parent="Head")


def _arm(G, c, s):
    """A tree-trunk arm that REACHES THE FLOOR: shoulder ball, upper arm, forearm, and a
    big dark palm resting flat on z 0.  It is raked outward as it falls (x 1.62 -> 2.30)
    so it stands clear of the pear torso and reads as its own limb, and each fur course
    hangs off the segment it grows on."""
    tag = "R" if s > 0 else "L"
    sh, el, wr = _m(SHOULDER, s), _m(ELBOW, s), _m(WRIST, s)

    bm = bmesh.new()
    G.blob(bm, (sh[0] + s * 0.10, sh[1], sh[2] - 0.10), (0.96, 0.94, 0.94), seed=50 + s,
           jitter=0.12)                                             # the deltoid mass
    G.limb(bm, sh, el, 0.90, 0.84, segs=7, bow=(s * 0.14, 0.06, 0))
    G.part("ArmUpper_" + tag, bm, c, "FurShadow", sh, parent="Body")

    bm = bmesh.new()                    # the shoulder ruff: 5 wide shards, not 12 needles
    _fur_row(G, bm, (sh[0] - s * 0.06, sh[1] - 0.02, sh[2] + 0.12), (0.92, 0.94), 5, 1.38,
             1.15, drop=0.78, out=0.26, phase=26.0, side=s)
    G.part("FurShoulder_" + tag, bm, c, "FurWhite", sh, parent="ArmUpper_" + tag)

    bm = bmesh.new()                    # two courses down the upper arm, the second one
    for t, ph in ((0.30, 12.0), (0.68, 40.0)):      # starting above the first one's tips
        mid = G.lerp3(sh, el, t)
        _fur_row(G, bm, mid, (0.90, 0.90), 6, 1.30, 1.20, drop=0.84, out=0.24, phase=ph,
                 side=s)
    G.part("FurArm_" + tag, bm, c, "FurWhite", sh, parent="ArmUpper_" + tag)

    bm = bmesh.new()
    G.limb(bm, el, wr, 0.84, 0.76, segs=7, bow=(s * 0.06, 0.10, 0))
    G.blob(bm, (el[0], el[1] - 0.04, el[2]), (0.86, 0.82, 0.72), seed=80 + s, jitter=0.12,
           subdiv=0)                                                # the knobbly elbow
    G.part("ArmLower_" + tag, bm, c, "FurShadow", el, parent="ArmUpper_" + tag)

    bm = bmesh.new()                                    # two courses down the forearm,
    for t, ph in ((0.28, 8.0), (0.66, 36.0)):           # the last ending at the wrist so
        mid = G.lerp3(el, wr, t)                        # the dark palm stays uncovered
        _fur_row(G, bm, mid, (0.82, 0.82), 5, 1.24, 1.15, drop=0.86, out=0.24, phase=ph,
                 side=s)
    G.part("FurFore_" + tag, bm, c, "FurWhite", el, parent="ArmLower_" + tag)

    bm = bmesh.new()            # THE PALM.  1.64 x 1.28 x 1.28 against the old 1.16 x
    hx = HAND_C[0] * s          # 1.28 x 1.04, and it starts at z 0.00 - it rests on the
    G.beveled_box(bm, (hx - 0.82, HAND_C[1] - 0.78, 0.0),      # floor, dark against white
                  (hx + 0.82, HAND_C[1] + 0.50, 1.28), bevel=0.24)
    for i in range(4):                                          # four heavy curled fingers
        fx = hx + s * (-0.54 + 0.36 * i)                        # plain boxes: cheap
        G.box(bm, (fx - 0.19, HAND_C[1] + 0.34, 0.0),
              (fx + 0.19, HAND_C[1] + 0.98, 0.54))
        G.stud_bump(bm, (fx, HAND_C[1] + 0.70, 0.54), normal=(0, 0.28, 1), radius=0.17,
                    height=0.13, segs=4)                # the knuckle, ON TOP of the finger
    tx = hx - s * 0.84                                              # the thumb, inboard
    G.beveled_box(bm, (tx - 0.19, HAND_C[1] - 0.30, 0.02),
                  (tx + 0.19, HAND_C[1] + 0.36, 0.66), bevel=0.10)
    G.part("Hand_" + tag, bm, c, "Face", wr, parent="ArmLower_" + tag)


def _leg(G, c, s):
    """Stubby, thick, half buried in the belly fur, on a big flat dark foot."""
    tag = "R" if s > 0 else "L"
    hip, ank = _m(HIP, s), _m(ANKLE, s)

    bm = bmesh.new()
    G.limb(bm, hip, ank, 0.96, 0.80, segs=7, bow=(s * 0.06, 0.04, 0))
    G.blob(bm, (hip[0], hip[1], hip[2] - 0.15), (0.92, 0.90, 0.82), seed=100 + s,
           jitter=0.12)                                             # the haunch
    G.part("Leg_" + tag, bm, c, "FurShadow", hip, parent="Body")

    bm = bmesh.new()                    # two wide courses: these and the hip skirt above
    _fur_row(G, bm, (hip[0] + s * 0.02, 0.06, 2.62), (1.00, 0.98), 6, 1.36, 1.30,
             drop=0.80, out=0.32, phase=20.0, side=s)       # them are the heavy bottom of
    _fur_row(G, bm, (hip[0] + s * 0.04, 0.10, 1.52), (0.92, 0.90), 6, 1.26, 1.15,
             drop=0.82, out=0.28, phase=48.0, side=s)       # the pear
    G.part("FurLeg_" + tag, bm, c, "FurWhite", hip, parent="Leg_" + tag)

    bm = bmesh.new()                                                # the flat dark foot
    G.beveled_box(bm, (ank[0] - 0.66, -0.88, 0.0), (ank[0] + 0.66, 1.16, 0.56), bevel=0.16)
    for i in range(4):                                              # four blunt toes
        tx = ank[0] + s * (-0.42 + 0.29 * i)
        G.box(bm, (tx - 0.15, 1.06, 0.0), (tx + 0.15, 1.52 - 0.06 * i, 0.34))
    G.stud_bump(bm, (ank[0], -0.62, 0.54), normal=(0, -0.3, 1), radius=0.30, height=0.12,
                segs=6)                                             # the ankle knuckle
    G.part("Foot_" + tag, bm, c, "Face", ank, parent="Leg_" + tag)


# ================================================================= the ice block
def _seat(G):
    """A cracked block of ice with dark sunken crack lines, two crystal shards leaning
    out of its top, icicles under the front lip and a low snow drift round its base."""
    c = G.begin(SEAT, GUARDIAN, prefix="FrostbiteSeat")
    x0, x1 = SEAT_C[0] - SEAT_HALF[0], SEAT_C[0] + SEAT_HALF[0]
    y0, y1 = SEAT_C[1] - SEAT_HALF[1], SEAT_C[1] + SEAT_HALF[1]

    bm = bmesh.new()                                    # z starts at the jitter amplitude
    G.stone_block(bm, (x0, y0, 0.06), (x1, y1, SEAT_TOP - 0.18), seed=7, jitter=0.05,
                  bevel=0.16)                           # so no nudged corner digs in
    G.stone_block(bm, (x0 + 0.16, y0 + 0.14, SEAT_TOP - 0.34),   # the top slab, OVERHANGING
                  (x1 - 0.16, y1 + SEAT_LIP, SEAT_TOP), seed=9, jitter=0.05, bevel=0.14)
    G.stone_block(bm, (x0 - 0.42, y0 + 0.30, 0.07), (x0 + 0.55, y1 - 0.45, 0.72),
                  seed=11, jitter=0.06, bevel=0.12)                            # broken chunk
    G.stone_block(bm, (x1 - 0.70, y1 - 0.30, 0.07), (x1 + 0.34, y1 + 0.52, 0.55),
                  seed=13, jitter=0.06, bevel=0.10)                            # a shed step
    G.part("IceBlock", bm, c, "Ice", (0.0, 0.0, 0.0), parent=None)

    bm = bmesh.new()                    # cracks: dark seams sunk INTO the faces, not laid
    cracks = (((x0 + 0.40, y0 + 0.30, SEAT_TOP - 0.09), (x1 - 0.70, y1 - 0.50, SEAT_TOP - 0.09)),
              ((x0 + 1.40, y1 - 0.20, SEAT_TOP - 0.09), (x0 + 0.90, y0 + 0.50, SEAT_TOP - 0.09)),
              ((x0 + 0.30, y1 - 0.07, 1.30), (x0 + 1.60, y1 - 0.07, 0.30)),
              ((x1 - 0.40, y1 - 0.07, 1.24), (x1 - 1.50, y1 - 0.07, 0.18)),
              ((x1 - 0.07, y0 + 0.40, 1.30), (x1 - 0.07, y1 - 0.70, 0.42)),
              ((x0 + 0.07, y0 + 0.60, 1.10), (x0 + 0.07, y1 - 0.90, 0.26)))
    for i, (a, b) in enumerate(cracks):
        pts = G.zigzag(a, b, n=3, amp=0.16, axis=(0, 0, 1) if i > 1 else (0, 1, 0))
        for j in range(len(pts) - 1):
            G.seam_strip(bm, pts[j], pts[j + 1], width=0.11, thick=0.09, segs=4, bulge=0.5)
    G.part("Cracks", bm, c, "IceDark", (0.0, 0.0, SEAT_TOP), parent="IceBlock")

    bm = bmesh.new()                                    # two shards leaning out of the top
    G.crystal_spire(bm, (x1 - 0.85, y0 + 0.55, SEAT_TOP - 0.20), height=2.05, radius=0.34,
                    segs=6, taper=0.56, tip=0.36, rot=G.rot_euler(-16, 12, 0))
    G.crystal_spire(bm, (x0 + 1.05, y0 + 0.30, SEAT_TOP - 0.22), height=1.45, radius=0.26,
                    segs=6, taper=0.58, tip=0.34, rot=G.rot_euler(-10, -20, 0))
    # icicles hanging UNDER the lip the top slab makes - at the old floor-level z they
    # pointed straight through the ground plane
    G.icicle_row(bm, (x0 + 0.70, y1 + 0.10, SEAT_TOP - 0.40),
                 (x1 - 0.70, y1 + 0.10, SEAT_TOP - 0.40), count=5,
                 length=0.42, radius=0.10, seed=5, vary=0.40, segs=5)
    G.part("Shards", bm, c, "Ice", (0.0, 0.0, SEAT_TOP), parent="IceBlock")

    bm = bmesh.new()                                    # a low snow drift round the base
    # A `rock` reaches radius * (1 + jitter) * scale, so each bank is lifted to at least
    # that in z or it sinks through the floor, and kept under ~0.9 or the drift ends up
    # wider than the block it is banked against.
    drift = ((x0 + 0.55, y1 - 0.45, 0.32, 0.85, 1), (x1 - 0.50, y0 + 0.85, 0.30, 0.80, 1),
             (SEAT_C[0] - 0.35, y0 + 0.40, 0.30, 0.78, 1),
             (x1 - 0.40, y1 + 0.20, 0.20, 0.50, 0),
             (x0 + 0.70, y1 + 0.10, 0.18, 0.42, 0))     # the last two are cheap chips
    for i, (dx, dy, dz, r, sub) in enumerate(drift):
        G.rock(bm, (dx, dy, dz), r, seed=30 + i, jitter=0.24, subdiv=sub,
               scale=(1.0, 0.85, 0.30))
    G.part("Drift", bm, c, "FurWhite", (0.0, 0.0, 0.0), parent="IceBlock")
    return c
