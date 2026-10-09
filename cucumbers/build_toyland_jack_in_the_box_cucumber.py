"""Toyland: the Jack-in-the-Box Cucumber - a cucumber head in a red bowler hat popping out
of a red toy box on a green coiled spring."""
import bmesh, math

COLLECTION = "ToylandJackInTheBoxCucumber"
NOTES = (
    "A toy JACK-IN-THE-BOX.  A red toy_red box 2.4 x 2.4 x 2.1 (z 0 - 2.10, bevel 0.10) "
    "stands on the ground, centred on x = 0, y = 0; round its open top runs a proud rim "
    "frame 2.52 across (4 bevelled bars, lip 0.20 wide, z 1.90 - 2.22) and inside the frame "
    "a dark toy_red_dk plate (2.16 across, top z 2.13) reads as the open box's shadowed "
    "inside - the tile shows the box open, so the brief's solid rim band became a frame "
    "0.10 taller with a dark floor 0.09 below its lip.  A big yellow toy_yellow 5-point "
    "STAR (outer r 0.62, inner 0.27, point up) stands 0.06 proud of each of the four side "
    "faces, centred at z 1.0.  Two yellow square sticks (0.12 x 0.12, 1.5 long - the open "
    "lid's hinges) rise from the back top corners (x +-1.0, y -1.0, z 2.0) leaning 25 deg "
    "outward and 10 deg back, tips at (+-1.63, -1.24, 3.34).  A yellow CRANK sticks out of "
    "the box's NEGATIVE-x side (the screen right, as in the tile) behind that side's star: "
    "a 0.12-square stub along -X at y -0.78, z 1.10, reaching x -1.66, ending in an "
    "upturned 0.14 x 0.14 x 0.40 handle (x -1.72 - -1.58, z 1.02 - 1.42).  Stars, sticks "
    "and crank are ONE part, Yellow.  Out of the box rises a green cuke_green SPRING: a "
    "square-section coil (0.19 tall x 0.26 deep, no twist) on radius 0.55, 4.5 turns, "
    "z 2.05 - 3.25, 8 samples per turn so it is octagonal like the body - lofted with "
    "D.ribbon along radial frames instead of the brief's D.coil 0.13-radius round wire, "
    "because coil's aim()-rolled rings twist round the wire at every step and a 0.26-thick "
    "round wire at this 0.267 pitch would leave no gap between coils; its bottom end "
    "is buried in the box floor at the front, its top end runs into the head at the back.  "
    "On it sits the HEAD: the set's cucumber body scaled to h 2.3, r 0.70, base z 3.15, "
    "with the standard (0.30, 0.30) nub, facet 1 facing +Y.  The spring is merged into "
    "the Head part (same colour + material - the merge rule), so Head = spring + head.  "
    "Nine cuke_stud speckles (HeadStuds, size 0.28) are hand-slotted in three rows (zf "
    "0.17 / 0.48 / 0.78) so the face stays clear: none on facet 1 or on facet 2, and on "
    "facet 0 only one low stud (z 3.40 - 3.68) well under the nose; the top row is on the "
    "sides and back (facets 3 / 5 / 7), ~0.2 under the brim.  The FACE on facet 1: two "
    "black toy_eye rounded squares (0.30 x 0.36, 0.05 proud) at zf 0.62 (z 4.58), x "
    "+-0.21 (the Faces rule's 0.42 spacing, not the brief's +-0.22), each with a 0.10 "
    "white toy_eye_hl highlight in its upper OUTER corner (0.02 proud); the pair (0.72 "
    "across) is wider than the 0.54-wide front facet, so each eye is sunk 0.14 behind the "
    "facet plane and never floats off the receding side facet.  A dark-green NOSE block "
    "(0.30 x 0.24, 0.15 proud, bevelled) sits just under the eyes, z 4.10 - 4.34, in "
    "cuke_dark - one step darker than the brief's cuke_mid, because the tile's nose reads "
    "clearly darker than the head and cuke_mid barely differs in value from the skin.  "
    "A red BOWLER HAT - a flat 10-gon brim r 0.95 x 0.10 and an 8-sided crown r 0.62 "
    "tapering to 0.53 then chamfered to a flat top, 0.55 tall - sits on the head top "
    "(brim base z 5.28 on the axis), tilted 10 deg about X so its top tips TOWARD the "
    "viewer (brim underside ~5.12 at the front, ~5.44 at the back); the head's crown and "
    "nub are wholly inside it (>= 0.07 clear of the crown walls).  The hat shares "
    "the Box part (same colour + material).  Box, spring and head keep the brief's "
    "proportions rather than the tile's (the tile's head is a little smaller against the "
    "box).  Footprint about 3.4 x 2.6 (the crank and the two sticks are the extremes), "
    "height ~5.95 at the back edge of the tilted crown's top.  Lowest point: the box "
    "bottom, exactly z = 0.  All SmoothPlastic.  8 parts: Box, Opening, Yellow, Head, "
    "HeadStuds, Eyes, EyeShine, Nose; ~1670 tris.  Stars, eyes, the spring, the sticks "
    "and the hat are placed with matrices, so dryrun's bounding box is only an "
    "approximation.")

# ------------------------------------------------------------------ the box
BOX_HW, BOX_H, BOX_BEVEL = 1.20, 2.10, 0.10
RIM_OUT, RIM_IN = 1.26, 1.06           # the proud frame round the open top
RIM_Z0, RIM_Z1, RIM_BEVEL = 1.90, 2.22, 0.05
OPEN_HW, OPEN_Z0, OPEN_Z1 = 1.08, 2.06, 2.13   # dark floor inside the frame

# ------------------------------------------------------------------ yellow bits
STAR_Z, STAR_RO, STAR_RI = 1.00, 0.62, 0.27
STAR_PROUD, STAR_SINK = 0.06, 0.03
SIDES = [(0.0, 1.0, 0.0), (0.0, -1.0, 0.0), (1.0, 0.0, 0.0), (-1.0, 0.0, 0.0)]

STICK_W, STICK_L, STICK_BEVEL = 0.12, 1.50, 0.03
STICK_ROOTS = [(1.0, -1.0, 2.0), (-1.0, -1.0, 2.0)]    # the back top corners
LEAN_OUT, LEAN_BACK = 25.0, 10.0

# the crank: -X is the tile's RIGHT (renders look down -Y, so +X is screen-left)
CRANK_Y, CRANK_Z = -0.78, 1.10         # behind that side's star (its tips reach |y| 0.59)
STUB_W, STUB_X0, STUB_X1 = 0.12, -1.12, -1.66
HANDLE_W, HANDLE_X0, HANDLE_X1 = 0.14, -1.72, -1.58
HANDLE_Z0, HANDLE_Z1 = 1.02, 1.42      # 0.40 tall, bottom just under the stub's

# ------------------------------------------------------------------ the spring
SPRING_Z0, SPRING_Z1, SPRING_R = 2.05, 3.25, 0.55
SPRING_TURNS, SPRING_PER_TURN = 4.5, 8
SPRING_PHASE = 90.0                    # starts at the front, ends at the back
WIRE_H, WIRE_D = 0.19, 0.26            # vertical x radial: leaves ~0.08 gaps

# ------------------------------------------------------------------ the head
HEAD_Z, HEAD_H, HEAD_R = 3.15, 2.30, 0.70
NUB = (0.30, 0.30)

# (zf, facet): facet 1 = +Y face; 0 / 2 flank it.  Facet 0 carries only the low stud
# under the nose, facet 2 none: a zf-0.78 stud there sat 0.05 above the screen-right
# eye's outer corner and read as a one-sided eyebrow.  7 = +X (screen left), 3 = -X,
# 5 = back.
HEAD_SLOTS = [(0.17, 0), (0.17, 3), (0.17, 5),
              (0.48, 7), (0.48, 4), (0.48, 6),
              (0.78, 3), (0.78, 5), (0.78, 7)]    # 0.78: ~0.2 under the brim on the sides
STUD_SIZE, STUD_RISE = 0.28, 0.055

# ------------------------------------------------------------------ the face
EYE_ZF, EYE_DX = 0.62, 0.21
EYE_W, EYE_H, EYE_CORNER = 0.30, 0.36, 0.08
EYE_PROUD, EYE_SINK = 0.05, 0.14       # sunk deep: the eyes overhang the facet edges
SHINE, SHINE_PROUD, SHINE_SINK = 0.10, 0.02, 0.03
SHINE_DX, SHINE_DZ = 0.065, 0.10       # upper OUTER corner, inside the rounded corner

NOSE_W, NOSE_H, NOSE_PROUD, NOSE_SINK = 0.30, 0.24, 0.15, 0.10
NOSE_GAP = 0.056                       # between the nose top and the eyes' bottom

# ------------------------------------------------------------------ the hat
HAT_Z, HAT_TILT = 5.28, -10.0          # negative about X tips the top toward +Y
BRIM_R, BRIM_T = 0.95, 0.10
CROWN = [(0.0, 0.06), (0.62, 0.06), (0.53, 0.53), (0.44, 0.61), (0.0, 0.61)]


def _stick_tip(root, sx):
    """Lean the stick `LEAN_OUT` outward (toward sign `sx` in x) and `LEAN_BACK` back."""
    d = (sx * math.tan(math.radians(LEAN_OUT)), -math.tan(math.radians(LEAN_BACK)), 1.0)
    k = STICK_L / math.sqrt(d[0] ** 2 + d[1] ** 2 + d[2] ** 2)
    return (root[0] + d[0] * k, root[1] + d[1] * k, root[2] + d[2] * k)


def _spring_frames():
    """(point, outward radial normal) along the helix - fed to D.ribbon, whose cross
    section follows the normal, so the square wire never twists the way D.coil's
    aim()-oriented rings do."""
    n = int(round(SPRING_TURNS * SPRING_PER_TURN)) + 1
    out = []
    for i in range(n):
        t = i / float(n - 1)
        a = math.radians(SPRING_PHASE) + 2.0 * math.pi * SPRING_TURNS * t
        c, s = math.cos(a), math.sin(a)
        out.append(((SPRING_R * c, SPRING_R * s, SPRING_Z0 + (SPRING_Z1 - SPRING_Z0) * t),
                    (c, s, 0.0)))
    return out


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # the head's front facet plane (y) at the face's heights - facet 1 is flat
    face_y = D.cuke_radius(EYE_ZF) * HEAD_R * math.cos(math.pi / 8.0)
    eye_z = HEAD_Z + EYE_ZF * HEAD_H
    front = (0.0, 1.0, 0.0)

    # ---- red: the box, its rim frame, and the bowler hat ------------------
    bm = bmesh.new()
    D.beveled_box(bm, (-BOX_HW, -BOX_HW, 0.0), (BOX_HW, BOX_HW, BOX_H), bevel=BOX_BEVEL)
    for lo, hi in (((-RIM_OUT, RIM_IN, RIM_Z0), (RIM_OUT, RIM_OUT, RIM_Z1)),      # front
                   ((-RIM_OUT, -RIM_OUT, RIM_Z0), (RIM_OUT, -RIM_IN, RIM_Z1)),    # back
                   ((RIM_IN, -RIM_IN, RIM_Z0), (RIM_OUT, RIM_IN, RIM_Z1)),        # +x
                   ((-RIM_OUT, -RIM_IN, RIM_Z0), (-RIM_IN, RIM_IN, RIM_Z1))):     # -x
        D.beveled_box(bm, lo, hi, bevel=RIM_BEVEL)
    hat = D.place((0.0, 0.0, HAT_Z), D.rot_euler(HAT_TILT, 0.0, 0.0))
    D.prism(bm, D.ngon_pts(10, BRIM_R), 0.0, BRIM_T, matrix=hat)
    D.lathe(bm, CROWN, segs=8, phase=math.pi / 8.0, matrix=hat)
    D.new_obj("Box", bm, c, D.C("toy_red"), rbx_material="SmoothPlastic")

    # ---- the open box's dark inside ---------------------------------------
    bm = bmesh.new()
    D.box(bm, (-OPEN_HW, -OPEN_HW, OPEN_Z0), (OPEN_HW, OPEN_HW, OPEN_Z1))
    D.new_obj("Opening", bm, c, D.C("toy_red_dk"), rbx_material="SmoothPlastic")

    # ---- yellow: four stars, two hinge sticks, the crank -------------------
    bm = bmesh.new()
    star = D.star_pts(5, STAR_RO, STAR_RI, phase=math.pi / 2.0)    # a point straight up
    for n in SIDES:
        ctr = (n[0] * BOX_HW, n[1] * BOX_HW, STAR_Z)
        D.prism(bm, star, -STAR_SINK, STAR_PROUD, matrix=D.place(ctr) @ D.surface_frame(n))
    for root in STICK_ROOTS:
        D.branch_box(bm, root, _stick_tip(root, 1.0 if root[0] > 0 else -1.0), STICK_W,
                     bevel=STICK_BEVEL)
    h = STUB_W / 2.0
    D.beveled_box(bm, (STUB_X1, CRANK_Y - h, CRANK_Z - h), (STUB_X0, CRANK_Y + h, CRANK_Z + h),
                  bevel=0.03)
    h = HANDLE_W / 2.0
    D.beveled_box(bm, (HANDLE_X0, CRANK_Y - h, HANDLE_Z0), (HANDLE_X1, CRANK_Y + h, HANDLE_Z1),
                  bevel=0.035)
    D.new_obj("Yellow", bm, c, D.C("toy_yellow"), rbx_material="SmoothPlastic")

    # ---- green: the spring + the cucumber head (one colour, one part) -------
    bm = bmesh.new()
    D.ribbon(bm, _spring_frames(), WIRE_H, WIRE_D)
    D.cuke_body(bm, h=HEAD_H, r=HEAD_R, nub=NUB, matrix=D.place((0.0, 0.0, HEAD_Z)))
    D.new_obj("Head", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    D.cuke_studs(bm, h=HEAD_H, r=HEAD_R, slots=HEAD_SLOTS, size=STUD_SIZE, rise=STUD_RISE,
                 matrix=D.place((0.0, 0.0, HEAD_Z)))
    D.new_obj("HeadStuds", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- the face on facet 1 (+Y) ------------------------------------------
    eye = D.rounded_rect_pts(EYE_W, EYE_H, EYE_CORNER, segs=3)
    bm = bmesh.new()
    for sx in (1.0, -1.0):
        D.prism(bm, eye, -EYE_SINK, EYE_PROUD,
                matrix=D.place((sx * EYE_DX, face_y, eye_z)) @ D.surface_frame(front))
    D.new_obj("Eyes", bm, c, D.C("toy_eye"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    for sx in (1.0, -1.0):          # outer = away from the face's centre line
        D.stud_patch(bm, (sx * (EYE_DX + SHINE_DX), face_y + EYE_PROUD, eye_z + SHINE_DZ),
                     front, size=SHINE, rise=SHINE_PROUD, sink=SHINE_SINK, bevel=0.0)
    D.new_obj("EyeShine", bm, c, D.C("toy_eye_hl"), rbx_material="SmoothPlastic")

    nose_top = eye_z - EYE_H / 2.0 - NOSE_GAP
    bm = bmesh.new()
    D.beveled_box(bm, (-NOSE_W / 2.0, face_y - NOSE_SINK, nose_top - NOSE_H),
                  (NOSE_W / 2.0, face_y + NOSE_PROUD, nose_top), bevel=0.06)
    D.new_obj("Nose", bm, c, D.C("cuke_dark"), rbx_material="SmoothPlastic")

    return c
