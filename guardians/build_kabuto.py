"""Samurai biome guardian 3/10: KABUTO, the stone oni that steps down off its shrine.

Reference sheet: a squat, immensely heavy blocky statue.  A square head with a heavy
brow, a grimace, deep-set amber glowing eyes and two cream tusks pushing up out of the
lower jaw, with two BIG horns - as long as the skull is tall and nearly half as thick -
sweeping forward and up out of the top corners of the skull to points that stand well
above the crown.  Square shoulders far wider than the hips, with green moss on each
pauldron and on one knee.  Jagged amber crack lines glow down the chest, along both arms
and both legs, like lightning in a channel.  A thick red rope belt with a big knot at
the front and two tassels hanging to the knee; matching red rope bands round one wrist,
one ankle and the club's grip.  Big blocky fists - the right one holds a kanabo, a long
tapering stone club covered in square studs with glowing cracks running up it, planted
butt-down on the ground beside it.  It sleeps slumped on a square stone pedestal under a
red torii, between two lit stone lanterns.
"""
import bmesh, math

COLLECTION = "Kabuto"
GUARDIAN = "Kabuto"
SEAT = "Kabuto_Seat"

NOTES = (
    "9.86 studs to the horn tips (head crown 8.66), 5.00 across the pauldrons (5.64 "
    "with the moss) and 2.8 deep through the body; the Hitbox is the 5.24 x 3.4 x 9.90 "
    "box round the BODY, the club excluded.  The silhouette is a TRIANGLE: the shoulder "
    "line at 5.00 is the widest thing on it, the fists stop at 2.06, the chest at 2.68 "
    "and the hips at 2.68, so it narrows all the way down.  The mass runs BACKWARD - "
    "chest 2.08 deep, pelvis 1.84, pauldrons 2.14 - so the statue reads as heavy from "
    "the side without pushing the face, the chin or the chest crack forward out of the "
    "head's shadow.  The two horns are the other half of the silhouette: 1.28 thick at "
    "the crown corners, 2.27 long (the skull is only 1.32 tall), bowed forward and "
    "dipped below their own chord so each leaves the head almost flat, sweeps over the "
    "brow and hooks UP to a point 1.20 above the crown and 0.56 in front of it.  "
    "The planted kanabo pushes the raw bounding box out to x 3.37 on its right and "
    "y 2.70 in front, as Strawman's staff does, so the BODY is centred on x = 0 while "
    "the reported centre sits about 0.25 right and 0.58 forward - that whole offset is "
    "the club, not the statue.  Faces +Y; the character's RIGHT is +X, which is "
    "screen-LEFT in a render.  "
    "Rig: Root at pelvis height carries Hips and the Hitbox, Hips carries the Torso, the "
    "rope Belt and both legs, Torso carries the Head, both square Pauldrons and both "
    "arms, and the club hangs off Fist_R at its GRIP so a wake animation can lift it.  "
    "Head carries the Jaw (which carries the Tusks, so a roar opens them together), both "
    "Horns and the two Neon eyes.  Every amber crack is a separate Neon part parented to "
    "the block it runs over - chest, both upper arms, both thighs, the club - so the "
    "glow travels with the limb; SLEEP_LOOK darkens EyeGlow to 5c5148 and the pedestal "
    "lanterns to 6b6354.  Moss sits on both pauldrons and the LEFT knee; the rope bands "
    "are on the LEFT wrist and the RIGHT ankle, matching the sheet's asymmetry.  Every "
    "rope that goes ROUND something (belt, wrist, ankle) is a rounded-RECTANGLE loop cut "
    "0.16 larger than the block it wraps, because a circular band on a square limb either "
    "floats off the flat faces or vanishes inside them; the club's grip wrap sits below "
    "and above the fist, never under it.  The kanabo is 1.13 thick at the grip and 1.76 "
    "through its studded head, planted at x 1.56..3.37 and leaning FORWARD (y 1.10 at "
    "the butt to 2.02 at the tip): that forward lean is load-bearing, because the "
    "forearm, the upper arm and the widened pauldron all stop at y 0.84 or less, so a "
    "shaft this fat can only run from the ground to above the shoulder by standing in "
    "front of them - and the right fist is cut 0.30 deeper (to y 1.06) to reach it.  "
    "Sitting he is 6.67 to the crown: perched on the "
    "front half of the 1.6-tall pedestal cap (buttocks resting 0.10 into the stone at "
    "z 1.50, thighs on the cap at 1.55), knees up at 2.19, both soles flat on the ground "
    "at y 2.3 to 4.4 clear of the plinth, and the fists hanging outside its sides at "
    "x 2.3 to 3.4 - which is why the two lanterns stand at y -1.06, beside the BACK half "
    "of the plinth, and not at its front corners where the sleeping hands are.  In Sit "
    "ONLY the club is re-planted on the ground beside the pedestal with a POSE_LOC "
    "offset, because a hand that has come down 1.45 studs would otherwise drive it "
    "straight through the stone."
)

# ---------------------------------------------------------------- the skeleton
# Joints in world space.  Every _R / _L pair is built from the +X value times a side sign.
ROOT_Z = 4.05                       # pelvis centre - the rig root
WAIST_Z = 4.55                      # hips -> torso
BELT_Z = 4.34                       # the rope loop
HIP = (0.80, 0.02, 3.86)            # hips -> thigh
KNEE = (0.86, 0.04, 2.32)
ANKLE = (0.86, 0.06, 0.78)
SHOULDER = (1.56, 0.02, 6.36)       # torso -> upper arm (and the pauldron above it)
ELBOW = (1.58, 0.06, 4.90)
WRIST = (1.56, 0.18, 3.52)
NECK = (0.0, -0.04, 7.02)           # torso -> head
JAW_HINGE = (0.0, -0.50, 7.46)
EYE = (0.44, 0.88, 7.86)
HORN_BASE = (0.86, -0.02, 8.46)     # the top CORNERS of the crown, not its sides
HORN_TIP = (1.46, 1.66, 9.86)       # the top of the whole model - 1.20 clear of the crown
HEAD_TOP = 8.66

# the kanabo: a straight axis from the butt on the ground to the domed tip, gripped
# where the right fist closes on it.  It stands OUT (x 2.1 -> 2.56, clear of a foot that
# ends at 1.42) and FORWARD (y 1.10 -> 2.02), which is the only way a shaft this fat can
# run from the ground to above the shoulder without driving through the forearm, the
# upper arm or the widened pauldron - all of which end at y 0.84 or less.
CLUB_BUTT = (2.10, 1.10, 0.09)      # 0.09, not 0.0: the butt cap is cut square to a
CLUB_TOP = (2.56, 2.02, 6.90)       # shaft leaning 8.2 deg, so its low corner drops
CLUB_GRIP = (2.30, 1.50, 3.06)      # 0.077 - it lands ON the floor, not through it
CLUB_PROFILE = ((0.00, 0.54), (0.10, 0.50), (0.34, 0.52), (0.52, 0.60),
                (0.68, 0.76), (0.84, 0.88), (0.94, 0.85), (1.00, 0.64))
_CD = (CLUB_TOP[0] - CLUB_BUTT[0], CLUB_TOP[1] - CLUB_BUTT[1], CLUB_TOP[2] - CLUB_BUTT[2])
_CL = math.sqrt(_CD[0] ** 2 + _CD[1] ** 2 + _CD[2] ** 2)
CLUB_DIR = (_CD[0] / _CL, _CD[1] / _CL, _CD[2] / _CL)


def _club_at(t):
    """A point on the club axis; t = 0 is the butt on the ground, 1 the domed tip."""
    return (CLUB_BUTT[0] + _CD[0] * t, CLUB_BUTT[1] + _CD[1] * t, CLUB_BUTT[2] + _CD[2] * t)


def _club_r(t):
    """The club's radius at t - thin at the grip, swelling into the studded head."""
    for (t0, r0), (t1, r1) in zip(CLUB_PROFILE, CLUB_PROFILE[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0)
            return r0 + (r1 - r0) * max(0.0, min(1.0, k))
    return CLUB_PROFILE[-1][1]


# ---------------------------------------------------------------- the states
POSES = {
    # asleep on the pedestal: pelvis rolled back, spine rounded, chin on the chest,
    # knees up and forward with the feet flat on the ground, arms hanging outside the
    # plinth, jaw just ajar.  POSE_LOC drops the root 1.45 onto the 1.6-tall stone.
    "Sit": {
        "Hips": (12, 0, 0), "Torso": (-28, 0, 4), "Head": (-26, 0, -5), "Jaw": (-5, 0, 0),
        "Pauldron_R": (0, 11, 0), "Pauldron_L": (0, -11, 0),
        "ArmUpper_R": (10, -18, 0), "ArmUpper_L": (10, 18, 0),
        "ArmLower_R": (6, -6, 0), "ArmLower_L": (6, 6, 0),
        "Fist_R": (-8, 0, 0), "Fist_L": (-8, 0, 0),
        "LegUpper_R": (69, 0, -10), "LegUpper_L": (69, 0, 10),
        "LegLower_R": (-57, 0, 0), "LegLower_L": (-57, 0, 0),
        "Foot_R": (-24, 0, 0), "Foot_L": (-24, 0, 0),
        "Club": (0, 24, 0),
    },
    # the sheet: upright, shoulders squared and shrugged, head up, mouth open in a
    # roar, club still planted but heeled out, the free fist cocked in front of it
    "Awake": {
        "Hips": (-2, 0, 0), "Torso": (-6, 0, 4), "Head": (12, 0, -6), "Jaw": (-22, 0, 0),
        "Pauldron_R": (0, -8, 0), "Pauldron_L": (0, 8, 0),
        "ArmUpper_R": (-7, -5, 0), "ArmLower_R": (5, 0, 0), "Fist_R": (4, 0, 0),
        "ArmUpper_L": (14, 16, 0), "ArmLower_L": (140, 0, 0), "Fist_L": (-8, 0, 0),
        "LegUpper_R": (12, -8, 0), "LegLower_R": (-8, 0, 0), "Foot_R": (-4, 0, 0),
        "LegUpper_L": (-10, 8, 0), "LegLower_L": (12, 0, 0), "Foot_L": (-2, 0, 0),
        "Club": (2, 5, 0),
    },
    # the heavy stone jog: short stride, pelvis counter-twisted, club swung back
    "Run": {
        "Hips": (0, 0, -8), "Torso": (-12, 0, 8), "Head": (8, 0, -8), "Jaw": (-8, 0, 0),
        "ArmUpper_R": (-26, -8, 0), "ArmLower_R": (30, 0, 0), "Club": (-28, 0, -10),
        "ArmUpper_L": (34, 10, 0), "ArmLower_L": (40, 0, 0),
        "LegUpper_R": (34, -4, 0), "LegLower_R": (-40, 0, 0), "Foot_R": (10, 0, 0),
        "LegUpper_L": (-28, 4, 0), "LegLower_L": (30, 0, 0), "Foot_L": (-14, 0, 0),
    },
    # the signature slam wind-up: weight back on the right leg, torso coiled, the club
    # cocked high behind the head with the elbow up beside the ear
    "Slam": {
        "Hips": (4, 0, 12), "Torso": (10, 0, -16), "Head": (-8, 0, -12), "Jaw": (-24, 0, 0),
        "Pauldron_R": (0, -14, 0), "Pauldron_L": (0, 6, 0),
        "ArmUpper_R": (128, 0, -14), "ArmLower_R": (60, 0, 0), "Fist_R": (-12, 0, 0),
        "Club": (185, 0, 10),          # tip up and BEHIND: a wind-up, not a raised bat
        "ArmUpper_L": (-30, 16, 0), "ArmLower_L": (34, 0, 0),
        "LegUpper_R": (-14, -6, 0), "LegLower_R": (16, 0, 0), "Foot_R": (-6, 0, 0),
        "LegUpper_L": (20, 8, 0), "LegLower_L": (-12, 0, 0), "Foot_L": (-8, 0, 0),
    },
}
# down onto the 1.60-tall pedestal, and the club re-planted on the ground beside it
POSE_LOC = {"Sit": {"Root": (0.0, 1.00, -1.45), "Club": (0.05, 0.70, 1.45)}}


def build(G):
    _guardian(G)
    _seat(G)
    return G.coll(COLLECTION)


# ================================================================= shared helpers
def _bx(G, bm, x0, x1, y0, y1, z0, z1, bevel=0.14, rot=None):
    """A box from raw (possibly mirrored) coordinates, so `s * x` never hands
    beveled_box a lo above its hi.  bevel <= 0 drops to a plain 12-tri box."""
    lo = (min(x0, x1), min(y0, y1), min(z0, z1))
    hi = (max(x0, x1), max(y0, y1), max(z0, z1))
    if bevel <= 0.0:
        return G.box(bm, lo, hi, rot)
    return G.beveled_box(bm, lo, hi, bevel=bevel, rot=rot)


def _band(G, bm, center, w, d, z, r=0.13, corner=0.26):
    """One rope band round a BOX limb, at height `z`.

    It has to be a rounded RECTANGLE, not a `ring_band` torus: a circle big enough to
    clear a block's corners floats off its flat faces, and a circle that touches the
    faces disappears inside the block on the other axis.  `w` x `d` is cut about 0.16
    larger than the limb's section, so the rope stands proud the whole way round."""
    ring = G.rounded_rect_pts(w, d, corner, segs=2, center=center)
    pts = [(p[0], p[1], z) for p in ring]
    pts.append(pts[0])
    return G.tube(bm, pts, [r] * len(pts), segs=4)


def _crack(G, bm, a, b, n=6, amp=0.20, axis=(1, 0, 0), r=0.10):
    """One amber crack: a zig-zag polyline lofted into a thin tube that sits half in the
    stone, so it reads as light in a channel rather than a painted line."""
    pts = G.zigzag(a, b, n=n, amp=amp, axis=axis)
    rs = [r * (0.45 if i in (0, n - 1) else 1.0) for i in range(n)]
    return G.tube(bm, pts, rs, segs=4)


# ================================================================= the guardian
def _guardian(G):
    c = G.begin(COLLECTION, GUARDIAN)

    G.root_part(c, (-0.62, -0.52, ROOT_Z - 0.55), (0.62, 0.52, ROOT_Z + 0.55))
    G.hitbox(c, (-2.62, -1.60, 0.0), (2.62, 1.80, 9.90), pivot=(0.0, 0.0, ROOT_Z),
             parent="Root")

    _hips(G, c)
    _belt(G, c)
    _torso(G, c)
    _head(G, c)
    _face(G, c)
    _horns(G, c)
    for side in (+1, -1):
        _pauldron(G, c, side)
        _arm(G, c, side)
        _leg(G, c, side)
    _ropes(G, c)
    _club(G, c)


def _hips(G, c):
    """A short heavy pelvis block: the narrow half of the silhouette.  Its extra mass is
    all at the BACK (y -1.10 against a front face still at 0.74) - a statue this heavy
    has to be deep, but pushing the front out would bury the belt knot and shove the
    chest in front of the chin."""
    bm = bmesh.new()
    G.beveled_box(bm, (-1.12, -1.10, 3.46), (1.12, 0.74, 4.58), bevel=0.22)
    G.beveled_box(bm, (-0.94, -1.00, 3.16), (0.94, 0.66, 3.60), bevel=0.16)   # the crotch
    for s in (+1, -1):                                                        # hip flares
        _bx(G, bm, s * 1.02, s * 1.34, -0.94, 0.60, 3.62, 4.40, bevel=0.14)
    G.part("Hips", bm, c, "Stone", (0.0, 0.0, ROOT_Z), parent="Root")

    bm = bmesh.new()                       # recessed sides, so the block reads as a block
    for s in (+1, -1):
        _bx(G, bm, s * 1.28, s * 1.40, -0.76, 0.44, 3.72, 4.30, bevel=0.0)
    G.box(bm, (-0.86, -1.16, 3.60), (0.86, -1.06, 4.46))                      # back slab
    G.box(bm, (-0.34, -1.02, 3.12), (0.34, 0.66, 3.26))                       # under-seam
    G.part("HipSides", bm, c, "StoneDark", (0.0, 0.0, ROOT_Z), parent="Hips")


def _belt(G, c):
    """A fat red rope round the waist, a fist-sized knot at the front, and two tassels
    that hang to the knee.  Hung off the hips so the knot swings with the pelvis."""
    bm = bmesh.new()
    # the loop is cut WIDER and DEEPER than the pelvis (which is 2.68 x 1.84 with its
    # flares) so the rope stands proud of the stone on all four faces instead of being
    # swallowed by it - it only reads as a rope if it bulges out of the block.
    ring = G.rounded_rect_pts(2.96, 2.08, 0.52, segs=3, center=(0.0, -0.18))
    pts = [(p[0], p[1], BELT_Z) for p in ring]
    pts.append(pts[0])                                   # close the loop under the knot
    G.tube(bm, pts, [0.20] * len(pts), segs=5)
    G.beveled_box(bm, (-0.36, 0.86, 4.06), (0.36, 1.30, 4.64), bevel=0.12)     # the knot
    G.box(bm, (-0.56, 0.94, 4.24), (0.56, 1.18, 4.48))                         # its wrap
    for s in (+1, -1):                                                         # loose ends
        G.tassel(bm, (s * 0.30, 1.14, 4.14), length=1.70, n=2, width=0.17, spread=0.16,
                 seed=6 + (s > 0))
    G.part("Belt", bm, c, "Rope", (0.0, 0.0, BELT_Z), parent="Hips")


def _torso(G, c):
    """Three stacked slabs widening from the waist to the collar shelf, flat across the
    front so the chest crack has a clean face to burn down."""
    bm = bmesh.new()
    G.beveled_box(bm, (-1.06, -1.06, 4.42), (1.06, 0.78, 5.40), bevel=0.22)    # belly
    G.beveled_box(bm, (-1.22, -1.20, 5.28), (1.22, 0.78, 6.20), bevel=0.24)    # ribs
    G.beveled_box(bm, (-1.34, -1.30, 6.02), (1.34, 0.78, 7.06), bevel=0.24)    # collar
    G.box(bm, (-0.46, -0.62, 6.96), (0.46, 0.40, 7.20))                        # neck stub
    G.part("Torso", bm, c, "Stone", (0.0, 0.0, WAIST_Z), parent="Hips")

    bm = bmesh.new()
    for s in (+1, -1):
        _bx(G, bm, s * 1.28, s * 1.40, -1.14, 0.62, 6.18, 6.92, bevel=0.0)     # side recess
        _bx(G, bm, s * 1.00, s * 1.14, -0.98, 0.50, 4.60, 5.30, bevel=0.0)     # flank groove
    # the spine plate is cut in two courses because the ribs' back face is at -1.20 and
    # the collar's at -1.30: one slab across both would float clear of the lower one
    G.box(bm, (-1.12, -1.26, 5.42), (1.12, -1.14, 6.06))                       # spine, ribs
    G.box(bm, (-1.12, -1.36, 6.00), (1.12, -1.24, 6.90))                       # spine, collar
    G.box(bm, (-1.20, -1.20, 5.96), (1.20, 0.84, 6.08))                        # chest shelf
    G.part("TorsoDark", bm, c, "StoneDark", (0.0, 0.0, WAIST_Z), parent="Torso")

    bm = bmesh.new()                       # ONE bold lightning crack down the chest
    # Three cracks of seven and five short segments read as a scribble at 100 studs, which
    # is exactly the distance this has to work at.  One main bolt of THREE long segments
    # (n=4) at nearly half again the amplitude and half again the width, plus a single
    # fork of two segments, says "cracked stone" with a fifth of the line-work.
    _crack(G, bm, (0.30, 0.78, 6.94), (-0.30, 0.78, 4.62), n=4, amp=0.36, axis=(1, 0, 0),
           r=0.16)
    _crack(G, bm, (-0.30, 0.78, 5.70), (-1.02, 0.76, 5.02), n=3, amp=0.24, axis=(0, 0, 1),
           r=0.13)
    G.part("CracksTorso", bm, c, "EyeGlow", (0.30, 0.78, 6.94), parent="Torso")


def _head(G, c):
    """A square skull under a shelf of a brow, with a heavy chin block on a hinge."""
    bm = bmesh.new()
    G.beveled_box(bm, (-0.94, -0.96, 7.34), (0.94, 0.90, 8.52), bevel=0.22)    # skull
    G.beveled_box(bm, (-0.86, -0.90, 8.44), (0.86, 0.82, HEAD_TOP), bevel=0.12)  # crown
    G.beveled_box(bm, (-1.00, 0.66, 8.08), (1.00, 1.10, 8.44), bevel=0.14)     # the brow
    G.beveled_box(bm, (-0.48, 0.80, 7.34), (0.48, 1.04, 7.80), bevel=0.10)     # upper lip
    for s in (+1, -1):                                                         # blunt ears
        _bx(G, bm, s * 0.92, s * 1.16, -0.40, 0.24, 7.58, 8.12, bevel=0.0)
    G.part("Head", bm, c, "Stone", NECK, parent="Torso")

    bm = bmesh.new()
    G.beveled_box(bm, (-0.80, -0.62, 6.98), (0.80, 0.98, 7.30), bevel=0.16)    # jaw
    G.beveled_box(bm, (-0.56, 0.74, 6.84), (0.56, 1.08, 7.24), bevel=0.12)     # chin
    G.part("Jaw", bm, c, "Stone", JAW_HINGE, parent="Head")

    bm = bmesh.new()                       # two stout tusks up off the lower jaw
    # They sweep OUT as they rise (tip at x 0.92 against an eye whose outer edge is at
    # 0.67) so they frame the face instead of crossing the glowing eyes, which is what a
    # tusk rising straight up in front of the socket would do.
    for s in (+1, -1):
        G.horn(bm, (s * 0.56, 0.90, 7.14), (s * 0.92, 1.06, 7.88), r0=0.19, r1=0.04,
               bow=(s * 0.12, 0.16, 0.06), n=5, segs=5)
    G.part("Tusks", bm, c, "Tusks", (0.0, 0.90, 7.14), parent="Jaw")


def _face(G, c):
    """The dark recesses the eyes burn in: sockets, brow shadow, grimace, cheek grooves."""
    # Every one of these has to STRADDLE the surface it darkens - the skull's face is at
    # y 0.90 and its cheek at x 0.94, so a panel drawn wholly inside those numbers is
    # simply not there.  The eye sockets stop at y 0.94 because the Neon eye's own front
    # face is at 0.97 and has to stay in front of its pit.
    bm = bmesh.new()
    for s in (+1, -1):
        _bx(G, bm, s * 0.16, s * 0.74, 0.80, 0.94, 7.68, 8.04, bevel=0.0)      # socket
        _bx(G, bm, s * 0.88, s * 1.00, 0.28, 0.84, 7.44, 7.94, bevel=0.0)      # cheek groove
    G.box(bm, (-1.00, 0.90, 8.00), (1.00, 1.12, 8.10))                         # brow shadow
    G.box(bm, (-0.64, 0.72, 7.24), (0.64, 1.06, 7.40))                         # the grimace
    G.part("Face", bm, c, "Cracks", (0.0, 0.84, 7.82), parent="Head")

    for s, tag in ((+1, "R"), (-1, "L")):
        bm = bmesh.new()
        G.hex_prism(bm, (s * EYE[0], EYE[1], EYE[2]), 0.23, 0.18,
                    axis=(s * 0.22, 1.0, 0.10), sides=6)
        G.part("Eye_" + tag, bm, c, "EyeGlow", (s * EYE[0], EYE[1], EYE[2]), parent="Head")


def _horns(G, c):
    """Two BIG horns out of the top corners of the skull, sweeping forward and up.

    These are half the silhouette, so they are built to dominate it: a base radius of
    0.64 (the horn is 1.28 thick where it leaves the crown, against a skull only 1.88
    wide, so the two bases nearly meet across the top) tapering over 2.27 studs - longer
    than the 1.32-tall skull - to a point 1.20 ABOVE the crown and 0.56 in front of the
    brow.  The bow dips the middle BELOW the chord (-0.22 in z) and pushes it forward
    (+0.52 in y), so each horn leaves the head almost horizontally, sweeps out over the
    face and then hooks up: from the front that is a pair of curved spikes standing over
    the skull, which is what the sheet shows - not a nub reading as an ear."""
    for s, tag in ((+1, "R"), (-1, "L")):
        base = (s * HORN_BASE[0], HORN_BASE[1], HORN_BASE[2])
        bm = bmesh.new()
        # horn() spelled out as its own chain_points + tube, which is all it is: the
        # curve needs a bow with a NEGATIVE z and the dry run reads a bare (x, y, z)
        # keyword as a point, so passing it would drop a phantom -0.22 into the reported
        # bounding box and make a model that never leaves the floor look like it does.
        pts = G.chain_points(base, (s * HORN_TIP[0], HORN_TIP[1], HORN_TIP[2]), 6,
                             bow=(s * 0.14, 0.52, -0.22))
        G.tube(bm, pts, G.taper(0.64, 0.07, 6, power=1.25), segs=6)
        G.hex_prism(bm, (s * 0.88, 0.04, 8.52), 0.70, 0.28, axis=(s * 0.30, 0.78, 0.56),
                    sides=6)                                       # the carved base collar
        G.part("Horn_" + tag, bm, c, "Stone", base, parent="Head")


def _pauldron(G, c, s):
    """An ENORMOUS square shoulder slab tilted out over the arm, mossed on top.

    The oni on the sheet is a triangle - the shoulder line is the widest thing on it and
    everything below narrows away - so the slab runs out to x 2.44 and the rim to 2.50,
    0.48 further out per side than the box-man version, against a chest half-width of
    1.34 and a fist that stops at 2.06.  It is also taller: 5.86 -> 7.48 is 1.62 of
    vertical mass where it was 1.12, which is what stops a wide slab reading as a thin
    shelf from the front."""
    tag = "R" if s > 0 else "L"
    sh = (s * SHOULDER[0], SHOULDER[1], SHOULDER[2])

    bm = bmesh.new()
    _bx(G, bm, s * 0.92, s * 2.44, -1.30, 0.84, 6.42, 7.46, bevel=0.18,
        rot=G.rot_euler(0, s * 12, 0))
    _bx(G, bm, s * 1.10, s * 2.34, -1.18, 0.72, 5.86, 6.48, bevel=0.16,
        rot=G.rot_euler(0, s * 12, 0))                              # the lower course
    _bx(G, bm, s * 2.36, s * 2.50, -1.30, 0.84, 6.16, 7.48, bevel=0.0)   # the outer rim
    for z in (6.66, 6.96, 7.26):                                   # square rivets
        G.stud_patch(bm, (s * 1.66, 0.84, z), (0.0, 1.0, 0.16), size=0.26, rise=0.09,
                     sink=0.06, bevel=0.0)
    G.part("Pauldron_" + tag, bm, c, "Stone", sh, parent="Torso")

    bm = bmesh.new()
    top = (s * 1.62, 0.10, 7.44)
    G.patch(bm, top, normal=(s * 0.22, 0.0, 1.0), radius=0.58, height=0.13,
            seed=21 + (s > 0), jitter=0.26, segs=7)
    G.patch(bm, (s * 2.50, 0.30, 7.02), normal=(s * 1.0, 0.12, 0.35), radius=0.32,
            height=0.10, seed=31 + (s > 0), jitter=0.30, segs=6)   # ON the rim, not in it
    G.patch(bm, (s * 1.14, -0.80, 7.40), normal=(s * 0.10, -0.20, 1.0), radius=0.30,
            height=0.09, seed=41 + (s > 0), jitter=0.30, segs=6)
    G.part("Moss_" + tag, bm, c, "Moss", top, parent="Pauldron_" + tag)


def _arm(G, c, s):
    """Blocky stone arm: square upper, narrower forearm, big fist, one glowing crack."""
    tag = "R" if s > 0 else "L"
    sh = (s * SHOULDER[0], SHOULDER[1], SHOULDER[2])
    el = (s * ELBOW[0], ELBOW[1], ELBOW[2])
    wr = (s * WRIST[0], WRIST[1], WRIST[2])

    bm = bmesh.new()
    _bx(G, bm, s * 1.14, s * 1.98, -0.74, 0.52, 4.84, 6.50, bevel=0.22)
    G.hex_prism(bm, (s * 1.56, 0.02, 6.44), 0.50, 0.96, axis=(1.0, 0.0, 0.08), sides=6)
    _bx(G, bm, s * 1.12, s * 2.00, -0.80, 0.62, 4.70, 4.96, bevel=0.0)     # the elbow band
    G.part("ArmUpper_" + tag, bm, c, "Stone", sh, parent="Torso")

    bm = bmesh.new()
    _crack(G, bm, (s * 1.98, 0.04, 6.28), (s * 1.94, 0.10, 4.98), n=6, amp=0.20,
           axis=(0, 1, 0), r=0.09)
    G.part("CracksArm_" + tag, bm, c, "EyeGlow", (s * 1.98, 0.04, 6.28),
           parent="ArmUpper_" + tag)

    bm = bmesh.new()
    _bx(G, bm, s * 1.20, s * 1.92, -0.64, 0.56, 3.30, 4.90, bevel=0.20)
    _bx(G, bm, s * 1.24, s * 1.88, 0.52, 0.66, 3.62, 4.58, bevel=0.0)      # a raised vein
    G.part("ArmLower_" + tag, bm, c, "Stone", el, parent="ArmUpper_" + tag)

    bm = bmesh.new()
    # The fist reaches FORWARD to y 1.06, not just down: the kanabo now stands clear of
    # the body at y 0.94 to 2.07 where the hand grips it, and a fist that stopped at the
    # old y 0.76 would be holding nothing but air.  It makes both fists big square blocks,
    # which is what the sheet shows anyway.
    _bx(G, bm, s * 1.10, s * 2.06, -0.40, 1.06, 2.58, 3.54, bevel=0.20)
    for z in (2.86, 3.10, 3.34):                                           # knuckles
        _bx(G, bm, s * 1.14, s * 2.02, 1.00, 1.18, z - 0.09, z + 0.09, bevel=0.0)
    _bx(G, bm, s * 1.00, s * 1.24, 0.30, 0.94, 2.74, 3.08, bevel=0.0)      # the thumb
    G.part("Fist_" + tag, bm, c, "Stone", wr, parent="ArmLower_" + tag)


def _leg(G, c, s):
    """Short heavy legs, a crack down each outer thigh, moss on the left knee."""
    tag = "R" if s > 0 else "L"
    hip = (s * HIP[0], HIP[1], HIP[2])
    knee = (s * KNEE[0], KNEE[1], KNEE[2])
    ankle = (s * ANKLE[0], ANKLE[1], ANKLE[2])

    bm = bmesh.new()
    _bx(G, bm, s * 0.42, s * 1.26, -0.86, 0.58, 2.20, 3.98, bevel=0.22)
    _bx(G, bm, s * 0.46, s * 1.22, 0.54, 0.66, 2.60, 3.70, bevel=0.0)      # a thigh ridge
    G.part("LegUpper_" + tag, bm, c, "Stone", hip, parent="Hips")

    bm = bmesh.new()
    _crack(G, bm, (s * 1.26, 0.06, 3.74), (s * 1.22, 0.02, 2.46), n=6, amp=0.18,
           axis=(0, 1, 0), r=0.09)
    G.part("CracksLeg_" + tag, bm, c, "EyeGlow", (s * 1.26, 0.06, 3.74),
           parent="LegUpper_" + tag)

    bm = bmesh.new()
    _bx(G, bm, s * 0.46, s * 1.24, -0.58, 0.56, 0.72, 2.40, bevel=0.20)
    _bx(G, bm, s * 0.50, s * 1.20, 0.50, 0.68, 2.08, 2.52, bevel=0.0)      # the knee cap
    G.part("LegLower_" + tag, bm, c, "Stone", knee, parent="LegUpper_" + tag)

    bm = bmesh.new()
    _bx(G, bm, s * 0.30, s * 1.42, -0.80, 1.06, 0.0, 0.66, bevel=0.16)
    _bx(G, bm, s * 0.36, s * 1.36, 0.88, 1.16, 0.0, 0.40, bevel=0.10)      # the toe cap
    _bx(G, bm, s * 0.52, s * 1.18, -0.32, 0.56, 0.60, 0.90, bevel=0.0)     # the ankle boss
    G.part("Foot_" + tag, bm, c, "Stone", ankle, parent="LegLower_" + tag)


def _ropes(G, c):
    """The two odd rope bands the sheet shows: left wrist, right ankle, and the moss
    growing on the left knee."""
    bm = bmesh.new()                       # LEFT wrist: the forearm is 0.72 x 1.30 here
    _band(G, bm, (-1.56, 0.01), 0.88, 1.46, 3.70)
    G.box(bm, (-2.04, 0.60, 3.56), (-1.70, 0.94, 3.88))                    # the tied end
    G.part("WristRope", bm, c, "Rope", (-WRIST[0], WRIST[1], WRIST[2]), parent="ArmLower_L")

    bm = bmesh.new()                       # RIGHT ankle: the shin is 0.78 x 1.14 here
    _band(G, bm, (0.85, -0.01), 0.94, 1.30, 1.08)
    G.box(bm, (0.98, 0.50, 0.92), (1.32, 0.84, 1.24))                      # its tied end
    G.part("AnkleRope", bm, c, "Rope", (ANKLE[0], ANKLE[1], ANKLE[2]), parent="LegLower_R")

    bm = bmesh.new()
    G.patch(bm, (-0.86, 0.68, 2.30), normal=(0.0, 1.0, 0.30), radius=0.42, height=0.11,
            seed=52, jitter=0.28, segs=7)                          # on the kneecap's face
    G.patch(bm, (-1.24, 0.34, 2.14), normal=(-1.0, 0.30, 0.20), radius=0.26, height=0.09,
            seed=53, jitter=0.30, segs=6)                          # ... and round its side
    G.part("MossKnee", bm, c, "Moss", (-KNEE[0], KNEE[1], KNEE[2]), parent="LegLower_L")


def _club(G, c):
    """The kanabo: a MASSIVE octagonal shaft swelling into a studded head, planted
    butt-down on the ground beside the right foot and gripped where the fist closes on it.

    Sized off the sheet, not off the hand: 1.13 thick at the grip (the forearm is 0.72 x
    1.20, so the shaft really is as thick as the arm holding it - 1.8x the pole it used to
    be) swelling to 1.76 through the studded head, and 6.97 long from the butt on the
    ground to a tip at z 6.90, which is 0.54 above the shoulder joint and clear of the
    pauldron's lower edge.  It stands OUT at x 1.56..3.37 - the foot ends at 1.42 and the
    fist at 2.06, so the whole length of it reads outboard of the body in silhouette
    instead of hiding behind a leg."""
    bm = bmesh.new()
    ts = (0.0, 0.10, 0.34, 0.52, 0.68, 0.84, 0.94, 1.0)
    G.tube(bm, [_club_at(t) for t in ts], [_club_r(t) for t in ts], segs=8)
    # Five courses of four, squared up in COLUMNS rather than staggered, at 0.46 across
    # and standing 0.17 proud: on a head 1.76 thick that is a grid of blocks you can
    # count from across the biome.  The old 0.28 studs on a 1.20 shaft were texture.
    for t in (0.54, 0.64, 0.74, 0.84, 0.93):                       # the square studs
        p, r = _club_at(t), _club_r(t)
        for k in range(4):
            a = math.pi * 0.5 * k
            G.stud_patch(bm, (p[0] + math.cos(a) * r * 0.94, p[1] + math.sin(a) * r * 0.94,
                              p[2]), (math.cos(a), math.sin(a), 0.16), size=0.46,
                         rise=0.17, sink=0.08, bevel=0.0)
    G.part("Club", bm, c, "Stone", CLUB_GRIP, parent="Fist_R")

    bm = bmesh.new()                       # the rope whipping round the grip
    # The fist closes on the shaft between t 0.39 and t 0.53, so bands inside that span
    # are swallowed by the stone hand: two go BELOW the fist and one just above it, which
    # is where a real weapon's wrap shows anyway.
    for t in (0.30, 0.35, 0.56):
        p = _club_at(t)
        G.ring_band(bm, p, axis=CLUB_DIR, radius=_club_r(t) + 0.12, minor=0.13,
                    seg_major=6, seg_minor=3)
    G.box(bm, (2.84, 1.19, 2.02), (3.24, 1.59, 2.42))              # the knot, clear of the fist
    G.part("ClubGrip", bm, c, "Rope", CLUB_GRIP, parent="Club")

    bm = bmesh.new()                       # two cracks burning up the shaft
    for side, t0, t1 in ((+1, 0.28, 0.88), (-1, 0.44, 0.96)):
        pts, rs = [], []
        for i in range(6):
            t = t0 + (t1 - t0) * i / 5.0
            p, r = _club_at(t), _club_r(t)
            pts.append((p[0] + 0.22 * side * (1 if i % 2 else -1), p[1] + r * 0.92 * side,
                        p[2]))
            rs.append(0.12 if 0 < i < 5 else 0.05)
        G.tube(bm, pts, rs, segs=4)
    G.part("ClubCracks", bm, c, "EyeGlow", CLUB_GRIP, parent="Club")


# ================================================================= the shrine
def _seat(G):
    """A square stone pedestal under a red torii, flanked by two lit lanterns - the
    shrine it sleeps on and the thing that is left standing when it walks off."""
    c = G.begin(SEAT, GUARDIAN, prefix="KabutoSeat")

    bm = bmesh.new()
    G.box(bm, (-2.12, -2.12, 0.0), (2.12, 2.12, 0.18))                       # ground lip
    G.stepped_base(bm, 3.66, 1.30, steps=3, grow=1.075, bevel=0.10, z0=0.06)
    G.beveled_box(bm, (-1.96, -1.96, 1.26), (1.96, 1.96, 1.60), bevel=0.12)  # the cap slab
    G.part("Pedestal", bm, c, "Stone", (0.0, 0.0, 0.0), parent=None)

    bm = bmesh.new()
    # The middle step's face is at 1.967, so a panel drawn at 1.72..1.80 would be BURIED
    # in the stone: each one straddles the face instead, 0.10 in and 0.03 proud.
    for x0, x1, y0, y1 in ((-1.30, 1.30, 1.90, 2.00), (-1.30, 1.30, -2.00, -1.90),
                           (1.90, 2.00, -1.30, 1.30), (-2.00, -1.90, -1.30, 1.30)):
        G.box(bm, (x0, y0, 0.58), (x1, y1, 0.90))                            # sunken panels
    G.box(bm, (-1.94, -1.94, 1.20), (1.94, 1.94, 1.28))                      # the cap seam
    G.part("PedestalDark", bm, c, "StoneDark", (0.0, 0.0, 0.0), parent="Pedestal")

    bm = bmesh.new()
    G.patch(bm, (-1.30, -1.10, 1.60), normal=(0.0, 0.0, 1.0), radius=0.52, height=0.10,
            seed=61, jitter=0.28, segs=7)
    G.patch(bm, (1.46, 0.90, 1.60), normal=(0.0, 0.0, 1.0), radius=0.38, height=0.09,
            seed=62, jitter=0.30, segs=6)
    G.patch(bm, (-1.84, 0.40, 1.02), normal=(-1.0, 0.10, 0.30), radius=0.34, height=0.09,
            seed=63, jitter=0.30, segs=6)
    G.part("Moss", bm, c, "Moss", (0.0, 0.0, 1.60), parent="Pedestal")

    bm = bmesh.new()
    for i, (x, y) in enumerate(((-2.42, 0.30), (2.44, -1.95), (-2.28, 1.95), (2.30, 1.90))):
        G.tuft(bm, (x, y, 0.05), direction=(0.10, 0.18, 1.0), n=3, length=0.39, width=0.07,
               spread_deg=26, seed=70 + i, vary=0.4)   # rooted at the FLOOR, not 0.26 over it
    G.part("Grass", bm, c, "Grass", (0.0, 0.0, 0.05), parent="Pedestal")

    _torii(G, c)
    for side in (+1, -1):
        _lantern(G, c, side)
    return c


def _torii(G, c):
    """Two posts and two beams in shrine red, standing behind the pedestal."""
    bm = bmesh.new()
    for s in (+1, -1):
        _bx(G, bm, s * 2.06, s * 2.54, -2.78, -2.30, 0.0, 5.24, bevel=0.09)
    G.beveled_box(bm, (-2.92, -2.86, 4.98), (2.92, -2.22, 5.34), bevel=0.10)   # the kasagi
    for s in (+1, -1):                                                         # upturned ends
        G.wedge(bm, (s * 2.92, -2.80, 5.20), (s * 3.30, -2.28, 5.52), rise='+X')
    G.beveled_box(bm, (-2.78, -2.74, 3.62), (2.78, -2.34, 3.98), bevel=0.08)   # the nuki
    G.part("Torii", bm, c, "Rope", (0.0, -2.54, 0.0), parent="Pedestal")

    bm = bmesh.new()
    G.box(bm, (-0.30, -2.80, 3.94), (0.30, -2.28, 5.02))                       # centre strut
    G.box(bm, (-2.62, -2.82, 4.74), (2.62, -2.26, 4.98))                       # the shimaki
    for s in (+1, -1):                                                         # post footings
        _bx(G, bm, s * 2.00, s * 2.60, -2.84, -2.24, 0.0, 0.30, bevel=0.0)
    G.part("ToriiTrim", bm, c, "RopeDark", (0.0, -2.54, 0.0), parent="Torii")


def _lantern(G, c, s):
    """A small stone lantern with a warm panel burning in its box.

    It stands BESIDE the back half of the plinth (y -1.06), not in front of it: asleep,
    Kabuto's fists hang at x +/-2.9 over y 1.0..2.4, which is exactly where a lantern at
    the front corner would be - the hand would pass straight through it."""
    tag = "R" if s > 0 else "L"
    x, y = s * 2.86, -1.06
    bm = bmesh.new()
    _bx(G, bm, x - 0.42, x + 0.42, y - 0.42, y + 0.42, 0.0, 0.28, bevel=0.0)
    G.cyl(bm, (x, y, 0.24), (x, y, 1.06), 0.17, segs=6)
    # the light box is a stone FLOOR and a stone LID with the glow panel showing between
    # them - a glow prism inside a solid stone box is simply invisible
    G.hex_prism(bm, (x, y, 1.23), 0.36, 0.14, axis=(0, 0, 1), sides=6)
    G.hex_prism(bm, (x, y, 1.67), 0.36, 0.14, axis=(0, 0, 1), sides=6)
    G.hex_prism(bm, (x, y, 1.80), 0.58, 0.26, axis=(0, 0, 1), sides=6, taper=0.40)
    G.part("Lantern_" + tag, bm, c, "Stone", (x, y, 0.0), parent="Pedestal")

    bm = bmesh.new()
    G.hex_prism(bm, (x, y, 1.45), 0.33, 0.30, axis=(0, 0, 1), sides=6)
    G.part("Glow_" + tag, bm, c, "Lantern", (x, y, 1.45), parent="Lantern_" + tag)
