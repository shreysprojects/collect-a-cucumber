"""Aquarium (Home) -- a fish tank on a wooden cabinet, fun-builds HomeDecor 2026-09-24.

~6.6 wide x 7.4 tall (6.7 to the hood) x 3.2 deep. A wooden cabinet (plinth, two blue doors with raised panels +
brass knobs, a top slab with a rounded lip) carries a black-framed glass tank (6 x 3.4): translucent blue water with a
paler surface layer, sand gravel sloping up toward the back, coloured pebbles, a blue backdrop with a darker reef, a
stone castle ornament (two square towers with red pyramid roofs, crenellated keep, arched door, a yellow flag), a
treasure-chest bubbler (lid ajar, gold inside), grey rocks and four plant clumps (tall green vallisneria at both
back corners, a red clump in the back middle, a small lime clump at the front left). A Neon light bar glows along
the back just under the rim. On top: a black hood over the back half, glass cover plates over the front half with
a black FEED FLAP in the middle, and a yellow fish-food tub on the hood.
Glass and water are SmoothPlastic + Transparency, never the Glass material (Roblox hides transparent parts and
particles behind Glass-material parts - the water, the bubbles and the flakes would vanish).
The fish are NOT modelled: the client behaviour swims 5 runtime fish inside Pivot_TankMin / Pivot_TankMax.

Part names / pivots the behaviour relies on (FB/src/behaviours/*/Aquarium.lua):
    Plant<N>Leaf<M>        leaves (long axis = the part's local Y); each clump sways about Pivot_Plant<N>
    CastleFlag             waves about the flag pole (Pivot_Flag = the pole's axis point)
    ChestLid               the treasure-chest lid, hinged at Pivot_ChestHinge (build X axis); authored ajar
    FeedFlap, FeedFlapTab  the feeding flap in the cover, hinged at Pivot_FeedHinge (build X axis)
    Water, WaterTop        the water volume + its paler surface layer
    TankLight              the Neon light bar along the back of the tank, under the rim
    Pivot_TankMin/Max      inner water volume corners (x/z inside the glass, y gravel-front-top .. water surface)
    Pivot_WaterSurface     centre of the water surface
    Pivot_Feed             where the flakes drop onto the water (under the feed flap)
    Pivot_Bubbler          just in front of the chest lid's front edge (bubbles rise from here, clear of the lid)
    Pivot_Light            under the hood, above the water (the client's PointLight)
    Pivot_Castle           castle footprint centre on the gravel (fish keep clear of it)
"""
import math

WOOD = "8a5a2b"
WOOD_D = "6b4423"
BRASS = "f2c13d"
BLUE = "3f79d4"
BLUE_L = "6a9ef0"
INK = "23262c"
CREAM = "f2f0ea"
RED = "d9443c"
STONE = "b3aea4"
STONE_D = "8f8a82"
SAND = "e8c27a"
WATER = "3ea6f2"
WATER_TOP = "b9e6ff"
BACKDROP = "1f5fb8"
BACKDROP_D = "184a91"
GREEN = "3dbb45"
GREEN_D = "2a9a3a"
LIME = "8bd346"
RED_PLANT = "e0553a"
RED_PLANT_D = "c23a30"

CAB_TOP = 3.05          # cabinet top
TANK_X, TANK_Z = 3.02, 1.32   # tank outer half extents
GLASS_IN_X, GLASS_IN_Z = 2.92, 1.22
BASE_TOP = 3.30         # tank bottom frame top = water bottom
GRAVEL_TOP = 3.62       # front gravel top
WATER_Y = 5.94          # water surface
RIM_BOTTOM, RIM_TOP = 6.22, 6.42
SLOPE_Z0, SLOPE_Z1, SLOPE_H = -0.11, 1.19, 0.36


def gravel_y(z):
    t = min(1.0, max(0.0, (z - SLOPE_Z0) / (SLOPE_Z1 - SLOPE_Z0)))
    return GRAVEL_TOP + t * SLOPE_H


def leaf(m, P, name, base, length, width, yaw, tilt, color, thick=0.07, material="SmoothPlastic"):
    """A flat leaf ellipsoid: long axis = local Y rising from `base`, leaning `tilt` degrees toward the
    direction `yaw` (degrees about +Y; 0 = toward -Z, 90 = toward -X), broad face toward that direction."""
    R = P.angles(0, yaw, 0) @ P.angles(-tilt, 0, 0)
    from mathutils import Vector
    c = Vector(base) + R @ Vector((0, length / 2, 0))
    return m.ellipsoid(name, tuple(c), (width, length, thick), color, material, rot=R, collide=False, shadow=False)


def build(D, P):
    m = P.Model(D, "Aquarium", category="Home")

    # ------------------------------------------------ cabinet
    m.block("Plinth", (0, 0.21, 0.02), (6.2, 0.42, 2.7), WOOD_D, "Wood")
    m.block("Carcass", (0, 1.625, 0), (6.4, 2.45, 2.8), WOOD, "Wood")
    m.block("CabinetTop", (0, 2.95, 0), (6.6, 0.2, 3.0), WOOD, "Wood")
    m.cyl("CabinetLip", (-3.3, 2.95, -1.5), (3.3, 2.95, -1.5), 0.22, WOOD_D, "Wood")
    for side, s in (("L", 1), ("R", -1)):
        x = s * 1.56
        m.block("Door" + side, (x, 1.63, -1.44), (2.94, 2.06, 0.1), BLUE, "SmoothPlastic")
        m.block("DoorPanel" + side, (x, 1.63, -1.495), (2.3, 1.44, 0.05), BLUE_L, "SmoothPlastic", collide=False)
        m.ball("Knob" + side, (s * 0.3, 1.74, -1.56), 0.24, BRASS, "Metal", collide=False)

    # ------------------------------------------------ tank frame (near-black) + glass
    m.block("TankBase", (0, (CAB_TOP - 0.02 + BASE_TOP) / 2, 0), (2 * TANK_X, BASE_TOP - CAB_TOP + 0.02, 2 * TANK_Z), INK, "SmoothPlastic")
    post_h = RIM_BOTTOM + 0.005 - (BASE_TOP - 0.025)
    post_y = (RIM_BOTTOM + 0.005 + BASE_TOP - 0.025) / 2
    for i, (sx, sz) in enumerate(((1, -1), (-1, -1), (1, 1), (-1, 1))):
        m.block("Post%d" % (i + 1), (sx * 2.95, post_y, sz * 1.25), (0.14, post_h, 0.14), INK, "SmoothPlastic")
    rim_y = (RIM_BOTTOM + RIM_TOP) / 2
    m.block("RimFront", (0, rim_y, -1.25), (2 * TANK_X, RIM_TOP - RIM_BOTTOM, 0.14), INK, "SmoothPlastic")
    m.block("RimBack", (0, rim_y, 1.25), (2 * TANK_X, RIM_TOP - RIM_BOTTOM, 0.14), INK, "SmoothPlastic")
    m.block("RimL", (2.95, rim_y, 0), (0.14, RIM_TOP - RIM_BOTTOM, 2 * TANK_Z), INK, "SmoothPlastic")
    m.block("RimR", (-2.95, rim_y, 0), (0.14, RIM_TOP - RIM_BOTTOM, 2 * TANK_Z), INK, "SmoothPlastic")
    gh = RIM_BOTTOM + 0.01 - (BASE_TOP - 0.01)
    gy = (RIM_BOTTOM + 0.01 + BASE_TOP - 0.01) / 2
    m.block("GlassFront", (0, gy, -1.25), (5.8, gh, 0.06), "e6f6ff", "SmoothPlastic", transparency=0.86, reflectance=0.12)
    m.block("GlassL", (2.95, gy, 0), (0.06, gh, 2.4), "e6f6ff", "SmoothPlastic", transparency=0.86, reflectance=0.12)
    m.block("GlassR", (-2.95, gy, 0), (0.06, gh, 2.4), "e6f6ff", "SmoothPlastic", transparency=0.86, reflectance=0.12)
    m.block("Backdrop", (0, gy, 1.25), (5.8, gh, 0.06), BACKDROP, "SmoothPlastic")
    # a darker reef silhouette low on the backdrop (depth)
    m.ellipsoid("BackdropReef", (0.0, BASE_TOP + 0.75, 1.2), (5.74, 2.1, 0.06), BACKDROP_D, "SmoothPlastic", collide=False, shadow=False)

    # ------------------------------------------------ water
    wh = WATER_Y - BASE_TOP
    m.block("Water", (0, BASE_TOP + wh / 2, 0), (2 * 2.90, wh, 2 * 1.20), WATER, "SmoothPlastic", transparency=0.64,
            collide=False, shadow=False)
    m.block("WaterTop", (0, WATER_Y, 0), (2 * 2.89, 0.05, 2 * 1.19), WATER_TOP, "SmoothPlastic", transparency=0.72,
            collide=False, shadow=False)

    # ------------------------------------------------ gravel (sloping up toward the back) + pebbles
    m.block("Gravel", (0, (BASE_TOP - 0.02 + GRAVEL_TOP) / 2, 0), (2 * 2.89, GRAVEL_TOP - BASE_TOP + 0.02, 2 * 1.19), SAND, "Pebble")
    m.wedge("GravelSlope", (0, GRAVEL_TOP - 0.02 + SLOPE_H / 2, (SLOPE_Z0 + SLOPE_Z1) / 2), (2 * 2.89, SLOPE_H, SLOPE_Z1 - SLOPE_Z0),
            SAND, "Pebble")
    for name, x, z, d, col in (("PebblePink", -0.95, -0.92, 0.18, "f28cb1"), ("PebbleBlue", 0.35, -0.78, 0.16, BLUE_L),
                               ("PebbleYellow", 1.05, -1.0, 0.17, BRASS), ("PebbleWhite", -1.7, -0.62, 0.15, CREAM)):
        m.ball(name, (x, GRAVEL_TOP + d * 0.25, z), d, col, "SmoothPlastic", collide=False, shadow=False)

    # ------------------------------------------------ castle ornament (back left)
    cx, cz = -1.55, 0.66
    cy = gravel_y(cz) - 0.1
    m.pivot("Castle", (cx, cy, cz))
    keep_h = 0.9
    tl_h, tr_h = 1.22, 1.06
    m.block("CastleKeep", (cx, cy + keep_h / 2, cz), (0.82, keep_h, 0.52), STONE, "Slate", collide=False)
    for k, dx in enumerate((-0.3, 0.0, 0.3)):
        m.block("CastleCrenel%d" % (k + 1), (dx + cx, cy + keep_h + 0.07, cz - 0.1), (0.17, 0.16, 0.3), STONE, "Slate", collide=False)
    # square towers with red pyramid roofs (4 corner wedges each: a CornerWedge's apex sits over its (+X, -Z) corner)
    quads = ((0, -1, 1), (90, 1, 1), (180, 1, -1), (-90, -1, -1))  # yaw, quadrant x sign, quadrant z sign
    roof_h = 0.44
    for side, tx, a, h in (("L", cx - 0.53, 0.5, tl_h), ("R", cx + 0.53, 0.44, tr_h)):
        m.block("CastleTower" + side, (tx, cy + h / 2, cz), (a, h, a), STONE, "Slate", collide=False)
        r = a + 0.14
        for k, (yaw, sx, sz) in enumerate(quads):
            m.corner("CastleRoof%s%d" % (side, k + 1), (tx + sx * r / 4, cy + h - 0.02 + roof_h / 2, cz + sz * r / 4), (r / 2, roof_h, r / 2),
                     RED, "SmoothPlastic", rot=(0, yaw, 0), collide=False)
    fx = cx - 0.53
    ftop = cy + tl_h - 0.02 + roof_h
    m.cyl("CastlePole", (fx, ftop - 0.08, cz), (fx, ftop + 0.3, cz), 0.05, INK, "SmoothPlastic", collide=False, shadow=False)
    m.block("CastleFlag", (fx + 0.16, ftop + 0.21, cz), (0.3, 0.17, 0.05), BRASS, "SmoothPlastic", collide=False, shadow=False)
    m.pivot("Flag", (fx, ftop + 0.21, cz))
    front = cz - 0.26
    m.block("CastleDoor", (cx, cy + 0.1 + 0.17, front - 0.01), (0.3, 0.34, 0.05), INK, "SmoothPlastic", collide=False, shadow=False)
    m.cyl("CastleDoorArch", (cx, cy + 0.44, front - 0.04), (cx, cy + 0.44, front + 0.02), 0.3, INK, "SmoothPlastic", collide=False, shadow=False)
    m.block("CastleWindow", (cx - 0.53, cy + 0.8, cz - 0.26), (0.1, 0.18, 0.05), INK, "SmoothPlastic", collide=False, shadow=False)

    # ------------------------------------------------ treasure chest bubbler (front right)
    bx, bz = 1.72, -0.36
    by = GRAVEL_TOP - 0.03
    m.block("ChestBody", (bx, by + 0.2, bz), (0.72, 0.4, 0.46), WOOD_D, "Wood", collide=False)
    m.block("ChestBand", (bx, by + 0.27, bz), (0.74, 0.08, 0.48), BRASS, "Metal", collide=False, shadow=False)
    m.block("ChestLock", (bx, by + 0.3, bz - 0.25), (0.12, 0.15, 0.05), BRASS, "Metal", collide=False, shadow=False)
    m.ellipsoid("ChestGold", (bx, by + 0.4, bz), (0.6, 0.16, 0.36), BRASS, "Metal", collide=False, shadow=False)
    hinge = (bx, by + 0.4, bz + 0.23)
    ajar = 24.0
    a = math.radians(ajar)
    ly, lz = 0.07, -0.24          # lid centre relative to the hinge, closed
    m.block("ChestLid", (bx, hinge[1] + ly * math.cos(a) - lz * math.sin(a), hinge[2] + ly * math.sin(a) + lz * math.cos(a)),
            (0.76, 0.14, 0.48), WOOD_D, "Wood", rot=(ajar, 0, 0), collide=False)
    m.pivot("ChestHinge", hinge)
    m.pivot("Bubbler", (bx, by + 0.43, bz - 0.30))   # in front of the lid's front edge (z -0.61 shut): clear of the lid in every pose

    # ------------------------------------------------ rocks
    m.ellipsoid("RockBack", (0.05, gravel_y(0.55) + 0.02, 0.55), (0.75, 0.42, 0.5), "8a8f99", "Slate", collide=False)
    m.ellipsoid("RockFront", (2.45, GRAVEL_TOP + 0.08, -0.72), (0.52, 0.36, 0.44), "9aa0aa", "Slate", collide=False)

    # ------------------------------------------------ plants (every leaf's long axis = its local Y)
    # yaw: 0 leans toward the front (-Z), 90 toward -X (viewer's right), -90 toward +X (viewer's left), 180 back
    clumps = [
        # N, base (x, z), leaves: (length, width, yaw, tilt, colour)
        (1, (2.35, 0.78), [(2.0, 0.26, 60, 10, GREEN), (1.75, 0.24, 20, 14, GREEN_D), (1.95, 0.26, 110, 16, GREEN_D),
                           (1.45, 0.24, 150, 8, GREEN), (1.6, 0.25, -10, 22, GREEN)]),
        (2, (-2.55, 0.92), [(2.05, 0.26, -60, 8, GREEN_D), (1.8, 0.24, -25, 16, GREEN), (1.6, 0.25, -110, 14, GREEN),
                            (1.3, 0.24, -80, 26, GREEN_D)]),
        (3, (0.62, 0.9), [(1.25, 0.36, 40, 16, RED_PLANT), (1.05, 0.34, -30, 20, RED_PLANT_D), (1.4, 0.36, 5, 6, RED_PLANT),
                          (0.9, 0.32, 150, 22, RED_PLANT_D)]),
        (4, (-2.5, -0.82), [(0.72, 0.28, -60, 18, LIME), (0.6, 0.26, 10, 24, LIME), (0.55, 0.26, -130, 22, "72bd35")]),
    ]
    for n, (x, z), leaves in clumps:
        base = (x, gravel_y(z) - 0.05, z)
        m.pivot("Plant%d" % n, base)
        for k, (length, width, yaw, tilt, col) in enumerate(leaves):
            leaf(m, P, "Plant%dLeaf%d" % (n, k + 1), base, length, width, yaw, tilt, col)

    # ------------------------------------------------ light hood (back half), cover glass + feed flap (front half)
    hz0, hz1 = -0.08, 1.33
    m.block("Hood", (0, RIM_TOP + 0.13, (hz0 + hz1) / 2), (2 * TANK_X + 0.04, 0.3, hz1 - hz0), INK, "SmoothPlastic")
    m.cyl("HoodNose", (-TANK_X - 0.02, RIM_TOP + 0.13, hz0), (TANK_X + 0.02, RIM_TOP + 0.13, hz0), 0.3, INK, "SmoothPlastic")
    m.block("HoodStripe", (0, RIM_TOP + 0.29, 0.5), (2 * TANK_X - 0.3, 0.05, 0.14), BLUE, "SmoothPlastic", collide=False, shadow=False)
    m.block("TankLight", (0, RIM_BOTTOM - 0.05, 1.0), (5.6, 0.1, 0.3), "e8f7ff", "Neon", collide=False, shadow=False)
    m.pivot("Light", (0, RIM_BOTTOM - 0.25, 0.3))
    cover_z0, cover_z1 = -1.31, hz0 - 0.1
    cz_mid = (cover_z0 + cover_z1) / 2
    for side, s in (("L", 1), ("R", -1)):
        x0, x1 = 0.63, 2.99
        m.block("Cover" + side, (s * (x0 + x1) / 2, RIM_TOP + 0.02, cz_mid), (x1 - x0, 0.05, cover_z1 - cover_z0), "e6f6ff", "SmoothPlastic",
                transparency=0.78, reflectance=0.12)
    flap_w = 1.22
    m.block("FeedFlap", (0, RIM_TOP + 0.03, cz_mid), (flap_w, 0.06, cover_z1 - cover_z0), INK, "SmoothPlastic")
    m.block("FeedFlapTab", (0, RIM_TOP + 0.05, cover_z0 - 0.05), (0.36, 0.06, 0.14), BRASS, "SmoothPlastic", collide=False)
    m.pivot("FeedHinge", (0, RIM_TOP + 0.03, cover_z1))
    m.pivot("Feed", (0, WATER_Y, cz_mid))

    # ------------------------------------------------ fish-food tub on the hood
    tx, tz = 2.25, 0.62
    ty = RIM_TOP + 0.28
    m.cyl("FoodTub", (tx, ty - 0.02, tz), (tx, ty + 0.56, tz), 0.54, BRASS, "SmoothPlastic", collide=False)
    m.cyl("FoodLabel", (tx, ty + 0.12, tz), (tx, ty + 0.38, tz), 0.56, CREAM, "SmoothPlastic", collide=False)
    m.cyl("FoodLid", (tx, ty + 0.54, tz), (tx, ty + 0.68, tz), 0.6, RED, "SmoothPlastic", collide=False)

    # ------------------------------------------------ behaviour data
    m.pivot("TankMin", (-GLASS_IN_X + 0.02, GRAVEL_TOP, -GLASS_IN_Z + 0.02))
    m.pivot("TankMax", (GLASS_IN_X - 0.02, WATER_Y, GLASS_IN_Z - 0.02))
    m.pivot("WaterSurface", (0, WATER_Y, 0))
    m.attr("Cost", 1500)
    m.attr("DisplayName", "Aquarium")
    m.attr("Notes", "Fish tank on a wooden cabinet (primlib parts, fun-builds HomeDecor). The client swims 5 runtime fish "
                    "inside Pivot_TankMin/Max, bubbles rise from the treasure chest (Pivot_Bubbler, ChestLid pops), "
                    "Plant<N>Leaf<M> sway about Pivot_Plant<N>, the TankLight glows; prompt 'Feed fish' opens the "
                    "FeedFlap and sprinkles flakes on the water - the fish rush up to them. "
                    "Built by fun-builds/models/build_Aquarium.py.")
    return m.finish()
