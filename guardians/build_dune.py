"""Desert biome guardian 2/10: DUNE, the sand worm that rears up out of the dune.

Reference sheet: a segmented worm bursting up out of the sand with most of its length
still buried.  The head is a three-part jaw opened like a flower - a big sandstone hood
plate on top and two side mandibles, each a thick plate with a raised rim, folded back
to show a dark red throat ringed with cream triangular teeth pointing inward.  Two amber
slit eyes sit on the front of the head below the jaw, under heavy sandstone lids.  Behind the head
the body is a chain of armoured rings, each a drum with a raised lip and a few
backward-swept spikes, shrinking as it recedes down into the sand, and chunks of
sandstone and sprays of sand fly around the point where it breaks the surface.  It
sleeps as a low sand mound with two closed lids showing on the front of it.
"""
import bmesh, math

COLLECTION = "Dune"
GUARDIAN = "Dune"
SEAT = "Dune_Seat"

NOTES = (
    "Reared up as the sheet shows.  The HEAD is the widest thing on the worm and reads "
    "as a flared bell: 4.40 studs across the shut three-petal hood against a 3.24-wide "
    "Body1 ring behind it - 1.36x, which is the ratio the sheet measures - with a "
    "2.87-wide neck collar pinched between them, so the silhouette narrows at the neck "
    "and flares into the hood.  11.2 studs to the tip of the head collar's spikes, 10.9 "
    "to the crown, 3.7 across the widest body ring and its spikes, 11.4 from the sand "
    "spray at -Y to the snout at +Y.  SPEC's 3.5 footprint is the BODY's width; the head "
    "is deliberately wider than that, because the hood IS the read.  SPEC's 12 is the "
    "worm's own length measured ALONG its body, which comes out at 14.8 here, because "
    "the other number the brief gives - reared to about z 10 - costs 11.5 studs of spine "
    "on its own.  The spine is one arc in the YZ plane, 1.64 studs of body per step over "
    "seven steps, leaving the sand 12 degrees off vertical and meeting the neck at 51, "
    "and the rings taper GENTLY: 1.46 (Body1, under the neck) down to 1.00 (Body6, at "
    "the sand), 0.08 to 0.11 a ring, so the body reads as a long animal still running on "
    "down into the sand instead of a stump that stops at the surface.  Each ring is a "
    "worm_ring drum with a raised leading lip, three to five backward-swept spikes, "
    "crusted scabs and a sleeve filling the gap to its neighbour, plus three RingShadow "
    "bands in the gaps nearest the head.  Every ring's spike phase is 90 - 180/n "
    "degrees, the one that is mirror-symmetric about x = 0 and keeps a spike off the "
    "ring's own downward spoke.  Body1 is parented to Body2 and so on DOWN the chain, so "
    "the rig root is the Tail in the sand and a travel animation is a wave running up "
    "it.  SandRing (the shadow on the ground), SandBurst (sand still in the air) and "
    "Chips (chunks thrown clear) hang off ROOT, not off Tail - they are ground dressing, "
    "and parenting them to the body stood the shadow on its edge the moment Sit laid the "
    "worm out.  "
    "THE MAW.  The jaws are modelled CLOSED so the hinges can be checked.  The hinge "
    "ring is an ELLIPSE - 1.70 half-width by 1.06 half-height - set 0.90 forward of the "
    "skull's centre and 0.46 above its axis, and those three numbers are what buy the "
    "hood.  A CIRCULAR ring wide enough for a 4.4-stud head would stand a stud proud of "
    "the top of the skull and sweep every square stud of the lower face, which is "
    "exactly how the first pass ended up a rounded caterpillar snout; elliptical and "
    "pushed forward, the hood is 4.40 across on a skull only 3.60 wide - so the plates "
    "really do overhang it - the jaw juts 1.17 studs past the front of the skull, and "
    "0.79 studs of bare face are left below the lowest mandible hinge for the eyes.  "
    "Each petal is TWO flat facets creased along the petal's own spine; every facet "
    "reads its own radius off the ellipse, so it gets its own cone half-angle (23 "
    "degrees at the top, 35 at the sides) and its own half-width.  JAW_CLOSE holds each "
    "facet back to 0.90 of its exact closing width, cutting a 0.20-stud seam down every "
    "petal line - five times the hairline the first pass had - and each facet carries a "
    "raised rim 0.26 wide by 0.20 deep standing 0.09 proud of its face, round the outer "
    "edge, across the hinge and over the nose, with a 0.32-wide ridge on the crease.  "
    "Shut, that reads as three armoured petals, not a cone.  Awake opens all three 64 "
    "degrees, Run 24, Bite 100; every petal turn is ONE rotation about the maw ring's "
    "tangent at that petal's hinge, solved by _axis_euler() rather than typed as three "
    "magic numbers, and the result was checked numerically instead of by eye: all three "
    "tips move OUTWARD along their own radial at 0.99-1.00 with 0.00 sideways off the "
    "hinge plane - the hood folds up and back 2.1 studs in z, each mandible swings 2.1 "
    "studs out in x and 0.8 down.  Cream teeth (7 on the hood, 4 on each mandible, 0.30 "
    "to 0.51 long) sit on the inner faces and the dark red throat - 1.9 across, reaching "
    "1.8 back into the skull - shows once the flower opens.  "
    "THE FACE.  TWO eyes, not one bar.  Each is a narrow amber slit, 0.88 long by 0.23 "
    "tall (3.8:1), standing 0.06 proud of its own dark EyeSlit socket; the centres are "
    "2.35 apart and 1.71 studs of head show between the slits, filled by Brow, a dark "
    "RingShadow keel laid on the skull between them.  The spot is pinned by four numbers, "
    "every one measured: it sits 0.48 studs BEHIND the hinge ring, which is what keeps "
    "the opening mandibles off it (nearest jaw surface 0.43 shut, 0.64 in Awake, 0.52 in "
    "Run, 0.62 in Bite - the first pass had the eyes level with the ring and the petals "
    "swept within 0.06 of them); it clears the shut maw's own ellipse by a factor of "
    "2.1; its outward normal faces the hero camera at 0.49; and it leaves LID_RISE of "
    "face above it for the lid to hinge on.  Lid_R / Lid_L pivot on the BROW LINE - a "
    "real hinge, not the eye's centre - and are built swung 120 degrees back off the "
    "face, so at rest each is a heavy 0.30-thick sandstone hood overhanging its own eye "
    "by 0.56 along the eye normal; Sit swings them forward 125 to lie flat over the eye "
    "(the shut tip lands 0.29 below the eye's centre against an eye half-height of 0.12) "
    "and Run narrows them to 62.  "
    "The character's RIGHT is +X, which is screen-LEFT in a render.  Nothing sits below "
    "z = 0: the tail stub's base ring bottoms out at z 0.03 and is hidden under the "
    "collar of thrown-up crust, and the dry run's min_z of -0.242 is its own artefact - "
    "it reads the unit HEAD_DIR vector passed as worm_ring's axis= as a world POINT.  "
    "Sit does not curl the worm up: 14.8 studs of armoured body cannot coil to SPEC's "
    "2.2 without knotting through itself, and SPEC's own footprint of 3.5 by 12 IS a "
    "worm lying straight, so Sit lays it out - 13.4 long, 4.6 tall at the reared front.  "
    "The lay-down is solved, not eyeballed: _SIT_WANT names the pitch each spine segment "
    "should end at and _sit_chain() subtracts the rest pitches to get the rx, then "
    "POSE_LOC slides Root along -Y until the head lands on the crest and lifts TAIL (not "
    "Root, so the ground dressing stays on the floor) until the rings rest.  "
    "Body6..Body3 finish with their undersides within 0.03 of the sand, Body2 0.12 proud "
    "of it, Body1 rests on the dune's back slope 0.06 over a surface of 0.72, and the "
    "head's chin settles 0.05 into a crest of 1.38.  The seat is that mound, widened to "
    "5.1 x 6.4 x 1.4 to carry the wider head, with the two closed lids on its front "
    "slope spaced like the worm's own eyes."
)


# ---------------------------------------------------------------- vector helpers
def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def _mid(a, b):
    return ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0, (a[2] + b[2]) / 2.0)


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _norm(v):
    L = math.sqrt(_dot(v, v))
    return (0.0, 0.0, 0.0) if L < 1e-12 else (v[0] / L, v[1] / L, v[2] / L)


def _dist(a, b):
    return math.sqrt(_dot(_sub(a, b), _sub(a, b)))


def _rot_about(v, axis, deg):
    """Rodrigues: turn the vector `v` by `deg` about the unit direction `axis`."""
    x, y, z = _norm(axis)
    t = math.radians(deg)
    c, s, k = math.cos(t), math.sin(t), 1.0 - math.cos(t)
    return (v[0] * (c + x * x * k) + v[1] * (x * y * k - z * s) + v[2] * (x * z * k + y * s),
            v[0] * (y * x * k + z * s) + v[1] * (c + y * y * k) + v[2] * (y * z * k - x * s),
            v[0] * (z * x * k - y * s) + v[1] * (z * y * k + x * s) + v[2] * (c + z * z * k))


def _axis_euler(axis, deg):
    """The (rx, ry, rz) XYZ euler, in degrees, of a turn of `deg` about world `axis`.

    A pose is an XYZ euler applied about the part's own pivot, so any hinge that does
    not happen to lie on a world axis - all three jaw petals, both eye lids - has to be
    written as one of these.  Solving it here rather than typing three magic numbers
    means the poses stay correct if the head geometry ever moves."""
    x, y, z = _norm(axis)
    t = math.radians(deg)
    c, s, k = math.cos(t), math.sin(t), 1.0 - math.cos(t)
    m20, m21, m22 = z * x * k - y * s, z * y * k + x * s, c + z * z * k
    m00, m10 = c + x * x * k, y * x * k + z * s
    ry = math.asin(max(-1.0, min(1.0, -m20)))
    return (round(math.degrees(math.atan2(m21, m22)), 2),
            round(math.degrees(ry), 2),
            round(math.degrees(math.atan2(m10, m00)), 2))


def _frame(normal, up=(0.0, 0.0, 1.0)):
    """guardianlib.surface_frame in plain python: the (tangent, bitangent, normal) a
    plate is authored in, so teeth and rim beams can be placed in plate-local 2-D."""
    n = _norm(normal)
    u = _norm(up)
    if abs(_dot(u, n)) > 0.985:
        u = (0.0, 1.0, 0.0) if abs(n[2]) > 0.5 else (0.0, 0.0, 1.0)
    t = _norm(_cross(u, n))
    return t, _norm(_cross(n, t)), n


def _spin_for(normal, origin, target):
    """The spin_deg that swings a plate's local +Y from `origin` onto `target`."""
    t, b, _ = _frame(normal)
    d = _sub(target, origin)
    return math.degrees(math.atan2(-_dot(d, t), _dot(d, b)))


def _plate_pt(origin, normal, spin_deg, lx, ly, lz=0.0):
    """A plate-local (x, y, z) back in world space - lz runs along the outward normal."""
    t, b, n = _frame(normal)
    a = math.radians(spin_deg)
    rx = lx * math.cos(a) - ly * math.sin(a)
    ry = lx * math.sin(a) + ly * math.cos(a)
    return _add(origin, _add(_add(_mul(t, rx), _mul(b, ry)), _mul(n, lz)))


def _plate(G, bm, pts2d, thick, at, normal, spin_deg=0.0):
    """guardianlib.plate() spelled as prism+place, so the dry run's bounding box is not
    polluted by the unit normal vector (which it would otherwise read as a POINT)."""
    return G.prism(bm, pts2d, -thick / 2.0, thick / 2.0,
                   matrix=G.place(at, G.surface_frame(normal) @ G.rot_euler(0.0, 0.0, spin_deg)))


def _blot(radius, n=9, seed=1, jitter=0.26):
    """A jittered closed outline for a flat stain on the ground.  `patch()` would do the
    same job, but the dry run grows a whole SPHERE of its radius round a flat disc, which
    reads as geometry two studs under the floor; a prism reports its real, flat extent."""
    return [(math.cos(2.0 * math.pi * i / n) * radius
             * (1.0 + jitter * math.sin(seed * 2.3 + i * 2.1)),
             math.sin(2.0 * math.pi * i / n) * radius
             * (1.0 + jitter * math.sin(seed * 1.7 + i * 3.3))) for i in range(n)]


# ---------------------------------------------------------------- the skeleton
# The spine is one arc in the YZ plane.  It leaves the sand at -Y leaning 12 degrees off
# vertical and meets the neck leaning 51, 1.64 studs of body per step, so the worm rears
# up and cranes forward over the player.  Ring 1 is the one under the neck, and the radii
# taper GENTLY - 1.46 down to 1.00, about 0.09 a ring - so the body reads as a long animal
# still running on down into the sand rather than a stump that stops at the surface.
SAND_ENTRY = (0.00, -2.30, 0.00)
TAIL_PIVOT = (0.00, -2.30, 0.20)
TAIL_BASE = (0.00, -2.38, 0.34)            # kept off the floor: see NOTES
TAIL_R = 0.92
BODY = (                                   # Body1 (under the neck) .. Body6 (in the sand)
    ((0.00,  2.271, 8.506), 1.46),
    ((0.00,  1.121, 7.336), 1.38),
    ((0.00,  0.111, 6.044), 1.30),
    ((0.00, -0.746, 4.646), 1.21),
    ((0.00, -1.439, 3.159), 1.11),
    ((0.00, -1.959, 1.604), 1.00),
)
BODY_SPIKES = (5, 5, 4, 4, 3, 3)           # backward-swept spikes per ring, head first
RING_THICK = 1.16
# `worm_ring` lays its spikes out from `phase`, and `aim()` maps a ring's local +X onto
# world +X for any axis in the YZ plane, so the phase decides where the spikes land.
# 90 - 180/n is the one that makes the set mirror-symmetric about x = 0 AND keeps a spike
# off the ring's own downward spoke: without the first the ring throws a spike straight
# out to one side with nothing to match it, and without the second the down-spoke spike
# digs a quarter of a stud through the floor once Sit lays the worm flat.
SPIKE_PHASE = (lambda n: math.pi / 2.0 - math.pi / float(n))
BODY_PHASE = tuple(SPIKE_PHASE(n) for n in BODY_SPIKES)
NECK_END = (0.00, 3.545, 9.538)
NECK_R = 1.30

# CHAIN runs neck-end -> ring centres -> sand entry, so JOINT[i] is the joint BELOW the
# i-th link: JOINT[0] is the neck's, JOINT[n] is Body n's, JOINT[6] is Body6's.
CHAIN = (NECK_END,) + tuple(p for p, _ in BODY) + (SAND_ENTRY,)
JOINT = tuple(_mid(CHAIN[i], CHAIN[i + 1]) for i in range(len(CHAIN) - 1))

# The head cranes 14 degrees below horizontal - it is looking down at the player.
HEAD_PIVOT = NECK_END
HEAD_DIR = _norm((0.0, math.cos(math.radians(14.0)), -math.sin(math.radians(14.0))))
HEAD_UP = _norm((0.0, math.sin(math.radians(14.0)), math.cos(math.radians(14.0))))
SIDE = (1.0, 0.0, 0.0)                     # the character's RIGHT
HEAD_ARM = 1.24                            # head centre, out along HEAD_DIR from its pivot
HEAD_C = _add(HEAD_PIVOT, _mul(HEAD_DIR, HEAD_ARM))
# The head is the WIDEST thing on the worm - a flared bell, not a snout.  The skull is
# 3.60 across, the neck behind it 2.87, and the three jaw petals hinge on a ring wider
# than either: 3.40 plus its rims = 4.40, which is 1.36x the 3.24-wide Body1 ring the
# sheet measures the hood against.  The skull is deliberately LEFT narrower than the
# hood so the plates overhang it, and it is longer than it is tall so there is chin
# below the mandibles for the eyes.
HEAD_R = (1.80, 1.74, 1.62)

# THE MAW.  Three petals hinge on a ring set 0.90 forward of the skull's centre and 0.46
# above its axis, and fold forward into a blunt cone that shuts at JAW_K of the ring.
#
# The ring is an ELLIPSE, JAW_RX wide by JAW_RZ tall, not a circle, and it is pushed
# forward rather than sitting on the head's equator.  Those two choices are what buy the
# sheet's flared bell: elliptical, the hood is 4.40 across on a skull only 3.60 wide, so
# the plates really do overhang it, and 0.79 studs of bare face are left below the lowest
# mandible hinge; pushed forward, the eyes end up 0.48 BEHIND the hinge ring, which is
# the only thing that keeps the petals off them when they swing open (a plate sweeps a
# cone FORWARD of its own hinge, so anything behind the ring is never swept).  A circular
# ring wide enough for the same hood would stand a stud proud of the top of the skull and
# sweep the whole lower face - which is how the first pass ended up a caterpillar snout
# with a single amber bar for a face.
#
# Each petal is TWO flat facets, not one.  A single flat plate tangent at radius r only
# meets its neighbour if it runs r * tan(60) = 1.73 r either side of its midline, which
# makes the shut nose far wider than the skull and sweeps it over every square stud of
# the lower face.  Split each petal down its own spine and the two facets need only
# r * tan(30) = 0.58 r each, and the crease between them is the raised spine ridge the
# sheet draws along each plate.
MAW_ORIGIN = _add(_add(HEAD_C, _mul(HEAD_DIR, 0.90)), _mul(HEAD_UP, 0.46))
JAW_LEN = 1.80
JAW_RX, JAW_RZ = 1.70, 1.06                # the hinge ellipse: half-width, half-height
JAW_K = 0.26                               # the shut nose is this fraction of the ring
JAW_THICK = 0.36
JAW_TIP_C = _add(MAW_ORIGIN, _mul(HEAD_DIR, JAW_LEN))
FACET_DEG = 30.0                           # each facet sits this far off its petal's line
JAW_CLOSE = math.tan(math.radians(FACET_DEG)) * 0.90   # 0.90 = a DEEP seam per petal
HOOD_DEG, MAND_DEG = 90.0, -30.0           # where each petal hinges on the maw ring


def _petal(angle_deg):
    """One facet of the maw: (radial, outward normal, hinge, tip, spin, length).

    Every facet reads its own radius off the hinge ELLIPSE, so each gets its own cone
    half-angle and its own half-width - the side facets are half again as far out as the
    top one, which is what flares the hood sideways instead of ballooning the skull."""
    a = math.radians(angle_deg)
    ux, uz = JAW_RX * math.cos(a), JAW_RZ * math.sin(a)
    radial = _norm(_add(_mul(SIDE, ux), _mul(HEAD_UP, uz)))
    alpha = math.atan2(math.hypot(ux, uz) * (1.0 - JAW_K), JAW_LEN)
    normal = _norm(_add(_mul(radial, math.cos(alpha)), _mul(HEAD_DIR, math.sin(alpha))))
    hinge = _add(MAW_ORIGIN, _add(_mul(SIDE, ux), _mul(HEAD_UP, uz)))
    tip = _add(JAW_TIP_C, _add(_mul(SIDE, ux * JAW_K), _mul(HEAD_UP, uz * JAW_K)))
    return radial, normal, hinge, tip, _spin_for(normal, hinge, tip), _dist(hinge, tip)


def _petal_r(petal):
    """The hinge radius of one facet - the ellipse is not a circle, so each differs."""
    return _dist(MAW_ORIGIN, petal[2])


def _facets(angle_deg):
    """The two facets of the petal whose own hinge line runs at `angle_deg`."""
    return (_petal(angle_deg - FACET_DEG), _petal(angle_deg + FACET_DEG))


HOOD = _petal(HOOD_DEG)
MAND_R = _petal(MAND_DEG)
MAND_L = _petal(180.0 - MAND_DEG)
HOOD_F = _facets(HOOD_DEG)
MAND_R_F = _facets(MAND_DEG)
MAND_L_F = _facets(180.0 - MAND_DEG)


def _on_skull(offset, out=1.03):
    """Push a direction out of HEAD_C onto (or just proud of) the skull ellipsoid."""
    d = _norm((offset[0] / HEAD_R[0], offset[1] / HEAD_R[1], offset[2] / HEAD_R[2]))
    return _add(HEAD_C, (d[0] * HEAD_R[0] * out, d[1] * HEAD_R[1] * out,
                         d[2] * HEAD_R[2] * out))


# TWO eyes, not one bar.  Each is a narrow amber slit set in a dark EyeSlit socket, far
# enough out on the face that 1.75 studs of bare sandstone - and the dark Brow keel -
# show between them: the eye is 0.88 long and 0.23 tall (a 3.8:1 slit), the two centres
# are 2.39 apart and the inner ends stop at x = 0.88.  The spot itself is pinned by
# three numbers, all checked in the dry run rather than eyeballed: it clears the shut
# maw's own ellipse by a factor of 2.6, its outward normal faces the hero camera at
# 0.49, and it leaves LID_RISE of face above it for the lid to hinge on.
EYE_OFF = _add(_add(_mul(HEAD_DIR, 0.45), _mul(HEAD_UP, -1.30)), _mul(SIDE, 1.25))
EYE_R = _on_skull(EYE_OFF, 1.03)
EYE_N = _norm(_add(_add(_mul(SIDE, 0.62), _mul(HEAD_DIR, 0.62)), _mul(HEAD_UP, -0.48)))
EYE_SPIN = -16.0
EYE_W, EYE_H = 0.44, 0.115
# the dark keel of head between the two eyes - the "dark sandstone between them"
BROW_N = _norm(_add(_mul(HEAD_DIR, 0.42), _mul(HEAD_UP, -1.10)))
BROW_C = _on_skull(BROW_N, 1.01)

# The lid is a HINGE, not a decal stuck on the eye.  It pivots on the brow line LID_RISE
# above the eye and is BUILT swung LID_OPEN degrees back off the face, so at rest it is
# the heavy sandstone hood the sheet draws above the eye; swinging it forward again by
# the same angle lays it flat over the eye, which is what Sit does.  LID_LEN is longer
# than LID_RISE + the eye's half-height, so shut really does mean shut.
LID_OPEN, LID_LEN, LID_RISE, LID_HALF = 120.0, 0.56, 0.28, 0.52
LID_THICK = 0.30                           # heavy: it has to read as a hood, not a decal


def _mirror(p):
    return (-p[0], p[1], p[2])


def _eye_frame(s):
    """(eye, normal, spin, hinge axis, up-the-face) for the +1 / -1 side.

    `_frame` picks its own handedness from the world up vector, so on one side its
    local +Y comes out pointing DOWN the face; flipping BOTH basis vectors keeps the
    frame right-handed and makes one set of lid angles work on both sides."""
    eye = EYE_R if s > 0 else _mirror(EYE_R)
    n = (s * EYE_N[0], EYE_N[1], EYE_N[2])
    spin = s * EYE_SPIN
    t_ax = _plate_pt((0.0, 0.0, 0.0), n, spin, 1.0, 0.0, 0.0)
    b_up = _plate_pt((0.0, 0.0, 0.0), n, spin, 0.0, 1.0, 0.0)
    if _dot(b_up, HEAD_UP) < 0.0:
        t_ax, b_up = _mul(t_ax, -1.0), _mul(b_up, -1.0)
    return eye, n, spin, t_ax, b_up


def _lid_frame(s):
    """(hinge, plate normal, spin, hinge axis) of one lid, built swung LID_OPEN back
    off the face - so posing it forward by the same angle shuts it over the eye."""
    eye, n, _spin, t_ax, b_up = _eye_frame(s)
    hinge = _add(_add(eye, _mul(b_up, LID_RISE)), _mul(n, 0.07))
    lid_n = _rot_about(n, t_ax, -LID_OPEN)
    free = _add(hinge, _mul(_rot_about(_mul(b_up, -1.0), t_ax, -LID_OPEN), LID_LEN))
    return hinge, lid_n, _spin_for(lid_n, hinge, free), t_ax


# ---------------------------------------------------------------- the four states
# A petal opens by turning about the TANGENT of the maw ring at its own hinge; a lid
# shuts by turning about its own brow line.  Neither of those is a world axis, so both
# go through _axis_euler instead of being three typed numbers - turn a mandible about a
# world axis instead and it swings straight through the skull.
def _jaw_open(petal, deg):
    """The euler that swings one petal `deg` open about the maw ring's tangent."""
    return _axis_euler(_cross(HEAD_DIR, petal[0]), deg)


def _lid_turn(s, deg):
    """The euler that swings one lid `deg` about its brow hinge (positive = shut)."""
    return _axis_euler(_lid_frame(s)[3], deg)


JAW_AWAKE, JAW_RUN, JAW_BITE = 64.0, 24.0, 100.0
LID_SHUT, LID_HALF_SHUT = LID_OPEN + 5.0, 62.0   # rest IS the eye wide open

# Sit lays the worm out flat rather than coiling it: 13.7 studs of armoured body cannot
# curl to SPEC's sit of 2.2 without knotting through itself, and SPEC's own footprint -
# 3.5 by 12 - IS a worm lying straight.  Every spine joint is a pure pitch about world
# X, so the lay-down solves in one subtraction per segment: a segment's posed pitch is
# its rest pitch plus the sum of every rx below it in the chain, so
# rx = (want - rest) - (want - rest) of its parent.  Solving it rather than eyeballing
# is what keeps the rings ON the sand and the head ON the crest when a radius changes.
_SPINE = ([("Tail", TAIL_PIVOT, JOINT[6])]
          + [("Body%d" % (6 - k), JOINT[6 - k], JOINT[5 - k]) for k in range(6)]
          + [("Neck", JOINT[0], NECK_END)])
# Solved against the ring radii and the mound's own profile so that Body6..Body3 rest
# ON the sand (their undersides land within 0.05 of the floor), Body1 rests on the dune's
# back slope, the neck arcs clear of it, and the tail end dips steeply back into the
# sand where the shadow and the spray are.
_SIT_WANT = {"Tail": 52.00, "Body6": 3.97, "Body5": 3.76, "Body4": 2.83, "Body3": 1.69,
             "Body2": 10.47, "Body1": 29.50, "Neck": 38.99}
SIT_HEAD_PITCH = -7.0                      # laid level, snout a touch down
CREST = (0.0, -0.20, 1.38)                 # the seat dome's summit
HEAD_HALF = HEAD_R[2]                      # the skull's own half-height, laid flat


def _pitch(a, b):
    d = _sub(b, a)
    return math.degrees(math.atan2(d[2], math.hypot(d[0], d[1])))


def _sit_chain():
    """(rx per spine part, where NECK_END lands) once the worm is laid out."""
    rot, prev, p = {}, 0.0, TAIL_PIVOT
    for name, a, b in _SPINE:
        want = _SIT_WANT[name]
        delta = want - _pitch(a, b)
        rot[name] = round(delta - prev, 2)
        prev, th, L = delta, math.radians(want), _dist(a, b)
        p = (0.0, p[1] + L * math.cos(th), p[2] + L * math.sin(th))
    rot["Head"] = round(SIT_HEAD_PITCH - _pitch(HEAD_PIVOT, HEAD_C) - prev, 2)
    return rot, p


_SIT_ROT, _SIT_NECK_END = _sit_chain()
_SIT_HEAD_C = _add(_SIT_NECK_END, _mul((0.0, math.cos(math.radians(SIT_HEAD_PITCH)),
                                        math.sin(math.radians(SIT_HEAD_PITCH))), HEAD_ARM))

POSES = {
    # asleep: the worm has surfaced and stretched out flat along the sand - rings resting
    # on the ground, the front third climbing the dune's back slope, the skull laid on the
    # crest turned a little onto one cheek, both lids swung shut over the eyes.
    "Sit": dict([(k, (v, 0.0, 0.0)) for k, v in _SIT_ROT.items()]
                + [("Head", (_SIT_ROT["Head"], 6.0, 5.0)),
                   ("Lid_R", _lid_turn(+1.0, LID_SHUT)),
                   ("Lid_L", _lid_turn(-1.0, LID_SHUT))]),
    # the hero pose: reared, head craned down at the player, and the maw opened into the
    # flower the sheet draws - hood folded up and back, both mandibles swung out wide.
    "Awake": {
        "Body6": (3, 0, 0), "Body5": (3, 0, 0), "Body4": (2, 0, 0),
        "Body3": (2, 0, 0), "Body2": (1, 0, 0), "Body1": (-3, 0, 0),
        "Neck": (-7, 0, 0), "Head": (-10, 0, 0),
        "JawTop": _jaw_open(HOOD, JAW_AWAKE),
        "Mandible_R": _jaw_open(MAND_R, JAW_AWAKE),
        "Mandible_L": _jaw_open(MAND_L, JAW_AWAKE),
    },
    # travelling: a wave runs up the body, the head drops and leads, the maw cracked open.
    "Run": {
        "Body6": (8, 0, 4), "Body5": (6, 0, -8), "Body4": (4, 0, -10),
        "Body3": (3, 0, 8), "Body2": (1, 0, 12), "Body1": (-5, 0, 10),
        "Neck": (-12, 0, -8), "Head": (-14, 0, -6),
        "JawTop": _jaw_open(HOOD, JAW_RUN),
        "Mandible_R": _jaw_open(MAND_R, JAW_RUN),
        "Mandible_L": _jaw_open(MAND_L, JAW_RUN),
        "Lid_R": _lid_turn(+1.0, LID_HALF_SHUT),       # narrowed against the sand
        "Lid_L": _lid_turn(-1.0, LID_HALF_SHUT),
    },
    # the strike: the whole worm pitches forward over the player and the maw opens out.
    "Bite": {
        "Body6": (-14, 0, 0), "Body5": (-12, 0, 0), "Body4": (-10, 0, 0),
        "Body3": (-8, 0, 0), "Body2": (-6, 0, 0), "Body1": (-6, 0, 0),
        "Neck": (-6, 0, 0), "Head": (6, 0, 0),
        "JawTop": _jaw_open(HOOD, JAW_BITE),
        "Mandible_R": _jaw_open(MAND_R, JAW_BITE),
        "Mandible_L": _jaw_open(MAND_L, JAW_BITE),
    },
}
# The lay-down is placed in two pieces on purpose.  Root carries the horizontal slide
# that walks the flattened worm back until its head lands on the crest, and everything
# hangs off Root - including the ground shadow and the sand still in the air, which must
# stay flat on the floor.  The LIFT that floats the body onto the sand goes on Tail
# instead, so only the worm rises and the spray is left where it belongs.
POSE_LOC = {"Sit": {"Root": (0.0, round(CREST[1] - _SIT_HEAD_C[1], 3), 0.0),
                    "Tail": (0.0, 0.0,
                             round(CREST[2] + HEAD_HALF - 0.05 - _SIT_HEAD_C[2], 3))}}


def build(G):
    _guardian(G)
    _seat(G)
    return G.coll(COLLECTION)


# ================================================================= the guardian
def _guardian(G):
    c = G.begin(COLLECTION, GUARDIAN)

    G.root_part(c, (-0.75, -2.90, 0.10), (0.75, -1.70, 1.25))
    G.hitbox(c, (-2.35, -3.85, 0.0), (2.35, 7.80, 11.30), pivot=(0.0, 1.40, 5.50),
             parent="Root")

    _tail(G, c)
    for i in range(6):
        _body_ring(G, c, i)
    _gaps(G, c)
    _neck(G, c)
    _head(G, c)
    _throat(G, c)
    _jaws(G, c)
    _face(G, c)


def _tail(G, c):
    """The stub of body still in the sand, and the spray it threw up getting out.

    The spray is GROUND dressing, not body: the shadow on the sand, the puffs still
    hanging in the air and the chunks thrown clear all hang off Root, not off Tail, so
    that laying the worm out for Sit - which swings Tail and the whole body with it -
    does not stand the ground shadow on its edge and float the chips two studs up."""
    bm = bmesh.new()
    G.limb(bm, TAIL_BASE, JOINT[6], TAIL_R * 0.70, TAIL_R * 1.00, segs=8, n=3)
    G.lathe(bm, [(0.0, 0.0), (1.26, 0.06), (1.12, 0.30), (1.00, 0.36)], segs=9,
            matrix=G.place((0.0, -2.30, 0.06)))          # the collar of thrown-up crust
    G.part("Tail", bm, c, "Sandstone", TAIL_PIVOT, parent="Root")

    bm = bmesh.new()                                     # the dark shadow on the ground
    G.prism(bm, _blot(2.25, 11, seed=3, jitter=0.22), 0.0, 0.09,
            matrix=G.place((0.0, -2.28, 0.02)))
    G.prism(bm, _blot(1.05, 8, seed=8, jitter=0.30), 0.0, 0.07,
            matrix=G.place((0.32, -1.52, 0.02)))
    G.part("SandRing", bm, c, "SandDark", (0.0, -2.28, 0.05), parent="Root")

    bm = bmesh.new()                                     # the sand still hanging in air
    for i, (x, y, z, r) in enumerate(((1.62, -2.60, 0.85, 0.52), (-1.48, -2.10, 1.15, 0.46),
                                      (0.35, -3.25, 0.70, 0.44), (-0.70, -3.05, 1.60, 0.34))):
        G.foliage(bm, (x, y, z), r, seed=20 + i, blobs=3, spread=0.62, jitter=0.30,
                  subdiv=0, flatten=0.75)
    for i in range(6):                                   # streaks flicking off the crust
        a = math.radians(38.0 + 61.0 * i)
        base = (math.cos(a) * 1.20, -2.30 + math.sin(a) * 0.95, 0.24)
        G.spike_shard(bm, base, (base[0] * 1.55, -2.30 + (base[1] + 2.30) * 1.55, 1.10),
                      0.26, thick=0.14, roll_deg=24.0 * i)
    G.part("SandBurst", bm, c, "Sand", (0.0, -2.30, 0.60), parent="Root")

    bm = bmesh.new()                                     # sandstone chunks thrown clear
    for i, (x, y, z, r) in enumerate(((1.28, -1.55, 1.85, 0.30), (-1.70, -2.85, 1.05, 0.34),
                                      (0.92, -3.15, 2.05, 0.24), (-0.95, -1.35, 0.55, 0.28),
                                      (1.95, -2.95, 0.45, 0.26), (-0.25, -3.40, 1.25, 0.22))):
        G.rock(bm, (x, y, z), r, seed=40 + i, jitter=0.34, subdiv=0,
               scale=(1.25, 0.95, 0.80))
    G.part("Chips", bm, c, "Sandstone", (0.0, -2.30, 0.95), parent="Root")


def _body_ring(G, c, i):
    """One armoured ring: a drum with a raised lip, backward-swept spikes, a sleeve
    filling the gap to its neighbour, and a few crusted scabs on its upper surface."""
    centre, r = BODY[i]
    above, below = JOINT[i], JOINT[i + 1]
    axis = _norm(_sub(above, below))
    r_up = NECK_R if i == 0 else BODY[i - 1][1]
    r_dn = TAIL_R if i == 5 else BODY[i + 1][1]

    bm = bmesh.new()
    G.limb(bm, below, above, 0.82 * (r + r_dn) / 2.0, 0.82 * (r + r_up) / 2.0, segs=8, n=3)
    G.worm_ring(bm, centre, axis=axis, radius=r, thick=RING_THICK, lip=0.16, segs=9,
                spikes=BODY_SPIKES[i], spike_len=0.40, phase=BODY_PHASE[i])

    e2 = _norm(_cross(SIDE, axis))                    # in-ring basis, e2 pointing up-back
    for k, deg in enumerate((34.0, 78.0, 124.0, 168.0)):
        a = math.radians(deg + 11.0 * i)
        rad = _norm(_add(_mul(SIDE, math.cos(a)), _mul(e2, math.sin(a))))
        G.patch(bm, _add(centre, _mul(rad, r * 0.99)), normal=rad,
                radius=0.34 - 0.03 * i, height=0.11, seed=60 + 4 * i + k, jitter=0.26,
                segs=5)
    G.part("Body%d" % (i + 1), bm, c, "Sandstone", below,
           parent=("Body%d" % (i + 2)) if i < 5 else "Tail")


def _gaps(G, c):
    """The dark bands showing in the three gaps nearest the head, where the plates of
    the shell slide over each other."""
    for n in (1, 2, 3):
        centre = JOINT[n]
        axis = _norm(_sub(CHAIN[n - 1], CHAIN[n + 1]))
        r = 0.88 * (BODY[n - 1][1] + BODY[n][1]) / 2.0
        bm = bmesh.new()
        G.cyl(bm, _sub(centre, _mul(axis, 0.30)), _add(centre, _mul(axis, 0.30)), r,
              segs=9)
        G.part("Gap%d" % n, bm, c, "RingShadow", centre, parent="Body%d" % n)


def _neck(G, c):
    """A short armoured collar that turns the body's 42-degree rise into the head's
    14-degree crane."""
    bm = bmesh.new()
    G.limb(bm, JOINT[0], NECK_END, NECK_R, NECK_R * 0.93, segs=9, n=4,
           bow=(0.0, 0.10, 0.06))
    axis = _norm(_sub(NECK_END, JOINT[0]))
    G.worm_ring(bm, _mid(JOINT[0], NECK_END), axis=axis, radius=NECK_R * 0.99, thick=0.62,
                lip=0.15, segs=9, spikes=4, spike_len=0.42, phase=SPIKE_PHASE(4))
    G.part("Neck", bm, c, "Sandstone", JOINT[0], parent="Body1")


def _head(G, c):
    """The skull the three jaw petals hinge on: a heavy sandstone lump with a spiked
    collar at the neck, a muzzle ridge between the eyes and a scab on each cheek."""
    bm = bmesh.new()
    G.blob(bm, HEAD_C, HEAD_R, seed=11, jitter=0.10, subdiv=1)
    G.worm_ring(bm, _add(HEAD_C, _mul(HEAD_DIR, -1.10)), axis=HEAD_DIR, radius=1.40,
                thick=0.62, lip=0.15, segs=9, spikes=5, spike_len=0.38,
                phase=SPIKE_PHASE(5))
    for s in (+1.0, -1.0):                       # a crusted scab on each wide cheek
        cheek = _on_skull(_add(_add(_mul(HEAD_DIR, 0.10), _mul(HEAD_UP, -0.25)),
                               _mul(SIDE, s * 1.70)), 1.0)
        G.patch(bm, cheek, normal=(s * 0.97, 0.16, -0.18), radius=0.62, height=0.16,
                seed=13 if s > 0 else 14, jitter=0.24, segs=6)
    G.part("Head", bm, c, "Sandstone", HEAD_PIVOT, parent="Neck")

    bm = bmesh.new()      # the dark keel BETWEEN the two eyes, so they never read as one
    _plate(G, bm, [(-0.72, -0.34), (0.72, -0.34), (0.56, 0.32), (0.0, 0.56),
                   (-0.56, 0.32)], 0.30, BROW_C, BROW_N)
    G.plank(bm, _plate_pt(BROW_C, BROW_N, 0.0, -0.70, -0.30, 0.16),
            _plate_pt(BROW_C, BROW_N, 0.0, 0.70, -0.30, 0.16), w=0.22, t=0.18, bevel=0.0)
    G.part("Brow", bm, c, "RingShadow", BROW_C, parent="Head")


def _throat(G, c):
    """The dark red gullet inside the head - sealed by the petals until they fold back."""
    bm = bmesh.new()
    G.lathe(bm, [(0.0, -1.80), (0.34, -1.58), (0.60, -1.16), (0.76, -0.78), (0.66, -0.44),
                 (0.82, -0.12), (0.92, 0.10), (0.94, 0.22)], segs=9, cap=False,
            matrix=G.place(MAW_ORIGIN, G.aim(HEAD_DIR)))
    G.part("Throat", bm, c, "Mouth", MAW_ORIGIN, parent="Head")


# ----------------------------------------------------------------- the three petals
def _hw(f, r0):
    """Half-width of one facet `f` of the way from its hinge to its tip, for a facet
    whose own hinge radius is `r0`.  The 0.90 in JAW_CLOSE holds each facet back off the
    exact closing width, which is what cuts the deep seam between the three petals."""
    return JAW_CLOSE * r0 * (1.0 + (JAW_K - 1.0) * f)


def _petal_outline(L, r0):
    """One facet, authored with +Y running from its hinge out to its tip.  Every station
    is as wide as its own place on the hinge ELLIPSE needs it, so the shut maw is a
    blunt elliptical cone with a seam down each petal line; only the nose is pulled in."""
    return [(-_hw(0.0, r0), -0.34), (_hw(0.0, r0), -0.34),
            (_hw(0.30, r0), L * 0.30), (_hw(0.62, r0), L * 0.62), (_hw(0.88, r0), L * 0.88),
            (_hw(1.0, r0) * 0.66, L * 1.02),
            (-_hw(1.0, r0) * 0.66, L * 1.02), (-_hw(0.88, r0), L * 0.88),
            (-_hw(0.62, r0), L * 0.62), (-_hw(0.30, r0), L * 0.30)]


def _jaw_plate(G, c, name, petal, facets, parent):
    """One jaw petal: two sandstone facets creased along the petal's spine, with the
    raised rim the sheet draws round the outer edge of each and a few crusted scabs.
    The whole thing pivots on `petal`'s hinge - the maw ring at the petal's own line."""
    bm = bmesh.new()
    for fi, fac in enumerate(facets):
        _, normal, hinge, _tip, spin, L = fac
        r0 = _dist(MAW_ORIGIN, hinge)
        out = +1.0 if fi == 0 else -1.0               # the edge facing AWAY from the spine
        _plate(G, bm, _petal_outline(L, r0), JAW_THICK, hinge, normal, spin)

        lz = JAW_THICK / 2.0 + 0.09                   # the rim stands proud of the face
        def P(lx, ly):
            return _plate_pt(hinge, normal, spin, lx, ly, lz)

        edge = [(_hw(0.0, r0) * 0.93, -0.20), (_hw(0.24, r0) * 0.92, L * 0.24),
                (_hw(0.48, r0) * 0.91, L * 0.48), (_hw(0.72, r0) * 0.90, L * 0.72),
                (_hw(0.92, r0) * 0.86, L * 0.92)]
        for k in range(len(edge) - 1):
            G.plank(bm, P(out * edge[k][0], edge[k][1]),
                    P(out * edge[k + 1][0], edge[k + 1][1]), w=0.26, t=0.20, bevel=0.0)
        G.plank(bm, P(-_hw(0.0, r0) * 0.93, -0.20), P(_hw(0.0, r0) * 0.93, -0.20),
                w=0.30, t=0.22, bevel=0.0)
        G.plank(bm, P(out * _hw(0.92, r0) * 0.86, L * 0.92),
                P(out * _hw(1.0, r0) * 0.60, L * 1.00), w=0.24, t=0.18, bevel=0.0)
        if fi == 0:                    # the ridge over the crease, on the INNER edge
            G.plank(bm, P(-out * _hw(0.02, r0) * 0.95, -0.08),
                    P(-out * _hw(0.94, r0) * 0.95, L * 0.94), w=0.32, t=0.22, bevel=0.0)
        for k, (sx, sy, r) in enumerate(((-0.45, 0.26, 0.30), (0.42, 0.68, 0.24))):
            _plate(G, bm, _blot(r, 5, seed=7 + k + 3 * fi + len(name), jitter=0.30), 0.12,
                   _plate_pt(hinge, normal, spin, sx * _hw(sy, r0), sy * L,
                             JAW_THICK / 2.0 - 0.02), normal, spin)
    G.part(name, bm, c, "Sandstone", petal[2], parent=parent)


def _jaw_teeth(G, c, name, petal, facets, parent, rows):
    """Cream triangular teeth on the INNER faces of a petal, pointing inward - they are
    what rings the throat once the flower opens.  `rows` is (facet, fraction, side),
    with side +1 always meaning the facet's OUTER edge, so one row list comes out
    mirror-symmetric about the petal's spine on both halves."""
    bm = bmesh.new()
    for fi, f, side in rows:
        _, normal, hinge, _tip, spin, L = facets[fi]
        r0 = _dist(MAW_ORIGIN, hinge)
        out = +1.0 if fi == 0 else -1.0
        face = r0 * (1.0 + (JAW_K - 1.0) * f)
        ln = max(0.30, min(0.86, 0.46 * face))  # stops short of the maw's centreline
        lx, ly = side * out * 0.48 * _hw(f, r0), L * f
        z0 = -JAW_THICK / 2.0 + 0.04
        G.spike_shard(bm, _plate_pt(hinge, normal, spin, lx, ly, z0),
                      _plate_pt(hinge, normal, spin, lx * 0.34, ly + 0.24, z0 - ln),
                      0.40 - 0.13 * f, thick=0.20, roll_deg=8.0)
    G.part(name, bm, c, "Teeth", petal[2], parent=parent)


def _jaws(G, c):
    _jaw_plate(G, c, "JawTop", HOOD, HOOD_F, "Head")
    _jaw_plate(G, c, "Mandible_R", MAND_R, MAND_R_F, "Head")
    _jaw_plate(G, c, "Mandible_L", MAND_L, MAND_L_F, "Head")
    # seven teeth on the hood, four on each mandible - what the sheet counts
    _jaw_teeth(G, c, "TeethTop", HOOD, HOOD_F, "JawTop",
               ((0, 0.16, -1), (0, 0.16, 1), (0, 0.58, 0),
                (1, 0.16, -1), (1, 0.16, 1), (1, 0.58, 0), (1, 0.86, 0)))
    for tag, pet, fac in (("R", MAND_R, MAND_R_F), ("L", MAND_L, MAND_L_F)):
        _jaw_teeth(G, c, "Teeth" + tag, pet, fac, "Mandible_" + tag,
                   ((0, 0.20, 1), (0, 0.62, -1), (1, 0.20, 1), (1, 0.62, -1)))


# ----------------------------------------------------------------- eyes and lids
def _eye_outline(w, h):
    return [(-w, 0.0), (-w * 0.52, h * 0.86), (w * 0.52, h * 0.86), (w, 0.0),
            (w * 0.52, -h * 0.86), (-w * 0.52, -h * 0.86)]


def _face(G, c):
    """TWO eyes, well apart: each a narrow amber slit standing proud in its own dark
    EyeSlit socket, each under its own heavy sandstone lid hinged on the brow above it.
    The dark `Brow` keel built with the head fills the 1.75 studs between them."""
    for s, tag in ((+1.0, "R"), (-1.0, "L")):
        eye, n, spin, _t, _b = _eye_frame(s)
        bm = bmesh.new()
        _plate(G, bm, _eye_outline(EYE_W, EYE_H), 0.24, eye, n, spin)
        G.part("Eye_" + tag, bm, c, "EyeGlow", eye, parent="Head")

    bm = bmesh.new()                       # a dark socket ringing each amber slit
    for s in (+1.0, -1.0):
        eye, n, spin, _t, _b = _eye_frame(s)
        _plate(G, bm, _eye_outline(EYE_W + 0.13, EYE_H + 0.11), 0.16,
               _add(eye, _mul(n, -0.02)), n, spin)
    G.part("EyeSockets", bm, c, "EyeSlit", (0.0, EYE_R[1], EYE_R[2]), parent="Head")

    for s, tag in ((+1.0, "R"), (-1.0, "L")):
        hinge, lid_n, spin, t_ax = _lid_frame(s)
        L, H = LID_LEN, LID_HALF
        bm = bmesh.new()                               # the heavy shelf over the eye
        _plate(G, bm, [(-H, -0.12), (H, -0.12), (H * 0.94, L * 0.44),
                       (H * 0.70, L * 0.84), (0.0, L * 1.02),
                       (-H * 0.70, L * 0.84), (-H * 0.94, L * 0.44)], LID_THICK,
               hinge, lid_n, spin)
        brow = LID_THICK / 2.0 + 0.09                  # the ridge along the hinge line
        G.plank(bm, _plate_pt(hinge, lid_n, spin, -H * 0.98, -0.02, brow),
                _plate_pt(hinge, lid_n, spin, H * 0.98, -0.02, brow),
                w=0.28, t=0.22, bevel=0.0)
        G.plank(bm, _plate_pt(hinge, lid_n, spin, -H * 0.92, L * 0.52, brow),
                _plate_pt(hinge, lid_n, spin, H * 0.92, L * 0.52, brow),
                w=0.22, t=0.17, bevel=0.0)
        for k, (lx, ly, r) in enumerate(((-0.30, 0.34, 0.19), (0.32, 0.22, 0.16))):
            _plate(G, bm, _blot(r, 5, seed=31 + k, jitter=0.30), 0.09,
                   _plate_pt(hinge, lid_n, spin, lx * H, ly * L, LID_THICK / 2.0 - 0.01),
                   lid_n, spin)
        G.part("Lid_" + tag, bm, c, "RingShadow", hinge, parent="Head")


# ================================================================= the sand mound
def _seat(G):
    """The low mound it travels as: nothing shows but a hump of sand with two closed
    lids on the front of it, so the player still knows something is under there."""
    c = G.begin(SEAT, GUARDIAN, prefix="DuneSeat")

    bm = bmesh.new()
    G.lathe(bm, [(3.20, 0.0), (3.05, 0.34), (2.55, 0.74), (1.75, 1.12), (0.85, 1.32),
                 (0.0, 1.38)], segs=12,
            matrix=G.place((0.0, -0.20, 0.0), scale=(0.80, 1.0, 1.0)))
    for i, (x, y, z, r) in enumerate(((1.05, -1.55, 0.74, 0.60), (-1.25, 0.55, 0.80, 0.52),
                                      (0.30, 1.35, 1.00, 0.46))):   # ridges ON the dome
        G.rock(bm, (x, y, z), r, seed=70 + i, jitter=0.26, subdiv=0, scale=(1.4, 1.5, 0.55))
    G.part("Mound", bm, c, "Sand", (0.0, -0.20, 0.0), parent=None)

    bm = bmesh.new()                                    # the shadow skirt and drag marks
    G.lathe(bm, [(3.95, 0.0), (3.72, 0.10), (3.20, 0.13)], segs=12,
            matrix=G.place((0.0, -0.20, 0.01), scale=(0.80, 1.0, 1.0)))
    for i, (x, y, r) in enumerate(((1.95, -2.55, 0.85), (-1.85, -2.20, 0.72),
                                   (1.35, 2.15, 0.62), (-1.40, 2.35, 0.70))):
        G.prism(bm, _blot(r, 7, seed=80 + i, jitter=0.32), 0.0, 0.07,
                matrix=G.place((x, y, 0.02)))
    G.part("MoundDark", bm, c, "SandDark", (0.0, -0.20, 0.06), parent="Mound")

    bm = bmesh.new()                                    # sandstone chips shed on the way
    for i, (x, y, z, r) in enumerate(((1.62, 0.95, 0.64, 0.30), (-0.85, -1.95, 0.92, 0.26),
                                      (0.45, 2.45, 0.56, 0.28), (-1.95, 0.15, 0.46, 0.24),
                                      (2.35, -2.10, 0.30, 0.26))):
        G.rock(bm, (x, y, z), r, seed=90 + i, jitter=0.34, subdiv=0, scale=(1.3, 1.0, 0.7))
    for i in range(4):
        a = math.radians(48.0 + 84.0 * i)
        base = (math.cos(a) * 1.9, -0.20 + math.sin(a) * 2.6, 0.10)
        G.spike_shard(bm, base, (base[0] * 1.12, base[1] * 1.12, 0.62), 0.24, thick=0.13,
                      roll_deg=30.0 * i)
    G.part("Chips", bm, c, "Sandstone", (0.0, -0.20, 0.30), parent="Mound")

    bm = bmesh.new()                                    # the two closed lids on the front
    for s in (+1.0, -1.0):                              # spaced like the worm's own eyes
        at = (s * 1.16, 1.66, 0.98)
        n = (s * 0.40, 0.84, 0.36)
        _plate(G, bm, _eye_outline(0.56, 0.18), 0.22, at, n, s * -12.0)
        G.plank(bm, _plate_pt(at, n, s * -12.0, -0.54, 0.15, 0.13),
                _plate_pt(at, n, s * -12.0, 0.54, 0.15, 0.13), w=0.20, t=0.16, bevel=0.0)
    G.part("Lids", bm, c, "RingShadow", (0.0, 1.70, 0.98), parent="Mound")
    return c
