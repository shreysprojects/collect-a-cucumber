"""couchlib.py -- the shared look of the HomeLiving couches (Sofa, Armchair), fun-builds 2026-09-24.

One chunky rolled-arm couch in the toy palette: brass-tipped wooden bun feet, a wooden plinth rail,
a fabric base with cream piping, scroll arms (roll + piped front disc), a rolled back frame, puffy
seat cushions (a block base + an Ellipsoid puff) and tufted back cushions that lean back.

Part names the behaviour relies on (FB/src/behaviours/client/Sofa.lua):
    Cushion<i>       the seat puff (Ellipsoid) the client squashes while seat i is taken
    BackCushion<i>   the back cushion (Ellipsoid) that gives a little when leaned on
    Pivot_Seat<i>    the SQUASHED top of seat cushion i (the client's rest squash, REST_SQUASH), where the server
                     puts the invisible Seat's top face (facing -Z). A sitter is welded to that Seat, so the pivot
                     is where the cushion ends up, not where it starts - otherwise they float over the dent.
Seats are numbered from the viewer's LEFT (+X) when standing in front of the couch.
Every OTHER part is named so it does not start with a string literal of Sofa.lua ("Cushion", "BackCushion", "Seat",
"Sit", "Sofa" ...): models/export_mesh.py keeps literal-prefixed parts as separate MeshParts, so CushBase / CushPipe /
BackCore / BackTop / BackSeam merge with the rest of the static couch instead.
"""

from mathutils import Vector

BODY = "3264b8"      # fabric shell (toy blue)
CUSH = "6a9ef0"      # cushions, a shade lighter
PIPE = "f2f0ea"      # cream piping
BUTTON = "23457f"    # tufting buttons
WOOD = "8a5a2b"      # plinth rail
WOOD_D = "6b4423"    # feet
BRASS = "f2c13d"     # foot tips

CUSH_Y = 1.78        # seat puff centre y ...
CUSH_H = 0.66        # ... and height: bottom 1.45, top 2.11 at rest
REST_SQUASH = 0.3    # share of the puff's height a sitter squashes away = SQUASH_Y in src/behaviours/client/Sofa.lua
SEAT_Y = CUSH_Y - CUSH_H / 2 + CUSH_H * (1 - REST_SQUASH)  # 1.912: the squashed top = where the sitter's thighs rest
SEAT_Z = -0.1        # seat centre z: a sitter's back (root z + ~0.6) meets the flattened back cushion
BASE_TOP = 1.36      # top of the fabric base (cushions sit on it)
DEPTH_F = -1.62      # front face z of the body
DEPTH_B = 1.68       # back face z
ARM_W = 0.84


def build_couch(m, P, seats, seat_w, pillows=(), colors=None):
    c = dict(BODY=BODY, CUSH=CUSH, PIPE=PIPE, BUTTON=BUTTON)
    c.update(colors or {})
    iw = seats * seat_w           # inner width between the arms
    hx = iw / 2                   # inner half width
    ax = hx + ARM_W / 2           # arm centre x

    # ------------------------------------------------ feet: brass tip + turned wooden bun
    for i, (sx, sz) in enumerate(((1, -1), (-1, -1), (1, 1), (-1, 1))):
        x, z = sx * (ax + 0.05), sz * 1.3
        m.cyl("FootTip%d" % (i + 1), (x, 0, z), (x, 0.13, z), 0.3, BRASS, "Metal", collide=False)
        m.cyl("Foot%d" % (i + 1), (x, 0.11, z), (x, 0.45, z), 0.42, WOOD_D, "Wood")
    # ------------------------------------------------ plinth rail + fabric base
    m.block("Plinth", (0, 0.52, 0.03), (iw + 2 * ARM_W + 0.06, 0.18, 3.30), WOOD, "Wood")  # 0.02+ proud of the arms + base
    m.block("Base", (0, (0.58 + BASE_TOP) / 2, 0.03), (iw + 0.04, BASE_TOP - 0.58, 3.24), c["BODY"], "Fabric")
    m.cyl("BasePiping", (hx, BASE_TOP - 0.02, DEPTH_F + 0.02), (-hx, BASE_TOP - 0.02, DEPTH_F + 0.02), 0.12,
          c["PIPE"], "Fabric", collide=False)

    # ------------------------------------------------ scroll arms
    roll_y, roll_d = 2.42, 1.1
    for side, tag in ((1, "L"), (-1, "R")):
        x = side * ax
        xr = side * (ax - 0.02)       # roll + piping stay inside the 8-stud footprint
        m.block("Arm" + tag, (x, (0.58 + roll_y + 0.03) / 2, 0.03), (ARM_W, roll_y + 0.03 - 0.58, 3.26), c["BODY"], "Fabric")
        m.cyl("ArmRoll" + tag, (xr, roll_y, DEPTH_F - 0.02), (xr, roll_y, DEPTH_B), roll_d, c["BODY"], "Fabric")
        # scroll front: a fabric panel, a piped disc on the roll end and piping down both edges
        m.block("ArmFront" + tag, (x, (0.6 + roll_y) / 2, DEPTH_F - 0.04), (ARM_W + 0.02, roll_y - 0.6, 0.08), c["BODY"], "Fabric")
        m.disc("ArmPipe" + tag, (xr, roll_y, DEPTH_F - 0.07), (0, 0, -1), roll_d + 0.1, 0.06, c["PIPE"], "Fabric", collide=False)
        m.disc("ArmCap" + tag, (xr, roll_y, DEPTH_F - 0.11), (0, 0, -1), roll_d - 0.16, 0.06, c["BODY"], "Fabric", collide=False)
        for k, ex in enumerate((x - ARM_W / 2 + 0.02, x + ARM_W / 2 - 0.02)):
            m.cyl("ArmEdge%s%d" % (tag, k + 1), (ex, 0.62, DEPTH_F - 0.08), (ex, roll_y - 0.36, DEPTH_F - 0.08), 0.1,
                  c["PIPE"], "Fabric", collide=False)
        # the roll's back end gets the same piped cap as the front
        m.disc("ArmPipeBack" + tag, (xr, roll_y, DEPTH_B + 0.02), (0, 0, 1), roll_d + 0.1, 0.06, c["PIPE"], "Fabric", collide=False)
        m.disc("ArmCapBack" + tag, (xr, roll_y, DEPTH_B + 0.06), (0, 0, 1), roll_d - 0.16, 0.06, c["BODY"], "Fabric", collide=False)
        # a stitched seam along the top of the roll
        m.cyl("ArmSeam" + tag, (xr, roll_y + roll_d / 2 - 0.035, DEPTH_F + 0.05), (xr, roll_y + roll_d / 2 - 0.035, DEPTH_B - 0.05),
              0.08, c["PIPE"], "Fabric", collide=False)

    # ------------------------------------------------ back frame with a rolled top
    back_top = 3.3
    m.block("Back", (0, (1.3 + back_top) / 2, 1.39), (iw + 0.04, back_top - 1.3, 0.58), c["BODY"], "Fabric")
    m.cyl("BackRoll", (hx + 0.04, back_top, 1.39), (-hx - 0.04, back_top, 1.39), 0.64, c["BODY"], "Fabric")
    m.cyl("BackPiping", (hx, back_top + 0.02, 1.07), (-hx, back_top + 0.02, 1.07), 0.1, c["PIPE"], "Fabric",
          collide=False)

    # piping framing the back panel (the side people see from behind)
    for k, ex in enumerate((hx, -hx)):
        m.cyl("BackEdge%d" % (k + 1), (ex, 0.62, DEPTH_B + 0.01), (ex, back_top - 0.1, DEPTH_B + 0.01), 0.1, c["PIPE"], "Fabric",
              collide=False)
    m.cyl("BackHem", (hx, 0.66, DEPTH_B + 0.01), (-hx, 0.66, DEPTH_B + 0.01), 0.1, c["PIPE"], "Fabric", collide=False)

    # ------------------------------------------------ seat + back cushions
    tilt = P.angles(12, 0, 0)
    for i in range(seats):
        n = i + 1
        cx = hx - seat_w * (i + 0.5)
        w = seat_w - 0.04
        m.block("CushBase%d" % n, (cx, (BASE_TOP - 0.02 + 1.74) / 2, -0.25), (w, 1.74 - BASE_TOP + 0.02, 2.78), c["CUSH"], "Fabric")
        m.ellipsoid("Cushion%d" % n, (cx, CUSH_Y, -0.25), (w + 0.02, CUSH_H, 2.8), c["CUSH"], "Fabric")
        m.cyl("CushPipe%d" % n, (cx + w / 2 - 0.03, 1.74, DEPTH_F - 0.02), (cx - w / 2 + 0.03, 1.74, DEPTH_F - 0.02), 0.1,
              c["PIPE"], "Fabric", collide=False)
        # back cushion: a boxy core with a rounded top edge + a soft puff on its face (the part that gives)
        centre = Vector((cx, 2.7, 0.9))
        m.block("BackCore%d" % n, tuple(centre), (w, 1.34, 0.5), c["CUSH"], "Fabric", rot=(12, 0, 0))
        top = centre + tilt @ Vector((0, 0.67, 0))
        m.cyl("BackTop%d" % n, tuple(top + Vector((w / 2 - 0.02, 0, 0))), tuple(top - Vector((w / 2 - 0.02, 0, 0))), 0.5, c["CUSH"], "Fabric")
        m.ellipsoid("BackCushion%d" % n, tuple(centre + tilt @ Vector((0, 0.03, -0.25))), (w - 0.1, 1.3, 0.36), c["CUSH"], "Fabric",
                    rot=(12, 0, 0))
        m.cyl("BackSeam%d" % n, tuple(top + tilt @ Vector((w / 2 - 0.04, 0, -0.25))), tuple(top + tilt @ Vector((-w / 2 + 0.04, 0, -0.25))),
              0.07, c["PIPE"], "Fabric", collide=False)
        m.pivot("Seat%d" % n, (cx, SEAT_Y, SEAT_Z))

    # ------------------------------------------------ throw pillows leaning into the corners
    for tag, side, col in pillows:
        rot = (10, side * 26, side * 10)
        pos = Vector((side * (hx - 0.56), 2.56, 0.26))
        m.block("Pillow" + tag + "Core", tuple(pos + P.angles(*rot) @ Vector((0, 0, 0.03))), (1.0, 1.0, 0.3), col, "Fabric", rot=rot,
                collide=False)
        m.ellipsoid("Pillow" + tag, tuple(pos), (1.22, 1.22, 0.44), col, "Fabric", rot=rot, collide=False)
        m.ball("PillowButton" + tag, tuple(pos + P.angles(*rot) @ Vector((0, 0, -0.21))), 0.14, "fbf6e8", "Fabric", collide=False)
    return m