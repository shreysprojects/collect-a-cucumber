"""Spawn-rate calculator for the New Map Cucumber Game (2026-09-23).

Mirrors CucumberSpawner: six cucumbers per biome at dawn = 2 fixed sliced slots ("S") + 4 regular
rolls. A regular roll is the biome landmark ("T") with probability 1/LANDMARK_ODDS (one standing at
most), otherwise a RAW-weight draw over the other regular types. A day is 180 s + a 45 s night.
Prints the per-roll odds ("1 in X", what the Index shows), the expected count per biome per day
and the expected real-time gap between spawns, plus what the OLD code did (a forced daily tree).
"""
RAW = {
    "Spawn": [("Sliced Cucumber", 25, "S"), ("Cucumber", 61, ""), ("Slice Stack", 24, ""), ("Vined Cucumber", 10, ""), ("Flowered Cucumber", 4, ""), ("Cucumber Tree", 2, "T")],
    "Desert": [("Sun-Dried Slice", 25, "S"), ("Prickly Cucumber", 46, ""), ("Sliced Cucumber", 25, ""), ("Sun-Baked Cucumber", 14, ""), ("Wrapped Cucumber", 7, ""), ("Cactus Cucumber", 4, ""), ("Desert Palm", 2, ""), ("Sandstone Tree", 1, "T")],
    "Samurai": [("Sliced Cucumber", 25, "S"), ("Katana Cucumber", 53, ""), ("Bamboo Cucumber", 25, ""), ("Lantern Cucumber", 12, ""), ("Bamboo Grove", 6, ""), ("Torii Gate", 3, ""), ("Sakura Tree", 1, "T")],
    "Farm": [("Cucumber Basket", 25, "S"), ("Muddy Cucumber", 61, ""), ("Crate Cucumber", 24, ""), ("Windmill Plant", 10, ""), ("Hay Bale", 4, ""), ("Cucumber Tree", 2, "T")],
    "Snow": [("Frozen Slice", 25, "S"), ("Snowcap Cucumber", 46, ""), ("Snowball Slice", 25, ""), ("Crystal Cucumber", 14, ""), ("Frozen Cucumber", 7, ""), ("Snow Tree", 4, ""), ("Icicle Tree", 2, ""), ("Frozen Tree", 1, "T")],
    "Underwater": [("Bubble Slice", 25, "S"), ("Seaweed Cucumber", 46, ""), ("Shell Slice", 25, ""), ("Coral Cucumber", 14, ""), ("Pearl Cucumber", 7, ""), ("Kelp Tree", 4, ""), ("Bubble Tree", 2, ""), ("Coral Tree", 1, "T")],
    "Volcano": [("Molten Slice", 25, "S"), ("Charred Cucumber", 53, ""), ("Molten Cucumber", 25, ""), ("Flame Cucumber", 12, ""), ("Obsidian Tree", 6, ""), ("Volcano Cucumber", 3, ""), ("Magma Tree", 1, "T")],
    "Narmek": [("Moon Slice", 25, "S"), ("Meteor Cucumber", 46, ""), ("Planet Slice", 25, ""), ("Astronaut Cucumber", 14, ""), ("Neon Alien Cucumber", 7, ""), ("Moon Tree", 4, ""), ("Alien Tree", 2, ""), ("Galaxy Tree", 1, "T")],
    "Toyland": [("Toy Slice", 25, "S"), ("Lego Cucumber", 53, ""), ("Jack-in-the-Box Cucumber", 25, ""), ("Toy Rocket Cucumber", 12, ""), ("Pinwheel Plant", 6, ""), ("Building Block Tree", 3, ""), ("Toy Train Cucumber", 1, "T")],
    "Neon": [("Neon Slice", 25, "S"), ("Electro Cucumber", 53, ""), ("Neon Grid Cucumber", 25, ""), ("Hologram Cucumber", 12, ""), ("Neon Palm", 6, ""), ("Neon Tree", 3, ""), ("Cyber Cucumber", 1, "T")],
}
ZONES = ["Spawn", "Desert", "Samurai", "Farm", "Snow", "Underwater", "Volcano", "Narmek", "Toyland", "Neon"]
LANDMARK_ODDS = {"Spawn": 100, "Desert": 150, "Samurai": 200, "Farm": 250, "Snow": 300, "Underwater": 400, "Volcano": 500, "Narmek": 650, "Toyland": 800, "Neon": 1000}
REGULAR_ROLLS, SLICED_SLOTS = 4, 2
DAY_SECONDS = 180 + 45
CHANCE_MIN = 10


def shown(odds):
    if odds < 100:
        return int(odds + 0.5)
    mag = 10 ** (len(str(int(odds))) - 2)
    return int(odds / mag + 0.5) * mag


def gap(per_day):
    """real time between expected spawns of this type in one biome (all servers share the dice)"""
    seconds = DAY_SECONDS / per_day
    if seconds < 3600:
        return "%.0f min" % (seconds / 60)
    return "%.1f h" % (seconds / 3600)


def main():
    md = ["| Biome | Cucumber | Weight | Old per day | New per roll | Index shows | New per day | Real-time gap |", "|---|---|---|---|---|---|---|---|"]
    for zone in ZONES:
        rows = RAW[zone]
        landmark = [r for r in rows if r[2] == "T"][0]
        regular = [r for r in rows if r[2] == ""]
        w_reg = sum(r[1] for r in regular)
        L = LANDMARK_ODDS[zone]
        # OLD: the first regular roll is forced to the tree; the other 3 roll the full pool (tree weight included)
        w_old = w_reg + landmark[1]
        for name, weight, kind in rows:
            if kind == "S":
                md.append("| %s | %s | fixed | %d (2 slots) | slice slot | - | %d | every day |" % (zone, name, SLICED_SLOTS, SLICED_SLOTS))
                continue
            if kind == "T":
                p_roll = 1.0 / L
                old_per_day = 1 + 3 * weight / w_old
                label = "**[1 in %s]** (gold)" % format(L, ",")
            else:
                p_roll = (1 - 1.0 / L) * weight / w_reg
                old_per_day = 3 * weight / w_old
                s = shown(1 / p_roll)
                label = ("[1 in %s]" % format(s, ",")) if s >= CHANCE_MIN else "-"
            per_day = REGULAR_ROLLS * p_roll
            md.append("| %s | %s | %d | %.2f | 1 in %.1f | %s | %.3f | %s |" % (zone, name, weight, old_per_day, 1 / p_roll, label, per_day, gap(per_day)))
    print("\n".join(md))


if __name__ == "__main__":
    main()
