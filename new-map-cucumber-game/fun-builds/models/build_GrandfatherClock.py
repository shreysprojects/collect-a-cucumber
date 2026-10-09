"""GrandfatherClock (Home, fun-builds 2026-09-24, package HomeOffice): a tall wooden longcase clock,
2.6 wide x 8.5 high x 1.6 deep. Bun feet, a panelled plinth, a long trunk with a glass door showing the
brass pendulum and three brass weights on their chains, a hood with brass-capped columns round a cream
dial (12 hour marks, gold corner spandrels, spade-tipped hands), an arched crown with a turning sun/moon
dial in the arch, and three brass finials.

Behaviour contract (behaviours/client/GrandfatherClock.lua):
  Pendulum*   PendulumRod / PendulumBob / PendulumBobFace swing about Pivot_PendulumPivot (authored Z axis),
              amplitude State_PendulumSwing degrees, shipped at rest (vertical)
  HourHand*   HourHand + HourHandTip turn about Pivot_FaceCentre (authored Z axis); shipped at
              State_HourAngle degrees clockwise from 12 (10:10 - the showroom pose)
  MinuteHand* MinuteHand + MinuteHandTip, shipped at State_MinuteAngle
  Moon*       MoonDisc / MoonSun / MoonMoon / MoonStarA / MoonStarB turn about Pivot_MoonCentre; shipped at
              State_MoonAngle (0 = the sun at the top = noon)
  Pivot_Chime the movement inside the hood: where the tick and the hour chime come from
A positive angle is clockwise as seen from the front: CFrame.Angles(0, 0, rad(angle)) about the pivot.
"""
import math

WOOD = "8a5a2b"
WOOD_D = "6b4423"
WOOD_IN = "4e311a"     # the trunk's inside (seen through the glass)
BRASS = "f2c13d"
BRASS_D = "c9962a"
CREAM = "f2f0ea"
INK = "23262c"
NIGHT = "2c3e7a"
MOON = "fbf1c8"
SUN = "ffb530"

W = 2.6
H = 8.5
FACE_C = (0.0, 6.25)       # dial centre (x, y)
FACE_D = 1.45              # white face diameter
PEND_TOP = 5.12            # pendulum pivot y (hidden behind the door's top rail)
PEND_Z = -0.22
MOON_C = (0.0, 7.5)        # moon dial centre (on the cornice top line)
MOON_Z = -0.625
HOUR_ANGLE = 305.0         # 10:10
MINUTE_ANGLE = 60.0
SWING = 6.0


def polar(r, deg):
    """A point on the dial at clock angle deg (clockwise from 12, seen from the front): +X is the viewer's left."""
    a = math.radians(deg)
    return (-r * math.sin(a), r * math.cos(a))


def build(D, P):
    m = P.Model(D, "GrandfatherClock", category="Home")

    # ------------------------------------------------------------ feet + plinth
    for i, (sx, sz) in enumerate(((1, -1), (-1, -1), (1, 1), (-1, 1))):
        m.ellipsoid("Foot%d" % (i + 1), (sx * 1.02, 0.18, sz * 0.58), (0.5, 0.36, 0.5), WOOD_D, "Wood")
    m.block("Plinth", (0, 0.86, 0), (2.4, 1.24, 1.46), WOOD, "Wood")
    m.block("PlinthPanel", (0, 0.86, -0.745), (1.62, 0.78, 0.06), WOOD_D, "Wood")
    m.block("PlinthMould", (0, 1.53, 0), (2.56, 0.16, 1.58), WOOD_D, "Wood")

    # ------------------------------------------------------------ trunk: back, sides, door frame, glass
    m.block("TrunkBack", (0, 3.4, 0.55), (2.08, 3.66, 0.12), WOOD_IN, "WoodPlanks")
    for side, sx in (("L", 1), ("R", -1)):
        m.block("TrunkSide" + side, (sx * 0.99, 3.4, -0.02), (0.14, 3.66, 1.18), WOOD, "Wood")
        m.block("DoorStile" + side, (sx * 0.87, 3.4, -0.6), (0.3, 3.66, 0.1), WOOD, "Wood")
    m.block("DoorRailTop", (0, 5.06, -0.6), (1.5, 0.34, 0.1), WOOD, "Wood")
    m.block("DoorRailBottom", (0, 1.77, -0.6), (1.5, 0.34, 0.1), WOOD, "Wood")
    m.block("DoorGlass", (0, 3.41, -0.6), (1.46, 2.98, 0.05), "cfe6f2", "Glass", transparency=0.72, collide=False,
            shadow=False)
    m.ball("DoorKnob", (-0.87, 3.4, -0.7), 0.14, BRASS, "Metal", collide=False)
    m.block("WaistMould", (0, 5.3, 0), (2.34, 0.16, 1.44), WOOD_D, "Wood")

    # ------------------------------------------------------------ weights on chains (behind the pendulum)
    for i, (x, y) in enumerate(((0.42, 4.02), (0.0, 3.62), (-0.42, 3.86))):
        n = i + 1
        top = y + 0.45
        m.block("Chain%d" % n, (x, (top + 5.2) / 2, 0.24), (0.05, 5.2 - top, 0.05), "7d6a45", "Metal", collide=False,
                shadow=False)
        m.cyl("Weight%d" % n, (x, y - 0.45, 0.24), (x, top, 0.24), 0.3, BRASS, "Metal", collide=False)

    # ------------------------------------------------------------ pendulum (rest pose: hanging straight down)
    bob_y = 2.55
    m.block("PendulumRod", (0, (PEND_TOP + bob_y) / 2, PEND_Z), (0.07, PEND_TOP - bob_y, 0.05), BRASS_D, "Metal",
            collide=False)
    m.disc("PendulumBob", (0, bob_y, PEND_Z), (0, 0, -1), 0.74, 0.08, BRASS, "Metal", collide=False)
    m.disc("PendulumBobFace", (0, bob_y, PEND_Z - 0.05), (0, 0, -1), 0.46, 0.055, "ffd76a", "Metal", collide=False)
    m.pivot("PendulumPivot", (0, PEND_TOP, PEND_Z))

    # ------------------------------------------------------------ hood
    m.block("Hood", (0, 6.35, 0), (2.4, 2.02, 1.4), WOOD, "Wood")
    for side, sx in (("L", 1), ("R", -1)):
        x = sx * 1.1
        m.cyl("Column" + side, (x, 5.46, -0.74), (x, 7.24, -0.74), 0.2, WOOD_D, "Wood")
        m.block("ColumnBase" + side, (x, 5.46, -0.74), (0.3, 0.14, 0.3), BRASS, "Metal", collide=False)
        m.block("ColumnCap" + side, (x, 7.26, -0.74), (0.3, 0.14, 0.3), BRASS, "Metal", collide=False)
    m.block("Cornice", (0, 7.43, -0.02), (2.66, 0.16, 1.66), WOOD_D, "Wood")

    # ------------------------------------------------------------ dial
    fx, fy = FACE_C
    m.block("DialPlate", (fx, fy + 0.1, -0.73), (1.8, 1.78, 0.08), NIGHT, "SmoothPlastic")
    for i, deg in enumerate((315, 45, 135, 225)):     # gold spandrels in the four plate corners
        px, py = polar(1.07, deg)
        m.ball("Spandrel%d" % (i + 1), (fx + px, fy + py, -0.77), 0.3, BRASS, "Metal", collide=False)
    m.disc("DialBezel", (fx, fy, -0.79), (0, 0, -1), FACE_D + 0.18, 0.06, BRASS, "Metal", collide=False)
    m.disc("DialFace", (fx, fy, -0.815), (0, 0, -1), FACE_D, 0.055, CREAM, "SmoothPlastic", collide=False)
    for h in range(12):
        deg = h * 30
        big = h % 3 == 0
        px, py = polar(0.6 if big else 0.62, deg)
        m.block("Mark%02d" % (h if h else 12), (fx + px, fy + py, -0.84),
                (0.09 if big else 0.05, 0.2 if big else 0.12, 0.05), INK, "SmoothPlastic", rot=(0, 0, deg),
                collide=False, shadow=False)

    # hands (showroom 10:10); a hand's part is centred along its radius, the spade tip at its end
    for name, deg, length, width, z, tip in (("HourHand", HOUR_ANGLE, 0.4, 0.07, -0.875, (0.17, 0.19)),
                                             ("MinuteHand", MINUTE_ANGLE, 0.6, 0.05, -0.93, (0.12, 0.16))):
        tail = 0.1
        px, py = polar((length - tail) / 2, deg)
        m.block(name, (fx + px, fy + py, z), (width, length + tail, 0.05), INK, "SmoothPlastic", rot=(0, 0, deg),
                collide=False, shadow=False)
        tx, ty = polar(length - 0.06, deg)
        m.ellipsoid(name + "Tip", (fx + tx, fy + ty, z), (tip[0], tip[1], 0.05), INK, "SmoothPlastic",
                    rot=(0, 0, deg), collide=False, shadow=False)
    m.ball("HandCap", (fx, fy, -0.96), 0.14, BRASS, "Metal", collide=False)
    m.pivot("FaceCentre", (fx, fy, -0.93))

    # ------------------------------------------------------------ crown: arch + brass rim + the sun/moon dial
    mx, my = MOON_C
    m.cylx("CrownRim", (mx, my, -0.36), 0.2, 1.86, BRASS_D, "Metal", rot=(0, 90, 0))
    m.cylx("CrownArch", (mx, my, 0.0), 1.2, 1.72, WOOD, "Wood", rot=(0, 90, 0))
    m.disc("MoonDisc", (mx, my, MOON_Z), (0, 0, -1), 1.24, 0.055, NIGHT, "SmoothPlastic", collide=False)
    sx_, sy_ = polar(0.37, 0)
    m.disc("MoonSun", (mx + sx_, my + sy_, MOON_Z - 0.035), (0, 0, -1), 0.36, 0.055, SUN, "Neon", collide=False,
           shadow=False)
    ux, uy = polar(0.37, 180)
    m.disc("MoonMoon", (mx + ux, my + uy, MOON_Z - 0.035), (0, 0, -1), 0.32, 0.055, MOON, "SmoothPlastic",
           collide=False, shadow=False)
    for tag, deg, r in (("A", 140, 0.44), ("B", 222, 0.46)):
        px, py = polar(r, deg)
        m.ball("MoonStar" + tag, (mx + px, my + py, MOON_Z - 0.03), 0.08, "fff6d0", "Neon", collide=False, shadow=False)
    m.pivot("MoonCentre", (mx, my, MOON_Z))

    # ------------------------------------------------------------ finials
    m.ball("FinialTop", (0, my + 0.9, -0.1), 0.2, BRASS, "Metal", collide=False)
    for side, sx in (("L", 1), ("R", -1)):
        m.block("FinialBase" + side, (sx * 1.1, 7.58, -0.3), (0.26, 0.14, 0.26), WOOD_D, "Wood")
        m.ball("Finial" + side, (sx * 1.1, 7.76, -0.3), 0.26, BRASS, "Metal", collide=False)

    m.pivot("Chime", (0, 6.3, 0))
    m.attr("State_HourAngle", HOUR_ANGLE)
    m.attr("State_MinuteAngle", MINUTE_ANGLE)
    m.attr("State_MoonAngle", 0.0)
    m.attr("State_PendulumSwing", SWING)
    m.attr("Cost", 1500)
    m.attr("DisplayName", "Grandfather Clock")
    return m.finish()
