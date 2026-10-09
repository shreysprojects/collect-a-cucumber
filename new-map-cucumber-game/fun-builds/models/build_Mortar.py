"""Mortar (Defences, fun-builds 2026-09-24, package DefMortar): the heavy mortar REBUILT as a chunky toy siege piece.
A fat BRONZE barrel (domed breech + cascabel knob, iron reinforcing bands, a trunnion collar, two lifting handles,
a flared muzzle with a hot orange bore) rides between two red trunnion cheeks with big brass bolts, bronze trunnion
caps, an elevation handwheel and a little sight. The cheeks stand on a red turret ring with a diamond-plate deck and a
ready-rack of eight brass shells (orange neon bands). The ring turns on a yellow race inside a pit of khaki sandbags
on a diamond-plate armour disc with a glowing orange rim.
Footprint 7.95 x 7.94 (round; the sandbag part boxes, inside the 8 x 8 tile), 7.92 tall to the top of the muzzle lip.

RIG CONTRACT (live/DefenceService.server.lua, key "Mortar" - set 2 rig: origin = Hitbox + source box centre):
  Base*   static (plate, glow rim, pedestal, race, sandbags)
  Mount*  yaws about the vertical axis through the origin (x = z = 0): ring, deck, cheeks, caps, wheel, sight, shells
  Tube*   the barrel: pitches about the axis parallel to X through Pivot_PitchPivot (the trunnion centre). Built at
          55 deg elevation pointing toward -Z and up: d = (0, sin 55, -cos 55).
  Pivot_PitchPivot  trunnion centre (x = 0)          Pivot_MuzzleTip  centre of the muzzle face = PitchPivot + 4.0 d
  Pivot_YawPivot    top of the static race (0, 1.3, 0) (informational)
  Glow parts keep their group prefix: BaseGlowRim, MountGlowShell1..8, TubeGlowBore.
Clearances (checked by sampling every part's true shape, all yaws): Mount + Tube stay within radius 2.96 of the yaw
axis for pitch 0..+8 (the sandbags start at r 2.96 and stay below the deck); the tube clears the deck, cheeks,
transom and shells from pitch -6 to +8 deg about the built 55 (DefenceService recoil is +6).
"""
import math
from mathutils import Vector, Matrix

# ---------------------------------------------------------------- palette
BRONZE = "c98a3e"
BRONZE_LT = "e2a650"
BRONZE_DK = "8e5b2a"
STEEL = "9aa7b8"
STEEL_DK = "3b4350"
IRON = "23262c"
RED = "d9443c"
RED_DK = "a8302b"
YELLOW = "f2c13d"
BRASS = "e8b64a"
SAND1 = "cfb77f"
SAND2 = "bda46b"
GLOW = "ff8a1f"
LENS = "8fd3ff"
WOOD = "8a5a2b"

# ---------------------------------------------------------------- rig geometry
ELEV = 55.0
_e = math.radians(ELEV)
DIR = Vector((0.0, math.sin(_e), -math.cos(_e)))    # barrel axis (toward the muzzle)
UP = Vector((0.0, math.cos(_e), math.sin(_e)))      # barrel "top" (perpendicular to DIR, in the YZ plane)
XX = Vector((1.0, 0.0, 0.0))
PIV = Vector((0.0, 3.85, 0.5))                      # trunnion centre
FACE_S = 4.0                                        # muzzle face, measured along DIR from PIV

DECK_Y = 1.85                                       # top of the turret deck (Mount)
CHEEK_X = 1.45                                      # cheek centre |x| (inner face 1.2, outer 1.7)
CHEEK_W = 0.5


def along(s, up=0.0, side=0.0):
    return PIV + DIR * s + UP * up + XX * side


def barrel_frame():
    """local X = +X (world), local Y = DIR, local Z = UP  (right-handed: X x DIR = UP)."""
    return Matrix((XX, DIR, UP)).transposed()


def frame_yz(ydir, zdir):
    y = Vector(ydir).normalized()
    z = Vector(zdir)
    z = (z - y * z.dot(y)).normalized()
    x = y.cross(z).normalized()
    return Matrix((x, y, z)).transposed()


def polar(r, az, y):
    """az 0 = +Z (back), 90 = +X (viewer's left from the front), 180 = -Z (front)."""
    a = math.radians(az)
    return Vector((r * math.sin(a), y, r * math.cos(a)))


def tube_cyl(m, name, s0, s1, dia, color, material="Metal", **kw):
    m.cyl(name, tuple(along(s0)), tuple(along(s1)), dia, color, material, **kw)


# ---------------------------------------------------------------- the build
def build(D, P):
    m = P.Model(D, "Mortar", category="Defences")

    # ================================================================ BASE (static)
    m.cyl("BasePlate", (0, 0, 0), (0, 0.42, 0), 7.8, STEEL_DK, "DiamondPlate")
    m.cyl("BaseGlowRim", (0, 0.15, 0), (0, 0.27, 0), 7.86, GLOW, "Neon", collide=False)
    m.cyl("BasePedestal", (0, 0.4, 0), (0, 1.1, 0), 4.6, STEEL, "Metal")
    m.cyl("BaseRace", (0, 1.05, 0), (0, 1.3, 0), 5.2, YELLOW, "Metal")
    # two staggered rings of sandbags hugging the turret ring
    for layer in range(2):
        y = 0.72 + layer * 0.55
        for i in range(12):
            az = i * 30 + layer * 15
            wob = ((i * 7 + layer * 3) % 5 - 2) * 0.02            # tiny deterministic size variation
            tilt = ((i * 5 + layer) % 3 - 1) * 2.5
            m.ellipsoid("BaseSandbag%d_%02d" % (layer + 1, i + 1), tuple(polar(3.4, az, y)),
                        (1.96 + wob * 2, 0.64 + wob, 0.88), SAND1 if (i + layer) % 2 == 0 else SAND2, "Fabric",
                        rot=(0, az, tilt))

    # a ramrod left lying across the back-right sandbags
    a, b = polar(3.35, -38, 1.63), polar(3.35, -80, 1.63)
    m.cyl("BaseRamrod", tuple(a), tuple(b), 0.14, WOOD, "Wood", collide=False)
    m.cyl("BaseRamrodBrush", tuple(b + (a - b).normalized() * 0.05), tuple(b + (a - b).normalized() * 0.5), 0.34, IRON, "Fabric", collide=False)

    # ================================================================ MOUNT (yaws about x = z = 0)
    m.cyl("MountRing", (0, 1.28, 0), (0, 1.72, 0), 5.8, RED, "Metal")
    m.cyl("MountRingLip", (0, 1.28, 0), (0, 1.4, 0), 5.92, RED_DK, "Metal")
    m.cyl("MountDeck", (0, 1.7, 0), (0, DECK_Y, 0), 5.2, STEEL, "DiamondPlate")
    for i, az in enumerate((180, 157, 203, 132, 228, 108, 252, 0)):
        c = polar(2.72, az, 1.72)
        m.cyl("MountRingBolt%d" % (i + 1), tuple(c), tuple(c + Vector((0, 0.09, 0))), 0.26, IRON, "Metal",
              collide=False)

    # trunnion cheeks: vertical back, sloped front, round top around the trunnion
    top_y = PIV.y
    z_back = PIV.z + 0.8
    z_top_front = PIV.z - 0.8
    z_foot_front = -1.0
    h = top_y - DECK_Y
    for side, sx in (("L", 1), ("R", -1)):
        x = sx * CHEEK_X
        m.block("MountCheek" + side, (x, DECK_Y + h / 2, (z_top_front + z_back) / 2),
                (CHEEK_W, h, z_back - z_top_front), RED, "Metal")
        m.wedge("MountCheek%sSlope" % side, (x, DECK_Y + h / 2, (z_foot_front + z_top_front) / 2 + 0.005),
                (CHEEK_W, h, z_top_front - z_foot_front + 0.01), RED, "Metal")
        m.cylx("MountCheek%sTop" % side, (x, PIV.y, PIV.z), CHEEK_W, 1.6, RED, "Metal")
        # foot flange + its bolts
        m.block("MountFoot" + side, (sx * 1.475, DECK_Y + 0.11, 0.05), (0.95, 0.22, 2.4), STEEL_DK, "Metal")
        for j, z in enumerate((-0.8, 0.95)):
            c = Vector((sx * 1.83, DECK_Y + 0.21, z))
            m.cyl("MountFootBolt%s%d" % (side, j + 1), tuple(c), tuple(c + Vector((0, 0.1, 0))), 0.24, YELLOW,
                  "Metal", collide=False)
        # big brass bolts on the outer face
        for j, (y, z) in enumerate(((2.5, -0.35), (2.5, 1.02), (3.35, 1.08))):
            m.disc("MountCheekBolt%s%d" % (side, j + 1), (sx * 1.79, y, z), (1, 0, 0), 0.36, 0.12, BRASS,
                   "Metal", collide=False)
        # darker inset panel on the outer face (depth)
        m.block("MountCheek%sPanel" % side, (sx * 1.725, 2.6, 0.35), (0.07, 0.9, 1.6), RED_DK, "Metal", collide=False)
        # bronze trunnion cap + iron nut
        m.disc("MountCap" + side, (sx * 1.8, PIV.y, PIV.z), (1, 0, 0), 1.3, 0.2, BRONZE_LT, "Metal")
        m.disc("MountNut" + side, (sx * 2.0, PIV.y, PIV.z), (1, 0, 0), 0.62, 0.22, IRON, "Metal", collide=False)
    # front cross-brace between the cheeks (under the chase, clear of the barrel)
    m.block("MountTransom", (0, DECK_Y + 0.42, -0.78), (2.44, 0.84, 0.44), RED_DK, "Metal")

    # elevation handwheel (viewer's right = -X)
    wc = Vector((-2.12, 2.78, -0.72))
    m.cyl("MountWheelShaft", (-1.68, wc.y, wc.z), (-2.1, wc.y, wc.z), 0.2, STEEL, "Metal", collide=False)
    m.disc("MountWheel", tuple(wc), (1, 0, 0), 1.2, 0.1, YELLOW, "Metal", collide=False)
    m.disc("MountWheelInner", tuple(wc), (1, 0, 0), 0.9, 0.12, IRON, "Metal", collide=False)
    m.block("MountWheelSpokeA", tuple(wc), (0.14, 0.92, 0.14), YELLOW, "Metal", collide=False)
    m.block("MountWheelSpokeB", tuple(wc), (0.14, 0.14, 0.92), YELLOW, "Metal", collide=False)
    m.disc("MountWheelHub", tuple(wc + Vector((-0.07, 0, 0))), (1, 0, 0), 0.3, 0.12, BRASS, "Metal", collide=False)
    gp = wc + Vector((0, 0.46, 0))
    m.cyl("MountWheelGrip", tuple(gp), tuple(gp + Vector((-0.32, 0, 0))), 0.16, WOOD, "Wood", collide=False)

    # sight on the +X cheek
    m.block("MountSightArm", (1.86, 3.12, -0.42), (0.34, 0.16, 0.22), STEEL_DK, "Metal", collide=False)
    m.block("MountSight", (2.1, 3.34, -0.55), (0.3, 0.34, 0.86), STEEL_DK, "Metal", collide=False)
    m.disc("MountSightLens", (2.1, 3.34, -0.99), (0, 0, 1), 0.24, 0.06, LENS, "Glass", collide=False)
    m.disc("MountSightEye", (2.1, 3.34, -0.1), (0, 0, 1), 0.3, 0.06, IRON, "Rubber", collide=False)

    # ready-rack: eight brass shells standing round the back of the ring
    for i, az in enumerate((32, 50, 68, 86, -32, -50, -68, -86)):
        c = polar(2.4, az, DECK_Y)
        m.cyl("MountShellCase%d" % (i + 1), tuple(c), tuple(c + Vector((0, 0.56, 0))), 0.48, BRASS, "Metal")
        m.ellipsoid("MountShellNose%d" % (i + 1), tuple(c + Vector((0, 0.56, 0))), (0.44, 1.02, 0.44), STEEL_DK,
                    "Metal")
        m.cyl("MountGlowShell%d" % (i + 1), tuple(c + Vector((0, 0.47, 0))), tuple(c + Vector((0, 0.59, 0))), 0.5,
              GLOW, "Neon", collide=False)

    # ================================================================ TUBE (pitches about PIV, axis // X)
    R = barrel_frame()
    m.cylx("TubeTrunnion", tuple(PIV), 3.44, 0.82, STEEL, "Metal")
    m.ball("TubeKnob", tuple(along(-1.85)), 0.62, BRONZE_DK, "Metal")
    tube_cyl(m, "TubeKnobNeck", -1.8, -1.4, 0.42, BRONZE_DK)
    m.ellipsoid("TubeBreech", tuple(along(-0.95)), (2.02, 1.5, 2.02), BRONZE, "Metal", rot=R)
    tube_cyl(m, "TubeBody", -0.95, 1.3, 2.05, BRONZE)
    tube_cyl(m, "TubeBandBreech", -0.95, -0.7, 2.22, STEEL_DK)
    tube_cyl(m, "TubeBandTrunnion", -0.42, 0.42, 2.3, STEEL_DK)
    tube_cyl(m, "TubeBandMid", 1.2, 1.45, 2.25, STEEL_DK)
    tube_cyl(m, "TubeChase", 1.3, 3.35, 1.82, BRONZE)
    tube_cyl(m, "TubeBandChase", 2.35, 2.55, 2.0, STEEL_DK)
    tube_cyl(m, "TubeAstragal", 3.25, 3.4, 2.02, BRONZE_DK)
    tube_cyl(m, "TubeFlare1", 3.38, 3.62, 2.22, BRONZE)
    tube_cyl(m, "TubeFlare2", 3.6, 3.82, 2.5, BRONZE_LT)
    tube_cyl(m, "TubeLip", 3.8, FACE_S, 2.75, BRONZE_DK)
    tube_cyl(m, "TubeBore", FACE_S - 0.04, FACE_S + 0.04, 1.62, IRON, "SmoothPlastic")
    tube_cyl(m, "TubeGlowBore", FACE_S, FACE_S + 0.06, 0.92, GLOW, "Neon", collide=False)
    # two lifting handles ("dolphins") on the barrel's top shoulder
    for side, a in (("L", 40), ("R", -40)):
        w = (UP * math.cos(math.radians(a)) + XX * math.sin(math.radians(a))).normalized()
        Rh = frame_yz(w, DIR)
        for j, s in enumerate((0.62, 1.02)):
            m.block("TubeHandle%sPost%d" % (side, j + 1), tuple(along(s) + w * 1.2), (0.16, 0.42, 0.16), IRON,
                    "Metal", rot=Rh, collide=False)
        m.block("TubeHandle%sBar" % side, tuple(along(0.82) + w * 1.43), (0.16, 0.16, 0.58), IRON, "Metal",
                rot=Rh, collide=False)

    # ================================================================ data
    m.pivot("PitchPivot", tuple(PIV))
    m.pivot("MuzzleTip", tuple(along(FACE_S)))
    m.pivot("YawPivot", (0, 1.3, 0))
    m.attr("Cost", 400000000)
    m.attr("PropSet", "defence2")
    m.attr("State_Elevation", 55)
    tip = along(FACE_S)
    m.attr("Notes", "Mortar rebuilt 2026-09-24 (fun-builds/models/build_Mortar.py, primlib parts): chunky bronze siege "
                    "mortar. Rig by name prefix: Base* static; Mount* yaws about the vertical axis through the origin "
                    "(x = z = 0); Tube* pitches about the axis parallel to X through Pivot_PitchPivot (0, %.2f, %.2f) "
                    "(trunnion centre). Built at 55 deg elevation pointing -Z and up, d = (0, sin55, -cos55); shells "
                    "leave Pivot_MuzzleTip (0, %.2f, %.2f) = PitchPivot + 4.0 d, the centre of the muzzle face. Glow "
                    "parts keep their group prefix: BaseGlowRim, MountGlowShell1..8, TubeGlowBore (orange neon). "
                    "Mount + Tube stay within r 2.96 of the yaw axis for pitch 0..+8 (sandbags start at r 2.96, "
                    "below the deck); the tube clears the carriage from -6 to +8 deg pitch about 55 (recoil is +6)."
                    % (PIV.y, PIV.z, tip.y, tip.z))
    return m.finish()
