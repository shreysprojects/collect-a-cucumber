"""
Patch the dumped dictionary sources with the final-design values.
Reads:  backups/EconomyRedesign_2026-08-28/scripts/*.lua  +  final-design.json
Writes: economy-redesign-2026-08-28/patched/*.lua
Verifies every intended replacement actually happened; prints a summary.
"""
import json, re, os, sys

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames"
SRC  = os.path.join(ROOT, "backups", "EconomyRedesign_2026-08-28", "scripts")
OUT  = os.path.join(ROOT, "economy-redesign-2026-08-28", "patched")
os.makedirs(OUT, exist_ok=True)
design = json.load(open(os.path.join(ROOT, "economy-redesign-2026-08-28", "final-design.json")))

def lua_num(x):
    if x == int(x): return str(int(x))
    return repr(round(x, 4))

def load(name): return open(os.path.join(SRC, name), encoding="utf-8").read()
def save(name, s):
    with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as f: f.write(s)

problems = []

def block_of(src, key):
    """return (start, end) of the table block  ["key"] = { ... };  (balanced braces)"""
    m = re.search(r'\[\"' + re.escape(key) + r'\"\]\s*=\s*\{', src)
    if not m: return None
    i = m.end() - 1; depth = 0
    for j in range(i, len(src)):
        if src[j] == "{": depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0: return (m.start(), j + 1)
    return None

def sub_in_block(src, key, pattern, repl, count=1, tag=""):
    b = block_of(src, key)
    if not b:
        problems.append(f"block not found: {key} {tag}"); return src
    seg = src[b[0]:b[1]]
    new_seg, n = re.subn(pattern, repl, seg, count=count)
    if n != count:
        problems.append(f"pattern miss in {key} {tag}: wanted {count}, got {n}")
    return src[:b[0]] + new_seg + src[b[1]:]

# ------------------------------------------------------------------ Doors
doors_src = load("ServerStorage__ServerController__Dictionaries__Doors.lua")
zone_orbs = {d["zone"]: d for d in design["zoneLadders"]["doorOrbs"]}
for d in design["doors"]:
    z = d["zone"]
    if d["price"] > 0:
        doors_src = sub_in_block(doors_src, z, r'Price = \d+;[^\n]*', f'Price = {lua_num(d["price"])};', tag="price")
    orbs = zone_orbs[z]
    doors_src = sub_in_block(doors_src, z, r'Multi = [\d\.]+;', f'Multi = {lua_num(orbs["Multi"])};', tag="multi")
    doors_src = sub_in_block(doors_src, z, r'Orb = [\d\.]+;[^\n]*', f'Orb = {lua_num(orbs["Orb"])};', tag="orb")
doors_src = doors_src.replace(
    "--.. (August 2026: all biome doors use Coins. Prices remain centralized here",
    "--.. (2026-08-28 ECONOMY REDESIGN: new price ladder + Orb/Multi zone-value ladder (Orb*Multi = 8^tier).\n--.. (all biome doors use Coins. Prices remain centralized here", 1)
save("Dictionaries__Doors.lua", doors_src)

# ------------------------------------------------------------------ Pickaxes
pick_src = load("ServerStorage__ServerController__Dictionaries__Pickaxes.lua")
for p in design["pickaxes"]:
    nm = p["name"]
    pick_src = sub_in_block(pick_src, nm, r'Price = \d+;', f'Price = {lua_num(p["price"])};', tag="price")
    pick_src = sub_in_block(pick_src, nm, r'Damage = \d+;', f'Damage = {lua_num(p["damage"])};', tag="dmg")
pick_src = pick_src.replace(
    "--.. Pickaxes replaced the pickaxe line (Aug 2026).",
    "--.. (2026-08-28 ECONOMY REDESIGN: damage x2.75/step, price ~x3.4-5/step — 5 dmg/400c to 147M dmg/5Qa.)\n--.. Pickaxes replaced the pickaxe line (Aug 2026).", 1)
save("Dictionaries__Pickaxes.lua", pick_src)

# ------------------------------------------------------------------ Eggs
eggs_src = load("ServerStorage__ServerController__Dictionaries__Eggs.lua")
ODDS_STD  = [40, 30, 15, 9, 5, 1]
ODDS_ULTRA= [40, 30, 15, 9.95, 5, 0.05]   # Lava/Narmek keep an ultra-chase slot
for egg in design["eggs"]:
    nm = egg["name"]
    if egg["price"] > 0:
        eggs_src = sub_in_block(eggs_src, nm, r'Price = \d+;[^\n]*', f'Price = {lua_num(egg["price"])};', tag="price")
    if nm in ("Lava Egg", "Narmek Egg"):   odds = ODDS_ULTRA
    elif nm == "Food Cuke Egg":            odds = None   # keep its 10-slot odds
    else:                                  odds = ODDS_STD
    if odds:
        b = block_of(eggs_src, nm)
        seg = eggs_src[b[0]:b[1]]
        for rank, pct in enumerate(odds, start=1):
            seg2, n = re.subn(r'Percent = [\d\.]+;(\s*\n\s*Rank = %d;)' % rank,
                              f'Percent = {lua_num(pct)};\\1', seg, count=1)
            if n != 1: problems.append(f"egg odds miss {nm} rank {rank}")
            seg = seg2
        eggs_src = eggs_src[:b[0]] + seg + eggs_src[b[1]:]
save("Dictionaries__Eggs.lua", eggs_src)

# ------------------------------------------------------------------ Upgrades
upg_src = load("ServerStorage__ServerController__Dictionaries__Upgrades.lua")
UPG = {"Vault slots": (500000, 2), "Pet equips": (25000, 2), "Smashes required": (50000, 3)}
for nm, (base, incr) in UPG.items():
    upg_src = sub_in_block(upg_src, nm, r'Price = \d+;', f'Price = {lua_num(base)};', tag="price")
    upg_src = sub_in_block(upg_src, nm, r'Increment = [\d\.]+;', f'Increment = {lua_num(incr)};', tag="incr")
save("Dictionaries__Upgrades.lua", upg_src)

# ------------------------------------------------------------------ Pets
pets_src = load("ServerStorage__ServerController__Dictionaries__Pets.lua")
patched_names = []
for pet in design["pets"]:
    nm = pet["name"]
    b = block_of(pets_src, nm)
    if not b:
        problems.append(f"pet block not found: {nm}"); continue
    seg = pets_src[b[0]:b[1]]
    seg, n1 = re.subn(r'Multi1 = [\d\.]+;', f'Multi1 = {lua_num(pet["Multi1"])};', seg, count=1)
    seg, n2 = re.subn(r'Damage = [\d\.]+;', f'Damage = {lua_num(pet["Damage"])};', seg, count=1)
    seg, n3 = re.subn(r'Multi2 = [\d\.]+;', f'Multi2 = {lua_num(pet["Multi2"])};', seg, count=1)
    if not (n1 == n2 == n3 == 1):
        problems.append(f"pet stat miss: {nm} ({n1}/{n2}/{n3})")
    pets_src = pets_src[:b[0]] + seg + pets_src[b[1]:]
    patched_names.append(nm)
pets_src = pets_src.replace(
    "--.. (stats rebalanced July 2026: Multi1/Multi2 1-8.2 bands + explicit per-pet Damage)",
    "--.. (2026-08-28 ECONOMY REDESIGN: Multi1 floors x3/area (1 -> 2.5K), Damage x~12/area (2 -> 270M).)", 1)
save("Dictionaries__Pets.lua", pets_src)

print("patched pets:", len(patched_names), "of", len(design["pets"]))
if problems:
    print("PROBLEMS:"); [print(" -", p) for p in problems]
    sys.exit(1)
print("ALL PATCHES CLEAN ->", OUT)
