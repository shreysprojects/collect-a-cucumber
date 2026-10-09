"""Minigun - squat charcoal six-barrel rotary-gun turret with tan accents: bolted octagon
base, a yawing head (yoke / receiver / ammo box + belt) and a rolling barrel cluster."""
import bmesh
import math
from mathutils import Vector

COLLECTION = "Minigun"

# Roll axis of the barrel cluster: a line parallel to +Y through (x, z) = (0.45, 4.10).
AXIS_X, AXIS_Z = 0.45, 4.10
MUZZLE_Y = 3.80          # front end of the barrels (see NOTES: shortened from the brief's 4.3)
BELT_Y = -1.10           # the ammo belt's y (shifted 0.15 behind the brief's -0.95, see NOTES)

NOTES = (
    "Rig by name prefix: Base* is static, Head* yaws about the world Z axis through (0, 0) "
    "(YawPivot is the collar top at z 1.70), Spin* rolls about BarrelAxis - a line parallel "
    "to +Y through (x 0.45, z 4.10) - in the same direction as the barrels point. Built at "
    "zero yaw with the barrels level and pointing +Y. Muzzle flash at MuzzleTip (0.45, 3.80, "
    "4.10); tracers tan / yellow. No Neon parts. "
    "Static footprint 6.84 x 6.84 (the octagon plate; the tan corner blocks stand 0.18 proud "
    "of its diagonal faces at radius 3.60). Total height 5.60 (top of the carry handle). "
    "Yaw sweep: the farthest Head*/Spin* point is a barrel-tip edge at (1.11, 3.80) = radius "
    "3.96, so a full 360 deg spin stays inside the 8 x 8 tile; the ammo-lid corner sweeps "
    "radius 3.52. Departures from the brief, all for clearance or read: "
    "(1) the barrels end at y 3.80 (brief 4.30) and the muzzle ring sits at y 2.95..3.50 "
    "(brief 3.35..3.90) because the brief's lengths swing to radius 4.1-4.45, outside the "
    "tile; the barrels still stick 0.30 past the ring, and to keep the shortened gun fat "
    "the barrels are r 0.21 on a 0.52 ring with a r 0.80 muzzle ring (brief 0.19 / 0.5 / "
    "0.78). (2) The ammo box bottom is z 1.98 "
    "(brief 1.75) so it clears the four collar bolt heads (top z 1.92) through the whole yaw. "
    "(3) The belt runs at y -1.10 (brief -0.95) so it passes behind the yoke's rear face "
    "(y -0.90) instead of through it; HeadPort covers where it enters the receiver. "
    "One extra part, HeadAmmoBracket (body mid), is the lug that hangs the ammo box off the "
    "yoke. Nothing dips below z = 0: the lowest geometry is the plate's bottom face; the "
    "corner blocks float 0.05 above the ground where they overhang the plate. "
    "Materials: charcoal bodies and tan accents SmoothPlastic; barrels, bolts and bores Metal."
)

PIVOTS = {
    "YawPivot":   (0.00, 0.00, 1.70),   # collar top, on the vertical axis
    "BarrelAxis": (0.45, 0.00, 4.10),   # a point on the roll axis (direction +Y)
    "MuzzleTip":  (0.45, MUZZLE_Y, 4.10),
}


def build(D):
    """D is the imported defenselib module. Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    DARK = "45474d"      # body dark
    MID = "565962"       # body mid
    LIGHT = "6a6e78"     # body light
    BOLT = "2f3136"      # bolt heads / bores
    TAN = "c8b276"       # accent

    PLASTIC = dict(rbx_material="SmoothPlastic", roughness=0.6)
    METAL = dict(rbx_material="Metal", metallic=0.5, roughness=0.4)

    CORNER_R = 3.0
    CORNER_ANGLES = (45.0, 135.0, 225.0, 315.0)

    # ------------------------------------------------------------------ BASE (static)
    # Octagon plate, flats facing the axes (phase pi/8). Circumradius 3.7 -> apothem 3.42.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(8, 3.7, phase=math.pi / 8.0), 0.0, 0.9)
    D.new_obj("BasePlate", bm, c, DARK, **PLASTIC)

    # Four tan corner blocks on the diagonal faces: 1.2 radial x 1.7 tangential x 1.05 tall,
    # centred at radius 3.0 so the outer face stands 0.18 proud of the octagon's flat.
    bm = bmesh.new()
    for ang in CORNER_ANGLES:
        a = math.radians(ang)
        cx, cy = CORNER_R * math.cos(a), CORNER_R * math.sin(a)
        D.beveled_box(bm, (cx - 0.6, cy - 0.85, 0.05), (cx + 0.6, cy + 0.85, 1.1),
                      bevel=0.14, rot=D.rot_euler(rz=ang))
    D.new_obj("BaseCorners", bm, c, TAN, **PLASTIC)

    # Hex bolts: one on each corner block's outer face (along the face normal) and four on
    # the collar's top rim at the 45-deg positions.
    bm = bmesh.new()
    for ang in CORNER_ANGLES:
        a = math.radians(ang)
        ux, uy = math.cos(a), math.sin(a)
        r0, r1 = CORNER_R + 0.58, CORNER_R + 0.82
        D.cyl(bm, (ux * r0, uy * r0, 0.575), (ux * r1, uy * r1, 0.575), 0.24, segs=6)
    for bx, by in D.ring_positions(4, 1.9, phase=math.pi / 4.0):
        D.cyl(bm, (bx, by, 1.68), (bx, by, 1.92), 0.24, segs=6)
    D.new_obj("BaseBolts", bm, c, BOLT, **METAL)

    # 12-gon collar the head bears on.
    bm = bmesh.new()
    D.cyl(bm, (0.0, 0.0, 0.9), (0.0, 0.0, 1.7), 2.3, segs=12)
    D.new_obj("BaseCollar", bm, c, MID, **PLASTIC)

    # ------------------------------------------------------------------ HEAD (yaws)
    bm = bmesh.new()
    D.cyl(bm, (0.0, 0.0, 1.7), (0.0, 0.0, 2.5), 1.55, segs=12)
    D.new_obj("HeadPedestal", bm, c, DARK, **PLASTIC)

    # Yoke: the thick upright plate on the gun's LEFT that carries the receiver.
    bm = bmesh.new()
    D.beveled_box(bm, (-1.25, -0.9, 2.5), (-0.55, 0.9, 4.9), bevel=0.15)
    D.new_obj("HeadYoke", bm, c, MID, **PLASTIC)

    # Tan pivot disc on the yoke's outer face, on the barrel-axis height.
    bm = bmesh.new()
    D.cyl(bm, (-1.45, 0.0, AXIS_Z), (-1.2, 0.0, AXIS_Z), 0.6, segs=12)
    D.new_obj("HeadPivotDisc", bm, c, TAN, **PLASTIC)

    # Receiver: the boxy gun body, cantilevered off the yoke's right side.
    bm = bmesh.new()
    D.beveled_box(bm, (-0.55, -2.0, 3.2), (1.35, 0.9, 5.0), bevel=0.18)
    D.new_obj("HeadReceiver", bm, c, DARK, **PLASTIC)

    # Carry handle on the receiver top: two posts and a bar.
    bm = bmesh.new()
    for py in (-1.6, -0.4):
        D.beveled_box(bm, (0.275, py - 0.125, 4.95), (0.525, py + 0.125, 5.38), bevel=0.05)
    D.beveled_box(bm, (0.26, -1.85, 5.35), (0.54, -0.35, 5.6), bevel=0.07)
    D.new_obj("HeadHandle", bm, c, MID, **PLASTIC)

    # Ammo box hanging on the left, its lug bracket, and the tan lid.
    bm = bmesh.new()
    D.beveled_box(bm, (-3.0, -1.7, 1.98), (-1.5, -0.2, 3.3), bevel=0.15)
    D.new_obj("HeadAmmoBox", bm, c, DARK, **PLASTIC)

    bm = bmesh.new()
    D.beveled_box(bm, (-1.65, -1.15, 2.55), (-1.15, -0.45, 3.1), bevel=0.06)
    D.new_obj("HeadAmmoBracket", bm, c, MID, **PLASTIC)

    bm = bmesh.new()
    D.beveled_box(bm, (-3.05, -1.75, 3.3), (-1.45, -0.15, 3.65), bevel=0.1)
    D.new_obj("HeadAmmoLid", bm, c, TAN, **PLASTIC)

    # Ammo belt: 7 tan links on a quadratic arc (in the x-z plane at y = BELT_Y) from the
    # lid top up and right into the receiver's port, each link turned to follow the arc.
    bm = bmesh.new()
    p0, ctl, p2 = Vector((-2.25, 3.75)), Vector((-1.9, 4.55)), Vector((-0.75, 4.45))
    for i in range(7):
        t = i / 6.0
        p = (1.0 - t) ** 2 * p0 + 2.0 * (1.0 - t) * t * ctl + t * t * p2
        d = 2.0 * (1.0 - t) * (ctl - p0) + 2.0 * t * (p2 - ctl)
        phi = math.degrees(math.atan2(d.y, d.x))        # climb angle in the x-z plane
        D.beveled_box(bm, (p.x - 0.16, BELT_Y - 0.25, p.y - 0.13),
                      (p.x + 0.16, BELT_Y + 0.25, p.y + 0.13),
                      bevel=0.06, rot=D.rot_euler(ry=-phi))
    D.new_obj("HeadBelt", bm, c, TAN, **PLASTIC)

    # Feed port on the receiver's left face, in the corner behind the yoke.
    bm = bmesh.new()
    D.beveled_box(bm, (-1.05, -1.45, 4.1), (-0.5, -0.75, 4.8), bevel=0.08)
    D.new_obj("HeadPort", bm, c, MID, **PLASTIC)

    # ------------------------------------------------------------------ SPIN (rolls)
    # Six barrels on a 0.5 ring around the axis, phase 30 deg (one at the top, one at the
    # bottom, two each side).
    ring = [(AXIS_X + 0.52 * math.cos(math.radians(30 + 60 * i)),
             AXIS_Z + 0.52 * math.sin(math.radians(30 + 60 * i))) for i in range(6)]
    bm = bmesh.new()
    for bx, bz in ring:
        D.cyl(bm, (bx, 0.9, bz), (bx, MUZZLE_Y, bz), 0.21, segs=8)
    D.new_obj("SpinBarrels", bm, c, LIGHT, **METAL)

    # Rear housing the barrels grow out of; its back 0.3 is buried in the receiver.
    bm = bmesh.new()
    D.cyl(bm, (AXIS_X, 0.6, AXIS_Z), (AXIS_X, 1.5, AXIS_Z), 0.9, segs=12)
    D.new_obj("SpinHousing", bm, c, MID, **PLASTIC)

    # Tan muzzle ring; the barrels stick 0.3 past it.
    bm = bmesh.new()
    D.cyl(bm, (AXIS_X, MUZZLE_Y - 0.85, AXIS_Z), (AXIS_X, MUZZLE_Y - 0.3, AXIS_Z), 0.80,
          segs=12)
    D.new_obj("SpinMuzzleRing", bm, c, TAN, **PLASTIC)

    # Dark bore discs in the muzzle tips so the barrels read hollow.
    bm = bmesh.new()
    for bx, bz in ring:
        D.cyl(bm, (bx, MUZZLE_Y - 0.06, bz), (bx, MUZZLE_Y + 0.02, bz), 0.12, segs=6)
    D.new_obj("SpinBores", bm, c, BOLT, **METAL)

    return c


# ---------------------------------------------------------------------------------------
# PART LIST - name / colour role / hex / approx tris        (tri = 44 per beveled_box,
#                                                            4n-4 per n-seg cyl / n-gon prism)
#
#   BasePlate        body dark  45474d   8-gon prism ..........................  28
#   BaseCorners      tan        c8b276   4 x beveled_box ...................... 176
#   BaseBolts        bolt       2f3136   8 x 6-seg cyl ........................ 160
#   BaseCollar       body mid   565962   12-seg cyl ...........................  44
#                                                            BASE subtotal    408
#   HeadPedestal     body dark  45474d   12-seg cyl ...........................  44
#   HeadYoke         body mid   565962   beveled_box ..........................  44
#   HeadPivotDisc    tan        c8b276   12-seg cyl ...........................  44
#   HeadReceiver     body dark  45474d   beveled_box ..........................  44
#   HeadHandle       body mid   565962   3 x beveled_box ...................... 132
#   HeadAmmoBox      body dark  45474d   beveled_box ..........................  44
#   HeadAmmoBracket  body mid   565962   beveled_box ..........................  44
#   HeadAmmoLid      tan        c8b276   beveled_box ..........................  44
#   HeadBelt         tan        c8b276   7 x beveled_box ...................... 308
#   HeadPort         body mid   565962   beveled_box ..........................  44
#                                                            HEAD subtotal    792
#   SpinBarrels      body light 6a6e78   6 x 8-seg cyl ........................ 168
#   SpinHousing      body mid   565962   12-seg cyl ...........................  44
#   SpinMuzzleRing   tan        c8b276   12-seg cyl ...........................  44
#   SpinBores        bolt       2f3136   6 x 6-seg cyl ........................ 120
#                                                            SPIN subtotal    376
#
#   19 objects, ~1576 tris of a 2000 budget.
#   Value ladder, base to muzzle: DARK plate -> TAN corners / MID collar -> BOLT heads ->
#   DARK pedestal -> MID yoke -> TAN disc; DARK receiver -> MID housing -> LIGHT barrels ->
#   TAN ring -> LIGHT tips -> BOLT bores; DARK ammo box -> MID bracket / TAN lid -> TAN belt
#   -> MID port -> DARK receiver.  No two touching parts share a value.
# ---------------------------------------------------------------------------------------
