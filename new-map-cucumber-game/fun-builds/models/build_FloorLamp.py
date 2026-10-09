"""FloorLamp (Home, fun-builds 2026-09-24, package HomeHearth).

A tall reading lamp, ~7.66 high: a heavy black weighted base (foot plate, domed weight, brass trim ring), a
brass pole with two knuckle collars and a little round side tray at hand height (a red book and a mug of
coffee on it), and a classic tapered (empire) fabric shade of 16 cream panels with a brass trim band round
its open bottom, a brass rim + diffuser disc on top, a finial, a bulb on a socket inside (seen through the
open bottom) and a brass pull-chain with a bead hanging out of the shade at the front.

Behaviour contract (behaviours/server|client/FloorLamp.lua):
  ShadeGlowTop    the diffuser disc on top of the shade: authored warm cream SmoothPlastic, Neon while Fun_On
  Bulb            the bulb inside the shade: authored off-white SmoothPlastic, Neon while Fun_On
  ShadePanel01..16  the fabric panels: authored cream Fabric, the client turns them warm cream Neon while on (the
                  whole shade glows, so the lamp reads as on from every side, even in daylight)
  PullChain, PullBead  the pull-chain: the client tugs them down + back when the lamp is switched
  Pivot_Light     the bulb centre (the PointLight)
  Pivot_Spot      inside the shade just over its open bottom, clear of the pole / socket / bulb (the SpotLight,
                  shining down through the opening)
  Pivot_Switch    the pull-chain bead (the "Lamp on" / "Lamp off" prompt)
  Pivot_ChainTop  where the chain hangs from (the tug pivot)
"""
import math
from mathutils import Vector, Matrix

BLACK = "23262c"
BRASS = "c9a227"
BRASS_DARK = "a8841c"
SHADE = "f3e7cc"
GLOW_OFF = "e9dcbd"
WOOD = "8a5a2b"
RED = "d9443c"
PAPER = "f2f0ea"

R_BOTTOM = 1.45      # shade apothem at the bottom edge
R_TOP = 0.95         # ... at the top edge
SHADE_BOTTOM = 5.55
SHADE_TOP = 7.3
BULB = (0, 6.1, 0)
BULB_OFF = "f4efe0"
TRIM = "c9a227"
CHAIN_X, CHAIN_Z = 0.3, -0.3
SHADE_ON = "ffe4af"   # the panels' Neon colour while on (the client's SHADE_NEON_COLOR, 255 228 175)
PREVIEW_ON = False    # review renders only (build__FloorLampLit.py): shade panels, diffuser + bulb Neon


def build(D, P):
    m = P.Model(D, "FloorLamp", category="Home")

    # ------------------------------------------------------------ weighted base
    m.disc("BaseFoot", (0, 0.08, 0), (0, 1, 0), 2.0, 0.16, BLACK, "Metal")
    m.ellipsoid("BaseWeight", (0, 0.28, 0), (1.76, 0.56, 1.76), BLACK, "Metal")
    m.disc("BaseTrim", (0, 0.17, 0), (0, 1, 0), 1.86, 0.07, BRASS, "Metal", collide=False)
    m.cyl("BaseCollar", (0, 0.4, 0), (0, 0.66, 0), 0.36, BRASS, "Metal")

    # ------------------------------------------------------------ pole, collars, tray
    m.cyl("Pole", (0, 0.5, 0), (0, SHADE_BOTTOM + 0.1, 0), 0.2, BRASS, "Metal")
    for i, y in enumerate((2.0, 4.35)):
        m.cyl("Collar%d" % (i + 1), (0, y, 0), (0, y + 0.16, 0), 0.3, BRASS_DARK, "Metal", collide=False)
    tray_y = 3.05
    m.disc("Tray", (0, tray_y, 0), (0, 1, 0), 1.5, 0.08, WOOD, "Wood")
    m.disc("TrayRim", (0, tray_y - 0.03, 0), (0, 1, 0), 1.58, 0.1, BRASS, "Metal", collide=False)
    m.cyl("TrayHub", (0, tray_y - 0.2, 0), (0, tray_y - 0.02, 0), 0.32, BRASS_DARK, "Metal", collide=False)
    top = tray_y + 0.04
    # a closed red book lying on the tray + a white mug
    m.block("Book", (-0.38, top + 0.05, 0.2), (0.5, 0.12, 0.38), RED, "SmoothPlastic", rot=(0, 12, 0), collide=False)
    m.block("BookPages", (-0.38, top + 0.05, 0.2), (0.46, 0.08, 0.42), PAPER, "SmoothPlastic", rot=(0, 12, 0),
            collide=False, shadow=False)
    m.cyl("Mug", (0.3, top - 0.01, -0.22), (0.3, top + 0.3, -0.22), 0.26, PAPER, "SmoothPlastic", collide=False)
    m.disc("MugHandle", (0.46, top + 0.15, -0.22), (0, 0, 1), 0.16, 0.06, PAPER, "SmoothPlastic", collide=False,
           shadow=False)
    m.disc("MugCoffee", (0.3, top + 0.28, -0.22), (0, 1, 0), 0.2, 0.06, "6b4423", "SmoothPlastic", collide=False,
           shadow=False)

    # ------------------------------------------------------------ shade: an open-bottomed tapered (empire) shade
    # of 16 fabric panels, each with a trim strip along its bottom edge, a brass rim + diffuser disc on top,
    # and a bulb on a socket inside (seen through the open bottom)
    m.cyl("Socket", (0, SHADE_BOTTOM - 0.1, 0), (0, SHADE_BOTTOM + 0.3, 0), 0.3, "3b4350", "Metal", collide=False)
    m.ball("Bulb", BULB, 0.6, "fff1c8" if PREVIEW_ON else BULB_OFF, "Neon" if PREVIEW_ON else "SmoothPlastic",
           collide=False, shadow=False)
    n = 16
    phi = math.atan2(R_BOTTOM - R_TOP, SHADE_TOP - SHADE_BOTTOM)          # lean of each panel
    slant = math.hypot(R_BOTTOM - R_TOP, SHADE_TOP - SHADE_BOTTOM)
    width = 2 * R_BOTTOM * math.tan(math.pi / n) + 0.01                      # no gaps at the bottom edge
    for i in range(n):
        a = 2 * math.pi * (i + 0.5) / n
        radial = Vector((math.sin(a), 0, math.cos(a)))
        t = Vector((math.cos(a), 0, -math.sin(a)))                           # local X: along the rim
        up = Vector((-math.sin(a) * math.sin(phi), math.cos(phi), -math.cos(a) * math.sin(phi)))  # local Y: up the slant
        nrm = t.cross(up)                                                    # local Z: outward
        R = Matrix((t, up, nrm)).transposed()
        mid = radial * ((R_BOTTOM + R_TOP) / 2) + Vector((0, (SHADE_BOTTOM + SHADE_TOP) / 2, 0))
        m.block("ShadePanel%02d" % (i + 1), tuple(mid), (width, slant, 0.06), SHADE_ON if PREVIEW_ON else SHADE,
                "Neon" if PREVIEW_ON else "Fabric", rot=R)
        foot = radial * R_BOTTOM + Vector((0, SHADE_BOTTOM, 0)) + up * 0.07
        m.block("ShadeTrim%02d" % (i + 1), tuple(foot), (width + 0.02, 0.14, 0.1), TRIM, "Fabric", rot=R,
                collide=False, shadow=False)
    # the top binding: a band deep enough to swallow the panels' top corners (each panel is cut for the bottom
    # circumference, so near the top neighbours overlap and their corners would stick out as a sawtooth; at
    # y 7.12 the outermost panel edge is 1.072 from the axis)
    m.cyl("ShadeRim", (0, SHADE_TOP - 0.18, 0), (0, SHADE_TOP + 0.04, 0), 2.17, TRIM, "Fabric",
          collide=False)
    glow, glow_mat = ("ffe2a6", "Neon") if PREVIEW_ON else (GLOW_OFF, "SmoothPlastic")
    m.disc("ShadeGlowTop", (0, SHADE_TOP + 0.05, 0), (0, 1, 0), 2 * R_TOP - 0.1, 0.06, glow, glow_mat,
           collide=False, shadow=False)
    # finial on top of the harp
    m.cyl("FinialStem", (0, SHADE_TOP + 0.05, 0), (0, SHADE_TOP + 0.2, 0), 0.08, BRASS, "Metal", collide=False)
    m.ball("Finial", (0, SHADE_TOP + 0.26, 0), 0.2, BRASS, "Metal", collide=False)

    # ------------------------------------------------------------ pull-chain
    chain_top = SHADE_BOTTOM + 0.15
    chain_bottom = SHADE_BOTTOM - 0.85
    m.cyl("PullChain", (CHAIN_X, chain_top, CHAIN_Z), (CHAIN_X, chain_bottom, CHAIN_Z), 0.05, BRASS, "Metal",
          collide=False, shadow=False)
    m.ball("PullBead", (CHAIN_X, chain_bottom - 0.06, CHAIN_Z), 0.16, BRASS, "Metal", collide=False, shadow=False)
    # the switch housing on the socket the chain comes out of
    m.cyl("SwitchArm", (0.08, chain_top + 0.02, -0.08), (CHAIN_X + 0.03, chain_top + 0.02, CHAIN_Z - 0.03), 0.09,
          BRASS_DARK, "Metal", collide=False, shadow=False)

    m.pivot("Light", BULB)
    m.pivot("Spot", (0, SHADE_BOTTOM + 0.2, -0.36))
    m.pivot("Switch", (CHAIN_X, chain_bottom - 0.06, CHAIN_Z))
    m.pivot("ChainTop", (CHAIN_X, chain_top, CHAIN_Z))
    m.attr("Cost", 300)
    m.attr("DisplayName", "Floor Lamp")
    m.attr("Notes", "Reading floor lamp (primlib parts, fun-builds HomeHearth). Prompt 'Lamp on' / 'Lamp off' at the "
                    "pull-chain (Pivot_Switch) toggles Fun_On (the server also switches it on at night, off at day). "
                    "While on: PointLight at Pivot_Light, downward SpotLight at Pivot_Spot, the ShadePanel* fabric, "
                    "ShadeGlowTop + Bulb go Neon (warm cream glow). "
                    "Built by fun-builds/models/build_FloorLamp.py.")
    return m.finish()
