"""PottedPlant (Home) -- a big leafy monstera in a glazed pot, fun-builds HomeDecor 2026-09-24.

~4.0 wide x 6.2 tall x 4.1 deep (leaves; the pot is 2.5 wide). A round-bellied cobalt-glazed pot (dark foot, cream equator band + a thinner lower
band, yellow shoulder dots, a cream glazed lip) on a terracotta saucer, dark soil on the lip (a cream ring shows round
it) with two pebbles, and eleven
monstera fronds (11): each a stem from the soil to a broad leaf made of two ellipsoid halves folded into a shallow V
about a pale midrib, from tall upright leaves to low ones drooping over the rim, plus a rolled new leaf in the middle.

Part names / pivots the behaviour relies on (FB/src/behaviours/client/PottedPlant.lua):
    Frond<N>Stem / Frond<N>LeafL / Frond<N>LeafR / Frond<N>Rib   one frond (N = 1..11); it sways about Pivot_Frond<N>
    Frond0Spike                                                  the rolled new leaf, sways about Pivot_Frond0
    Pivot_Frond<N>                                               the stem's base in the soil
"""
import math
from mathutils import Vector

GLAZE = "2b5fc2"
GLAZE_D = "1d3f86"
CREAM = "f2f0ea"
BRASS = "f2c13d"
TERRA = "b8612f"
SOIL = "5a3b24"
LEAF = "2f9e44"
LEAF_D = "23823a"
LEAF_L = "3fb957"
RIB = "8fd67a"
STEM = "4f8f3a"

BELLY_Y, BELLY_R, BELLY_H = 1.25, 1.25, 1.0   # ellipsoid centre, horizontal radius, vertical half height
SOIL_TOP = 2.47   # 0.03 above the lip top (2.44): the soil disc sits ON the solid lip, a 0.12 cream ring shows round it

# fronds: yaw (deg, 0 = toward the front -Z, 90 = toward -X), stem base offset, stem reach out, stem height above the
# soil, leaf pitch (deg above horizontal), leaf length, leaf width, fold (deg), colour
FRONDS = [
    (0, 0.1, 0.3, 2.2, 60, 1.6, 1.42, 18, LEAF),
    (140, 0.12, 0.32, 2.05, 55, 1.65, 1.46, 18, LEAF_D),
    (250, 0.12, 0.34, 1.85, 50, 1.65, 1.48, 16, LEAF),
    (65, 0.12, 0.36, 1.55, 42, 1.7, 1.5, 16, LEAF_L),
    (195, 0.12, 0.36, 1.4, 38, 1.7, 1.5, 16, LEAF),
    (305, 0.12, 0.38, 1.2, 30, 1.65, 1.46, 14, LEAF_D),
    (105, 0.1, 0.38, 0.95, 20, 1.6, 1.42, 14, LEAF),
    (225, 0.1, 0.38, 0.75, 10, 1.55, 1.38, 12, LEAF_L),
    (345, 0.1, 0.36, 0.55, -2, 1.5, 1.34, 12, LEAF),
    (165, 0.1, 0.34, 0.45, -8, 1.45, 1.3, 12, LEAF_D),
    (35, 0.1, 0.34, 0.35, -14, 1.4, 1.26, 12, LEAF_L),
]


def direction(yaw):
    a = math.radians(yaw)
    return Vector((-math.sin(a), 0.0, -math.cos(a)))


def belly_r(y):
    t = (y - BELLY_Y) / BELLY_H
    return BELLY_R * math.sqrt(max(0.0, 1 - t * t))


def build(D, P):
    m = P.Model(D, "PottedPlant", category="Home")

    # ------------------------------------------------ saucer + glazed pot
    m.cyl("Saucer", (0, 0, 0), (0, 0.14, 0), 2.0, TERRA, "SmoothPlastic")
    m.cyl("SaucerLip", (0, 0.1, 0), (0, 0.2, 0), 2.08, TERRA, "SmoothPlastic", collide=False)
    m.cyl("PotFoot", (0, 0.12, 0), (0, 0.36, 0), 1.42, GLAZE_D, "SmoothPlastic", reflectance=0.12)
    m.ellipsoid("PotBelly", (0, BELLY_Y, 0), (2 * BELLY_R, 2 * BELLY_H, 2 * BELLY_R), GLAZE, "SmoothPlastic", reflectance=0.15)
    m.cyl("PotBand", (0, BELLY_Y - 0.1, 0), (0, BELLY_Y + 0.1, 0), 2 * BELLY_R + 0.04, CREAM, "SmoothPlastic", reflectance=0.1, collide=False)
    yb = 0.66
    m.cyl("PotBandLow", (0, yb - 0.05, 0), (0, yb + 0.05, 0), 2 * belly_r(yb) + 0.04, CREAM, "SmoothPlastic", reflectance=0.1, collide=False)
    ys = 1.78
    rs = belly_r(ys)
    for k in range(8):
        a = 2 * math.pi * (k + 0.5) / 8
        m.ball("PotDot%d" % (k + 1), (rs * math.sin(a), ys, rs * math.cos(a)), 0.18, BRASS, "SmoothPlastic", collide=False, shadow=False)
    m.cyl("PotNeck", (0, 2.0, 0), (0, 2.34, 0), 1.9, GLAZE, "SmoothPlastic", reflectance=0.15)
    m.cyl("PotLip", (0, 2.3, 0), (0, 2.44, 0), 2.08, CREAM, "SmoothPlastic", reflectance=0.1)
    m.cyl("Soil", (0, SOIL_TOP - 0.09, 0), (0, SOIL_TOP, 0), 1.84, SOIL, "Ground", collide=False)
    m.ellipsoid("SoilPebble1", (0.52, SOIL_TOP + 0.02, -0.4), (0.26, 0.14, 0.2), "c9c3b8", "Slate", collide=False, shadow=False)
    m.ellipsoid("SoilPebble2", (-0.45, SOIL_TOP + 0.02, 0.5), (0.22, 0.12, 0.2), "9aa0aa", "Slate", collide=False, shadow=False)

    # ------------------------------------------------ fronds
    for n, (yaw, off, reach, height, pitch, L, W, fold, col) in enumerate(FRONDS, start=1):
        d = direction(yaw)
        base = Vector((0, SOIL_TOP - 0.1, 0)) + d * off
        top = Vector((0, SOIL_TOP, 0)) + d * (off + reach) + Vector((0, height, 0))
        m.cyl("Frond%dStem" % n, tuple(base), tuple(top), 0.11, STEM, "SmoothPlastic", collide=False, shadow=False)
        m.pivot("Frond%d" % n, tuple(base))
        # leaf frame: long axis -Z (outward), normal +Y, then pitch up and yaw around
        R = P.angles(0, yaw, 0) @ P.angles(pitch, 0, 0)
        # two halves: each toed in (in the leaf plane) so their tips meet at the midrib and their bases part into the
        # monstera heart notch, then folded up about the midrib into a shallow V
        toe = math.degrees(math.atan2(0.36 * W, L))
        for side, sg in (("L", 1), ("R", -1)):
            H = P.angles(0, 0, sg * fold) @ P.angles(0, sg * toe, 0)
            c = top + R @ (P.angles(0, 0, sg * fold) @ Vector((sg * 0.18 * W, 0, -L / 2)))
            m.ellipsoid("Frond%dLeaf%s" % (n, side), tuple(c), (0.64 * W, 0.06, L), col, "SmoothPlastic", rot=R @ H,
                        collide=False)
        rib_c = top + R @ Vector((0, 0.025, -L * 0.42))
        m.block("Frond%dRib" % n, tuple(rib_c), (0.06, 0.05, L * 0.8), RIB, "SmoothPlastic", rot=R, collide=False, shadow=False)

    # ------------------------------------------------ the rolled new leaf in the middle
    spike_base = (0.05, SOIL_TOP - 0.05, 0.05)
    m.pivot("Frond0", spike_base)
    Rs = P.angles(-8, 30, 0)
    c = Vector(spike_base) + Rs @ Vector((0, 0.9, 0))
    m.ellipsoid("Frond0Spike", tuple(c), (0.16, 1.8, 0.16), LEAF_L, "SmoothPlastic", rot=Rs, collide=False, shadow=False)

    m.attr("Cost", 200)
    m.attr("DisplayName", "Potted Plant")
    m.attr("Notes", "Monstera in a glazed pot (primlib parts, fun-builds HomeDecor). The client sways each Frond<N>* "
                    "group gently about Pivot_Frond<N>. Built by fun-builds/models/build_PottedPlant.py.")
    return m.finish()
