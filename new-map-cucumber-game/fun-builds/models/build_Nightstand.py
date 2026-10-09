"""Nightstand (Home) -- a bedside cabinet with a drawer, books and a table lamp, fun-builds HomeBedroom 2026-09-24.

~2.4 wide x 2.6 tall (cabinet top) x 2 deep. Wooden carcass on brass-capped feet, a blue drawer (matching the Bed's
quilt) with a raised panel and a brass knob, an open shelf with books below it; on top a table lamp (brass foot,
red ceramic ball base, cream drum shade with yellow trims) and a little twin-bell alarm clock.

Part names / pivots the behaviour relies on (FB/src/behaviours/*/Nightstand.lua):
    LampShade              the drum shade (the PointLight lives here; it warms in colour while the lamp is on)
    ShadeInnerTop/Bottom   the discs seen inside the shade's open ends: Neon while the lamp is on
    ClockHour, ClockMinute the alarm clock's hands, authored pointing at 12 (the client turns them to Lighting.ClockTime)
    Pivot_ClockCentre      the clock face centre (hands turn about the build's local Z axis through it)
    Pivot_Lamp             the shade centre
"""

WOOD = "8a5a2b"
WOOD_D = "6b4423"
BRASS = "f2c13d"
BLUE = "3f79d4"
BLUE_L = "6a9ef0"
CREAM = "f2f0ea"
RED = "d9443c"
INK = "23262c"

TOP = 2.6          # cabinet top
LAMP_X, LAMP_Z = 0.42, 0.14
CLOCK_X, CLOCK_Z = -0.56, -0.12


def build(D, P):
    m = P.Model(D, "Nightstand", category="Home")

    # ------------------------------------------------ feet: brass caps under turned wooden legs
    for i, (sx, sz) in enumerate(((1, -1), (-1, -1), (1, 1), (-1, 1))):
        x, z = sx * 0.94, sz * 0.76
        m.cyl("FootCap%d" % (i + 1), (x, 0, z), (x, 0.08, z), 0.3, BRASS, "Metal", collide=False)
        m.cyl("Leg%d" % (i + 1), (x, 0.06, z), (x, 0.44, z), 0.26, WOOD_D, "Wood")

    # ------------------------------------------------ carcass
    m.block("Bottom", (0, 0.5, 0), (2.3, 0.18, 1.9), WOOD, "Wood")
    for side, s in (("L", 1), ("R", -1)):
        m.block("Side" + side, (s * 1.1, 1.49, 0), (0.18, 1.8, 1.92), WOOD, "Wood")
    m.block("Back", (0, 1.49, 0.88), (2.04, 1.8, 0.14), WOOD_D, "Wood")
    m.block("Shelf", (0, 1.36, 0.0), (2.04, 0.1, 1.84), WOOD, "Wood")
    m.block("ShelfLip", (0, 1.36, -0.93), (2.04, 0.12, 0.06), WOOD_D, "Wood", collide=False)
    m.block("Top", (0, TOP - 0.11, 0.02), (2.44, 0.22, 2.0), WOOD, "Wood")
    m.cyl("TopLip", (-1.22, TOP - 0.11, -0.98), (1.22, TOP - 0.11, -0.98), 0.22, WOOD_D, "Wood")

    # ------------------------------------------------ drawer: blue front, raised light panel, brass knob
    m.block("DrawerFront", (0, 1.9, -0.98), (1.96, 0.88, 0.12), BLUE, "SmoothPlastic")
    m.block("DrawerPanel", (0, 1.9, -1.045), (1.56, 0.54, 0.05), BLUE_L, "SmoothPlastic", collide=False)
    m.cyl("DrawerKnobStem", (0, 1.9, -1.06), (0, 1.9, -1.16), 0.1, BRASS, "Metal", collide=False)
    m.ball("DrawerKnob", (0, 1.9, -1.22), 0.26, BRASS, "Metal", collide=False)

    # ------------------------------------------------ books on the open shelf
    y0 = 0.59
    for name, x, w, h, col, tilt in (("BookRed", -0.84, 0.2, 0.64, RED, 0), ("BookYellow", -0.62, 0.17, 0.56, BRASS, 0),
                                     ("BookBlue", -0.36, 0.22, 0.6, BLUE, -14)):
        m.block(name, (x, y0 + h / 2, -0.2), (w, h, 1.0), col, "SmoothPlastic", collide=False, rot=(0, 0, tilt))
    m.block("BookFlat1", (0.46, y0 + 0.08, -0.18), (0.95, 0.15, 1.05), BLUE_L, "SmoothPlastic", collide=False)
    m.block("BookFlat2", (0.42, y0 + 0.22, -0.2), (0.82, 0.14, 0.95), RED, "SmoothPlastic", collide=False, rot=(0, 8, 0))

    # ------------------------------------------------ table lamp
    x, z = LAMP_X, LAMP_Z
    m.cyl("LampFoot", (x, TOP - 0.02, z), (x, TOP + 0.08, z), 0.72, BRASS, "Metal")
    m.ball("LampBase", (x, TOP + 0.47, z), 0.84, RED, "SmoothPlastic")
    m.cyl("LampNeck", (x, TOP + 0.84, z), (x, TOP + 1.0, z), 0.26, BRASS, "Metal", collide=False)
    m.cyl("LampStem", (x, TOP + 0.98, z), (x, TOP + 1.5, z), 0.09, BRASS, "Metal", collide=False)
    sb, st = TOP + 1.12, TOP + 1.9  # shade bottom / top
    m.cyl("LampShade", (x, sb, z), (x, st, z), 1.3, CREAM, "Fabric")
    m.disc("ShadeTrimBottom", (x, sb, z), (0, 1, 0), 1.36, 0.08, BRASS, "Fabric", collide=False)
    m.disc("ShadeTrimTop", (x, st, z), (0, 1, 0), 1.36, 0.08, BRASS, "Fabric", collide=False)
    m.disc("ShadeInnerBottom", (x, sb - 0.05, z), (0, 1, 0), 1.14, 0.05, "fff4d6", "SmoothPlastic", collide=False)
    m.disc("ShadeInnerTop", (x, st + 0.05, z), (0, 1, 0), 1.14, 0.05, "fff4d6", "SmoothPlastic", collide=False)
    m.ball("LampFinial", (x, st + 0.14, z), 0.18, BRASS, "Metal", collide=False)
    m.cyl("PullCord", (x - 0.34, sb - 0.02, z - 0.2), (x - 0.34, sb - 0.42, z - 0.2), 0.05, BRASS, "Metal", collide=False)
    m.ball("PullBead", (x - 0.34, sb - 0.46, z - 0.2), 0.12, BRASS, "Metal", collide=False)
    m.pivot("Lamp", (x, (sb + st) / 2, z))

    # ------------------------------------------------ twin-bell alarm clock (hands point at 12; the client sets the time)
    cx, cz = CLOCK_X, CLOCK_Z
    cy = TOP + 0.08 + 0.36
    for k, s in enumerate((1, -1)):
        m.ball("ClockFoot%d" % (k + 1), (cx + s * 0.2, TOP + 0.06, cz), 0.14, INK, "SmoothPlastic", collide=False)
        m.ball("ClockBell%d" % (k + 1), (cx + s * 0.27, cy + 0.29, cz + 0.02), 0.28, BRASS, "Metal", collide=False)
    m.disc("ClockBody", (cx, cy, cz), (0, 0, -1), 0.72, 0.3, BLUE, "SmoothPlastic")
    m.disc("ClockRim", (cx, cy, cz - 0.16), (0, 0, -1), 0.66, 0.05, BRASS, "Metal", collide=False)
    m.disc("ClockFace", (cx, cy, cz - 0.18), (0, 0, -1), 0.56, 0.05, CREAM, "SmoothPlastic", collide=False)
    fz = cz - 0.225
    m.block("ClockHour", (cx, cy + 0.085, fz), (0.07, 0.17, 0.05), INK, "SmoothPlastic", collide=False)
    m.block("ClockMinute", (cx, cy + 0.12, fz - 0.02), (0.05, 0.24, 0.05), INK, "SmoothPlastic", collide=False)
    m.ball("ClockPin", (cx, cy, fz - 0.04), 0.08, RED, "SmoothPlastic", collide=False)
    m.pivot("ClockCentre", (cx, cy, fz))

    m.attr("Cost", 300)
    m.attr("Notes", "Bedside cabinet (primlib parts): drawer + book shelf, table lamp (prompt 'Lamp on/off': PointLight in "
                    "LampShade, ShadeInner* go Neon) and an alarm clock whose hands follow Lighting.ClockTime. "
                    "Built by fun-builds/models/build_Nightstand.py.")
    return m.finish()
