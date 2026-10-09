# Index rarity + collection trails (New Map Cucumber Game, 2026-09-23)

User request: *"calculate spawn rates for each cucumber in game. in index frame, display chance of
getting a cucumber for cucumbers that are over 1 in 10 like [1 in 10] in white. make last cucumbers
in index of each biome much rarer, and it would be like [1 in x] chance it would say, in gold. index
trail reward - gives more strength power thing (like the headbands, stacks on top of headbands) -
equip/unequip trails directly from index via the claim button. make several trails (one for each
biome) - earned after getting every one of the cucumber in that biome."*

Place: **New Map Cucumber Game** (`place:87967102884366`). Not saved / published by me.

## What the spawner actually does (the rates)

`ServerScriptService.CucumberSpawner`: **six cucumbers per biome at dawn = 2 fixed sliced slots
("S" type) + 4 regular rolls**, no replenishment during the day (collected ones stay gone until the
next dawn). Days last 180 s + a 45 s night (`DayNightCycle` attributes), so a biome gets **64 regular
rolls per real hour**, and every server rolls the same morning (the day number seeds the dice).

**Before this change the "last" cucumber (the biome's `T` landmark tree) was the COMMONEST regular
cucumber, not the rarest**: `SpawnBreakable` forced the first regular roll of every biome to the tree
whenever none stood ("every zone keeps at least one tree standing: it's the landmark payday"), so it
spawned every single day in every biome (about 1.03-1.06 per biome per day, see the table).

**Now:** the forced tree is gone. Each regular roll is the landmark with probability
`1 / LANDMARK_ODDS[zone]` (one standing per biome at most); otherwise it is a RAW-weight draw over the
other regular types. The landmark's RAW weight is ignored.

```lua
-- CucumberSpawner
local LANDMARK_ODDS = {Spawn = 100, Desert = 150, Samurai = 200, Farm = 250, Snow = 300,
                       Underwater = 400, Volcano = 500, Narmek = 650, Toyland = 800, Neon = 1000}
```

`StampOdds(zone)` writes `Odds` ("1 in Odds" **per regular roll**) and `Landmark = true` onto every
type def before `Adventure.SetCatalog`, so the Index shows exactly what the dice do. Sliced types
get no odds (they are the fixed slots: 2 of 6 every day, "1 in 3" of everything that spawns).

Full table (`stage/rates.py` prints it; `stage/rates.md` is its output). Old per day = the forced-tree
code; New per day = 4 rolls x per-roll chance; the gap is real time between expected spawns of that
type in ONE biome:

| Biome | Cucumber | Weight | Old per day | New per roll | Index shows | New per day | Real-time gap |
|---|---|---|---|---|---|---|---|
| Spawn | Sliced Cucumber | fixed | 2 (2 slots) | slice slot | - | 2 | every day |
| Spawn | Cucumber | 61 | 1.81 | 1 in 1.6 | - | 2.440 | 2 min |
| Spawn | Slice Stack | 24 | 0.71 | 1 in 4.2 | - | 0.960 | 4 min |
| Spawn | Vined Cucumber | 10 | 0.30 | 1 in 10.0 | [1 in 10] | 0.400 | 9 min |
| Spawn | Flowered Cucumber | 4 | 0.12 | 1 in 25.0 | [1 in 25] | 0.160 | 23 min |
| Spawn | Cucumber Tree | 2 | 1.06 | 1 in 100.0 | **[1 in 100]** (gold) | 0.040 | 1.6 h |
| Desert | Sun-Dried Slice | fixed | 2 (2 slots) | slice slot | - | 2 | every day |
| Desert | Prickly Cucumber | 46 | 1.39 | 1 in 2.1 | - | 1.865 | 2 min |
| Desert | Sliced Cucumber | 25 | 0.76 | 1 in 3.9 | - | 1.014 | 4 min |
| Desert | Sun-Baked Cucumber | 14 | 0.42 | 1 in 7.0 | - | 0.568 | 7 min |
| Desert | Wrapped Cucumber | 7 | 0.21 | 1 in 14.1 | [1 in 14] | 0.284 | 13 min |
| Desert | Cactus Cucumber | 4 | 0.12 | 1 in 24.7 | [1 in 25] | 0.162 | 23 min |
| Desert | Desert Palm | 2 | 0.06 | 1 in 49.3 | [1 in 49] | 0.081 | 46 min |
| Desert | Sandstone Tree | 1 | 1.03 | 1 in 150.0 | **[1 in 150]** (gold) | 0.027 | 2.3 h |
| Samurai | Sliced Cucumber | fixed | 2 (2 slots) | slice slot | - | 2 | every day |
| Samurai | Katana Cucumber | 53 | 1.59 | 1 in 1.9 | - | 2.131 | 2 min |
| Samurai | Bamboo Cucumber | 25 | 0.75 | 1 in 4.0 | - | 1.005 | 4 min |
| Samurai | Lantern Cucumber | 12 | 0.36 | 1 in 8.3 | - | 0.482 | 8 min |
| Samurai | Bamboo Grove | 6 | 0.18 | 1 in 16.6 | [1 in 17] | 0.241 | 16 min |
| Samurai | Torii Gate | 3 | 0.09 | 1 in 33.2 | [1 in 33] | 0.121 | 31 min |
| Samurai | Sakura Tree | 1 | 1.03 | 1 in 200.0 | **[1 in 200]** (gold) | 0.020 | 3.1 h |
| Farm | Cucumber Basket | fixed | 2 (2 slots) | slice slot | - | 2 | every day |
| Farm | Muddy Cucumber | 61 | 1.81 | 1 in 1.6 | - | 2.455 | 2 min |
| Farm | Crate Cucumber | 24 | 0.71 | 1 in 4.1 | - | 0.966 | 4 min |
| Farm | Windmill Plant | 10 | 0.30 | 1 in 9.9 | [1 in 10] | 0.402 | 9 min |
| Farm | Hay Bale | 4 | 0.12 | 1 in 24.8 | [1 in 25] | 0.161 | 23 min |
| Farm | Cucumber Tree | 2 | 1.06 | 1 in 250.0 | **[1 in 250]** (gold) | 0.016 | 3.9 h |
| Snow | Frozen Slice | fixed | 2 (2 slots) | slice slot | - | 2 | every day |
| Snow | Snowcap Cucumber | 46 | 1.39 | 1 in 2.1 | - | 1.871 | 2 min |
| Snow | Snowball Slice | 25 | 0.76 | 1 in 3.9 | - | 1.017 | 4 min |
| Snow | Crystal Cucumber | 14 | 0.42 | 1 in 7.0 | - | 0.570 | 7 min |
| Snow | Frozen Cucumber | 7 | 0.21 | 1 in 14.0 | [1 in 14] | 0.285 | 13 min |
| Snow | Snow Tree | 4 | 0.12 | 1 in 24.6 | [1 in 25] | 0.163 | 23 min |
| Snow | Icicle Tree | 2 | 0.06 | 1 in 49.2 | [1 in 49] | 0.081 | 46 min |
| Snow | Frozen Tree | 1 | 1.03 | 1 in 300.0 | **[1 in 300]** (gold) | 0.013 | 4.7 h |
| Underwater | Bubble Slice | fixed | 2 (2 slots) | slice slot | - | 2 | every day |
| Underwater | Seaweed Cucumber | 46 | 1.39 | 1 in 2.1 | - | 1.873 | 2 min |
| Underwater | Shell Slice | 25 | 0.76 | 1 in 3.9 | - | 1.018 | 4 min |
| Underwater | Coral Cucumber | 14 | 0.42 | 1 in 7.0 | - | 0.570 | 7 min |
| Underwater | Pearl Cucumber | 7 | 0.21 | 1 in 14.0 | [1 in 14] | 0.285 | 13 min |
| Underwater | Kelp Tree | 4 | 0.12 | 1 in 24.6 | [1 in 25] | 0.163 | 23 min |
| Underwater | Bubble Tree | 2 | 0.06 | 1 in 49.1 | [1 in 49] | 0.081 | 46 min |
| Underwater | Coral Tree | 1 | 1.03 | 1 in 400.0 | **[1 in 400]** (gold) | 0.010 | 6.2 h |
| Volcano | Molten Slice | fixed | 2 (2 slots) | slice slot | - | 2 | every day |
| Volcano | Charred Cucumber | 53 | 1.59 | 1 in 1.9 | - | 2.137 | 2 min |
| Volcano | Molten Cucumber | 25 | 0.75 | 1 in 4.0 | - | 1.008 | 4 min |
| Volcano | Flame Cucumber | 12 | 0.36 | 1 in 8.3 | - | 0.484 | 8 min |
| Volcano | Obsidian Tree | 6 | 0.18 | 1 in 16.5 | [1 in 17] | 0.242 | 15 min |
| Volcano | Volcano Cucumber | 3 | 0.09 | 1 in 33.1 | [1 in 33] | 0.121 | 31 min |
| Volcano | Magma Tree | 1 | 1.03 | 1 in 500.0 | **[1 in 500]** (gold) | 0.008 | 7.8 h |
| Narmek | Moon Slice | fixed | 2 (2 slots) | slice slot | - | 2 | every day |
| Narmek | Meteor Cucumber | 46 | 1.39 | 1 in 2.1 | - | 1.875 | 2 min |
| Narmek | Planet Slice | 25 | 0.76 | 1 in 3.9 | - | 1.019 | 4 min |
| Narmek | Astronaut Cucumber | 14 | 0.42 | 1 in 7.0 | - | 0.571 | 7 min |
| Narmek | Neon Alien Cucumber | 7 | 0.21 | 1 in 14.0 | [1 in 14] | 0.285 | 13 min |
| Narmek | Moon Tree | 4 | 0.12 | 1 in 24.5 | [1 in 25] | 0.163 | 23 min |
| Narmek | Alien Tree | 2 | 0.06 | 1 in 49.1 | [1 in 49] | 0.082 | 46 min |
| Narmek | Galaxy Tree | 1 | 1.03 | 1 in 650.0 | **[1 in 650]** (gold) | 0.006 | 10.2 h |
| Toyland | Toy Slice | fixed | 2 (2 slots) | slice slot | - | 2 | every day |
| Toyland | Lego Cucumber | 53 | 1.59 | 1 in 1.9 | - | 2.139 | 2 min |
| Toyland | Jack-in-the-Box Cucumber | 25 | 0.75 | 1 in 4.0 | - | 1.009 | 4 min |
| Toyland | Toy Rocket Cucumber | 12 | 0.36 | 1 in 8.3 | - | 0.484 | 8 min |
| Toyland | Pinwheel Plant | 6 | 0.18 | 1 in 16.5 | [1 in 17] | 0.242 | 15 min |
| Toyland | Building Block Tree | 3 | 0.09 | 1 in 33.0 | [1 in 33] | 0.121 | 31 min |
| Toyland | Toy Train Cucumber | 1 | 1.03 | 1 in 800.0 | **[1 in 800]** (gold) | 0.005 | 12.5 h |
| Neon | Neon Slice | fixed | 2 (2 slots) | slice slot | - | 2 | every day |
| Neon | Electro Cucumber | 53 | 1.59 | 1 in 1.9 | - | 2.139 | 2 min |
| Neon | Neon Grid Cucumber | 25 | 0.75 | 1 in 4.0 | - | 1.009 | 4 min |
| Neon | Hologram Cucumber | 12 | 0.36 | 1 in 8.3 | - | 0.484 | 8 min |
| Neon | Neon Palm | 6 | 0.18 | 1 in 16.5 | [1 in 17] | 0.242 | 15 min |
| Neon | Neon Tree | 3 | 0.09 | 1 in 33.0 | [1 in 33] | 0.121 | 31 min |
| Neon | Cyber Cucumber | 1 | 1.03 | 1 in 1000.0 | **[1 in 1,000]** (gold) | 0.004 | 15.6 h |

Because the dice are shared, a landmark day is the same day on every server: when the Galaxy Tree
comes, it comes everywhere at once and stands until someone in that server lifts it.

## Index cards

`StarterGui.CucumberMenus.IndexView` (+ a new authored `Templates.CucumberCard.Chance` TextLabel,
FredokaOne, TextScaled, right-aligned on the card's top row between the `#NN` number and the collected
check; `stage/install_template.lua` adds it, and IndexView clones `Number` if it is ever missing):

- `[1 in X]` in **white** when the per-roll odds round to **1 in 10 or rarer** (`CHANCE_MIN = 10`);
  nothing on commoner cards and on the sliced card.
- the biome's **landmark** (`Landmark = true`, always the last card because it has the highest
  `CucumberValues` reward) shows its odds in **gold** (255, 214, 64).
- rounding: nearest integer below 100, two significant digits from 100 up, thousands separators
  (`9.9 -> 10`, `24.7 -> 25`, `1000 -> 1,000`, `1234 -> 1,200`).
- the payload: `CucumberAdventure.SetCatalog` keeps `Odds` / `Landmark` per name (`meta`), the
  `CucumberCollectionBook` snapshot sends them per card plus `Trail` / `StrengthMult` per row.

Reward button (`Content.EquipReward`, the authored "claim" button): **LOCKED** (lock icon) until the
biome is complete, then **EQUIP TRAIL** / **UNEQUIP TRAIL**. `Footer` reads
`Collect every Spawn cucumber to unlock the Sprout Trail (2x strength)` /
`Sprout Trail unlocked! Equip it: 2x strength, stacks with headbands` /
`Sprout Trail equipped: 2x strength (stacks with your headband)`.

## Trails (`ReplicatedStorage.Modules.CollectionTrails`, new)

One per biome, earned when `CucumberAdventure` marks the family complete (every cucumber of the biome
`Seen`), one worn at a time (`data.CucumberCollection.Equipped = zone`, the existing save key):

| Biome | Trail | Strength | Look |
|---|---|---|---|
| Spawn | Sprout Trail | 2x | lime -> green ribbon, falling green sparkles |
| Desert | Dune Trail | 3x | sand -> amber, tan dust puffs (smoke texture) |
| Samurai | Sakura Trail | 4x | pink -> blush, drifting pink petals (sparkles) |
| Farm | Harvest Trail | 5x | hay gold -> amber, gold sparkles |
| Snow | Frost Trail | 6x | ice blue -> white, white flakes |
| Underwater | Tide Trail | 7x | cyan -> deep blue, rising white bubbles |
| Volcano | Ember Trail | 8x | orange -> red, rising embers (fire texture), strong glow |
| Narmek | Galaxy Trail | 9x | violet -> magenta -> midnight, spinning star sparkles |
| Toyland | Confetti Trail | 10x | rainbow ribbon, falling multicolour confetti |
| Neon | Cyber Trail | 11x | cyan -> magenta, full light emission |

Built from engine textures only (`rbxasset://textures/particles/{sparkles,smoke,fire}_main.dds`),
nothing uploaded: a wide soft `Trail` (`CollectionTrail`) + a thin bright core (`CollectionTrailCore`)
between attachments on the back of the `HumanoidRootPart`, plus a `ParticleEmitter`
(`CollectionTrailParticles`). Everything carries the attribute `CollectionTrailZone = zone`;
`Clear(character)` removes only those root children (a carried cucumber's own old
`CollectionTrail` is untouched).

**Strength:** `GymService.StrengthPerRep = 2^(bench level - 1) x HeadbandMultiplier x
TrailMultiplier`, `TrailMultiplier(data)` = `CollectionTrails.StrengthMultOf(Equipped)` only while
`Families[Equipped]` is true (1x otherwise). `CucumberAdventure.equip` calls `GymService.Refresh`
so the `StrengthPerRep` attribute, the bench board and `TimeSkipService` quotes follow at once.
Verified in the playtest with the test profile (bench 8, Champion Band 13x): 1664 -> 3328 with the
Sprout Trail (2x), 13312 with the Ember Trail (8x), back to 1664 on unequip.

Server side (`ServerStorage.CucumberAdventure`): `dress(player)` = `Trails.Wear` on profile load, every
`CharacterAdded` and every equip (the old "<Zone> Collector" head title is GONE - user 2026-09-23:
"remove index titles i just wanted trails"; `clearTitle` only removes a leftover billboard); the
completion message names the trail and its multiplier. The carried-cucumber ribbon (`ApplyCosmetic`) is unchanged.

## Files

- `src/CollectionTrails.lua` -> `ReplicatedStorage.Modules.CollectionTrails` (new)
- `src/CucumberSpawner.server.lua`, `src/CucumberAdventure.lua`, `src/GymService.lua`,
  `src/IndexView.lua` = the live sources after the push; `orig/` = as pulled before; `live-before/`
  = the raw CRLF mirrors of everything read (DataService, TimeSkipService, HeadbandService,
  CucumberCarry, DayNightCycle, MenuController, MenuClient, IndexController included for reference)
- `stage/patches.json` = the surgical hunks (`pets-remake/mkpatch.py orig src`), applied with
  `pets-remake/apply_patches.lua` served by `pets-remake/serve.ps1 -Port 8792 -Root stage`
  (dry run first); `stage/install_template.lua` = the Chance label; `stage/rates.py` / `rates.md`
- backup before the push: `backups/NewMap_index-rarity-trails_before_2026-09-23.rbxm`
  (CucumberSpawner, CucumberAdventure, GymService, the whole CucumberMenus ScreenGui)

## Dev hooks + test recipe

`ServerStorage.CucumberAdventure:SetAttribute("AdventureDev", cmd)` (Studio only, from
`eval_server_runtime`): `complete:<zone>[:<player>]`, `reset:<zone>[:<player>]`,
`equip:<zone>[:<player>]`, `unequip[:<player>]` (player defaults to the first one). Two commands
need a `task.wait` between them (deferred attribute signals collapse same-frame writes).

Verified 2026-09-23 in a solo playtest (test profile `PetTest_140977250`, so nothing touched the real
save): morning `Day 6878: 60 cucumbers ... 0 trees standing` (the forced tree is gone), the book
payload carries the odds above, the Spawn page showed `[1 in 10]` / `[1 in 25]` white and
`[1 in 100]` gold, the real UNEQUIP / EQUIP clicks (simulate_mouse_input on the button) toggled the
trail instances, the attribute and the footer, and `AdventureDev complete/equip/reset` round-tripped.

## Gotchas

- `HasStandingTree` must be declared ABOVE `PickType` now (PickType captures it as an upvalue).
- `TreeTypeFor` in the spawner is now unused (kept).
- The Index panel's `Content` is a CanvasGroup under a `ResponsiveScale`; the Chance label's
  `TextScaled` fit is width-bound (`[1 in 1,000]` is 12 characters), which is why the label starts at
  x 72 (right after `#NN`) and widens to 170 when the collected check is hidden.
- Night resets any `Scriptable` playtest camera (the raid cutscene) - take trail screenshots in the day.
