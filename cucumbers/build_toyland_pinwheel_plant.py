"""Toyland: Pinwheel Plant - a six-blade toy pinwheel flower planted in a green toy brick."""
import bmesh, math

COLLECTION = "ToylandPinwheelPlant"
NOTES = (
    "A toy pinwheel 'flower' on a curved green stem, planted in a green toy brick.  "
    "BRICK: two bevelled toy_green halves side by side, together 2.2 x 2.2 x 0.95 "
    "(z 0-0.95, the lowest point of the model), so the joint between them reads as the "
    "seam down the tile's front face; on top, four chunky 8-sided studs (r 0.30, 0.18 "
    "tall, chamfered tops, flat faces square to the brick) on a 2 x 2 grid 1.0 apart.  "
    "STEM: a 0.36-wide square-section toy_green_dk stalk of seven bevelled branch_box "
    "segments.  It rises out of the brick between the studs just screen-left of centre "
    "(x +0.10), bows gently to screen-RIGHT as it climbs (x -0.09 around z 3.0, the "
    "lean the tile's stem has) and swings back to x = 0 behind the pinwheel; in side "
    "view it leans back 0.125 so its front face (y 0.055) stays just behind the blades, "
    "and it ends at z 4.58 behind the hub.  Five raised toy_green speckles sit on the "
    "stem (three on its front, one on each side) and are merged into the Brick part "
    "(same colour + material).  PINWHEEL: faces +Y, disc in the XZ plane, centred at "
    "(0, 0.10, 4.40).  Six folded-kite blades at 60-degree steps, 1.55 from the hub "
    "centre to the tip, 0.08 thick (y 0.06-0.14); each is two triangles sharing the "
    "radial crease hub -> tip: a narrow flat half on the vane's CLOCKWISE side (as you "
    "face it) and a broad half on its anticlockwise side folded 25 degrees toward the "
    "viewer (its outer corner stands 0.27 proud, y 0.41), which is how every vane in "
    "the tile is drawn - a straight edge clockwise, the bulge anticlockwise - so it "
    "reads as a pinwheel vane, not a flat fan.  Clockwise from the top-left as you face "
    "it: blue, red, yellow, green, green, yellow - i.e. world angle alpha = 73 + 60*i "
    "measured from +X toward +Z, so blue (alpha 73, tip at x +0.45, z 5.88) is on the "
    "+X side = screen-LEFT and the two yellows sit at alpha 13 (screen-left) and 193 "
    "(screen-right); the tips land within ~8 degrees of the tile's.  The stem shows "
    "through the narrow gap between the two lower green blades, as in the tile.  HUB: a "
    "toy_red_dk 10-sided disc r 0.36 x 0.20 with a chamfered front (y 0.13-0.33) plus a "
    "hidden r 0.12 axle through the blade centre into the stem; a chamfered green centre "
    "stud r 0.16 x 0.14 on its front (y 0.32-0.46) lives in the BladeGreen part.  About "
    "3.03 wide x 2.2 deep x 5.89 tall, centred on x = 0, y = 0, nothing below z = 0.  "
    "Seven parts: Brick, Stem, BladeBlue, BladeRed, BladeYellow, BladeGreen, Hub.  The "
    "rotor (BladeBlue, BladeRed, BladeYellow, BladeGreen, Hub) shares no colour with the "
    "static Brick/Stem, so it can be spun as a group about the Y axis through "
    "PinwheelHub; the six blades are centrally symmetric, so the group's bounding-box "
    "centre in x and z IS the hub (in y the rotor spans -0.03 to 0.46, axle to centre "
    "stud).  Deviations, all tile-driven: the hub is toy_red_dk, not "
    "toy_red (the tile's hub reads a step darker than its red blade, it keeps the "
    "adjacent hub and blade apart in value, and a toy_red hub would have to merge into "
    "BladeRed under the same-colour rule); the green blades + centre stud are "
    "plastic_green, not toy_green (the tile's blade green samples a touch bluer than its "
    "brick, and a distinct colour keeps the spinning rotor separable from the brick "
    "without breaking the merge-same-colour rule - FarmWindmillPlant used a material "
    "switch for the same reason, but Toyland is SmoothPlastic throughout); the stem is "
    "0.36 wide, not 0.26 (the tile's stem is nearly as wide as a brick stud, ~0.5; 0.36 "
    "keeps it reading as a stalk); the studs "
    "are 8-sided rounded squares rather than round (as drawn in the tile); the brick is "
    "two halves (the tile's front seam); the stem runs BEHIND the blades to the back of "
    "the hub rather than to the hub point itself (the tile shows it passing behind the "
    "lower green blades); the tile's hub sits ~0.4 screen-right of the stem's foot, but "
    "the hub is kept on x = 0 as the brief asks so the footprint stays centred.  "
    "Blades, hub and studs are placed with matrices, so dryrun's bounding box "
    "under-reads the width and height.")

PIVOTS = {"PinwheelHub": (0.0, 0.10, 4.40)}     # spin axis: +Y through this point
STATES = {"Spin": 60.0}                          # one blade step

# ------------------------------------------------------------------ the brick
BRICK_W, BRICK_H = 2.20, 0.95
BRICK_BEVEL = 0.06
STUD_R, STUD_H = 0.30, 0.18                     # 8-sided, circumradius
STUD_SINK = 0.02
STUD_CHAMFER = 0.05
STUD_GRID = 1.0

# ------------------------------------------------------------------ the stem
STEM_W = 0.36
STEM_BEVEL = 0.04
STEM_Z0, STEM_Z1 = 0.85, 4.58                   # sunk 0.10 into the brick; top behind hub
STEM_X0 = 0.10                                  # foot, just screen-left of centre
STEM_BOW = 0.14                                 # bow toward -x (screen-right)
STEM_BACK = -0.125                              # how far it leans back (front face 0.055)
STEM_BACK_BY = 0.60                             # ... reached by this fraction of the rise
STEM_SEGS = 7
STEM_OVERLAP = 0.05                             # segments run into each other at the joints

# speckles on the stem: (segment, fraction along it, face, sideways offset)
STEM_SPECKS = [
    (1, 0.30, "front", -0.04),
    (1, 0.75, "left", 0.00),                    # +x face = screen-left
    (2, 0.45, "front", 0.05),
    (3, 0.15, "right", 0.00),                   # -x face = screen-right
    (3, 0.75, "front", -0.04),
]
SPECK_SIZE, SPECK_RISE = 0.16, 0.04

# ------------------------------------------------------------------ the pinwheel
HUB_Z = 4.40
BLADE_Y = 0.10                                  # blade mid-plane
BLADE_T = 0.08                                  # blade thickness (along Y)
FOLD = 25.0                                     # the broad half folds toward the viewer
# blade outline in its own frame: u out along the crease, v toward increasing alpha.
# World angle alpha runs from +X toward +Z; +X renders on the LEFT, so increasing alpha
# is CLOCKWISE as you face it.  In the tile every vane has its straight, narrow edge on
# its clockwise side and its broad bulge on its anticlockwise side, so the narrow flat
# half is at +v and the broad folded half at -v.
BLADE_TIP = (1.55, 0.00)
BLADE_FLAT = (0.92, 0.32)                       # narrow flat half: r 0.97, 19 deg (CW)
BLADE_FOLD = (0.84, -0.64)                      # broad folded half: r 1.06, 37 deg (ACW)
# Top-left blue, then clockwise round the dial.  73 + 60*i puts the six tips within
# ~7 degrees of where the tile draws them (screen angles 107, 47, -13, -73, -133, 167).
BLADES = [(73.0, "blue"), (133.0, "red"), (193.0, "yellow"),
          (253.0, "green"), (313.0, "green"), (13.0, "yellow")]

HUB_R, HUB_T = 0.36, 0.20
HUB_Y0 = BLADE_Y + BLADE_T / 2.0 - 0.01         # 0.13: sits on the blades' front
HUB_CHAMFER = 0.06
AXLE_R, AXLE_Y0 = 0.12, -0.03                   # hidden pin into the stem's front
CAP_R, CAP_T = 0.16, 0.14                       # the green centre stud
CAP_Y0 = HUB_Y0 + HUB_T - 0.01                  # 0.32


def _stem_points():
    """Centre line of the stalk: a gentle bow toward -x in front view, an S leaning
    back in side view, both ends on the brick / hub axes."""
    pts = []
    for i in range(STEM_SEGS + 1):
        t = i / float(STEM_SEGS)
        x = STEM_X0 * (1.0 - t) - STEM_BOW * math.sin(math.pi * t)
        s = min(1.0, t / STEM_BACK_BY)
        y = STEM_BACK * (3.0 * s * s - 2.0 * s ** 3)
        z = STEM_Z0 + (STEM_Z1 - STEM_Z0) * t
        pts.append((x, y, z))
    return pts


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _unit(v):
    n = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    return (v[0] / n, v[1] / n, v[2] / n)


def _box_axes(d):
    """Where branch_box's local +x and +y faces point for a beam along unit `d`.

    branch_box aims local +Z down the beam with the SHORTEST-ARC rotation from +Z
    (Vector.rotation_difference); this is that rotation's first two columns."""
    a, b, c = d
    k = 1.0 / (1.0 + c)
    col_x = (1.0 - a * a * k, -a * b * k, -a)
    col_y = (-a * b * k, 1.0 - b * b * k, -b)
    return col_x, col_y


def _blade_frame(D, alpha):
    """Local x -> out along the blade (alpha from +X toward +Z), local y -> toward
    increasing alpha, local z -> world -Y.  rot_euler(90, -alpha, 0) = Ry(-alpha) @ Rx(90)."""
    return D.place((0.0, BLADE_Y, HUB_Z), D.rot_euler(90.0, -alpha, 0.0))


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    hw = BRICK_W / 2.0
    h = STEM_W / 2.0

    # ---- brick: two halves (the seam), four chunky studs, the stem's speckles --------
    bm = bmesh.new()
    D.beveled_box(bm, (-hw, -hw, 0.0), (0.0, hw, BRICK_H), bevel=BRICK_BEVEL)
    D.beveled_box(bm, (0.0, -hw, 0.0), (hw, hw, BRICK_H), bevel=BRICK_BEVEL)
    z0 = BRICK_H - STUD_SINK
    z1 = BRICK_H + STUD_H
    stud_prof = [(STUD_R, z0), (STUD_R, z1 - STUD_CHAMFER),
                 (STUD_R - STUD_CHAMFER * 1.2, z1), (0.0, z1)]
    g = STUD_GRID / 2.0
    for sx, sy in ((g, g), (-g, g), (g, -g), (-g, -g)):
        D.lathe(bm, stud_prof, segs=8, phase=math.pi / 8.0, matrix=D.place((sx, sy, 0.0)))

    pts = _stem_points()
    for seg, f, face, side in STEM_SPECKS:
        p0, p1 = pts[seg], pts[seg + 1]
        d = _unit(_sub(p1, p0))
        col_x, col_y = _box_axes(d)
        if face == "front":
            n, lat = col_y, col_x
        elif face == "left":
            n, lat = col_x, col_y
        else:
            n, lat = (-col_x[0], -col_x[1], -col_x[2]), col_y
        p = tuple(p0[i] + (p1[i] - p0[i]) * f + n[i] * h + lat[i] * side for i in range(3))
        D.stud_patch(bm, p, n, size=SPECK_SIZE, rise=SPECK_RISE, bevel=0.025)
    D.new_obj("Brick", bm, c, D.C("toy_green"), rbx_material="SmoothPlastic")

    # ---- stem: overlapping square beams along the bowed centre line --------------------
    bm = bmesh.new()
    last = len(pts) - 2
    for i in range(len(pts) - 1):
        p0, p1 = pts[i], pts[i + 1]
        d = _unit(_sub(p1, p0))
        e0 = 0.0 if i == 0 else STEM_OVERLAP
        e1 = 0.0 if i == last else STEM_OVERLAP
        a = (p0[0] - d[0] * e0, p0[1] - d[1] * e0, p0[2] - d[2] * e0)
        b = (p1[0] + d[0] * e1, p1[1] + d[1] * e1, p1[2] + d[2] * e1)
        D.branch_box(bm, a, b, STEM_W, bevel=STEM_BEVEL)
    D.new_obj("Stem", bm, c, D.C("toy_green_dk"), rbx_material="SmoothPlastic")

    # ---- the six folded blades, one bmesh per colour ----------------------------------
    flat = [(0.0, 0.0), BLADE_TIP, BLADE_FLAT]
    fold = [(0.0, 0.0), BLADE_FOLD, BLADE_TIP]
    colour = {"blue": ("BladeBlue", "toy_blue"), "red": ("BladeRed", "toy_red"),
              "yellow": ("BladeYellow", "toy_yellow"), "green": ("BladeGreen", "plastic_green")}
    meshes = {k: bmesh.new() for k in colour}
    for alpha, key in BLADES:
        bm = meshes[key]
        m = _blade_frame(D, alpha)
        D.prism(bm, flat, -BLADE_T / 2.0, BLADE_T / 2.0, matrix=m)
        # rotating about the crease (local x) by +FOLD swings -v toward local -z = world +Y
        D.prism(bm, fold, -BLADE_T / 2.0, BLADE_T / 2.0, matrix=m @ D.rot_euler(FOLD, 0.0, 0.0))

    # the green centre stud rides with the green blades
    face_y = D.rot_euler(-90.0, 0.0, 0.0)          # lathe axis (local +z) -> world +Y
    cap_prof = [(0.0, 0.0), (CAP_R, 0.0), (CAP_R, CAP_T - 0.05),
                (CAP_R - 0.045, CAP_T), (0.0, CAP_T)]
    D.lathe(meshes["green"], cap_prof, segs=10, phase=math.pi / 10.0,
            matrix=D.place((0.0, CAP_Y0, HUB_Z), face_y))

    for key in ("blue", "red", "yellow", "green"):
        name, pal = colour[key]
        D.new_obj(name, meshes[key], c, D.C(pal), rbx_material="SmoothPlastic")

    # ---- hub: chamfered red disc on the blades' front + the hidden axle ----------------
    bm = bmesh.new()
    hub_prof = [(0.0, 0.0), (HUB_R, 0.0), (HUB_R, HUB_T - HUB_CHAMFER),
                (HUB_R - HUB_CHAMFER, HUB_T), (0.0, HUB_T)]
    D.lathe(bm, hub_prof, segs=10, phase=math.pi / 10.0,
            matrix=D.place((0.0, HUB_Y0, HUB_Z), face_y))
    D.prism(bm, D.ngon_pts(10, AXLE_R, phase=math.pi / 10.0), AXLE_Y0, HUB_Y0 + 0.05,
            matrix=D.place((0.0, 0.0, HUB_Z), face_y))
    D.new_obj("Hub", bm, c, D.C("toy_red_dk"), rbx_material="SmoothPlastic")

    return c
