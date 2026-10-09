"""Underwater biome guardian 6/10: PINCH, the reef-crusted king crab.

Reference sheet: a wide crab under a TALL DOMED orange-red carapace, plated across the
back, with a tan belly plate showing at the front between the legs and a row of marginal
teeth along the shell's leading edge.  Eight CHUNKY legs, four a side, each a thick
tapering upper that kinks up to a high knee and a thinner shin that drops steeply to a
sharp tan point - tucked in close so the shell hangs out over them.  ONE ENORMOUS CLAW
dominates everything: on the crab's RIGHT (+X, which is screen LEFT in a render), held
up and forward, nearly as big as the body - an arm, a huge studded palm block, and two
thick pincer halves (a fixed lower jaw and a hinged upper) that meet at a point, with
blunt teeth on the inside edge and tan tips.  The other claw is the same shape at half
the size, held low on the far side.  Two short eye stalks carry octagonal dark plates
with a bright green cross burning in each.  The shell is crusted with big cream barnacle
rings and teal coral sprigs, and a string of bubbles rises off its shoulder.  It sleeps
in a horseshoe rock nook with a big ribbed scallop shell standing behind it.
"""
import bmesh, math

COLLECTION = "Pinch"
GUARDIAN = "Pinch"
SEAT = "Pinch_Seat"

NOTES = (
    "9.4 studs across the leg tips (10.0 across the Hitbox), 9.6 deep from the rear leg "
    "tips to the big claw's point, 6.25 to the top of the eye plates, which are the "
    "tallest geometry, and 5.94 to the top of the raised claw.  Faces +Y.  THE BIG CLAW "
    "IS THE CHARACTER: arm 2.1 + palm 2.4 + pincer 2.1 = 6.6 studs of claw against a 5.8 "
    "x 4.2 body, its palm a 2.8 x 1.7 x 2.1 block (about a third of the carapace's bulk) "
    "with two 1.15/1.05-thick pincer halves that meet at a point, and it is carried UP "
    "AND FORWARD in the REST pose - palm centre at z 4.5, tip at (0.67, 6.11, 5.67), "
    "clear of the shell's 4.88 crown - so it dominates the silhouette before any pose is "
    "applied.  The palm is aimed with pitch as well as yaw so the slab follows the "
    "climbing arm, and the whole claw swings slightly INBOARD (toward -X) rather than "
    "straight down +Y: renders look down -Y, and a claw pointing at the lens reads as a "
    "blob.  The small claw is the same four pieces at half the size and held LOW, palm "
    "at z 2.4 against the big one's 4.5.  Rig: Root sits at the centre of the body and "
    "carries the Carapace, and EVERYTHING else hangs off the Carapace - eight legs as "
    "LegU (hip) > LegL (knee) > LegTip (the tan point, welded), two eye stalks as Stalk "
    "> EyePlate > Eye, and each claw as ClawArm (shoulder) > ClawPalm (wrist) > "
    "PincerBot / PincerTop (both pivoted on the same hinge, so a snap is one rotation).  "
    "The body is centred on x = 0; the bounding box leans to +Y because the cheliped, "
    "like a real crab's, is the frontmost appendage and reaches out past the legs.  The "
    "SHELL is a tall dome, not a disc - 2.54 of rise above the rim over a 5.79-wide "
    "shell, where the first build had 1.64 - with four raised ShellDark plate seams "
    "across the back and two fore-aft ones.  The LEGS are 1.55x thicker at the hip and "
    "1.5x at the knee than the first build's sticks, the knee is lifted a clear 1.4 "
    "above the hip so the profile is an 'n' and not a splayed ray, and the stance was "
    "pulled in from a 13.4 span to 9.2 so the shell overhangs the leg row instead of "
    "perching between it.  The eight BARNACLES are 1.7x bigger (0.40-0.56) and stand "
    "0.05 proud of the dome instead of sinking 0.03 into it.  Every angle in POSES was "
    "solved against a replica of apply_pose, and the legs in TWO unknowns (hip ry and "
    "knee ry together), because a hip-only solve lands the tip on the floor by dragging "
    "it in under the body: all eight tan points land within 0.002 of z 0.02 in Sit, "
    "Awake and Snap, and Run alternates four planted tips (0.02-0.09) against four "
    "lifted 0.48-0.68, every knee clears the dome's plan ellipse in every pose, and "
    "nothing at rest or in any pose goes below the floor.  Awake's gape carries the "
    "upper jaw's tan point to z 7.35, which is the highest anything reaches in any "
    "pose.  The only limb-on-limb contact anywhere is the shared "
    "shoulder mass where the big claw arm and leg 1 leave the same front corner of the "
    "shell (0.24 at their bases, clear by the wrist) and the Sit claw's palm corner "
    "brushing leg 1's shin by 0.23 - both are Shell-on-Shell.  Barnacles, coral, the "
    "shell seams and the belly are all placed by _shell(), which solves the revolved "
    "dome for a point and its normal, so the crust sits flat on the shell instead of "
    "floating.  Bubbles is a transparency-0.45 cream part and is the one piece that "
    "floats free of the body - hide or animate it at runtime; the Hitbox (0 to 6.40) "
    "still encloses it.  Seat is "
    "a horseshoe of boulders opening toward +Y with a scallop shell leaning over the "
    "back of it, sand, two coral sprigs and a starfish.  The horseshoe had to grow to "
    "~10.6 across the outer faces rather than the brief's 'about 7': the carapace alone "
    "is 5.8 wide and its underside sits only 1.9 above the floor once Sit settles the "
    "crab, so side boulders any further in grow straight through the shell.  As placed, "
    "every boulder clears the sitting crab even if rock()'s jitter pushes a vertex out "
    "to its full 1.24x.  The dry run reports Pinch_Seat reaching z = -1.15: that is its "
    "shell_fan hint growing a symmetric cube round the fan's centre, not real geometry - "
    "the fan's lowest vertex is z 0.95 and every rib only runs up and forward from there."
)

# ---------------------------------------------------------------- the skeleton
BODY = (0.0, -0.10, 2.36)              # carapace centre - the joint the whole crab turns about
SHELL_SX, SHELL_SY = 1.34, 0.97        # the revolved dome stretched wide - but NOT flat
# The sheet's shell is a tall DOME, clearly higher at the centre than at the rim.  The
# first build revolved 1.64 of rise over a 5.79-wide shell (0.28 of the width) and read
# as a pancake; this one carries 2.54 (0.44 of the width) and holds its height out to
# r 1.6 before it falls away, so the crown is a dome and not a cone.  The last entry
# tucks back under the rim.
SHELL_PROFILE = [(0.00, 2.52), (0.62, 2.40), (1.16, 2.10), (1.62, 1.62),
                 (1.96, 0.92), (2.16, -0.02), (2.06, -0.34)]   # (revolve radius, z)
_RIM_I = max(range(len(SHELL_PROFILE)), key=lambda i: SHELL_PROFILE[i][0])
SHELL_RIM = SHELL_PROFILE[_RIM_I][0]   # profile radius at the widest point
SHELL_RIM_Z = SHELL_PROFILE[_RIM_I][1]
SHELL_TOP = BODY[2] + SHELL_PROFILE[0][1]           # 4.88

# The eight walking legs, front (index 0) to back (index 3), for the +X side.
# The first build splayed the feet out to x 6.70 on thin 0.4-radius sticks and the whole
# thing read as a SPIDER.  Three things fix that and all three are here: every segment is
# thicker (uppers ~1.55x, shins ~1.5x, ankles ~1.45x), the knee is lifted a clear 1.4
# above the hip and 1.2 above the shell rim so the profile is an "n" and not a splayed
# ray, and the tips are pulled 2.1 studs in per side (span 13.4 -> 9.2) so the 5.79-wide
# shell hangs out over the top of the leg row instead of perching between the legs.
LEG_ROOT = ((2.30, 1.00, 2.18), (2.34, 0.10, 2.18), (2.26, -0.82, 2.14), (1.90, -1.62, 2.06))
LEG_KNEE = ((3.20, 1.58, 3.58), (3.55, 0.45, 3.74), (3.48, -1.30, 3.62), (3.05, -2.58, 3.34))
LEG_FOOT = ((4.10, 2.05, 0.02), (4.60, 0.40, 0.02), (4.50, -1.72, 0.02), (3.85, -3.50, 0.02))
LEG_R0 = (0.62, 0.68, 0.66, 0.58)      # radius where the leg leaves the shell (was 0.40)
LEG_R1 = (0.40, 0.44, 0.43, 0.38)      # at the knee (was 0.26)
LEG_R2 = (0.13, 0.145, 0.14, 0.125)    # at the ankle, where the tan point starts
ANKLE_T = 0.80                         # how far down the shin the tan point begins

# THE BIG CLAW, on the crab's RIGHT (+X) - SCREEN LEFT in a render.  It is the whole
# character: arm 2.1 + palm 2.4 + pincer 2.1 = 6.6 studs of claw against a 5.8 x 4.2 body,
# with a 2.8 x 1.7 x 2.1 palm block that is about a third of the carapace's bulk.  It is
# built RAISED AND FORWARD - the arm climbs out of the front corner of the shell, the palm
# swings up and back inboard so its slab is presented broadside to the camera (a claw
# aimed straight down +Y points AT the lens and disappears), and the pincer carries on up
# and forward to z 5.7.  Nothing else on the crab reaches that high except the eye plates.
# The claw used to sweep FORWARD and back INWARD (tip at x 0.67, y 6.11), so it crossed
# the front of the body and vanished into the silhouette - the sheet holds it UP and OUT
# to the crab's own right, clear of everything, which is why it is the first thing you see.
BIG_SHOULDER = (2.10, 1.20, 2.60)
BIG_WRIST = (3.80, 1.70, 4.20)
BIG_HINGE = (4.85, 2.35, 5.45)
BIG_TIP = (5.95, 3.45, 6.85)
BIG_PALM = (3.10, 1.85, 2.30)          # palm box: along the palm, across it, and up
BIG_GAPE = 0.52                        # how far the two jaw roots sit apart at the hinge
BIG_ARM_R = (0.80, 0.66)               # arm radius at the shoulder and at the wrist
BIG_JAW = (1.15, 1.05)                 # jaw thickness at the hinge: lower, upper
# The small claw, on the crab's LEFT (-X): the SAME four pieces at half the size, and held
# LOW - its palm sits at z 2.4 where the big one is at 4.5, so the asymmetry reads from the
# front as much from the height as from the size.
SML_SHOULDER = (-2.05, 1.52, 2.26)
SML_WRIST = (-2.78, 2.10, 2.32)
SML_HINGE = (-3.31, 3.22, 2.47)
SML_TIP = (-3.68, 4.24, 2.62)
SML_PALM = (1.45, 0.90, 1.10)
SML_GAPE = 0.26
SML_ARM_R = (0.44, 0.36)
SML_JAW = (0.60, 0.55)

# the eye stalks (mirrored about x = 0).  Unchanged in shape - the taller dome simply
# carries them 0.59 further up, so they still sit ON the shell instead of inside it.
STALK_BASE = (0.82, 1.18, 4.09)
STALK_TOP = (0.98, 1.52, 5.61)
EYE_C = (1.04, 1.66, 5.79)
EYE_N = (0.20, 0.88, 0.44)             # the plate faces FORWARD and about 24 deg up, so
                                       # the green cross reads square-on from the front
EYE_R = 0.46

# The reef growing on the shell: (plan x, plan y, size).  The first build's rings were
# 0.24-0.36 across and sunk 0.03 INTO the dome, which at render distance was a freckle;
# these are 0.40-0.56 (about 1.7x) and stand 0.05 PROUD of it, so several of them are
# unmistakable cream discs at a glance.  Laid out on a fresh scatter that keeps ~1.1
# between ring centres and ~0.6 clear of every coral base.
BARNACLES = ((-1.75, 0.95, 0.52), (-0.45, 1.20, 0.46), (0.90, 1.05, 0.50),
             (1.95, -0.35, 0.44), (0.35, 0.05, 0.56), (-1.40, -0.15, 0.50),
             (-0.45, -1.75, 0.42), (1.20, -1.55, 0.40))
CORALS = ((-1.08, -1.32, 0.86), (0.58, -1.58, 0.74), (1.68, -1.02, 0.66),
          (-1.88, -0.72, 0.62), (0.06, -0.92, 0.94), (2.12, 0.30, 0.58))
# The y of each transverse shell plate seam.  Four of them now, and RAISED instead of
# sunk: a dark ridge standing 0.06 off a bright dome reads as segmentation at 100 studs
# where a 0.05-deep channel read as nothing at all.
GROOVES = (1.25, 0.45, -0.45, -1.35)
# the string tops out at 5.84, inside the Hitbox; two of the seven beads were dropped to
# pay for the bigger barnacles and the extra plate seam
BUBBLES = ((-1.28, 1.52, 3.98, 0.20), (-1.48, 1.26, 4.52, 0.26), (-1.14, 1.02, 5.06, 0.17),
           (-1.58, 0.82, 5.52, 0.23), (-1.22, 0.58, 5.84, 0.14))

# The nook: boulders round the back and sides, opening toward +Y.  The two SIDE boulders
# have to clear the carapace, which is 5.8 studs wide and whose flat underside sits only
# ~1.7 above the floor once Sit settles the crab - a boulder any further in than |x| 3.8
# grows straight through the shell in the Sit render.  That makes the horseshoe ~10.3
# across the outer faces rather than the brief's "about 7"; a 7-wide nook cannot hold a
# 14-wide crab.  Every boulder's bottom vertex still stays at or above z = 0.
ROCKS = ((-3.97, -1.12, 1.15, 1.05), (-2.45, -2.75, 1.10, 0.96), (0.05, -3.80, 1.35, 1.17),
         (2.50, -2.70, 1.12, 0.98), (4.01, -1.07, 1.12, 1.02))          # x, y, radius, z
CHIPS = ((-4.35, -2.30, 0.68, 0.65), (1.35, -3.55, 0.62, 0.59),
         (4.30, -2.40, 0.58, 0.56), (-1.35, -3.60, 0.72, 0.69))
# crust rings solved onto the boulder surfaces (centre z + radius * 0.66 * cos), not
# floated above them
SEAT_CRUST = ((-3.83, -1.12, 1.74, 0.30), (0.12, -3.65, 1.99, 0.34), (3.87, -1.10, 1.69, 0.27))
SEAT_CORAL = ((-2.60, -1.60, 0.16, (-0.30, 0.10, 1.0), 1.35),
              (2.75, -1.15, 0.16, (0.34, 0.16, 1.0), 1.15))


def _unit(v):
    L = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    return (0.0, 0.0, 1.0) if L < 1e-9 else (v[0] / L, v[1] / L, v[2] / L)


def _profile(r):
    """(z, dz/dr) on the carapace dome at revolve radius `r` - the dome as a function."""
    pts = SHELL_PROFILE[:_RIM_I + 1]
    if r <= pts[0][0]:
        return pts[0][1], 0.0
    for i in range(len(pts) - 1):
        r0, z0 = pts[i]
        r1, z1 = pts[i + 1]
        if r <= r1:
            return z0 + (z1 - z0) * (r - r0) / (r1 - r0), (z1 - z0) / (r1 - r0)
    return pts[-1][1], 0.0


def _shell(x, y, lift=0.0):
    """(point, out-normal) on the carapace at plan position (x, y).

    Every barnacle, coral sprig, shell seam and brow point is placed through this, so
    the crust sits FLAT on the dome instead of floating over it or sinking into it.
    `lift` moves the point along the normal: positive stands proud, negative sinks in."""
    rx = (x - BODY[0]) / SHELL_SX
    ry = (y - BODY[1]) / SHELL_SY
    r = math.sqrt(rx * rx + ry * ry)
    z, slope = _profile(r)
    n = ((0.0, 0.0, 1.0) if r < 1e-6 else
         _unit((-slope * rx / (r * SHELL_SX), -slope * ry / (r * SHELL_SY), 1.0)))
    return (x + n[0] * lift, y + n[1] * lift, BODY[2] + z + n[2] * lift), n


def _rim(a):
    """(point, out-normal) on the widest edge of the shell at plan angle `a` degrees."""
    t = math.radians(a)
    p = (SHELL_RIM * math.cos(t) * SHELL_SX, SHELL_RIM * math.sin(t) * SHELL_SY + BODY[1],
         BODY[2] + SHELL_RIM_Z)
    return p, _unit((math.cos(t) / SHELL_SX, math.sin(t) / SHELL_SY, -0.30))


# ---------------------------------------------------------------- the four states
def _at(v, i):
    return v[i] if isinstance(v, (tuple, list)) else v


def _legs(upper, lower, sweep=0.0, alt=False):
    """Expand per-leg angles (front to back) into the sixteen walking-leg entries.

    A leg swings in its own XZ plane, so `upper`/`lower` are ry.  With the knee now
    lifted well above the hip the two do DIFFERENT jobs and have to be picked together:
    +upper drives the tan point down but also drags it IN under the shell, and the
    `lower` knee angle is what pushes it back out to its stance width.  `sweep` is rz,
    fanning a leg fore or aft about the world Z - it leaves the tip's height alone.  All
    three MIRROR on the -x side, which is what the `* s` is doing.  `alt` shifts the -x
    side one leg along so a scuttle is out of phase side to side instead of hopping."""
    out = {}
    for i in range(4):
        for s, tag in ((+1, "R"), (-1, "L")):
            j = (i + 1) % 4 if (alt and s < 0) else i
            out["LegU_%s%d" % (tag, i + 1)] = (0.0, _at(upper, j) * s, _at(sweep, j) * s)
            out["LegL_%s%d" % (tag, i + 1)] = (0.0, _at(lower, j) * s, 0.0)
    return out


# Every angle below was SOLVED against a Python replica of guardianlib.apply_pose, not
# eyeballed, and the legs are solved in TWO unknowns, not one: the hip ry alone lands the
# tan point on the floor but drags it in under the body (leg 1's tip went from x 4.1 to
# x 2.1 the moment the shell reared), so the hip ry and the knee ry are solved together
# for "tip on z 0.02 AND tip still at its stance width".  Every planted tip in Sit, Awake
# and Snap lands within 0.004 of z 0.02; Run alternates four planted against four lifted
# 0.55.  The knee of every leg in every pose was then checked against the dome: the
# closest any of them comes to the shell's plan ellipse is Run's swinging leg 2 at
# r 2.17 against a rim of 2.16, which clears it beside the shell, not through it.
POSES = {
    # hunkered into the nook: body settled, knees drawn up, both claws folded in low and
    # across the front, eye stalks laid back flat over the shell
    "Sit": _legs((-26.8, -12.0, -3.2, 4.2), (16.6, 8.6, 4.8, 3.4), sweep=(-5, 0, 3, 8)),
    # the sheet's hero pose: reared up on braced legs, the big claw carried higher still
    # and gaping, the small claw low on the other side, eyes levelled forward
    "Awake": _legs((25.0, 11.4, 0.8, -6.6), (-21.0, -8.8, -2.8, -2.6), sweep=(8, 3, -3, -8)),
    # mid-scuttle: legs 1 and 3 planted, 2 and 4 swinging, out of phase side to side
    "Run": _legs((5.6, -24.0, -2.6, -25.0), (-6.2, 16.8, 3.2, 11.2),
                 sweep=(8, -5, 8, -5), alt=True),
    # the signature: reared hard onto the back legs, the big claw thrust forward to y 7.9
    "Snap": _legs((34.8, 17.2, 2.6, -7.6), (-29.2, -14.0, -5.4, -4.8), sweep=(10, 4, -4, -10)),
}
# The pincer gape is now rx, not ry: the jaws point along +Y and up, so a ry would turn
# them about their own length and barely open them - +rx swings a forward-pointing jaw UP.
POSES["Sit"].update({
    "Carapace": (-7, 0, 0),
    # the arm drops out and the wrist folds hard back on itself (which is how a crab
    # stows its cheliped) so the palm lies at z 2.6 and the pincer across the front of
    # the mouth, tip just past the midline at x -0.25, z 0.92
    "ClawArm_R": (-10, -5, -29), "ClawPalm_R": (33, -86, 31),
    "PincerTop_R": (3, 0, 0), "PincerBot_R": (-2, 0, 0),
    "ClawArm_L": (-8, -2, 8), "ClawPalm_L": (2, 16, -74),
    "PincerTop_L": (3, 0, 0), "PincerBot_L": (-2, 0, 0),
    "Stalk_R": (58, -10, 0), "Stalk_L": (58, 10, 0),
    "EyePlate_R": (-20, 0, 0), "EyePlate_L": (-20, 0, 0),
})
POSES["Awake"].update({
    "Carapace": (8, 0, 0),
    # the big claw climbs from a rest palm at z 4.5 to z 4.97 and its tip from 5.67 to
    # 6.51, and the jaws come apart 44 degrees
    "ClawArm_R": (-11, 5, 2), "ClawPalm_R": (4, 10, -8),
    "PincerTop_R": (34, 0, 0), "PincerBot_R": (-10, 0, 0),
    # the small claw stays LOW - palm z 2.92 against the big one's 4.97
    "ClawArm_L": (-4, -4, 2), "ClawPalm_L": (6, 5, -8),
    "PincerTop_L": (24, 0, 0), "PincerBot_L": (-8, 0, 0),
    "Stalk_R": (-16, 10, 0), "Stalk_L": (-16, -10, 0),
    # the stalks lean forward and the plates level out against the reared body, so the
    # crosses look at the player instead of at the sky
    "EyePlate_R": (-10, 0, 0), "EyePlate_L": (-10, 0, 0),
})
POSES["Run"].update({
    "Carapace": (2, 0, 0),
    # `alt` hands the -X side leg 4 the front leg's angles, and on leg 4's shorter,
    # further-back geometry that buried its tan point 0.20 under the floor - so that one
    # leg is solved on its own instead of mirrored
    "LegU_L4": (0.0, 6.8, -8.0), "LegL_L4": (0.0, -8.2, 0.0),
    "ClawArm_R": (-5, -3, -7), "ClawPalm_R": (3, -1, -2),
    "PincerTop_R": (12, 0, 0),
    "ClawArm_L": (4, 1, -1), "ClawPalm_L": (-1, 1, -4),
    "PincerTop_L": (8, 0, 0),
    "Stalk_R": (-10, 8, 0), "Stalk_L": (-10, -8, 0),
})
POSES["Snap"].update({
    "Carapace": (11, 0, 0),
    # arm and wrist both driven forward: the claw is thrust out to y 7.87 at z 4.86 and
    # clamped past closed, rather than raised overhead like Awake
    "ClawArm_R": (-36, 13, 14), "ClawPalm_R": (7, 21, -26),
    "PincerTop_R": (-5, 0, 0), "PincerBot_R": (4, 0, 0),
    "ClawArm_L": (-14, -20, 2), "ClawPalm_L": (2, 5, -16),
    "PincerTop_L": (-4, 0, 0),
    "Stalk_R": (-22, 12, 0), "Stalk_L": (-22, -12, 0),
    "EyePlate_R": (-12, 0, 0), "EyePlate_L": (-12, 0, 0),
})
# Sit settles the body 0.24 onto the sand of the nook (0.40 folded the front leg so far
# that its knee came up through the new, taller dome); Awake and Snap rear it up.
POSE_LOC = {"Sit": {"Root": (0.0, -0.30, -0.24)},
            "Awake": {"Root": (0.0, 0.0, 0.20)},
            "Snap": {"Root": (0.0, 0.15, 0.30)}}


def build(G):
    _guardian(G)
    _seat(G)
    return G.coll(COLLECTION)


# ================================================================= the guardian
def _guardian(G):
    c = G.begin(COLLECTION, GUARDIAN)

    G.root_part(c, (-0.70, BODY[1] - 0.70, BODY[2] - 0.55),
                (0.70, BODY[1] + 0.70, BODY[2] + 0.55))
    G.hitbox(c, (-5.00, -3.80, 0.0), (5.00, 6.40, 6.40), pivot=BODY, parent="Root")

    _carapace(G, c)
    _belly(G, c)
    _segments(G, c)
    _barnacles(G, c)
    _coral(G, c)
    _mouth(G, c)
    _bubbles(G, c)
    for s in (+1, -1):
        _eye(G, c, s)
        for i in range(4):
            _leg(G, c, s, i)
        _claw(G, c, s)


def _carapace(G, c):
    """The shell: a revolved dome stretched wide and shallow, a raised brow arcing over
    the eye stalks, and the row of marginal teeth every crab has along its front edge."""
    bm = bmesh.new()
    G.lathe(bm, SHELL_PROFILE, segs=12,
            matrix=G.place(BODY, scale=(SHELL_SX, SHELL_SY, 1.0)))

    brow, radii = [], []                               # the ridge over the eyes
    for i in range(7):
        x = -1.62 + 0.54 * i
        p, _n = _shell(x, 1.52 - 0.22 * (x / 1.62) ** 2, lift=0.09)
        brow.append(p)
        radii.append((0.07, 0.15, 0.20, 0.22, 0.20, 0.15, 0.07)[i])
    G.tube(bm, brow, radii, segs=5)

    for s in (+1, -1):                                 # marginal teeth, front edge
        for a in (16.0, 33.0, 50.0, 67.0, 84.0):
            p, n = _rim(a)
            base = (s * p[0], p[1], p[2])
            G.spike_shard(bm, base, (base[0] + s * n[0] * 0.40, base[1] + n[1] * 0.40,
                                     base[2] + n[2] * 0.40), 0.30, thick=0.22)
        p, n = _rim(-8.0)                              # the big side lobe
        base = (s * p[0], p[1], p[2])
        G.spike_shard(bm, base, (base[0] + s * n[0] * 0.58, base[1] + n[1] * 0.58,
                                 base[2] + n[2] * 0.52), 0.52, thick=0.34)
    G.part("Carapace", bm, c, "Shell", BODY, parent="Root")


def _belly(G, c):
    """The tan sternum showing between the legs, and the tucked abdomen flap behind it."""
    bm = bmesh.new()
    G.prism(bm, G.rounded_rect_pts(3.15, 3.45, 0.75, segs=3, center=(0.0, 0.35)), 1.72, 2.16)
    G.prism(bm, G.teardrop_pts(1.30, 1.60, n=6, center=(0.0, -1.20)), 1.66, 1.88)
    for s in (+1, -1):                                 # two rim plates under the leg roots
        G.prism(bm, G.rounded_rect_pts(0.95, 2.30, 0.30, segs=2, center=(s * 1.75, 0.05)),
                1.86, 2.10)
    G.part("Belly", bm, c, "Underside", (0.0, 0.55, 1.98), parent="Carapace")


def _segments(G, c):
    """The plates the sheet shows across the back: four transverse ridges standing PROUD
    of the dome (plus two short fore-aft seams), so the crown reads as segmented armour
    instead of as one smooth cap."""
    bm = bmesh.new()
    for gy in GROOVES:
        ry = (gy - BODY[1]) / SHELL_SY
        half = SHELL_SX * math.sqrt(max(0.04, 1.94 ** 2 - ry * ry))
        pts = [_shell(-half + 2.0 * half * i / 6.0, gy, lift=0.06)[0] for i in range(7)]
        G.tube(bm, pts, [0.06, 0.13, 0.16, 0.16, 0.16, 0.13, 0.06], segs=4)
    for s in (+1, -1):                                 # two short fore-aft seams
        pts = [_shell(s * (1.30 - 0.06 * i), 1.15 - 0.61 * i, lift=0.05)[0] for i in range(5)]
        G.tube(bm, pts, [0.05, 0.11, 0.12, 0.10, 0.05], segs=4)
    G.part("Segments", bm, c, "ShellDark", (0.0, GROOVES[1], SHELL_TOP - 0.10),
           parent="Carapace")


def _barnacles(G, c):
    """Eight cream barnacle rings crusted over the shell - big, and sitting PROUD of the
    dome (lift +0.05) so the ring wall casts a shadow instead of hiding in the paint."""
    bm = bmesh.new()
    for i, (x, y, r) in enumerate(BARNACLES):
        p, n = _shell(x, y, lift=0.05)
        G.barnacle(bm, p, normal=n, r_out=r, r_in=r * 0.46, height=r * 0.72, segs=8)
    G.part("Barnacles", bm, c, "Barnacle", _shell(0.0, 0.0)[0], parent="Carapace")


def _coral(G, c):
    """Six teal coral sprigs growing out of the back half of the shell."""
    bm = bmesh.new()
    for i, (x, y, L) in enumerate(CORALS):
        p, n = _shell(x, y, lift=-0.06)
        d = _unit((n[0] * 0.70 + (0.26 if x < 0 else -0.26), n[1] * 0.70 - 0.24,
                   n[2] * 0.90))
        G.coral_arm(bm, p, direction=d, length=L, radius=0.13, depth=1, branches=2,
                    spread=46.0, shrink=0.66, seed=11 + i, segs=4, curl=0.16)
    G.part("Coral", bm, c, "Coral", _shell(0.2, -1.0)[0], parent="Carapace")


def _mouth(G, c):
    """The stacked tan mouthparts on the FRONT of the body, under the brow.

    They have to sit at y ~2.06: the shell's front face runs y 1.92 (at z 2.6) to 1.98
    (at z 2.3) and its flat underside stops at y 1.90, so anything further back than
    that is buried inside the dome and never renders."""
    bm = bmesh.new()
    for i, (w, h, z) in enumerate(((0.90, 0.38, 2.62), (0.78, 0.34, 2.28), (0.60, 0.30, 1.98))):
        G.plate(bm, G.rounded_rect_pts(w, h, 0.10, segs=2), 0.26,
                at=(0.0, 2.08 - 0.06 * i, z), normal=(0.0, 1.0, 0.16))
    G.part("Mouth", bm, c, "Underside", (0.0, 2.08, 2.30), parent="Carapace")


def _bubbles(G, c):
    """The string of bubbles the sheet shows rising off its shoulder.  This is the ONE
    part that floats free of the body - it is welded, transparent and easy to hide."""
    bm = bmesh.new()
    for i, (x, y, z, r) in enumerate(BUBBLES):
        G.ico(bm, (x, y, z), r, subdiv=0)
    G.part("Bubbles", bm, c, "Barnacle", (BUBBLES[0][0], BUBBLES[0][1], BUBBLES[0][2]),
           parent="Carapace", transparency=0.45, moving=False)


def _eye(G, c, s):
    """A short stalk carrying an octagonal socket plate with a green cross burning in it."""
    tag = "R" if s > 0 else "L"
    base = (s * STALK_BASE[0], STALK_BASE[1], STALK_BASE[2])
    top = (s * STALK_TOP[0], STALK_TOP[1], STALK_TOP[2])
    eye = (s * EYE_C[0], EYE_C[1], EYE_C[2])
    n = (s * EYE_N[0], EYE_N[1], EYE_N[2])

    bm = bmesh.new()
    G.limb(bm, base, top, 0.30, 0.22, segs=5)
    G.hex_prism(bm, base, 0.36, 0.18, axis=(s * 0.10, 0.24, 1.0), sides=6)
    G.part("Stalk_" + tag, bm, c, "Shell", base, parent="Carapace")

    bm = bmesh.new()
    G.hex_prism(bm, eye, EYE_R, 0.30, axis=n, sides=8)
    G.part("EyePlate_" + tag, bm, c, "EyeSocket", top, parent="Stalk_" + tag)

    bm = bmesh.new()
    G.cross_glyph(bm, (eye[0] + n[0] * 0.18, eye[1] + n[1] * 0.18, eye[2] + n[2] * 0.18),
                  normal=n, arm=0.30, thick=0.12, depth=0.10)
    G.part("Eye_" + tag, bm, c, "EyeGlow", eye, parent="EyePlate_" + tag)


def _leg(G, c, s, i):
    """One walking leg: a thick upper that kinks out and up to the knee, a shin dropping
    to the floor, and the sharp tan point it actually stands on."""
    tag = ("R" if s > 0 else "L") + str(i + 1)
    root = (s * LEG_ROOT[i][0], LEG_ROOT[i][1], LEG_ROOT[i][2])
    knee = (s * LEG_KNEE[i][0], LEG_KNEE[i][1], LEG_KNEE[i][2])
    foot = (s * LEG_FOOT[i][0], LEG_FOOT[i][1], LEG_FOOT[i][2])
    ankle = G.lerp3(knee, foot, ANKLE_T)

    bm = bmesh.new()
    G.limb(bm, root, knee, LEG_R0[i], LEG_R1[i], segs=5)
    G.hex_prism(bm, root, LEG_R0[i] * 1.20, 0.24, axis=(s, 0.10, 0.10), sides=5)
    G.part("LegU_" + tag, bm, c, "Shell", root, parent="Carapace")

    bm = bmesh.new()
    G.limb(bm, knee, ankle, LEG_R1[i] * 0.94, LEG_R2[i] * 1.70, segs=5)
    for k in (0.40, 0.66):                             # bristles down the trailing edge
        p = G.lerp3(knee, ankle, k)
        G.spike_shard(bm, p, (p[0] - s * 0.10, p[1] - 0.30, p[2] - 0.14), 0.16, thick=0.08)
    G.part("LegL_" + tag, bm, c, "Shell", knee, parent="LegU_" + tag)

    bm = bmesh.new()
    G.cone(bm, ankle, foot, LEG_R2[i] * 1.70, r_tip=0.0, segs=5)
    G.part("LegTip_" + tag, bm, c, "Underside", ankle, parent="LegL_" + tag, moving=False)


def _claw(G, c, s):
    """Arm, studded palm and the two pincer halves.  Built CLOSED and held low and
    forward - POSES["Awake"] raises and gapes it, POSES["Snap"] slams it shut."""
    tag = "R" if s > 0 else "L"
    big = s > 0
    sh, wr = (BIG_SHOULDER, BIG_WRIST) if big else (SML_SHOULDER, SML_WRIST)
    hg, tp = (BIG_HINGE, BIG_TIP) if big else (SML_HINGE, SML_TIP)
    pl, gape = (BIG_PALM, BIG_GAPE) if big else (SML_PALM, SML_GAPE)
    arm_r, jaw_w = (BIG_ARM_R, BIG_JAW) if big else (SML_ARM_R, SML_JAW)

    bm = bmesh.new()
    G.limb(bm, sh, wr, arm_r[0], arm_r[1], segs=6 if big else 5)
    G.hex_prism(bm, sh, arm_r[0] * 1.12, 0.30, axis=(s, 0.24, 0.24), sides=6)
    G.part("ClawArm_" + tag, bm, c, "Shell", sh, parent="Carapace")

    # The palm block is aimed along the WHOLE wrist-to-hinge axis, pitch as well as yaw:
    # this claw is carried up at 20 degrees, and a yaw-only box would leave a horizontal
    # slab hanging off a climbing arm.  `up` is the palm's own up, so the studs ride its
    # top face and the two jaws gape apart across its thickness, not across world z.
    mid = G.mid3(wr, hg)
    ax = G.norm3(G.sub3(hg, wr))
    across = _unit((-ax[1], ax[0], 0.0))
    up = _unit((ax[1] * across[2] - ax[2] * across[1],
                ax[2] * across[0] - ax[0] * across[2],
                ax[0] * across[1] - ax[1] * across[0]))
    yaw = math.degrees(math.atan2(ax[1], ax[0]))
    pitch = -math.degrees(math.asin(max(-1.0, min(1.0, ax[2]))))
    bm = bmesh.new()
    G.beveled_box(bm, (mid[0] - pl[0] / 2, mid[1] - pl[1] / 2, mid[2] - pl[2] / 2),
                  (mid[0] + pl[0] / 2, mid[1] + pl[1] / 2, mid[2] + pl[2] / 2),
                  bevel=0.26, rot=G.rot_euler(0, pitch, yaw))
    G.hex_prism(bm, wr, pl[2] * 0.38, 0.34, axis=ax, sides=6)          # wrist knuckle
    warts = ((0.24, 0.34, 0.20), (0.48, -0.28, 0.22), (0.72, 0.30, 0.18),
             (0.40, 0.04, 0.16)) if big else ((0.34, 0.18, 0.12), (0.66, -0.16, 0.11))
    for k, off, r in warts:
        p = G.lerp3(wr, hg, k)
        G.stud_bump(bm, (p[0] + across[0] * off + up[0] * pl[2] * 0.47,
                         p[1] + across[1] * off + up[1] * pl[2] * 0.47,
                         p[2] + across[2] * off + up[2] * pl[2] * 0.47),
                    normal=up, radius=r, height=r * 0.80, segs=5)
    G.part("ClawPalm_" + tag, bm, c, "Shell", wr, parent="ClawArm_" + tag)

    n_teeth = 3 if big else 2
    w = 0.52 if big else 0.32
    for half, rootw, dz, tz in (("Bot", jaw_w[0], -gape, -0.07),
                                ("Top", jaw_w[1], +gape, +0.07)):
        a = (hg[0] + up[0] * dz, hg[1] + up[1] * dz, hg[2] + up[2] * dz)
        b = (tp[0] + up[0] * tz, tp[1] + up[1] * tz, tp[2] + up[2] * tz)
        bm = bmesh.new()
        G.claw_jaw(bm, a, b, width=w, thick=0.5, curve=0.05, teeth=n_teeth,
                   side=1 if half == "Bot" else -1, root_w=rootw)
        G.part("Pincer%s_%s" % (half, tag), bm, c, "Shell", hg,
               parent="ClawPalm_" + tag)

        bm = bmesh.new()                               # the tan point of that jaw
        q = G.lerp3(a, b, 0.70)
        G.cone(bm, q, b, (0.22 if big else 0.12) * (1.0 if half == "Bot" else 0.94),
               r_tip=0.0, segs=5)
        G.part("ClawTip%s_%s" % (half, tag), bm, c, "Underside", q,
               parent="Pincer%s_%s" % (half, tag), moving=False)


# ================================================================= the rock nook
def _seat(G):
    """A horseshoe of boulders about 7 wide opening toward +Y, a big ribbed scallop
    leaning over the back of it, sand on the floor, coral sprigs and a starfish."""
    c = G.begin(SEAT, GUARDIAN, prefix="PinchSeat")

    bm = bmesh.new()
    pts = []
    for i in range(12):
        a = 2.0 * math.pi * i / 12.0
        rr = 4.35 + 0.42 * math.sin(2.3 * i + 1.1)
        pts.append((math.cos(a) * rr, math.sin(a) * rr * 0.86 - 0.35))
    G.prism(bm, pts, 0.0, 0.18)
    G.patch(bm, (-1.85, 1.35, 0.18), normal=(0, 0, 1), radius=0.95, height=0.07, seed=4,
            jitter=0.32, segs=6)
    G.part("SandBed", bm, c, "Sand", (0.0, -0.35, 0.0), parent=None)

    bm = bmesh.new()
    for i, (x, y, r, z) in enumerate(ROCKS):     # the two mid-back pair drop to subdiv 0
        G.rock(bm, (x, y, z), r, seed=20 + i, jitter=0.24, subdiv=0 if i in (1, 3) else 1,
               scale=(1.15, 1.0, 0.66))
    G.part("Rocks", bm, c, "Rock", (0.0, -2.40, 0.30), parent="SandBed")

    bm = bmesh.new()
    for i, (x, y, r, z) in enumerate(CHIPS):
        G.rock(bm, (x, y, z), r, seed=40 + i, jitter=0.30, subdiv=0,
               scale=(1.10, 1.0, 0.70))
    G.part("RocksDark", bm, c, "RockDark", (0.0, -2.60, 0.40), parent="Rocks")

    bm = bmesh.new()
    G.shell_fan(bm, (0.0, -4.15, 1.10), normal=(0.0, 0.88, -0.47), radius=2.25, ribs=6,
                thick=0.42, spread_deg=156.0, rise=0.42)
    G.wedge(bm, (-0.58, -4.40, 0.57), (0.58, -3.88, 1.25), rise='-Y')
    G.part("Fan", bm, c, "Underside", (0.0, -4.15, 1.10), parent="Rocks")

    bm = bmesh.new()
    for i, (x, y, z, r) in enumerate(SEAT_CRUST):
        G.barnacle(bm, (x, y, z), normal=_unit((x * 0.30, y * 0.18, 1.0)), r_out=r,
                   r_in=r * 0.46, height=r * 0.60, segs=4)
    G.part("Crust", bm, c, "Barnacle", (0.0, -2.20, 2.00), parent="Rocks")

    bm = bmesh.new()
    for i, (x, y, z, d, L) in enumerate(SEAT_CORAL):
        G.coral_arm(bm, (x, y, z), direction=d, length=L, radius=0.14, depth=1,
                    branches=2, spread=44.0, shrink=0.66, seed=61 + i, segs=4, curl=0.20)
    G.part("Coral", bm, c, "Coral", (SEAT_CORAL[0][0], SEAT_CORAL[0][1], SEAT_CORAL[0][2]),
           parent="Rocks")

    bm = bmesh.new()
    G.prism(bm, G.star_pts(5, 0.92, 0.36, phase=1.2), 0.0, 0.15,
            matrix=G.place((1.85, 1.75, 0.18)))
    G.lathe(bm, [(0.0, 0.17), (0.26, 0.13), (0.30, 0.0)], segs=6,
            matrix=G.place((1.85, 1.75, 0.18)))
    G.part("Starfish", bm, c, "Starfish", (1.85, 1.75, 0.18), parent="SandBed")
    return c
