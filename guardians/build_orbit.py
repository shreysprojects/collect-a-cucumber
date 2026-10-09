"""Narmek biome guardian 8/10: ORBIT, the meteor colossus that never touches the ground.

Reference sheet: a legless cosmic being hanging in the air.  Its head is a dark navy
hood shaped like a crescent, with a grey MoonGrey crescent laid over the front of it and
a single purple crack burning across that face.  Sharp navy spikes sweep back off both
shoulders.  A cyan four-point diamond sits on the chest with a smaller one either side.
Below the waist the body gives up on anatomy: it tapers into a corkscrew swirl that ends
in a point with a starlight diamond on it - no legs at all.  Two hands float free with
no arms between them and the body, each a navy claw mount carrying three purple glowing
crystal claws.  Six navy meteor rocks, each with a cyan diamond set into it, ride a
tilted ring around the figure, with a scatter of navy chips drifting between them.  It
sleeps curled inside a crescent moon.
"""
import bmesh, math

COLLECTION = "Orbit"
GUARDIAN = "Orbit"
SEAT = "Orbit_Seat"

NOTES = (
    "12.35 studs tall (the point of the tail diamond at z 2.00 to the hood points at "
    "14.35).  THE WHOLE RIG HOVERS: nothing touches z 0 and nothing is meant to - the "
    "lowest geometry is the tail's starlight point at z 2.00, so the model sits in the "
    "air with a 2-stud gap under it, and the crescent moon it sleeps in is the SEAT, "
    "not part of the model.  The Hitbox is the BODY box, 8.2 x 7.4: robe, hood, swirl "
    "and both floating hands.  The orbit ring is deliberately outside it - the rocks "
    "ride a 7.9-stud circle and reach 9.9 across, and a query box round them would have "
    "a player touching the guardian three studs out in empty air.  Faces +Y; the "
    "character's RIGHT is +X, which is screen-LEFT in a render.  "
    "Rig: Root at the waist carries the Torso, the six orbit rocks, their gems and the "
    "chips; the Torso carries the shoulder yoke (and a spike cluster a side), the chest "
    "gem, the hood and both floating hands; the swirl hangs off the Torso in two "
    "segments so the tail can curl, and the tail-tip diamond is its own part.  The face "
    "is Crescent (grey) + CrescentShade + Crack; the Crack is the wake tell in place of "
    "eyes - Orbit has no EyeGlow role, and SLEEP_LOOK darkens Glow and Starlight "
    "together, so the crack, the claws and every diamond go out at once.  THE HEAD "
    "reads as a crescent or it reads as nothing: the moon face is 3.2 across against "
    "the hood's 3.6, opens 244 degrees so both horn ends stand 0.86 ABOVE its centre, "
    "and two shards carry those ends on to points at z 13.62, well over the hood rim at "
    "12.2.  A block fills the hood behind it so the opening shows dark navy and not "
    "sky, and the only other shapes on the head are the two long hood points sweeping "
    "out to x 1.92 and back to y -1.05.  FOUR THINGS A "
    "REVIEWER SHOULD KNOW.  (1) Every orbit rock, RockGems and Chips has its pivot AT "
    "THE RING CENTRE (0, 0, 6.40), not at its own middle, so one rotation per part "
    "spins the whole orbit - the dry run may flag those pivots as sitting outside their "
    "own geometry, which is exactly the intent.  The ring rides at the waist, where the "
    "robe becomes the swirl: higher up its raised front arc runs through the floating "
    "hands.  Every pose spins it about the RING'S OWN NORMAL (Rx(tilt).Rz(a).Rx(-tilt), "
    "handed to apply_pose as an XYZ Euler triple), so the rocks stay exactly on the "
    "tilted ring at any spin instead of sliding off it.  (2) The hands have no arms, so "
    "a pose cannot swing them - POSE_LOC moves them instead, and every pose here "
    "carries hand offsets as well as rotations.  They hang at x 3.20, a stud and a half "
    "clear of the robe, so the gap is the thing that says they are detached.  (3) The "
    "ring's rocks are 1.7-2.0 studs across on a radius of 3.95, which is past the "
    "widest point on the whole figure (the hands' outer edge at 3.68), so every rock "
    "centre rides outside the silhouette; at the ring's own height the robe is 1.6 "
    "across and the nearest rock face has 2.1 studs of air under it.  Four chips drift "
    "with them, not nine.  (4) Torso, Shoulders and Head "
    "stand above their pivots, so their pose rx is BACK-positive; Swirl, SwirlEnd and "
    "SwirlTip hang below theirs and are forward-positive."
)

# ---------------------------------------------------------------- the skeleton
HOVER = 2.00                       # the floor of the model: nothing below this
WAIST = (0.0, 0.0, 6.60)           # Torso pivot - the "hips" of a body with no legs
CHEST = (0.0, 0.0, 9.30)
SHOULDER_Z = 10.05
SHOULDER_X = 1.62
COLLAR_Z = 10.05                   # under the hood's rim, not inside the hood
NECK = (0.0, 0.0, 10.55)
HEAD_C = (0.0, -0.10, 11.95)
HOOD_R = 1.78
HORN_TOP = 14.35                   # the two sweeping hood points - long, and OUTBOARD of
                                   # the moon face so they frame it.  They used to run
                                   # from x 1.62 IN to x 1.02 and stop at 13.95, which
                                   # closed over the crescent like a knight's helm.
MASK_Y = 0.70                      # the grey moon face, laid on the front of the hood
# THE MOON FACE.  It has to read as a crescent at 100 studs, not as a ring or a visor.
# open_deg 244 puts each horn end 54 degrees ABOVE the centre line; the old 176 left them
# level with it, so the outline closed into a bowl and the opening never showed.  r_out
# 1.62 against the hood's 1.78 means the moon nearly fills the hood instead of floating
# in the middle of it, and two shards carry each horn on to a point above the hood rim.
MASK_C = (0.0, MASK_Y, 11.89)
MASK_ROUT, MASK_RIN, MASK_OFF, MASK_OPEN, MASK_THICK = 1.62, 1.06, 0.30, 244.0, 0.40
HORN_TIP_Z = 13.62                 # the grey horns' points; the hood rim is at z 12.2
HORN_TIP_X = 1.40

TAIL_TOP = (0.0, 0.0, 6.45)        # where the swirl leaves the hem
TAIL_MID = (0.10, -0.30, 4.30)     # the joint between the two tail segments
TAIL_END = (0.18, -0.52, 2.98)     # where the tail hands over to its diamond
TIP_C = (0.18, -0.52, 2.50)        # the diamond itself - its bottom point IS z 2.00

# The hands float with no arms, so the GAP is the only thing that says "detached".  At
# x 2.18 the mount sat directly under the 1.96-wide shoulder pad and read as a fist on a
# hidden arm; 3.20 puts 1.7 studs of empty air between the robe and the mount.
HAND = (3.20, 1.05, 8.35)          # the right hand; the left is mirrored in x
CLAW_ROOT = (3.20, 1.47, 8.35)     # where the three claws leave the mount

RING_C = (0.0, 0.0, 6.40)          # every orbit part pivots HERE - the waist, where the
                                   # robe becomes the swirl.  At the old 7.60 the ring's
                                   # high front arc ran straight through the floating
                                   # hands: the inner claw of each hand ended up INSIDE
                                   # the front rock, and a spin swept them through it.
# The ring has to orbit OUTSIDE the silhouette or the rocks read as rubble stuck to the
# robe.  3.95 puts every rock CENTRE past the widest point on the whole figure (the
# hands' outer edge at x 3.68), and at the ring's own height the robe is barely 1.6
# across, so the nearest rock face still has 2.1 studs of clear air under it.  At 3.00,
# with rocks this size, they would have been touching the hem.
RING_R = 3.95                      # 7.9 between rock centres, 9.9 across the rocks
RING_TILT = 17.0                   # degrees, the +Y side lifted
RING_PHASE = 60.0                  # 60/120/180/240/300/0: mirror-symmetric about x = 0,
                                   # which 62 was not (its mirror of 62 is 118, not 122)

# spike cluster on one shoulder: (y offset, z offset, length, root radius)
# Two per shoulder, not three, and swept BACK rather than up: three tall ones standing
# beside the hood were half of the "crown of spikes" the silhouette had to lose.
SHOULDER_SPIKES = ((0.26, 0.14, 2.15, 0.28), (-0.46, 0.24, 1.60, 0.23))
# Six substantial chunks, mirrored in pairs across x = 0 (the ring is symmetric now).
ROCK_R = (1.00, 1.00, 0.90, 0.84, 0.84, 0.90)
# drifting chips: (ring angle, radius as a fraction of RING_R, height offset, size, seed)
# Four, not nine.  Nine small ones turned the orbit into a debris field.
CHIPS = ((104.0, 1.14, 0.62, 0.30, 62), (196.0, 0.84, -0.48, 0.26, 64),
         (284.0, 1.12, 0.40, 0.28, 66), (26.0, 0.86, -0.42, 0.24, 68))

# the seat: a crescent moon 7 across, its outer rim resting on the ground
MOON_R = 3.50
MOON_Z = 3.50                      # centre of the outer circle, so its bottom is z 0
MOON_GEMS = ((-3.20, 3.10), (3.20, 3.10), (-1.53, 0.86), (0.0, 0.45), (1.53, 0.86))
MOON_CRATERS = ((0.0, 1.00, 0.46), (-1.60, 1.35, 0.54), (1.45, 1.75, 0.38),
                (-2.60, 2.60, 0.30))
MOON_SHARDS = ((2.95, -0.85, 3.95, 0.26, 71), (-3.05, 0.80, 3.70, 0.22, 72),
               (3.65, 0.60, 2.35, 0.19, 73), (-3.70, -0.70, 2.05, 0.21, 74),
               (1.20, 1.05, 4.15, 0.16, 75))

RING_PARTS = ["OrbitRock%d" % (i + 1) for i in range(6)] + ["RockGems", "Chips"]

# ---------------------------------------------------------------- the robe's surface
# Every bolt, socket and gem on the chest has to sit ON the robe, and the robe is an
# eight-sided lathe squashed to 0.86 in y - so the flat that faces the camera is at
# 0.9239 of the profile radius, not at the radius.  Placing trim at the radius buries
# it: that is how the first pass lost all five seam bolts, both gem sockets and the
# yoke plates inside the navy.  These two helpers give the real surface back.
TORSO_PROF = [(0.00, 0.00), (0.58, 0.06), (0.84, 0.72), (1.06, 1.62), (1.24, 2.38),
              (1.14, 3.06), (0.78, 3.50), (0.00, 3.66)]
TORSO_SCALE = (1.22, 0.86)
_OCT_FLAT, _OCT_CORNER = 0.92388, 0.38268      # cos/sin 22.5: an 8-gon at phase pi/8


def _torso_r(z):
    """The robe column's profile radius at world height `z`."""
    zl = z - WAIST[2]
    if zl <= TORSO_PROF[0][1]:
        return TORSO_PROF[0][0]
    for (r0, z0), (r1, z1) in zip(TORSO_PROF, TORSO_PROF[1:]):
        if zl <= z1:
            return r0 + (r1 - r0) * (zl - z0) / (z1 - z0)
    return TORSO_PROF[-1][0]


def _torso_y(z, x=0.0, out=0.0):
    """The y of the robe's FRONT surface at (x, z), `out` studs proud of it.

    +y falls on the middle of the front flat, which runs from x = -bx to +bx; past
    that the surface folds back along the 22.5-degree corner face."""
    r = _torso_r(z)
    bx, by = _OCT_CORNER * r * TORSO_SCALE[0], _OCT_FLAT * r * TORSO_SCALE[1]
    ax, ay = _OCT_FLAT * r * TORSO_SCALE[0], _OCT_CORNER * r * TORSO_SCALE[1]
    x = abs(x)
    if x <= bx:
        return by + out
    if x >= ax:
        return ay + out
    return by + (ay - by) * (x - bx) / (ax - bx) + out


CHEST_GEM = (0.0, _torso_y(9.38, out=0.10), 9.38)     # standing proud of the chest
SMALL_GEM = (0.68, _torso_y(9.02, x=0.68, out=0.10), 9.02)


def _ring_slot(i, n=6):
    """Where orbit rock `i` sits on the tilted ring."""
    return _ring_point(RING_PHASE + 360.0 * i / n, RING_R, 0.0)


def _ring_point(angle_deg, radius, dz):
    """A point on (or near) the ring: the ring is a circle tilted about the X axis."""
    a, t = math.radians(angle_deg), math.radians(RING_TILT)
    return (RING_C[0] + math.cos(a) * radius,
            RING_C[1] + math.sin(a) * radius * math.cos(t),
            RING_C[2] + math.sin(a) * radius * math.sin(t) + dz)


def _mask_horn(s):
    """Base and tip of one grey horn: the shard that carries the crescent's blunt end on
    to a point.  `crescent()` can never end in a point on its own - the outer and inner
    arcs close on a chord (r_out - r_in) * sin(open/2) wide, 0.48 here - so the base is
    the MIDDLE of that chord and the shard covers it exactly."""
    a = math.radians(-90.0 + MASK_OPEN / 2.0)
    x = (math.cos(a) * MASK_ROUT + math.cos(a) * MASK_RIN) / 2.0
    z = (math.sin(a) * MASK_ROUT + math.sin(a) * MASK_RIN + MASK_OFF) / 2.0
    return ((s * x, MASK_C[1], MASK_C[2] + z), (s * HORN_TIP_X, MASK_C[1], HORN_TIP_Z))


def _crack_points():
    """Five points tracing the belly of the moon face, kinked in and out so the crack
    reads as a break in the stone rather than a groove cut along it.

    They ride the MIDLINE between the crescent's two arcs - radius (r_out + r_in) / 2
    about a centre lifted by half the inner arc's offset - so the crack stays inside the
    grey at every point of the bigger, thinner-horned moon.  Held at a fixed radius it
    walked out through the opening as soon as the crescent opened up."""
    out = []
    mid_r, mid_z = (MASK_ROUT + MASK_RIN) / 2.0, MASK_C[2] + MASK_OFF / 2.0
    for i in range(5):
        a = math.radians(-158.0 + 34.0 * i)
        r = mid_r + (0.10 if i % 2 else -0.06)
        out.append((math.cos(a) * r, MASK_Y + 0.24, mid_z + math.sin(a) * r))
    return out


def _ring_spin(deg):
    """One rotation on every ring part - they all share the ring-centre pivot, so this
    is the whole orbit turning as one.

    It turns about the RING'S OWN NORMAL, not about Z.  The ring is the XY circle tilted
    `RING_TILT` about X, so the spin is Rx(t) . Rz(deg) . Rx(-t); a plain (0, 0, deg)
    keeps every rock at the height it started at, which lifts them off their own ring by
    up to 0.6 studs over a third of a turn and reads as a wobble instead of an orbit.
    apply_pose wants an XYZ Euler triple (its matrix is Rz.Ry.Rx), so the product is
    written out and decomposed here."""
    t, a = math.radians(RING_TILT), math.radians(deg)
    ct, st, ca, sa = math.cos(t), math.sin(t), math.cos(a), math.sin(a)
    m00, m10 = ca, ct * sa                       # the three entries the decomposition
    m20, m21, m22 = st * sa, st * ct * (ca - 1.0), st * st * ca + ct * ct   # needs
    rx = math.degrees(math.atan2(m21, m22))
    ry = math.degrees(math.asin(max(-1.0, min(1.0, -m20))))
    rz = math.degrees(math.atan2(m10, m00))
    return {n: (round(rx, 3), round(ry, 3), round(rz, 3)) for n in RING_PARTS}


# ---------------------------------------------------------------- the states
# WHICH WAY rx GOES HERE.  Torso, Shoulders and Head all stand ABOVE their own pivot
# (the waist, the yoke, the neck), so +rx tips them BACK and -rx is the slump - the
# opposite of what these four poses were first written with.  Swirl, SwirlEnd and
# SwirlTip all hang BELOW theirs, so +rx swings them forward, which is what they already
# said.  The hands and claws point forward along +Y, where -rx lifts them.
POSES = {
    # asleep, curled down into the crescent moon: hood drooped forward over the cup, tail
    # curled up under it, hands limp and tucked in, the orbit slowed to a stop and sunk
    "Sit": {
        "Torso": (-14, 0, 5), "Shoulders": (-8, 0, 0), "Head": (-24, 0, -6),
        "Spikes_R": (10, 0, 7), "Spikes_L": (10, 0, -7),
        # +18 against the torso's -14: the slump swings the tail root back, and this
        # brings the tip forward again so it lands IN the moon's cup, not behind it.
        "Swirl": (18, 0, -8), "SwirlEnd": (14, 0, 12), "SwirlTip": (10, 0, 0),
        "Hand_R": (26, 0, 32), "Hand_L": (26, 0, -32),
        "Claws_R": (30, 0, 8), "Claws_L": (30, 0, -8),
    },
    # the sheet's hero pose: risen, hood back, chest gem forward, both hands up and open
    "Awake": {
        "Torso": (7, 0, 0), "Shoulders": (5, 0, 0), "Head": (11, 0, 0),
        "Spikes_R": (14, 0, -5), "Spikes_L": (14, 0, 5),
        "Swirl": (6, 0, 6), "SwirlEnd": (9, 0, -8), "SwirlTip": (-6, 0, 0),
        "Hand_R": (-32, 0, -20), "Hand_L": (-32, 0, 20),
        "Claws_R": (-24, 0, -12), "Claws_L": (-24, 0, 12),
    },
    # the chase: it does not run, it leans and glides, hood first, tail streaming behind
    "Run": {
        "Torso": (-20, 0, 0), "Shoulders": (-6, 0, 0), "Head": (14, 0, 0),
        "Spikes_R": (12, 0, -3), "Spikes_L": (12, 0, 3),
        "Swirl": (-30, 0, 0), "SwirlEnd": (-22, 0, 4), "SwirlTip": (12, 0, 0),
        "Hand_R": (34, 0, -14), "Hand_L": (34, 0, 14),
        "Claws_R": (18, 0, 0), "Claws_L": (18, 0, 0),
    },
    # the signature: the gravity pull.  Arched back, hands thrown up and out, claws
    # splayed, the whole ring whipped round a third of a turn.
    "Pull": {
        "Torso": (16, 0, 0), "Shoulders": (8, 0, 0), "Head": (24, 0, 0),
        "Spikes_R": (18, 0, -8), "Spikes_L": (18, 0, 8),
        "Swirl": (14, 0, 0), "SwirlEnd": (18, 0, 0), "SwirlTip": (-10, 0, 0),
        "Hand_R": (-52, 0, -34), "Hand_L": (-52, 0, 34),
        "Claws_R": (-36, 0, -16), "Claws_L": (-36, 0, 16),
    },
}
for _name, _deg in (("Sit", -12), ("Awake", 10), ("Run", 26), ("Pull", 40)):
    POSES[_name].update(_ring_spin(_deg))

# No arms, so no rotation can move a hand through space - POSE_LOC does it instead.
POSE_LOC = {
    "Sit": dict({"Root": (0.0, 0.15, 0.55),
                 "Hand_R": (-0.75, -0.70, -1.45), "Hand_L": (0.75, -0.70, -1.45)},
                **{n: (0.0, 0.0, -1.25) for n in RING_PARTS}),
    "Awake": {"Root": (0.0, 0.0, 0.60),
              "Hand_R": (0.45, 0.55, 1.15), "Hand_L": (-0.45, 0.55, 1.15)},
    "Run": {"Root": (0.0, 0.0, -0.30),
            "Hand_R": (0.15, -1.15, -0.55), "Hand_L": (-0.15, -1.15, -0.55)},
    "Pull": {"Root": (0.0, 0.0, 1.10),
             "Hand_R": (1.15, 0.35, 2.05), "Hand_L": (-1.15, 0.35, 2.05)},
}


def build(G):
    _guardian(G)
    _seat(G)
    return G.coll(COLLECTION)


# ================================================================= the guardian
def _guardian(G):
    c = G.begin(COLLECTION, GUARDIAN)

    G.root_part(c, (-0.70, -0.55, WAIST[2] - 0.70), (0.70, 0.55, WAIST[2] + 0.70))
    # The BODY box: robe, hood points, swirl and both floating hands.  The orbit ring is
    # deliberately outside it - at radius 3.95 a box round the rocks would be 10 studs
    # across and a player would be "touching" the guardian three studs from empty air.
    G.hitbox(c, (-4.10, -3.70, HOVER - 0.05), (4.10, 3.70, 14.50), pivot=WAIST,
             parent="Root")

    _torso(G, c)
    _chest(G, c)
    _shoulders(G, c)
    _tail(G, c)
    _head(G, c)
    _face(G, c)
    for side in (+1, -1):
        _hand(G, c, side)
    _ring(G, c)


def _torso(G, c):
    """The robe column: an eight-sided lathe squashed in y, so the body is broad across
    the shoulders and thin front to back, with a hem where it becomes the swirl."""
    bm = bmesh.new()
    G.lathe(bm, [(0.00, 0.00), (0.58, 0.06), (0.84, 0.72), (1.06, 1.62), (1.24, 2.38),
                 (1.14, 3.06), (0.78, 3.50), (0.00, 3.66)],
            segs=8, phase=math.pi / 8, matrix=G.place(WAIST, None, (1.22, 0.86, 1.0)))
    G.lathe(bm, [(0.00, 0.00), (0.66, -0.04), (0.60, -0.42), (0.00, -0.66)],
            segs=8, phase=math.pi / 8, matrix=G.place(WAIST, None, (1.22, 0.86, 1.0)))
    G.part("Torso", bm, c, "Navy", WAIST, parent="Root")

    bm = bmesh.new()                                # the lighter plating over the navy
    for s in (+1, -1):                              # a collar-bone yoke plate a side
        # `plate` lays its outline in a frame whose local +x runs along world -x, so the
        # outline is flipped by -s to put each plate on its OWN side; 0.40 thick so the
        # back of the slab stays buried in the robe's curve and the front stands proud
        # of it at every height instead of diving in and out of the navy.
        G.plate(bm, [(-s * 0.30, 0.56), (-s * 1.26, 0.80), (-s * 0.98, -0.26),
                     (-s * 0.34, -0.62)], 0.40, at=(0.0, 0.99, 9.30),
                normal=(0, 1, 0.10))
    G.lathe(bm, [(1.00, 0.0), (1.13, 0.12), (1.13, 0.40), (1.00, 0.52)], segs=8,
            phase=math.pi / 8, matrix=G.place((0.0, 0.0, 7.30), None, (1.22, 0.86, 1.0)))
    for i in range(4):                              # bolts up the front seam, between
        z = 7.85 + 0.27 * i                         # the belt band and the gem socket
        G.hex_prism(bm, (0.0, _torso_y(z, out=0.03), z), 0.13, 0.16, axis=(0, 1, 0.08),
                    sides=6)
    G.hex_prism(bm, (0.0, _torso_y(CHEST_GEM[2], out=0.02), CHEST_GEM[2]), 0.54, 0.22,
                axis=(0, 1, 0.14), sides=6)         # the socket the big gem sits in
    for s in (+1, -1):                              # sockets under the two small gems
        G.hex_prism(bm, (s * SMALL_GEM[0], _torso_y(SMALL_GEM[2], x=SMALL_GEM[0],
                                                    out=0.02), SMALL_GEM[2]),
                    0.30, 0.22, axis=(s * 0.30, 1, 0.10), sides=6)
    G.part("TorsoTrim", bm, c, "NavyLight", CHEST, parent="Torso")


def _chest(G, c):
    """The cyan four-point diamond on the chest, with a smaller one either side of it."""
    bm = bmesh.new()
    G.diamond(bm, CHEST_GEM, radius=0.44, length=1.24, axis=(0, 0, 1), sides=4,
              squash=0.48)
    for s in (+1, -1):
        G.diamond(bm, (s * SMALL_GEM[0], SMALL_GEM[1], SMALL_GEM[2]), radius=0.22,
                  length=0.62, axis=(0, 0, 1), sides=4, squash=0.48)
    G.part("ChestGem", bm, c, "Starlight", CHEST_GEM, parent="Torso")


def _shoulders(G, c):
    """A yoke far wider than the waist, a squashed collar ring with two shards behind
    it, and two swept spikes a side."""
    bm = bmesh.new()
    G.beveled_box(bm, (-1.66, -0.64, 9.72), (1.66, 0.64, 10.30), bevel=0.16)
    for s in (+1, -1):
        G.crown_cube(bm, (s * 1.42, 0.0, 10.26), (1.08, 1.18, 0.80), bevel=0.18,
                     rot=G.rot_euler(0, s * 14, 0))
        # -s again: unflipped, this shard hung OUTBOARD on the left and ran inboard
        # across the chest on the right, which is the one asymmetry in the model.
        G.plate(bm, [(-s * 0.28, 0.02), (-s * 1.02, 0.32), (-s * 0.92, -0.44),
                     (-s * 0.24, -0.52)], 0.22, at=(s * 1.28, 0.74, 10.02),
                normal=(0, 1, 0.16))
    G.part("Shoulders", bm, c, "NavyLight", (0.0, 0.0, SHOULDER_Z), parent="Torso")

    bm = bmesh.new()
    # 1.10 wide but only 0.62 deep.  A round collar of radius 1.00 reaches y 0.92 at the
    # front, and the moon face's own belly now comes down to z 10.27 with its front at
    # 0.90 - a round one would push a navy nub out through the bright grey.  Squashed, it
    # still stands 0.10 proud of the robe at the sides, where it is the only place it
    # shows anyway.
    G.lathe(bm, [(0.56, 0.0), (1.00, 0.26), (0.94, 0.46), (0.50, 0.30)], segs=8,
            phase=math.pi / 8,
            matrix=G.place((0.0, 0.0, COLLAR_Z), None, (1.10, 0.62, 1.0)))
    # TWO shards, at the BACK of the collar, not a seven-point starburst round it.  The
    # ring of seven was the "dense crown of many small spikes": it framed the hood, but
    # with the shoulder spikes beside it the head grew a halo of eleven points and the
    # calm silhouette the sheet has went with it.  These two root inside the collar and
    # come out through the BACK of the hood, where they support its line without
    # breaking the front silhouette at all.
    for sx in (+1, -1):
        G.spike_shard(bm, (sx * 0.40, -0.46, COLLAR_Z + 0.23),
                      (sx * 0.95, -1.62, COLLAR_Z + 1.00), 0.34, thick=0.18)
    # it rests ON the yoke, so it hangs off the yoke: parented to the Torso it slid
    # 0.3 studs through its own shoulders every time a pose tipped them.
    G.part("Collar", bm, c, "Navy", (0.0, 0.0, COLLAR_Z), parent="Shoulders")

    for s in (+1, -1):
        tag = "R" if s > 0 else "L"
        bm = bmesh.new()
        for i, (dy, dz, length, r) in enumerate(SHOULDER_SPIKES):
            # out and BACK, rising only 0.6 of their length: the old tips climbed the
            # full length to z 12.5, level with the hood, so two pairs of shoulder spikes
            # joined the collar shards in the crown.  Now they sweep to y -0.9 and -1.6
            # and top out at 11.5, below the moon face, where they read as shoulders.
            base = (s * (1.38 + 0.12 * i), dy, SHOULDER_Z + dz)
            tip = (s * (2.26 + 0.34 * i), dy - 1.15, SHOULDER_Z + dz + length * 0.60)
            G.horn(bm, base, tip, r0=r, r1=0.04, bow=(s * 0.30, -0.10, 0.22), n=5, segs=4,
                   power=1.25)
        G.part("Spikes_" + tag, bm, c, "Navy",
               (s * SHOULDER_X, 0.0, SHOULDER_Z + 0.25), parent="Shoulders")


def _tail(G, c):
    """No legs: the body corkscrews down in two segments and ends on a starlight point.
    Two segments, not one, so a Run or a Pull can whip the tail instead of swinging a
    rigid spike."""
    bm = bmesh.new()
    G.swirl(bm, TAIL_TOP, TAIL_MID, r0=0.80, r1=0.46, turns=0.55, n=8, segs=6,
            wobble=0.30)
    for i in range(3):                              # wisps trailing off the coil
        a = math.radians(40 + 120 * i)
        p = G.lerp3(TAIL_TOP, TAIL_MID, 0.30 + 0.25 * i)
        G.spike_shard(bm, (p[0] + math.cos(a) * 0.40, p[1] + math.sin(a) * 0.40, p[2]),
                      (p[0] + math.cos(a) * 0.98, p[1] + math.sin(a) * 0.98, p[2] + 0.34),
                      0.26, thick=0.14)
    G.part("Swirl", bm, c, "Navy", TAIL_TOP, parent="Torso")

    bm = bmesh.new()
    G.swirl(bm, TAIL_MID, TAIL_END, r0=0.46, r1=0.08, turns=0.80, n=7, segs=6,
            wobble=0.26)
    G.ring_band(bm, G.mid3(TAIL_MID, TAIL_END), axis=(0.06, 0.16, 1.0), radius=0.30,
                minor=0.07, seg_major=6, seg_minor=4)
    G.part("SwirlEnd", bm, c, "Navy", TAIL_MID, parent="Swirl")

    bm = bmesh.new()
    G.diamond(bm, TIP_C, radius=0.34, length=1.00, axis=(0, 0, 1), sides=4)
    G.diamond(bm, (TIP_C[0], TIP_C[1], TIP_C[2] + 0.62), radius=0.15, length=0.40,
              axis=(0, 0, 1), sides=4)
    G.part("SwirlTip", bm, c, "Starlight", TAIL_END, parent="SwirlEnd")


def _head(G, c):
    """The hood: a crescent standing in XZ, a solid crown block filling it and backing
    the moon face's opening, and two long points sweeping out and back off its horns."""
    bm = bmesh.new()
    G.crescent(bm, center=HEAD_C, r_out=HOOD_R, r_in=1.16, offset=0.74, thick=1.55,
               open_deg=198, n=10, plane="XZ")
    # THE CROWN, and the dark the crescent opens onto.  The hood is itself a crescent, so
    # it has a hole of its own (r 1.16 about z 12.69) and the moon's new opening (r 1.06
    # about z 12.19) sits right inside it - left alone you would see straight through the
    # head.  This block covers the moon's hole whole (x +-1.10 against its +-1.06, z
    # 10.92-13.38 against its 11.13-13.25) and its bevelled top corners stay inside the
    # hood's outer circle, so above the hood's rim it becomes the crown the grey horns
    # rise out of.  It stops at y 0.53, just behind the moon, so the grey stands proud.
    # (The old chin block went with it: at z 10.30-10.95 it is now inside the moon's
    # belly, which reaches down to 10.30, and it poked through the grey at y 0.92.)
    G.crown_cube(bm, (0.0, -0.15, 12.15), (2.20, 1.36, 2.46), bevel=0.26)
    # THE TWO HOOD POINTS.  They are the whole silhouette above the shoulders, so they
    # are long (2.5 studs), thick at the root, and they sweep OUT and BACK: from the
    # hood's own horn ends at x 1.66 out to 1.92 and back to y -1.05, which leaves the
    # grey moon standing clear between them.  Before, they leaned inward to x 1.02 and
    # met over the crescent, and with the collar starburst around them the head read as a
    # dark knight's helm rather than a hood.
    for s in (+1, -1):
        G.horn(bm, (s * 1.66, HEAD_C[1] + 0.06, 12.15), (s * 1.92, -1.05, HORN_TOP),
               r0=0.46, r1=0.05, bow=(s * 0.34, -0.16, 0.30), n=6, segs=5, power=1.30)
    G.part("Head", bm, c, "Navy", NECK, parent="Torso")

    bm = bmesh.new()                                # the lighter rim round the hood -
    # and nothing else.  The two temple bolts and the two crest plates that used to sit
    # here are all inside the bigger moon face now, and every one of them was another
    # small shape radiating off the head.
    G.crescent(bm, center=(0.0, HEAD_C[1] + 0.12, HEAD_C[2]), r_out=HOOD_R + 0.14,
               r_in=HOOD_R - 0.16, offset=0.10, thick=0.90, open_deg=196, n=10,
               plane="XZ")
    G.part("HoodTrim", bm, c, "NavyLight", (0.0, 0.0, 12.30), parent="Head")


def _face(G, c):
    """The grey moon laid over the hood's front - a bold crescent 3.2 across with a wide
    opening and two pointed horns over the hood line - the shadow behind it, and the
    single purple crack that is this guardian's whole wake tell: it has no eyes."""
    bm = bmesh.new()
    G.crescent(bm, center=MASK_C, r_out=MASK_ROUT, r_in=MASK_RIN, offset=MASK_OFF,
               thick=MASK_THICK, open_deg=MASK_OPEN, n=12, plane="XZ")
    for s in (+1, -1):                              # the horns, carried on to a point
        base, tip = _mask_horn(s)
        # roll 90: spike_shard runs its `width` along the cross product of the shard's
        # own direction with +Z, which for an upright shard is Y - so unrolled the flat
        # of the shard would face sideways and the horn would read as a peg.  Rolled, the
        # width lies in X, in the crescent's own plane, and the thickness matches the
        # 0.40 slab it grows out of.
        G.spike_shard(bm, base, tip, 0.50, thick=MASK_THICK - 0.02, roll_deg=90)
    G.part("Crescent", bm, c, "MoonGrey", (0.0, MASK_Y - 0.14, MASK_C[2]), parent="Head")

    bm = bmesh.new()                                # a darker moon BEHIND the grey one:
    # bigger than the mask, not smaller.  At r_out 1.10 it sat entirely inside the mask
    # and behind it in y - a hundred triangles that could never be seen.  Bigger, it
    # rings the grey with a shadow edge, which is what separates the moon face from a
    # navy hood at 100 studs.  Its open_deg has to TRACK the mask's (240 against 244) or
    # the shade fills the horn gap back in and hands the ring silhouette straight back;
    # its hole (r_in 1.12 lifted 0.34) wholly contains the mask's (1.06 lifted 0.30), so
    # no shadow ever intrudes into the opening.
    # y 0.41-0.75: 0.075 proud of the hood slab's 0.675 front face (coplanar would
    # z-fight) and 0.15 behind the grey moon's 0.90.
    G.crescent(bm, center=(0.0, MASK_Y - 0.12, MASK_C[2]), r_out=1.76, r_in=1.12,
               offset=0.34, thick=0.34, open_deg=240, n=12, plane="XZ")
    G.part("CrescentShade", bm, c, "MoonShadow", (0.0, MASK_Y - 0.12, MASK_C[2]),
           parent="Crescent")

    bm = bmesh.new()
    pts = _crack_points()
    for i in range(len(pts) - 1):
        G.seam_strip(bm, pts[i], pts[i + 1], width=0.24, thick=0.17, segs=4)
    G.diamond(bm, pts[2], radius=0.19, length=0.50, axis=(0, 1, 0.0), sides=4)
    G.part("Crack", bm, c, "Glow", pts[2], parent="Crescent")


def _hand(G, c, s):
    """A claw mount floating where a hand would be.  There is no arm and no shoulder
    joint above it: it hangs off the Torso, and POSE_LOC is what moves it."""
    tag = "R" if s > 0 else "L"
    h = (s * HAND[0], HAND[1], HAND[2])

    bm = bmesh.new()
    G.crown_cube(bm, h, (0.96, 0.82, 0.78), bevel=0.18, rot=G.rot_euler(0, 0, -s * 16))
    G.hex_prism(bm, (h[0], h[1] + 0.36, h[2]), 0.42, 0.24, axis=(0, 1, 0.12), sides=6)
    G.hex_prism(bm, (h[0] - s * 0.36, h[1] - 0.28, h[2] + 0.10), 0.26, 0.22,
                axis=(s * 0.80, 0.40, 0.30), sides=6)
    G.ring_band(bm, (h[0], h[1] + 0.16, h[2]), axis=(0, 1, 0.12), radius=0.50, minor=0.09,
                seg_major=8, seg_minor=4)
    G.part("Hand_" + tag, bm, c, "NavyLight", h, parent="Torso")

    bm = bmesh.new()
    root = (s * CLAW_ROOT[0], CLAW_ROOT[1], CLAW_ROOT[2])
    for a in (58.0, 0.0, -58.0):
        ang = math.radians(a)
        base = (root[0] + s * math.sin(ang) * 0.30, root[1],
                root[2] + math.cos(ang) * 0.30)
        tip = (root[0] + s * math.sin(ang) * 0.74, root[1] + 1.30,
               root[2] + math.cos(ang) * 0.74 - 0.34)
        G.horn(bm, base, tip, r0=0.17, r1=0.02, bow=(0.0, 0.22, 0.0), n=5, segs=4,
               power=1.20)
    G.diamond(bm, (root[0], root[1] - 0.06, root[2]), radius=0.18, length=0.50,
              axis=(0, 1, 0.0), sides=4)
    G.part("Claws_" + tag, bm, c, "Glow", root, parent="Hand_" + tag)


def _ring(G, c):
    """Six meteor rocks 1.7-2.0 studs across on a 3.95 ring tilted 17 degrees, their
    gems, and the four chips drifting between them.  EVERY part here pivots at the ring
    centre, never at its own middle, so one rotation per part is the whole orbit
    turning."""
    for i in range(6):
        p = _ring_slot(i)
        r = ROCK_R[i]
        bm = bmesh.new()
        G.rock(bm, p, r, seed=21 + i, jitter=0.34, subdiv=1, scale=(1.0, 0.86, 0.78))
        G.stud_bump(bm, (p[0], p[1], p[2] + r * 0.70), normal=(0, 0, 1), radius=r * 0.34,
                    height=r * 0.20, segs=5)
        G.part("OrbitRock%d" % (i + 1), bm, c, "Navy", RING_C, parent="Root")

    bm = bmesh.new()
    for i in range(6):
        p = _ring_slot(i)
        # 1.56 = 2 x the rock's 0.78 z-squash, so the gem clears the stone it is set in
        # by the same 0.4 studs at every size instead of burying itself in the big ones.
        G.diamond(bm, p, radius=0.40, length=ROCK_R[i] * 1.56 + 0.80, axis=(0, 0, 1),
                  sides=4, squash=0.75)
    G.part("RockGems", bm, c, "Starlight", RING_C, parent="Root")

    bm = bmesh.new()
    for (ang, rad, dz, size, seed) in CHIPS:
        G.rock(bm, _ring_point(ang, rad * RING_R, dz), size, seed=seed, jitter=0.42,
               subdiv=0, scale=(1.0, 0.90, 0.80))
    G.part("Chips", bm, c, "NavyLight", RING_C, parent="Root")


# ================================================================= the crescent moon
def _seat(G):
    """The moon it sleeps in: a crescent 7 across resting on its outer rim, horns up,
    shadowed on the inside, with five starlight diamonds set into it."""
    c = G.begin(SEAT, GUARDIAN, prefix="OrbitSeat")

    bm = bmesh.new()
    G.crescent(bm, center=(0.0, 0.0, MOON_Z), r_out=MOON_R, r_in=2.55, offset=1.30,
               thick=1.40, open_deg=172, n=14, plane="XZ")
    G.part("Moon", bm, c, "MoonGrey", (0.0, 0.0, 0.0), parent=None)

    bm = bmesh.new()                                # the shaded inner face of the cup
    G.crescent(bm, center=(0.0, -0.26, MOON_Z + 0.06), r_out=3.20, r_in=2.46,
               offset=1.30, thick=0.96, open_deg=168, n=12, plane="XZ")
    for (x, z, r) in MOON_CRATERS:
        G.barnacle(bm, (x, 0.64, z), normal=(0, 1, 0), r_out=r, r_in=r * 0.52,
                   height=0.14, segs=6)
    G.part("MoonShade", bm, c, "MoonShadow", (0.0, 0.0, MOON_Z), parent="Moon")

    bm = bmesh.new()                                # one gem at each horn, three along
    for (x, z) in MOON_GEMS:                        # the belly - set into BOTH faces,
        for y in (0.62, -0.62):                     # so the moon reads from either side
            G.diamond(bm, (x, y, z), radius=0.34, length=0.52, axis=(0, 1, 0.04), sides=4)
    G.part("Gems", bm, c, "Starlight", (0.0, 0.0, MOON_Z), parent="Moon")

    bm = bmesh.new()                                # chips floating off the horns
    for (x, y, z, r, seed) in MOON_SHARDS:
        G.rock(bm, (x, y, z), r, seed=seed, jitter=0.40, subdiv=0, scale=(1.0, 0.85, 0.80))
    G.part("Shards", bm, c, "MoonShadow", (0.0, 0.0, MOON_Z), parent="Moon")
    return c
