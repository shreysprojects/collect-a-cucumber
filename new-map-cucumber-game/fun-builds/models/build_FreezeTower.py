"""FreezeTower (Defences, fun-builds 2026-09-24, package DefFreezeTower): the frost tower REBUILT as a crystalline
spire. A round snowy stone plinth (blue slate foundation, pale limestone drum, frosted-metal band with four neon
frost gems, a snow cap with drifts and icicles) carries four ice-crystal clusters and a tapered GLACIER obelisk
clamped by frosted-metal collars and lit by neon rune strips. On top a metal cradle holds the glowing core (Orb)
between four ice claws, circled by a floating rune ring, three floating ice shards and a floating crown crystal.
Footprint 7.8 x 7.8 (inside the 8 x 8 tile), 12.8 tall, 139 parts (budget 140).

RIG CONTRACT (live/DefenceService.server.lua, key "FreezeTower" - set 2 rig: origin = Hitbox + source box centre):
  Orb              the ONLY moving part: a Neon Ball (diameter 2.2) CENTRED on Pivot_OrbCentre; the server spins it
                   about the vertical axis through OrbCentre (nothing else is named Orb*)
  Pivot_OrbCentre  (0, ORB_Y, 0) - the orb centre, on the yaw axis x = z = 0
  Glow*            neon accents the DefenceFX client pulses (Transparency 0..0.35): GlowRune01-12 (floating ring),
                   GlowStrip<1-4><Low|High> (obelisk runes), GlowGem1-4 + GlowFlakeFront1-3 / GlowFlakeBack1-3
                   (plinth belt gems + snowflakes), GlowCradle (disc under the orb)
  Pivot_Mist1..4   frost-mist emitter points on the foundation ledge around the base (diagonals)
Everything else is static. Authored origin = floor centre (min y = 0), front = -Z.
"""
import math
from mathutils import Vector, Matrix

# ---------------------------------------------------------------- palette
FOUND = "5f86b5"      # blue slate foundation ring
STONE = "dfe7f1"      # pale limestone drum
BAND = "6f9ad0"       # blue frosted-metal belt round the drum
SNOW = "f7fbff"
METAL = "dde8f4"      # frosted metal (collars, band, cradle)
METAL_DK = "3f6aa0"   # blue steel trim
ICE1 = "9ed6ff"
ICE2 = "cfefff"
ICE3 = "6fc3ff"
RUNE = "8fe8ff"       # neon runes / gems
CORE = "aee6ff"       # the orb

ORB_Y = 9.9
ORB_D = 2.2

# obelisk (tapered square frustum, turned 45 degrees so an edge faces the front)
SP_Y0, SP_Y1 = 2.05, 8.2
SP_W0, SP_W1 = 2.7, 1.55
SP_YAW = 45.0


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
    return Vector((r * math.sin(a), y, r * math.cos(a)))


def frame_y(direction, twist=0.0):
    """Rotation whose local +Y points along `direction`, turned `twist` degrees about that axis."""
    y = Vector(direction).normalized()
    ref = Vector((0, 0, 1)) if abs(y.z) < 0.9 else Vector((1, 0, 0))
    x = ref.cross(y).normalized()
    z = x.cross(y).normalized()
    return Matrix((x, y, z)).transposed() @ Ry(twist)


def lean(az, deg):
    """Unit direction tilted `deg` from vertical toward azimuth az."""
    a = math.radians(az)
    t = math.radians(deg)
    return Vector((math.sin(t) * math.sin(a), math.cos(t), math.sin(t) * math.cos(a)))


# ---------------------------------------------------------------- shape helpers
def pyramid(m, name, base, R, w, h, color, material, **kw):
    """Square pyramid (4 CornerWedges) whose base is centred on `base`, apex along R's +Y."""
    base = Vector(base)
    for i, a in enumerate((0, 90, 180, 270)):
        local = Ry(a) @ Vector((-w / 4, h / 2, w / 4))
        m.corner("%s%d" % (name, i + 1), tuple(base + R @ local), (w / 2, h, w / 2), color, material,
                 rot=R @ Ry(a), **kw)


def crystal(m, name, base, direction, w, length, tip, color, material="Ice", twist=0.0, pyr=False, **kw):
    """A shard: square shaft `w` x `length` from `base` along `direction`, then a tip (`pyr`: symmetric 4-part
    pyramid, else one CornerWedge whose apex sits over a corner - a natural crystal termination)."""
    R = frame_y(direction, twist)
    base = Vector(base)
    m.block(name, tuple(base + R @ Vector((0, length / 2, 0))), (w, length, w), color, material, rot=R, **kw)
    top = base + R @ Vector((0, length, 0))
    if pyr:
        pyramid(m, name + "Tip", top, R, w, tip, color, material, **kw)
    else:
        m.corner(name + "Tip", tuple(top + R @ Vector((0, tip / 2, 0))), (w, tip, w), color, material, rot=R, **kw)
    return top + R @ Vector((0, tip, 0))


def floating_shard(m, name, centre, direction, w, body, tip, color, material="Ice", twist=0.0):
    """Double-ended floating shard: body block + a CornerWedge tip at each end."""
    R = frame_y(direction, twist)
    c = Vector(centre)
    m.block(name, tuple(c), (w, body, w), color, material, rot=R, collide=False)
    m.corner(name + "Top", tuple(c + R @ Vector((0, body / 2 + tip / 2, 0))), (w, tip, w), color, material,
             rot=R, collide=False)
    Rf = R @ Rx(180)
    m.corner(name + "Bot", tuple(c + Rf @ Vector((0, body / 2 + tip / 2, 0))), (w, tip, w), color, material,
             rot=Rf, collide=False)


def icicle(m, name, top, w, h, color=ICE2, yaw=0.0):
    """Downward CornerWedge hanging from `top` (its flat base at `top`)."""
    R = Ry(yaw) @ Rx(180)
    m.corner(name, tuple(Vector(top) + Vector((0, -h / 2, 0))), (w, h, w), color, "Ice", rot=R, collide=False)


def spire_width(y):
    return SP_W0 + (SP_W1 - SP_W0) * (y - SP_Y0) / (SP_Y1 - SP_Y0)


def frustum(m, name, color, material, edge_color=None):
    """Tapered square column: core block + 4 Wedges + 4 CornerWedge corner fills, turned SP_YAW."""
    H = SP_Y1 - SP_Y0
    d = (SP_W0 - SP_W1) / 2
    ym = (SP_Y0 + SP_Y1) / 2
    Y = Ry(SP_YAW)
    m.block(name + "Core", (0, ym, 0), (SP_W1, H, SP_W1), color, material, rot=Y)
    for i, a in enumerate((0, 90, 180, 270)):
        R = Y @ Ry(a)
        m.wedge("%sSide%d" % (name, i + 1), tuple(R @ Vector((0, ym, -(SP_W1 / 2 + d / 2)))), (SP_W1, H, d),
                color, material, rot=R)
        m.corner("%sEdge%d" % (name, i + 1), tuple(R @ Vector((SP_W1 / 2 + d / 2, ym, -SP_W1 / 2 - d / 2))),
                 (d, H, d), edge_color or color, material, rot=R @ Ry(180))


def face_strip(m, name, ya, yb, width, color, face_az):
    """A thin neon strip lying on the obelisk face whose outward normal points at azimuth face_az."""
    H = SP_Y1 - SP_Y0
    d = (SP_W0 - SP_W1) / 2
    t = 0.08

    def surf(y):
        # distance of the face from the axis at height y
        return SP_W1 / 2 + d * (1 - (y - SP_Y0) / H)

    n_local = Vector((0, d, H)).normalized()          # outward normal in a frame where the face looks along +Z'
    turn = Ry(face_az)                                  # +Z' -> azimuth face_az
    a = turn @ (Vector((0, ya, surf(ya))) + n_local * (t / 2 - 0.03))
    b = turn @ (Vector((0, yb, surf(yb))) + n_local * (t / 2 - 0.03))
    m.beam(name, tuple(a), tuple(b), width, t, color, "Neon", up=tuple(turn @ n_local), collide=False)


def square_collar(m, name, y0, h, extra, color, material="Metal", yaw=SP_YAW):
    w = spire_width(y0) + extra
    m.block(name, (0, y0 + h / 2, 0), (w, h, w), color, material, rot=Ry(yaw))
    return w


# ---------------------------------------------------------------- the build
def build(D, P):
    m = P.Model(D, "FreezeTower", category="Defences")

    # ---- plinth: slate foundation, limestone drum, frosted band + gems, snow cap
    m.cyl("BaseFoundation", (0, 0, 0), (0, 0.5, 0), 7.8, FOUND, "Slate")
    m.cyl("BaseFoundationLip", (0, 0.44, 0), (0, 0.6, 0), 7.3, METAL, "Metal")
    m.cyl("BaseDrum", (0, 0.5, 0), (0, 1.56, 0), 6.8, STONE, "Limestone")
    m.cyl("BaseBand", (0, 0.77, 0), (0, 1.37, 0), 6.95, BAND, "Metal")
    for i, az in enumerate((180, 90, 0, 270)):
        flake = az in (180, 0)                        # front + back: a neon snowflake behind the gem
        g = 0.34 if flake else 0.42
        m.block("GlowGem%d" % (i + 1), tuple(polar(3.5, az, 1.07)), (g, g, 0.18), RUNE, "Neon", rot=Ry(az) @ Rz(45),
                collide=False)
        if flake:
            for k in range(3):
                m.block("GlowFlake%s%d" % ("Front" if az == 180 else "Back", k + 1), tuple(polar(3.47, az, 1.07)),
                        (0.95, 0.13, 0.1), RUNE, "Neon", rot=Ry(az) @ Rz(60 * k), collide=False)
    m.cyl("BaseSnowCap", (0, 1.52, 0), (0, 1.8, 0), 7.3, SNOW, "Snow")
    for i, az in enumerate((20, 118, 205, 300)):
        c = polar(3.05, az, 1.8)
        m.ellipsoid("BaseSnowDrift%d" % (i + 1), tuple(c), (2.1, 0.55, 1.2), SNOW, "Snow", rot=Ry(az), collide=False)
    for i in range(8):
        az = 22.5 + 45 * i
        c = polar(3.55, az, 1.54)
        icicle(m, "BaseIcicle%d" % (i + 1), c, 0.3, 0.55 if i % 2 else 0.85, ICE2, yaw=az + 45)

    # ---- ice-crystal clusters on the snow cap (diagonals)
    for k, az in enumerate((45, 135, 225, 315)):
        base = polar(2.7, az, 1.6)
        col = (ICE3, ICE1, ICE3, ICE1)[k]
        crystal(m, "IceCluster%dA" % (k + 1), base, lean(az, 16), 0.72, 0.95, 0.75, col, "Ice", twist=az)
        crystal(m, "IceCluster%dB" % (k + 1), base + polar(0.45, az + 70, 0), lean(az + 55, 38), 0.46, 0.55, 0.5,
                ICE2, "Ice", twist=az + 20)
        crystal(m, "IceCluster%dC" % (k + 1), base + polar(0.45, az - 70, 0), lean(az - 55, 34), 0.5, 0.4, 0.55,
                ICE1 if col == ICE3 else ICE3, "Ice", twist=az - 15)

    # ---- the obelisk
    m.block("SpireFootTrim", (0, 1.85, 0), (3.6, 0.14, 3.6), METAL_DK, "Metal", rot=Ry(SP_YAW))
    m.block("SpireFoot", (0, 2.1, 0), (3.35, 0.4, 3.35), METAL, "Metal", rot=Ry(SP_YAW))
    frustum(m, "Spire", ICE3, "Glacier", edge_color=ICE2)
    w_mid = square_collar(m, "SpireBandMid", 4.7, 0.45, 0.32, METAL)
    square_collar(m, "SpireBandMidTrim", 4.62, 0.1, 0.44, METAL_DK)
    w_hi = square_collar(m, "SpireBandHigh", 6.85, 0.42, 0.3, METAL)
    square_collar(m, "SpireBandHighTrim", 6.78, 0.1, 0.42, METAL_DK)
    for i, az in enumerate((135, 225, 315, 45)):      # the four faces (after the 45 degree turn)
        face_strip(m, "GlowStrip%dLow" % (i + 1), 2.45, 4.45, 0.2, RUNE, az)
        face_strip(m, "GlowStrip%dHigh" % (i + 1), 5.4, 6.6, 0.2, RUNE, az)
    # icicles under the collar corners (the corners point front / left / back / right)
    for i, az in enumerate((180, 90, 0, 270)):
        icicle(m, "SpireBandMidIcicle%d" % (i + 1), polar(w_mid / math.sqrt(2) - 0.18, az, 4.7), 0.24, 0.6, ICE2, yaw=az)

    # ---- big crystals hugging the obelisk foot
    crystal(m, "SpireCrystal1", polar(1.75, 150, 1.6), lean(150, 20), 0.9, 1.9, 0.9, ICE3, "Glacier", twist=150)
    crystal(m, "SpireCrystal2", polar(1.8, 255, 1.6), lean(255, 26), 0.72, 1.3, 0.7, ICE2, "Glacier", twist=255)
    crystal(m, "SpireCrystal3", polar(1.75, 20, 1.6), lean(20, 22), 0.82, 1.6, 0.8, ICE3, "Glacier", twist=20)

    # ---- cradle + orb + claws
    m.block("CradleNeck", (0, 8.3, 0), (1.9, 0.3, 1.9), METAL, "Metal", rot=Ry(SP_YAW))
    m.cyl("CradlePlate", (0, 8.42, 0), (0, 8.62, 0), 3.0, METAL, "Metal")
    m.cyl("CradlePlateTrim", (0, 8.36, 0), (0, 8.45, 0), 3.15, METAL_DK, "Metal")
    m.disc("GlowCradle", (0, 8.64, 0), (0, 1, 0), 1.9, 0.06, RUNE, "Neon", collide=False)
    m.ball("Orb", (0, ORB_Y, 0), ORB_D, CORE, "Neon")
    m.pivot("OrbCentre", (0, ORB_Y, 0))
    for i, az in enumerate((45, 135, 225, 315)):
        crystal(m, "Claw%d" % (i + 1), polar(1.27, az, 8.45), lean(az, 11), 0.5, 1.95, 0.75, ICE2, "Glacier",
                twist=az + 45, pyr=True)

    # ---- floating rune ring (12 neon segments, tilted a touch toward the front)
    ring_r, ring_y, tilt = 2.3, 9.45, 10.0
    T = Rx(-tilt)
    for i in range(12):
        az = i * 30 + 15
        c = T @ polar(ring_r, az, 0) + Vector((0, ring_y, 0))
        m.block("GlowRune%02d" % (i + 1), tuple(c), (0.85, 0.16, 0.24), RUNE, "Neon", rot=T @ Ry(az), collide=False)

    # ---- floating ice shards (back, front-left, front-right) + crown crystal
    for i, az in enumerate((0, 120, 240)):
        floating_shard(m, "FloatShard%d" % (i + 1), polar(2.85, az, 10.35), lean(az, 14), 0.44, 0.8, 0.5, ICE1, "Ice",
                       twist=az + 45)
    Rc = Ry(45)
    pyramid(m, "CrownTop", (0, 12.05, 0), Rc, 0.8, 0.75, ICE2, "Glacier", collide=False)
    m.block("Crown", (0, 11.9, 0), (0.8, 0.3, 0.8), ICE2, "Glacier", rot=Rc, collide=False)
    pyramid(m, "CrownBot", (0, 11.75, 0), Rc @ Rx(180), 0.8, 0.5, ICE2, "Glacier", collide=False)

    # ---- frost mist emitter points (foundation ledge, diagonals)
    for i, az in enumerate((135, 225, 315, 45)):
        m.pivot("Mist%d" % (i + 1), tuple(polar(3.72, az, 0.62)))

    m.attr("Cost", 3000000)
    m.attr("PropSet", "defence2")
    m.attr("Notes", "FreezeTower rebuilt 2026-09-24 (fun-builds/models/build_FreezeTower.py, primlib parts): crystalline "
                    "frost spire. ONE moving part 'Orb' (Neon Ball d %.1f) centred on Pivot_OrbCentre (0, %.2f, 0); the "
                    "server spins it about the vertical axis there. Everything else is static. Glow* = neon accents the "
                    "DefenceFX client pulses; Pivot_Mist1..4 = frost-mist points on the foundation ledge." % (ORB_D, ORB_Y))
    return m.finish()
