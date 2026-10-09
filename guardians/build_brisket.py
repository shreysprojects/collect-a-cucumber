"""Farm biome guardian 4/10: BRISKET, the bull that dozes in the wallow until you steal.

Reference sheet: a chestnut bull built front-heavy - an enormous chest and shoulder mass,
a thick low-slung head and much smaller hindquarters.  Cream horns WIDER THAN THE BODY
sweep out sideways, then curl forward and up to points.  The muzzle is a big soft cream
block with a pink nose, a brass ring through the septum, and two white steam puffs blowing
out of the nostrils.  Small angry red eyes sit deep under a heavy brow; the ears are
tucked back behind the horns; a loose dewlap hangs from the throat to the brisket.  Black
cloven hooves on thick two-part legs, mud thrown up the front ones, and a thin tail with a
black tuft flicking up behind.  It sleeps in a churned mud patch by a broken fence corner.
"""
import bmesh, math

COLLECTION = "Brisket"
GUARDIAN = "Brisket"
SEAT = "Brisket_Seat"
EXTRA = "Brisket_Extra"

NOTES = (
    "8.30 studs at the top of the shoulder hump (SPEC says 8), 12.1 long from the nose "
    "pad to the tail tuft, 3.6 wide through the barrel and 4.6 across the shoulder - but "
    "7.64 across the horn tips, which are the "
    "widest thing on it by half again, exactly as the sheet asks.  Faces +Y: chest and head at +Y, rump "
    "and tail at -Y, and the character's RIGHT is +X, which is screen-LEFT, so the horn "
    "on the left of a render is Horn_R.  Rig: Root sits mid-barrel and carries Body; Body "
    "carries the Neck, all four upper legs and the Tail; Neck carries the Head, the Mane "
    "and the hanging Dewlap (the cut of beef it is named for); Head carries both Horns, "
    "both Ears, the Brow, both Eyes and the Muzzle; Muzzle carries the pink Nose - which "
    "carries the brass Ring, pivoted AT THE SEPTUM so it swings - plus the dark Nostrils "
    "and both Steam puffs, pivoted at the nostrils so a snort can scale them.  THE "
    "SILHOUETTE IS A WEDGE: the hump peaks at 8.30 right over the shoulder, the back is "
    "7.20 over the barrel, 6.45 at the loin and 6.52 at the rump - a 1.78 fall against "
    "the 0.65 it used to have - and the half-width goes 2.30 at the shoulder slab, 1.80 "
    "at the barrel, 1.26 at the loin, 1.18 at the rump.  THE HORNS leave the skull dead "
    "horizontal (start tangent 0.999 in x, -0.2 deg), sweep out to x 3.09 at the halfway "
    "mark, then curl forward and up with no x left in the end tangent, finishing at "
    "(3.82, 6.35, 7.00) - 0.86 above the top of the skull, 3.80 of reach and 4.39 of arc "
    "off a base radius of 0.59, against 2.57 / 3.57 / 0.42 before.  THE LEGS are columns, "
    "not sticks: the front thigh is 2.04 thick at the hip (the neck is 2.12 where it "
    "meets the head) and still 1.76 at the knee, the cannon 1.60 down to 1.12, the hind "
    "1.76 / 1.48 and 1.36 / 1.00; every segment runs 0.14-0.30 past its joint into its "
    "neighbour and a 1.80-across knee cap and a 1.48-across hock cap sit centred ON the "
    "pivot, so no gap can open at any fold.  Each leg "
    "is upper + lower + a cloven two-block hoof (widened to 1.16 with the cannon), and each front lower carries a Mud "
    "Splatter part.  The eyes sit PROUD of the skull side (x 1.26 against a skull face at "
    "1.20) and the cheek blobs stop at z 5.10 underneath them, so the two red pips are "
    "actually visible under the brow instead of being buried in the head.  Built STANDING "
    "with the head low but clear of the ground; the sheet's head-down charge is "
    "POSES['Charge'].  Sit drops the Root 3.05 studs and slides it 0.95 back, so the "
    "brisket and belly settle INTO the wallow (belly 3.52 -> 0.43 against a churned "
    "middle at 0.32), the withers land at 5.20 against SPEC's 5.0 sitting height, all "
    "four hoof soles rest within 0.02 of the floor, and the chin rests on the front rim "
    "with the nose ring swung forward so it does not spear the ground.  The Sit fold is "
    "13 deg tighter at the front and 12 at the back than the first cut, because thick "
    "legs need their joints higher: the carpus axis sits at z 1.07 and the hock at 0.80, "
    "so a 0.90 knee cap and a 0.74 hock cap clear the floor and bury themselves in the "
    "0.26-deep mud instead of going through it.  Nothing is below "
    "z = 0 - the four hooves stand on it; the dry run's -0.31 min_z is only the -z "
    "component of the horn BOW vector, which it records as though it were a point (the "
    "patch normals do the same thing at -0.25), and the "
    "13.21 x 8.95 it reports is the tuft/steam hints inflating a real 12.1 x 8.30, while "
    "the 7.9 width is the Hitbox, which has to reach past the horn tips.  The "
    "seat is a 7.4 x 9.4 Mud wallow (longer than the 7 x 5 in the brief, because a "
    "12-stud bull lying down would otherwise hang off both ends of it) with a MudDark "
    "churned middle, cloven hoof prints, clods round the rim, a broken Fence corner "
    "behind it at -Y and grass tufts; the extra collection is one mud clod, which the "
    "runtime clones and flings off the hooves when it charges."
)

# ---------------------------------------------------------------- the skeleton
# Everything is hung off these: joints first, then the masses that sit on them.
BODY_PIVOT = (0.00, 0.20, 5.30)       # mid-barrel; Root sits on the same point
CHEST_C = (0.00, 1.50, 5.75)          # the shoulder mass - four times the volume of the rump
CHEST_R = (2.22, 2.10, 2.30)
RUMP_C = (0.00, -3.15, 5.30)          # deliberately small: the wedge falls away behind
RUMP_R = (1.18, 1.35, 1.22)
WITHERS_Z = 8.30                      # the top of the hump: the tallest point on the model
BELLY_Z = 3.52

NECK_PIVOT = (0.00, 2.40, 6.35)       # where the neck leaves the withers
HEAD_PIVOT = (0.00, 3.90, 5.30)       # the atlas joint at the back of the skull
JOWL = (1.00, 4.92, 4.52)             # the cheek mass, kept BELOW the eye line
MUZZLE_PIVOT = (0.00, 5.20, 4.58)
NOSE_AT = (0.00, 6.32, 4.64)
NOSTRIL = (0.34, 6.36, 4.72)
EYE = (1.26, 4.94, 5.30)              # PROUD of the skull side (x 1.20) so it is visible,
                                      # and under the brow ridge, which starts at 5.50
HORN_BASE = (0.86, 4.30, 5.78)        # out at the top corners of the skull
HORN_TIP = (3.82, 6.35, 7.00)         # 7.64 across the tips - the widest thing on the bull
HORN_BOW = (0.74, -0.57, -0.31)       # leaves the skull DEAD HORIZONTAL (start tangent
                                      # 0.999x/-0.2 deg), then curls forward and up: the
                                      # end tangent is 0.87y/0.49z with no x left in it
EAR_BASE = (1.12, 4.02, 5.40)
EAR_TIP = (2.06, 3.18, 5.10)

F_HIP = (1.42, 1.55, 4.55)            # front leg: the heavy pair
F_KNEE = (1.48, 1.78, 2.30)
F_ANKLE = (1.50, 1.68, 0.88)
B_HIP = (1.16, -2.75, 4.70)           # back leg: shorter, thinner, set inboard
B_HOCK = (1.20, -3.30, 2.25)
B_ANKLE = (1.22, -2.80, 0.82)
HOOF_H = 0.82

TAIL_PIVOT = (0.00, -4.02, 5.95)      # dropped with the rump so the root stays buried
TAIL_PTS = [(0.00, -4.02, 5.95), (0.00, -4.58, 5.00), (0.00, -4.90, 4.20),
            (0.00, -5.20, 3.98), (0.00, -5.37, 4.52)]      # hangs, then flicks up
TAIL_TIP = (0.00, -5.37, 4.58)


# ---------------------------------------------------------------- the states
POSES = {
    # Asleep in the wallow.  The brisket and belly are DOWN IN the mud (3.52 -> 0.39,
    # against a churned middle at 0.32); both front knees fold forward into the mud
    # with the cannons folded right back and the hooves standing under the chest; the
    # hind legs fold out beside the barrel with their soles flat; the chin rests on
    # the front rim with the nose ring swung forward so it is not driven through the
    # floor; ears drooped, tail draped.  POSE_LOC drops the Root 3.05 and slides it
    # 0.95 back so the barrel lands inside the wallow: withers 8.30 -> 5.20, which is
    # SPEC's 5.0 sitting height, and every hoof sole within 0.02 of the floor.
    #
    # THE rz TRAP.  Once rx has swung a leg FORWARD the leg points along +Y, and Euler
    # XYZ applies ry about world Y afterwards - which does nothing to a +Y vector.  rz
    # is the only splay control left and its sign is the OPPOSITE of the one you would
    # use at rest: on the +X (right) leg, rz negative swings the foot outward.  A
    # positive rz here walks both hind legs through each other at the centreline.
    "Sit": {
        "Body": (-3, 0, 0), "Neck": (-7, 0, 3), "Head": (0, 0, 13), "Ring": (-70, 0, 0),
        "Ear_R": (-30, 0, 12), "Ear_L": (-30, 0, -12),
        # the fold is 13 deg tighter than it used to be because the legs are now COLUMNS:
        # a carpus of radius 0.80 under a 0.90 knee cap needs its axis at z 1.07, not the
        # 0.58 that suited a 0.46 cannon, or the knee is driven through the floor
        "LegUpperF_R": (78, 0, 4), "LegUpperF_L": (78, 0, -4),
        "LegLowerF_R": (-153, 0, 0), "LegLowerF_L": (-153, 0, 0),
        # +78 cancels the folded chain so the hoof hangs VERTICALLY again and stands
        # on its sole; without it the hoof lies on its side and one edge is underground
        "HoofF_R": (78, 0, 0), "HoofF_L": (78, 0, 0),
        "LegUpperB_R": (82, 0, -15), "LegUpperB_L": (82, 0, 15),
        "LegLowerB_R": (-8, 0, 0), "LegLowerB_L": (-8, 0, 0),      # hock axis at z 0.80
        "HoofB_R": (-71, 0, 0), "HoofB_L": (-71, 0, 0),   # same trick, other sign
        "Tail": (16, 0, 8), "TailTuft": (24, 0, 0),
    },
    # up and awake: chest rocked back, head raised, ears swivelled forward, right fore
    # pawing the ground, steam blasting down out of the nose
    "Awake": {
        "Body": (2, 0, 0), "Neck": (20, 0, 0), "Head": (10, 0, 0),
        "Ear_R": (16, 0, 22), "Ear_L": (16, 0, -22),
        "LegUpperF_R": (-26, 0, 0), "LegLowerF_R": (34, 0, 0), "HoofF_R": (-36, 0, 0),
        "LegUpperF_L": (5, 0, 0), "LegLowerF_L": (-5, 0, 0), "HoofF_L": (2, 0, 0),
        "LegUpperB_R": (-4, 0, 0), "LegUpperB_L": (-4, 0, 0),
        "LegLowerB_R": (7, 0, 0), "LegLowerB_L": (7, 0, 0),
        "HoofB_R": (-5, 0, 0), "HoofB_L": (-5, 0, 0),
        "Tail": (-40, 0, -12), "TailTuft": (-18, 0, 0),
        "Steam_R": (-12, 0, 6), "Steam_L": (-12, 0, -6),
    },
    # the sheet's hero pose: head down, horns levelled at you, ears pinned back, tail up
    "Charge": {
        "Body": (-9, 0, 0), "Neck": (-24, 0, 0), "Head": (-16, 0, 0),
        "Ear_R": (-28, 0, -14), "Ear_L": (-28, 0, 14),
        "LegUpperF_R": (36, 0, 0), "LegLowerF_R": (-44, 0, 0), "HoofF_R": (-14, 0, 0),
        "LegUpperF_L": (-32, 0, 0), "LegLowerF_L": (12, 0, 0),
        "LegUpperB_R": (-28, 0, 0), "LegLowerB_R": (38, 0, 0),
        "LegUpperB_L": (24, 0, 0), "LegLowerB_L": (-22, 0, 0),
        "Tail": (-95, 0, 14), "TailTuft": (-30, 0, 0),
        "Steam_R": (-20, 0, 10), "Steam_L": (-20, 0, -10),
    },
    # a rolling gallop on the diagonal pairs, head swinging with the stride
    "Run": {
        "Body": (-4, 0, 0), "Neck": (6, 0, 0), "Head": (-8, 0, 0),
        "Ear_R": (-18, 0, -8), "Ear_L": (-18, 0, 8),
        "LegUpperF_R": (44, 0, 0), "LegLowerF_R": (-28, 0, 0), "HoofF_R": (-12, 0, 0),
        "LegUpperF_L": (-34, 0, 0), "LegLowerF_L": (-50, 0, 0),
        "LegUpperB_R": (-2, 0, 0), "LegLowerB_R": (4, 0, 0), "HoofB_R": (-2, 0, 0),
        "LegUpperB_L": (38, 0, 0), "LegLowerB_L": (-22, 0, 0),
        "Tail": (-58, 0, -12), "TailTuft": (-26, 0, 0),
    },
}
POSE_LOC = {"Sit": {"Root": (0.0, -0.95, -3.05)}}


def build(G):
    _guardian(G)
    _seat(G)
    _clod(G)
    return G.coll(COLLECTION)


# ================================================================= the guardian
def _guardian(G):
    c = G.begin(COLLECTION, GUARDIAN)

    G.root_part(c, (-0.62, -0.42, BODY_PIVOT[2] - 0.62), (0.62, 0.82, BODY_PIVOT[2] + 0.62))
    # wide enough for the horn tips (3.82) and long enough for the tail brush and the
    # steam - a query box that stops short of the horns lets a player stand inside them
    G.hitbox(c, (-3.95, -5.90, 0.0), (3.95, 7.10, 8.60), pivot=BODY_PIVOT, parent="Root")

    _body(G, c)
    _hide(G, c)
    _neck(G, c)
    _mane(G, c)
    _dewlap(G, c)
    _head(G, c)
    _brow(G, c)
    _muzzle(G, c)
    for s in (+1, -1):
        _eye(G, c, s)
        _horn(G, c, s)
        _ear(G, c, s)
        _steam(G, c, s)
        _front_leg(G, c, s)
        _back_leg(G, c, s)
    _tail(G, c)


def _body(G, c):
    """One mass, deliberately lopsided: the withers hump is the tallest thing on the
    animal and the rump is a quarter of it, so the profile is a WEDGE that falls away
    sharply behind the shoulder - 8.30 at the hump, 7.20 over the barrel, 6.45 at the
    loin, and 2.30 half-wide at the chest against 1.18 at the rump."""
    bm = bmesh.new()
    G.blob(bm, CHEST_C, CHEST_R, seed=3, jitter=0.10, subdiv=1)                    # shoulders
    G.beveled_box(bm, (-1.66, -0.15, 6.05), (1.66, 2.20, WITHERS_Z), bevel=0.46)   # hump
    G.beveled_box(bm, (-1.80, -1.85, BELLY_Z), (1.80, 1.75, 7.20), bevel=0.46)     # barrel
    G.beveled_box(bm, (-1.28, 1.55, 4.20), (1.28, 3.10, 6.55), bevel=0.36)         # brisket
    G.beveled_box(bm, (-1.26, -3.40, 4.15), (1.26, -1.60, 6.45), bevel=0.36)       # loin
    G.blob(bm, RUMP_C, RUMP_R, seed=5, jitter=0.10, subdiv=1)                      # rump
    G.part("Body", bm, c, "Chestnut", BODY_PIVOT, parent="Root")


def _hide(G, c):
    """The darker hide: a shadow band under the belly and worn patches on flank and rump."""
    bm = bmesh.new()
    G.beveled_box(bm, (-1.58, -1.80, BELLY_Z - 0.10), (1.58, 1.60, BELLY_Z + 0.26),
                  bevel=0.14)
    for s in (+1, -1):
        G.patch(bm, (s * 1.80, 0.55, 4.55), normal=(s * 1.0, 0.10, -0.25), radius=0.95,
                height=0.10, seed=11 + (s > 0), jitter=0.30, segs=7)
        G.patch(bm, (s * 1.24, -2.80, 5.00), normal=(s * 1.0, -0.30, -0.10), radius=0.62,
                height=0.09, seed=13 + (s > 0), jitter=0.28, segs=7)
    G.part("Markings", bm, c, "ChestnutDark", (0.0, 0.20, 4.30), parent="Body")


def _neck(G, c):
    """Short, thick and crested - a bull's neck, not a cow's."""
    bm = bmesh.new()
    G.limb(bm, (0.0, 2.20, 6.45), (0.0, 4.00, 5.30), 1.48, 1.06, segs=8, n=4,
           bow=(0.0, 0.0, 0.12))
    # the crest tops out at 8.26, i.e. flush with the new hump, and runs down to the poll
    G.branch_box(bm, (0.0, 2.34, 7.55), (0.0, 3.95, 6.12), 1.42, 0.96, bevel=0.22)
    G.part("Neck", bm, c, "Chestnut", NECK_PIVOT, parent="Body")


def _mane(G, c):
    """Shaggy crest hair from the withers down to the poll."""
    bm = bmesh.new()
    for i in range(4):
        p = G.lerp3((0.0, 2.45, 8.12), (0.0, 3.90, 6.60), i / 3.0)
        G.tuft(bm, p, direction=(0.0, 0.30, 1.0), n=3, length=0.52, width=0.15,
               spread_deg=44, seed=30 + i, vary=0.45)
    G.part("Mane", bm, c, "ChestnutDark", (0.0, 2.50, 8.02), parent="Neck")


def _dewlap(G, c):
    """The loose fold of hide swinging from the throat down onto the brisket."""
    bm = bmesh.new()
    G.blob(bm, (0.0, 3.55, 4.75), (0.58, 0.72, 0.78), seed=7, jitter=0.18, subdiv=1)
    for i, y in enumerate((3.05, 3.50, 3.92)):
        G.spike_shard(bm, (0.0, y, 4.85), (0.0, y - 0.22, 3.80), 1.10 - 0.18 * i, thick=0.46)
    G.part("Dewlap", bm, c, "ChestnutDark", (0.0, 3.30, 5.15), parent="Neck")


def _head(G, c):
    """A heavy square skull with deep jowls and a big blunt lower jaw, carried low."""
    bm = bmesh.new()
    G.beveled_box(bm, (-1.20, 3.86, 4.62), (1.20, 5.24, 5.96), bevel=0.30)     # skull
    G.beveled_box(bm, (-0.94, 4.45, 4.06), (0.94, 5.88, 4.84), bevel=0.24)     # lower jaw
    for s in (+1, -1):                      # cheeks: they stop at z 5.10, under the eye
        G.blob(bm, (s * JOWL[0], JOWL[1], JOWL[2]), (0.48, 0.68, 0.58),
               seed=9 + (s > 0), jitter=0.14, subdiv=1)
    G.part("Head", bm, c, "Chestnut", HEAD_PIVOT, parent="Neck")


def _brow(G, c):
    """The poll plate between the horns, a ridge over each deep-set eye, forelock curls."""
    bm = bmesh.new()
    G.beveled_box(bm, (-1.22, 4.18, 5.72), (1.22, 4.92, 6.14), bevel=0.16)
    for s in (+1, -1):
        x0, x1 = sorted((s * 0.72, s * 1.34))
        G.beveled_box(bm, (x0, 4.62, 5.50), (x1, 5.22, 5.92), bevel=0.14)      # brow ridge
        # the socket rides the skull's SIDE face (x 1.20) so the eye in it is not buried
        G.hex_prism(bm, (s * 1.19, EYE[1], EYE[2]), 0.34, 0.14,
                    axis=(s * 0.92, 0.36, 0.10), sides=6)                      # eye socket
    for i in range(3):
        G.tuft(bm, (-0.42 + 0.42 * i, 4.52, 6.10), direction=(0.0, 0.42, 0.92), n=3,
               length=0.44, width=0.13, spread_deg=52, seed=40 + i, vary=0.5)
    G.part("Brow", bm, c, "ChestnutDark", (0.0, 4.55, 5.92), parent="Head")


def _eye(G, c, s):
    """Small and angry, shaded by the brow ridge above it but standing PROUD of the
    skull face at x 1.20 - an eye flush with, or inside, the head is an eye nobody
    ever sees, and a little red goes a long way at 100 studs."""
    tag = "R" if s > 0 else "L"
    at = (s * EYE[0], EYE[1], EYE[2])
    bm = bmesh.new()
    G.hex_prism(bm, at, 0.20, 0.16, axis=(s * 0.92, 0.36, 0.10), sides=6)
    G.part("Eye_" + tag, bm, c, "EyeGlow", at, parent="Head")


def _horn(G, c, s):
    """The biggest thing on the animal.  It leaves the skull DEAD HORIZONTAL and straight
    out sideways, sweeps to x 3.09 at the halfway mark, then curls forward and up to a
    point at x 3.82 - 7.64 across the pair against 4.6 through the shoulders and 3.6
    through the barrel, so the spread is well over half as wide again as the bull.  The
    tips finish at z 7.00, 0.86 above the top of the skull (6.14), which is what stops
    them reading as tusks.  1.22 studs of reach and 0.82 of arc more than the first cut,
    and a base 40 % fatter: r0 0.59 against 0.42."""
    tag = "R" if s > 0 else "L"
    base = (s * HORN_BASE[0], HORN_BASE[1], HORN_BASE[2])
    tip = (s * HORN_TIP[0], HORN_TIP[1], HORN_TIP[2])
    bow = (s * HORN_BOW[0], HORN_BOW[1], HORN_BOW[2])
    bm = bmesh.new()
    G.horn(bm, base, tip, r0=0.59, r1=0.07, bow=bow, n=8, segs=7, power=1.25)
    G.ring_band(bm, base, axis=(s * 1.0, -0.06, 0.0), radius=0.66, minor=0.11,
                seg_major=7, seg_minor=3)                                   # the bony boss
    G.part("Horn_" + tag, bm, c, "Horn", base, parent="Head")


def _ear(G, c, s):
    """A flat leaf tucked back behind the horn, out of the way of the charge."""
    tag = "R" if s > 0 else "L"
    base = (s * EAR_BASE[0], EAR_BASE[1], EAR_BASE[2])
    tip = (s * EAR_TIP[0], EAR_TIP[1], EAR_TIP[2])
    bm = bmesh.new()
    G.blob(bm, (s * 1.08, 4.06, 5.38), (0.26, 0.24, 0.22), seed=17 + (s > 0), jitter=0.16,
           subdiv=0)
    G.spike_shard(bm, base, tip, 0.80, thick=0.30, roll_deg=16)
    G.spike_shard(bm, (s * 1.06, 4.12, 5.28), (s * 1.78, 3.44, 4.98), 0.50, thick=0.20)
    G.spike_shard(bm, (s * 1.02, 4.00, 5.52), (s * 1.62, 3.40, 5.44), 0.42, thick=0.18)
    G.part("Ear_" + tag, bm, c, "ChestnutDark", base, parent="Head")


def _muzzle(G, c):
    """The cream block, the pink pad on the front of it, the nostrils and the brass ring."""
    bm = bmesh.new()
    G.beveled_box(bm, (-0.84, 5.16, 4.10), (0.84, 6.30, 5.06), bevel=0.30)
    G.beveled_box(bm, (-0.74, 5.86, 4.02), (0.74, 6.26, 4.52), bevel=0.20)   # heavy lip
    G.part("Muzzle", bm, c, "Horn", MUZZLE_PIVOT, parent="Head")

    bm = bmesh.new()
    G.plate(bm, G.rounded_rect_pts(1.34, 0.88, 0.28, segs=3), 0.24, at=NOSE_AT,
            normal=(0.0, 1.0, 0.10))
    G.part("Nose", bm, c, "Nose", NOSE_AT, parent="Muzzle")

    bm = bmesh.new()
    for s in (+1, -1):
        G.hex_prism(bm, (s * NOSTRIL[0], NOSTRIL[1], NOSTRIL[2]), 0.17, 0.16,
                    axis=(s * 0.25, 1.0, -0.20), sides=6)
    G.part("Nostrils", bm, c, "ChestnutDark", (0.0, NOSTRIL[1], NOSTRIL[2]), parent="Muzzle")

    bm = bmesh.new()                                     # through the septum, swinging
    G.ring_band(bm, (0.0, 6.28, 4.12), axis=(0.0, 1.0, 0.0), radius=0.44, minor=0.10,
                seg_major=10, seg_minor=5)
    G.part("Ring", bm, c, "Ring", (0.0, 6.28, 4.54), parent="Nose")


def _steam(G, c, s):
    """Two chunky puffs blowing down and out of the nostrils; pivoted AT the nostril so a
    snort animation can scale them from nothing."""
    tag = "R" if s > 0 else "L"
    bm = bmesh.new()
    G.foliage(bm, (s * 0.40, 6.80, 4.52), 0.38, seed=50 + (s > 0), blobs=3, spread=0.62,
              jitter=0.30, subdiv=0)
    G.foliage(bm, (s * 0.56, 7.18, 4.22), 0.26, seed=52 + (s > 0), blobs=2, spread=0.55,
              jitter=0.32, subdiv=0)
    G.part("Steam_" + tag, bm, c, "Steam", (s * NOSTRIL[0], NOSTRIL[1] + 0.10, NOSTRIL[2]),
           parent="Muzzle")


def _front_leg(G, c, s):
    """The heavy pair: a slab of shoulder muscle, then a COLUMN.  The thigh is 2.04 thick
    at the hip - within a hair of the neck, which is 2.12 where it meets the head - and it
    only gives up 0.28 of that by the knee; the cannon carries 1.60 down to 1.12 at the
    fetlock.  The thigh runs 0.16 PAST the knee and the cannon starts 0.30 ABOVE it, so
    the two overlap 0.46 through the joint and no gap can open however far it folds."""
    tag = "R" if s > 0 else "L"
    hip = (s * F_HIP[0], F_HIP[1], F_HIP[2])
    knee = (s * F_KNEE[0], F_KNEE[1], F_KNEE[2])
    ank = (s * F_ANKLE[0], F_ANKLE[1], F_ANKLE[2])

    bm = bmesh.new()                    # the muscle CAPS the hip - a slab reaching further
    x0, x1 = sorted((s * 0.70, s * 2.30))   # into the chest would shear out of it when the
    G.beveled_box(bm, (x0, 0.80, 3.62), (x1, 2.30, 5.15), bevel=0.36)   # leg swings
    G.limb(bm, hip, (knee[0], knee[1] + 0.02, knee[2] - 0.16), 1.02, 0.88, segs=7, n=4,
           bow=(0.0, 0.12, 0.0))
    G.part("LegUpperF_" + tag, bm, c, "Chestnut", hip, parent="Body")

    bm = bmesh.new()
    G.limb(bm, (knee[0], knee[1] - 0.02, knee[2] + 0.30), ank, 0.80, 0.56, segs=6, n=4)
    G.hex_prism(bm, knee, 0.90, 0.84, axis=(0.0, 1.0, 0.0), sides=6)          # the knee
    x0, x1 = sorted((s * (F_ANKLE[0] - 0.58), s * (F_ANKLE[0] + 0.58)))
    G.beveled_box(bm, (x0, ank[1] - 0.50, ank[2] - 0.30), (x1, ank[1] + 0.44, ank[2] + 0.38),
                  bevel=0.16)                                                # the fetlock
    G.part("LegLowerF_" + tag, bm, c, "Chestnut", knee, parent="LegUpperF_" + tag)

    _hoof(G, c, "HoofF_" + tag, ank, "LegLowerF_" + tag)
    _splatter(G, c, s, tag)


def _back_leg(G, c, s):
    """Still the lighter pair - it has to read as the narrow end of the wedge - but a
    column all the same: 1.76 thick at the hip against the front's 2.04, and the haunch
    slab is 0.17 shallower than it was so the hindquarters lose mass, not gain it.  Same
    0.14/0.26 overlap through the hock as the front leg has through the knee."""
    tag = "R" if s > 0 else "L"
    hip = (s * B_HIP[0], B_HIP[1], B_HIP[2])
    hock = (s * B_HOCK[0], B_HOCK[1], B_HOCK[2])
    ank = (s * B_ANKLE[0], B_ANKLE[1], B_ANKLE[2])

    bm = bmesh.new()
    x0, x1 = sorted((s * 0.52, s * 1.88))
    G.beveled_box(bm, (x0, -3.55, 3.62), (x1, -2.10, 4.98), bevel=0.32)      # the haunch
    G.limb(bm, hip, (hock[0], hock[1] - 0.02, hock[2] - 0.14), 0.88, 0.74, segs=7, n=4,
           bow=(0.0, -0.14, 0.0))
    G.part("LegUpperB_" + tag, bm, c, "Chestnut", hip, parent="Body")

    bm = bmesh.new()
    G.limb(bm, (hock[0], hock[1] + 0.02, hock[2] + 0.26), ank, 0.68, 0.50, segs=6, n=4)
    G.hex_prism(bm, hock, 0.74, 0.70, axis=(0.0, 1.0, 0.0), sides=6)         # the hock
    x0, x1 = sorted((s * (B_ANKLE[0] - 0.54), s * (B_ANKLE[0] + 0.54)))
    G.beveled_box(bm, (x0, ank[1] - 0.46, ank[2] - 0.28), (x1, ank[1] + 0.40, ank[2] + 0.34),
                  bevel=0.14)
    G.part("LegLowerB_" + tag, bm, c, "Chestnut", hock, parent="LegUpperB_" + tag)

    _hoof(G, c, "HoofB_" + tag, ank, "LegLowerB_" + tag)


def _hoof(G, c, name, ank, parent):
    """Cloven: two black blocks with a cleft between them, under a coronet band.  Widened
    with the cannon (1.16 across against 1.04) so the leg does not overhang its own hoof -
    the shape, the cleft and the colour are untouched."""
    bm = bmesh.new()
    for k in (+1, -1):
        x0, x1 = sorted((ank[0] + k * 0.08, ank[0] + k * 0.58))
        G.beveled_box(bm, (x0, ank[1] - 0.56, 0.0), (x1, ank[1] + 0.62, HOOF_H), bevel=0.14)
    G.box(bm, (ank[0] - 0.54, ank[1] - 0.50, HOOF_H - 0.12), (ank[0] + 0.54, ank[1] + 0.38,
                                                              HOOF_H + 0.26))
    G.part(name, bm, c, "Hoof", ank, parent=parent)


def _splatter(G, c, s, tag):
    """Mud flung up the front legs - the sheet has clods flying round its feet.  The x of
    each patch is the cannon's own surface at that height, so it sits ON the leg."""
    bm = bmesh.new()
    for i, (x, y, z, r) in enumerate(((2.08, 1.62, 1.32, 0.34), (2.17, 1.88, 2.00, 0.26),
                                      (2.03, 1.74, 0.96, 0.30))):
        G.patch(bm, (s * x, y, z), normal=(s * 0.95, 0.20, -0.18), radius=r, height=0.09,
                seed=60 + i + 3 * (s > 0), jitter=0.34, segs=5)
    G.patch(bm, (s * 1.50, 2.20, 1.05), normal=(s * 0.25, 1.0, 0.15), radius=0.26,
            height=0.08, seed=66 + (s > 0), jitter=0.30, segs=5)
    G.part("Splatter_" + tag, bm, c, "Mud",
           (s * F_ANKLE[0], F_ANKLE[1], F_ANKLE[2] + 0.60), parent="LegLowerF_" + tag)


def _tail(G, c):
    """Thin, hanging off the rump, with the black tuft kicked up behind it."""
    bm = bmesh.new()
    G.tube(bm, TAIL_PTS, [0.28, 0.21, 0.16, 0.14, 0.12], segs=6)
    G.part("Tail", bm, c, "Chestnut", TAIL_PIVOT, parent="Body")

    bm = bmesh.new()
    G.tuft(bm, TAIL_TIP, direction=(0.0, -0.30, 1.0), n=6, length=0.66, width=0.16,
           spread_deg=40, seed=70, vary=0.4)
    for i in range(3):
        G.spike_shard(bm, TAIL_TIP, (0.12 - 0.12 * i, TAIL_TIP[1] - 0.26, TAIL_TIP[2] + 0.62),
                      0.22, thick=0.12)
    G.part("TailTuft", bm, c, "Hoof", TAIL_TIP, parent="Tail")


# ================================================================= the mud patch
def _puddle(rx, ry, n, phase):
    """A wobbly closed outline - the rim of a wallow, never a clean ellipse."""
    out = []
    for i in range(n):
        a = 2.0 * math.pi * i / n
        k = 1.0 + 0.13 * math.sin(3.0 * a + phase) + 0.07 * math.cos(5.0 * a - phase)
        out.append((math.cos(a) * rx * k, math.sin(a) * ry * k))
    return out


def _seat(G):
    """The wallow it sleeps in: churned mud, hoof prints, clods, and the fence it broke."""
    c = G.begin(SEAT, GUARDIAN, prefix="BrisketSeat")

    # 7.4 x 9.4 at its widest: a 12-stud bull lying down needs a longer wallow than the
    # 7 x 5 in the brief, or its head and rump hang off the mud in the Sit render.
    bm = bmesh.new()
    G.prism(bm, _puddle(3.10, 3.90, 16, 0.0), 0.0, 0.26)
    G.part("Wallow", bm, c, "Mud", (0.0, 0.0, 0.0), parent=None)

    bm = bmesh.new()                                   # the wet, churned middle
    G.prism(bm, _puddle(1.80, 2.35, 14, 1.4), 0.12, 0.32)
    G.part("Wet", bm, c, "MudDark", (0.0, 0.0, 0.22), parent="Wallow")

    bm = bmesh.new()                                   # cloven prints walking out of it
    for i, (x, y, sp) in enumerate(((1.30, 2.95, 0.20), (-1.35, 2.35, 0.19),
                                    (2.10, 0.55, 0.20))):
        for k in (+1, -1):
            G.patch(bm, (x + k * sp, y, 0.22), normal=(0.0, 0.0, 1.0), radius=0.20,
                    height=0.07, seed=80 + 2 * i + k, jitter=0.24, segs=4)
    G.part("Prints", bm, c, "MudDark", (0.0, 2.00, 0.22), parent="Wallow")

    bm = bmesh.new()                                   # clods kicked onto the rim
    for i, (x, y) in enumerate(G.ring_slots(7, 3.35, phase_deg=18, squash=1.20)):
        G.rock(bm, (x, y, 0.18 + 0.05 * (i % 3)), 0.30 + 0.06 * (i % 4), seed=90 + i,
               jitter=0.36, subdiv=0)
    G.part("Clods", bm, c, "Mud", (0.0, 0.0, 0.20), parent="Wallow")

    bm = bmesh.new()                                   # the corner it leans on, one rail gone
    for (px, py, h) in ((-3.88, -4.38, 2.10), (-1.05, -4.38, 1.95), (-3.88, -1.70, 1.95)):
        G.beveled_box(bm, (px - 0.22, py - 0.22, 0.0), (px + 0.22, py + 0.22, h), bevel=0.06)
    G.plank(bm, (-3.88, -4.38, 1.04), (-1.05, -4.38, 1.00), w=0.30, t=0.17, bevel=0.04)
    G.plank(bm, (-3.88, -4.38, 1.66), (-2.45, -4.32, 1.58), w=0.30, t=0.17, bevel=0.04)
    G.plank(bm, (-1.92, -4.26, 1.12), (-1.05, -4.38, 1.60), w=0.30, t=0.17, bevel=0.04)
    G.plank(bm, (-3.88, -4.20, 1.66), (-3.88, -1.70, 1.70), w=0.30, t=0.17, bevel=0.04)
    for i in range(3):                                 # splinters at the break
        G.spike_shard(bm, (-2.42, -4.32, 1.50 + 0.10 * i), (-2.06, -4.30, 1.44 + 0.14 * i),
                      0.13, thick=0.10)
    G.part("Fence", bm, c, "Fence", (-3.88, -4.38, 0.0), parent="Wallow")

    bm = bmesh.new()                                   # what is left of the grass round it
    for i, (x, y) in enumerate(G.ring_slots(5, 3.85, phase_deg=52, squash=1.18)):
        G.tuft(bm, (x, y, 0.12), direction=(0.0, 0.0, 1.0), n=3, length=0.40, width=0.09,
               spread_deg=30, seed=110 + i, vary=0.45)
    G.part("Grass", bm, c, "Grass", (0.0, 0.0, 0.10), parent="Wallow")
    return c


# ================================================================= the flying clod
def _clod(G):
    """One clod of mud.  The runtime clones these and throws them off the hooves."""
    c = G.begin(EXTRA, GUARDIAN, prefix="BrisketClod")

    bm = bmesh.new()
    G.rock(bm, (0.0, 0.0, 0.0), 0.34, seed=9, jitter=0.36, subdiv=1)
    G.part("Clod", bm, c, "Mud", (0.0, 0.0, 0.0), parent=None)

    bm = bmesh.new()
    G.rock(bm, (0.16, -0.10, 0.18), 0.17, seed=10, jitter=0.40, subdiv=0)
    G.part("ClodWet", bm, c, "MudDark", (0.16, -0.10, 0.18), parent="Clod")
    return c
