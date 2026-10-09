"""Stove (Home, fun-builds 2026-09-24, package HomeKitchenB): a cheerful cream kitchen range, 4 wide x 3.6 to the
cooktop x 3 deep, on four chunky black feet. A black glass cooktop in a chrome frame with four electric coil
burners (two big, two small; each = chrome drip ring + outer coil + dark gap + inner coil), a back guard
(backsplash) with a black control panel carrying four white knobs on chrome skirts (red pointer ticks), a
little green digital clock and a red power light, a big oven door with a black window (a rack and a roast
silhouette inside), a chrome bar handle with a blue striped tea towel hung over it, a vent strip, a storage
drawer, a frying pan with a fried egg on the front-left burner (its handle turned toward the cook) and a red
enamel kettle on the front-right burner (spout to the viewer's right). 84 parts.

Behaviour contract (behaviours/server|client/Stove.lua):
  Burner*        the coil parts that glow red-orange Neon while the stove is on (BurnerFL, BurnerFLIn, ...);
                 CoilGap* / DripRing* never change
  OvenWindow     glows warm orange while on; OvenRack / OvenRoast are dark silhouettes in front of it
  PowerLight     the little indicator that lights red while on
  Pan* / Egg* / Kettle*   the pan, egg and kettle (never moved)
  Pivot_Controls front-centre of the control panel: where the "Turn on/off" prompt sits
  Pivot_PanTop   the pan's inside-bottom centre (sizzle + oil pops)
  Pivot_OvenWindow  front-centre of the oven window (the warm light)
  Pivot_SpoutTip the kettle's spout tip (a wisp of steam while on)
  Pivot_KettleBase the kettle's base centre (its burner gets no heat shimmer; spout direction = base -> tip)
"""
import math

CREAM = "f2f0ea"
CHROME = "9aa7b8"
STEEL = "3b4350"
BLACK = "23262c"
DEEP = "1a1c20"
COIL = "4f545e"
RED = "d9443c"
YOLK = "f2a93b"
EGG = "fbfaf5"
GLASS = "2c3038"
ROAST = "3b2a20"
CLOCK = "1d2a22"
DIGIT = "69ff00"
WHITE = "f7f6f1"

TOP = 3.6            # cooktop surface
FEET = 0.3           # body bottom
BODY_FRONT = -1.45
SPLASH_FRONT = 1.1   # back guard front face (z)
PANEL_Y = 4.3        # knob row height on the back guard
KETTLE = "d9443c"
TOWEL = "3f79d4"

# burners: name, x, z, diameter  (+X = the viewer's left)
BURNERS = [
    ("FL", 0.95, -0.62, 1.15),
    ("BL", 0.95, 0.48, 0.85),
    ("FR", -0.95, -0.62, 0.85),
    ("BR", -0.95, 0.48, 1.15),
]


def build(D, P):
    m = P.Model(D, "Stove", category="Home")

    # ------------------------------------------------------------ feet + carcass
    for i, (x, z) in enumerate([(1.62, -1.12), (-1.62, -1.12), (1.62, 1.18), (-1.62, 1.18)], start=1):
        m.cyl("Foot%d" % i, (x, 0.0, z), (x, FEET + 0.03, z), 0.42, BLACK, "Rubber")
    m.block("Body", (0, (FEET + 3.46) / 2, 0.025), (4.0, 3.46 - FEET, 2.95), CREAM, "SmoothPlastic")
    m.block("KickStrip", (0, FEET + 0.06, BODY_FRONT - 0.01), (3.9, 0.12, 0.05), BLACK, "SmoothPlastic", collide=False)
    for side, sx in (("L", 1), ("R", -1)):
        m.cyl("CornerTrim" + side, (sx * 2.0, FEET, BODY_FRONT + 0.02), (sx * 2.0, 3.45, BODY_FRONT + 0.02), 0.11,
              CHROME, "Metal", collide=False)

    # back: a service panel with two vent slots (a freestanding stove is seen from behind too)
    m.block("BackPanel", (0, 2.0, 1.51), (3.3, 2.6, 0.05), "dedbd2", "SmoothPlastic", collide=False)
    for i, y in enumerate((2.9, 2.62), start=1):
        m.block("BackVent%d" % i, (0, y, 1.53), (2.4, 0.1, 0.05), BLACK, "SmoothPlastic", collide=False,
                shadow=False)

    # ------------------------------------------------------------ cooktop
    m.block("CooktopFrame", (0, 3.48, -0.01), (4.1, 0.1, 3.04), CHROME, "Metal")
    m.block("Cooktop", (0, TOP - 0.05, -0.16), (3.92, 0.1, 2.62), BLACK, "Glass", reflectance=0.08)
    for name, x, z, d in BURNERS:
        m.disc("DripRing" + name, (x, TOP + 0.01, z), (0, 1, 0), d + 0.16, 0.052, CHROME, "Metal", collide=False)
        m.disc("Burner" + name, (x, TOP + 0.03, z), (0, 1, 0), d, 0.052, COIL, "SmoothPlastic", collide=False)
        m.disc("CoilGap" + name, (x, TOP + 0.04, z), (0, 1, 0), d * 0.66, 0.052, DEEP, "SmoothPlastic", collide=False)
        m.disc("Burner" + name + "In", (x, TOP + 0.05, z), (0, 1, 0), d * 0.42, 0.052, COIL, "SmoothPlastic",
               collide=False)
        m.disc("CoilHub" + name, (x, TOP + 0.06, z), (0, 1, 0), d * 0.14, 0.052, DEEP, "SmoothPlastic", collide=False)

    # ------------------------------------------------------------ back guard: control panel, knobs, clock, power light
    m.block("Backsplash", (0, 4.12, 1.3), (4.0, 1.26, 0.4), CREAM, "SmoothPlastic")
    m.block("BacksplashCap", (0, 4.78, 1.29), (4.1, 0.1, 0.48), CHROME, "Metal")
    m.block("ControlPanel", (0, PANEL_Y, SPLASH_FRONT - 0.02), (3.76, 0.66, 0.05), BLACK, "Glass", reflectance=0.08)
    panel_face = SPLASH_FRONT - 0.045
    for i, x in enumerate((1.58, 1.08, -1.08, -1.58), start=1):
        m.disc("KnobSkirt%d" % i, (x, PANEL_Y, panel_face - 0.02), (0, 0, 1), 0.46, 0.052, CHROME, "Metal", collide=False)
        m.disc("Knob%d" % i, (x, PANEL_Y, panel_face - 0.09), (0, 0, 1), 0.34, 0.16, WHITE, "SmoothPlastic",
               collide=False)
        m.block("KnobTick%d" % i, (x, PANEL_Y + 0.08, panel_face - 0.185), (0.05, 0.14, 0.05), RED, "SmoothPlastic",
                collide=False, shadow=False)
    m.block("ClockGlass", (0, PANEL_Y - 0.03, panel_face - 0.02), (0.86, 0.34, 0.05), CLOCK, "Glass", collide=False)
    for side, sx in (("L", 1), ("R", -1)):
        m.block("ClockDigits" + side, (sx * 0.19, PANEL_Y - 0.03, panel_face - 0.045), (0.26, 0.14, 0.05), DIGIT, "Neon",
                collide=False, shadow=False)
    m.block("ClockColon", (0, PANEL_Y - 0.03, panel_face - 0.045), (0.05, 0.12, 0.05), DIGIT, "Neon", collide=False,
            shadow=False)
    m.disc("PowerLight", (0.62, PANEL_Y + 0.21, panel_face - 0.02), (0, 0, 1), 0.13, 0.052, "5a2020", "SmoothPlastic",
           collide=False, shadow=False)

    # ------------------------------------------------------------ oven door + window + handle
    door_face = BODY_FRONT - 0.11
    m.block("OvenDoor", (0, 1.96, BODY_FRONT - 0.05), (3.6, 2.02, 0.12), CREAM, "SmoothPlastic")
    m.block("WindowFrame", (0, 2.0, door_face - 0.015), (2.74, 1.14, 0.05), BLACK, "SmoothPlastic", collide=False)
    m.block("OvenWindow", (0, 2.0, door_face - 0.03), (2.46, 0.9, 0.05), GLASS, "Glass", reflectance=0.1,
            collide=False)
    m.block("OvenRack", (0, 1.8, door_face - 0.045), (2.46, 0.05, 0.05), DEEP, "SmoothPlastic", collide=False,
            shadow=False)
    m.ellipsoid("OvenRoast", (0, 1.95, door_face - 0.055), (0.86, 0.3, 0.05), ROAST, "SmoothPlastic", collide=False,
                shadow=False)
    hz = door_face - 0.26
    m.cyl("DoorHandle", (1.5, 2.74, hz), (-1.5, 2.74, hz), 0.15, CHROME, "Metal", collide=False)
    for side, sx in (("L", 1), ("R", -1)):
        m.cyl("HandlePost" + side, (sx * 1.3, 2.74, door_face + 0.01), (sx * 1.3, 2.74, hz), 0.1, CHROME, "Metal",
              collide=False)
    m.block("VentStrip", (0, 3.2, BODY_FRONT - 0.015), (3.0, 0.12, 0.05), BLACK, "SmoothPlastic", collide=False,
            shadow=False)

    # ------------------------------------------------------------ drawer
    m.block("Drawer", (0, 0.64, BODY_FRONT - 0.045), (3.6, 0.52, 0.11), CREAM, "SmoothPlastic")
    m.cyl("DrawerHandle", (0.6, 0.72, BODY_FRONT - 0.14), (-0.6, 0.72, BODY_FRONT - 0.14), 0.09, CHROME, "Metal",
          collide=False)

    # ------------------------------------------------------------ frying pan + fried egg on the front-left burner
    _, px, pz, pd = BURNERS[0]
    pan_bottom = TOP + 0.085
    m.disc("PanBody", (px, pan_bottom + 0.12, pz), (0, 1, 0), 1.2, 0.24, STEEL, "Metal", collide=False)
    m.disc("PanInside", (px, pan_bottom + 0.225, pz), (0, 1, 0), 1.04, 0.052, "1f2227", "SmoothPlastic", collide=False)
    a = math.radians(-53)                       # the handle points toward the front-left (the cook)
    dx, dz = math.cos(a), math.sin(a)
    s0 = (px + dx * 0.55, pan_bottom + 0.16, pz + dz * 0.55)
    s1 = (px + dx * 0.88, pan_bottom + 0.2, pz + dz * 0.88)
    s2 = (px + dx * 1.42, pan_bottom + 0.28, pz + dz * 1.42)
    m.cyl("PanNeck", s0, s1, 0.1, STEEL, "Metal", collide=False)
    m.cyl("PanGrip", s1, s2, 0.17, BLACK, "SmoothPlastic", collide=False)
    m.ball("PanGripEnd", s2, 0.17, BLACK, "SmoothPlastic", collide=False)
    egg_y = pan_bottom + 0.25
    m.ellipsoid("EggWhite", (px - 0.03, egg_y + 0.015, pz + 0.03), (0.66, 0.07, 0.56), EGG, "SmoothPlastic",
                collide=False, rot=(0, 15, 0))
    m.ellipsoid("EggWhite2", (px + 0.14, egg_y + 0.013, pz - 0.14), (0.42, 0.065, 0.38), EGG, "SmoothPlastic",
                collide=False, rot=(0, -20, 0))
    m.ellipsoid("EggYolk", (px - 0.05, egg_y + 0.05, pz + 0.04), (0.27, 0.14, 0.27), YOLK, "SmoothPlastic",
                collide=False)

    # ------------------------------------------------------------ red enamel kettle on the front-right burner (spout -> viewer's right)
    _, kx, kz, _ = BURNERS[2]
    kb = TOP + 0.085
    m.cyl("KettleBody", (kx, kb - 0.01, kz), (kx, kb + 0.3, kz), 0.86, KETTLE, "SmoothPlastic", collide=False)
    m.ellipsoid("KettleDome", (kx, kb + 0.3, kz), (0.86, 0.56, 0.86), KETTLE, "SmoothPlastic", collide=False)
    m.disc("KettleLid", (kx, kb + 0.56, kz), (0, 1, 0), 0.38, 0.07, CHROME, "Metal", collide=False)
    m.ball("KettleKnob", (kx, kb + 0.64, kz), 0.16, BLACK, "SmoothPlastic", collide=False)
    spout_a = (kx - 0.3, kb + 0.2, kz)
    spout_b = (kx - 0.66, kb + 0.5, kz)
    m.cyl("KettleSpout", spout_a, spout_b, 0.14, KETTLE, "SmoothPlastic", collide=False)
    for side, sx in (("L", 1), ("R", -1)):
        m.cyl("KettlePost" + side, (kx + sx * 0.24, kb + 0.44, kz), (kx + sx * 0.3, kb + 0.8, kz), 0.07, CHROME,
              "Metal", collide=False)
    m.cyl("KettleGrip", (kx + 0.34, kb + 0.8, kz), (kx - 0.34, kb + 0.8, kz), 0.14, BLACK, "SmoothPlastic",
          collide=False)

    # ------------------------------------------------------------ tea towel over the oven handle (viewer's right)
    tx = -0.95
    m.cyl("TowelFold", (tx + 0.27, 2.76, hz), (tx - 0.27, 2.76, hz), 0.26, TOWEL, "Fabric", collide=False)
    m.block("TowelFront", (tx, 2.34, hz - 0.1), (0.54, 0.84, 0.05), TOWEL, "Fabric", collide=False)
    for i, y in enumerate((2.08, 1.98), start=1):
        m.block("TowelStripe%d" % i, (tx, y, hz - 0.11), (0.55, 0.05, 0.05), WHITE, "Fabric", collide=False,
                shadow=False)

    # ------------------------------------------------------------ behaviour points
    m.pivot("Controls", (0, PANEL_Y, panel_face - 0.2))
    m.pivot("PanTop", (px, egg_y, pz))
    m.pivot("OvenWindow", (0, 2.0, door_face - 0.05))
    m.pivot("SpoutTip", spout_b)
    m.pivot("KettleBase", (kx, kb, kz))
    m.attr("Cost", 1000)
    m.attr("DisplayName", "Stove")
    return m.finish()
