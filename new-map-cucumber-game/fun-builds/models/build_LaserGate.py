"""LaserGate (Defences, fun-builds 2026-09-24, package DefLaserGate) - v2: TALL, WIDE, SLIM laser fence.
Two slim armoured emitter pylons (dark DiamondPlate ski feet with sloped toe armour and bolts, yellow/black hazard-stripe
collars top and bottom, off-white armour plates over a gunmetal core split into three panels by dark belts, a
laser-warning sign front and back, red neon edge strips up the inner corners, a dark emitter spine on each inner face
carrying six bezelled red lenses, a white head whose roof rises toward the gap and overhangs it above y 10.02 with a
neon brow, neon slits, an antenna beacon, vents and a grab handle on the outer face) and two floor cables with yellow
clamps linking the feet in front of and behind the passage. v2 proportions: 12.2 wide x 3.0 deep x 11.09 tall; pylon
bodies 1.1 wide in X (x 4.85..5.98), feet to 6.1, roof tops 10.57, beacon tops 11.09.

RIG CONTRACT (live DefenceService "LaserGate", set-2 rig: origin = Hitbox + source bounding-box centre):
  Beam1..Beam6   ONE Neon ff2f2f Cylinder each (axis X, diameter 0.16), x -4.75..+4.75 at z = 0,
                 y = 1.5 / 3.0 / 4.5 / 6.0 / 7.5 / 9.0 (bottom to top). Non-colliding; the server shimmers them.
  PASSAGE        nothing solid (CanCollide) within |x| <= 4.8 and |z| <= 1.3 from y 0 to 10 except the beams (which
                 don't collide). Pylon inner faces at |x| = 4.85 (clear gap 9.7). Only the non-colliding neon lenses
                 reach in to |x| 4.73 (they sleeve the beam ends); the floor cables (non-colliding) run at |z| = 1.40.
  Glow*          neon parts the DefenceFX client pulses: GlowLens<L|R><1-6> (the emitter lenses at the beam ends),
                 GlowEdge<L|R><F|B> (vertical inner-corner strips), GlowBrow<L|R> (roof brow facing the gap),
                 GlowCap<L|R><F|B> (head slits), GlowBeacon<L|R> (antenna tips)
  Pivot_Spark1..12  beam ends: Spark(2i-1) = (-4.75, y_i, 0), Spark(2i) = (+4.75, y_i, 0) for beam i
  Pivot_BeamLeft / Pivot_BeamRight  (-/+4.75, 5.25, 0)
Pylon L is at -X, pylon R at +X (the old prop's naming). Authored origin = floor centre (min y = 0), front = -Z,
the bounding box is symmetric about x = 0 and z = 0.
"""
import math

# ---------------------------------------------------------------- palette
DARK = "23262c"      # near-black: base plates, rails, stripes, spine, belts
GUN = "3b4350"       # gunmetal core / toe armour
ARMOUR = "f2f0ea"    # off-white armour plates / head
YELLOW = "f2c13d"    # hazard collars / cable clamps
STEEL = "9aa7b8"     # bolts, bezels, antenna, handle
RED = "ff2f2f"       # laser neon

# ---------------------------------------------------------------- layout (pylon R at +X; pylon L mirrors it)
BEAM_Y = (1.5, 3.0, 4.5, 6.0, 7.5, 9.0)
BEAM_HALF = 4.75
XI = 4.85            # pylon inner face (every solid part has |x| >= XI)
PX = 5.45            # pylon centre |x|
FOOT_X1 = 6.1        # outer face of the foot (the widest part)
HEAD_X1 = 6.06       # outer face of the head / roof


def bx(m, name, s, x0, x1, y0, y1, z0, z1, color, material="SmoothPlastic", **kw):
    """Axis-aligned block from pylon-R extents (x0 < x1 as |x|), mirrored to the pylon side s."""
    return m.block(name, (s * (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (round(x1 - x0, 4), round(y1 - y0, 4), round(z1 - z0, 4)),
                   color, material, **kw)


def stripes_front(m, name, s, y0, y1, offs, z_face, w, zsign):
    """Black 45-degree hazard stripes on a collar face looking along zsign*Z (ends tucked under the rails)."""
    L = (y1 - y0) * math.sqrt(2) - w
    for i, off in enumerate(offs):
        m.block("%s%d" % (name, i + 1), (s * (PX + off), (y0 + y1) / 2, zsign * (z_face + 0.015)), (w, L, 0.05), DARK,
                "SmoothPlastic", rot=(0, 0, 45 * s * zsign), collide=False)


def stripes_side(m, name, s, y0, y1, zs, x_face, w):
    """Hazard stripes on the collar's outer face (normal along s*X)."""
    L = (y1 - y0) * math.sqrt(2) - w
    for i, zc in enumerate(zs):
        m.block("%s%d" % (name, i + 1), (s * (x_face + 0.015), (y0 + y1) / 2, zc), (0.05, L, w), DARK,
                "SmoothPlastic", rot=(45 * s, 0, 0), collide=False)


BAND = (4.97, 5.93, 0.72)    # collar band x0, x1, half depth
RAIL = (4.94, 6.02, 0.78)    # collar rails x0, x1, half depth


def collar(m, name, s, y0, y1, offs, stripe_w, zs=None):
    """Yellow hazard collar y0..y1 round the column (not the inner spine) with dark rails and black stripes."""
    bx(m, name, s, BAND[0], BAND[1], y0, y1, -BAND[2], BAND[2], YELLOW)
    bx(m, name + "RailLo", s, RAIL[0], RAIL[1], y0 - 0.06, y0 + 0.06, -RAIL[2], RAIL[2], DARK, "Metal")
    bx(m, name + "RailHi", s, RAIL[0], RAIL[1], y1 - 0.06, y1 + 0.06, -RAIL[2], RAIL[2], DARK, "Metal")
    stripes_front(m, name + "StripeF", s, y0, y1, offs, BAND[2], stripe_w, -1)
    stripes_front(m, name + "StripeB", s, y0, y1, offs, BAND[2], stripe_w, 1)
    if zs:
        stripes_side(m, name + "StripeS", s, y0, y1, zs, BAND[1], stripe_w)


def pylon(m, s):
    t = "L" if s < 0 else "R"
    P = "Pylon" + t

    # ---- armoured ski foot: DiamondPlate base, gunmetal armour block with sloped toes, steel bolts at the tips
    bx(m, P + "FootBase", s, XI, FOOT_X1, 0.0, 0.3, -1.5, 1.5, DARK, "DiamondPlate")
    bx(m, P + "FootArmour", s, 4.87, 5.99, 0.3, 0.9, -0.8, 0.8, GUN, "Metal")
    m.wedge(P + "ToeF", (s * 5.43, 0.6, -1.025), (1.12, 0.6, 0.45), GUN, "Metal")                  # z -1.25 .. -0.8
    m.wedge(P + "ToeB", (s * 5.43, 0.6, 1.025), (1.12, 0.6, 0.45), GUN, "Metal", rot=(0, 180, 0))
    for i, bz in enumerate((-1.38, 1.38)):
        m.cyl(P + "Bolt%d" % (i + 1), (s * PX, 0.28, bz), (s * PX, 0.38, bz), 0.16, STEEL, "Metal", collide=False)

    # ---- lower hazard collar (y 0.9 .. 1.4): stripes front, back and outer face
    collar(m, P + "CollarLo", s, 0.9, 1.4, (-0.2, 0.2), 0.13, zs=(-0.4, 0.0, 0.4))

    # ---- column: gunmetal core + off-white armour plates (front, back, outer) + two dark belts = three panels
    m.block(P + "Core", (s * PX, 5.15, 0), (0.9, 7.54, 1.2), GUN, "Metal")                            # x 5.0..5.9, y 1.38..8.92
    pa, pb = 1.52, 8.78
    bx(m, P + "PlateF", s, 5.08, 5.82, pa, pb, -0.68, -0.58, ARMOUR)
    bx(m, P + "PlateB", s, 5.08, 5.82, pa, pb, 0.58, 0.68, ARMOUR)
    bx(m, P + "PlateS", s, 5.88, 5.98, pa, pb, -0.5, 0.5, ARMOUR)
    for i, by in enumerate((3.95, 6.35)):
        bx(m, P + "Belt%d" % (i + 1), s, 4.97, 6.01, by - 0.07, by + 0.07, -0.71, 0.71, DARK, "Metal")
    # laser-warning signs (yellow diamond, dark border, "!") on the middle panel front and back
    sy = 5.15
    for tag, zs in (("F", -1), ("B", 1)):
        face = 0.68
        m.block(P + "Sign%sBorder" % tag, (s * PX, sy, zs * (face + 0.015)), (0.5, 0.5, 0.05), DARK,
                "SmoothPlastic", rot=(0, 0, 45), collide=False)
        m.block(P + "Sign%s" % tag, (s * PX, sy, zs * (face + 0.035)), (0.38, 0.38, 0.05), YELLOW, "SmoothPlastic",
                rot=(0, 0, 45), collide=False)
        m.block(P + "Sign%sBang" % tag, (s * PX, sy + 0.045, zs * (face + 0.055)), (0.065, 0.18, 0.05), DARK,
                "SmoothPlastic", collide=False)
        m.block(P + "Sign%sDot" % tag, (s * PX, sy - 0.12, zs * (face + 0.055)), (0.065, 0.065, 0.05), DARK,
                "SmoothPlastic", collide=False)
    # red neon strips up the inner corners (proud of the plates by 0.02, the belts wrap over them)
    bx(m, "GlowEdge%sF" % t, s, 4.98, 5.09, 1.54, 8.86, -0.70, -0.57, RED, "Neon", collide=False, shadow=False)
    bx(m, "GlowEdge%sB" % t, s, 4.98, 5.09, 1.54, 8.86, 0.57, 0.70, RED, "Neon", collide=False, shadow=False)
    # outer face: vents (top panel) + grab handle (bottom panel)
    for i, vy in enumerate((7.35, 7.6)):
        bx(m, P + "Vent%d" % (i + 1), s, 5.96, 6.02, vy - 0.05, vy + 0.05, -0.35, 0.35, DARK, "Metal", collide=False)
    for i, hy in enumerate((2.5, 3.4)):
        bx(m, P + "HandleMount%d" % (i + 1), s, 5.96, 6.06, hy - 0.05, hy + 0.05, -0.06, 0.06, DARK, "Metal",
           collide=False)
    m.cyl(P + "Handle", (s * 6.04, 2.43, 0), (s * 6.04, 3.47, 0), 0.08, STEEL, "Metal", collide=False)

    # ---- emitter spine on the inner face + six bezelled lenses at the beam heights
    bx(m, P + "Spine", s, 4.89, 5.02, 0.88, 9.5, -0.3, 0.3, DARK, "Metal")
    for i, by in enumerate(BEAM_Y):
        m.cylx(P + "Bezel%d" % (i + 1), (s * 4.88, by, 0), 0.06, 0.46, STEEL, "Metal", collide=False)  # x 4.85..4.91
        m.cylx("GlowLens%s%d" % (t, i + 1), (s * 4.8, by, 0), 0.14, 0.3, RED, "Neon", collide=False,
               shadow=False)                             # x 4.73..4.87: sleeves the beam end (beam stops at 4.75)

    # ---- upper hazard collar (y 8.9 .. 9.4): stripes front and back
    collar(m, P + "CollarHi", s, 8.9, 9.4, (-0.19, 0.19), 0.12)

    # ---- head: white block + a roof that rises toward the gap and overhangs it ABOVE the passage (y >= 10.02),
    #      neon brow on the roof's inner face, neon slits front / back, antenna beacon at the outer back corner
    bx(m, P + "Head", s, XI, HEAD_X1, 9.44, 10.02, -0.8, 0.8, ARMOUR)
    rx0 = 4.6                                                     # roof inner face (overhang 0.25 past the body)
    m.wedge(P + "Roof", (s * (rx0 + HEAD_X1) / 2, 10.295, 0), (1.6, 0.55, round(HEAD_X1 - rx0, 4)), ARMOUR,
            "SmoothPlastic", rot=(0, -90 * s, 0))                 # y 10.02 .. 10.57
    bx(m, "GlowBrow" + t, s, rx0 - 0.03, rx0 + 0.03, 10.2, 10.36, -0.62, 0.62, RED, "Neon", collide=False, shadow=False)
    bx(m, "GlowCap%sF" % t, s, 5.05, 5.85, 9.68, 9.78, -0.84, -0.78, RED, "Neon", collide=False, shadow=False)
    bx(m, "GlowCap%sB" % t, s, 5.05, 5.85, 9.68, 9.78, 0.78, 0.84, RED, "Neon", collide=False, shadow=False)
    ax, az = 5.8, 0.4                         # roof surface here: 10.02 + 0.55 * (6.06 - 5.8) / 1.46 = 10.12
    m.cyl(P + "Antenna", (s * ax, 10.08, az), (s * ax, 10.92, az), 0.08, STEEL, "Metal", collide=False)
    m.ball("GlowBeacon" + t, (s * ax, 10.98, az), 0.22, RED, "Neon", collide=False, shadow=False)


def build(D, P):
    m = P.Model(D, "LaserGate", category="Defences")

    pylon(m, -1)
    pylon(m, 1)

    # ---- the six beams (rig contract: exact names, positions, sizes)
    for i, y in enumerate(BEAM_Y):
        m.cylx("Beam%d" % (i + 1), (0, y, 0), 2 * BEAM_HALF, 0.16, RED, "Neon", collide=False, shadow=False)
        m.pivot("Spark%d" % (2 * i + 1), (-BEAM_HALF, y, 0))
        m.pivot("Spark%d" % (2 * i + 2), (BEAM_HALF, y, 0))
    m.pivot("BeamLeft", (-BEAM_HALF, 5.25, 0))
    m.pivot("BeamRight", (BEAM_HALF, 5.25, 0))

    # ---- floor cables in front of and behind the passage (|z| = 1.40, outside the clear zone), yellow clamps
    for tag, z in (("F", -1.4), ("B", 1.4)):
        m.cylx("Cable" + tag, (0, 0.09, z), 9.8, 0.18, DARK, "Rubber", collide=False)       # x -4.9..4.9, into the feet
        for i, cx in enumerate((-2.4, 2.4)):
            m.block("Cable%sClamp%d" % (tag, i + 1), (cx, 0.11, z), (0.22, 0.22, 0.19), YELLOW, "Metal", collide=False)

    m.attr("Cost", 250000)
    m.attr("PropSet", "defence2")
    m.attr("Notes", "LaserGate v2 2026-09-24 (fun-builds/models/build_LaserGate.py, primlib parts): tall wide slim "
                    "laser fence, two emitter pylons (PylonL* at x -5.45, PylonR* at x +5.45, inner faces |x| 4.85). "
                    "Static prop. Beam1..Beam6 (bottom to top) = ONE Neon ff2f2f Cylinder each, d 0.16, x -4.75..4.75 "
                    "at z 0, y 1.5/3/4.5/6/7.5/9 - the server shimmers them. Nothing solid within |x| <= 4.8, "
                    "|z| <= 1.3, y 0..10 except the beams (zombies walk through along Z). Glow* = neon parts the "
                    "DefenceFX client pulses (GlowLens<L|R>1-6 at the beam ends, GlowEdge, GlowBrow, GlowCap, "
                    "GlowBeacon); Pivot_Spark1..12 = beam ends (odd -X, even +X, beam i -> 2i-1 / 2i).")
    return m.finish()
