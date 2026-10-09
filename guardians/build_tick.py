"""Toyland biome guardian 9/10: TICK, the tin wind-up soldier that runs down mid-chase.

Reference sheet: a red barrel body with a big cream five-point star painted across the
chest, a blue collar band at the top and a blue belt band at the bottom, both studded
with brass bolts.  The head is a cream dome on a cream collar whose only eye is a cyan
visor slot; a small brass finial and a yellow bulb sit on top of it.  A huge brass
clock key - a shaft and two flat ring loops 2.56 studs across - stands out of its upper
back on a brass winder housing, high enough that its loops top the dome and read from
dead in front.  The arms are a blue shoulder ball, a cream upper arm and forearm riveted
at the elbow, and a red mitten fist, one raised and one down.  The legs are stubby and
blue with a brass bolt at each knee and big rounded blue feet.  Run down, it sits
slumped in a nest of ABC blocks with its back against them, its key standing clear above.
"""
import bmesh, math

COLLECTION = "Tick"
GUARDIAN = "Tick"
SEAT = "Tick_Seat"

NOTES = (
    "9.10 studs to the top of the bulb, 3.98 across the shoulders and fists and 2.99 "
    "deep - SPEC wants 9 on a 4 x 3 footprint, so it fits on all three axes.  Faces +Y. "
    "Rig: Root at waist height carries the Body and both legs (so the barrel leans "
    "without dragging the legs with it); the Body carries the two blue bands, every "
    "brass bolt, the tin seam, the chest star, the winder housing, the key, the head and "
    "both shoulder balls; each shoulder ball carries its own arm chain.  The KEY is the "
    "signature and it is built to READ: the bow is 2.56 studs across (wider than the "
    "2.24 barrel) and 1.48 tall, and it is mounted HIGH - a BrassDark winder housing "
    "crimps into the collar band at the back of the barrel and straps up behind the head "
    "to carry the shaft boss at z 7.58, above the shoulder balls and the collar line - "
    "so the top of the loops sits at z 8.32, 0.16 above the top of the cream dome, 0.29 "
    "of each loop stands proud of the dome's silhouette on either side, and the crown of "
    "the bow is clear sky from a dead-on front view as well as from three-quarters.  The "
    "Key's pivot is ON ITS OWN SHAFT AXIS - x 0, z 7.58, where the shaft leaves the boss "
    "- and the shaft runs dead along -Y, so ry alone spins the bow about the shaft, in "
    "place: it never swings around the torso (see Wind, a full 210 degrees of rewind).  "
    "Its bow is two flat pressed-tin annuli (capless lathes) lying in the XZ plane, i.e. "
    "the loops' faces look along +-Y: that way the rings read BROADSIDE from the hero "
    "camera at yaw 24 instead of edge-on, they stay broadside through a whole turn of "
    "the wind, and only the bow's 0.15 thickness - not its 2.56 diameter - counts toward "
    "the model's depth.  Two clearances hold the mounting up: the housing strap's front "
    "face is y -1.20 and the furthest the dome's back reaches in any pose is y -1.12 "
    "(Run, head rx +7), so the head never touches it; and the bow's own front face is "
    "y -1.65, half a stud behind that.  A pose must not roll the bow much past 30 "
    "degrees if the render is a dead-on one - at ry -55 the loops turn edge-on and hide "
    "behind the head again, which is why Awake winds only 25 (0.24 proud) and the big "
    "angles live in Run and Wind.  The barrel and the dome are lathes and everything stuck to them is placed "
    "on their real radius by _barrel_r() / _dome_r(): the bolts are half-buried in the "
    "bands, and the visor and its frame are CURVED bands (an annular arc extruded in z) "
    "rather than flat plates, because a flat plate across a 2-stud dome stands half a "
    "stud off the surface by the time it reaches its own ends.  The cyan slot is the "
    "only eye; it stands 0.09 proud of the BlueDark frame that rings it, and SLEEP_LOOK "
    "darkens VisorGlow and Bulb together.  The head lathe starts with a hidden neck "
    "stub at z 5.80, inside the collar band, so a drooped head never opens a notch at "
    "the back of its neck.  The character's RIGHT is +X, which is screen-LEFT in a "
    "render: the fist punched overhead in Awake is the one on the LEFT of the frame.  "
    "The seat is a nest, not a perch - three ABC blocks with one more stacked on each "
    "end, two high and all askew - and the guardian sits on the FLOOR against it, legs "
    "straight out like a dropped doll, its barrel resting on the middle block (0.03 of "
    "air) and the key - now mounted high on its back - sweeping clear over the two top "
    "ones with 1.33 studs of air under the bow.  That is "
    "deliberate: a rigid tin body with a tall dome head cannot fold at the waist "
    "without diving off a perch, so the slump lives in the neck and the sprawl, and "
    "sitting at floor level is what brings it to 6.7 studs against the 6.0 in SPEC.  "
    "Every pose was replayed numerically outside Blender with the real Euler XYZ order: "
    "the lowest probe is z 0.00 (Sit, the thighs lying on the floor), 0.01 (Awake), "
    "0.01 (Run, which dips the Root 0.10 to plant the trailing boot) and 0.00 (Wind), "
    "and no probe lands inside a seat block."
)

# ---------------------------------------------------------------- the skeleton
WAIST_Z = 2.55                      # the Body pivot: the bottom of the barrel, on the hips
HIP = (0.60, 0.00, 2.52)            # +x side; every ± value below is written positive
KNEE = (0.60, 0.02, 1.70)
ANKLE = (0.60, 0.06, 0.88)
SHOULDER = (1.22, 0.00, 5.70)
ELBOW = (1.44, 0.05, 4.52)
WRIST = (1.57, 0.08, 3.46)
FIST_C = (1.60, 0.12, 3.06)

BELT_Z = 2.68                       # the blue band round the foot of the barrel
COLLAR_Z = 5.87                     # the blue band round its shoulders
NECK_Z = 6.22                       # the Head pivot, at the foot of the cream collar
DOME_TOP = 8.16
FINIAL_Z = 8.06
BULB_C = (0.0, 0.0, 8.76)

# the wind-up key: a shaft straight back along -Y and a flat two-loop bow on the end.
# It is the signature of the character, so it is mounted HIGH and built BIG.  A brass
# winder housing crimps into the collar band and straps up the back behind the head, and
# the shaft leaves it along -Y at z 7.58 - above the shoulder balls, above the collar
# line - so nothing of the body is in front of the bow.  The bow is 2.56 across and 1.48
# tall and the top of its loops is z 8.32, 0.16 ABOVE the top of the cream dome: from a
# dead-on front view 0.29 of brass stands proud of the dome's silhouette on each side
# and the whole crown of the bow is against the sky, and from three-quarters all of it
# clears the body.  The bow lies in the XZ plane - the loops' flat faces look along +-Y
# - so the rings read BROADSIDE from the camera instead of edge-on, they stay broadside
# through a whole turn of the wind, and only the bow's 0.15 thickness, not its 2.56
# diameter, counts toward the model's depth.
KEY_HUB = (0.0, -1.44, 7.58)        # ON THE SHAFT AXIS - this is the Key pivot
KEY_END = (0.0, -1.70, 7.58)        # where the shaft meets the bow
KEY_COL = (-1.32, -1.20)            # the housing strap up the back: back face, front face
KEY_FOOT = ((-0.38, -1.30, 5.16), (0.38, -0.86, 6.10))   # crimped into the collar band
KEY_LOOP_X = 0.54                   # loop centres, mirrored in x
KEY_LOOP_Y = -1.72                  # the plane the bow lies in
KEY_LOOP_R = 0.74                   # so the bow is 2.56 across, up from 2.28
KEY_LOOP_RIN = 0.42                 # the hole in each loop, up from 0.30
KEY_LOOP_T = 0.15                   # pressed tin: the loops are thin flat plates

# The red barrel, as (radius, z) on its silhouette.  Everything stuck to the body is
# placed against this, not against a guessed cylinder.
BARREL = [(0.92, 2.42), (1.06, 2.62), (1.12, 3.58), (1.10, 4.60), (1.02, 5.46),
          (0.96, 5.94), (0.86, 6.12)]
# the cream head dome, likewise.  The first ring is a NECK STUB buried inside the blue
# collar band: without it, a drooped head in Sit swings its collar clear of the band and
# opens a notch at the back of the neck.
HEAD = [(0.58, 5.80), (0.66, 6.22), (0.74, 6.34), (0.74, 6.62), (0.95, 6.78),
        (0.99, 7.30), (0.95, 7.68), (0.78, 7.96), (0.44, 8.12)]


def _on(curve, z):
    """Radius of a (radius, z) silhouette at height z, clamped at both ends."""
    if z <= curve[0][1]:
        return curve[0][0]
    for (r0, z0), (r1, z1) in zip(curve, curve[1:]):
        if z <= z1:
            return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    return curve[-1][0]


def _barrel_r(z):
    return _on(BARREL, z)


def _dome_r(z):
    return _on(HEAD, z)


def _profile(curve, z0):
    """A world (radius, z) silhouette as a lathe profile relative to z0, capped at both
    ends with a pole so the part comes out solid."""
    return ([(0.0, curve[0][1] - z0)] + [(r, z - z0) for (r, z) in curve]
            + [(0.0, curve[-1][1] - z0 + 0.04)])


STAR_C = (0.0, _barrel_r(4.30) - 0.12, 4.30)      # the chest star, sunk into the curve
VISOR_Z = 7.24
FOOT_Y0, FOOT_Y1 = -0.52, 1.04    # the boot round the ankle: only 0.58 of heel behind
FOOT_H = 0.78                     # it, so a seated leg can stand the boot on its heel
# the back face of the winder housing's foot, where the four little bolts sit
KEY_PLATE_C = (0.0, KEY_FOOT[0][1], (KEY_FOOT[0][2] + KEY_FOOT[1][2]) / 2.0)
KEY_PLATE_FACE = KEY_PLATE_C[1]


# ---------------------------------------------------------------- the four states
POSES = {
    # run down: sitting in the nest of blocks, the barrel tipped back on to the middle
    # one (rx +5 leans an upright part AWAY from +Y - Blender XYZ is Rz@Ry@Rx, so a
    # piece pointing up swings its top toward -Y on a positive rx), legs straight out
    # along the floor like a dropped doll, head drooped forward and cocked, hands fallen
    # into its lap.  A rigid tin body cannot fold at the waist without diving off its
    # seat, so the slump is in the neck and the sprawl, not in the spine.
    "Sit": {
        "Body": (5, 0, -4), "Head": (-30, 0, 12),
        "LegUpper_R": (86, 0, 7), "LegUpper_L": (86, 0, -7),
        "LegLower_R": (4, 0, 0), "LegLower_L": (4, 0, 0),
        "Foot_R": (22, 0, 0), "Foot_L": (22, 0, 0),     # boots stood on their heels
        "ArmUpper_R": (14, -10, 0), "ArmUpper_L": (11, 10, 0),
        "ArmLower_R": (20, 0, 0), "ArmLower_L": (24, 0, 0),
        "Key": (0, -14, 0),
    },
    # the sheet's hero pose: chest out, visor up, right fist punched overhead, left arm
    # swung back, key a quarter wound - and no further, because the hero render is shot
    # from dead in front and a bow rolled much past 30 degrees turns edge-on to the
    # camera and hides behind the head (ry -25 keeps 0.24 of each loop proud of the dome,
    # ry -55 left only 0.06)
    "Awake": {
        "Body": (6, 0, 0), "Head": (5, 0, 0),
        "ArmUpper_R": (152, -16, 0), "ArmLower_R": (-26, 0, 0),
        "ArmUpper_L": (-20, 16, 0), "ArmLower_L": (12, 0, 0),
        "LegUpper_R": (12, 0, 0), "LegLower_R": (-12, 0, 0),
        "LegUpper_L": (-9, 0, 0), "Foot_L": (9, 0, 0),
        "Key": (0, -25, 0),
    },
    # the six-second sprint: a stiff tin march, the key spinning down
    "Run": {
        "Body": (-11, 0, 0), "Head": (7, 0, 0),
        "LegUpper_R": (42, 0, 0), "LegLower_R": (-34, 0, 0), "Foot_R": (4, 0, 0),
        "LegUpper_L": (-30, 0, 0), "LegLower_L": (10, 0, 0), "Foot_L": (28, 0, 0),
        "ArmUpper_R": (-44, -8, 0), "ArmLower_R": (-26, 0, 0),
        "ArmUpper_L": (46, 8, 0), "ArmLower_L": (-30, 0, 0),
        "Key": (0, -120, 0),
    },
    # the signature: the spring being wound, key cranking round, fists tucked in and
    # the whole body twisting against it
    "Wind": {
        "Body": (4, 0, -9), "Head": (-6, 0, 10),
        "ArmUpper_R": (34, -10, 0), "ArmLower_R": (-64, 0, 0),
        "ArmUpper_L": (34, 10, 0), "ArmLower_L": (-64, 0, 0),
        "LegUpper_R": (-6, 0, 0), "LegUpper_L": (-6, 0, 0),
        "Foot_R": (6, 0, 0), "Foot_L": (6, 0, 0),
        "Key": (0, -210, 0),
    },
}
# Sit drops the whole rig to the floor of the block nest: -2.12 lands the thighs exactly
# on the ground on their own 0.40 radius, and the 5-degree lean back brings the barrel to
# within 0.03 of the middle block.  Run dips 0.10 to plant the trailing boot.
POSE_LOC = {"Sit": {"Root": (0.0, 0.0, -2.12)},
            "Run": {"Root": (0.0, 0.0, -0.10)}}


def build(G):
    _guardian(G)
    _seat(G)
    return G.coll(COLLECTION)


# ================================================================= the guardian
def _guardian(G):
    c = G.begin(COLLECTION, GUARDIAN)

    G.root_part(c, (-0.62, -0.52, WAIST_Z - 0.45), (0.62, 0.52, WAIST_Z + 0.45))
    G.hitbox(c, (-2.05, -1.95, 0.0), (2.05, 1.32, 9.15), pivot=(0, 0, WAIST_Z),
             parent="Root")

    _body(G, c)
    _bands(G, c)
    _star(G, c)
    _key(G, c)
    _head(G, c)
    _face(G, c)
    for side in (+1, -1):
        _arm(G, c, side)
        _leg(G, c, side)


def _body(G, c):
    """The red tin barrel, and the crimp seams where its pressed halves are joined."""
    bm = bmesh.new()
    G.lathe(bm, _profile(BARREL, WAIST_Z), segs=12,
            matrix=G.place((0.0, 0.0, WAIST_Z)))
    G.part("Body", bm, c, "Red", (0.0, 0.0, WAIST_Z), parent="Root")

    bm = bmesh.new()                                  # the crimp seams, only where the
    for s in (+1, -1):                                # red actually shows between bands
        zs = [3.05, 3.70, 4.30, 4.95, 5.60]
        G.tube(bm, [(s * (_barrel_r(z) - 0.01), 0.0, z) for z in zs],
               [0.075] * len(zs), segs=4)
    G.torus(bm, (0.0, 0.0, 4.30), _barrel_r(4.30) + 0.012, 0.055,          # waist crimp
            seg_major=12, seg_minor=4)
    G.part("BodySeam", bm, c, "RedDark", (0.0, 0.0, 4.30), parent="Body")


def _bands(G, c):
    """The blue collar and belt bands, and every brass bolt on the toy."""
    bm = bmesh.new()
    G.lathe(bm, [(0.0, -0.27), (1.02, -0.27), (1.10, -0.15), (1.10, 0.15),
                 (0.92, 0.31), (0.80, 0.39), (0.0, 0.39)], segs=12,
            matrix=G.place((0.0, 0.0, COLLAR_Z)))
    G.part("CollarBand", bm, c, "Blue", (0.0, 0.0, COLLAR_Z), parent="Body")

    bm = bmesh.new()
    G.lathe(bm, [(0.0, -0.38), (1.06, -0.38), (1.16, -0.24), (1.16, 0.24),
                 (1.06, 0.36), (0.0, 0.36)], segs=12,
            matrix=G.place((0.0, 0.0, BELT_Z)))
    G.part("BeltBand", bm, c, "Blue", (0.0, 0.0, BELT_Z), parent="Body")

    bm = bmesh.new()                                  # 8 bolts on each band...
    for z, rad in ((COLLAR_Z, 1.14), (BELT_Z, 1.20)):
        for (x, y) in G.ring_slots(8, rad, phase_deg=22.5):
            G.hex_prism(bm, (x, y, z), 0.14, 0.17, axis=(x, y, 0.0), sides=6)
    for (x, z) in G.ring_slots(4, 0.26, phase_deg=45.0, center=(0.0, KEY_PLATE_C[2])):
        G.hex_prism(bm, (x, KEY_PLATE_FACE - 0.02, z), 0.10, 0.14, axis=(0, -1, 0),
                    sides=6)                 # ...and four riveting the winder housing on
                                             # (0.09 proud of its back face, 0.05 buried)
    G.part("Bolts", bm, c, "Brass", (0.0, 0.0, 4.30), parent="Body")


def _star(G, c):
    """The big cream five-point star stamped across the chest.  It is a thick plate, so
    the BACK face stays buried in the barrel all the way out to the points (no gap where
    the curve falls away) and the star reads as embossed tin: 0.09 proud at the middle,
    0.33 at the two side points."""
    bm = bmesh.new()
    G.plate(bm, G.star_pts(5, 0.72, 0.30, phase=math.pi / 2.0), 0.42, at=STAR_C,
            normal=(0, 1, 0))
    G.part("Star", bm, c, "Cream", STAR_C, parent="Body")


def _key(G, c):
    """The clock key: a brass winder housing up the back, a shaft on the Y axis, and a
    flat bow of two big ring loops.  The housing is what RAISES the key - its foot is
    crimped into the collar band on the back of the barrel and its strap climbs behind
    the head to carry the boss at z 7.58, so the bow clears the shoulder balls and the
    dome instead of hiding behind the torso.  The Key pivots on the shaft axis (x 0,
    z 7.58) with the shaft running dead along -Y, so a pose winds it in place: ry alone
    spins the bow about the shaft, it never swings around the body."""
    bm = bmesh.new()
    G.beveled_box(bm, KEY_FOOT[0], KEY_FOOT[1], bevel=0.10)     # crimped into the collar
    G.box(bm, (-0.30, KEY_COL[0], 5.90), (0.30, KEY_COL[1], 7.94))    # the strap up the
    G.barnacle(bm, (0.0, KEY_COL[0], KEY_HUB[2]), normal=(0, -1, 0), r_out=0.40,
               r_in=0.17, height=0.16, segs=8)        # back, and the boss it turns in
    G.part("KeyPlate", bm, c, "BrassDark", (0.0, -1.06, KEY_PLATE_C[2]), parent="Body")

    bm = bmesh.new()
    G.cyl(bm, (0.0, KEY_HUB[1] + 0.10, KEY_HUB[2]), KEY_END, 0.17, segs=8)
    G.ring_band(bm, (0.0, -1.56, KEY_HUB[2]), axis=(0, 1, 0), radius=0.26, minor=0.075,
                seg_major=8, seg_minor=4)             # the collar half way up the shaft
    for s in (+1, -1):                                # two FLAT loops: a capless lathe
        t = KEY_LOOP_T                                # turned to face +-Y, so the rings
        G.lathe(bm, [(KEY_LOOP_RIN, -t / 2), (KEY_LOOP_R, -t / 2), (KEY_LOOP_R, t / 2),
                     (KEY_LOOP_RIN, t / 2), (KEY_LOOP_RIN, -t / 2)], segs=10, cap=False,
                matrix=G.place((s * KEY_LOOP_X, KEY_LOOP_Y, KEY_HUB[2]),
                               rot=G.aim((0, 1, 0))))   # read broadside, not edge-on
    G.part("Key", bm, c, "Brass", KEY_HUB, parent="Body")


def _head(G, c):
    """The cream dome and the cream collar it stands on, then the finial and the bulb."""
    bm = bmesh.new()
    G.lathe(bm, _profile(HEAD, NECK_Z), segs=12, matrix=G.place((0.0, 0.0, NECK_Z)))
    G.part("Head", bm, c, "Cream", (0.0, 0.0, NECK_Z), parent="Body")

    bm = bmesh.new()
    G.lathe(bm, [(0.0, 0.0), (0.30, 0.0), (0.26, 0.10), (0.13, 0.20), (0.17, 0.34),
                 (0.10, 0.44), (0.0, 0.46)], segs=8,
            matrix=G.place((0.0, 0.0, FINIAL_Z)))
    G.part("Finial", bm, c, "Brass", (0.0, 0.0, FINIAL_Z), parent="Head")

    bm = bmesh.new()
    G.ico(bm, BULB_C, 0.34, subdiv=1)
    G.part("Bulb", bm, c, "Bulb", (BULB_C[0], BULB_C[1], BULB_C[2] - 0.32),
           parent="Finial")


def _arc_band(r_in, r_out, half_deg, n=8):
    """A 2-D annular-arc outline centred on +Y, for `prism` - a band that WRAPS a dome
    instead of a flat plate that lifts off it at the ends."""
    a0 = math.radians(90.0 - half_deg)
    a1 = math.radians(90.0 + half_deg)
    out = [(math.cos(a0 + (a1 - a0) * i / (n - 1.0)) * r_out,
            math.sin(a0 + (a1 - a0) * i / (n - 1.0)) * r_out) for i in range(n)]
    out += [(math.cos(a1 + (a0 - a1) * i / (n - 1.0)) * r_in,
             math.sin(a1 + (a0 - a1) * i / (n - 1.0)) * r_in) for i in range(n)]
    return out


def _face(G, c):
    """The one eye: a cyan slot standing proud of a dark frame sunk into the dome.

    A flat `plate` across a 2-stud dome stands half a stud off the surface by the time
    it reaches its own ends, so both pieces are CURVED bands - an annular arc extruded
    in z - whose inner radius stays inside the dome all the way round."""
    def band(half_h):
        """The dome's TIGHTEST radius over a band, so the inner arc never surfaces."""
        return min(_dome_r(VISOR_Z + half_h * t / 4.0) for t in range(-4, 5))

    bm = bmesh.new()
    G.prism(bm, _arc_band(band(0.30) - 0.10, band(0.30) + 0.08, 58.0),
            VISOR_Z - 0.30, VISOR_Z + 0.30)
    G.part("VisorFrame", bm, c, "BlueDark", (0.0, 0.0, VISOR_Z), parent="Head")

    bm = bmesh.new()
    G.prism(bm, _arc_band(band(0.17) - 0.09, band(0.17) + 0.16, 48.0),
            VISOR_Z - 0.17, VISOR_Z + 0.17)
    G.part("Visor", bm, c, "VisorGlow", (0.0, 0.0, VISOR_Z), parent="Head")


def _arm(G, c, s):
    """Blue shoulder ball, cream upper arm and forearm riveted at the elbow, red mitten."""
    tag = "R" if s > 0 else "L"
    sh = (s * SHOULDER[0], SHOULDER[1], SHOULDER[2])
    el = (s * ELBOW[0], ELBOW[1], ELBOW[2])
    wr = (s * WRIST[0], WRIST[1], WRIST[2])
    fist = (s * FIST_C[0], FIST_C[1], FIST_C[2])

    bm = bmesh.new()
    G.ico(bm, sh, 0.44, subdiv=1)
    G.part("Shoulder_" + tag, bm, c, "Blue", sh, parent="Body")

    bm = bmesh.new()
    G.limb(bm, sh, el, 0.31, 0.27, segs=6, bow=(s * 0.03, 0.02, 0))
    G.part("ArmUpper_" + tag, bm, c, "Cream", sh, parent="Shoulder_" + tag)

    bm = bmesh.new()
    G.limb(bm, el, wr, 0.27, 0.25, segs=6, bow=(s * 0.02, 0.03, 0))
    G.part("ArmLower_" + tag, bm, c, "Cream", el, parent="ArmUpper_" + tag)

    bm = bmesh.new()                                  # the rivet the forearm swings on:
    G.hex_prism(bm, (el[0] + s * 0.17, el[1], el[2]), 0.19, 0.44, axis=(s, 0, 0.12),
                sides=6)                              # 0.12 proud, the rest buried
    G.part("Elbow_" + tag, bm, c, "Brass", el, parent="ArmLower_" + tag)

    bm = bmesh.new()
    G.mitten(bm, fist, size=(0.78, 0.66, 0.84), thumb=0.26, bevel=0.16,
             facing=(0, 1, 0))
    G.part("Fist_" + tag, bm, c, "Red", wr, parent="ArmLower_" + tag)


def _leg(G, c, s):
    """Stubby blue legs, a brass bolt on the outside of each knee, big rounded feet."""
    tag = "R" if s > 0 else "L"
    hip = (s * HIP[0], HIP[1], HIP[2])
    knee = (s * KNEE[0], KNEE[1], KNEE[2])
    ankle = (s * ANKLE[0], ANKLE[1], ANKLE[2])

    bm = bmesh.new()
    G.limb(bm, hip, knee, 0.40, 0.36, segs=6)
    G.part("LegUpper_" + tag, bm, c, "Blue", hip, parent="Root")

    bm = bmesh.new()                                  # 0.12 proud of the 0.36 shin
    G.hex_prism(bm, (knee[0] + s * 0.36, knee[1], knee[2]), 0.21, 0.24, axis=(s, 0, 0),
                sides=6)
    G.part("Knee_" + tag, bm, c, "Brass", knee, parent="LegUpper_" + tag)

    bm = bmesh.new()                                  # the shin runs on down INTO the
    G.limb(bm, knee, (ankle[0], ankle[1], 0.62), 0.36, 0.34, segs=6)   # foot, so no gap
    G.part("LegLower_" + tag, bm, c, "Blue", knee, parent="LegUpper_" + tag)

    bm = bmesh.new()
    G.beveled_box(bm, (ankle[0] - 0.48, FOOT_Y0, 0.0), (ankle[0] + 0.48, FOOT_Y1, FOOT_H),
                  bevel=0.30, segments=2)
    G.part("Foot_" + tag, bm, c, "Blue", ankle, parent="LegLower_" + tag)


# ================================================================= the block stack
BLOCK = 1.55
# (part name, role, centre x, centre y, z of the bottom face, yaw degrees)
BLOCKS = [("BlockBlue", "Blue", 0.00, -2.01, 0.00, -4.0, ""),    # the backrest, and root
          ("BlockRed", "Red", -1.62, -1.97, 0.00, 5.0, "A"),
          ("BlockGreen", "BlockGreen", 1.62, -2.05, 0.00, -6.0, "B"),
          # the two upper blocks leave the middle of the wall open for the barrel to lean
          # into, while still resting on ~60 % of their own footprint
          ("BlockYellow", "BlockYellow", -2.06, -2.28, BLOCK, 9.0, "C"),
          ("BlockCream", "Cream", 2.06, -2.33, BLOCK, -11.0, "")]
BALL_C = (2.95, 1.90, 0.54)         # the ball that rolled out of the pile


def _face_of(cx, cy, z0, yaw):
    """The centre of a yawed block's front face, and the normal out of it."""
    a = math.radians(yaw)
    n = (math.sin(a), math.cos(a), 0.0)
    h = BLOCK / 2.0
    return (cx + n[0] * h, cy + n[1] * h, z0 + h), n


def _seat(G):
    """Five ABC blocks with a ball beside them: a three-block wall with one more block
    stacked on each end, two high and every one askew.  It is a BACKREST, not a perch -
    the guardian sits on the floor in front of it and tips back on to the middle block
    (0.03 of air), which is the only way a rigid 9-stud tin toy gets anywhere near the
    6-stud sitting height the spec asks for.  The key rides high on the back now, so in
    Sit its bow swings over the top blocks with 1.33 studs of air under it (lowest point
    of the bow z 4.43, block tops z 3.10) instead of dropping into the notch."""
    c = G.begin(SEAT, GUARDIAN, prefix="TickSeat")

    h = BLOCK / 2.0
    for i, (name, role, cx, cy, z0, yaw, _ltr) in enumerate(BLOCKS):
        bm = bmesh.new()
        G.beveled_box(bm, (cx - h, cy - h, z0), (cx + h, cy + h, z0 + BLOCK),
                      bevel=0.13, rot=G.rot_euler(0, 0, yaw))
        a = math.radians(yaw)
        for (dx, dy) in G.grid_positions(2, 2, 0.74, 0.74):   # moulding pips, yawed with
            G.stud_patch(bm, (cx + dx * math.cos(a) - dy * math.sin(a),   # the block
                              cy + dx * math.sin(a) + dy * math.cos(a), z0 + BLOCK),
                         (0, 0, 1), size=0.26, rise=0.06, bevel=0.0, spin=yaw)
        G.part(name, bm, c, role, (cx, cy, z0),
               parent=None if name == "BlockBlue" else "BlockBlue")

    bm = bmesh.new()                                  # A, B and C on the front faces
    for (name, role, cx, cy, z0, yaw, letter) in BLOCKS:
        if not letter:
            continue
        at, n = _face_of(cx, cy, z0, yaw)
        G.face_text(bm, letter, at, normal=n, height=0.86, radius=0.09, segs=4,
                    depth=0.045)                      # RAISED, not half sunk
    G.part("Letters", bm, c, "Cream", (0.0, -1.35, 1.40), parent="BlockBlue")

    bm = bmesh.new()                                  # the ball that rolled off the pile
    G.ico(bm, BALL_C, 0.54, subdiv=1)
    G.part("Ball", bm, c, "Red", BALL_C, parent="BlockBlue")

    bm = bmesh.new()
    G.ring_band(bm, BALL_C, axis=(0.22, 0.10, 1.0), radius=0.50, minor=0.10,
                seg_major=10, seg_minor=4)
    G.part("BallBand", bm, c, "Cream", BALL_C, parent="Ball")
    return c
