"""SinkCounter (Home, fun-builds 2026-09-24, package HomeKitchenB): an 8 x 3.6 x 3 kitchen counter. Wooden cabinets
on a black toe kick (four panelled doors with chrome pulls, two drawers and a false front over the sink), a
cream marble worktop, a pale-blue tiled backsplash with a marble cap, a deep stainless sink in the middle
with a chrome gooseneck faucet and red / blue tap handles, a green dish-soap bottle and a sponge beside it,
a red retro pop-up toaster with two slices of bread on the viewer's right and a blue fruit bowl on the left.

Behaviour contract (behaviours/server|client/SinkCounter.lua):
  Toast*           the two bread slices (Toast1, Toast1Crust, Toast2, Toast2Crust): they pop UP 0.8 stud
  PopLever         the toaster's lever (slides down 0.3 while toasting); PopSlot1/2 = the dark slots
  Pop*             the rest of the toaster housing (never moves; NOT prefixed "Toast" on purpose)
  Pivot_Spout      the faucet nozzle's lower tip: the water stream starts here
  Pivot_SinkFloor  the sink floor straight under the spout: the stream ends + splashes here
  Pivot_PoolA/B    opposite corners of the basin floor (the rising pool of water fills this box)
  Pivot_Tap        where the "Tap on/off" prompt sits (in front of the faucet)
  Pivot_Toaster    where the "Make toast" prompt sits (over the toaster)
"""
import math

WOOD = "8a5a2b"
WOOD_DARK = "6b4423"
PANEL = "9c6a38"
BLACK = "23262c"
MARBLE = "ece8df"
TILE = "a9d3ea"
STEEL = "b9c3cd"
STEEL_DARK = "8d98a5"
CHROME = "9aa7b8"
RED = "d9443c"
BLUE = "3f79d4"
GREEN = "5aa845"
WHITE = "f2f0ea"
YELLOW = "f2c13d"
ORANGE = "f08a30"
BREAD = "f0d9a0"
CRUST = "c98a45"

TOP = 3.6
CT = 0.18                     # worktop thickness
CARCASS_TOP = 2.78            # the carcass block stops under the sink; fillers wrap the basin above it
FRONT = -1.3                  # carcass front face
DOOR_T = 0.12
DOOR_FACE = FRONT - DOOR_T + 0.01
HOLE = (1.4, -1.0, 0.55)      # sink opening: x in +/-1.4, z from -1.0 to 0.55
BASIN_FLOOR = 2.92
TOASTER = (-2.75, 0.3)        # toaster centre (x, z) on the worktop
TOASTER_K = 1.15              # toaster size factor (1 = a 1.3 x 0.82 x 1.1 toaster)


def build(D, P):
    m = P.Model(D, "SinkCounter", category="Home")
    hx, hz0, hz1 = HOLE
    ctop = TOP - CT

    # ------------------------------------------------------------ carcass
    m.block("ToeKick", (0, 0.21, 0.2), (7.8, 0.42, 2.5), BLACK, "SmoothPlastic")
    m.block("Carcass", (0, (0.4 + CARCASS_TOP) / 2, 0.075), (7.9, CARCASS_TOP - 0.4, 2.75), WOOD_DARK, "Wood")
    fill_h = ctop + 0.01 - (CARCASS_TOP - 0.01)
    fy = (ctop + 0.01 + CARCASS_TOP - 0.01) / 2
    m.block("FillL", (2.7, fy, 0.075), (2.5, fill_h, 2.75), WOOD_DARK, "Wood")
    m.block("FillR", (-2.7, fy, 0.075), (2.5, fill_h, 2.75), WOOD_DARK, "Wood")
    m.block("FillF", (0, fy, (FRONT + hz0) / 2), (2.9, fill_h, hz0 - FRONT), WOOD_DARK, "Wood")
    m.block("FillB", (0, fy, (hz1 + 1.45) / 2), (2.9, fill_h, 1.45 - hz1), WOOD_DARK, "Wood")

    # ------------------------------------------------------------ worktop around the sink hole
    cy = TOP - CT / 2
    m.block("TopFront", (0, cy, (-1.55 + hz0) / 2), (8.2, CT, hz0 + 1.55), MARBLE, "Marble")
    m.block("TopBack", (0, cy, (hz1 + 1.55) / 2), (8.2, CT, 1.55 - hz1), MARBLE, "Marble")
    side_w = 4.1 - hx
    m.block("TopL", (hx + side_w / 2, cy, (hz0 + hz1) / 2), (side_w, CT, hz1 - hz0), MARBLE, "Marble")
    m.block("TopR", (-hx - side_w / 2, cy, (hz0 + hz1) / 2), (side_w, CT, hz1 - hz0), MARBLE, "Marble")

    m.block("BackPanel", (0, 1.6, 1.46), (7.6, 2.3, 0.05), WOOD, "Wood", collide=False)

    # ------------------------------------------------------------ backsplash
    m.block("Backsplash", (0, TOP + 0.5, 1.45), (8.2, 1.02, 0.2), TILE, "CeramicTiles")
    m.block("BacksplashCap", (0, TOP + 1.03, 1.44), (8.24, 0.1, 0.26), MARBLE, "Marble")

    # ------------------------------------------------------------ stainless basin (its walls poke 0.03 over the top = the rim)
    wall_h = TOP + 0.03 - (BASIN_FLOOR - 0.06)
    wy = (TOP + 0.03 + BASIN_FLOOR - 0.06) / 2
    m.block("BasinWallF", (0, wy, hz0 + 0.05), (2 * hx, wall_h, 0.1), STEEL, "Metal")
    m.block("BasinWallB", (0, wy, hz1 - 0.05), (2 * hx, wall_h, 0.1), STEEL, "Metal")
    m.block("BasinWallL", (hx - 0.05, wy, (hz0 + hz1) / 2), (0.1, wall_h, hz1 - hz0 - 0.18), STEEL, "Metal")
    m.block("BasinWallR", (-hx + 0.05, wy, (hz0 + hz1) / 2), (0.1, wall_h, hz1 - hz0 - 0.18), STEEL, "Metal")
    m.block("BasinFloor", (0, BASIN_FLOOR - 0.06, (hz0 + hz1) / 2), (2 * hx - 0.18, 0.12, hz1 - hz0 - 0.18),
            STEEL_DARK, "Metal")
    spout_z = -0.1
    m.disc("Drain", (0, BASIN_FLOOR + 0.005, spout_z), (0, 1, 0), 0.34, 0.052, BLACK, "Metal", collide=False)

    # ------------------------------------------------------------ gooseneck faucet
    fz = 0.9
    m.disc("FaucetBase", (0, TOP + 0.05, fz), (0, 1, 0), 0.5, 0.12, CHROME, "Metal", collide=False)
    m.cyl("FaucetRiser", (0, TOP + 0.05, fz), (0, 4.5, fz), 0.25, CHROME, "Metal", collide=False)
    arc_c, arc_r = (4.5, (fz + spout_z) / 2), (fz - spout_z) / 2
    pts = []
    for deg in (0, 60, 120, 180):
        t = math.radians(deg)
        pts.append((0, arc_c[0] + arc_r * math.sin(t), arc_c[1] + arc_r * math.cos(t)))
    for i in range(3):
        m.cyl("FaucetNeck%d" % (i + 1), pts[i], pts[i + 1], 0.22, CHROME, "Metal", collide=False)
    for i in (1, 2):
        m.ball("FaucetJoint%d" % i, pts[i], 0.22, CHROME, "Metal", collide=False)
    m.cyl("FaucetSpout", (0, 4.52, spout_z), (0, 4.3, spout_z), 0.27, CHROME, "Metal", collide=False)
    for side, sx, cap in (("Hot", 1, RED), ("Cold", -1, BLUE)):
        m.cyl("Handle" + side, (sx * 0.46, TOP - 0.01, fz), (sx * 0.46, TOP + 0.26, fz), 0.14, CHROME, "Metal",
              collide=False)
        m.ellipsoid("Handle" + side + "Cap", (sx * 0.46, TOP + 0.3, fz), (0.3, 0.16, 0.3), cap, "SmoothPlastic",
                    collide=False)

    # ------------------------------------------------------------ dish soap + sponge
    sx0 = 0.9
    m.cyl("SoapBottle", (sx0, TOP - 0.01, fz), (sx0, TOP + 0.52, fz), 0.3, GREEN, "SmoothPlastic", collide=False)
    m.cyl("SoapCap", (sx0, TOP + 0.51, fz), (sx0, TOP + 0.62, fz), 0.15, WHITE, "SmoothPlastic", collide=False)
    m.block("SoapNozzle", (sx0, TOP + 0.59, fz - 0.1), (0.05, 0.05, 0.14), WHITE, "SmoothPlastic", collide=False,
            shadow=False)
    m.block("SoapLabel", (sx0, TOP + 0.25, fz - 0.135), (0.18, 0.22, 0.05), WHITE, "SmoothPlastic", collide=False,
            shadow=False)
    m.block("Sponge", (1.95, TOP + 0.07, -0.45), (0.52, 0.16, 0.32), YELLOW, "SmoothPlastic", collide=False,
            rot=(0, 14, 0))
    m.block("SpongeScrub", (1.95, TOP + 0.17, -0.45), (0.52, 0.06, 0.32), GREEN, "Fabric", collide=False,
            rot=(0, 14, 0))

    # ------------------------------------------------------------ fruit bowl (viewer's left end)
    bx, bz = 2.95, 0.35
    m.cyl("BowlBase", (bx, TOP - 0.01, bz), (bx, TOP + 0.06, bz), 0.5, BLUE, "SmoothPlastic", collide=False)
    m.cyl("Bowl", (bx, TOP + 0.05, bz), (bx, TOP + 0.34, bz), 1.1, BLUE, "SmoothPlastic", collide=False)
    m.disc("BowlInside", (bx, TOP + 0.33, bz), (0, 1, 0), 0.94, 0.052, "2f5fae", "SmoothPlastic", collide=False)
    m.ball("FruitApple1", (bx + 0.2, TOP + 0.5, bz + 0.12), 0.38, RED, "SmoothPlastic", collide=False)
    m.ball("FruitApple2", (bx - 0.22, TOP + 0.5, bz + 0.16), 0.36, "c7372f", "SmoothPlastic", collide=False)
    m.ball("FruitOrange", (bx, TOP + 0.5, bz - 0.2), 0.38, ORANGE, "SmoothPlastic", collide=False)
    m.ellipsoid("FruitBanana", (bx + 0.02, TOP + 0.72, bz + 0.05), (0.8, 0.16, 0.22), YELLOW, "SmoothPlastic",
                collide=False, rot=(0, 25, 12))

    # ------------------------------------------------------------ red retro toaster (viewer's right) + bread
    tx, tz = TOASTER
    k = TOASTER_K
    body_h, depth, length = 0.6 * k, 0.82 * k, 1.3 * k
    R = depth / 2                                   # the rounded top: a cylinder along X
    m.block("PopBase", (tx, TOP + 0.06, tz), (length + 0.06, 0.14, depth + 0.06), CHROME, "Metal", collide=False)
    m.block("PopBody", (tx, TOP + 0.1 + body_h / 2, tz), (length, body_h, depth), RED, "SmoothPlastic")
    dome_y = TOP + 0.1 + body_h
    m.cylx("PopDome", (tx, dome_y, tz), length - 0.01, depth, RED, "SmoothPlastic", collide=False)
    m.block("PopStripe", (tx, TOP + 0.1 + 0.35 * k, tz), (length + 0.02, 0.07, depth + 0.02), CHROME, "Metal",
            collide=False, shadow=False)
    off = 0.16 * k                                  # slot / slice offset from the centre line
    a = math.degrees(math.asin(off / R))
    for i, sz in ((1, 1), (2, -1)):
        r = R - 0.005
        ang = math.radians(a)
        m.block("PopSlot%d" % i, (tx, dome_y + r * math.cos(ang), tz + sz * r * math.sin(ang)),
                (1.0 * k, 0.08, 0.15 * k), BLACK, "SmoothPlastic", collide=False, shadow=False, rot=(sz * a, 0, 0))
    end_x = tx - length / 2
    lever_slot_y = TOP + 0.1 + 0.32 * k
    m.block("PopLeverSlot", (end_x - 0.01, lever_slot_y, tz), (0.05, 0.5 * k, 0.1), BLACK, "SmoothPlastic",
            collide=False, shadow=False)
    m.block("PopLever", (end_x - 0.13, lever_slot_y + 0.25 * k - 0.06, tz), (0.26, 0.1, 0.24), BLACK,
            "SmoothPlastic", collide=False)
    m.disc("PopDial", (tx - 0.42 * k, TOP + 0.1 + 0.15 * k, tz - R - 0.02), (0, 0, 1), 0.2 * k, 0.06, WHITE,
           "SmoothPlastic", collide=False, shadow=False)
    # bread at rest: the crust peeks ~0.15 over the slots; the slice runs deep into the body so a +0.8 pop keeps it seated
    slot_top = dome_y + R + 0.035
    for i, sz in ((1, 1), (2, -1)):
        z = tz + sz * off
        crust_h = 0.28 * k
        c = slot_top + 0.15 - crust_h / 2 - 0.5
        m.block("Toast%d" % i, (tx, c, z), (0.84 * k, 1.0, 0.1 * k), BREAD, "SmoothPlastic", collide=False)
        m.ellipsoid("Toast%dCrust" % i, (tx, c + 0.5, z), (0.9 * k, crust_h, 0.11 * k), CRUST, "SmoothPlastic",
                    collide=False)

    # ------------------------------------------------------------ doors (4 bays of 2) + drawers
    bays = [(2.97, 1.86, -1), (1.0, 1.92, -1), (-1.0, 1.92, 1), (-2.97, 1.86, 1)]  # centre x, width, handle side (+1 = toward +X)
    door_y0, door_y1 = 0.5, 2.62
    dcy, dh = (door_y0 + door_y1) / 2, door_y1 - door_y0
    dz = FRONT - DOOR_T / 2 + 0.01
    for n, (x, w, hs) in enumerate(bays, start=1):
        m.block("Door%d" % n, (x, dcy, dz), (w, dh, DOOR_T), WOOD, "Wood")
        m.block("DoorPanel%d" % n, (x, dcy - 0.02, DOOR_FACE - 0.015), (w - 0.42, dh - 0.46, 0.05), PANEL, "Wood",
                collide=False)
        hx_ = x + hs * (w / 2 - 0.12)
        m.cyl("DoorPull%d" % n, (hx_, 1.95, DOOR_FACE - 0.04), (hx_, 2.45, DOOR_FACE - 0.04), 0.09, CHROME, "Metal",
              collide=False)
    drw_y0, drw_y1 = 2.7, ctop - 0.04
    wcy, wh = (drw_y0 + drw_y1) / 2, drw_y1 - drw_y0
    for n, x in ((1, 2.97), (2, -2.97)):
        m.block("Drawer%d" % n, (x, wcy, dz), (1.86, wh, DOOR_T), WOOD, "Wood")
        m.cyl("DrawerPull%d" % n, (x + 0.35, wcy, DOOR_FACE - 0.04), (x - 0.35, wcy, DOOR_FACE - 0.04), 0.09, CHROME,
              "Metal", collide=False)
    m.block("SinkFront", (0, wcy, dz), (3.92, wh, DOOR_T), WOOD, "Wood")

    # ------------------------------------------------------------ behaviour points
    m.pivot("Spout", (0, 4.3, spout_z))
    m.pivot("SinkFloor", (0, BASIN_FLOOR, spout_z))
    m.pivot("PoolA", (hx - 0.1, BASIN_FLOOR, hz0 + 0.1))
    m.pivot("PoolB", (-hx + 0.1, BASIN_FLOOR, hz1 - 0.1))
    m.pivot("Tap", (0, 4.1, 0.55))
    m.pivot("Toaster", (tx, dome_y + R + 0.45, tz - 0.25))
    m.attr("Cost", 900)
    m.attr("DisplayName", "Sink Counter")
    return m.finish()
