"""CoffeeTable (Home) -- a low wooden coffee table to go with the Sofa, fun-builds HomeLiving 2026-09-24.

~5 x 1.8 x 3 studs (top at 1.8): a round-edged top (slab + edge cylinders + corner balls), a dark apron with
a little drawer and brass knob, turned legs with brass caps, a lower shelf with a stack of books, and on top a
fruit bowl (orange, apples, banana and - of course - a cucumber), two magazines and a mug on a coaster.
No behaviour (purely decorative).
"""
import math

WOOD = "8a5a2b"
WOOD_D = "6b4423"
BRASS = "f2c13d"
CREAM = "f2f0ea"
BLUE = "3f79d4"
RED = "d9443c"
YELLOW = "f2c13d"


def _yaw(x, z, deg):
    """rotate a local (x, z) offset by a yaw of deg degrees (CFrame.Angles(0, deg, 0))"""
    a = math.radians(deg)
    return x * math.cos(a) + z * math.sin(a), -x * math.sin(a) + z * math.cos(a)


def build(D, P):
    m = P.Model(D, "CoffeeTable", category="Home")
    top_y, th = 1.8, 0.26
    cy = top_y - th / 2
    hx, hz = 2.5 - th / 2, 1.5 - th / 2

    # ------------------------------------------------ round-edged top
    m.block("Top", (0, cy, 0), (2 * hx, th, 2 * hz), WOOD, "Wood")
    for s in (1, -1):
        m.cyl("TopEdgeZ%d" % (1 if s > 0 else 2), (hx, cy, s * hz), (-hx, cy, s * hz), th, WOOD, "Wood")
        m.cyl("TopEdgeX%d" % (1 if s > 0 else 2), (s * hx, cy, hz), (s * hx, cy, -hz), th, WOOD, "Wood")
    for i, (sx, sz) in enumerate(((1, 1), (-1, 1), (1, -1), (-1, -1))):
        m.ball("TopCorner%d" % (i + 1), (sx * hx, cy, sz * hz), th, WOOD, "Wood")
    # the inlay stands 0.02 proud of the top (less flickers against it in Roblox at range)
    inlay_top = top_y + 0.02
    m.block("TopInlay", (0, inlay_top - 0.025, 0), (2 * hx - 0.5, 0.05, 2 * hz - 0.5), "9c6936", "Wood", collide=False)

    # ------------------------------------------------ apron, drawer, legs, shelf
    m.block("Apron", (0, 1.4, 0), (4.3, 0.32, 2.3), WOOD_D, "Wood")
    m.block("Drawer", (0, 1.4, -1.16), (1.6, 0.22, 0.06), WOOD, "Wood", collide=False)
    m.ball("DrawerKnob", (0, 1.4, -1.22), 0.14, BRASS, "Metal", collide=False)
    for i, (sx, sz) in enumerate(((1, -1), (-1, -1), (1, 1), (-1, 1))):
        x, z = sx * 2.0, sz * 1.0
        m.cyl("LegCap%d" % (i + 1), (x, 0, z), (x, 0.14, z), 0.3, BRASS, "Metal", collide=False)
        m.cyl("Leg%d" % (i + 1), (x, 0.12, z), (x, 1.6, z), 0.36, WOOD_D, "Wood")  # top inside the slab, not flush with the apron
    m.block("Shelf", (0, 0.5, 0), (4.0, 0.12, 2.0), WOOD, "Wood")
    for i, (col, yaw, dx) in enumerate(((BLUE, 4, 0.0), (YELLOW, -7, 0.05), (RED, 10, -0.03))):
        m.block("Book%d" % (i + 1), (1.0 + dx, 0.61 + i * 0.12, -0.1), (1.1, 0.12, 0.8), col, "SmoothPlastic",
                rot=(0, yaw, 0), collide=False)

    # ------------------------------------------------ fruit bowl
    bx, bz = -1.15, 0.15
    m.cyl("BowlFoot", (bx, top_y - 0.02, bz), (bx, top_y + 0.1, bz), 0.62, CREAM, "SmoothPlastic", collide=False)
    m.cyl("Bowl", (bx, top_y + 0.08, bz), (bx, top_y + 0.38, bz), 1.36, CREAM, "SmoothPlastic", collide=False)
    m.cyl("BowlBand", (bx, top_y + 0.2, bz), (bx, top_y + 0.28, bz), 1.39, BLUE, "SmoothPlastic", collide=False)
    fy = top_y + 0.5
    m.ball("Orange", (bx + 0.32, fy, bz + 0.2), 0.5, "f08a24", "SmoothPlastic", collide=False)
    m.ball("AppleRed", (bx - 0.3, fy, bz + 0.24), 0.48, RED, "SmoothPlastic", collide=False)
    m.cyl("AppleStem", (bx - 0.3, fy + 0.22, bz + 0.24), (bx - 0.28, fy + 0.36, bz + 0.24), 0.05, "5a3a22", "Wood", collide=False)
    m.ellipsoid("AppleLeaf", (bx - 0.2, fy + 0.31, bz + 0.24), (0.2, 0.05, 0.11), "4caf50", "SmoothPlastic", rot=(0, 0, 25),
                collide=False)
    m.ball("AppleGreen", (bx + 0.05, fy, bz - 0.3), 0.46, "9ccc3c", "SmoothPlastic", collide=False)
    m.ellipsoid("Banana", (bx + 0.08, fy + 0.18, bz - 0.02), (1.0, 0.22, 0.26), "f7d44a", "SmoothPlastic", rot=(0, 28, 8),
                collide=False)
    m.ellipsoid("Cucumber", (bx - 0.08, fy + 0.26, bz + 0.02), (1.05, 0.28, 0.28), "3f8f3a", "SmoothPlastic", rot=(0, -34, -10),
                collide=False)

    # ------------------------------------------------ magazines ("Cucumber Monthly") and a mug on a coaster
    mx, mz = 1.05, 0.2
    m.block("Magazine1", (mx + 0.1, top_y + 0.02, mz + 0.05), (1.25, 0.06, 1.6), BLUE, "SmoothPlastic", rot=(0, 14, 0), collide=False)
    yaw = -8
    m.block("Magazine2", (mx, top_y + 0.08, mz), (1.25, 0.06, 1.6), RED, "SmoothPlastic", rot=(0, yaw, 0), collide=False)
    for name, (lx, lz), size, col in (("MagCover", (0, 0.12), (0.95, 0.05, 0.95), "fbe7a1"),
                                      ("MagTitle", (0, -0.58), (1.0, 0.05, 0.2), CREAM)):
        ox, oz = _yaw(lx, lz, yaw)
        m.block(name, (mx + ox, top_y + 0.105, mz + oz), size, col, "SmoothPlastic", rot=(0, yaw, 0), collide=False)
    ox, oz = _yaw(0, 0.12, yaw)
    m.ellipsoid("MagCucumber", (mx + ox, top_y + 0.13, mz + oz), (0.7, 0.06, 0.24), "3f8f3a", "SmoothPlastic", rot=(0, yaw + 30, 0),
                collide=False)

    # coaster top 0.02+ above the inlay and the magazine it overlaps; the coffee 0.02 above the mug's rim;
    # the handle's bars 0.02 inside the grip's faces
    ux, uz = 1.7, -0.85
    cy0 = top_y + 0.07
    m.cyl("Coaster", (ux, top_y - 0.02, uz), (ux, cy0, uz), 0.6, "b07a45", "Cardboard", collide=False)
    m.cyl("Mug", (ux, cy0 - 0.02, uz), (ux, cy0 + 0.42, uz), 0.38, RED, "SmoothPlastic", collide=False)
    m.cyl("MugCoffee", (ux, cy0 + 0.36, uz), (ux, cy0 + 0.44, uz), 0.3, "4a2c17", "SmoothPlastic", collide=False)
    m.block("MugHandle", (ux - 0.3, cy0 + 0.2, uz), (0.07, 0.24, 0.1), RED, "SmoothPlastic", collide=False)
    m.block("MugHandleTop", (ux - 0.24, cy0 + 0.31, uz), (0.14, 0.06, 0.06), RED, "SmoothPlastic", collide=False)
    m.block("MugHandleLow", (ux - 0.24, cy0 + 0.09, uz), (0.14, 0.06, 0.06), RED, "SmoothPlastic", collide=False)

    m.attr("Cost", 250)
    m.attr("Notes", "Low round-edged wooden coffee table with a fruit bowl, magazines and a mug (primlib parts). "
                    "Decorative, no behaviour. Built by fun-builds/models/build_CoffeeTable.py.")
    return m.finish()
