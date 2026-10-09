"""Toilet (Home) -- a white porcelain toilet with a raised lid, fun-builds HomeBath 2026-09-24.

~2.4 wide x 4 tall x 3.2 deep: an oval foot and a vase-like pedestal, a round bowl under a wooden seat (the
opening painted as a grey ring round blue water), the lid raised and leaning on a boxy cistern with a rounded
lid, a chrome flush lever on the cistern's front-left (+X) corner pointing out past the side, a chrome supply pipe + stop valve at the back,
and on the cistern lid a spare toilet roll and a tiny potted plant. A blue bath mat on the floor in front.

Part names / pivots the behaviour relies on (FB/src/behaviours/*/Toilet.lua):
    Handle*              the flush lever + knob (the client dips them about Pivot_Handle, axis = the build's Z)
    FlushPlate           the lever's round chrome base (the Flush prompt hangs off it)
    BowlWater            the blue water in the bowl (the client darkens / swirls it during a flush)
    Pivot_Seat           the seat's top centre where a sitter's hips rest (faces the front, -Z)
    Pivot_Handle         the lever's pivot (centre of the FlushPlate, on the cistern's front face)
    Pivot_Bowl           the water surface centre (swirl centre)
"""
import math

PORC = "f6f4ee"
PORC_SH = "e2dfd6"
SEAT = "a8733d"     # light wood seat + lid
SEAT_D = "8a5a2b"
CHROME = "c9d2de"
WATER = "5fc3ec"
BOWL_IN = "d6dbe2"
MAT = "3f79d4"
MAT_L = "6a9ef0"
PAPER = "ffffff"
CARD = "b98d5a"
POT = "d9443c"
LEAF = "4caf50"

SEAT_TOP = 2.12
BOWL_Z = -0.3       # bowl / seat centre z
TANK_Z0, TANK_Z1 = 0.72, 1.58   # cistern front / back faces
TANK_Y0, TANK_Y1 = 2.2, 3.78
TANK_X = 1.15       # cistern half width


def build(D, P):
    m = P.Model(D, "Toilet", category="Home")

    # ------------------------------------------------ bath mat (flat, under the front)
    m.ellipsoid("Mat", (0, 0.03, -0.55), (2.9, 0.06, 2.3), MAT, "Fabric", collide=False)
    m.ellipsoid("MatStripe", (0, 0.045, -0.55), (2.3, 0.06, 1.7), MAT_L, "Fabric", collide=False)

    # ------------------------------------------------ foot, pedestal, bolt caps
    m.ellipsoid("Foot", (0, 0.2, 0.15), (1.7, 0.4, 2.1), PORC, "SmoothPlastic")
    m.ellipsoid("Pedestal", (0, 0.95, 0.05), (1.25, 1.9, 1.75), PORC, "SmoothPlastic")
    for tag, sx in (("L", 1), ("R", -1)):
        m.ellipsoid("BoltCap" + tag, (sx * 0.72, 0.3, 0.55), (0.24, 0.2, 0.24), PORC_SH, "SmoothPlastic", collide=False)

    # ------------------------------------------------ bowl + seat (the opening is painted rings) + hinges
    m.ellipsoid("Bowl", (0, 1.52, BOWL_Z), (2.1, 1.3, 2.55), PORC, "SmoothPlastic")
    m.block("BowlNeck", (0, 1.85, 0.62), (1.3, 0.7, 0.4), PORC, "SmoothPlastic")
    m.ellipsoid("Seat", (0, SEAT_TOP - 0.11, BOWL_Z), (2.22, 0.24, 2.6), SEAT, "Wood")
    m.ellipsoid("BowlInner", (0, SEAT_TOP + 0.005, BOWL_Z - 0.05), (1.4, 0.05, 1.72), BOWL_IN, "SmoothPlastic",
                collide=False)
    m.ellipsoid("BowlWater", (0, SEAT_TOP + 0.02, BOWL_Z - 0.12), (1.0, 0.05, 1.2), WATER, "SmoothPlastic",
                collide=False)
    for tag, sx in (("L", 1), ("R", -1)):
        m.cyl("Hinge" + tag, (sx * 0.38, SEAT_TOP - 0.02, 0.84), (sx * 0.72, SEAT_TOP - 0.02, 0.84), 0.2, CHROME,
              "Metal", collide=False)
    m.pivot("Seat", (0, SEAT_TOP, BOWL_Z + 0.15))
    m.pivot("Bowl", (0, SEAT_TOP + 0.045, BOWL_Z - 0.12))

    # ------------------------------------------------ raised lid, leaning back on the cistern
    lid_len, lid_th = 2.2, 0.2
    tilt = 4.0  # degrees back from vertical (top toward the cistern, +Z)
    hinge = (0, SEAT_TOP + 0.02, TANK_Z0 - 0.26)
    a = math.radians(tilt)
    # the lid's centre: half its length up the tilted axis u from the hinge, half its thickness in front (-n)
    lc = (0, hinge[1] + lid_len / 2 * math.cos(a) + lid_th / 2 * math.sin(a),
          hinge[2] + lid_len / 2 * math.sin(a) - lid_th / 2 * math.cos(a))
    m.ellipsoid("Lid", lc, (1.85, lid_len, lid_th), SEAT, "Wood", rot=(tilt, 0, 0))
    m.ellipsoid("LidRim", (lc[0], lc[1], lc[2] - 0.03), (1.5, lid_len - 0.34, 0.2), SEAT_D, "Wood",
                rot=(tilt, 0, 0), collide=False)

    # ------------------------------------------------ cistern: box, base trim, rounded lid
    tz = (TANK_Z0 + TANK_Z1) / 2
    td = TANK_Z1 - TANK_Z0
    m.block("Tank", (0, (TANK_Y0 + TANK_Y1) / 2, tz), (2 * TANK_X, TANK_Y1 - TANK_Y0, td), PORC, "SmoothPlastic")
    m.block("TankTrim", (0, TANK_Y0 + 0.08, tz), (2 * TANK_X + 0.08, 0.16, td + 0.08), PORC_SH, "SmoothPlastic",
            collide=False)
    ly = TANK_Y1 + 0.1
    m.block("TankLid", (0, ly, tz), (2 * TANK_X + 0.14, 0.2, td + 0.14), PORC, "SmoothPlastic")
    for tag, zz in (("F", TANK_Z0 - 0.07), ("B", TANK_Z1 + 0.07)):
        m.cyl("TankLidEdge" + tag, (-TANK_X - 0.07, ly, zz), (TANK_X + 0.07, ly, zz), 0.2, PORC, "SmoothPlastic",
              collide=False)

    # ------------------------------------------------ flush lever (front-left corner of the cistern)
    hx, hy = TANK_X - 0.17, TANK_Y1 - 0.36
    fz = TANK_Z0 - 0.02
    m.disc("FlushPlate", (hx, hy, fz - 0.03), (0, 0, -1), 0.4, 0.07, CHROME, "Metal", collide=False)
    m.cyl("HandleLever", (hx, hy, fz - 0.12), (hx + 0.5, hy, fz - 0.12), 0.15, CHROME, "Metal", collide=False)
    m.ball("HandleKnob", (hx + 0.54, hy, fz - 0.12), 0.24, CHROME, "Metal", collide=False)
    m.cyl("HandleHub", (hx, hy, fz - 0.02), (hx, hy, fz - 0.18), 0.2, CHROME, "Metal", collide=False)
    m.pivot("Handle", (hx, hy, fz - 0.1))

    # ------------------------------------------------ chrome supply pipe + stop valve (back, -X side)
    px, pz = -0.75, TANK_Z1 - 0.2
    m.cyl("SupplyPipe", (px, 0.02, pz), (px, TANK_Y0 + 0.05, pz), 0.12, CHROME, "Metal", collide=False)
    m.ball("SupplyValve", (px, 0.62, pz), 0.26, CHROME, "Metal", collide=False)
    m.cyl("SupplyKnob", (px, 0.62, pz), (px, 0.62, pz + 0.3), 0.1, CHROME, "Metal", collide=False)
    m.disc("SupplyFlange", (px, 0.03, pz), (0, 1, 0), 0.3, 0.06, CHROME, "Metal", collide=False)

    # ------------------------------------------------ on the cistern lid: a spare roll + a tiny potted plant
    top = ly + 0.1
    rx = -0.52
    m.cyl("PaperRoll", (rx, top, tz), (rx, top + 0.62, tz), 0.72, PAPER, "Fabric", collide=False)
    m.cyl("PaperCore", (rx, top + 0.59, tz), (rx, top + 0.65, tz), 0.28, CARD, "Cardboard", collide=False)
    px2 = 0.55
    m.cyl("PlantPot", (px2, top, tz), (px2, top + 0.42, tz), 0.44, POT, "SmoothPlastic", collide=False)
    m.cyl("PlantPotRim", (px2, top + 0.36, tz), (px2, top + 0.46, tz), 0.52, POT, "SmoothPlastic", collide=False)
    m.ball("PlantLeaf1", (px2, top + 0.68, tz), 0.5, LEAF, "SmoothPlastic", collide=False)
    m.ball("PlantLeaf2", (px2 + 0.18, top + 0.9, tz - 0.08), 0.34, "5cc75f", "SmoothPlastic", collide=False)

    m.attr("Cost", 300)
    m.attr("Notes", "Toilet (primlib parts): seat at Pivot_Seat (faces -Z, prompt Sit), Flush prompt on the "
                    "FlushPlate -> the Handle* parts dip about Pivot_Handle, a blue swirl spins in the bowl "
                    "(Pivot_Bowl) and the flush sound plays. Built by fun-builds/models/build_Toilet.py.")
    return m.finish()
