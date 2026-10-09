"""Minigun (Defences, fun-builds 2026-09-24, package DefMinigun): the top-tier defence REBUILT as a mean gold-trimmed
gatling turret. An armoured octagonal base on four diagonal outrigger feet carries a heavy two-part yaw ring (a
steel race with a hot neon seam under a gunmetal ring with a gold band and gold bolts). On it a neck + pedestal hold
the armoured gun housing: a front armour plate with gold bands and a sloped glacis brow, glowing side + top vent
grilles, a casing eject port, a scope with a red neon lens and a whip antenna on top, an electric drive motor with
cooling fins at the back and a big ammo drum on the +X side (the viewer's left from the front) whose belt of brass
cartridges loops up into the feed port. Six barrels in a rotating cluster (hub with gold bolts, a gold clamp and a
dark clamp, a muzzle block, flared tips with black bores) point -Z. Legs carry hydraulic rams. 138 parts.

RIG CONTRACT (live DefenceService Minigun branch - set-2 rig: origin = Hitbox + source box centre):
  Base*   static.
  Head*   yaws about the vertical axis through the origin (x = z = 0); every Head point stays inside radius 4.
  Spin*   the barrel cluster: rolls about the line through Pivot_BarrelAxis parallel to Z. Every Spin part is either
          a round cylinder centred on that line or one of 6 copies at 60-degree steps, so the cluster is balanced.
  Pivot_BarrelAxis  (0, AX_Y, 0)          on the barrel-cluster axis, straight above the yaw axis (exact aim)
  Pivot_MuzzleTip   (0, AX_Y, MUZZLE_Z)   on that axis at the barrels' front ends (tracers start here)
  Pivot_CasingPort  (-1.34, 3.45, 0.47)   OPTIONAL, for FX only: just outside the casing eject port on the -X side of
                    the housing, authored at rest yaw (a Head point - turn it with the head's current yaw)
  *Glow*  the hot-orange Neon accents (BaseGlowLight1-4, BaseGlowSeam, HeadGlowVent, HeadGlowTopVent) + the red
          HeadGlowAntennaTip; HeadSightLens is the red Neon scope lens. An FX client may pulse / brighten them.
Authored origin = floor centre (min y = 0), front = -Z, footprint 7.85 x 7.85 (inside 8 x 8), height 6.17.
check() (run on every build) asserts the prefixes, the 8 x 8 footprint, the radius-4 yaw sweep (Spin parts
swept through a full roll), the cluster balance, min y = 0 and the part budget.
"""
import math
from mathutils import Vector, Matrix

# ---------------------------------------------------------------- palette
ARMOUR = "434d5f"     # gunmetal armour
ARMOUR_LT = "6b7893"  # lighter steel-blue plates
DARK = "23262c"       # near-black
STEEL = "9aa7b8"      # bright steel (barrels, race, fins)
STEEL_DK = "66717f"   # tips
GOLD = "f2c13d"       # the top-tier accent
BRASS = "d9a441"      # cartridges
COPPER = "c8692e"     # bullet noses
HOT = "ff8a1a"        # neon heat glow (vents, seam, status lights)
RED = "ff2f2f"        # neon sight lens
BORE = "111317"

AX_Y = 3.875          # barrel-cluster axis height (chest height on the 6-stud avatar) = housing centre
MUZZLE_Z = -3.8       # the barrels' front ends
BARREL_R = 0.58       # barrel ring radius about the axis


# ---------------------------------------------------------------- maths helpers
def Ry(deg):
    return Matrix.Rotation(math.radians(deg), 3, 'Y')


def Rx(deg):
    return Matrix.Rotation(math.radians(deg), 3, 'X')


def Rz(deg):
    return Matrix.Rotation(math.radians(deg), 3, 'Z')


def polar(r, az, y):
    """az 0 = +Z (back), 90 = +X (viewer's left), 180 = -Z (front), 270 = -X (viewer's right)."""
    a = math.radians(az)
    return (r * math.sin(a), y, r * math.cos(a))


def ring_xy(r, ang):
    """A point on the barrel ring (angle about the Z axis, 0 = +X side), as (x, y) in the model."""
    a = math.radians(ang)
    return r * math.cos(a), AX_Y + r * math.sin(a)


def vcyl(m, name, x, z, y0, y1, d, color, material="Metal", **kw):
    """Vertical cylinder (axis Y) from y0 to y1."""
    return m.cyl(name, (x, y0, z), (x, y1, z), d, color, material, **kw)


def zcyl(m, name, x, y, z0, z1, d, color, material="Metal", **kw):
    """Cylinder along Z from z0 to z1."""
    return m.cyl(name, (x, y, z0), (x, y, z1), d, color, material, **kw)


def xcyl(m, name, y, z, x0, x1, d, color, material="Metal", **kw):
    """Cylinder along X from x0 to x1."""
    return m.cyl(name, (x0, y, z), (x1, y, z), d, color, material, **kw)


# ---------------------------------------------------------------- BASE (static)
def base(m):
    # four diagonal outrigger feet: diamond-plate pads with a gold bolt cap, sloped legs up into the base
    for i, (sx, sz) in enumerate(((1, -1), (-1, -1), (-1, 1), (1, 1)), 1):
        fx, fz = sx * 3.3, sz * 3.3
        m.block("BaseFoot%d" % i, (fx, 0.16, fz), (1.25, 0.32, 1.25), DARK, "DiamondPlate")
        vcyl(m, "BaseFootBolt%d" % i, fx, fz, 0.3, 0.44, 0.52, GOLD, collide=False)
        a, b = Vector((sx * 1.95, 0.8, sz * 1.95)), Vector((fx, 0.32, fz))
        m.beam("BaseLeg%d" % i, tuple(a), tuple(b), 0.72, 0.5, ARMOUR, "Metal")
        # hydraulic stabiliser ram riding on top of the leg
        up = Vector((0, 0.33, 0))
        m.cyl("BaseLegRam%d" % i, tuple(a + (b - a) * 0.2 + up), tuple(a + (b - a) * 0.85 + up), 0.26, STEEL, "Metal",
              collide=False)

    # the armoured core: a drum wrapped in 8 sloped armour plates (an octagon, flats facing the cardinals)
    vcyl(m, "BaseCore", 0, 0, 0.0, 1.0, 5.6, ARMOUR)
    flat = 2.92
    width = 2 * flat * math.tan(math.radians(22.5)) + 0.02
    for k in range(8):
        az = k * 45.0
        R = Ry(az) @ Rx(-10.0)
        c = polar(flat, az, 0.52)
        m.block("BaseArmor%d" % (k + 1), c, (width, 1.0, 0.3), ARMOUR_LT if k % 2 == 0 else ARMOUR, "Metal", rot=R)
        if k % 2 == 0:
            # cardinal plates carry a neon status light
            p = Vector(c) + (R @ Vector((0, 0.1, 0.17)))
            m.block("BaseGlowLight%d" % (k // 2 + 1), tuple(p), (1.2, 0.2, 0.06), HOT, "Neon", rot=R, collide=False)
    # deck + gold rim
    vcyl(m, "BaseRim", 0, 0, 0.94, 1.08, 6.02, GOLD)
    vcyl(m, "BaseDeck", 0, 0, 0.96, 1.14, 5.8, DARK, "DiamondPlate")
    # the static half of the yaw bearing + its hot neon seam
    vcyl(m, "BaseRace", 0, 0, 1.12, 1.42, 4.9, STEEL)
    vcyl(m, "BaseGlowSeam", 0, 0, 1.36, 1.52, 4.72, HOT, "Neon", collide=False)


# ---------------------------------------------------------------- HEAD (yaws)
HZ = 0.45   # the gun sits this far behind the yaw axis so the barrels can run long inside radius 4


def head(m):
    # heavy yaw ring: gunmetal ring, gold band, 8 gold bolts
    vcyl(m, "HeadRing", 0, 0, 1.42, 1.95, 4.6, ARMOUR)
    vcyl(m, "HeadRingBand", 0, 0, 1.56, 1.8, 4.72, GOLD)
    for k in range(8):
        x, _, z = polar(1.98, k * 45.0 + 22.5, 0)
        vcyl(m, "HeadRingBolt%d" % (k + 1), x, z, 1.93, 2.05, 0.3, GOLD, collide=False)
    vcyl(m, "HeadNeck", 0, 0, 1.93, 2.35, 2.7, ARMOUR_LT)
    vcyl(m, "HeadPedestal", 0, 0.5 + HZ, 2.3, 2.75, 2.0, DARK)

    # armoured gun housing (x +-1.2, y 2.7..5.05, z 0.2..2.8) + top armour with a gold centre stripe
    m.block("HeadHousing", (0, AX_Y, 1.05 + HZ), (2.4, 2.35, 2.6), ARMOUR, "Metal")
    m.block("HeadTopArmor", (0, 5.14, 1.0 + HZ), (2.6, 0.2, 2.9), ARMOUR_LT, "Metal")
    m.block("HeadTopStripe", (0, 5.26, 1.45 + HZ), (0.34, 0.06, 2.0), GOLD, "Metal", collide=False)
    # front armour plate framing the barrel collar: gold bands top + bottom, four bolts, and a sloped glacis
    # brow on top that overhangs the collar
    fz = -0.35 + HZ
    m.block("HeadFrontPlate", (0, AX_Y, fz), (2.8, 2.5, 0.26), ARMOUR_LT, "Metal")
    m.block("HeadFrontTrimTop", (0, 5.06, fz), (2.84, 0.14, 0.32), GOLD, "Metal", collide=False)
    m.block("HeadFrontTrimLow", (0, 2.66, fz), (2.84, 0.14, 0.32), GOLD, "Metal", collide=False)
    m.wedge("HeadGlacis", (0, 5.0 + 0.15, fz - 0.33), (2.8, 0.3, 1.0), ARMOUR, "Metal")
    for i, (bx, by) in enumerate(((1.08, 4.72), (-1.08, 4.72), (-1.08, 2.98), (1.08, 2.98)), 1):
        zcyl(m, "HeadFrontBolt%d" % i, bx, by, fz - 0.11, fz - 0.21, 0.24, DARK, collide=False)
    # barrel collar (does not spin) + gold lip
    zcyl(m, "HeadCollar", 0, AX_Y, fz - 0.1, fz - 0.43, 2.1, STEEL)
    zcyl(m, "HeadCollarLip", 0, AX_Y, fz - 0.37, fz - 0.49, 2.22, GOLD)

    # side vent grille (-X, the viewer's right): hot neon in a dark frame behind 4 dark slats
    vz = 1.1 + HZ
    m.block("HeadVentFrame", (-1.22, AX_Y, vz), (0.06, 1.44, 1.72), DARK, "Metal", collide=False)
    m.block("HeadGlowVent", (-1.24, AX_Y, vz), (0.08, 1.2, 1.5), HOT, "Neon", collide=False)
    for i, dy in enumerate((-0.42, -0.14, 0.14, 0.42), 1):
        m.block("HeadVentSlat%d" % i, (-1.31, AX_Y + dy, vz), (0.08, 0.12, 1.6), DARK, "Metal", collide=False)
    # casing eject port (-X side, ahead of the vent): Pivot_CasingPort sits just outside it
    m.block("HeadEjectPort", (-1.24, 3.45, 0.47), (0.1, 0.46, 0.36), DARK, "Metal", collide=False)
    m.block("HeadEjectLip", (-1.27, 3.2, 0.47), (0.12, 0.06, 0.44), GOLD, "Metal", collide=False)
    # top vent (+X half of the top armour): hot neon under 3 slats
    m.block("HeadGlowTopVent", (0.64, 5.25, 1.5 + HZ), (0.8, 0.06, 1.1), HOT, "Neon", collide=False)
    for i, z in enumerate((1.13, 1.5, 1.87), 1):
        m.block("HeadTopSlat%d" % i, (0.64, 5.31, z + HZ), (0.92, 0.08, 0.12), DARK, "Metal", collide=False)

    # scope on top (-X side of the top armour), red neon lens facing -Z
    sx, sy = -0.6, 5.8
    m.block("HeadSightMount", (sx, 5.43, 0.6 + HZ), (0.36, 0.4, 0.7), DARK, "Metal")
    zcyl(m, "HeadSightTube", sx, sy, 0.0 + HZ, 1.3 + HZ, 0.44, DARK)
    zcyl(m, "HeadSightBell", sx, sy, -0.3 + HZ, 0.02 + HZ, 0.6, DARK)
    zcyl(m, "HeadSightLens", sx, sy, -0.34 + HZ, -0.28 + HZ, 0.46, RED, "Neon", collide=False)
    zcyl(m, "HeadSightRing1", sx, sy, 0.3 + HZ, 0.44 + HZ, 0.54, GOLD, collide=False)
    zcyl(m, "HeadSightRing2", sx, sy, 0.92 + HZ, 1.06 + HZ, 0.54, GOLD, collide=False)
    zcyl(m, "HeadSightEye", sx, sy, 1.28 + HZ, 1.48 + HZ, 0.5, DARK, "Rubber", collide=False)

    # whip antenna at the back-right corner of the top armour, red neon tip
    vcyl(m, "HeadAntennaBase", -0.95, 2.55 + HZ, 5.2, 5.34, 0.32, DARK, collide=False)
    vcyl(m, "HeadAntenna", -0.95, 2.55 + HZ, 5.3, 6.02, 0.1, DARK, collide=False)
    m.ball("HeadGlowAntennaTip", (-0.95, 6.06, 2.55 + HZ), 0.22, RED, "Neon", collide=False)

    # electric drive motor at the back: dark can, steel cooling fins, gold end cap
    zcyl(m, "HeadMotor", 0, AX_Y, 2.3 + HZ, 3.05 + HZ, 1.45, DARK)
    for i, z in enumerate((2.47, 2.67, 2.87), 1):
        zcyl(m, "HeadMotorFin%d" % i, 0, AX_Y, z - 0.05 + HZ, z + 0.05 + HZ, 1.7, STEEL, collide=False)
    zcyl(m, "HeadMotorCap", 0, AX_Y, 3.03 + HZ, 3.17 + HZ, 0.95, GOLD)

    # ammo drum on the +X side (viewer's left from the front), axis along X: gold rims, steel face, gold hub
    dy, dz = 3.2, 1.3
    xcyl(m, "HeadDrum", dy, dz, 1.72, 2.95, 2.2, DARK)
    xcyl(m, "HeadDrumRimIn", dy, dz, 1.7, 1.84, 2.34, GOLD)
    xcyl(m, "HeadDrumRimOut", dy, dz, 2.82, 2.98, 2.34, GOLD)
    xcyl(m, "HeadDrumFace", dy, dz, 2.96, 3.02, 1.96, ARMOUR_LT)
    xcyl(m, "HeadDrumHub", dy, dz, 3.0, 3.12, 0.72, GOLD)
    xcyl(m, "HeadDrumBand", dy, dz, 2.26, 2.42, 2.28, ARMOUR_LT)
    m.block("HeadDrumArm", (1.45, dy, dz), (0.55, 0.6, 0.7), ARMOUR, "Metal")
    # feed port on the housing's +X side
    m.block("HeadFeedPort", (1.3, 4.55, 0.8 + HZ), (0.24, 0.6, 0.9), ARMOUR_LT, "Metal")
    # the belt: brass cartridges (along Z) with copper noses toward -Z, looping from the drum top into the port
    bc = (2.02, 4.44)
    br = 0.56
    n = 8
    for i in range(n):
        a = math.radians(180.0 * i / (n - 1))
        x, y = bc[0] + br * math.cos(a), bc[1] + br * math.sin(a)
        zcyl(m, "HeadBelt%d" % (i + 1), x, y, 0.5 + HZ, 1.15 + HZ, 0.26, BRASS, collide=False)
        m.ball("HeadBullet%d" % (i + 1), (x, y, 0.46 + HZ), 0.24, COPPER, "Metal", collide=False)


# ---------------------------------------------------------------- SPIN (the barrel cluster, rolls about the axis)
def spin(m):
    zcyl(m, "SpinHub", 0, AX_Y, -0.33, -0.8, 1.95, ARMOUR_LT)
    zcyl(m, "SpinCore", 0, AX_Y, -0.75, -3.62, 0.34, DARK)
    for k in range(6):
        x, y = ring_xy(BARREL_R, 60.0 * k + 90.0)
        zcyl(m, "SpinBarrel%d" % (k + 1), x, y, -0.75, -3.52, 0.38, STEEL)
        zcyl(m, "SpinTip%d" % (k + 1), x, y, -3.45, -3.78, 0.46, STEEL_DK)
        zcyl(m, "SpinBore%d" % (k + 1), x, y, -3.76, -3.815, 0.26, BORE, "SmoothPlastic", collide=False)
        bx, by = ring_xy(0.8, 60.0 * k + 120.0)
        zcyl(m, "SpinHubBolt%d" % (k + 1), bx, by, -0.78, -0.88, 0.18, GOLD, collide=False)
    zcyl(m, "SpinClampA", 0, AX_Y, -1.62, -1.88, 1.78, GOLD)
    zcyl(m, "SpinClampB", 0, AX_Y, -2.55, -2.75, 1.66, DARK)
    zcyl(m, "SpinMuzzle", 0, AX_Y, -3.3, -3.54, 1.72, DARK)


# ---------------------------------------------------------------- validation
def _points(p):
    """World sample points of a part (box corners; rim circles for cylinders; an ellipsoid shell for balls)."""
    s = p["size"]
    c = p["cf"]
    t = Vector(c[0:3])
    R = Matrix((c[3:6], c[6:9], c[9:12]))
    pts = []
    if p["shape"] == "Cylinder":
        for i in range(48):
            a = 2 * math.pi * i / 48
            for x in (-s[0] / 2, s[0] / 2):
                pts.append(Vector((x, s[1] / 2 * math.cos(a), s[2] / 2 * math.sin(a))))
    elif p["shape"] in ("Ball", "Ellipsoid"):
        for i in range(24):
            for j in range(1, 12):
                a, b = 2 * math.pi * i / 24, math.pi * j / 12
                pts.append(Vector((s[0] / 2 * math.sin(b) * math.cos(a), s[1] / 2 * math.cos(b), s[2] / 2 * math.sin(b) * math.sin(a))))
        pts += [Vector((0, s[1] / 2, 0)), Vector((0, -s[1] / 2, 0))]
    else:
        for x in (-1, 1):
            for y in (-1, 1):
                for z in (-1, 1):
                    pts.append(Vector((x * s[0] / 2, y * s[1] / 2, z * s[2] / 2)))
    return [t + R @ v for v in pts]


def check(info):
    bad = [p["name"] for p in info["parts"] if not p["name"].startswith(("Base", "Head", "Spin"))]
    assert not bad, "parts without a Base/Head/Spin prefix: %s" % bad
    assert info["part_count"] <= 140, "over the 140-part budget: %d" % info["part_count"]
    assert abs(info["min"][1]) < 1e-3, "min y must be 0, is %.3f" % info["min"][1]
    assert not info["duplicate_names"], info["duplicate_names"]
    foot = head_r = spin_r = 0.0
    counts = {"Base": 0, "Head": 0, "Spin": 0}
    mass = Vector((0, 0))
    mass_w = 0.0
    for p in info["parts"]:
        group = p["name"][:4]
        counts[group] += 1
        pts = _points(p)
        if group == "Base":
            foot = max(foot, max(max(abs(v.x), abs(v.z)) for v in pts))
        elif group == "Head":
            head_r = max(head_r, max(math.hypot(v.x, v.z) for v in pts))
        else:
            for v in pts:
                rho = math.hypot(v.x, v.y - AX_Y)
                spin_r = max(spin_r, math.hypot(rho, v.z))
            vol = p["size"][0] * p["size"][1] * p["size"][2]
            mass += Vector((p["cf"][0], p["cf"][1] - AX_Y)) * vol
            mass_w += vol
    off = (mass / mass_w).length
    print("CHECK parts %d (Base %d, Head %d, Spin %d) | base half-extent %.3f | head sweep r %.3f | spin sweep r %.3f | "
          "cluster imbalance %.4f | height %.2f" % (info["part_count"], counts["Base"], counts["Head"], counts["Spin"],
                                                    foot, head_r, spin_r, off, info["max"][1]))
    assert foot <= 4.0, "static base leaves the 8 x 8 tile: %.3f" % foot
    assert head_r <= 3.98, "Head sweep leaves radius 4: %.3f" % head_r
    assert spin_r <= 3.98, "Spin sweep leaves radius 4: %.3f" % spin_r
    assert off < 0.01, "barrel cluster is not balanced about the axis: %.4f" % off


NOTES = ("Rebuilt 2026-09-24 (fun-builds DefMinigun, primlib Roblox parts). Rig by name prefix: Base* static, Head* yaws "
         "about the vertical axis through the origin (x = z = 0), Spin* (6-barrel cluster) rolls about the line through "
         "Pivot_BarrelAxis parallel to Z; barrels point -Z; tracers leave Pivot_MuzzleTip. Neon: *Glow* parts (hot "
         "orange) + HeadSightLens (red). Footprint 7.85 x 7.85, Head/Spin sweep inside radius 3.9, height 6.17.")


def build(D, P):
    m = P.Model(D, "Minigun", category="Defences")
    base(m)
    head(m)
    spin(m)
    m.pivot("BarrelAxis", (0, AX_Y, 0))
    m.pivot("MuzzleTip", (0, AX_Y, MUZZLE_Z))
    m.pivot("CasingPort", (-1.34, 3.45, 0.47))   # a Head point at rest yaw (optional FX: spent casings)
    m.attr("Cost", 5000000000)
    m.attr("PropSet", "defence2")
    m.attr("Notes", NOTES)
    info = m.finish()
    check(info)
    return info
