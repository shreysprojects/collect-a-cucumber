"""Bed (Home) -- a cozy double bed, fun-builds HomeBedroom 2026-09-24 (fix pass: 8 wide, sleepers toward the foot).

8.0 wide (the 8-stud grid, like the Sofa) x ~9.1 long, blanket top 2.2, headboard at the BACK (+Z) with a padded
starry panel and a crescent-moon night-light standing on its top rail; low footboard at the front (-Z) with two
raised insets. A blue patchwork quilt with its top end folded back (cream lining + rolled crease), cream sheet
under two pillows.

Why 8 wide: lying blocky avatars are ~4 studs wide with their arms, so two of them side by side need ~8 studs.
Pelvises at x = +-2.0 put the inner arms edge to edge on the centre line (no overlap) and the outer arms mostly on
the quilt (the outer ~0.3 of the arm hangs over the quilt edge, like an arm at the edge of a mattress).
Head clearance: the lying head reaches ~2.5 toward +Z (CONTRACT), so the head top ends at z ~3.6 - on the pillow
and ~0.3 in front of the padded headboard; the feet end at z ~-2.7, well inside the quilt (front edge -4.05).

Part names / pivots the behaviour relies on (FB/src/behaviours/*/Bed.lua):
    Pillow1, Pillow2      Ellipsoid pillows (the client squashes pillow i while sleeper i lies on it)
    NightLight            the yellow moon disc of the roundel on the headboard's top rail (MoonCover, a sky-blue disc
                          in front of it, leaves a crescent showing); the PointLight lives in it
    NightStar1..9         yellow star dots on the padded headboard (1..8) and the roundel (9)
                          (every Night* part turns Neon while anyone sleeps)
    Pivot_Sleep1/2        the blanket top where sleeper i's pelvis rests (1 = +X side, 2 = -X side); head -> +Z
    Pivot_Pillow1/2       pillow centres (the "Z z z" fall back to above these)
    Pivot_NightLight      moon centre
"""
import math

WOOD = "8a5a2b"
WOOD_D = "6b4423"
WOOD_L = "a8733d"
BRASS = "f2c13d"
QUILT = "3f79d4"
PATCH = "6a9ef0"
CREAM = "f2f0ea"
PILLOW = "fcefc4"
MOON = "f2c13d"
PAD = "2f5fae"

POST_X = 3.7       # post centre |x| (0.6 caps / collars / finials -> the bed is exactly 8.0 wide)
POST_Z = 4.25      # post centre |z|
POST_D = 0.5
KNOB_D = 0.6       # foot caps, collars, ball finials
MAT_TOP = 1.98     # mattress top
MAT_X = 3.52       # mattress half width (sits on the side rails' inner edge)
BLANKET_TOP = 2.2
BL_X = 3.68        # blanket half width (the drapes hang just outside the mattress, over the rails)
BL_Z0 = -4.05      # blanket front edge
BL_Z1 = 1.25       # the fold crease (blanket turned back from here)
SLEEP_Z = 1.1      # pelvis of a sleeper: head top ~z 3.6 (on the pillow, clear of the headboard), feet ~z -2.7
SLEEP_X = 2.0      # sleeper pelvis |x|: two 4-wide blocky avatars meet edge to edge on the centre line
PILLOW_Z = 3.25
PILLOW_X = 1.9
PILLOW_W = 2.9


def build(D, P):
    m = P.Model(D, "Bed", category="Home")

    # ------------------------------------------------ posts: brass foot caps, turned posts, collars, ball finials
    for tag, z, top in (("Head", POST_Z, 4.45), ("Foot", -POST_Z, 2.35)):
        for side, s in (("L", 1), ("R", -1)):
            x = s * POST_X
            m.cyl("%sCap%s" % (tag, side), (x, 0, z), (x, 0.12, z), KNOB_D, BRASS, "Metal", collide=False)
            m.cyl("%sPost%s" % (tag, side), (x, 0.1, z), (x, top, z), POST_D, WOOD_D, "Wood")
            m.cyl("%sCollar%s" % (tag, side), (x, top - 0.04, z), (x, top + 0.08, z), KNOB_D, WOOD, "Wood", collide=False)
            m.ball("%sFinial%s" % (tag, side), (x, top + 0.34, z), KNOB_D, WOOD, "Wood", collide=False)

    # ------------------------------------------------ side rails + hidden slat deck
    for side, s in (("L", 1), ("R", -1)):
        m.block("Rail" + side, (s * (POST_X - 0.01), 0.8, 0), (0.28, 0.7, 8.1), WOOD, "Wood")
        m.cyl("RailBead" + side, (s * (POST_X + 0.12), 0.62, -4.02), (s * (POST_X + 0.12), 0.62, 4.02), 0.12, WOOD_D, "Wood",
              collide=False)
    m.block("Deck", (0, 0.76, 0), (2 * (POST_X - 0.13), 0.4, 8.1), WOOD_D, "WoodPlanks")

    # ------------------------------------------------ headboard: panel, round top rail, padded starry cushion
    panel_w = 2 * POST_X - 0.46
    m.block("HeadPanel", (0, 2.3, POST_Z + 0.03), (panel_w, 3.6, 0.26), WOOD, "Wood")
    m.cyl("HeadRail", (-POST_X + 0.2, 4.2, POST_Z + 0.03), (POST_X - 0.2, 4.2, POST_Z + 0.03), 0.4, WOOD_D, "Wood")
    pad_c, pad_s = (0, 3.0, 4.1), (6.1, 2.1, 0.45)
    m.ellipsoid("HeadPad", pad_c, pad_s, PAD, "Fabric")
    # the back of the headboard: a raised lighter inset in a dark bead frame, like the footboard's
    m.block("HeadBackBead", (0, 2.4, POST_Z + 0.165), (panel_w - 0.58, 2.76, 0.05), WOOD_D, "Wood", collide=False)
    m.block("HeadBackInset", (0, 2.4, POST_Z + 0.19), (panel_w - 0.74, 2.6, 0.06), WOOD_L, "Wood", collide=False)

    ha, hb, hc = pad_s[0] / 2, pad_s[1] / 2, pad_s[2] / 2

    def pad_surface(x, y):
        """Point on the pad's front face at (x, y) and its outward normal."""
        u = 1 - (x / ha) ** 2 - ((y - pad_c[1]) / hb) ** 2
        z = pad_c[2] - hc * math.sqrt(max(u, 0.0))
        n = (x / ha ** 2, (y - pad_c[1]) / hb ** 2, (z - pad_c[2]) / hc ** 2)
        k = math.sqrt(sum(c * c for c in n))
        return (x, y, z), tuple(c / k for c in n)

    # stars on the pad (glow with the night-light): flat round yellow dots of a few sizes, lying on the curved
    # cushion (turned to its surface), in the band the pillows leave visible
    stars = ((2.0, 3.55, 0.3), (-1.7, 3.65, 0.26), (0.5, 3.75, 0.2), (-0.55, 3.08, 0.24), (2.55, 3.05, 0.18),
             (-2.6, 3.2, 0.2), (1.12, 3.12, 0.16), (-1.2, 3.42, 0.14))
    for k, (x, y, d) in enumerate(stars):
        p, n = pad_surface(x, y)
        pos = tuple(p[i] + n[i] * 0.01 for i in range(3))
        m.ellipsoid("NightStar%d" % (k + 1), pos, (d, d, 0.08), MOON, "SmoothPlastic", collide=False, rot=P.frame_z(n))

    # ------------------------------------------------ night-light: a wooden roundel on the top rail, a night-sky disc
    # and a crescent moon (a yellow disc half-hidden by a sky-coloured disc in front of it: only the crescent shows,
    # and only the crescent glows when the yellow disc turns Neon)
    r = 1.12  # the roundel is a touch bigger than on the old 6-wide bed, to suit the wider headboard
    cy, cz = 4.33 + 0.75 * r, POST_Z + 0.03
    m.disc("MoonRoundel", (0, cy, cz), (0, 0, -1), 1.5 * r, 0.24, WOOD_D, "Wood")
    m.disc("MoonSky", (0, cy, cz - 0.13), (0, 0, -1), 1.28 * r, 0.06, PAD, "SmoothPlastic", collide=False)
    m.disc("NightLight", (0.07 * r, cy - 0.02 * r, cz - 0.17), (0, 0, -1), 0.94 * r, 0.06, MOON, "SmoothPlastic", collide=False)
    m.disc("MoonCover", (-0.2 * r, cy + 0.1 * r, cz - 0.21), (0, 0, -1), 0.8 * r, 0.06, PAD, "SmoothPlastic", collide=False)
    m.ellipsoid("NightStar9", (-0.32 * r, cy - 0.36 * r, cz - 0.17), (0.15, 0.15, 0.06), MOON, "SmoothPlastic", collide=False)
    m.disc("MoonBack", (0, cy, cz + 0.13), (0, 0, 1), 1.1 * r, 0.06, WOOD, "Wood", collide=False)
    m.pivot("NightLight", (0.07 * r, cy - 0.02 * r, cz - 0.2))

    # ------------------------------------------------ footboard: low panel, round rail, two raised insets
    m.block("FootPanel", (0, 1.15, -POST_Z), (panel_w, 1.4, 0.26), WOOD, "Wood")
    m.cyl("FootRail", (-POST_X + 0.2, 1.9, -POST_Z), (POST_X - 0.2, 1.9, -POST_Z), 0.36, WOOD_D, "Wood")
    inset_w = (panel_w - 0.9) / 2
    for side, s in (("L", 1), ("R", -1)):
        x = s * (inset_w / 2 + 0.2)
        m.block("FootInset" + side, (x, 1.12, -POST_Z - 0.14), (inset_w - 0.16, 0.8, 0.06), WOOD_L, "Wood", collide=False)
        m.block("FootInsetBead" + side, (x, 1.12, -POST_Z - 0.12), (inset_w, 0.96, 0.05), WOOD_D, "Wood", collide=False)

    # ------------------------------------------------ mattress + sheet
    m.block("Mattress", (0, (0.95 + MAT_TOP) / 2, 0), (2 * MAT_X, MAT_TOP - 0.95, 7.96), CREAM, "Fabric")
    for side, s in (("L", 1), ("R", -1)):
        m.cyl("MattressSeam" + side, (s * MAT_X, MAT_TOP - 0.06, BL_Z1), (s * MAT_X, MAT_TOP - 0.06, 3.98), 0.1, PATCH,
              "Fabric", collide=False)

    # ------------------------------------------------ quilt: top, drapes, rounded edges, patchwork
    bl_len = BL_Z1 - BL_Z0
    bl_zc = (BL_Z0 + BL_Z1) / 2
    m.block("BlanketTop", (0, (MAT_TOP - 0.02 + BLANKET_TOP) / 2, bl_zc), (2 * BL_X, BLANKET_TOP - MAT_TOP + 0.02, bl_len),
            QUILT, "Fabric")
    drape_t = BL_X - MAT_X + 0.02   # overlaps the mattress side by 0.02
    for side, s in (("L", 1), ("R", -1)):
        m.block("BlanketSide" + side, (s * (BL_X - drape_t / 2), 1.64, bl_zc), (drape_t, 1.04, bl_len), QUILT, "Fabric")
        m.cyl("BlanketEdge" + side, (s * (BL_X - 0.1), BLANKET_TOP - 0.11, BL_Z0 + 0.1), (s * (BL_X - 0.1), BLANKET_TOP - 0.11, BL_Z1),
              0.24, QUILT, "Fabric", collide=False)
    m.block("BlanketFront", (0, 1.64, BL_Z0 - 0.02), (2 * BL_X, 1.04, 0.14), QUILT, "Fabric")
    m.cyl("BlanketEdgeF", (-BL_X + 0.1, BLANKET_TOP - 0.11, BL_Z0 + 0.06), (BL_X - 0.1, BLANKET_TOP - 0.11, BL_Z0 + 0.06),
          0.24, QUILT, "Fabric", collide=False)
    # patchwork: light squares in a checker over the part of the quilt below the fold
    cols, rows = 4, 3
    z_a, z_b = BL_Z0 + 0.12, 0.3
    cw, rh = (2 * BL_X - 0.24) / cols, (z_b - z_a) / rows
    n = 0
    for ci in range(cols):
        for ri in range(rows):
            if (ci + ri) % 2 == 0:
                n += 1
                x = BL_X - 0.12 - cw * (ci + 0.5)
                z = z_a + rh * (ri + 0.5)
                m.block("Patch%d" % n, (x, BLANKET_TOP + 0.015, z), (cw - 0.04, 0.05, rh - 0.04), PATCH, "Fabric", collide=False)
    # the fold: the quilt's top end turned back toward the foot, showing its cream lining, with a rolled crease
    fold_a = 0.35
    m.block("FoldLining", (0, BLANKET_TOP + 0.04, (fold_a + BL_Z1) / 2), (2 * BL_X - 0.04, 0.1, BL_Z1 - fold_a), CREAM, "Fabric",
            collide=False)
    m.cyl("FoldStripe", (-BL_X + 0.04, BLANKET_TOP + 0.08, fold_a + 0.22), (BL_X - 0.04, BLANKET_TOP + 0.08, fold_a + 0.22), 0.07,
          QUILT, "Fabric", collide=False)
    m.cyl("FoldRoll", (-BL_X + 0.02, BLANKET_TOP - 0.02, BL_Z1), (BL_X - 0.02, BLANKET_TOP - 0.02, BL_Z1), 0.34, QUILT, "Fabric",
          collide=False)

    # ------------------------------------------------ pillows, leaning back on the headboard
    for i, s in ((1, 1), (2, -1)):
        pc = (s * PILLOW_X, MAT_TOP + 0.36, PILLOW_Z)
        m.ellipsoid("Pillow%d" % i, pc, (PILLOW_W, 0.8, 1.4), PILLOW, "Fabric", rot=(16, 0, 0))
        m.pivot("Pillow%d" % i, pc)
        m.pivot("Sleep%d" % i, (s * SLEEP_X, BLANKET_TOP, SLEEP_Z))

    m.attr("Cost", 1200)
    m.attr("Seats", 2)
    m.attr("Notes", "Double bed (primlib parts), 8 wide: 2 lying seats at Pivot_Sleep1/2 (x +-2.0, z 1.1; head toward +Z "
                    "onto Pillow1/2), crescent-moon night-light (NightLight + NightStar* go Neon while anyone sleeps). "
                    "Built by fun-builds/models/build_Bed.py.")
    return m.finish()
