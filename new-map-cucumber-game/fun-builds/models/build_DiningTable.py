"""DiningTable (Home, fun-builds 2026-09-24): a wooden dining set - a 5 x 4 table (top at 3.2) with four
chairs round it, one per side, each facing across the table; a red table runner with yellow stitching,
four place settings (blue-rimmed plates, each with a cucumber on it) and a centrepiece (a brass candle
holder with a lit candle + a blue vase of flowers). ~8 x 8 footprint.

Sitter clearances (fix pass 2026-09-24; a seated avatar = torso ~1 deep centred over the seat, thighs ~1
thick running ~1.5 forward from the hips, thigh top ~3.1 on a 2.13 cushion, shoulders + arms ~4 wide):
  * end chairs: seat centre 0.7 beyond the table end (0.63 beyond the runner flap) - the torso clears it
    (the table is 5 long, not 6, so the ends stay inside the 8-stud footprint);
  * long-side chairs: seat centre 1.1 beyond the table edge;
  * one chair per side, so no two sitters sit shoulder to shoulder (arms would overlap at 3-stud spacing);
  * the apron is a thin inset underframe (|x| <= 1.4, |z| <= 1.1, bottom 2.86) that the knees never reach
    (end knees stop near |x| 1.7, side knees near |z| 1.6); the corner legs sit outside every leg path.

Behaviour contract (behaviours/server|client/DiningTable.lua):
  Pivot_Seat1..4      the top of each chair cushion (hips rest here)
  Pivot_Seat1..4Face  a point 1 stud straight ahead of that seat, over the table: the sitter looks at it
  CandleFlame         the Neon flame (Ellipsoid) the client flickers + lights; Pivot_Candle = its base
"""
import math

WOOD = "8a5a2b"
WOOD_DARK = "6b4423"
RED = "d9443c"
YELLOW = "f2c13d"
BLUE = "3f79d4"
WHITE = "f2f0ea"
GREEN = "5aa845"
LEAF = "3f8f3a"

TABLE_TOP = 3.2
TOP_THICK = 0.22
HALF_LEN = 2.5          # table x extent (5 long)
HALF_DEP = 2.0          # table z extent (4 deep)
RUNNER_TOP = 3.24
LEG_X, LEG_Z = 2.0, 1.5


def build(D, P):
    m = P.Model(D, "DiningTable", category="Home")

    # ------------------------------------------------------------ table
    m.block("TableTop", (0, TABLE_TOP - TOP_THICK / 2, 0), (HALF_LEN * 2, TOP_THICK, HALF_DEP * 2), WOOD, "Wood")
    under = TABLE_TOP - TOP_THICK
    # thin inset underframe, clear of every knee path (see the docstring)
    m.block("TableApron", (0, under - 0.05, 0), (2.8, 0.14, 2.2), WOOD_DARK, "Wood")
    for i, (x, z) in enumerate([(LEG_X, -LEG_Z), (-LEG_X, -LEG_Z), (LEG_X, LEG_Z), (-LEG_X, LEG_Z)], start=1):
        m.cyl("TableLeg%d" % i, (x, 0.3, z), (x, under + 0.02, z), 0.44, WOOD_DARK, "Wood")
        m.cyl("TableFoot%d" % i, (x, 0.0, z), (x, 0.32, z), 0.58, WOOD, "Wood")

    # ------------------------------------------------------------ runner (along X, drapes over both ends)
    m.block("Runner", (0, RUNNER_TOP - 0.025, 0), (HALF_LEN * 2 + 0.04, 0.05, 1.5), RED, "Fabric")
    for side, sx in (("L", 1), ("R", -1)):
        m.block("RunnerFlap" + side, (sx * (HALF_LEN + 0.045), 2.92, 0), (0.05, 0.64, 1.5), RED, "Fabric")
    for side, sz in (("F", -1), ("B", 1)):
        m.block("RunnerStitch" + side, (0, RUNNER_TOP + 0.01, sz * 0.6), (HALF_LEN * 2 - 0.1, 0.05, 0.06), YELLOW,
                "Fabric", collide=False, shadow=False)

    # ------------------------------------------------------------ chairs (local frame: the sitter faces -Z, back at +Z)
    # (centre x, centre z, yaw) - yaw turns local -Z toward the table
    chairs = [
        (HALF_LEN + 0.7, 0.0, 90),       # Seat1: viewer's left end, faces -X
        (-(HALF_LEN + 0.7), 0.0, -90),   # Seat2: viewer's right end, faces +X
        (0.0, -(HALF_DEP + 1.1), 180),   # Seat3: front, faces +Z
        (0.0, HALF_DEP + 1.1, 0),        # Seat4: back, faces -Z
    ]
    for n, (cx, cz, yaw) in enumerate(chairs, start=1):
        chair(m, n, cx, cz, yaw)

    # ------------------------------------------------------------ place settings (in front of each chair)
    settings = [(1.8, 0.0, True, 90), (-1.8, 0.0, True, -90), (0.0, -1.35, False, 180), (0.0, 1.35, False, 0)]
    for n, (x, z, on_runner, yaw) in enumerate(settings, start=1):
        base = RUNNER_TOP if on_runner else TABLE_TOP
        m.disc("PlateRim%d" % n, (x, base + 0.02, z), (0, 1, 0), 1.1, 0.05, BLUE, "SmoothPlastic", collide=False)
        m.disc("Plate%d" % n, (x, base + 0.03, z), (0, 1, 0), 0.84, 0.05, WHITE, "SmoothPlastic", collide=False)
        m.ellipsoid("Cucumber%d" % n, (x, base + 0.13, z), (0.62, 0.2, 0.2), GREEN, "SmoothPlastic",
                    rot=(0, yaw + 35, 0), collide=False)

    # ------------------------------------------------------------ centrepiece: candle (viewer's right) + vase (left)
    cx = -0.72
    m.disc("CandleBase", (cx, RUNNER_TOP + 0.04, 0), (0, 1, 0), 0.62, 0.08, YELLOW, "Metal", collide=False)
    m.cyl("CandleStem", (cx, RUNNER_TOP + 0.07, 0), (cx, RUNNER_TOP + 0.36, 0), 0.34, YELLOW, "Metal", collide=False)
    candle_top = RUNNER_TOP + 1.12
    m.cyl("Candle", (cx, RUNNER_TOP + 0.34, 0), (cx, candle_top, 0), 0.26, WHITE, "SmoothPlastic", collide=False)
    m.ellipsoid("CandleFlame", (cx, candle_top + 0.16, 0), (0.18, 0.34, 0.18), "ffb347", "Neon",
                collide=False, shadow=False)
    m.pivot("Candle", (cx, candle_top, 0))

    vx = 0.72
    m.ellipsoid("Vase", (vx, RUNNER_TOP + 0.36, 0), (0.7, 0.76, 0.7), BLUE, "SmoothPlastic", collide=False)
    m.cyl("VaseNeck", (vx, RUNNER_TOP + 0.6, 0), (vx, RUNNER_TOP + 0.95, 0), 0.34, BLUE, "SmoothPlastic",
          collide=False)
    top = RUNNER_TOP + 0.95
    m.ellipsoid("VaseLeafL", (vx + 0.2, top + 0.14, 0.02), (0.14, 0.5, 0.24), LEAF, "SmoothPlastic",
                rot=(0, 0, -38), collide=False)
    m.ellipsoid("VaseLeafR", (vx - 0.2, top + 0.14, -0.02), (0.14, 0.5, 0.24), LEAF, "SmoothPlastic",
                rot=(0, 0, 38), collide=False)
    m.ball("FlowerRed", (vx + 0.12, top + 0.42, 0.06), 0.34, RED, "SmoothPlastic", collide=False)
    m.ball("FlowerYellow", (vx - 0.2, top + 0.32, -0.08), 0.3, YELLOW, "SmoothPlastic", collide=False)
    m.ball("FlowerWhite", (vx + 0.02, top + 0.3, -0.24), 0.28, WHITE, "SmoothPlastic", collide=False)

    m.attr("Cost", 900)
    m.attr("DisplayName", "Dining Table")
    return m.finish()


def chair(m, n, cx, cz, yaw):
    """One chair: local frame sitter-faces -Z, back at +Z, turned by yaw about Y and moved to (cx, 0, cz)."""
    a = math.radians(yaw)
    ca, sa = math.cos(a), math.sin(a)

    def w(p):  # local point -> model point (CFrame.Angles(0, yaw, 0))
        x, y, z = p
        return (cx + x * ca + z * sa, y, cz - x * sa + z * ca)

    rot = (0, yaw, 0)
    seat_top = 1.98
    m.block("Chair%dSeat" % n, w((0, seat_top - 0.11, 0)), (1.7, 0.22, 1.6), WOOD, "Wood", rot=rot)
    m.ellipsoid("Chair%dCushion" % n, w((0, seat_top, -0.04)), (1.5, 0.32, 1.4), RED, "Fabric", rot=rot)
    for side, sx in (("L", 1), ("R", -1)):
        m.block("Chair%dLegF%s" % (n, side), w((sx * 0.68, 0.88, -0.63)), (0.24, 1.76, 0.24), WOOD_DARK, "Wood",
                rot=rot)
        m.block("Chair%dPost%s" % (n, side), w((sx * 0.68, 2.3, 0.66)), (0.26, 4.6, 0.26), WOOD_DARK, "Wood",
                rot=rot)
    m.cylx("Chair%dCrest" % n, w((0, 4.52, 0.66)), 1.96, 0.36, WOOD, "Wood", rot=rot)
    # back panel: overlaps each post's inner face (+/-0.55) by 0.02 and runs 0.02 up into the crest (underside 4.34)
    m.block("Chair%dSplat" % n, w((0, 3.46, 0.68)), (1.14, 1.80, 0.12), WOOD, "Wood", rot=rot)
    m.pivot("Seat%d" % n, w((0, seat_top + 0.15, 0)))
    m.pivot("Seat%dFace" % n, w((0, seat_top + 0.15, -1.0)))
