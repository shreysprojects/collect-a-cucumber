"""
Generate the FINAL concrete design tables for the Collect a Cucumber economy
redesign -> final-design.json (consumed by the report + the Lua implementation).
Numbers frozen from economy_sim.py v2 calibration (2026-08-28).
"""
import json, math

def sig3(x):
    if x <= 0: return 0
    e = max(0, math.floor(math.log10(x)) - 2)
    return int(round(x / 10**e) * 10**e)

ZONES = ["Spawn", "Desert", "Samurai", "Farm", "Snow", "Underwater", "Volcano", "Narmek"]
ZONE_V  = [1, 8, 64, 512, 4096, 32768, 262144, 2097152]  # exact 8^i
ZONE_HP = [1, 13, 165, 2_050, 24_500, 285_000, 3_250_000, 36_500_000]

# ---------------- per-zone breakable types (keep existing names/templates; retune numbers)
# tier anchors: (valX, hpX, weightShare)
TIERS = [(1.0, 1.0, 0.58), (2.5, 1.9, 0.25), (7.0, 3.5, 0.10), (18.0, 6.0, 0.055), (45.0, 10.0, 0.015)]
EXISTING_TYPES = {  # regular (non-sliced) type names, in ascending current value order
    "Spawn":      ["Cucumber", "Slice Stack", "Vined Cucumber", "Flowered Cucumber", "Cucumber Tree"],
    "Desert":     ["Prickly Cucumber", "Sliced Cucumber", "Sun-Baked Cucumber", "Wrapped Cucumber", "Cactus Cucumber", "Desert Palm", "Sandstone Tree"],
    "Samurai":    ["Katana Cucumber", "Bamboo Cucumber", "Lantern Cucumber", "Bamboo Grove", "Torii Gate", "Sakura Tree"],
    "Farm":       ["Muddy Cucumber", "Crate Cucumber", "Windmill Plant", "Hay Bale", "Cucumber Tree"],
    "Snow":       ["Snowcap Cucumber", "Snowball Slice", "Crystal Cucumber", "Frozen Cucumber", "Snow Tree", "Icicle Tree", "Frozen Tree"],
    "Underwater": ["Seaweed Cucumber", "Shell Slice", "Coral Cucumber", "Pearl Cucumber", "Kelp Tree", "Bubble Tree", "Coral Tree"],
    "Volcano":    ["Charred Cucumber", "Molten Cucumber", "Flame Cucumber", "Obsidian Tree", "Volcano Cucumber", "Magma Tree"],
    "Narmek":     ["Meteor Cucumber", "Planet Slice", "Astronaut Cucumber", "Neon Alien Cucumber", "Moon Tree", "Alien Tree", "Galaxy Tree"],
}
SLICED = {  # zone -> sliced quota type name
    "Spawn": "Sliced Cucumber", "Desert": "Sun-Dried Slice", "Samurai": "Sliced Cucumber",
    "Farm": "Cucumber Basket", "Snow": "Frozen Slice", "Underwater": "Bubble Slice",
    "Volcano": "Molten Slice", "Narmek": "Moon Slice",
}
BASE_V, BASE_HP = 8, 30

def interp_tiers(n):
    """spread the 5 anchor tiers across n types (log-interpolated)"""
    out = []
    for k in range(n):
        pos = k * 4 / (n - 1) if n > 1 else 0
        i0, frac = int(min(pos, 3.999)), min(pos, 3.999) - int(min(pos, 3.999))
        v = TIERS[i0][0] * (TIERS[i0+1][0] / TIERS[i0][0]) ** frac if i0 < 4 else TIERS[4][0]
        h = TIERS[i0][1] * (TIERS[i0+1][1] / TIERS[i0][1]) ** frac if i0 < 4 else TIERS[4][1]
        out.append((v, h))
    # weights: geometric decay matched to anchor shares, normalized to 100
    raw = [0.58 * (0.015/0.58) ** (k/(n-1)) for k in range(n)] if n > 1 else [1]
    tot = sum(raw)
    w = [r / tot * 100 for r in raw]
    return out, w

types_out = {}
for zi, z in enumerate(ZONES):
    names = EXISTING_TYPES[z]
    vh, w = interp_tiers(len(names))
    lst = []
    for k, name in enumerate(names):
        v, h = vh[k]
        lst.append({
            "name": name,
            "weight": max(1, round(w[k])),
            "hp": max(6, round(BASE_HP * h)),
            "reward": max(1, sig3(BASE_V * v)),  # zone-FREE: engine multiplies by Orb*Multi (8^tier) at Break
            "bonusCoins": max(1, round(2 * v)),      # small direct coin drips, zone Multi scales later
            "tree": k == len(names) - 1,
        })
    sliced = {"name": SLICED[z], "weight": 25, "hp": 8, "reward": 3, "bonusCoins": 1}
    types_out[z] = {"sliced": sliced, "regular": lst}

# ---------------- materials & mutations
materials = {
    "GOLDEN":  {"chance": 0.04, "valueMult": 12, "hpMult": 3, "coinMult": 10, "goldenHourMult": 4},
    "DIAMOND": {"chance": 0.006, "valueMult": 50, "hpMult": 5, "coinMult": 25},
}
mutations = {
    "mixTotalChance": 0.0305,
    "mixNote": "ALWAYS-ON weighted mix since 2026-08-28 later (daily rotation removed): per-spawn odds below",
    "mixChances": {"NEON": 0.01, "SHADOW": 0.01, "FROZEN": 0.004, "RADIOACTIVE": 0.0025, "ROYAL": 0.0015, "MOLTEN": 0.0025},
    "rotation": {   # daily rotation (6-day cycle), per-day multiplier = appointment variety
        "NEON": 15, "SHADOW": 15, "FROZEN": 20, "RADIOACTIVE": 25, "ROYAL": 40, "MOLTEN": 25,
    },
    "VOID":      {"chance": 1/1200,  "valueMult": 150, "color": [90, 30, 140], "announce": False},
    "PRISMATIC": {"chance": 1/20000, "valueMult": 750, "announce": True},
    "lightningChargedMult": [40, 80],
    "lightningIntervalSeconds": [120, 240],
    "stackRule": "material x mutation multiply; product capped at JACKPOT_STACK_CAP",
    "jackpotStackCap": 5000,
}

# ---------------- pickaxes (19, sequential; Wood free = 3 dmg)
PICK_NAMES = ["Stone Pickaxe","Bronze Pickaxe","Iron Pickaxe","Steel Pickaxe","Gold Pickaxe",
    "Emerald Pickaxe","Ruby Pickaxe","Amethyst Pickaxe","Diamond Pickaxe","Valentine Pickaxe",
    "Magma Pickaxe","VoidNeon Pickaxe","CosmicIce Pickaxe","YinYang Pickaxe","Galaxy Pickaxe",
    "SolarFlare Pickaxe","BloodMoon Pickaxe","Rainbow Pickaxe"]
# NOTE: live ladder is Wood + 18 more (19 total incl. Wood). Wood stays order 0 / free.
PICK_PRICE  = [400, 6e3, 60e3, 500e3, 2.5e6, 10e6, 60e6, 300e6, 2e9, 10e9, 60e9, 250e9, 1e12, 6e12, 40e12, 200e12, 1e15, 5e15]
PICK_DAMAGE = [5, 14, 38, 105, 290, 800, 2200, 6000, 16500, 45000, 124000, 340000, 935000, 2.6e6, 7e6, 19.5e6, 53.5e6, 147e6]
WOOD = {"name": "Wood Pickaxe", "order": 0, "price": 0, "damage": 3}
pickaxes = [WOOD] + [
    {"name": PICK_NAMES[i], "order": i + 1, "price": int(PICK_PRICE[i]), "damage": int(PICK_DAMAGE[i]), "range": 6 + i}
    for i in range(18)
]

# ---------------- doors & rebirth
doors = [
    {"zone": "Spawn",      "price": 0,        "minRebirths": 0},
    {"zone": "Desert",     "price": 60e3,     "minRebirths": 0},
    {"zone": "Samurai",    "price": 5e6,      "minRebirths": 0},
    {"zone": "Farm",       "price": 300e6,    "minRebirths": 1},
    {"zone": "Snow",       "price": 60e9,     "minRebirths": 2},
    {"zone": "Underwater", "price": 5e12,     "minRebirths": 3},
    {"zone": "Volcano",    "price": 400e12,   "minRebirths": 4},
    {"zone": "Narmek",     "price": 25e15,    "minRebirths": 5},
]
# zone Orb/Multi fields: Orb*Multi must equal ZONE_V; keep Multi modest (BonusCoins scaler)
door_orbs = []
for zi in range(8):
    multi = 2 ** zi
    door_orbs.append({"zone": ZONES[zi], "Multi": multi, "Orb": 4 ** zi})

REBIRTH = {
    "incomeMultiplier": "2^R on Cucumbers earned (replaces 1+0.5R)",
    "coinSideMultiplier": "REMOVED (sell is flat 1:1; kills the quadratic double-dip)",
    "costs": [90e6, 20e9, 1.5e12, 100e12, 7.5e15] + [7.5e15 * 2.9 ** (r - 4) for r in range(5, 50)],
    "max": 50,
    "keeps": "pickaxes, pets, upgrades, vault, shards (unchanged)",
    "resets": "Cukes, Coins, doors (unchanged)",
    "vaultSlotPerRebirth": 1,
}

# ---------------- eggs & pets
EGG_DEFS = [  # (name, zone, price, floorM1, floorDmg)
    ("Basic Egg",  "Spawn",      250,    1.0,  2),
    ("Desert Egg", "Desert",     100e3,  3.5,  25),
    ("Samurai Egg","Samurai",    3e6,    10,   280),
    ("Farm Egg",   "Farm",       200e6,  30,   3200),
    ("Frozen Egg", "Snow",       10e9,   90,   38e3),
    ("Ocean Egg",  "Underwater", 500e9,  275,  430e3),
    ("Lava Egg",   "Volcano",    30e12,  800,  5e6),
    ("Narmek Egg", "Narmek",     2e15,   2500, 60e6),
]
# within-egg spread (mult of floor) + odds
SPREAD = [(1.0, 40), (1.25, 30), (1.6, 15), (2.1, 9), (2.8, 5), (4.5, 1)]
POOLS = {  # existing pet names per egg, ascending power order
    "Basic Egg":  ["Cat", "Dog", "Bunny", "Wolf", "Tabby", "Fox"],
    "Desert Egg": ["Barrel", "Treasure Gem", "Cannon", "Chest", "Desert Overlord", "Cactus"],
    "Samurai Egg":["Dog Ninja", "Good Ninja", "Evil Ninja", "Good Samurai", "Evil Samurai", "Sensei"],
    "Farm Egg":   ["Hay", "Bird", "Panda", "Cow", "Pig", "Farmer"],
    "Frozen Egg": ["Red Snowman", "Blue Snowman", "Frozen Dragon", "Frozen Hydra", "Frozen Ice Shock", "Frozen Gem"],
    "Ocean Egg":  ["Oceanic Dog", "Oceanic Kitty", "Oceanic Bunny", "Oceanic Bear", "Ocean Dragon", "Atlantic Hydra"],
    "Lava Egg":   ["Lava Plume", "Lava Golem", "Lava Veltal", "Lava Trio", "Lava Dragon", "Demon Dog"],
    "Narmek Egg": ["Moon Bunny", "Satellite Pup", "Alien Slime", "Meteor Moth", "Nebula Fox", "Cosmo Cat"],
}
RARITY_BY_SLOT = ["Common", "Common", "Uncommon", "Rare", "Legendary", "Mythical"]

def pnum(x):
    """pretty pet stat"""
    if x < 10: return round(x * 2) / 2
    e = 10 ** (math.floor(math.log10(x)) - 1)
    return round(x / e) * e

eggs, pets = [], []
for name, zone, price, fm1, fdmg in EGG_DEFS:
    pool = []
    for slot, ((mult, pct), pet) in enumerate(zip(SPREAD, POOLS[name])):
        m1, dmg = pnum(fm1 * mult), pnum(fdmg * mult)
        pool.append({"pet": pet, "pct": pct})
        pets.append({"name": pet, "rarity": RARITY_BY_SLOT[slot], "source": name,
                     "Multi1": m1, "Damage": dmg, "Multi2": pnum(1 + m1 * 0.1)})
    eggs.append({"name": name, "zone": zone, "price": int(price), "pool": pool})
# secrets stay carved out of the floor pet's odds (unchanged mechanics)
pets.append({"name": "Gregory", "rarity": "Mythical", "source": "Basic Egg secret 1/50,000 (pity 25)",
             "Multi1": 50, "Damage": 10_000, "Multi2": 6})

# Food Cuke Egg (playtime-only): band ~A2-A3
FOOD = [("Popcorn Cuke",4,60,30),("Cotton Candy Cuke",5,80,24),("Lollipop Cuke",6.5,110,18),
        ("Fried Egg Cuke",8,150,12),("Cupcake Cuke",10,210,8),("Taco Cuke",13,280,4),
        ("Watermelon Cuke",16,380,2.5),("Burger Cuke",20,500,1),("Pizza Cuke",28,900,0.49),
        ("Ice Cream Cuke",40,3000,0.01)]
for n, m1, d, pct in FOOD:
    pets.append({"name": n, "rarity": "varies", "source": "Food Cuke Egg (playtime)", "Multi1": m1, "Damage": d, "Multi2": pnum(1+m1*0.1)})
eggs.append({"name": "Food Cuke Egg", "zone": None, "price": 0, "pool": [{"pet": n, "pct": p} for n, _, _, p in FOOD]})

# specials
SPECIALS = [
    ("Lil Pickle",        "tutorial",                       2,    3),
    ("OG Pickle",         "launch exclusive",               3,    8),
    ("Blazing Pickle",    "playtime 30m (ONE-TIME now)",    25,   5_000),
    ("King Cuke",         "playtime 90m (ONE-TIME now)",    60,   25_000),
    ("Gregory-NOTE",      None, None, None),  # placeholder removed below
    ("Red Demon",         "Robux product / Starter Pack",   500,  500_000),
    ("Purple Hydra",      "Robux product",                  800,  900_000),
    ("Heavenly Angel",    "Robux product",                  800,  900_000),
    ("Golden Cucumber",   "season champion (Cukes)",        1200, 2_000_000),
    ("Solid Gold Coin",   "season champion (Coins)",        600,  800_000),
    ("Silver Pickle",     "season top-10",                  300,  300_000),
    ("Diamond Gherkin",   "unobtainable (future)",          600,  800_000),
]
BOSS_PETS = [("Colossal Cucumber","Spawn"),("Cactus Colossus","Desert"),("Shogun Colossus","Samurai"),
             ("Harvest Colossus","Farm"),("Frozen Colossus","Snow"),("Abyssal Colossus","Underwater"),
             ("Magma Colossus","Volcano"),("Cosmic Colossus","Narmek")]
for n, src, m1, d in SPECIALS:
    if m1 is None: continue
    pets.append({"name": n, "rarity": "Special/Omega", "source": src, "Multi1": m1, "Damage": d, "Multi2": pnum(1+m1*0.1)})
for i, (n, z) in enumerate(BOSS_PETS):
    fm1 = [1.0, 3.5, 10, 30, 90, 275, 800, 2500][i]
    fd  = [2, 25, 280, 3200, 38e3, 430e3, 5e6, 60e6][i]
    pets.append({"name": n, "rarity": "Special (boss forge, 10 shards)", "source": f"{z} boss",
                 "Multi1": pnum(fm1 * 3.2), "Damage": pnum(fd * 4), "Multi2": pnum(1 + fm1 * 0.32)})

# ---------------- bosses
BOSS_HPBASE = [3500, 4000, 4500, 5000, 5500, 6500, 7500, 8500]
bosses = [{"zone": ZONES[i], "hpBase": BOSS_HPBASE[i], "reward": 900, "bonusCoins": 300,
           "note": "pool = 900 * ZONE_V * 6 split by contribution; escape pays HALF rate now"} for i in range(8)]

# ---------------- vault & misc systems
vault = {
    "earnRate": "rate/s = max(1, floor(breakValue(record) / 220)) — each stored cucumber re-earns its break value every ~3.7 min",
    "breakValue": "typeReward * materialMult * mutationMult (record's own properties, zone-inflated)",
    "accrualMultiplier": "x (1 + Pets.Multi1) x 2^Rebirths read LIVE from the owner (was flat) — snapshot persisted as VaultMultSnap for offline math",
    "upgrades": "cost = Rate x 500 x 1.35^(L-1) Cukes, L<=20, rate x1.18^(L-1) (UNCHANGED)",
    "offline": "50% first 6h / 30% next, 6h-equivalent cap (UNCHANGED), applied to rate x VaultMultSnap",
    "questQuoteCap": "vault-coin quest/minigame quotes capped at TimeSkipRate-equivalent for same seconds",
    "migration": "LoadVault recomputes each record's Rate from live tables (RateV=2 stamp); Accrued/OfflineCash preserved",
}
upgrades = [
    {"name": "Vault slots",      "prices": [500e3, 25e6, 2e9],  "max": 3},
    {"name": "Pet equips",       "prices": [25e3, 100e3, 400e3], "max": 3},
    {"name": "Smashes required", "prices": [50e3, 1e6, 30e6],   "max": 3},
]
fixes = [
    "EvolveService: validate 3 same-name Normal copies + ownership BEFORE charging; evolve cost = 2x source egg price (was flat 600k)",
    "PlaytimeRewards: free rebirth + Blazing Pickle + King Cuke become ONE-TIME (persisted); repeat sessions get time-skip grants instead",
    "StarterPortalService: progress reset moved from loadCooldown (every join) to startCooldown (parity with other portals)",
    "Escaped bosses pay HALF the per-HP kill rate (was full)",
    "SellCarried pays flat (MultipliersApplied) so the shown card value == paid value",
    "SellAll: rebirth coin multiplier REMOVED (1:1; income already scales 2^R on the cuke side)",
    "Quest/minigame vault-coin quotes capped (see vault.questQuoteCap)",
    "GoldenHour churn filter: base HP <= zone common HP (was flat 30; no-oped outside Spawn)",
    "Index milestone payout: 500*N -> scales with sqrt of current zone value, capped (was unbounded flat faucet)",
    "NumberController.SuffixNumber: nil-guard + scientific fallback past table end; VaultService Abbrev unified onto NumberController",
]
retention = {
    "firstSession": "tutorial gift 2,500 Coins ~= 10 Basic Egg hatches; Stone Pickaxe at 400 within ~1 min; Desert door 60K at ~6-8 min",
    "jackpotCadence": "DIAMOND 1/167 (~every 8 min), daily mutation 1/50, VOID 1/1500 (~1.5/h), PRISMATIC 1/25,000 (~1/day of active play, server-announced)",
    "singleDropBudget": "largest realistic jackpot (PRISMATIC common) ~= 10 min of income; stacked cap 5000x ~= 1.1h of income",
}

design = {
    "_meta": {"date": "2026-08-28", "sim": "economy_sim.py v2", "targets": {"A2": "7m", "A3": "27m", "A4": "72m", "A5": "3h", "A6": "6h", "A7": "10.3h", "A8": "16.7h"},
              "simResults": {"average": "A2@6m A3@29m A4@1.0h A5@2.7h A6@5.4h A7@10.1h A8@17.2h", "casual": "A7@15.4h (A8 ~24h)", "lucky": "A8@12.2h", "optimized(whale)": "A8@1.9h"}},
    "zoneLadders": {"ZONE_V": ZONE_V, "ZONE_HP": ZONE_HP, "doorOrbs": door_orbs},
    "types": types_out,
    "materials": materials,
    "mutations": mutations,
    "pickaxes": pickaxes,
    "doors": doors,
    "rebirth": {k: v for k, v in REBIRTH.items()},
    "eggs": eggs,
    "pets": pets,
    "bosses": bosses,
    "vault": vault,
    "upgrades": upgrades,
    "fixes": fixes,
    "retention": retention,
}
out = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\economy-redesign-2026-08-28\final-design.json"
with open(out, "w") as f:
    json.dump(design, f, indent=1)
print("wrote", out)
print("pets:", len(pets), " eggs:", len(eggs))
for z in ZONES:
    t = types_out[z]
    print(z, "->", [(x["name"], x["weight"], x["hp"], x["reward"]) for x in t["regular"]][:3], "... tree:", t["regular"][-1]["reward"])
