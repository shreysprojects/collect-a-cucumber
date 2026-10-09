"""Fireplace (Home, fun-builds 2026-09-24, package HomeHearth).

A chunky red-brick fireplace, ~7.6 wide (mantel) x 7 high x 3.2 deep (2.25 body + the stone hearth in front):
a stone hearth with a rounded bullnose edge, brick piers and lintel, a light stone surround with a keystone
framing a soot-black firebox (splayed sides), iron andirons holding three logs on a bed of coals, a wooden
mantel shelf on two corbels, and a narrower brick chimney breast (sloped brick shoulders into it, so the back
reads as a real chimney) with a two-tone stone crown.
On the mantel: a wooden mantel clock (arched top, brass bezel, real hands), a picture frame leaning on the
chimney breast (a little sunny landscape), a golden cucumber on a stand and three candles in brass cups. On the hearth: a companion
tool stand (poker + shovel) and a small stack of spare logs with their cut ends facing the room.

Behaviour contract (behaviours/server|client/Fireplace.lua):
  Ember*          coals under the logs + glowing seams on the logs: authored dark charcoal, the client turns
                  them Neon orange (flickering) while Fun_Lit is true
  CandleFlame1..3 candle flames: authored Transparency 1 (Neon), shown + flickered while lit
  ClockHour / ClockMinute   the mantel clock's hands, authored at 10:10 (hour 305 deg, minute 60 deg clockwise
                  as seen from the front), turned about Pivot_ClockCentre (axis = authored Z) to the game time (Lighting.ClockTime)
  PicCanvas / PicHill / PicSun   the picture (a FunAssets.Pictures decal may replace the painted scene)
  Pivot_Fire      centre of the log pile: Fire instances + ember sparks
  Pivot_Light     just in front of the firebox opening: the warm PointLight
  Pivot_Chimney   top centre of the chimney crown: smoke while lit
  Pivot_Prompt    over the hearth: the "Light fire" / "Put out" prompt
  Pivot_ClockCentre  the clock face centre (on the hands' front)
"""
import math
from mathutils import Vector

BRICK = "b4553d"
STONE = "d9d2c3"
STONE_KEY = "e8e1d2"
JOINT = "aaa294"
HEARTH = "a9a397"
SOOT = "2b2624"
ASH = "8c8580"
WOOD = "8a5a2b"
WOOD_DARK = "6b4423"
BARK = "5e3b1f"
LOG_CUT = "d8b077"
IRON = "2f3640"
BRASS = "c9a227"
EMBER_OFF = "3a2f2a"
PREVIEW_LIT = False   # review renders only (build__FireplaceLit.py): embers Neon + candle flames shown
FLAME = "ffb347"
CREAM = "f2f0ea"
RED = "d9443c"

# ------------------------------------------------------------------ key dimensions (authored studs)
FRONT = -1.0          # body front face z
BACK = 1.25           # body back face z
OPEN_X = 1.75         # firebox opening half width
OPEN_TOP = 3.25       # firebox opening top (lintel underside)
FLOOR = 0.5           # firebox floor top
SHELF_TOP = 4.375     # mantel shelf top (decorations stand here)
SHELF_FRONT = -1.6
BREAST_FRONT = -0.7


def build(D, P):
    m = P.Model(D, "Fireplace", category="Home")

    # ------------------------------------------------------------ base: plinth course + hearth
    m.block("Plinth", (0, 0.225, 0.125), (7.1, 0.45, 2.35), HEARTH, "Slate")
    # the hearth butts up to the plinth's front face (z -1.05) instead of overlapping it: two coplanar Slate tops
    # over the same strip would shimmer
    m.block("Hearth", (0, 0.225, -1.55), (6.6, 0.45, 1.0), HEARTH, "Slate")
    m.cylx("HearthEdge", (0, 0.225, -2.05), 6.6, 0.45, HEARTH, "Slate")

    # ------------------------------------------------------------ brick body around the firebox
    pier_w = 3.5 - OPEN_X
    for side, sx in (("L", 1), ("R", -1)):
        m.block("Pier" + side, (sx * (OPEN_X + pier_w / 2), 2.24, 0.125), (pier_w, 3.62, 2.25), BRICK, "Brick")
    m.block("Lintel", (0, (OPEN_TOP + 4.05) / 2, 0.125), (2 * OPEN_X + 0.1, 4.05 - OPEN_TOP, 2.25), BRICK, "Brick")
    m.block("BackSkin", (0, 1.865, 1.1), (2 * OPEN_X + 0.1, 2.87, 0.3), BRICK, "Brick")

    # ------------------------------------------------------------ firebox: soot back, splayed sides, floor, ash
    m.block("FireboxBack", (0, 1.865, 0.685), (2.6, 2.83, 0.57), SOOT, "Slate")
    for side, sx in (("L", 1), ("R", -1)):
        m.beam("FireboxSide" + side, (sx * (OPEN_X - 0.01), 1.865, FRONT + 0.02), (sx * 1.24, 1.865, 0.44),
               0.08, 2.83, SOOT, "Slate")
    m.block("FireboxFloor", (0, FLOOR - 0.03, -0.22), (3.5, 0.06, 1.5), SOOT, "Slate")
    m.block("Ash", (0, FLOOR + 0.015, -0.3), (2.9, 0.05, 1.2), ASH, "Slate", collide=False)

    # ------------------------------------------------------------ stone surround + keystone + mortar joints
    sz = FRONT - 0.07
    for side, sx in (("L", 1), ("R", -1)):
        m.block("Surround" + side, (sx * 2.04, 1.85, sz), (0.6, 2.8, 0.18), STONE, "Limestone")
    m.block("SurroundTop", (0, 3.51, sz), (4.68, 0.58, 0.18), STONE, "Limestone")
    m.block("Keystone", (0, 3.51, FRONT - 0.12), (0.56, 0.7, 0.28), STONE_KEY, "Limestone")

    # ------------------------------------------------------------ mantel: shelf, rounded edge, cove, corbels
    m.block("MantelShelf", (0, 4.2, -1.025), (7.6, 0.35, 1.15), WOOD, "Wood")
    m.cylx("MantelEdge", (0, 4.2, SHELF_FRONT), 7.6, 0.35, WOOD, "Wood")
    m.block("MantelCove", (0, 3.97, -1.27), (7.2, 0.14, 0.62), WOOD_DARK, "Wood")
    for side, sx in (("L", 1), ("R", -1)):
        m.block("Corbel" + side, (sx * 3.05, 3.62, -1.215), (0.42, 0.56, 0.49), WOOD_DARK, "Wood")
        m.wedge("CorbelFoot" + side, (sx * 3.05, 3.1, -1.215), (0.42, 0.5, 0.49), WOOD_DARK, "Wood", rot=(0, 0, 180))

    # ------------------------------------------------------------ chimney breast + crown
    m.block("Breast", (0, 5.33, 0.275), (5.4, 2.6, 1.95), BRICK, "Brick")
    for side, sx in (("L", 1), ("R", -1)):  # sloped brick shoulders from the wide body into the breast
        m.wedge("Shoulder" + side, (sx * 3.09, 4.4, 0.275), (1.95, 0.75, 0.84), BRICK, "Brick", rot=(0, -90 * sx, 0))
    m.block("Crown", (0, 6.72, 0.2), (5.8, 0.2, 2.2), STONE, "Limestone")
    m.block("CrownCap", (0, 6.9, 0.25), (5.4, 0.2, 1.9), HEARTH, "Slate")

    # ------------------------------------------------------------ fire: andirons, logs, coals / seams
    andirons(m)
    logs(m)

    # ------------------------------------------------------------ mantel decorations
    clock(m, 0.0)
    picture(m, -1.55)
    candle(m, 1, 2.95, -1.2, 0.95, RED)
    candle(m, 2, 2.35, -1.3, 0.6, CREAM)
    candle(m, 3, -2.95, -1.2, 0.95, RED)
    # a little golden cucumber on a wooden stand (between the clock and the short candle)
    m.block("CukeStand", (1.4, SHELF_TOP + 0.05, -1.2), (0.62, 0.12, 0.34), WOOD_DARK, "Wood", collide=False)
    m.ellipsoid("GoldenCuke", (1.4, SHELF_TOP + 0.23, -1.2), (0.78, 0.28, 0.28), "f2c13d", "Metal",
                rot=(0, -18, 8), collide=False)

    # ------------------------------------------------------------ hearth: tool stand + spare logs
    tools(m, -2.85, -1.55)
    spare_logs(m)

    m.pivot("Fire", (0, 0.95, -0.2))
    m.pivot("Light", (0, 1.7, -1.55))
    m.pivot("Chimney", (0, 7.0, 0.25))
    m.pivot("Prompt", (0, 1.9, -1.95))
    m.attr("Cost", 1500)
    m.attr("DisplayName", "Fireplace")
    m.attr("Notes", "Brick fireplace (primlib parts, fun-builds HomeHearth). Prompt 'Light fire' / 'Put out' toggles "
                    "Fun_Lit: Fire + sparks at Pivot_Fire, a flickering PointLight at Pivot_Light, Ember* parts glow "
                    "Neon, CandleFlame1..3 appear, chimney smoke at Pivot_Chimney. The mantel clock's ClockHour / "
                    "ClockMinute hands turn about Pivot_ClockCentre (authored 10:10) to Lighting.ClockTime. Built by "
                    "fun-builds/models/build_Fireplace.py.")
    return m.finish()


# ================================================================== pieces
def andirons(m):
    for side, sx in (("L", 1), ("R", -1)):
        x = sx * 0.95
        m.block("AndironBar" + side, (x, FLOOR + 0.08, -0.27), (0.13, 0.16, 1.32), IRON, "Metal")
        m.cyl("AndironPost" + side, (x, FLOOR - 0.01, -0.86), (x, 1.2, -0.86), 0.15, IRON, "Metal")
        m.ball("AndironKnob" + side, (x, 1.24, -0.86), 0.24, BRASS, "Metal", collide=False)


def _log(m, name, centre, length, dia, yaw, caps=(1, -1)):
    """A log along local X turned by yaw about Y, with cut-end discs on the listed ends (+1 = +X end)."""
    rot = (0, yaw, 0)
    m.cylx(name, centre, length, dia, BARK, "Wood", rot=rot)
    R = m_rot(rot)
    ax = R @ Vector((1, 0, 0))
    for s in caps:
        end = Vector(centre) + ax * (s * length / 2)
        m.disc(name + ("CapA" if s > 0 else "CapB"), tuple(end), tuple(ax), dia - 0.1, 0.06, LOG_CUT, "Wood",
               collide=False)


def m_rot(rot):
    rx, ry, rz = (math.radians(a) for a in rot)
    from mathutils import Matrix
    return Matrix.Rotation(rx, 3, 'X') @ Matrix.Rotation(ry, 3, 'Y') @ Matrix.Rotation(rz, 3, 'Z')


def EC():
    return "ff7a22" if PREVIEW_LIT else EMBER_OFF


def EM():
    return "Neon" if PREVIEW_LIT else "Slate"


def logs(m):
    grate = FLOOR + 0.16
    _log(m, "Log1", (0.05, grate + 0.25, -0.45), 2.5, 0.5, 4)
    _log(m, "Log2", (-0.05, grate + 0.27, 0.1), 2.4, 0.54, -3, caps=())
    _log(m, "Log3", (0.0, 1.31, -0.17), 2.2, 0.46, -14)
    # coal bed under / in front of the logs
    m.ball("Ember1", (0.42, FLOOR + 0.07, -0.8), 0.36, EC(), EM(), collide=False)
    m.ball("Ember2", (-0.4, FLOOR + 0.06, -0.82), 0.32, EC(), EM(), collide=False)
    m.block("Ember3", (0.02, FLOOR + 0.06, -0.86), (0.42, 0.16, 0.3), EC(), EM(), rot=(0, 25, 0), collide=False)
    m.ball("Ember4", (-0.68, FLOOR + 0.08, -0.7), 0.36, EC(), EM(), collide=False)
    m.block("Ember5", (0.72, FLOOR + 0.06, -0.66), (0.36, 0.15, 0.28), EC(), EM(), rot=(0, -20, 0), collide=False)
    # glowing seams on the logs (front-lower face of Log1, front face of Log3)
    m.block("EmberSeam1", (0.05, grate + 0.25 - 0.17, -0.45 - 0.17), (1.7, 0.07, 0.09), EC(), EM(),
            rot=(45, 4, 0), collide=False, shadow=False)
    m.block("EmberSeam2", (0.02, grate + 0.25 + 0.02, -0.45 - 0.245), (1.1, 0.07, 0.05), EC(), EM(),
            rot=(0, 4, 0), collide=False, shadow=False)
    m.block("EmberSeam3", (0.0, 1.31 - 0.08, -0.17 - 0.215), (1.2, 0.07, 0.05), EC(), EM(),
            rot=(0, -14, 0), collide=False, shadow=False)


def clock(m, x):
    z = -1.1
    base_y = SHELF_TOP
    m.block("ClockBase", (x, base_y + 0.05 - 0.01, z), (1.4, 0.1, 0.62), WOOD, "Wood", collide=False)
    m.block("ClockBody", (x, base_y + 0.09 + 0.425, z), (1.2, 0.85, 0.5), WOOD_DARK, "Wood", collide=False)
    m.disc("ClockArch", (x, base_y + 0.94, z), (0, 0, 1), 1.2, 0.5, WOOD_DARK, "Wood", collide=False)
    m.ball("ClockFinial", (x, base_y + 1.56, z), 0.16, BRASS, "Metal", collide=False)
    cy = base_y + 0.8
    front = z - 0.25
    m.disc("ClockBezel", (x, cy, front - 0.02), (0, 0, 1), 0.92, 0.08, BRASS, "Metal", collide=False)
    m.disc("ClockFace", (x, cy, front - 0.06), (0, 0, 1), 0.76, 0.06, CREAM, "SmoothPlastic", collide=False)
    face_front = front - 0.09
    # hands at 10:10; rz = clockwise angle as seen from the front
    for name, deg, length, width, zoff in (("ClockHour", 305, 0.24, 0.07, 0.005), ("ClockMinute", 60, 0.34, 0.05, 0.015)):
        a = math.radians(deg)
        d = Vector((-math.sin(a), math.cos(a), 0))
        c = Vector((x, cy, face_front - zoff)) + d * (length / 2 - 0.03)
        m.block(name, tuple(c), (width, length, 0.05), "23262c", "SmoothPlastic", rot=(0, 0, deg), collide=False,
                shadow=False)
    m.ball("ClockPin", (x, cy, face_front - 0.03), 0.09, BRASS, "Metal", collide=False, shadow=False)
    m.pivot("ClockCentre", (x, cy, face_front - 0.03))


def picture(m, x):
    tilt = 12.0
    R = m_rot((tilt, 0, 0))
    h, t = 1.1, 0.1
    c = Vector((x, SHELF_TOP + 0.534 - 0.01, BREAST_FRONT - 0.165))

    def at(lx, ly, lz):
        return tuple(c + R @ Vector((lx, ly, lz)))

    m.block("PicFrame", tuple(c), (1.35, h, t), WOOD, "Wood", rot=(tilt, 0, 0), collide=False)
    m.block("PicCanvas", at(0, 0, -0.03), (1.07, 0.82, 0.08), "9fd4e6", "SmoothPlastic", rot=(tilt, 0, 0),
            collide=False)
    m.ellipsoid("PicHill", at(0.12, -0.36, -0.07), (1.05, 0.5, 0.05), "5aa845", "SmoothPlastic", rot=(tilt, 0, 0),
                collide=False, shadow=False)
    m.disc("PicSun", at(-0.3, 0.2, -0.075), tuple(R @ Vector((0, 0, 1))), 0.24, 0.06, "f2c13d", "SmoothPlastic",
           collide=False, shadow=False)


def candle(m, i, x, z, h, color):
    top = SHELF_TOP
    m.disc("Candle%dSaucer" % i, (x, top + 0.02, z), (0, 1, 0), 0.46, 0.08, BRASS, "Metal", collide=False)
    m.cyl("Candle%dHolder" % i, (x, top + 0.05, z), (x, top + 0.2, z), 0.28, BRASS, "Metal", collide=False)
    m.cyl("Candle%d" % i, (x, top + 0.18, z), (x, top + 0.18 + h, z), 0.2, color, "SmoothPlastic", collide=False)
    wick_y = top + 0.18 + h
    m.ellipsoid("CandleFlame%d" % i, (x, wick_y + 0.14, z), (0.15, 0.3, 0.15), FLAME, "Neon",
                transparency=0 if PREVIEW_LIT else 1, collide=False, shadow=False)


def tools(m, x, z):
    base = 0.45
    m.disc("ToolBase", (x, base + 0.03, z), (0, 1, 0), 0.6, 0.08, IRON, "Metal", collide=False)
    m.cyl("ToolPole", (x, base + 0.05, z), (x, base + 2.0, z), 0.1, IRON, "Metal", collide=False)
    m.ball("ToolKnob", (x, base + 2.06, z), 0.2, BRASS, "Metal", collide=False)
    m.block("ToolBar", (x, base + 1.85, z), (0.62, 0.06, 0.06), IRON, "Metal", collide=False)
    # poker (viewer's left, +X) with a hooked tip, shovel (viewer's right)
    m.cyl("ToolPoker", (x + 0.28, base + 1.87, z), (x + 0.28, base + 0.35, z), 0.06, IRON, "Metal", collide=False)
    m.block("ToolPokerHook", (x + 0.34, base + 0.42, z), (0.14, 0.05, 0.05), IRON, "Metal", rot=(0, 0, 35),
            collide=False, shadow=False)
    m.cyl("ToolShovel", (x - 0.28, base + 1.87, z), (x - 0.28, base + 0.55, z), 0.06, IRON, "Metal", collide=False)
    m.block("ToolShovelBlade", (x - 0.28, base + 0.4, z - 0.02), (0.3, 0.32, 0.05), IRON, "Metal", rot=(8, 0, 0),
            collide=False)


def spare_logs(m):
    base = 0.45
    z0, z1 = -1.98, -1.18
    for i, (x, y, d) in enumerate(((2.52, base + 0.22, 0.44), (2.98, base + 0.21, 0.42), (2.75, base + 0.6, 0.42))):
        name = "SpareLog%d" % (i + 1)
        m.cyl(name, (x, y, z1), (x, y, z0), d, BARK, "Wood", collide=False)
        m.disc(name + "Cap", (x, y, z0), (0, 0, 1), d - 0.1, 0.06, LOG_CUT, "Wood", collide=False)
