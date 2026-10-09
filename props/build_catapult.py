"""Wooden siege catapult: two heavy side beams on four spoked wheels, a throwing arm
hinged low at the back and COCKED - raked back and up over the tail at 42 degrees above
horizontal with a boulder riding high in its bucket - a winch drum and crank that hold it
there, and a low dark A-frame carrying the padded stop the arm slams into.  Throws +Y."""
import bmesh, math

COLLECTION = "Catapult"
NOTES = (
    "About 4.8 wide x 6.7 long (y -4.1 .. 2.6) x 5.2 tall, standing on four wheels that "
    "touch z = 0.01.  Built in the LOADED pose: the arm rakes BACK and UP over the tail, "
    "so the bright beam and the loaded bucket are the silhouette and clear the dark "
    "A-frame by about a stud.  "
    "Every object whose name starts with 'Arm' (ArmBeam, ArmIron, ArmBucket, ArmRope, "
    "ArmLoad) is the swinging group: weld them together and rotate the lot about "
    "PIVOTS['ArmPivot'] on a horizontal axis parallel to world +X.  "
    "SIGN CONVENTION: STATES are degrees about that +X axis, right-handed, applied to the "
    "pose as built.  POSITIVE winds the arm further BACK and DOWN (cocking it harder); "
    "NEGATIVE swings the bucket forward and over the top toward +Y (firing).  "
    "'Loaded' = 0 (as built), 'Fired' = -92, which lays the front face of the arm beam "
    "onto the padded stop bar at (0, 0.34, 3.42) - that pad IS the mechanical stop, so do "
    "not rotate past it.  "
    "ArmLoad is the boulder - delete it on its own for an empty bucket, or swap it for a "
    "giant cucumber; it sits at world (0, -3.48, 4.79) with a 0.40 radius.  StopPad is the "
    "dark wrap on the stop bar.  RopeBundle holds the torsion skein at the hinge and the "
    "winch line; that line runs from the drum up to the arm at 2.3 studs out from the "
    "hinge and is what holds the arm cocked - hide or re-loft it once the arm moves.  "
    "The crank is on the -X side, i.e. the RIGHT of a player standing in front at +Y, and "
    "its dark handle deliberately stands proud of the tail.  Wheels are part of the rigid "
    "frame (Wheels / Timbers / Ironwork); spin them about the axles at y = -1.05 and "
    "y = 1.60, z = 0.96 if wanted.")
PIVOTS = {"ArmPivot": (0.0, -1.30, 2.30)}
STATES = {"Loaded": 0.0, "Fired": -92.0}

# ---- the numbers the whole prop hangs off ---------------------------------------
Y_BACK, Y_FRONT = -2.05, 2.60          # side beam ends
XB_IN, XB_OUT = 1.38, 1.86             # side beam inner / outer faces
ZB0, ZB1 = 1.00, 1.80                  # side beam underside / top
WHEEL_R, TYRE_HW, X_WHEEL, Z_AX = 0.95, 0.22, 2.12, 0.96
AXLE_Y = (-1.05, 1.60)
PIVOT = (0.0, -1.30, 2.30)             # hinge, low and at the back
ARM_TILT = 48.0                        # local +Z -> (0, -sin, cos): back and 42 deg UP
ARM_REACH = 3.17                       # hinge -> beam tip, along the arm
DRUM = (0.0, -1.85, 2.05)              # winch drum centre
BAR = (0.0, 0.34, 3.42)                # padded stop bar centre (the fired-arm stop)
PAD_R = 0.25                           # outer radius of the dark pad on that bar
POST_TOP = (0.34, 3.50)                # (y, z) the A-frame uprights reach
POST_FOOT = (0.80, 1.30)               # (y, z) where they socket into the beams

_ST, _CT = math.sin(math.radians(ARM_TILT)), math.cos(math.radians(ARM_TILT))
ARM_DIR = (0.0, -_ST, _CT)             # unit vector hinge -> bucket, in world


def _on_arm(d):
    """World point `d` studs out from the hinge along the cocked arm."""
    return (0.0, PIVOT[1] + ARM_DIR[1] * d, PIVOT[2] + ARM_DIR[2] * d)


def _sym(fn, x0, x1, *args, **kw):
    """Run `fn` twice with the x span mirrored across x = 0."""
    for s in (1.0, -1.0):
        a, b = sorted((s * x0, s * x1))
        fn(a, b, *args, **kw)


def _leg(D, bm, x0, x1, a, b, hw=0.18, bevel=None):
    """A square-section leg spanning x0..x1, running from (y, z) `a` to (y, z) `b`.
    Built axis-aligned about its own midpoint and tipped with rot=, which rotates a
    primitive about its own centre."""
    dy, dz = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dy, dz)
    ang = math.degrees(math.atan2(-dy, dz))     # rot_euler(rx=ang): +Z -> (0,-sin,cos)
    cy, cz = (a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0
    lo = (x0, cy - hw, cz - L / 2.0)
    hi = (x1, cy + hw, cz + L / 2.0)
    m = D.rot_euler(rx=ang)
    if bevel:
        return D.beveled_box(bm, lo, hi, bevel=bevel, rot=m)
    return D.box(bm, lo, hi, rot=m)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # value ladder: frame darkest, beams mid, ONLY the deck and the arm are light
    frame = D.C("log_bark")        # braces, hinge posts, A-frame, struts, bar core
    beam = D.C("wood_mid")         # side beams, spokes, hubs, winch drum
    light = D.C("wood_light")      # deck slats + the arm beam - the two bright things
    rim = D.C("wood_dark")         # wheel rims, bucket
    iron = D.C("iron_dark")        # every piece of ironwork
    cord = D.C("rope")             # torsion skein, winch line, lashings
    padc = D.C("rubber_black")     # the padded stop
    stone = D.C("stone_mid")

    # local arm space: +Z runs from the hinge out to the bucket, +X stays world +X
    M_ARM = D.place(PIVOT, D.rot_euler(rx=ARM_TILT))
    up_l = (0.0, _ST, _CT)             # world +Z expressed in arm-local coordinates

    # ---- side beams + wheel spokes/hubs + winch drum (the mid-value timber) --------
    bm = bmesh.new()
    _sym(lambda a, b: D.beveled_box(bm, (a, Y_BACK, ZB0), (b, Y_FRONT, ZB1), bevel=0.10),
         XB_IN, XB_OUT)
    for ay in AXLE_Y:                                   # spokes + wooden hub disc
        for s in (1.0, -1.0):
            wm = D.place((s * X_WHEEL, ay, Z_AX), D.rot_euler(ry=90))
            for k in range(4):
                ang = math.radians(45 + 90 * k)
                cx, cz = math.cos(ang), math.sin(ang)
                D.cyl(bm, (s * X_WHEEL, ay + cx * 0.18, Z_AX + cz * 0.18),
                      (s * X_WHEEL, ay + cx * 0.64, Z_AX + cz * 0.64), 0.095, segs=3)
            D.lathe(bm, [(0.0, -0.13), (0.31, -0.13), (0.31, 0.13), (0.0, 0.13)],
                    segs=5, matrix=wm)
    D.cyl(bm, (-1.24, DRUM[1], DRUM[2]), (1.24, DRUM[1], DRUM[2]), 0.30, segs=8)
    D.new_obj("Timbers", bm, c, beam, rbx_material="Wood", roughness=0.62)

    # ---- dark frame: cross braces, hinge posts, winch bearings, A-frame, bar core ---
    bm = bmesh.new()
    for (y0, y1) in ((-2.02, -1.70), (0.36, 0.78), (2.24, 2.56)):
        D.box(bm, (-1.90, y0, 1.10), (1.90, y1, 1.62))
    _sym(lambda a, b: D.beveled_box(bm, (a, -1.58, 1.52), (b, -1.02, 2.62), bevel=0.07),
         1.14, 1.44)                                     # hinge posts
    _sym(lambda a, b: D.box(bm, (a, -2.04, 1.70), (b, -1.66, 2.38)), 1.22, 1.52)
    _sym(lambda a, b: _leg(D, bm, a, b, POST_FOOT, POST_TOP, hw=0.18, bevel=0.07),
         1.16, 1.48)                                     # A-frame uprights
    _sym(lambda a, b: _leg(D, bm, a, b, (1.90, 1.80), (0.50, 2.85), hw=0.14),
         1.20, 1.44)                                     # forward struts
    D.cyl(bm, (-1.50, BAR[1], BAR[2]), (1.50, BAR[1], BAR[2]), 0.13, segs=6)
    D.new_obj("Frame", bm, c, frame, rbx_material="Wood", roughness=0.66)

    # ---- plank deck between the beams --------------------------------------------
    bm = bmesh.new()
    D.slat_run(bm, (-1.42, -0.55, 1.70), (1.42, 2.35, 1.88), 3, gap_frac=0.26,
               axis='y', bevel=0.05)
    D.new_obj("Deck", bm, c, light, rbx_material="WoodPlanks", roughness=0.68)

    # ---- four wheel rims ----------------------------------------------------------
    bm = bmesh.new()
    for ay in AXLE_Y:
        for s in (1.0, -1.0):
            wm = D.place((s * X_WHEEL, ay, Z_AX), D.rot_euler(ry=90))
            D.lathe(bm, [(0.60, -TYRE_HW), (WHEEL_R - 0.05, -TYRE_HW),
                         (WHEEL_R - 0.05, TYRE_HW), (0.60, TYRE_HW), (0.60, -TYRE_HW)],
                    segs=8, cap=False, matrix=wm)
    D.new_obj("Wheels", bm, c, rim, rbx_material="Wood", roughness=0.60)

    # ---- ironwork: axles, tyre bands, hub caps, hinge pin, straps, crank ----------
    bm = bmesh.new()
    for ay in AXLE_Y:
        D.cyl(bm, (-X_WHEEL - 0.10, ay, Z_AX), (X_WHEEL + 0.10, ay, Z_AX), 0.13, segs=5)
        for s in (1.0, -1.0):
            wm = D.place((s * X_WHEEL, ay, Z_AX), D.rot_euler(ry=90))
            D.lathe(bm, [(WHEEL_R, -TYRE_HW + 0.04), (WHEEL_R, TYRE_HW - 0.04)],
                    segs=8, cap=False, matrix=wm)                      # iron tyre band
            D.lathe(bm, [(0.0, -0.20), (0.17, -0.20), (0.17, 0.20), (0.0, 0.20)], segs=5,
                    matrix=D.place((s * (X_WHEEL + 0.04), ay, Z_AX), D.rot_euler(ry=90)))
    D.cyl(bm, (-1.46, PIVOT[1], PIVOT[2]), (1.46, PIVOT[1], PIVOT[2]), 0.11, segs=6)
    _sym(lambda a, b: D.box(bm, (a, -2.09, ZB0 - 0.04), (b, -1.86, ZB1 + 0.04)),
         XB_IN - 0.04, XB_OUT + 0.04)                                  # rear end straps
    for by in (-0.20, 2.20):                                     # bolt heads
        for s in (1.0, -1.0):
            D.cyl(bm, (s * (XB_OUT - 0.02), by, 1.40), (s * (XB_OUT + 0.09), by, 1.40),
                  0.10, segs=4)
    # winch crank: shaft out past the bearing, a web up the back, then a fat grip
    D.cyl(bm, (-1.26, DRUM[1], DRUM[2]), (-2.06, DRUM[1], DRUM[2]), 0.08, segs=4)
    D.box(bm, (-2.14, DRUM[1] - 0.09, DRUM[2] - 0.06), (-1.98, DRUM[1] + 0.09, DRUM[2] + 0.83))
    D.cyl(bm, (-2.02, DRUM[1], DRUM[2] + 0.74), (-2.46, DRUM[1], DRUM[2] + 0.74),
          0.10, segs=5)                                                # crank handle
    D.new_obj("Ironwork", bm, c, iron, rbx_material="Metal", metallic=0.55, roughness=0.42)

    # ---- the dark padded stop that the fired arm slams into ------------------------
    bm = bmesh.new()
    D.lathe(bm, [(0.19, -0.78), (PAD_R, -0.64), (PAD_R, 0.64), (0.19, 0.78)], segs=6,
            cap=False, matrix=D.place(BAR, D.rot_euler(ry=90)))
    D.new_obj("StopPad", bm, c, padc, rbx_material="Leather", roughness=0.80)

    # ---- rope: torsion skein at the hinge, winch line up to the cocked arm ---------
    bm = bmesh.new()
    hel = D.helix_pts((0, 0, 0.0), (0, 0, 1.14), 0.33, turns=3.0, n=8)
    vs = D.tube(bm, hel, [0.105] * len(hel), segs=4)
    D.translate(bm, vs, (0.0, 0.0, -0.57))
    D.xform(bm, vs, D.place(PIVOT, D.rot_euler(ry=90)))
    D.rope(bm, (0.0, DRUM[1], DRUM[2] + 0.31), _on_arm(2.30), sag=0.05,
           radius=0.075, n=6, segs=4)
    D.new_obj("RopeBundle", bm, c, cord, rbx_material="Fabric", roughness=0.78)

    # ================= the swinging group (built in arm-local space) ===============
    # local z is measured from the arm's heel; AH lifts it so the literals stay >= 0 and
    # the -AH translate drops the heel back onto the hinge before M_ARM places the group.
    AH = 0.55
    CUP = AH + 3.00                       # cup sits 3.00 studs out from the hinge

    def arm_place(bm_):
        D.translate(bm_, list(bm_.verts), (0.0, 0.0, -AH))
        D.xform(bm_, list(bm_.verts), M_ARM)

    # ---- arm beam: a stubby heel below the hinge, a light shaft out to the bucket ---
    bm = bmesh.new()
    D.beveled_box(bm, (-0.21, -0.21, 0.00), (0.21, 0.21, 2.10), bevel=0.07)
    D.beveled_box(bm, (-0.16, -0.16, 2.00), (0.16, 0.16, AH + ARM_REACH), bevel=0.06)
    arm_place(bm)
    D.new_obj("ArmBeam", bm, c, light, rbx_material="Wood", roughness=0.60)

    # ---- arm ironwork: hinge collars either side of the beam, a band up the shaft --
    bm = bmesh.new()
    for s in (1.0, -1.0):
        D.cyl(bm, (s * 0.22, 0.0, AH), (s * 0.44, 0.0, AH), 0.30, segs=6)
    D.lathe(bm, [(0.20, -0.09), (0.20, 0.09)], segs=6, cap=False,
            matrix=D.place((0.0, 0.0, 2.70)))
    arm_place(bm)
    D.new_obj("ArmIron", bm, c, iron, rbx_material="Metal", metallic=0.55, roughness=0.42)

    # ---- bucket: a hollow cup lathed about world-up so the load sits in it ---------
    bm = bmesh.new()
    D.lathe(bm, [(0.0, 0.0), (0.50, 0.0), (0.56, 0.44), (0.47, 0.44), (0.40, 0.11),
                 (0.0, 0.11)], segs=8,
            matrix=D.place((0.0, 0.08, CUP), D.rot_euler(rx=-ARM_TILT)))
    arm_place(bm)
    D.new_obj("ArmBucket", bm, c, rim, rbx_material="Wood", roughness=0.66)

    # ---- rope lashings binding the shaft, and the sling loop under the cup ---------
    bm = bmesh.new()
    for lz in (1.40, 2.15):
        D.lathe(bm, [(0.24, -0.10), (0.24, 0.10)], segs=6, cap=False,
                matrix=D.place((0.0, 0.0, lz)))
    D.tube(bm, [(0.0, 0.20, CUP - 0.80), (0.0, 0.34, CUP - 0.35), (0.0, 0.30, CUP - 0.03)],
           [0.07, 0.07, 0.07], segs=4)
    arm_place(bm)
    D.new_obj("ArmRope", bm, c, cord, rbx_material="Fabric", roughness=0.78)

    # ---- the loaded boulder, riding proud of the cup rim -------------------------
    bm = bmesh.new()
    D.rock(bm, (0.0, 0.08 + up_l[1] * 0.42, CUP + up_l[2] * 0.42), 0.40, seed=7,
           jitter=0.26, subdiv=1)
    arm_place(bm)
    D.new_obj("ArmLoad", bm, c, stone, rbx_material="Slate", roughness=0.80)

    return c
