# New Map Cucumber Game: economy plan (2026-09-23) - IMPLEMENTED the same day; see the README section "ECONOMY REBUILD" for what landed and the playtest results. Deviations: CUCUMBERS_PER_BIOME = 10 (the constant counts the slices), FormatCost abbreviates from 100K, EggShopClient toast abbreviated, PortalHudClient got the reward toast, no physique stages added, store key kept (no wipe).

User ask: "go through the entire game and set up the economy: when players upgrade the base, how long
until the next biome and the one after (retention / proven metrics), fun threat levels per biome (more
zombies, it is a bit too easy), the number of defences a player would have at that biome. Plan every
script edit, do not edit anything yet."

All "current" numbers below were read from the LIVE place (instance:yy4-a6j) on 2026-09-23 by four
read-only agents; citations are Script:line.

## 1. Where the live economy breaks

1. **Strength cannot reach the last four biomes.** Strength per rep is `2^(bench-1) x headband`
   (GymService:100-102), max 128 x 13 = 1,664 per rep at 960 reps/min = 1.6M/min fully geared.
   The lift needs `Strength >= 0.4 x kg` (CucumberCarry:671), kg base per biome
   (CucumberLift:81-84): 3 / 300 / 2K / 15K / 400K / 6M / 40M / 750M / 14B / 1T.
   Narmek min 300M = 3 h of benching at max gear, Toyland 5.6B = 58 h, Neon 400B = 170 DAYS.
   The requirement grows x7 to x70 per biome, the gain grows linearly. Unwinnable.
2. **Cash prices are flat while income grows x8 per biome.** Every defence costs 300-5,000
   (Builds Cost attrs), bench tiers 100-6,400, plot 250-8,000, every egg 100, items 2.5K-500K,
   headbands 500-50M. A Farm player (typical cucumber 18.6 $/s, 10 placed = 11K/min) buys every
   defence in 3 minutes; from Snow up everything is free. The only thing left to gate progression is
   strength, which is broken (point 1).
3. **Cucumber income is tiny vs pets.** Rate = value / 220 s (CucumberValues:73-77): a typical
   Spawn cucumber pays 0.036 $/s, so a +0.5 $/s "first zone bonus" was bolted on, which makes Spawn
   cucumbers out-earn Desert ones (0.54 vs 0.29 $/s). Pets pay 0.5 x 8^(tier-1) x rarity per second
   (PetStats:309-318), i.e. a Basic Common pet = 14 Spawn cucumbers.
4. **Threat level is front-loaded.** points = biome^1.6 per cucumber, level = 1 + floor(3.2 x
   log10(1 + score/2)) (ZombieCatalog:168-190): a FULL Spawn base is already level 4, a Desert base
   level 5, and everything from Snow to Neon lands in levels 7-9. Wave = 3..9 zombies with fixed HP
   60..900 (ZombieCatalog:94-136, :193-233). Against a maxed base (limits 3 + PlotLevel of nine
   defence types, ~1,000+ DPS) any wave dies in seconds. Bat = 35 dmg / 0.55 s, never scales.
5. **Trees dominate.** Tree reward 360 = 45x the typical cucumber of the same biome and 5.6x the
   typical of the NEXT biome (CucumberValues:30-42), so the daily tree matters more than the next
   biome.
6. Spawn field = 6 cucumbers per biome per 225 s day, shared by the whole server
   (CucumberSpawner:21-22). Two players in one biome starve each other.
7. Portals have no reward (PortalService:1); they are content without a loop.

## 2. Target pacing (the numbers everything else is derived from)

Session-1 median for Roblox simulators is 25-35 min; retention wants a new unlock inside the first
5 min, a new area every 8-15 min during session 1, session 1 ending with the NEXT area just
unlocked, then roughly doubling time per area, with daily reasons to return (offline earnings, egg
stock, hourly portal rewards). Target cumulative play time to be "comfortable" in each biome:

| Biome | Comfortable strength (new kg base) | Enter at | Time in biome | Threat level while based there |
|---|---|---|---|---|
| 1 Spawn | 3 | 0 | 6 min | 1 |
| 2 Desert | 300 | 6 min | 9 min | 2 |
| 3 Samurai | 3K | 15 min | 15 min | 3 |
| 4 Farm | 30K | 30 min | 30 min | 4 |
| 5 Snow | 300K | 1 h | 1 h | 5 |
| 6 Underwater | 3M | 2 h | 2 h | 6 |
| 7 Volcano | 30M | 4 h | 4 h | 7 |
| 8 Narmek | 300M | 8 h | 8 h | 8 |
| 9 Toyland | 3B | 16 h | 16 h | 9 |
| 10 Neon | 30B | 32 h | endgame | 10 |

Three ladders, all geometric and aligned:
- Strength requirement x10 per biome (kg base 3 x 10^(N-1)); the tree of a biome needs 3.4x its base.
- Cash income x8 per biome (already true); prices of the thing you buy IN biome N are ~10-25 % of
  what you earn while there.
- Zombie HP x3 per threat level, defence damage x3 per unlock tier, bat damage x3 per biome of
  strength, pet damage x3 per egg tier. Count of zombies 4 -> 16.

Income model used for prices: typical cucumber of biome N = 0.5 x 8^(N-1) $/s. A mid-biome base
(12 typical + 1 tree + a few pets) = U_N = 600 x 8^(N-1) $/min. Earned while in biome N,
E_N = 0.75 x U_N x time: 2.7K / 29K / 430K / 6.9M / 113M / 1.8B / 28B / 450B / 7.2T.

### Strength gain check (bench N and headband N+1 owned while in biome N)
Strength/rep = 3^(bench-1) x band; reps/min = 30 x RepSpeed {1,2,4,7,11,18,27,32} plus ~45
rep-equivalents/min from bonus circles. Needed = next base / (half the biome time on the bench).

| Biome | Gear | Str/min | Needed | Margin |
|---|---|---|---|---|
| 1 | bench 1, band 2 (3x) | 225 | 150 | 1.5x |
| 2 | bench 2, band 3 (4x) | 1.3K | 750 | 1.7x |
| 3 | bench 3, band 4 (6x) | 8.9K | 4K | 2.2x |
| 4 | bench 4, band 5 (8x) | 55K | 20K | 2.8x |
| 5 | bench 5, band 6 (12x) | 364K | 100K | 3.6x |
| 6 | bench 6, band 7 (16x) | 2.3M | 500K | 4.5x |
| 7 | bench 7, band 8 (24x) | 15M | 2.5M | 6x |
| 8 | bench 8, band 9 (32x) | 70M | 12.5M | 5.6x |
| 9 | bench 8, band 11 (64x) | 140M | 62M | 2.3x |
| 10 | bench 8, band 12 (96x) | 211M | Neon tree 41B in ~3 h | endgame |

Margins of 1.5-6x mean an engaged player beats the schedule and CASH (gear prices) sets the floor.

## 3. Price and stat tables (final proposal)

### Bench (GymService) and headbands (HeadbandsCatalog)
| Bench tier | Cost | Str/rep | Bought in |
|---|---|---|---|
| 2 Iron | 300 | 3 | Spawn |
| 3 Gold | 7K | 9 | Desert |
| 4 Frost | 100K | 27 | Samurai |
| 5 Inferno | 1.5M | 81 | Farm |
| 6 Cosmic | 25M | 243 | Snow |
| 7 Celestial | 400M | 729 | Underwater |
| 8 VoidEmperor | 6B | 2,187 | Volcano |

| Band | Price | Mult (was N+1) |
|---|---|---|
| 1 Sweatband | free | 2 |
| 2 Red Bandana | 500 | 3 |
| 3 Camo | 6K | 4 |
| 4 Cucumber | 80K | 6 |
| 5 Straw | 1.2M | 8 |
| 6 Leaf Crown | 20M | 12 |
| 7 Steel | 300M | 16 |
| 8 Cactus | 5B | 24 |
| 9 Frost | 60B | 32 |
| 10 Gold | 150B | 48 |
| 11 Lava | 1T | 64 |
| 12 Champion | 3T | 96 |

### Plot upgrades (PlotUpgrades:12-19), capacity/limits unchanged (10+2L cucumbers, 3+L pets, 3+L defences)
| To level | Cost | Expected when |
|---|---|---|
| 1 | 400 | ~4 min, Spawn, base hits 10 |
| 2 | 4K | ~12 min, Desert |
| 3 | 60K | ~25 min, Samurai |
| 4 | 1M | ~50 min, Farm |
| 5 | 15M | ~2 h, Snow |
| 6 | 250M | ~4 h, Underwater |

### Cucumbers (CucumberValues, CucumberLift, CucumberSpawner)
- `EARN_VALUE_PERIOD` 220 -> 16 (rate = value/16: typical Spawn 0.5 $/s), `FIRST_ZONE_BONUS` 0.5 -> 0.
- Reward rows (tree = 8x typical = the next biome's typical, was 45x):
  6-row {3, 8, 14, 24, 40, 64}; 8-row {3, 8, 12, 17, 24, 34, 48, 64}; 7-row {3, 8, 13, 20, 30, 45, 64};
  GENERIC {Cucumber 8, Giant 40, Sliced 3, Tree 64}. Index order stays monotonic.
- `ZONE_BASE` -> {3, 300, 3e3, 3e4, 3e5, 3e6, 3e7, 3e8, 3e9, 3e10}. Everything else in CucumberLift
  (REWARD_POWER 0.4, material/mutation factors, curve, MIN_RATIO 0.4) unchanged.
- Field: `CUCUMBERS_PER_BIOME` 6 -> 8 (+2 sliced = 10 per biome, 100 per day).
- Signs (nine SurfaceGuis under Map.Biomes."01 Spawn".Decor.Sign): 300 / 3K / 30K / 300K / 3M / 30M /
  300M / 3B / 30B recommended.
- Manage: `SELL_SECONDS` 220 -> 120 (placing beats selling after 2 minutes); offline earnings unchanged.

### Threat (ZombieCatalog / ZombieRaidService)
- score = sum over placed cucumbers of RewardOf x 8^(zone-1) x min(TotalMult, 12)  (mutation
  contribution capped so one Prismatic does not jump three levels).
- level = clamp(1 + floor(log8(score / 128)), 1, 10): the level follows the biome the BULK of the
  base comes from (16 typical or 2 trees of biome L); one tree of the next biome does not bump it.
  Income term dropped (it is the same information); pets and potions never raise threat.
- Wave count = clamp(round(3 + 1.3 x level), 4, 16): 4, 6, 7, 8, 10, 11, 12, 13, 15, 16.
- HP multiplier HP_MULT(level) = 3^(level-1) for 1..8 (1 .. 2,187), 3,281 at 9, 4,921 at 10
  (the last two levels add bodies and specials, not only HP).
- Variety HP re-based to ROLE (the level multiplier does the scaling): Shambler 60, Runner 40,
  Brute 200, Iron Brute 250, Lava Brute 300, Titan 600, one-hit sprinters 1, Splitters 180
  (children 20 / 35), Grapplers 100, Shadows 70, Diggers 80, Toxic 90, Blood Runner 50, Void
  Shambler 90, Neon Runner 60, Chain Reaper 220. MinLevels unchanged.
- Bash damage on builds = 25 x HP_MULT(level); Barbed wall returns 10 % of the basher's max HP.
- Per-server alive cap 48 zombies (later door rows wait).
- Steal limit 3, day thieves, night 45 s: unchanged.

### Defences: unlock tier, price, damage, HP (Builds Cost attrs, BuildCatalog, DefenceService, ZombieCatalog.BUILD_HEALTH)
| Build | Tier / unlock strength | Cost | Damage (was) | Build HP |
|---|---|---|---|---|
| SpikeTrap | 1 / 0 | 300 | 7 per 0.4 s (7) | 300 |
| BoostPad | 1 / 0 | 400 | utility | 300 |
| WoodenWall | 1 / 0 | 100 | wall | 150 |
| Catapult | 2 / 300 | 2.5K | 180 splash per 4.5 s (45) | 900 |
| StoneWall | 2 / 300 | 600 | wall | 1,200 |
| Turret | 3 / 3K | 25K | 100 per 0.45 s (12) | 2.7K |
| LaserGate | 4 / 30K | 250K | 80 per 0.1 s tick (2.5) | 8.1K |
| IronWall | 4 / 30K | 60K | wall | 10.8K |
| FreezeTower | 5 / 300K | 3M | 50 per 0.5 s to all in 24 studs (2) + slow | 24K |
| TeslaCoil | 6 / 3M | 30M | 1,800 chain, x0.75 per hop, per 1.5 s (18) | 73K |
| Mortar | 7 / 30M | 400M | 18K splash per 3.6 s (60) | 219K |
| BarbedStoneWall | 7 / 30M | 100M | wall, 10 % reflect | 365K |
| Minigun | 8 / 300M | 5B | 1,500 per 0.08 s (4) | 656K |
| Flooring / Staircase | 1 | 100 / 300 | | never damaged |
| Garden / Fun decor | 1 | unchanged | | 150 |

Expected loadout per level and the DPS check (need = 70 % of wave HP inside a 15 s exposure; uptime
0.5 on defences): L1 bat only vs 4 shamblers; L2 3 traps + 1-2 catapults vs 6; L3 +3 turrets vs 7
(need 1.1K, have ~1.2K); L4 +3 lasers, iron walls vs 8 (need 1.5K, have 1.7K); L5 +3 freeze vs 10
(need 5.7K, have ~4.8K but everything is slowed 55 %); L6 +3 tesla vs 11 (need 19K, have 17K);
L7 +3 mortars vs 12 (need 61K, have 53K); L8 +3 miniguns vs 13 (need 199K, have ~230K with 9
miniguns, top pets and bat); L9 15 zombies at x1.5 HP (need 460K, have ~360K); L10 16 at x2.25
(need 550K, have ~640K). Calibrate with the raid simulator before publishing (section 5).

### Player and pet damage
- Bat (BatServer:24): 35 -> `35 x 3^max(0, log10(Strength / 300))`: 35 at Desert strength, 105 at
  Samurai, x3 per biome, 76K at Toyland. Every zombie of your own level takes 4-5 hits.
- Pet shot damage (PetStats:309-318): `RARITY.Damage x (1 + 0.05 x (tier-1))` -> `x 3^(tier-1)`.
- Holy Water (ItemsCatalog:72): 150 flat -> 40 % of each zombie's max HP + the 2 s stun.

### Eggs (EggShop:49 `EGG_PRICE`)
Basic 100, Desert 1K, Samurai 12K, Farm 200K, Frozen 3M, Ocean 50M, Lava 800M, Narmek 12B
(~3-5 % of E_N each; 5-10 eggs per biome). Stock ranges and hatch times unchanged. Pet income
formula unchanged (it is now on equal footing with cucumbers: a Basic Common = one typical Spawn cucumber).

### Item shop (ItemShopCatalog:24-36) and portals (PortalService)
- Item price x 4^(threatLevel-1) of the buyer (a Redemption Token at level 8 = 8B, 2 % of E_8).
- Portal StrengthRequired attrs: Lobby 100, Desert 1K, Ice 1M, Volcano 100M, Narmek 1B, Neon 100B.
- Portal finish reward = 10 minutes of that biome's U: Lobby 6K, Desert 48K, Ice 25M, Volcano 1.6B,
  Narmek 12.6B, Neon 800B (hourly cooldown already exists = an hourly reason to come back).

## 4. Every script edit (implementation order)

1. `ReplicatedStorage.Modules.CucumberValues` :23 PERIOD 16, :26 bonus 0, :30-42 reward rows, :44 GENERIC.
2. `ReplicatedStorage.Modules.CucumberLift` :81-84 ZONE_BASE table.
3. `Map.Biomes."01 Spawn".Decor.Sign` nine SurfaceGui TextLabels (one Luau pass), `Map.Biomes.*.Portals.*`
   StrengthRequired attributes (six).
4. `ServerScriptService.CucumberSpawner` :21 CUCUMBERS_PER_BIOME 8.
5. `ReplicatedStorage.Modules.ManageConfig` :40 SELL_SECONDS 120.
6. `ServerStorage.GymService` :59-60 cost table replaces `100 x 2^(L-1)`; :100-102 `3^(L-1)`.
   Check `GymBoardsClient` / `BenchBoardClient` read the cost through GymService (they do via the
   board remote) and their labels format K/M/B.
7. `ReplicatedStorage.Modules.HeadbandsCatalog` :46-83 prices, :21-23 + :125-130 explicit Mult column.
   Check `StarterGui.HeadbandShop` price labels format B/T.
8. `ReplicatedStorage.Modules.PlotUpgrades` :12-19 costs.
9. `ServerStorage.Builds/*` Cost attributes (13 defence/wall models) + `BuildCatalog` :89-96 DEFAULT_COST
   to match; new `UNLOCK_STRENGTH` table + `UnlockOf(key)` + `IsUnlocked(strength, key)`; card data
   carries Unlock. `ServerScriptService.BuildService` Place :511-518 refuses locked keys
   ("Needs 3K strength"). `StarterGui.BuildMenu` (BuildMenuClient) greys locked cards with the strength
   label and refreshes on `Data.Strength` change.
10. `ReplicatedStorage.Modules.ZombieCatalog` :30-36 + :168-190 new score/level; :193-233 wave count;
    :94-143 role HP; new `HP_MULT(level)` + `HealthOf(variety, level)`; :58-61 BUILD_HEALTH tiers,
    BARBED as a fraction.
11. `ServerScriptService.ZombieRaidService` spawn sets Humanoid MaxHealth/Health = HealthOf(variety,
    raid.Level) (night waves, day thieves, splitter children); :183 BASH_DAMAGE x HP_MULT; :1099 barbed
    reflect; alive cap; `ThreatOf` :1488-1493 sums placed-cucumber values (reads the same attributes
    CucumberValues.ValueOf needs: Type/Zone/Material/Mutations/Size, verify they are stamped on placed
    models, else stamp `Value` at placement in CucumberCarry).
12. `ServerStorage.DefenceService` :65-76 damage config (7 numbers), :403-418 trap, :431-444 catapult,
    :521 mortar, :657-678 tesla, :695-717 freeze, :737-772 minigun, :783-791 laser.
13. `StarterPack.Bat.BatServer` :24 damage from Data.Strength.
14. `ReplicatedStorage.Modules.PetStats` :309-318 damage tier factor.
15. `ReplicatedStorage.Modules.ItemsCatalog` :72 Holy Water percent + `ServerScriptService.ItemService`
    applies it per target from Humanoid.MaxHealth.
16. `ReplicatedStorage.Modules.ItemShopCatalog` + `ServerScriptService.ItemShopService` price multiplier
    by `ZombieAPI.ThreatLevel(player)`; the shop state sent to the client carries the buyer's prices.
17. `ServerScriptService.EggShop` :49 per-egg price table (or Price attributes on the eight stands).
18. `ServerStorage.PortalService` :275-279 finish pays PORTAL_REWARDS[PortalId] through DataService with a
    toast; the six StrengthRequired attributes.
19. `ReplicatedStorage.Modules.NumberAbbrev` + HUDClient Compact: make sure K M B T Qa Qi are covered
    (Neon prices reach 10^13, mutated Neon rates 10^15).
20. `ServerStorage.DataService`: no migration needed for Strength (the new ladder is easier) or Cash;
    decision for the user: bump `PlayerData_v1` to `_v2` to relaunch everyone fresh, or keep.
    `Defense.Survived` keys shift with the new levels: players simply survive one night again.
21. `StarterGui.AdminPanel` / `ZombieDev` hook: add "force raid at level L" for calibration.

## 5. Verification before publishing
- Raid simulator (Luau, edit-mode or a Python port of the tables): for each level 1..10 run the wave
  against the expected loadout of section 3 and print kill % inside 15 s; tune HP_MULT / counts until
  60-80 % everywhere.
- Pacing sheet: simulate a player with 50 % bench time, the purchase order above and the U_N income
  model; assert the enter-times of section 2 within +-30 %.
- Playtest: AdminPanel set strength/cash to each biome's checkpoint, force night, watch levels 1, 4, 7,
  10 with the stated loadouts.
- Mirrors + README + backups for every touched script (backups/NewMap_economy_before_2026-09-2x.rbxm).

## 6. Guardians and player speed (added 2026-09-23, user: "guardians fast, chase on pickup, hit and knock
## back further; users even faster at higher strengths")

### Current (GuardianCatalog / GuardianService / StrengthProgression, live)
- Player WalkSpeed = 25 + 6 x log10(1 + Strength/100), cap 120 (StrengthProgression:28-31): Desert-strength
  28.6, Farm 39.9, Volcano 58, Neon 76. Carrying under ratio 1 slows to 0.45x at ratio 0.4 (CucumberLift:325-331).
- Guardian set speeds 24, 32, 40, 48, 56, 64, 72, 80, 88, 96 (GuardianCatalog:126-155) = 1.0-1.3x the
  comfortable player, BUT they sprint 2.6-4.2 s then rest 1.1-1.9 s at 0.72x (:37-39) so the average is ~0.9x
  = outrunnable. Wake 0.9-1.8 s after the pickup (:55), 0.35x of that when already lurking (:52), lurk at 0.34x
  (:45). Chase only the carrier of their own zone (GuardianService:1062), to the lobby (:57-65).
- Catch: reach 7 (:68), cooldown 1.6 (:69), knockback 6..30 studs / 0.5..0.9 s air on a log2 curve of
  Strength vs 5 x ZONE_BASE (:79-85; GuardianService:1193-1215), drop + the guardian returns the cucumber,
  no damage, silent.
- Trigger: `CarryingCucumberZone` is set when the lift COMPLETES, so the guardian starts after the bar is won.

### Target
1. Player speed grows 15 % per tenfold of strength (per biome): `WalkSpeed = min(120, 25 x 1.15^log10(1 + Strength/3))`:
   Spawn 25, Desert 33, Samurai 38, Farm 44, Snow 50, Underwater 58, Volcano 66, Narmek 77, Toyland 88, Neon 101.
   Boosts (pad / potion x2) apply after, total capped at 140. Slow mode stays 25.
2. Guardian speed = 1.3x the comfortable player of its biome, written as set numbers in the catalog:
   Strawman 32, Dune 43, Kabuto 49, Brisket 57, Frostbite 65, Pinch 75, Ember 86, Orbit 99, Tick 114, Scan 131
   (SPEED_MAX 260 is fine). One biome ahead in strength you are 1.15x = still caught unless you are not
   carrying; two biomes ahead (1.32x) you outrun it. Under-strength carries (0.45-0.7x speed) are near-certain
   catches: strength is what buys the escape.
3. Fewer, shorter rests: BURST_SECONDS {4, 6}, REST_SECONDS_CHASE {0.6, 1.0}, REST_SPEED 0.9 (average ~1.25x).
   LURK_SPEED 0.34 -> 0.5 so they are visibly prowling. WAKE_DELAY {0.9, 1.8} -> {0.4, 0.9}.
4. Wake at LIFT START, not lift end: CucumberCarry sets a `LiftingCucumberZone` attribute when the bar opens
   (cleared on cancel), GuardianService treats it like CarryingCucumberZone for waking/targeting (catching still
   needs the carry). A 4-click trivial lift is over before the guardian closes in; a 12 s hard lift is a race.
5. Hit + bigger fling: KNOCKBACK_MIN 6 -> 10, KNOCKBACK_MAX 30 -> 45 studs, KNOCKBACK_TIME_MIN 0.5 -> 0.55,
   KNOCKBACK_TIME_MAX 0.9 -> 1.1 s (arc peaks ~29 studs up; the client parabola already does the flight).
   Same strength curve: at your own biome's strength you fly the full 45; one biome ahead ~19; two ahead 10.
   REACH 7 -> 8, CATCH_COOLDOWN 1.6 -> 1.2. Still 0 damage, still silent, the signature clip is the hit.
6. Heat unchanged (+2.2 % speed and +0.22 reach per theft, max 8).

### Edits
22. `ReplicatedStorage.Modules.StrengthProgression` :28-31 new GetWalkSpeed; `ServerScriptService.StrengthProgressionServer`
    :36-50 cap 140 after boosts. Extend Stages with Titan 100M / Legend 1B / Mythic 10B (cosmetic).
23. `ReplicatedStorage.Modules.GuardianCatalog` :37-39 bursts/rests, :45 LURK_SPEED, :55 WAKE_DELAY, :68-69 reach/cooldown,
    :80-83 knockback, :126-155 speed column.
24. `ServerScriptService.CucumberCarry` (lift Start / Cancel / Lifted): set + clear `LiftingCucumberZone`.
25. `ServerScriptService.GuardianService` :1062 + :2057 + :2165 wake/target on Lifting OR Carrying zone; catch still
    requires CarryingCucumberZone.

## 7. Guardian pressure: options to make it less hard (2026-09-23, user: "they attack too fast even before you pick
## up the cucumber; do not change it yet, think about it") - NOT IMPLEMENTED

Why it feels that way now: the guardian wakes when the lift BAR OPENS (0.4-0.9 s, x0.35 when already lurking), it is
already on its feet inside the field (lurk 0.5x speed, LURK_INSET 10), and it chases at 1.3x the player. A field is
120 x 44 studs, so it is on you in 1-2 s, then it stands at reach 8 and the grab lands the tick the lift completes.
Any lift longer than ~1.5 s is a guaranteed catch; the player never gets a first step.

Options (pick 2-3):
1. Arrival timed to the lift's end: wake delay = max(0, expectedLift - travelTime - 0.5) where expectedLift = 0.3 +
   Clicks / CPS from the bar params (CucumberCarry already knows them) and travelTime = distance / speed. Trivial lifts
   keep the current pressure; a 6 s lift means the guardian shows up as you stand, not 5 s early.
2. Head start after the pickup: CATCH_GRACE 1.5 s from the moment CarryingCucumber is set; the guardian hovers at reach
   (signature clip as a roar / wind-up) and the grab is allowed only after the grace.
3. Wind-up tell: the hit is the CONTACT frame of the signature clip (0.5-0.7 s in), not the first tick within reach, so a
   player who keeps moving can slip it; require the target inside reach for 0.3 s continuously (GRAB_WINDOW).
4. Adrenaline: +30 % WalkSpeed for 3 s after a successful lift (one-shot, not stackable with the pad), so the chase opens
   with the player ahead.
5. Biome ramp: Strawman (Spawn) and Dune (Desert) get longer wake delays / longer crow-shake stops (shakeEvery {3, 5},
   stop 1.2 s) so the mechanic is learned safely; Kabuto onward keeps the full pressure.
6. Teach the escape: one-time toast on the first chase "Drop it (X) to shake the guardian" - dropping already ends the
   chase, most players do not know.
7. Perimeter lurking: lurk points on the field's edge (LURK_INSET negative / a ring) so the average approach is longer.
Recommendation: 1 + 2 + 3 together (the guardian arrives as you stand, you get 1.5 s to run, and the hit is dodgeable),
plus 6. Keep the 1.3x speeds: once it is a chase, strength is still what wins it.
