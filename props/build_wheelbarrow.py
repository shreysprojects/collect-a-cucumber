"""Garden wheelbarrow: a flared steel tray tipped nose-down on a rolled lip, slung on a
tubular frame that rakes up to two wooden grips at -Y and forks around a rubber-tyred
wheel at +Y.  Loaded with a heap of dirt and a trowel stuck in it.  Handles at -Y, wheel
at +Y - it is parked pointing away from the player, ready to be pushed."""
import bmesh, math

COLLECTION = "Wheelbarrow"
NOTES = ("2.0 wide x 3.85 long x ~2.16 tall (the trowel handle is the tallest thing; the "
         "tub rim tops out at 1.62).  It stands on the wheel (+Y end) and two splayed "
         "stub legs with foot pads at y=-1.22.  Handle grips are wooden cylinders at "
         "x=+/-0.70, y -1.74..-2.36, z 1.56..1.74 - just proud of the back rim, so the "
         "rails make a clean diagonal from the grips down to the axle and a player can "
         "actually be posed pushing it.  The tub is built square and then tipped 11 deg "
         "nose-down about PIVOTS['TubPivot'] (axis = X), so the rim and the bright lip "
         "run downhill toward the wheel: back rim z=1.53, front rim z=1.22.  In the tub's "
         "own (untipped) frame the interior is x +/-0.54..0.86, y -0.98..0.48, "
         "z 1.00..1.38; the Dirt object fills it and can be deleted on its own for an "
         "empty barrow (delete the Grips' trowel handle and the Trim blade too if you "
         "want it bare).  One rigid prop otherwise; the wheel is a separate object "
         "(Tyre + the hub half of Trim) if anyone wants to spin it about "
         "PIVOTS['WheelAxle'] (axis = X).")
PIVOTS = {"WheelAxle": (0.0, 0.95, 0.55), "TubPivot": (0.0, -0.25, 1.14)}


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    tray_c = D.C("plastic_green")     # painted steel tub - the colour that names the prop
    trim_c = D.C("metal_light")       # bright rolled lip, wheel hub, trowel blade
    frame_c = D.C("metal_dark")       # tubular frame, legs, axle
    wood_c = D.C("wood_mid")          # handle grips + trowel handle
    tyre_c = D.C("rubber_black")
    dirt_c = D.C("dirt")

    # ---- the numbers the whole prop hangs off -----------------------------------
    # The tub is designed square and level in its OWN frame, then the whole thing is
    # rotated TILT degrees about the X axis through PIV so it tips nose-down toward the
    # wheel.  Everything tub-side (walls, lip, load, bolts) is written in that frame and
    # pushed through tip() / TUB, so the rim, the bright lip and the floor all carry the
    # same slope and nothing can open a gap.
    Z_FLOOR, Z_IN, Z_RIM = 0.90, 1.00, 1.38     # tray floor underside / inside / rim
    X_BOT, X_IN, X_OUT = 0.58, 0.86, 0.96       # trapezoid: narrow at the foot, flared up
    X_FLOOR = 0.54                              # inside half-width of the floor
    Y_BACK, Y_FRONT = -1.08, 0.58               # outer faces of the tray's end walls
    WALL = 0.10
    TILT = -11.0                                # nose-down; negative drops +Y
    PIV = (0.0, -0.25, 1.14)                    # tub centre = the tipping axis
    AXLE = (0.0, 0.95, 0.55)
    TYRE_R = 0.54                               # wheel rests on z = 0.01

    _ct, _st = math.cos(math.radians(TILT)), math.sin(math.radians(TILT))

    def tip(x, y, z):
        """A point written in the tub's own level frame -> where it really ends up."""
        dy, dz = y - PIV[1], z - PIV[2]
        return (x, PIV[1] + dy * _ct - dz * _st, PIV[2] + dy * _st + dz * _ct)

    # D.prism always extrudes along +Z.  rot_euler(rx=90) maps (lx, ly, lz) -> (lx, -lz, ly),
    # so a profile written in (x, z) and extruded from -y1 to -y0 lands as a solid running
    # along Y, with its profile standing up in the XZ plane.  Rolling that angle to 90+TILT
    # and hanging it off PIV tips the whole tub nose-down in the same move.
    TUB = D.place(PIV, D.rot_euler(rx=90.0 + TILT))

    def ly(y):
        """World Y (tub frame) -> the extrusion coordinate TUB expects."""
        return -(y - PIV[1])

    # ---- tray: a U-shaped trapezoid trough, closed by two solid end walls -------
    zf, zi, zr = Z_FLOOR - PIV[2], Z_IN - PIV[2], Z_RIM - PIV[2]
    trough = [(-X_BOT, zf), (X_BOT, zf), (X_OUT, zr), (X_IN, zr),
              (X_FLOOR, zi), (-X_FLOOR, zi), (-X_IN, zr), (-X_OUT, zr)]
    endwall = [(-X_BOT, zf), (X_BOT, zf), (X_OUT, zr), (-X_OUT, zr)]
    bm = bmesh.new()
    D.prism(bm, trough, ly(Y_FRONT - WALL), ly(Y_BACK + WALL), matrix=TUB)
    D.prism(bm, endwall, ly(Y_BACK + WALL), ly(Y_BACK), matrix=TUB)
    D.prism(bm, endwall, ly(Y_FRONT), ly(Y_FRONT - WALL), matrix=TUB)
    D.new_obj("Tray", bm, c, tray_c, rbx_material="Metal", metallic=0.35, roughness=0.50)

    # ---- bright steel: rolled rim lip, wheel hub, trowel blade, two bolt heads ---
    bm = bmesh.new()
    rx, cr = X_OUT - 0.045, 0.28                # lip centreline; corner cut
    ry0, ry1 = Y_BACK + 0.05, Y_FRONT - 0.05
    lip = [tip(0.00, ry0, Z_RIM),               # start mid-edge so the tube seam is hidden
           tip(rx - cr, ry0, Z_RIM), tip(rx, ry0 + cr, Z_RIM),
           tip(rx, ry1 - cr, Z_RIM), tip(rx - cr, ry1, Z_RIM),
           tip(-(rx - cr), ry1, Z_RIM), tip(-rx, ry1 - cr, Z_RIM),
           tip(-rx, ry0 + cr, Z_RIM), tip(-(rx - cr), ry0, Z_RIM),
           tip(0.00, ry0, Z_RIM)]
    D.tube(bm, lip, [0.085] * len(lip), segs=5)
    hub_m = D.place(AXLE, D.rot_euler(ry=90))   # lathe about Z, tipped so the axis is X
    D.lathe(bm, [(0.00, -0.09), (0.32, -0.09), (0.32, 0.09), (0.00, 0.09)], segs=10,
            matrix=hub_m)
    D.lathe(bm, [(0.00, -0.19), (0.16, -0.19), (0.16, 0.19), (0.00, 0.19)], segs=8,
            matrix=hub_m)                       # centre boss, proud of the tyre
    # trowel blade: a leaf paddle 0.06 thick, speared point-first into the heap at 45 deg.
    # rot_euler(rx=-90, ry=45) drops the leaf's +Y tip to (-X, down) and leaves its FACE
    # square to +Y, so the flat of the blade shows in both the hero and the eye view.
    D.prism(bm, D.teardrop_pts(0.44, 0.56, n=5), -0.03, 0.03,
            matrix=D.place((0.196, -0.29, 1.506), D.rot_euler(rx=-90, ry=45)))
    for bx in (0.35, -0.35):                    # bolts on the nose plate, above the wheel
        D.cyl(bm, tip(bx, Y_FRONT - 0.01, 1.12), tip(bx, Y_FRONT + 0.06, 1.12),
              0.07, segs=5)
    D.new_obj("Trim", bm, c, trim_c, rbx_material="Metal", metallic=0.70, roughness=0.35)

    # ---- frame: two rails grip-to-axle, cross braces, stub legs, stub axle ------
    # The rail is the prop's read: it leaves the grips at rim height and rakes all the way
    # down to the axle, hugging the underside of the tipped tub on the way.
    rail = [(0.70, -2.30, 1.72), (0.70, -1.95, 1.62), (0.68, -1.58, 1.40),
            (0.65, -1.24, 1.10), (0.62, -0.96, 0.90), (0.58, 0.28, 0.66),
            (0.43, 0.70, 0.60), (0.24, 0.95, 0.55)]   # last two converge into the fork
    rail_r = [0.13, 0.13, 0.13, 0.125, 0.125, 0.12, 0.10, 0.085]
    bm = bmesh.new()
    for sx in (1.0, -1.0):
        D.tube(bm, [(sx * p[0], p[1], p[2]) for p in rail], rail_r, segs=6)
        D.cyl(bm, (sx * 0.65, -1.24, 1.06), (sx * 0.72, -1.22, 0.11), 0.10, segs=6)
        D.cyl(bm, (sx * 0.72, -1.23, 0.00), (sx * 0.72, -1.22, 0.12), 0.18, segs=6)
    D.cyl(bm, (-0.615, -0.90, 0.885), (0.615, -0.90, 0.885), 0.085, segs=6)
    D.cyl(bm, (-0.53, 0.42, 0.64), (0.53, 0.42, 0.64), 0.085, segs=6)
    D.cyl(bm, (-0.40, AXLE[1], AXLE[2]), (0.40, AXLE[1], AXLE[2]), 0.075, segs=6)
    D.new_obj("Frame", bm, c, frame_c, rbx_material="Metal", metallic=0.60, roughness=0.42)

    # ---- wooden grips (0.62 long, splayed, at rim height) + the trowel handle ----
    bm = bmesh.new()
    for sx in (1.0, -1.0):
        D.cyl(bm, (sx * 0.70, -1.74, 1.56), (sx * 0.70, -2.36, 1.74), 0.14, segs=8)
    D.cyl(bm, (0.337, -0.27, 1.647), (0.762, -0.17, 2.072), 0.09, segs=6)
    D.new_obj("Grips", bm, c, wood_c, rbx_material="Wood", roughness=0.72)

    # ---- tyre: a lathed ring laid on its side so the wheel axis runs along X ----
    bm = bmesh.new()
    D.lathe(bm, [(0.36, -0.15), (0.52, -0.145), (TYRE_R, 0.00), (0.52, 0.145), (0.36, 0.15)],
            segs=12, matrix=hub_m)
    D.new_obj("Tyre", bm, c, tyre_c, rbx_material="Rubber", roughness=0.85)

    # ---- the load: one low dome plus two off-centre lumps so it heaps unevenly --
    # Written in the tub's level frame and tipped with it, so the heap lies on the sloped
    # floor and spills toward the low front lip instead of sitting flat.
    HEAP = D.rot_euler(rx=TILT)
    bm = bmesh.new()
    D.rock(bm, tip(0.00, -0.26, 1.22), 1.0, seed=7, jitter=0.10, subdiv=1,
           scale=(0.52, 0.62, 0.28), rot=HEAP)
    D.rock(bm, tip(0.30, -0.06, 1.30), 0.26, seed=11, jitter=0.22, subdiv=0,
           scale=(1.0, 1.0, 0.75), rot=HEAP)
    D.rock(bm, tip(-0.20, -0.66, 1.30), 0.26, seed=13, jitter=0.22, subdiv=0,
           scale=(1.0, 1.0, 0.80), rot=HEAP)
    D.new_obj("Dirt", bm, c, dirt_c, rbx_material="Ground", roughness=0.95)

    return c
