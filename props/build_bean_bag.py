"""Three soft bean-bag seats side by side: a round Pouf, a slumped Slouch bag and a
cube Ottoman.  Nothing here is allowed a crisp edge - every mass is a jittered blob or a
barrelled lathe with a convex profile, and every join is hidden under a welt, a piped seam
or a stitch.  Crisp geometry is the failure mode for soft goods: a faceted blob reads as
folded paper and a straight-sided one reads as a crate, so the masses carry more, smaller
facets than the rest of the set and their outlines are never allowed to go concave.
Each variant faces +Y, is built around its own origin and then offset along X, so it is
separable by name prefix and drops into a game alone."""
import bmesh, math

COLLECTION = "BeanBag"
NOTES = (
    "Three separable soft-goods variants, prefixed A_ / B_ / C_, each built around its own "
    "origin and then moved to the X offset in VARIANTS.  Every one is a sit-on prop: no "
    "moving parts, no pivots, nothing below z = 0.  "
    "A_Pouf: 2.65 across x 1.64 tall (2.67 counting the leather tab hanging off the "
    "welt on the -X flank at z 0.54-0.82); a dark lathed base, a light welt ring at 0.62-0.94 "
    "that IS the widest point, a jittered purple dome over it and a tufted button set "
    "off-centre at plan (+0.16, -0.20), its disc standing proud to z 1.62 with four stitch "
    "creases cut INTO the fabric around it and dying out before the silhouette.  "
    "B_Slouch: 3.29 wide x 2.69 deep x 1.73 at the back bolster, 1.80 at the top of the "
    "carry strap; the back (-Y) is the tall end and the front (+Y) slumps.  The bag is a "
    "ring of four stuffed masses - tall back bolster, a big +X side roll, a smaller/lower "
    "-X one and a low front roll that closes the front - around a crater, and the sitting "
    "dent is a sag_sheet seat panel scooped into that crater: its rim is buried under all "
    "four masses at every corner and its underside clears the dark base crown by 0.15.  A "
    "back seam cord runs up the centre of the bolster and dies out below the crown; the zip "
    "run and its slider sit on the +X flank only, half-buried at z 0.79-0.95.  "
    "C_Ottoman: 2.16 x 2.16 x 1.48 including the button; one barrelled rounded-square body "
    "(widest at mid height, no plinth seam), a domed rounded-square top that overhangs it "
    "and dimples into a dark tufted button, ONE piping cord half-buried in the top seam, "
    "and four small wooden feet at (+-0.62, +-0.62) carrying z 0 to 0.10 under a body that "
    "starts at z 0.04."
)
VARIANTS = {
    "A": {"name": "Pouf",    "x": 6.0},
    "B": {"name": "Slouch",  "x": 0.0},
    "C": {"name": "Ottoman", "x": -5.8},
}

# The viewer stands on +Y, so +X is screen LEFT: A reads leftmost, C rightmost.
AX = VARIANTS["A"]["x"]
BX = VARIANTS["B"]["x"]
CX = VARIANTS["C"]["x"]

FAB = "Fabric"
LEA = "Leather"

# Purple pouf: four values off cloth_purple plus a tan leather tab.
P_DARK = "5b3a91"        # shaded lathed base - the ground half
P_LIGHT = "b28ce0"       # the welt ring, the one thing that catches light on the equator
P_DEEP = "3f2a66"        # tuft button + stitch creases

# Orange slouch bag: three values one step apart, plus the metal zip.  The body is a
# saturated pumpkin rather than the palette's paler cloth_orange - washed out by the render
# light that one read as kraft paper, which is exactly what a bean bag must not be.
O_DARK = "a8542a"        # squashed base, the back seam cord and the carry strap
O_BODY = "d4702a"        # the stuffed masses
O_LIGHT = "d8945a"       # the seat panel that carries the sitting dent

# Teal ottoman: three values off cloth_teal, a teal-tinted cream piping cord one step
# above the dome (a true cream read as a white luggage frame), dark wood feet.
T_DARK = "1c6e70"        # the tufted button
T_LIGHT = "5fc4bd"       # the domed top
T_PIPE = "a1c8c2"        # the single seam cord


# ---------------------------------------------------------------- A : Pouf
# The dome is an ellipsoid centred at (AX, 0, 0.84); the stitch creases are solved onto
# its surface so they lie ON the fabric instead of floating over it.
_A_CZ = 0.84
_A_SEMI = (1.20, 1.176, 0.744)
_A_BUTTON = (0.16, -0.20)        # button centre in plan, local to the pouf origin


def _pouf_z(dx, dy, lift=-0.05):
    """Height of the pouf dome at a plan offset from its centre.  `lift` is NEGATIVE by
    default: the body is a jittered rock whose facets chord up to ~0.09 inside this smooth
    ellipsoid, so a cord solved onto the ellipsoid itself lifts clean off the fabric.
    Sinking it makes the cord cut INTO the crown instead - which is what a stitch does."""
    t = 1.0 - (dx / _A_SEMI[0]) ** 2 - (dy / _A_SEMI[1]) ** 2
    return _A_CZ + _A_SEMI[2] * math.sqrt(max(0.03, t)) + lift


def _pouf(D, c):
    """A squashed purple blob on a dark lathed base, belted by a light welt at the
    equator and pinched by one off-centre tufted button."""
    # base: the shaded lower half.  Bellies out to r 1.24 at z 0.40 and pulls back in to
    # 1.12 under the dome, so the dome visibly overhangs it instead of stacking on it.
    bm = bmesh.new()
    D.lathe(bm, [(0.00, 0.00), (1.04, 0.00), (1.19, 0.14), (1.24, 0.40), (1.12, 0.64)],
            segs=12, matrix=D.place((AX, 0.0, 0.0)))
    D.new_obj("A_Base", bm, c, P_DARK, rbx_material=FAB, roughness=0.82)

    # welt: a piped ridge round the equator.  r 1.325 makes it the widest thing on the
    # prop, so it reads as a belt and hides the base/dome seam behind it.
    bm = bmesh.new()
    D.lathe(bm, [(1.10, 0.62), (1.325, 0.78), (1.10, 0.94)], segs=12, cap=False,
            matrix=D.place((AX, 0.0, 0.0)))
    D.new_obj("A_Welt", bm, c, P_LIGHT, rbx_material=FAB, roughness=0.7)

    # the cushion itself: a flattened jittered blob, never a lathe - the little dents in
    # its outline are what say "stuffed bag" from 40 studs
    bm = bmesh.new()
    D.rock(bm, (AX, 0.0, _A_CZ), 1.20, seed=41, jitter=0.075, subdiv=1,
           scale=(1.00, 0.98, 0.62))
    D.new_obj("A_Body", bm, c, D.C("cloth_purple"), rbx_material=FAB, roughness=0.75)

    # tuft: a dark button disc that stands PROUD of the crown (the dome is 1.566 high at
    # its plan point, so a button topping out below that is simply invisible), skirted down
    # to 1.40 so the fabric never shows daylight under it, with four stitch creases sunk
    # into the crown around it and tapered to nothing well inside the silhouette
    bm = bmesh.new()
    D.lathe(bm, [(0.00, 1.40), (0.34, 1.46), (0.30, 1.60), (0.00, 1.62)], segs=8,
            matrix=D.place((AX + _A_BUTTON[0], _A_BUTTON[1], 0.0)))
    for ang in (25.0, 115.0, 205.0, 295.0):
        a = math.radians(ang)
        pts = []
        for s in (0.24, 0.42, 0.60):
            dx = _A_BUTTON[0] + math.cos(a) * s
            dy = _A_BUTTON[1] + math.sin(a) * s
            pts.append((AX + dx, dy, _pouf_z(dx, dy)))
        D.tube(bm, pts, [0.060, 0.042, 0.012], segs=3)
    D.new_obj("A_Tuft", bm, c, P_DEEP, rbx_material=LEA, roughness=0.55)

    # the one asymmetric detail: a leather maker's tab caught in the welt on the -X flank
    # (screen RIGHT to a player standing in front of it) and HANGING DOWN off it - a plate
    # 0.26 wide and 0.28 tall, its top edge buried in the welt (r 1.325 at z 0.78) and its
    # body swinging clear as the flank falls away below.  Poking out sideways, small and
    # near-white, this used to read as a bolt through the seam.
    bm = bmesh.new()
    D.beveled_box(bm, (AX - 1.34, -0.13, 0.54), (AX - 1.28, 0.13, 0.82), bevel=0.02,
                  rot=D.rot_euler(rz=8))
    D.new_obj("A_Tag", bm, c, D.C("rope"), rbx_material=LEA, roughness=0.5)


# ---------------------------------------------------------------- B : Slouch
# The bag is a RING of four stuffed masses round a crater: the seat panel is the crater
# floor and every one of its rim points has to sit under one of them, or the panel reads as
# a sheet of card laid on a sack.  These four were solved against that constraint (worst
# rim point is 0.06 under the fabric) while still letting a 24-degree hero camera see down
# into the dent over the front roll.
_B_BOLSTER = ((BX, -0.78, 0.90), (1.42, 0.66, 0.80))       # tall back, crown z 1.70
_B_LOBE_P = ((BX + 1.00, -0.25, 0.78), (0.64, 1.34, 0.66))  # +X side roll: the big one
_B_LOBE_M = ((BX - 0.90, -0.26, 0.73), (0.64, 1.05, 0.60))  # -X side roll: smaller, lower
_B_ROLL = ((BX - 0.09, 0.64, 0.67), (1.56, 0.46, 0.52))     # low front roll, top z 1.19

# Back seam: sampled round the y-z ellipse of the bolster at 1.03x its semi-axes, so the
# cord is half-buried in the fabric instead of arching over it, and it dies out at z 1.62 -
# below the 1.70 crown - with its radius tapered to nothing.
_B_SEAM = [(BX, -1.139, 0.20), (BX, -1.395, 0.55), (BX, -1.460, 0.92),
           (BX, -1.374, 1.30), (BX, -1.246, 1.50), (BX, -1.111, 1.62)]
_B_SEAM_R = [0.085, 0.085, 0.085, 0.070, 0.050, 0.030]


def _slouch(D, c):
    """A big slumped bag: tall bolster at the -Y back, side rolls of deliberately different
    sizes, a low roll closing the front and a sagging seat panel scooped between them."""
    # base: a wide jittered pancake, the darkest value, and the ground contact.  Its crown
    # is at z 0.78 and the seat panel's underside is kept 0.15 clear of it - coplanar was
    # what speckled the old panel.
    bm = bmesh.new()
    D.rock(bm, (BX, -0.10, 0.42), 1.45, seed=12, jitter=0.06, subdiv=1,
           scale=(1.03, 0.82, 0.25))
    # back seam, running up the centre of the bolster and dying into the dark base
    D.tube(bm, _B_SEAM, _B_SEAM_R, segs=4)
    D.new_obj("B_Base", bm, c, O_DARK, rbx_material=FAB, roughness=0.85)

    # the bag mass.  subdiv=2 on the three masses that own the silhouette: at subdiv=1 a
    # rock this big is 80 facets half a stud across meeting at sharp creases, which is the
    # language of folded paper, not stuffing.  The jitter comes down with it so the outline
    # stops going concave; only the smaller -X roll stays at subdiv=1 for the tri budget.
    bm = bmesh.new()
    D.rock(bm, _B_BOLSTER[0], 1.00, seed=7, jitter=0.04, subdiv=2, scale=_B_BOLSTER[1])
    D.rock(bm, _B_LOBE_P[0], 1.00, seed=19, jitter=0.04, subdiv=2, scale=_B_LOBE_P[1])
    D.rock(bm, _B_LOBE_M[0], 1.00, seed=31, jitter=0.05, subdiv=1, scale=_B_LOBE_M[1])
    D.rock(bm, _B_ROLL[0], 1.00, seed=23, jitter=0.04, subdiv=2, scale=_B_ROLL[1])
    D.new_obj("B_Body", bm, c, O_BODY, rbx_material=FAB, roughness=0.78)

    # seat panel: a small scoop pinned at 1.19 under the bolster and 1.03 under the front
    # roll, dipping to 0.99 in the middle.  Every rim corner lands well inside the
    # surrounding fabric, so what shows is the dent, never the panel's edge.
    bm = bmesh.new()
    D.sag_sheet(bm, (BX - 0.66, -0.31, 1.19), (BX + 0.56, 0.44, 1.03),
                sag=0.11, nx=5, ny=4, thickness=0.06)
    D.new_obj("B_Seat", bm, c, O_LIGHT, rbx_material=FAB, roughness=0.72)

    # carry strap lying ON the bolster crown, planted just off centre: a thin dark web
    # sunk into the fabric at both ends, half-buried at the top of its arch.  In near-white
    # canvas at 0.085 arching to 1.96 this was a toolbox handle.
    bm = bmesh.new()
    D.tube(bm, [(BX + 0.46, -0.62, 1.46), (BX + 0.44, -0.78, 1.66),
                (BX + 0.04, -0.88, 1.74), (BX - 0.36, -0.78, 1.66),
                (BX - 0.38, -0.62, 1.45)], [0.06] * 5, segs=5)
    D.new_obj("B_Handle", bm, c, O_DARK, rbx_material=LEA, roughness=0.6)

    # zip: a short toothed run along the widest part of the +X flank, solved onto that
    # roll's surface at 0.98x its semi-axes so the teeth half-bury in the fabric, with the
    # slider parked two thirds along.  No pull tab - free-floating at this size it read as
    # a signpost stuck in the bag.
    bm = bmesh.new()
    D.tube(bm, [(BX + 1.600, -0.60, 0.86), (BX + 1.618, -0.10, 0.86),
                (BX + 1.553, 0.35, 0.86), (BX + 1.416, 0.72, 0.86)],
           [0.05] * 4, segs=4)
    D.box(bm, (BX + 1.46, 0.30, 0.79), (BX + 1.60, 0.46, 0.95))
    D.new_obj("B_Zip", bm, c, D.C("metal_light"), rbx_material="Metal",
              metallic=0.6, roughness=0.4)


# ---------------------------------------------------------------- C : Ottoman
# Rounded-square plan: lathe at segs=8, phase 22.5 deg, so a flat faces the camera and the
# four corners are cut off - a square that has softened, not an octagon on show.  A ring's
# half-width across the flats is radius * cos(22.5 deg), so radius = half-width * 1.0824
# and the numbers below are quoted as half-widths in the comments.
_C_PHASE = math.pi / 8.0
_C_K = 1.0 / math.cos(math.pi / 8.0)


def _hw(pairs):
    """(half-width, z) -> (lathe radius, z)."""
    return [(w * _C_K, z) for w, z in pairs]


# body: barrelled, widest at mid height, and it carries the plinth itself - as two stacked
# blocks the split showed only as a horizontal seam, i.e. two slabs.
_C_BODY = _hw([(0.86, 0.04), (1.00, 0.24), (1.08, 0.62), (1.00, 1.00), (0.93, 1.16)])
# dome: a crown, not a hip roof - the old segs=4 lathe had dead-straight ridges and a flat
# plateau.  It domes over and then dimples back down to a pole so the button sits IN it.
_C_DOME = _hw([(0.93, 1.06), (0.95, 1.17), (0.88, 1.30), (0.62, 1.41), (0.36, 1.45)]) \
    + [(0.00, 1.40)]
_C_PIPE_R = 1.02         # lathe-radius units: right on the dome/body seam at z 1.13
_C_PIPE_Z = 1.13
_C_FOOT_XY = 0.62


def _ottoman(D, c):
    """A cube ottoman that has given up being a cube: one barrelled rounded-square body, a
    domed top dimpled round a tufted button, one piping cord in the seam, four little
    feet the body settles onto."""
    # the tufted button, sunk into the dimple in the crown and standing 0.03 proud of it.
    # The only dark object on the variant.
    bm = bmesh.new()
    D.lathe(bm, [(0.00, 1.34), (0.30, 1.38), (0.28, 1.47), (0.00, 1.48)], segs=8,
            matrix=D.place((CX, 0.0, 0.0)))
    D.new_obj("C_Button", bm, c, T_DARK, rbx_material=FAB, roughness=0.82)

    # body: one convex barrel from z 0.04 (so the fabric squashes onto the floor over the
    # feet rather than perching on them) up to the seam
    bm = bmesh.new()
    D.lathe(bm, _C_BODY, segs=8, phase=_C_PHASE, matrix=D.place((CX, 0.0, 0.0)))
    D.new_obj("C_Body", bm, c, D.C("cloth_teal"), rbx_material=FAB, roughness=0.78)

    # domed top: overhangs the body between z 1.13 and 1.30, crowns at 1.45
    bm = bmesh.new()
    D.lathe(bm, _C_DOME, segs=8, phase=_C_PHASE, matrix=D.place((CX, 0.0, 0.0)))
    D.new_obj("C_Dome", bm, c, T_LIGHT, rbx_material=FAB, roughness=0.72)

    # piping: ONE cord, following the plan octagon so every straight run lies along a face
    # of the seam instead of orbiting it, half-buried where the dome crosses the body.  The
    # four vertical corner runs are gone - stood off the chamfer they were a luggage frame.
    bm = bmesh.new()
    ring = D.ngon_pts(8, _C_PIPE_R, phase=_C_PHASE, center=(CX, 0.0))
    ring = ring[5:] + ring[:5]                       # start the loop at the back
    pts = [(p[0], p[1], _C_PIPE_Z) for p in ring]
    D.tube(bm, pts + [pts[0]], [0.045] * (len(pts) + 1), segs=4)
    D.new_obj("C_Piping", bm, c, T_PIPE, rbx_material=LEA, roughness=0.5)

    # four squat tapered feet, the only hard material on the whole prop
    bm = bmesh.new()
    f = _C_FOOT_XY
    for sx in (1, -1):
        for sy in (1, -1):
            D.cyl(bm, (CX + sx * f, sy * f, 0.0), (CX + sx * f, sy * f, 0.10),
                  0.15, segs=4, r2=0.12)
    D.new_obj("C_Feet", bm, c, D.C("wood_dark"), rbx_material="Wood", roughness=0.6)


# ---------------------------------------------------------------- build
def build(D):
    """D is the imported proplib module.  Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    _pouf(D, c)
    _slouch(D, c)
    _ottoman(D, c)
    return c
