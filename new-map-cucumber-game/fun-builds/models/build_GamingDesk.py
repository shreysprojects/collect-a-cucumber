"""GamingDesk (Home, fun-builds 2026-09-24, package HomeOffice): a battle station. A straight black gaming desk
(7.2 wide x 3.1 high x 3.4 deep) on red-striped Z-frame legs, a big curved-ish monitor (a 16:9 centre panel
and two wings turned 20 degrees toward the player, a V-foot, an RGB ring on its back), a keyboard and mouse on
a red-trimmed desk mat, two speakers, a can of cucumber soda, a glass-sided tower PC full of RGB (two front
fans, GPU, cooler, RAM) - and a racing-style gaming chair in front of it, part of the build.

Behaviour contract (behaviours/server|client/GamingDesk.lua):
  Pivot_Seat          the chair's seat top in the SITTING pose (chair facing the desk, +Z): the server's Seat
  Pivot_ChairSwivel   the swivel axis (vertical) of the chair
  Swivel*             every part that turns with the seat (everything above the gas-lift sleeve); shipped turned
                      State_ChairIdleYaw degrees (CFrame.Angles(0, rad(yaw), 0) about the swivel axis) from the
                      sitting pose State_ChairSitYaw (0). All collide=False: the client animates them.
  ChairBase/ChairLeg*/ChairWheel*/ChairSleeve   the five-star base - never moves
  ScreenC / ScreenL / ScreenR   the three screen panels (Neon, one Block each, front face toward the player);
                      the client draws its game on local parts laid over them
  ScreenArt*          the static picture (ground strips, hero, coin) on the panels - the client's screens cover it
  RGB*                Neon parts whose colour the client cycles through the rainbow
  Pivot_RGBGlow       under the desk: where the client's rainbow PointLight sits
  Pivot_Keys          the keyboard (clack sounds), Pivot_Monitor the centre screen (game sounds)
"""
import math
from mathutils import Vector

BLACK = "23262c"
CARBON = "2d3139"
GREY = "3b4350"
METAL = "9aa7b8"
RED = "d9443c"
GREEN = "5aa845"
SKY = "6fd0ff"
NEON_GREEN = "5fe05a"
RGB0 = "ff3df0"     # the RGB parts' shipped colour (the client cycles them)

TOP_Y = 3.1         # desk top surface
TOP_T = 0.16
DESK_Z0, DESK_Z1 = -0.1, 3.3
DESK_HW = 3.6
MON_Z = 2.25        # front face of the centre monitor housing
MY = 4.4            # monitor centre height
WING_A = 20.0       # wing turn (degrees)
WING_L = 0.9        # wing housing length
CHAIR = Vector((0.0, 0.0, -2.0))
IDLE_YAW = 32.0


def build(D, P):
    m = P.Model(D, "GamingDesk", category="Home")
    desk(m, P)
    monitor(m, P)
    gear(m, P)
    tower(m, P)
    chair(m, P)
    m.pivot("RGBGlow", (0.0, 2.3, 1.5))
    m.pivot("Keys", (0.0, 3.3, 0.7))
    m.pivot("Monitor", (0.0, MY, MON_Z))
    m.attr("State_ChairIdleYaw", IDLE_YAW)
    m.attr("State_ChairSitYaw", 0.0)
    m.attr("Cost", 2000)
    m.attr("DisplayName", "Gaming Desk")
    return m.finish()


# ------------------------------------------------------------------------------------------------ desk
def desk(m, P):
    zc = (DESK_Z0 + DESK_Z1) / 2
    m.block("DeskTop", (0, TOP_Y - TOP_T / 2, zc), (DESK_HW * 2, TOP_T, DESK_Z1 - DESK_Z0), BLACK, "SmoothPlastic")
    m.block("RGBDeskFront", (0, TOP_Y - TOP_T - 0.03, DESK_Z0 + 0.06), (DESK_HW * 2 - 0.3, 0.06, 0.06), RGB0, "Neon",
            collide=False, shadow=False)
    m.block("MatTrim", (0.1, TOP_Y + 0.02, 0.86), (5.5, 0.05, 1.66), RED, "Fabric", collide=False)
    m.block("Mat", (0.1, TOP_Y + 0.035, 0.86), (5.4, 0.05, 1.56), GREY, "Fabric", collide=False)
    for side, sx in (("L", 1), ("R", -1)):
        x = sx * 3.2
        m.block("DeskFoot" + side, (x, 0.11, 1.6), (0.38, 0.22, 3.3), BLACK, "Metal")
        m.beam("DeskPost" + side, (x, 0.16, 2.95), (x, TOP_Y - TOP_T - 0.05, 0.55), 0.38, 0.42, BLACK, "Metal")
        m.block("DeskRail" + side, (x, TOP_Y - TOP_T - 0.08, 1.6), (0.38, 0.16, 3.1), BLACK, "Metal")
        m.beam("DeskStripe" + side, (x + sx * 0.2, 0.3, 2.8), (x + sx * 0.2, TOP_Y - TOP_T - 0.12, 0.72), 0.05, 0.14,
               RED, "SmoothPlastic", collide=False)
    m.block("DeskBrace", (0, 1.1, 2.2), (6.02, 0.22, 0.22), BLACK, "Metal")


# ------------------------------------------------------------------------------------------------ monitor
def monitor(m, P):
    m.block("MonitorC", (0, MY, MON_Z + 0.07), (2.62, 1.54, 0.14), BLACK, "SmoothPlastic")
    m.block("ScreenC", (0, MY, MON_Z - 0.005), (2.56, 1.42, 0.05), SKY, "Neon", collide=False)
    art_z = -0.035    # ScreenArt faces sit 0.03 in front of the screens
    m.block("ScreenArtGround", (0, MY - 0.54, MON_Z + art_z), (2.56, 0.34, 0.05), NEON_GREEN, "Neon", collide=False,
            shadow=False)
    m.ellipsoid("ScreenArtHero", (0.62, MY - 0.2, MON_Z + art_z), (0.2, 0.36, 0.05), "2f8f3a", "Neon", collide=False,
                shadow=False)
    m.disc("ScreenArtCoin", (0.05, MY - 0.08, MON_Z + art_z), (0, 0, -1), 0.14, 0.055, "ffd23d", "Neon", collide=False,
           shadow=False)
    for side, sx in (("L", 1), ("R", -1)):
        R = P.angles(0, sx * WING_A, 0)
        hinge = Vector((sx * 1.31, MY, MON_Z))

        def at(local):
            return tuple(hinge + R @ Vector(local))
        m.block("Monitor" + side, at((sx * WING_L / 2, 0, 0.07)), (WING_L, 1.54, 0.14), BLACK, "SmoothPlastic",
                rot=R)
        m.block("Screen" + side, at((sx * 0.425, 0, -0.005)), (0.85, 1.42, 0.05), SKY, "Neon", rot=R, collide=False)
        m.block("ScreenArtGround" + side, at((sx * 0.425, -0.54, art_z)), (0.85, 0.34, 0.05), NEON_GREEN, "Neon",
                rot=R, collide=False, shadow=False)
    # back: a rounded housing with an RGB ring, the neck and a V-foot
    m.ellipsoid("MonitorBack", (0, MY - 0.05, MON_Z + 0.3), (2.2, 1.2, 0.42), BLACK, "SmoothPlastic")
    m.disc("RGBMonitorBack", (0, MY + 0.02, MON_Z + 0.5), (0, 0, 1), 0.84, 0.055, RGB0, "Neon", collide=False,
           shadow=False)
    m.disc("MonitorBackCap", (0, MY + 0.02, MON_Z + 0.53), (0, 0, 1), 0.6, 0.055, BLACK, "SmoothPlastic", collide=False)
    m.block("MonitorNeck", (0, (TOP_Y + MY) / 2, MON_Z + 0.42), (0.3, MY - TOP_Y, 0.16), GREY, "Metal")
    for side, sx in (("L", 1), ("R", -1)):
        m.beam("MonitorFoot" + side, (0, TOP_Y + 0.03, MON_Z + 0.42), (sx * 0.8, TOP_Y + 0.03, MON_Z - 0.28), 0.2, 0.06,
               GREY, "Metal")


# ------------------------------------------------------------------------------------------------ keyboard, mouse, speakers, soda
def gear(m, P):
    ky = TOP_Y + 0.06 + 0.05
    m.block("Keyboard", (0, ky, 0.72), (1.96, 0.1, 0.62), BLACK, "SmoothPlastic")
    for i, z in enumerate((0.57, 0.74, 0.9)):
        m.block("Keys%d" % (i + 1), (0.05 if i < 2 else 0.15, ky + 0.07, z), (1.76 if i < 2 else 1.56, 0.06, 0.13),
                GREY, "SmoothPlastic", collide=False, shadow=False)
    m.block("RGBKeyboard", (0, ky - 0.03, 0.4), (1.96, 0.05, 0.05), RGB0, "Neon", collide=False, shadow=False)
    m.ellipsoid("Mouse", (-1.4, TOP_Y + 0.14, 0.78), (0.3, 0.17, 0.44), BLACK, "SmoothPlastic", collide=False)
    m.block("RGBMouse", (-1.4, TOP_Y + 0.2, 0.9), (0.05, 0.05, 0.16), RGB0, "Neon", collide=False, shadow=False)
    for side, sx in (("L", 1), ("R", -1)):
        x = sx * 2.43
        m.block("Speaker" + side, (x, TOP_Y + 0.52, 1.82), (0.46, 1.04, 0.62), BLACK, "SmoothPlastic")
        m.disc("Woofer" + side, (x, TOP_Y + 0.36, 1.5), (0, 0, -1), 0.36, 0.06, GREY, "Metal", collide=False)
        m.disc("Tweeter" + side, (x, TOP_Y + 0.8, 1.5), (0, 0, -1), 0.17, 0.06, METAL, "Metal", collide=False)
    m.cyl("CucumberSoda", (3.15, TOP_Y - 0.01, 0.95), (3.15, TOP_Y + 0.42, 0.95), 0.26, GREEN, "Metal", collide=False)


# ------------------------------------------------------------------------------------------------ tower PC (viewer's right end)
def tower(m, P):
    x0, x1 = -3.58, -2.7      # -X side = the glass side
    z0, z1 = 0.95, 3.15
    y0, y1 = TOP_Y, TOP_Y + 2.25
    xc, zc, yc = (x0 + x1) / 2, (z0 + z1) / 2, (y0 + y1) / 2
    w, d, h = x1 - x0, z1 - z0, y1 - y0
    m.block("TowerTop", (xc, y1 - 0.05, zc), (w, 0.1, d), BLACK, "SmoothPlastic")
    m.block("TowerBottom", (xc, y0 + 0.06, zc), (w, 0.12, d), BLACK, "SmoothPlastic")
    m.block("TowerBack", (xc, yc, z1 - 0.04), (w, h, 0.08), BLACK, "SmoothPlastic")
    m.block("TowerFront", (xc, yc, z0 + 0.05), (w, h, 0.1), CARBON, "SmoothPlastic")
    m.block("TowerWall", (x1 - 0.04, yc, zc), (0.08, h, d), BLACK, "SmoothPlastic")
    m.block("TowerBoard", (x1 - 0.1, yc + 0.05, zc + 0.05), (0.05, h - 0.4, d - 0.4), "243a5e", "SmoothPlastic",
            collide=False)
    m.block("TowerGlass", (x0 + 0.03, yc, zc), (0.05, h - 0.2, d - 0.12), "9fb8d0", "Glass", transparency=0.55,
            collide=True, shadow=False)
    # inside: GPU with an RGB edge, CPU cooler ring, RAM
    m.block("TowerGpu", (xc - 0.05, yc - 0.15, zc + 0.12), (0.5, 0.24, 1.5), GREY, "Metal", collide=False)
    m.block("RGBGpu", (x0 + 0.2, yc - 0.15, zc + 0.12), (0.05, 0.07, 1.4), RGB0, "Neon", collide=False, shadow=False)
    m.disc("RGBCooler", (xc - 0.1, yc + 0.5, zc + 0.25), (-1, 0, 0), 0.62, 0.06, RGB0, "Neon", collide=False,
           shadow=False)
    m.disc("CoolerHub", (xc - 0.14, yc + 0.5, zc + 0.25), (-1, 0, 0), 0.4, 0.06, BLACK, "SmoothPlastic", collide=False)
    m.block("RGBRam", (xc - 0.05, yc + 0.5, zc - 0.45), (0.3, 0.5, 0.1), RGB0, "Neon", collide=False, shadow=False)
    # front: two RGB fan rings + a light strip
    for i, fy in enumerate((yc + 0.42, yc - 0.36)):
        m.disc("RGBFan%d" % (i + 1), (xc, fy, z0 - 0.02), (0, 0, -1), 0.66, 0.055, RGB0, "Neon", collide=False,
               shadow=False)
        m.disc("FanHub%d" % (i + 1), (xc, fy, z0 - 0.05), (0, 0, -1), 0.44, 0.055, BLACK, "SmoothPlastic",
               collide=False)
    m.block("RGBTowerStrip", (x0 + 0.06, yc, z0 - 0.02), (0.06, h - 0.3, 0.06), RGB0, "Neon", collide=False,
            shadow=False)


# ------------------------------------------------------------------------------------------------ racing chair
def chair(m, P):
    """Chair-local frame: swivel axis at the origin, the seat faces +Z (the desk). Swivel parts are shipped
    turned IDLE_YAW about the axis."""
    Ry = P.angles(0, IDLE_YAW, 0)

    def put(local, yaw=True):
        return tuple(CHAIR + ((Ry @ Vector(local)) if yaw else Vector(local)))

    def rot(r=(0, 0, 0)):
        return Ry @ P.angles(*r)

    # static five-star base
    m.cyl("ChairBase", put((0, 0.26, 0), False), put((0, 0.5, 0), False), 0.34, BLACK, "Metal")
    for k in range(5):
        a = math.radians(k * 72 + 18)
        tip = Vector((math.sin(a) * 1.0, 0.24, math.cos(a) * 1.0))
        m.beam("ChairLeg%d" % (k + 1), put((0, 0.4, 0), False), put(tuple(tip), False), 0.16, 0.12, BLACK, "Metal")
        m.ball("ChairWheel%d" % (k + 1), put((tip.x * 0.97, 0.12, tip.z * 0.97), False), 0.24, GREY, "SmoothPlastic")
    m.cyl("ChairSleeve", put((0, 0.48, 0), False), put((0, 1.2, 0), False), 0.2, BLACK, "Metal")

    # swivel: lift, mechanism, seat pan, cushion, bolsters. EVERY Swivel* part is collide=False (fix pass 2026-09-24):
    # the client swivels/spins them (anchored) through the space the gamer just left, and a collidable backrest
    # sweeping at ~490 deg/s would shove or fling the locally simulated character; it also keeps the server's
    # (parked) and the clients' (turned) collision identical. The five-star base + sleeve below stay solid.
    m.cyl("SwivelLift", put((0, 1.15, 0)), put((0, 1.62, 0)), 0.12, METAL, "Metal", collide=False)
    m.block("SwivelMech", put((0, 1.66, 0.05)), (0.8, 0.14, 0.8), BLACK, "Metal", rot=rot(), collide=False)
    m.block("SwivelPan", put((0, 1.85, 0.05)), (1.8, 0.26, 1.85), BLACK, "Leather", rot=rot(), collide=False)
    m.ellipsoid("SwivelSeat", put((0, 2.0, 0.1)), (1.3, 0.34, 1.8), BLACK, "Leather", rot=rot(), collide=False)
    for side, sx in (("L", 1), ("R", -1)):
        m.ellipsoid("SwivelBolster" + side, put((sx * 0.72, 2.05, 0.08)), (0.44, 0.44, 1.84), RED, "Leather",
                    rot=rot(), collide=False)

    # backrest (tilted back 10 degrees) with red wings, headrest + lumbar pillows and a cucumber logo on its back
    tilt = P.angles(-10, 0, 0)
    back_c = Vector((0, 3.28, -0.84))

    def on_back(local):
        return put(tuple(back_c + tilt @ Vector(local)))
    m.block("SwivelBack", on_back((0, 0, 0)), (1.5, 2.56, 0.34), BLACK, "Leather", rot=rot((-10, 0, 0)),
            collide=False)
    for side, sx in (("L", 1), ("R", -1)):
        m.block("SwivelWing" + side, on_back((sx * 0.74, -0.12, 0.08)), (0.34, 2.2, 0.5), RED, "Leather",
                rot=rot((-10, sx * -12, 0)), collide=False)
    m.ellipsoid("SwivelHeadrest", on_back((0, 0.86, 0.22)), (0.92, 0.46, 0.28), BLACK, "Leather",
                rot=rot((-10, 0, 0)), collide=False)
    m.ellipsoid("SwivelLumbar", on_back((0, -0.62, 0.22)), (1.04, 0.44, 0.28), RED, "Leather",
                rot=rot((-10, 0, 0)), collide=False)
    m.ellipsoid("SwivelLogo", on_back((0, 0.35, -0.18)), (0.34, 0.74, 0.06), GREEN, "SmoothPlastic",
                rot=rot((-10, 0, 0)), collide=False)
    # armrests
    for side, sx in (("L", 1), ("R", -1)):
        m.block("SwivelArmPost" + side, put((sx * 1.0, 2.1, 0.0)), (0.14, 0.64, 0.22), BLACK, "Metal", rot=rot(),
                collide=False)
        m.block("SwivelArmPad" + side, put((sx * 1.0, 2.46, 0.12)), (0.24, 0.1, 0.84), BLACK, "Leather", rot=rot(),
                collide=False)

    m.pivot("ChairSwivel", tuple(CHAIR))
    m.pivot("Seat", tuple(CHAIR + Vector((0, 2.12, 0.08))))
