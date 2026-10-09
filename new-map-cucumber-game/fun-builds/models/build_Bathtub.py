"""Bathtub (Home) -- a white clawfoot bathtub full of bubbles, fun-builds HomeBath 2026-09-24.

~7 long (X) x 2.8 to the rim x 3.4 wide (Z), standing on four gold lion-claw feet, with a roll-top rim (a tube
of cylinders + ball joints following the stadium outline), light-blue bath water just under the rim, heaps of
foam and loose bubbles, a yellow rubber duck bobbing near the front, a little bath pillow at the HEAD end (-X)
and a freestanding gold tub filler at the TAP end (+X): two floor pipes, a mixer with red / blue cross handles
and a gooseneck spout arching over the rim. The body is a straight-sided stadium wall (WallMid + WallEnd*)
turned under by a long Belly plus a shallow BellyEnd under each round end (fix pass 2026-09-24: no ledge).
Review renders shade cylinders like Roblox does (_roblox_shading below).

Part names / pivots the behaviour relies on (FB/src/behaviours/*/Bathtub.lua):
    Duck*                  the rubber duck (client bobs it as one rigid group about Pivot_Duck)
    Foam*                  foam mounds (client swells / wobbles them while the bubbles run)
    Bubble*                loose bubbles (client drifts them a little while the bubbles run)
    TapMixer               the Bubbles prompt hangs off it (at Pivot_Taps)
    Pivot_BathSeat         where a bather's pelvis rests (the lying seat's top face)
    Pivot_BathHead         a point the head points toward (head end, reclined ~10 deg): seat LookVector
    Pivot_WaterMin/Max     the water surface's plan box corners (y = the water top)
    Pivot_SpoutTip         under the spout nozzle (the tap stream starts here)
    Pivot_Taps             mixer centre, a little above (Bubbles prompt)
    Pivot_Duck             the duck's float point (body centre)
"""
import math

PORC = "f6f4ee"       # porcelain (the palette's off-white, a touch brighter)
GOLD = "f2c13d"
WATER = "86cdee"
FOAM = "ffffff"
BUB_BLUE = "dcf1ff"
BUB_PINK = "ffe3f1"
BUB_MINT = "e2fff0"
RED = "d9443c"
BLUE = "3f79d4"
DUCK = "ffd23f"
BEAK = "f28a2e"
INK = "23262c"
PILLOW = "8fb8f0"

TX = -0.3            # the tub's centre x (the filler sits at +X, so the tub shifts a little to centre the footprint)
EX = 1.75            # stadium: the round ends' centres at TX +/- EX
RW = 1.7             # wall plan radius (width 3.4)
WALL_Y0, WALL_Y1 = 1.5, 2.62
RIM_R = 1.65         # roll-top tube centreline radius
RIM_D = 0.36         # roll-top tube diameter
RIM_Y = 2.62         # tube centre height (top 2.80)
WATER_R = 1.6        # water plan radius
WATER_TOP = 2.68
BELLY_H = 1.8        # the main belly's height (centred on WALL_Y0: it turns the wall under, down to y 0.6)
BELLY_END_H = 1.2    # the round-end fillers' height: shallow, so they stay tucked above the main belly (no lobes)
BELLY_END_W = 2 * RW - 0.04   # round-end bellies: 0.02 inside the wall line, so the seam never crosses the wall
FX = TX + 4.18       # the filler's x
RECLINE = 10.0       # bather recline (degrees, head up): the torso at the water line, face up above it, feet still inside the tub


def _yaw(x, z, deg):
    a = math.radians(deg)
    return x * math.cos(a) + z * math.sin(a), -x * math.sin(a) + z * math.cos(a)


def _roblox_shading(m):
    """Make the review renders shade cylinders the way Roblox does (render-only, the part data is unchanged).

    primlib's cylinder mesh shares its ring vertices between the side and the flat caps, and every face is
    smooth-shaded, so Blender averages the cap normals into the side: a short wide cylinder (WallEnd*: 1.1
    tall, 3.4 across) renders like a dark barrel and the flat WallMid between the ends looked like a pale
    label stuck on the tub. A Roblox cylinder has hard cap edges. Splitting the normals at every edge
    sharper than 45 degrees gives exactly that (sphere / ellipsoid facets are 18-20 degrees apart: untouched).
    """
    for o in m.coll.all_objects:
        me = getattr(o, "data", None)
        if me is None or not hasattr(me, "edges"):
            continue
        normals = {}
        for poly in me.polygons:
            for ek in poly.edge_keys:
                normals.setdefault(ek, []).append(poly.normal.copy())
        for e in me.edges:
            ns = normals.get(tuple(sorted(e.vertices)), ())
            if len(ns) == 2 and ns[0].angle(ns[1], 0.0) > math.radians(45):
                e.use_edge_sharp = True


def build(D, P):
    m = P.Model(D, "Bathtub", category="Home")

    # ------------------------------------------------ body: a stadium wall turned under by three bellies
    # The wall is a real tub's: straight long sides (WallMid) tangent to round ends (WallEnd*), smooth in
    # Roblox (see _roblox_shading). One long Belly alone is an ELLIPSE in plan, narrower than the stadium near
    # the round ends, which left a shadowed ledge under the wall there; a round BellyEnd under each end
    # follows the stadium instead, so the wall turns under all the way round.
    m.ellipsoid("Belly", (TX, WALL_Y0, 0), (2 * (EX + RW) - 0.1, BELLY_H, 2 * RW), PORC, "SmoothPlastic")
    wy = (WALL_Y0 + WALL_Y1) / 2
    m.block("WallMid", (TX, wy, 0), (2 * EX, WALL_Y1 - WALL_Y0, 2 * RW), PORC, "SmoothPlastic")
    for tag, s in (("L", 1), ("R", -1)):
        m.cyl("WallEnd" + tag, (TX + s * EX, WALL_Y0, 0), (TX + s * EX, WALL_Y1, 0), 2 * RW, PORC, "SmoothPlastic")
        m.ellipsoid("BellyEnd" + tag, (TX + s * EX, WALL_Y0, 0), (BELLY_END_W, BELLY_END_H, BELLY_END_W), PORC,
                    "SmoothPlastic")

    # ------------------------------------------------ roll-top rim: long sides + 4-segment half rings, ball joints
    for tag, sz in (("Front", -1), ("Back", 1)):
        m.cyl("Rim" + tag, (TX - EX, RIM_Y, sz * RIM_R), (TX + EX, RIM_Y, sz * RIM_R), RIM_D, PORC, "SmoothPlastic")
    k = 0
    for tag, s in (("L", 1), ("R", -1)):
        cx = TX + s * EX
        pts = []
        for i in range(5):
            th = math.radians(-90 + 45 * i)
            pts.append((cx + s * RIM_R * math.cos(th), RIM_Y, RIM_R * math.sin(th)))
        for i in range(4):
            m.cyl("RimArc%s%d" % (tag, i + 1), pts[i], pts[i + 1], RIM_D, PORC, "SmoothPlastic")
        for i, p in enumerate(pts):
            k += 1
            m.ball("RimJoint%d" % k, p, RIM_D, PORC, "SmoothPlastic", collide=False)

    # ------------------------------------------------ bath water (just under the rim)
    wh = 0.18
    m.block("Water", (TX, WATER_TOP - wh / 2, 0), (2 * EX, wh, 2 * WATER_R), WATER, "SmoothPlastic")
    for tag, s in (("L", 1), ("R", -1)):
        m.cyl("WaterEnd" + tag, (TX + s * EX, WATER_TOP - wh, 0), (TX + s * EX, WATER_TOP, 0), 2 * WATER_R, WATER,
              "SmoothPlastic")
    m.pivot("WaterMin", (TX - EX - WATER_R + 0.15, WATER_TOP, -WATER_R + 0.15))
    m.pivot("WaterMax", (TX + EX + WATER_R - 0.15, WATER_TOP, WATER_R - 0.15))

    # ------------------------------------------------ gold lion-claw feet (leg out of the belly, ball paw)
    for i, (sx, sz) in enumerate(((1, -1), (-1, -1), (1, 1), (-1, 1))):
        top = (TX + sx * 2.45, 1.12, sz * 0.95)
        paw = (TX + sx * 2.85, 0.25, sz * 1.25)
        m.cyl("FootLeg%d" % (i + 1), top, paw, 0.36, GOLD, "Metal", collide=False)
        m.ball("FootPaw%d" % (i + 1), paw, 0.5, GOLD, "Metal")

    # ------------------------------------------------ bath pillow on the head-end rim
    m.ellipsoid("BathPillow", (TX - EX - 1.35, 2.95, 0), (0.55, 0.85, 1.5), PILLOW, "Fabric", rot=(0, 0, -22),
                collide=False)

    # ------------------------------------------------ freestanding filler at the tap end
    for tag, sz in (("H", -1), ("C", 1)):
        m.cyl("FillerPipe" + tag, (FX, 0, sz * 0.34), (FX, 3.1, sz * 0.34), 0.24, GOLD, "Metal")
    m.cyl("TapMixer", (FX, 3.1, -0.56), (FX, 3.1, 0.56), 0.36, GOLD, "Metal")
    for tag, sz, cap in (("H", -1, RED), ("C", 1, BLUE)):
        z = sz * 0.38
        m.cyl("TapCross%s1" % tag, (FX - 0.3, 3.32, z), (FX + 0.3, 3.32, z), 0.11, GOLD, "Metal", collide=False)
        m.cyl("TapCross%s2" % tag, (FX, 3.32, z - 0.3), (FX, 3.32, z + 0.3), 0.11, GOLD, "Metal", collide=False)
        m.ball("TapCap" + tag, (FX, 3.42, z), 0.27, cap, "SmoothPlastic", collide=False)
    top_y = 3.85
    tip_x = TX + EX + 1.15
    m.cyl("SpoutRiser", (FX, 3.1, 0), (FX, top_y, 0), 0.2, GOLD, "Metal", collide=False)
    m.ball("SpoutElbow", (FX, top_y, 0), 0.26, GOLD, "Metal", collide=False)
    m.cyl("SpoutArm", (FX, top_y, 0), (tip_x, top_y, 0), 0.2, GOLD, "Metal", collide=False)
    m.ball("SpoutBend", (tip_x, top_y, 0), 0.24, GOLD, "Metal", collide=False)
    m.cyl("SpoutTip", (tip_x, top_y, 0), (tip_x, top_y - 0.32, 0), 0.24, GOLD, "Metal", collide=False)
    m.pivot("SpoutTip", (tip_x, top_y - 0.36, 0))
    m.pivot("Taps", (FX, 3.6, 0))

    # ------------------------------------------------ foam heaps + loose bubbles
    W = WATER_TOP
    foam = (   # low flat mounds = the foam layer
        ((TX + 0.4, W + 0.02, 0.35), (2.8, 0.6, 2.3)),
        ((TX - 1.2, W + 0.0, -0.3), (2.0, 0.5, 1.8)),
        ((TX + 2.25, W + 0.02, 0.5), (1.8, 0.55, 1.7)),
        ((TX + 0.55, W + 0.02, -1.5), (1.5, 0.52, 0.95)),   # spilling over the front rim
    )
    for i, (p, sz) in enumerate(foam):
        m.ellipsoid("Foam%d" % (i + 1), p, sz, FOAM, "SmoothPlastic", collide=False)
    bubbles = (   # round bubbles heaped on the mounds
        ((TX + 0.2, W + 0.38, 0.3), 0.85, FOAM),
        ((TX + 0.9, W + 0.4, 0.75), 0.75, FOAM),
        ((TX + 0.95, W + 0.3, -0.2), 0.6, BUB_BLUE),
        ((TX - 0.45, W + 0.28, 0.75), 0.6, BUB_PINK),
        ((TX + 2.1, W + 0.35, 0.55), 0.7, FOAM),
        ((TX + 2.6, W + 0.3, 0.0), 0.5, BUB_MINT),
        ((TX - 1.4, W + 0.25, -0.45), 0.55, FOAM),
        ((TX + 0.5, W + 0.8, 0.5), 0.5, FOAM),
    )
    for i, (p, d, col) in enumerate(bubbles):
        m.ball("Bubble%d" % (i + 1), p, d, col, "SmoothPlastic", reflectance=0.05, collide=False)
    # (the two static BubbleFloat* balls hovering above the water were dropped 2026-09-24 to pay for the
    #  BellyEnd parts: at play distance they read as specks, and the client's rising bubble particles do that job)

    # ------------------------------------------------ rubber duck (faces the front, turned a little toward -X)
    dc = (TX + 1.55, W + 0.14, -0.9)
    yaw = -28.0

    def at(x, y, z):
        rx, rz = _yaw(x, z, yaw)
        return (dc[0] + rx, dc[1] + y, dc[2] + rz)

    Y = P.angles(0, yaw, 0)
    m.ellipsoid("DuckBody", at(0, 0, 0), (0.78, 0.62, 1.05), DUCK, "SmoothPlastic", rot=Y, collide=False)
    m.ellipsoid("DuckTail", at(0, 0.2, 0.48), (0.34, 0.36, 0.26), DUCK, "SmoothPlastic", rot=Y @ P.angles(-35, 0, 0),
                collide=False)
    m.ball("DuckHead", at(0, 0.5, -0.26), 0.56, DUCK, "SmoothPlastic", collide=False)
    m.ellipsoid("DuckBeak", at(0, 0.44, -0.58), (0.34, 0.13, 0.3), BEAK, "SmoothPlastic", rot=Y, collide=False)
    for tag, sx in (("L", 1), ("R", -1)):
        m.ball("DuckEye" + tag, at(sx * 0.14, 0.6, -0.5), 0.09, INK, "SmoothPlastic", collide=False)
    m.pivot("Duck", dc)

    # ------------------------------------------------ the bather: pelvis on the seat, head toward -X, reclined
    seat = (TX - 0.9, 1.8, 0)
    a = math.radians(RECLINE)
    head = (seat[0] - 2.4 * math.cos(a), seat[1] + 2.4 * math.sin(a), 0)
    m.pivot("BathSeat", seat)
    m.pivot("BathHead", head)

    m.attr("Cost", 1000)
    m.attr("Notes", "Clawfoot bathtub (primlib parts): one lying seat at Pivot_BathSeat (head toward Pivot_BathHead, "
                    "the -X end), Bubbles prompt at the gold filler (Pivot_Taps) -> foam surge + bubbling loop, the "
                    "Duck* parts bob. Built by fun-builds/models/build_Bathtub.py.")
    _roblox_shading(m)
    return m.finish()
