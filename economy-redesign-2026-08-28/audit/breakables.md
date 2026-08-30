# Breakables / Zones / Damage Economy Audit — 2026-08-28

Sources (dump: `backups/EconomyRedesign_2026-08-28/scripts/`):
- **BS** = `ServerStorage__ServerController__BreakablesService.lua` (4675 lines, read in full)
- **TS** = `ServerStorage__ServerController__TimeSkipRateService.lua`
- **CS** = `ServerStorage__ServerController__CarryService.lua`
- **CH** = `ServerStorage__ServerController__CurrencyHandler.lua`
- **VS** = `ServerStorage__ServerController__VaultService.lua`
- **RB** = `ServerStorage__ServerController__RebirthService.lua`
- **DOORS** = `ServerStorage__ServerController__Dictionaries__Doors.lua`
- **BC** = `StarterPlayer__StarterPlayerScripts__BreakablesClient.lua` (visual mirror only; no authoritative numbers)

`ServerStorage__ServerController__ServerNetwork.lua` contains **no** PickaxeStrike validation — the remote is bound and validated inside `BreakablesService.Initialize` (BS:4324-4344): instance type check, slice-flesh parent redirect, then debounce/reach/locked-biome guards in `PickaxeStrike` itself.

---

## 1. Zones and scaling

`ZONES = {Spawn, Desert, Samurai, Farm, Snow, Underwater, Volcano, Narmek}` (BS:158). Zone index drives:

| Zone | idx | ZONE_HP wall (BS:111-114) | Orb (DOORS) | Multi (DOORS) | zoneValue = Orb×Multi | Carry-rarity ÷2^(idx−1) | Vault tier ×1.6^(idx−1) |
|---|---|---|---|---|---|---|---|
| Spawn | 1 | 1 | 1 (30) | 1 (29) | 1 | 1 | 1.0 |
| Desert | 2 | 3 | 2 (61) | 1.5 (62) | 3 | 2 | 1.6 |
| Samurai | 3 | 8 | 2.5 (91) | 2 (92) | 5 | 4 | 2.56 |
| Farm | 4 | 20 | 3 (120) | 2.5 (121) | 7.5 | 8 | 4.10 |
| Snow | 5 | 45 | 3.5 (149) | 3 (150) | 10.5 | 16 | 6.55 |
| Underwater | 6 | 110 | 5 (178) | 4 (179) | 20 | 32 | 10.49 |
| Volcano | 7 | 240 | 6 (208) | 5 (209) | 30 | 64 | 16.78 |
| Narmek | 8 | 500 | 7 (238) | 6 (239) | 42 | 128 | 26.84 |

- **Effective HP** = `floor(typeHP × ZONE_HP)` (BS:2730-2732; also BS:3625).
- **Effective reward** = `typeReward × Orb × Multi` (BS:1065-1067).
- **BonusCoins** = `floor(BonusCoins × Multi × damageShare × Pets.Multi2)` min 1 — uses **Multi only, not Orb** (BS:1127-1134).
- Boss HP wall & escape payouts also scale by ZONE_HP / zoneValue (BS:3813, 3901-3914).

HP-vs-value spread: Narmek pays 42× Spawn per point of Reward but costs 500× the HP → raw Cukes/HP *falls* ~12× from Spawn to Narmek; pet DPS growth + coins + vault carry是 the intended compensation.

## 2. Type pools (per-zone, all exclusive)

Every zone uses `ZONE_EXCLUSIVE_TYPES` (BS:175-522); the legacy shared `TYPES` (BS:119-156) and empty `ZONE_TYPES` (BS:532-550) are dead fallbacks (`EffectiveTypes`, BS:825-835). Full per-type tables (Name, Weight, HP, Reward, BonusCoins, Template, spawn %) are in `breakables.json → types`. Regular-pool spawn % = `Weight / Σ(non-sliced weights)` — **sliced types never enter the weighted roll** (`PickType` filters `Sliced`, BS:845-867); they fill a separate quota via `SlicedTypeFor` (BS:838-843).

Per-zone effective ranges (regular pool; sliced in parens):

| Zone | Σweight | HP range (eff.) | Reward range (eff. Cukes) | Sliced |
|---|---|---|---|---|
| Spawn | 82 | 30 – 350 | 8 – 140 | (8 HP / 3) |
| Desert | 95 | 105 – 1,200 | 30 – 495 | (30 / 12) |
| Samurai | 87 | 304 – 3,360 | 55 – 875 | (80 / 20) |
| Farm | 80 | 840 – 8,800 | 90 – 1,387.5 | (200 / 30) |
| Snow | 89 | 2,025 – 20,700 | 136.5 – 2,047.5 | (450 / 42) |
| Underwater | 89 | 5,280 – 52,800 | 280 – 4,100 | (1,100 / 80) |
| Volcano | 90 | 12,000 – 120,000 | 450 – 6,300 | (2,400 / 120) |
| Narmek | 89 | 26,000 – 260,000 | 672 – 9,240 | (5,000 / 168) |

Common-tier spawn share is ~36–43% everywhere; the landmark tree is 4.5–9.8%.

## 3. Spawn system

| Constant | Value | Ref |
|---|---|---|
| PER_ZONE (other, base) | 12 | BS:24 |
| PER_ZONE_MAX (other) | 32 | BS:25 |
| PER_PLAYER_BONUS (other) | +3/extra player | BS:26 |
| OTHER_COUNT_MULTIPLIER | 1 | BS:27 |
| SLICED_BASE_PER_ZONE | 7 | BS:28 |
| SLICED_PER_PLAYER_BONUS | +3 | BS:29 |
| SLICED_PER_ZONE_MAX | 28 | BS:30 |
| EMPTY_ZONE_SLICED / OTHER | 2 / 3 | BS:31-32 |
| POPULATION_PLAN/WORK/STARTUP_TICK | 0.5 / 0.08 / 0.025 s | BS:33-35 |
| ZONE_UNLOAD_GRACE | 8 s | BS:36 |
| PRUNE_PER_STEP | 1 | BS:37 |
| RESPAWN_TIME | 6 s | BS:38 |

- Targets: `other = clamp(12+(n−1)·3, 12, 32)`, `sliced = clamp(7+(n−1)·3, 7, 28)` (BS:1963-1977). *n = whole-server player count.*
- Active zones = each player's anchored biome ±1 neighbor (BS:2045-2102); inactive biomes idle at 2 sliced + 3 other (BS:2104-2109).
- One round-robin worker does one create/remove per 0.08 s tick (BS:4384-4431). Break() also schedules a direct 6 s respawn check (BS:1311-1319).
- `PruneZone` removes ≤1 over-target breakable per pass and **never** prunes bosses, lightning jackpots, or player-dropped carries (BS:2111-2134).
- Tree guarantee: if no standing tree in the zone folder (name match incl. `"Golden "` prefix), the next non-sliced spawn is forced to the tree type (BS:2696-2717).
- All non-boss templates render at ×0.75 scale, ×2 during SuperStrength (BS:2742-2744).

## 4. Golden (material)

| Constant | Value | Ref |
|---|---|---|
| GOLDEN_CHANCE | 0.08 per non-boss spawn | BS:2521 |
| GOLDEN_HOUR_MULT | ×4 chance (→0.32) | BS:2522, 2545-2547 |
| GOLDEN_HP_MULT | ×2.5 | BS:2523 |
| GOLDEN_REWARD_MULT | ×7 | BS:2524 |
| GOLDEN_COIN_MULT | ×10 | BS:2525 |

Rolled on top of any picked type (BS:2718-2727). Same-zone golden chance is per-spawn, not per-type.

## 5. Diamond (material, `MUTATIONS.DiamondMod`, BS:618-639)

Chance **0.02**, HP **×4**, Reward **×20**, Coin **×25**, name prefix `"Diamond "`. Rolled **before** golden and mutually exclusive with it (BS:2722-2727) → effective golden chance = 0.98×0.08 = **7.84%**. Rotation/Prismatic mutations still stack on top. Vault earn ×8 (CS:84).

## 6. Mutations

Rotation table (BS:597-604): **NEON, SHADOW, FROZEN, RADIOACTIVE, ROYAL, MOLTEN** — one active per UTC day, `MUTATIONS[(floor(os.time()/86400) % 6)+1]` → strict 6-day cycle (BS:650-653).

- `MUTATION_CHANCE = 0.02` per spawn (BS:605); `MUTATION_MULT = 25×` reward (BS:606, applied BS:1074-1078). **No HP change.**
- **PRISMATIC** (BS:613): pre-rolled on EVERY spawn before the daily roll (BS:2789-2793 template path, 3010-3014 procedural path), chance **1/30000**, **100×** loot, server-wide announcement (BS:1086-1089), quest-board wildcard. Vault carry earn ×20 vs ×5 for rotation mutations (CS:85).
- **FROZEN** mechanics live in the vault, not the field: 0.8× earn everywhere the record earns/is valued (CS:417-423) in exchange for theft immunity even while unlocked (VS:646-647, 1880-1882).
- **MOLTEN** mechanics: vault pad rate ramps `rate ×= 1 + 1.5·(HeatT/3600)`, HeatT capped at 3600 s → **2.5× after 1 h uncollected**; collecting resets heat; live tick only (VS:1663, 2088-2096).
- Roll order per spawn: type → material (diamond→golden) → HP calc → mutation (force → prismatic → daily). Mutation stacks multiplicatively on material.

## 7. Lightning / CHARGED

Per-zone independent clock 30–90 s (BS:658-659, 4437-4444). One bolt converts a plain (non-boss, **non-mutated**; golden/diamond OK) cucumber to CHARGED with flat mult **random(25, 50)** (BS:660, 682-684). Cap: **1 live jackpot per zone** (BS:671-675); lifetime **75 s** + one grace extension if damaged (BS:676-679, 1704-1719). Applied as `totalReward ×= mult` at Break (BS:1094-1103).

## 8. Damage

**Click** (BS:1833-1891):
```
dmg = floor( floor( PickaxeDamage × FriendBoost ) × comboMult )
comboMult = min(1 + (combo−1)×0.05, 2)          -- 21 hits to cap; 3 s window (BS:44-49)
then: ×5 if SuperStrength active in the zone (BS:1443-1447)
then: ×5 on 10% crit (BS:1452-1453)
```
- PickaxeDamage = `Pickaxes[equipped].Stats.Damage`, default 4, min 1 (TS:219-228).
- FriendBoost = 1 + 0.10×min(friendsInServer, 5) → up to 1.5 (BS:1506-1543). Excluded from Time Skip quotes.
- Debounce 0.25 s → 4 accepted clicks/s (BS:41, 1862-1864); TS mirrors as PICKAXE_TICK (TS:16).
- Reach: surface radius + 30 studs (BS:1478-1494, client mirror BC:539); beyond-reach clicks ≤55 studs commit pets only (BS:1847-1860). ClickDetector = commit only, never damage (BS:1899-1922).
- Indirect (auto-aim) strikes: flat ×1, no combo build/break (BS:1874-1878).
- SuperStrength click splash: exact resolved dmg copied to every breakable within 10 studs, one hop, no event-goal credit (BS:1420, 1455-1475).

**Pets** (BS:4654-4671): one combined swarm strike every **0.6 s** = `max(1, 2 + floor(Pets.Damage.Value))` (TS:230-241), ×2 under SuperStrength, same 10% ×5 crit. All readable pet models must be within surface+10 studs (BS:919-942). Leash 110 studs; manual chain range 15; pet retarget needs 3 pickaxe hits on the new target (BS:1560-1587). Locked-biome guard blocks every damage source cross-border (BS:1425-1441).

## 9. Bosses (BOSS_TYPES, BS:3546-3609)

- **HP** = `floor((HPBase + 800×max(0, players−1)) × ZONE_HP)` (BS:58, 3813).
- **Summon** = `floor(Breaks × (1 + 0.05×players) + 0.5)` — 5% per player **including the first** (BS:59, 4548-4559). Meter counts non-boss, non-nuke breaks only while no event/boss is running (BS:1212-1224).
- **Kill payout** = `Reward × zoneValue × 6`, split by damage contribution, min 1 per damager (BS:1069-1071, 1117-1123); plus BonusCoins formula; plus 1 shard **per damager** (BS:1146-1205); 10 shards forge that zone's boss pet, spent & repeatable (BS:108, 997-1045); top damager gets the trophy carry (BS:1273-1294) at rate `floor(8×1.6^(tier−1))` c/s (CS:391-392) → 8/12/20/32/52/83/134/214.
- **Timeout** 360 s: escaped boss pays every damager at the identical 6×/HP rate — no coins/shards/trophy (BS:57, 3894-3926).
- **Mobile boss death burst**: 18 single-claim pickups (12×500 Cukes + 6×500 Coins), 12 s expiry (BS:3164-3220).

| Zone | Breaks | HPBase | Solo HP | Reward | Solo Cuke pool (×6×zoneValue) | Coins |
|---|---|---|---|---|---|---|
| Spawn | 90 | 1,200 | 1,200 | 600 | 3,600 | 250 |
| Desert | 135 | 1,500 | 4,500 | 650 | 11,700 | 275 |
| Samurai | 180 | 1,800 | 14,400 | 700 | 21,000 | 300 |
| Farm | 225 | 2,100 | 42,000 | 750 | 33,750 | 325 |
| Snow | 270 | 2,400 | 108,000 | 800 | 50,400 | 350 |
| Underwater | 330 | 2,800 | 308,000 | 900 | 108,000 | 400 |
| Volcano | 390 | 3,200 | 768,000 | 1,000 | 180,000 | 450 |
| Narmek | 450 | 4,000 | 2,000,000 | 1,200 | 302,400 | 550 |

## 10. Reward flow on Break (BS:1049-1320)

```
totalReward = Type.Reward × Orb × Multi
            [× 6 if boss] [× 25 mutation | × 100 PRISMATIC] [× lightning 25–50]
per damager: max(1, floor(totalReward × dmg/totalDmg))  → AddCurrency("Cucumbers")
AddCurrency multipliers (CH:66-103): × rebirth(1+0.5×R, RB:17) × 2 (2x pass) × Pets.Multi1 × 2 (boost) × 1.5 (group)
BonusCoins → banked Coins directly: floor(BonusCoins × Multi × share × Pets.Multi2) min 1, then × rebirth at CH
```
Stats: TotalBreaks/Goal/SmashEvent credit per contributor; `GoldenBreaks` only for Golden (BS:1137-1144). Carry pickup: 100% catch mode for template types post-tutorial, rarer-swap gate (CS:301-364). Vault earn: `(1 + (35−W)/35×4) × 1.6^(tier−1) [×3 gold][×8 diamond][×5 mut|×20 prisma][×4 charged]` c/s, ×1.18^(level−1) upgrades, value = rate×250 (CS:76-88, 417-429).

## 11. Post-boss events

Boss kill → Goal challenge: `Required = 100 + 25×(playersInBiome−1)` landed non-boss hits (BS:565-567, 4167-4211) → 2-min event (GoldenHour ×4 golden chance; SuperStrength 5×/2× dmg + 2× scale; registry events e.g. CucumberSmash). Paid requirement skip exists (BS:4216-4252).

---

## Quirks / bugs / risks (designer surprises)

1. **Mutations are pure profit; materials are not.** Rotation ×25 / Prismatic ×100 / Charged ×25–50 add **zero HP**. Golden is 2.8× reward-per-HP (7/2.5); Diamond is 5× (20/4) with 6.25× coins-per-HP — diamond strictly dominates golden per effort AND is only 4× rarer.
2. **Multiplicative stacking is live and large.** Material × mutation stack: Diamond×Prismatic = ×2,000 base reward; Diamond×Charged up to ×1,000; Golden×Prismatic ×700 — all *before* the ×(rebirth×2×Multi1×2×1.5) currency stack (CH). A Narmek Galaxy Tree at 9,240 base → Diamond Prismatic = 18.48M pre-multiplier Cukes.
3. **Boss multiplayer scaling is punitive.** Each extra player adds `800 × ZONE_HP` HP (Narmek: +400,000/player) but the reward pool never grows — per-capita boss income collapses in crowded servers. Summon cost also starts at 105% of `Breaks` even solo (1 + 0.05×n counts the first player).
4. **Escaped bosses pay the full kill rate.** Timeout payout uses the identical 6×/HP rate (BS:3901-3914) — only coins/shards/trophy are lost; slow-rolling a boss to timeout is barely penalized.
5. **`ContributionReward` min-1 floor** (BS:988): tagging N breakables for 1 damage each guarantees ≥N Cukes ×full multipliers — a multi-tap crumb faucet in high zones where 1 Cuke is trivial, but relevant to splash/AoE designs.
6. **GoldenHour churn is Spawn-only in practice.** `ChurnGoldenCucumbers` filters `data.Type.HP <= 30` on *base* HP (BS:4077) — the only qualifying live type in the whole game is Spawn's "Cucumber" (HP 30); every other zone's cheapest regular is 34–52. The advertised "re-roll the field" effect silently no-ops in 7 of 8 zones.
7. **Diamond trees break the landmark guarantee.** The standing-tree scan matches `treeType.Name` or `"Golden "..name` only (BS:2710-2713); a spawned tree renamed `"Diamond X Tree"` is invisible to it, so the zone force-spawns another tree next roll — extra trees (extra top-end paydays) while a diamond tree stands.
8. **Sliced Weight 25 is a phantom.** It never affects spawning (dedicated quota), but inflates the `CarryRarityOf` denominator (BS:3685-3688) and quest-board target odds (`TypeNamesFor`, BS:3746-3752) — displayed "1 in N" carry rarities are ~25/Σw too generous for every regular type.
9. **Dead code:** `TARGET_RANGE = 42` (BS:115) never read; `isDiamond` in `LightningStrike` is an undefined global — the glass-material branch and `"Diamond"` return label (BS:1675/1680/1687/1733) are unreachable remnants of the pre-2026-08-27 diamond storm.
10. **Time Skip quotes diverge from the live field.** Spawn is deliberately quoted from the legacy pool including the removed "Golden Cucumber" type (TS:38-43, 55-57); quotes assume 15/24 sliced/other slots (live: 7/12 solo baseline) and ignore golden/diamond/mutation/lightning upside, friend boost, and combo — quotes systematically *undervalue* live farming, more so in high-luck sessions.
11. **Crit stacks after SuperStrength**: 10% chance ×5 on the already ×5 click → 25× spikes; expected DPS factor from crit is a flat 1.4×. Splash copies the crit result to every neighbor within 10 studs, so one crit can multi-crit the whole cluster.
12. **Combo is per-player, not per-target** (BS:685-686, 1880-1889): switching cucumbers preserves the ×2 cap bonus as long as a hit lands every 3 s.
13. **NukeAll pays everything, including a live boss.** The dev-product collector grants full credit for every live breakable — boss ×6 pools, mutants, jackpots — via the normal payout loop (BS:1324-1349); only meters/trophies/announcements are skipped.
14. **Pet DPS ignores pet count directly** — `2 + floor(Pets.Damage.Value)` is one combined strike (TS:230-241); equip count only gates >0 and the swarm-arrival check. All-pets-in-range fails closed (BS:919-942): one straggler pet silences the whole swarm.
15. **Coins get rebirth twice conceptually but not literally:** direct coin drops apply `Multi` + `Pets.Multi2` at Break, then rebirth at AddCurrency (CH:94-100) — coins deliberately skip Multi1/2x-style stacking; rebirth is the only sell lever (comment CH:96-99).
16. **FROZEN/MOLTEN are vault-economy mutations only.** As field breaks they are ordinary ×25 rotation mutations; their signature mechanics (0.8× theft-proof / 2.5× heat ramp) exist solely for carried/vaulted records (CS:417-423, VS:2088-2096).
17. **Lightning cannot hit mutants but can hit materials** (BS:1653): Charged Golden (≤×350) and Charged Diamond (≤×1,000) are reachable jackpots; Charged Prismatic is impossible.
