"""build_items.py -- the nine New Map drop items (2026-09-23), one builder per item Key.

Palette / look: chunky toy potions (glass body + a bright Neon liquid + cork), a purple warp
pearl with a tilted halo, a holy-water vial with a gold cross stopper, golden / void seeds with a
sprout, a cracked glowing zombie egg and a gold redemption coin carrying a cucumber emblem.
Every builder returns Item.finish() (the parts record for the Studio installer). Items are
hand-held: 1.2 - 2.0 studs tall, standing on z = 0, facing +Y.
"""
import math
from itemlib import Item, rot

GLASS_T = 0.35
CORK = "a5703f"
GOLD = "f2c230"
GOLD_DARK = "c99a1a"
WHITE = "f4f4f4"


def speed_potion(D):
    it = Item(D, "SpeedPotion")
    it.ball("Body", (0, 0, 0.62), 0.62, "9fe3ff", "Glass", GLASS_T)
    it.ball("Liquid", (0, 0, 0.58), 0.50, "33d6ff", "Neon")
    it.cyl("Neck", (0, 0, 1.15), (0, 0, 1.55), 0.20, "a8e6ff", "Glass", 0.3)
    it.cyl("Lip", (0, 0, 1.52), (0, 0, 1.62), 0.26, "a8e6ff", "Glass", 0.3)
    it.cyl("Cork", (0, 0, 1.60), (0, 0, 1.86), 0.19, CORK)
    it.block("Label", (0, 0.57, 0.58), (0.50, 0.12, 0.30), WHITE)
    # a lightning bolt: two short yellow bars set at opposite tilts on the label
    it.block("BoltTop", (-0.05, 0.64, 0.66), (0.07, 0.05, 0.17), "ffd83a", "Neon", rotation=rot(0, -32, 0))
    it.block("BoltBottom", (0.05, 0.64, 0.50), (0.07, 0.05, 0.17), "ffd83a", "Neon", rotation=rot(0, -32, 0))
    # little wings either side of the flask
    it.ball("WingL", (-0.74, 0, 0.90), 0.26, "ffffff", scale=(1.3, 0.35, 0.7), rotation=rot(0, -28, 0))
    it.ball("WingR", (0.74, 0, 0.90), 0.26, "ffffff", scale=(1.3, 0.35, 0.7), rotation=rot(0, 28, 0))
    return it.finish()


def strength_potion(D):
    it = Item(D, "StrengthPotion")
    it.block("Body", (0, 0, 0.60), (0.90, 0.90, 1.20), "ffb0b0", "Glass", GLASS_T)
    it.block("Liquid", (0, 0, 0.55), (0.72, 0.72, 1.00), "ff3b3b", "Neon")
    it.block("Shoulder", (0, 0, 1.28), (0.55, 0.55, 0.18), "ffb0b0", "Glass", GLASS_T)
    it.cyl("Neck", (0, 0, 1.36), (0, 0, 1.62), 0.17, "ffc4c4", "Glass", 0.3)
    it.cyl("Lip", (0, 0, 1.60), (0, 0, 1.70), 0.22, "ffc4c4", "Glass", 0.3)
    it.cyl("Cork", (0, 0, 1.68), (0, 0, 1.92), 0.16, "8a5a2b")
    it.block("Label", (0, 0.46, 0.60), (0.62, 0.06, 0.50), WHITE)
    # dumbbell emblem lying across the label
    it.cyl("Bar", (-0.20, 0.51, 0.60), (0.20, 0.51, 0.60), 0.035, "2b2b30")
    it.ball("PlateL", (-0.21, 0.51, 0.60), 0.095, "2b2b30")
    it.ball("PlateR", (0.21, 0.51, 0.60), 0.095, "2b2b30")
    return it.finish()


def cash_potion(D):
    it = Item(D, "CashPotion")
    it.cyl("Body", (0, 0, 0.0), (0, 0, 1.15), 0.42, "c9ffc9", "Glass", GLASS_T)
    it.cyl("Liquid", (0, 0, 0.04), (0, 0, 0.95), 0.33, "3fe83f", "Neon")
    it.ball("Shoulder", (0, 0, 1.15), 0.42, "c9ffc9", "Glass", GLASS_T, scale=(1, 1, 0.45))
    it.cyl("Neck", (0, 0, 1.30), (0, 0, 1.62), 0.16, "d6ffd6", "Glass", 0.3)
    it.cyl("Cap", (0, 0, 1.60), (0, 0, 1.86), 0.20, GOLD, "Foil")
    it.cyl("CapBand", (0, 0, 1.70), (0, 0, 1.76), 0.215, GOLD_DARK, "Foil")
    # gold coin emblem on the front of the bottle
    it.disc("Coin", (0, 0.45, 0.62), (0, 1, 0), 0.23, 0.10, GOLD, "Foil")
    it.disc("CoinFace", (0, 0.505, 0.62), (0, 1, 0), 0.16, 0.03, GOLD_DARK, "Foil")
    it.block("CoinMark", (0, 0.53, 0.62), (0.06, 0.03, 0.20), "8b6b10")
    return it.finish()


def warp_pearl(D):
    it = Item(D, "WarpPearl")
    it.ball("Shell", (0, 0, 0.50), 0.45, "5a1f9a", "Glass", 0.25)
    it.ball("Core", (0, 0, 0.50), 0.30, "8f3bff", "Neon")
    it.disc("Halo", (0, 0, 0.50), (0.35, 0.20, 0.90), 0.66, 0.05, "d18cff", "Neon", 0.45)
    # three drifting shards around the pearl
    for i, (ang, z) in enumerate(((20, 0.78), (150, 0.36), (275, 0.62))):
        a = math.radians(ang)
        it.ball("Shard%d" % (i + 1), (math.cos(a) * 0.72, math.sin(a) * 0.72, z), 0.09, "d18cff", "Neon",
                scale=(0.55, 0.55, 1.6), rotation=rot(25 * math.cos(a), 25 * math.sin(a), 0))
    return it.finish()


def holy_water(D):
    it = Item(D, "HolyWater")
    it.ball("Body", (0, 0, 0.50), 0.50, "e8f6ff", "Glass", 0.3)
    it.ball("Liquid", (0, 0, 0.47), 0.40, "bfe9ff", "Neon")
    it.cyl("Neck", (0, 0, 0.95), (0, 0, 1.30), 0.16, "eef8ff", "Glass", 0.3)
    it.cyl("Lip", (0, 0, 1.28), (0, 0, 1.36), 0.21, "eef8ff", "Glass", 0.3)
    it.cyl("Stopper", (0, 0, 1.34), (0, 0, 1.50), 0.14, GOLD, "Foil")
    it.block("CrossPost", (0, 0, 1.74), (0.10, 0.10, 0.50), GOLD, "Foil")
    it.block("CrossBar", (0, 0, 1.82), (0.36, 0.10, 0.10), GOLD, "Foil")
    it.block("Label", (0, 0.45, 0.45), (0.34, 0.10, 0.22), WHITE)
    it.block("LabelCross1", (0, 0.51, 0.45), (0.04, 0.03, 0.15), "4aa3ff", "Neon")
    it.block("LabelCross2", (0, 0.51, 0.47), (0.12, 0.03, 0.04), "4aa3ff", "Neon")
    return it.finish()


def _seed(D, key, seed_hex, seed_mat, seed_t, glow_hex, stem_hex, leaf_hex, speck_hex):
    it = Item(D, key)
    it.ball("Seed", (0, 0, 0.45), 0.45, seed_hex, seed_mat, seed_t, scale=(0.85, 0.65, 1.0))
    if glow_hex:
        it.ball("Glow", (0, 0, 0.45), 0.26, glow_hex, "Neon")
    it.ball("Shine", (-0.14, -0.20, 0.66), 0.09, "fff6c8" if not glow_hex else "e0c4ff", seed_mat, scale=(1, 0.6, 1.2))
    it.cyl("Stem", (0, 0, 0.86), (0, 0, 1.16), 0.06, stem_hex)
    it.ball("LeafL", (-0.24, 0, 1.22), 0.23, leaf_hex, scale=(1.2, 0.45, 0.35), rotation=rot(0, 30, 0))
    it.ball("LeafR", (0.24, 0, 1.22), 0.23, leaf_hex, scale=(1.2, 0.45, 0.35), rotation=rot(0, -30, 0))
    if speck_hex:
        for i, (ang, z) in enumerate(((40, 0.30), (170, 0.70), (290, 0.48))):
            a = math.radians(ang)
            it.ball("Speck%d" % (i + 1), (math.cos(a) * 0.52, math.sin(a) * 0.46, z), 0.05, speck_hex, "Neon")
    return it.finish()


def golden_seed(D):
    return _seed(D, "GoldenSeed", GOLD, "Foil", 0.0, None, "55a446", "6ccf4a", None)


def void_seed(D):
    return _seed(D, "VoidSeed", "3a1560", "Glass", 0.35, "8f3bff", "4a2078", "7a3fc0", "c77dff")


def zombie_egg(D):
    it = Item(D, "ZombieEgg")
    it.ball("Egg", (0, 0, 0.74), 0.55, "5c7d3a", "SmoothPlastic", scale=(0.85, 0.85, 1.35))
    for i, (ang, z, r) in enumerate(((30, 0.40, 0.11), (130, 1.05, 0.09), (215, 0.62, 0.12), (320, 1.15, 0.08))):
        a = math.radians(ang)
        # spots sit on the egg's surface: radius at that height from the ellipsoid equation
        dz = (z - 0.74) / (0.55 * 1.35)
        rr = 0.55 * 0.85 * math.sqrt(max(0.0, 1 - dz * dz))
        it.ball("Spot%d" % (i + 1), (math.cos(a) * rr, math.sin(a) * rr, z), r, "3d5526", scale=(1, 1, 0.55),
                rotation=rot(0, 0, ang))
    # glowing cracks on the upper front
    for i, (x, z, tilt) in enumerate(((0.0, 0.98, 35), (0.14, 1.16, -40), (-0.12, 0.84, -25))):
        dz = (z - 0.74) / (0.55 * 1.35)
        y = 0.55 * 0.85 * math.sqrt(max(0.0, 1 - dz * dz - (x / (0.55 * 0.85)) ** 2))
        it.block("Crack%d" % (i + 1), (x, y - 0.01, z), (0.05, 0.07, 0.30), "9bff4a", "Neon", rotation=rot(0, tilt, 0))
    it.ball("Eye", (0.05, 0.40, 0.98), 0.10, "c8ff5a", "Neon")
    return it.finish()


def redemption_token(D):
    it = Item(D, "RedemptionToken")
    it.disc("Coin", (0, 0, 0.70), (0, 1, 0), 0.70, 0.16, GOLD, "Metal")
    it.disc("FaceFront", (0, 0.085, 0.70), (0, 1, 0), 0.56, 0.03, GOLD_DARK, "Metal")
    it.disc("FaceBack", (0, -0.085, 0.70), (0, 1, 0), 0.56, 0.03, GOLD_DARK, "Metal")
    # cucumber emblem across the front face, tilted like a banner
    it.ball("Cucumber", (0, 0.12, 0.70), 0.40, "55a446", scale=(1.0, 0.30, 0.30), rotation=rot(0, -28, 0))
    for i, t in enumerate((-0.22, 0.0, 0.22)):
        x = t * math.cos(math.radians(-28))
        z = 0.70 + t * math.sin(math.radians(28))
        it.ball("Bump%d" % (i + 1), (x, 0.20, z), 0.055, "3f8a33")
    it.ball("CucumberBack", (0, -0.12, 0.70), 0.40, "55a446", scale=(1.0, 0.30, 0.30), rotation=rot(0, 28, 0))
    return it.finish()


BUILDERS = [
    ("SpeedPotion", speed_potion),
    ("StrengthPotion", strength_potion),
    ("CashPotion", cash_potion),
    ("WarpPearl", warp_pearl),
    ("HolyWater", holy_water),
    ("GoldenSeed", golden_seed),
    ("VoidSeed", void_seed),
    ("ZombieEgg", zombie_egg),
    ("RedemptionToken", redemption_token),
]
