"""TeslaCoil (Defences, fun-builds 2026-09-24, package DefTeslaCoil): the tesla coil REBUILT as an iconic tesla tower.
A heavy riveted octagonal steel plinth (hazard-striped warning plates on its four axis faces, rivets on the diagonals,
a diamond-plate deck) carries a blue transformer drum with HIGH-VOLTAGE signs front and back, a neon power band and a
bolted lid; four spark-gap insulator posts stand on the deck corners and feed copper leads into the coil. A ribbed
white/blue ceramic insulator lifts the tall secondary: copper windings (alternating d9894a / b86f35 Metal) over a
glowing core, white ceramic collars top and bottom. Above it a chrome TOROID (a 12-segment donut with a web plate and
four neon breakout nodes), an insulator neck, a copper-trimmed cradle and four dark-steel claws whose neon tips ring
the chrome ORB with ~0.45 studs of open air (so DefenceService's idle arcs show). Footprint 7.84 x 7.84 (7.6 plinth + warning plates; inside the 8 x 8 tile), 12.17 tall, 139 parts.

RIG CONTRACT (live/DefenceService.server.lua, key "TeslaCoil" - set 2 rig: origin = Hitbox + source box centre):
  Orb                   the ONLY moving part: a Metal Ball CENTRED on Pivot_OrbCentre; the server spins it about the
                        vertical axis through OrbCentre (nothing else is named Orb*)
  Pivot_OrbCentre       (0, ORB_Y, 0) - on the yaw axis x = z = 0
  Pivot_ProngTip1..4    the centres of the four neon claw tips around the orb (bolts arc OrbCentre -> tip -> zombie):
                        1 front-left (+X, -Z), 2 front-right (-X, -Z), 3 back-right (-X, +Z), 4 back-left (+X, +Z)
                        - the same order as the old model
  Pivot_Spark1..4       spark points on the toroid's outer equator (the neon breakout nodes): 1 front (-Z),
                        2 left (+X), 3 back (+Z), 4 right (-X)
  Glow*                 neon accents the DefenceFX client pulses: GlowCoil (the coil core between the windings),
                        GlowBand (drum power band), GlowNode1..4 (toroid breakout nodes), GlowTip1..4 (claw tips),
                        GlowPost1..4 (spark-gap post caps)
Everything else is static. Authored origin = floor centre (min y = 0), front = -Z.
"""
import math
from mathutils import Vector, Matrix

# ---------------------------------------------------------------- palette
STEEL_DK = "3b4350"    # plinth, claws, lid
STEEL_MID = "59636f"   # foot ring, cradle
STEEL = "9aa7b8"       # diamond-plate deck
CHROME = "d3dbe4"      # toroid
ORB_COL = "c4dcf2"     # the chrome orb, a touch of charged blue
COPPER = "d9894a"
COPPER_DK = "b86f35"
CERAMIC = "f2f0ea"
CERAMIC_BLUE = "3f79d4"
DRUM = "2f64c0"        # transformer drum (a deeper blue than the ceramic)
YELLOW = "f2c13d"
BLACK = "23262c"
NEON = "4fc8ff"        # electric cyan
NEON_HOT = "b4ecff"    # the hottest glows (claw tips, breakout nodes)

# ---------------------------------------------------------------- key heights
PLINTH_W, PLINTH_H = 7.6, 0.9
DECK_D, DECK_Y0, DECK_Y1 = 7.1, 0.84, 1.06
DRUM_D, DRUM_Y0, DRUM_Y1 = 5.0, 1.26, 2.5
LID_D, LID_Y0, LID_Y1 = 5.4, 2.46, 2.76
COIL_Y0, COIL_Y1 = 3.95, 8.35
WIND_D, CORE_D = 2.5, 2.2
TOR_Y, TOR_R, TOR_T = 9.3, 2.3, 1.1       # toroid centre height, ring radius, tube diameter
CRADLE_Y = 10.42                           # top of the cradle plate
ORB_Y, ORB_D = 11.32, 1.7
ELBOW_R, ELBOW_Y = 1.58, 10.98            # claw knuckle (copper ball)
TIP_R, TIP_Y = 1.33, 11.97                # claw tip centre = Pivot_ProngTip (1.48 from OrbCentre, 0.45 air to the orb)


# ---------------------------------------------------------------- maths helpers
def Ry(deg):
    return Matrix.Rotation(math.radians(deg), 3, 'Y')


def Rz(deg):
    return Matrix.Rotation(math.radians(deg), 3, 'Z')


def polar(r, az, y):
    """az 0 = +Z (back), 90 = +X (viewer's left), 180 = -Z (front), 270 = -X (viewer's right)."""
    a = math.radians(az)
    return Vector((r * math.sin(a), y, r * math.cos(a)))


def face(az):
    """Frame for a face whose outward normal points at azimuth az: local -Z = outward, +Y = up."""
    return Ry(az + 180)


def fblock(m, name, R, lp, size, color, material="SmoothPlastic", lrot=None, **kw):
    """Block authored in a face frame R (local -Z = outward)."""
    rot = R @ (lrot if lrot is not None else Matrix.Identity(3))
    return m.block(name, tuple(R @ Vector(lp)), size, color, material, rot=rot, **kw)


def fwedge(m, name, R, lp, size, color, material="SmoothPlastic", lrot=None, **kw):
    rot = R @ (lrot if lrot is not None else Matrix.Identity(3))
    return m.wedge(name, tuple(R @ Vector(lp)), size, color, material, rot=rot, **kw)


def vdisc(m, name, y0, y1, d, color, material="SmoothPlastic", **kw):
    """Vertical-axis cylinder from height y0 to y1 on the yaw axis."""
    return m.cyl(name, (0, y0, 0), (0, y1, 0), d, color, material, **kw)


# ---------------------------------------------------------------- pieces
def octagon(m, name, W, y0, y1, color, material):
    """Regular octagon (flats facing the axes AND the diagonals, W across the flats) from 4 overlapping blocks.
    Each block's top is raised 0.02 more than the last so no two top faces are coplanar (bottoms sit on the floor)."""
    a = W * (math.sqrt(2) - 1)
    for i, yaw in enumerate((0, 45, 90, 135)):
        d = 0.02 * i
        m.block("%s%d" % (name, i + 1), (0, (y0 + y1) / 2 + d / 2, 0), (W, y1 - y0 + d, a), color, material, rot=Ry(yaw))


def hazard_plate(m, name, az):
    """Yellow warning plate with three black 45-degree stripes on a plinth axis face."""
    R = face(az)
    zf = -(PLINTH_W / 2)
    fblock(m, name, R, (0, 0.45, zf - 0.03), (2.6, 0.56, 0.1), YELLOW, "SmoothPlastic", collide=False)
    for j, x in enumerate((-0.62, 0.0, 0.62)):
        fblock(m, "%sStripe%d" % (name, j + 1), R, (x, 0.45, zf - 0.09), (0.2, 0.58, 0.06), BLACK, "SmoothPlastic",
               lrot=Rz(45), collide=False)


def hv_sign(m, name, az):
    """HIGH-VOLTAGE sign: yellow triangle with a black lightning bolt on a dark mount, on the drum."""
    R = face(az)
    r = DRUM_D / 2
    yc = (DRUM_Y0 + DRUM_Y1) / 2 + 0.02
    fblock(m, name + "Mount", R, (0, yc, -(r - 0.08)), (1.5, 1.08, 0.3), BLACK, "Metal", collide=False)
    w, h, t = 1.28, 0.98, 0.08
    zt = -(r + 0.07 + t / 2 - 0.02)
    # two wedges back to back = an isosceles triangle (apex up) in the face plane
    fwedge(m, name + "Tri1", R, (w / 4, yc, zt), (t, h, w / 2), YELLOW, "SmoothPlastic", lrot=Ry(-90), collide=False)
    fwedge(m, name + "Tri2", R, (-w / 4, yc, zt), (t, h, w / 2), YELLOW, "SmoothPlastic", lrot=Ry(90), collide=False)
    # the bolt, a classic zig-zag seen from outside: the upper stroke runs from top-right down to the middle-left,
    # a short horizontal LINK jogs back to the right, and the lower stroke runs on down-left to the point.
    # Points are (viewer x, y above yb); the face frame's local +X is the viewer's LEFT, so local x = -viewer x.
    zb = zt - t / 2 - 0.02
    yb = yc - 0.02
    strokes = (((0.11, 0.21), (-0.07, -0.05)), ((0.07, -0.05), (-0.15, -0.39)))
    for j, (top, bot) in enumerate(strokes):
        tx, bx = -top[0], -bot[0]
        dx, dy = tx - bx, top[1] - bot[1]
        length = math.hypot(dx, dy)
        ang = math.degrees(math.atan2(-dx, dy))    # Rz(ang) turns local +Y onto (dx, dy)
        fblock(m, "%sBolt%d" % (name, j + 1), R, ((tx + bx) / 2, yb + (top[1] + bot[1]) / 2, zb),
               (0.13, length + 0.04, 0.06), BLACK, "SmoothPlastic", lrot=Rz(ang), collide=False)
    # the link sits 0.02 behind the strokes' front faces (no coplanar faces), back face buried in the triangle
    fblock(m, name + "BoltLink", R, (0.0, yb - 0.05, zb + 0.015), (0.27, 0.12, 0.05), BLACK, "SmoothPlastic",
           collide=False)


def spark_post(m, i, az):
    """Spark-gap insulator post on a deck corner: white rod, two blue sheds, a glowing cap, a copper lead to the coil."""
    base = polar(3.05, az, DECK_Y1)
    top_y = 2.42
    m.cyl("Post%dRod" % i, tuple(base + Vector((0, -0.02, 0))), tuple(Vector((base.x, top_y, base.z))), 0.34, CERAMIC)
    for j, y in enumerate((1.42, 1.86)):
        m.cyl("Post%dShed%d" % (i, j + 1), (base.x, y - 0.07, base.z), (base.x, y + 0.07, base.z), 0.78, CERAMIC_BLUE,
              collide=False)
    cap = Vector((base.x, top_y + 0.12, base.z))
    m.ball("GlowPost%d" % i, tuple(cap), 0.44, NEON, "Neon", collide=False)
    # copper lead from the cap up to the coil's base collar
    tgt = polar(1.32, az, 3.86)
    m.cyl("Post%dLead" % i, tuple(cap), tuple(tgt), 0.12, COPPER, "Metal", collide=False)


def claw(m, i, az):
    """A dark-steel claw rising from the cradle rim, bowing out and curling in, a neon tip beside the orb.
    The tip stands ~0.45 studs off the orb surface (centre TIP_R / TIP_Y, 1.48 from OrbCentre) so DefenceService's idle
    arcs (OrbCentre -> ProngTip, 0.08 thick) visibly jump the gap. The upper rod ENDS at the tip centre, so the
    neon ball (r 0.18) swallows the rod's flat end (rod r 0.13)."""
    b = polar(0.78, az, CRADLE_Y - 0.06)
    e = polar(ELBOW_R, az, ELBOW_Y)
    tip = polar(TIP_R, az, TIP_Y)
    m.cyl("Claw%dLower" % i, tuple(b), tuple(e), 0.3, STEEL_DK, "Metal")
    m.ball("Claw%dElbow" % i, tuple(e), 0.36, COPPER, "Metal")
    m.cyl("Claw%dUpper" % i, tuple(e), tuple(tip), 0.26, STEEL_DK, "Metal")
    m.ball("GlowTip%d" % i, tuple(tip), 0.36, NEON_HOT, "Neon", collide=False)
    m.pivot("ProngTip%d" % i, tuple(tip))


# ---------------------------------------------------------------- the build
def build(D, P):
    m = P.Model(D, "TeslaCoil", category="Defences")

    # ---- heavy riveted plinth + deck
    octagon(m, "BasePlinth", PLINTH_W, 0.0, PLINTH_H, STEEL_DK, "Metal")
    vdisc(m, "BaseDeck", DECK_Y0, DECK_Y1, DECK_D, STEEL, "DiamondPlate")
    for i, az in enumerate((180, 90, 0, 270)):
        hazard_plate(m, "BaseWarn%d" % (i + 1), az)
    k = 0
    for az in (135, 45, 315, 225):
        R = face(az)
        for x in (-0.95, 0.95):
            k += 1
            fblock_pos = R @ Vector((x, 0.45, -(PLINTH_W / 2) + 0.02))
            m.ball("BaseRivet%d" % k, tuple(fblock_pos), 0.26, STEEL, "Metal", collide=False)

    # ---- transformer drum, power band, lid, HV signs
    vdisc(m, "DrumFoot", DECK_Y1 - 0.04, DRUM_Y0 + 0.02, 5.5, STEEL_MID, "Metal")
    vdisc(m, "Drum", DRUM_Y0, DRUM_Y1, DRUM_D, DRUM, "SmoothPlastic")
    vdisc(m, "GlowBand", 1.44, 1.58, DRUM_D + 0.08, NEON, "Neon", collide=False)
    vdisc(m, "DrumLid", LID_Y0, LID_Y1, LID_D, STEEL_DK, "Metal")
    for i in range(6):                         # 6 bolt heads (was 8: the two parts pay for the HV-sign bolt links)
        az = 30 + 60 * i
        p = polar(2.42, az, LID_Y1)
        m.cyl("DrumLidBolt%d" % (i + 1), tuple(p + Vector((0, -0.03, 0))), tuple(p + Vector((0, 0.09, 0))), 0.26,
              STEEL, "Metal", collide=False)
    hv_sign(m, "SignFront", 180)
    hv_sign(m, "SignBack", 0)

    # ---- spark-gap posts on the deck corners
    for i, az in enumerate((135, 225, 315, 45)):
        spark_post(m, i + 1, az)

    # ---- ribbed ceramic insulator under the coil (white / blue / white sheds)
    vdisc(m, "InsulatorCore", LID_Y1 - 0.02, COIL_Y0 - 0.2, 1.7, CERAMIC)
    for j, (y, d, col) in enumerate(((2.98, 3.5, CERAMIC), (3.3, 3.0, CERAMIC_BLUE), (3.6, 3.3, CERAMIC))):
        vdisc(m, "InsulatorShed%d" % (j + 1), y - 0.09, y + 0.09, d, col, collide=j == 0)

    # ---- the secondary coil: glowing core, copper windings, ceramic collars
    vdisc(m, "CoilCollarLow", COIL_Y0 - 0.24, COIL_Y0 + 0.06, 2.85, CERAMIC)
    vdisc(m, "GlowCoil", COIL_Y0, COIL_Y1, CORE_D, NEON, "Neon")
    n = 10
    pitch = (COIL_Y1 - COIL_Y0 - 0.06) / n
    for i in range(n):
        y0 = COIL_Y0 + 0.06 + i * pitch + 0.05
        y1 = y0 + pitch - 0.12
        vdisc(m, "CoilWinding%02d" % (i + 1), y0, y1, WIND_D, COPPER if i % 2 == 0 else COPPER_DK, "Metal")
    vdisc(m, "CoilCollarHigh", COIL_Y1 - 0.06, COIL_Y1 + 0.24, 2.85, CERAMIC)
    vdisc(m, "CoilCap", COIL_Y1 + 0.22, TOR_Y - 0.05, 1.9, CERAMIC_BLUE)

    # ---- chrome toroid: 12 tube segments + ball joints, a web plate across the hole, 4 breakout nodes
    segs = 12
    pts = [polar(TOR_R, 360.0 * i / segs, TOR_Y) for i in range(segs)]
    for i in range(segs):
        a, b = pts[i], pts[(i + 1) % segs]
        m.cyl("Toroid%02d" % (i + 1), tuple(a), tuple(b), TOR_T, CHROME, "Metal")
        m.ball("ToroidJoint%02d" % (i + 1), tuple(a), TOR_T, CHROME, "Metal", collide=False)
    vdisc(m, "ToroidWeb", TOR_Y - 0.06, TOR_Y + 0.06, TOR_R * 2, CHROME, "Metal", collide=False)
    for i, az in enumerate((180, 90, 0, 270)):
        # the ring's outer edge at azimuth az: 90-degree multiples are 12-gon VERTICES (joint balls), so the edge is
        # at TOR_R + TOR_T / 2; the node stands half out of it and the spark point sits on the node's outer face
        edge = TOR_R + TOR_T / 2
        p = polar(edge - 0.06, az, TOR_Y)
        m.ball("GlowNode%d" % (i + 1), tuple(p), 0.44, NEON_HOT, "Neon", collide=False)
        m.pivot("Spark%d" % (i + 1), tuple(polar(edge + 0.16, az, TOR_Y)))

    # ---- insulator neck + cradle + claws + orb
    vdisc(m, "NeckCore", TOR_Y - 0.1, CRADLE_Y - 0.1, 1.15, CERAMIC)
    vdisc(m, "NeckShed1", 9.94, 10.08, 1.75, CERAMIC_BLUE, collide=False)
    vdisc(m, "Cradle", CRADLE_Y - 0.18, CRADLE_Y, 2.15, STEEL_MID, "Metal")
    vdisc(m, "CradleTrim", CRADLE_Y - 0.14, CRADLE_Y - 0.04, 2.3, COPPER, "Metal", collide=False)
    m.ball("Orb", (0, ORB_Y, 0), ORB_D, ORB_COL, "Metal")
    m.pivot("OrbCentre", (0, ORB_Y, 0))
    for i, az in enumerate((135, 225, 315, 45)):
        claw(m, i + 1, az)

    m.attr("Cost", 30000000)
    m.attr("PropSet", "defence2")
    m.attr("Notes", "TeslaCoil rebuilt 2026-09-24 (fun-builds/models/build_TeslaCoil.py, primlib parts): tesla tower. ONE "
                    "moving part 'Orb' (Metal Ball d %.1f) centred on Pivot_OrbCentre (0, %.2f, 0); the server spins it "
                    "about the vertical axis there. Pivot_ProngTip1..4 = the neon claw tip centres at radius %.2f, "
                    "y %.2f (1 +X-Z, 2 -X-Z, 3 -X+Z, 4 +X+Z), %.2f from OrbCentre = ~%.2f studs of open air between the "
                    "orb and each tip for the idle arcs; Pivot_Spark1..4 = toroid breakout nodes (front, +X, back, -X). "
                    "Glow* = neon the DefenceFX client pulses. Everything else is static."
                    % (ORB_D, ORB_Y, TIP_R, TIP_Y, math.hypot(TIP_R, TIP_Y - ORB_Y),
                       math.hypot(TIP_R, TIP_Y - ORB_Y) - ORB_D / 2 - 0.18))
    return m.finish()
