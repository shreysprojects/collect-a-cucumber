# Pet system polish - implementation handoff

**Game:** New Map Cucumber Game · **PlaceId:** `87967102884366`
**Inspected:** September 22, 2026, through the connected chxxrz Roblox Studio MCP.
**Status:** Planning only. No game scripts, instances, balance settings, or player data were changed for this plan.

This document specifies a complete first release: pet income, occasional cucumber buffs, zombie combat, persistence, management UI, effects, and verification. Observations below describe the inspected game; all new numbers and behavior are **recommended starting designs**, not existing features or playtested balance. The implementing model should re-read the affected live scripts before patching because the place can change after this inspection.

## 1. Player experience and release boundaries

Hatch a pet from an existing egg. Its species, rarity, and inherited egg mutations determine its stats. Equip it in one of **six free active slots**. Active pets roam your plot, generate cash every second, and shoot approaching zombies. Some species also make a rare roll every minute of active online time to buff one random cucumber on your own plot.

The pet menu makes all three contributions understandable: **cash/sec, damage and attack interval, and a special ability with its actual chance**. Cucumbers show temporary boost icons and remaining time. A successful ability sends a short colored effect from the pet to the cucumber, with one owner notification.

Recommended first-release rules:

- Six active pets; remaining owned pets stay in a reserve inventory. Reserve pets do not earn, fight, or roll abilities. This is a new limit needed to bound economy and combat; never delete existing pets when introducing it.
- Duplicate species are allowed and remain separate owned pets with unique IDs.
- No pet leveling, fusion, trading, pet death, healing, hunger, paid slots, or offline pet earnings in this release. These would add separate progression and persistence work.
- Pets defend their owner's plot, including daytime thieves. They do not follow the player into portals or attack biome guardians, players, or another player's raid.
- All active pets earn and fight. Species without a cucumber ability receive a modest combat bonus so they still have a role.
- Existing hatch odds, egg prices, egg stock, cucumber mutation math, towers, bench rewards, cash HUD positioning/color, night timer, and Slow Mode remain compatible.
- Equip changes are allowed in daytime while the owner has no live raid/daytime thief. A hatch during combat goes to reserve until combat ends; do not let a fresh hatch bypass the roster lock.
- Pets and their systems are server authoritative. Clients display menus and effects, never calculate rewards, choose proc results, or deal damage.

## 2. What exists in the inspected place

Paths in this document are Roblox DataModel paths, not filesystem files. Line references are inspection anchors and will move as scripts are edited.

| Existing component | Verified behavior | Consequence for this update |
|---|---|---|
| `ReplicatedStorage.Modules.PetsCatalog` | 49 species across eight eggs, including secret Gregory. Stores weighted odds, internal names, display names, rarity, and models. | Preserve internal names and odds. Add a separate balance module rather than replacing the hatch catalog. |
| `ServerScriptService.PetHatchService` | Handles reveal, spawning, and roam plans. Pets live under `plot.Pets`, tagged `PlotPet`. | Separate ownership/gameplay from reveal; extract spawn/roam ownership into PetService. |
| `StarterPlayer.StarterPlayerScripts.PetRoamClient` | Moves anchored pet models on each client using replicated roam attributes. | A server model's physical pivot is not its current visible position. Combat needs shared logical motion. |
| `ServerScriptService.LeaderstatsService` | Calculates cucumber rates, pays cash every second, sets `Data.CashPerSec`, emits `Remotes.CucumberIncome`. | Extend one income authority. Do not add a second independent pet cash loop. |
| `ServerScriptService.BaseSaveService` | Saves cucumbers, builds, pets, and eggs in `Data.Base`. A pet currently saves only `{Pet, Pos}`. | New pet identity, mutations, roster, and cooldown data must survive snapshots and failed restores. |
| `ServerStorage.DataService` | Uses ProfileStore; reconciles data before loaded callbacks; callbacks run in spawned tasks. | Migrate before callbacks. Do not rely on callback registration order. |
| `ReplicatedStorage.Modules.CucumberValues` | Base income depends on biome, species, material, mutations, and size. Biomes scale by 8. | Keep this base formula unchanged; apply temporary boosts in the income layer. |
| `ReplicatedStorage.Modules.CucumberMutations` | Golden ×12, Diamond ×50; mutation products can reach a 5,000 cap before size multipliers. | Those multipliers are too large to reuse directly for pet damage. Define pet-specific scaling. |
| `ServerScriptService.ZombieRaidService` | Owns targets, theft, grapples, digging, damage, drops, and raid lifecycle. Exposes `ServerStorage.ZombieAPI`. | Pets use the existing damage API; shield checks must cover every theft path. |
| `ServerScriptService.DefenceService` | Towers already use `ZombieAPI.Zombies` and `Damage`. Turret baseline is 12 damage / 0.45 seconds. | Pets should complement towers. Leave tower damage unchanged for the first release. |
| `StarterGui.CucumberMenus.MenuController` | Shared Shop/Index opening, sizing, transitions, and closing. Assumes a left-menu opener for every panel. | Register a Pets panel and explicitly support its separate opener. |
| `StarterGui.CucumberHUDDesign.BaseHUDController` | Swaps Shop/Index with Build/Manage; bench offer occupies another state. | Do not insert a new button into those slots without updating layout/state logic. |

### Issues the implementation must fix or account for

1. **Reveal-dependent ownership:** `PetHatchService` destroys the egg after starting the reveal, but spawns the pet when reveal completion or an 80-second fallback runs. Pending state is discarded on leave. Commit ownership before the reveal so leaving mid-animation cannot lose a successfully recorded hatch.
2. **Egg traits are dropped:** material/mutations reach the egg reveal payload but not the saved pet/spawn record. Preserve them when granting the pet.
3. **No stable identity:** current pet saves have no ID. Display names differ from internal model keys; using display names as save keys would break restoration.
4. **World snapshots are incomplete ownership records:** a failed pet spawn is not preserved like failed cucumber restores are. It can disappear from a later snapshot. Ownership must not depend on a model successfully spawning.
5. **Stale server pet pivots:** combat origins and saved positions cannot use `pet:GetPivot()` while clients alone animate roaming.
6. **Raid difficulty currently reads total cash/sec:** `ZombieRaidService.IncomeOf` reads `Data.CashPerSec`; `ThreatOf` passes it into `ZombieCatalog.ThreatOf`. Adding pet income there would quietly increase raid difficulty. Use unboosted cucumber income for this input.
7. **Combat can accidentally change aggro:** the fourth argument to `ZombieAPI.Damage` marks a raid hostile to an attacking player. Pet attacks should use tower-style damage without that fourth player argument.
8. **Protection cannot be a targeting-only filter:** grapplers physically move a cucumber before the final `Grab`; check protection before the pull and again if a new shield appears before final capture.
9. **Version mismatch:** BaseSaveService uses base version 2, while the DataService template still says 1. Existing version-1 cucumber migration deliberately discards old-format cucumber geometry. Do not trigger or broaden that wipe as part of pet migration.
10. **Actual cycle settings differ from a comment:** script attributes are 180-second days and **45-second nights**, despite a header mentioning 10-second nights. Use attributes, not that comment.
11. **Leave/save ordering:** DataService ends the profile session in its leave handler; BaseSaveService's leave handler cleans up world instances. Introduce an explicit pre-close flush hook rather than assuming independently connected leave events run in a safe order.

## 3. Recommended starting balance

Keep all new numbers in `ReplicatedStorage.Modules.PetBalance`, with pure stat calculation in `PetStats`. Gameplay code and UI both read these tables. The server still validates everything independently.

### 3.1 Rarity and egg progression

| Rarity | Income multiplier | Base shot damage | Base interval | Range, studs | Ability chance per 60 active seconds |
|---|---:|---:|---:|---:|---:|
| Common | 1.0 | 3 | 2.50 s | 26 | 1% |
| Uncommon | 1.5 | 5 | 2.25 s | 29 | 2% |
| Rare | 2.5 | 8 | 2.00 s | 32 | 4% |
| Legendary | 5.0 | 12 | 1.75 s | 35 | 8% |
| Mythical | 10.0 | 18 | 1.50 s | 38 | 12% |

The current roster does not contain Epic pets. Do not reclassify existing pets or invent an Epic tier just because the catalog has an unused color for it. Unknown future rarities should produce a configuration warning and conservative fallback stats, never crash a profile load.

| Egg | Income/combat tier | Equivalent cucumber zone | Base pet cash/sec before rarity/rank/traits |
|---|---:|---|---:|
| Basic Egg | 1 | Spawn | 0.5 |
| Desert Egg | 2 | Desert | 4 |
| Samurai Egg | 3 | Samurai | 32 |
| Farm Egg | 4 | Farm | 256 |
| Frozen Egg | 5 | Snow | 2,048 |
| Ocean Egg | 6 | Underwater | 16,384 |
| Lava Egg | 7 | Volcano | 131,072 |
| Narmek Egg | 8 | Narmek | 1,048,576 |

Explicitly map Frozen→Snow, Ocean→Underwater, and Lava→Volcano. Do not infer zones from display strings. Toyland and Neon currently have no pet egg in this catalog; leave them alone.

### 3.2 Income formula

```text
BaseIncome       = 0.5 × 8^(eggTier - 1)
RankMultiplier   = 1 + 0.10 × (rank - 1)        -- ranks 1 through 6
PetCashPerSecond = BaseIncome × RarityIncome × RankMultiplier × AffixIncome
```

Gregory has no current catalog rank: use an explicit balance rank of 6 while leaving its hatch catalog entry untouched. Rarity is not multiplied a second time through hatch odds. Egg weight/visual size gives **no additional stat multiplier in v1**; retain weight as provenance only.

Examples, with no material/mutations:

- Cucumber Deer / internal `Cat`: Basic, Common, rank 1 → **$0.50/sec**.
- Meadow Bunny / `Fox`: Basic, Legendary, rank 6 → **$3.75/sec**.
- Gregory: Basic, Mythical, balance rank 6 → **$7.50/sec**, plus Mythical combat and a flexible ability. Its Basic-egg income intentionally remains below later biomes; reassess this particular secret-pet tradeoff during balance review.
- Oasis Turtle / `Chest`: Desert, Uncommon, rank 4 → **$7.80/sec**.
- Cosmo Cat: Narmek, Mythical, rank 6 → **$15,728,640/sec**.

Pet income is paid automatically into existing Cash. Keep fractional values internally and abbreviate only for display. A $0.50/sec pet must earn $30 over 60 uninterrupted seconds; never round each payout down to zero.

### 3.3 Material and mutation inheritance

At hatch, copy the egg's material and distinct mutation names into the pet record, with **no second mutation roll**. Preserve original metadata for unknown names, but ignore unknown entries in calculations and report a bounded diagnostic. Never reinterpret a bad name as a premium mutation.

| Material | Pet income factor | Combat affinity points |
|---|---:|---:|
| Normal / empty | 1.0 | 0 |
| Golden | 1.5 | 0.05 |
| Diamond | 2.0 | 0.10 |

| Mutation | Added income bonus | Combat affinity points |
|---|---:|---:|
| NEON | +0.15 | +0.02 |
| SHADOW | +0.20 | +0.03 |
| FROZEN | +0.25 | +0.03 |
| RADIOACTIVE | +0.30 | +0.04 |
| MOLTEN | +0.30 | +0.04 |
| ROYAL | +0.50 | +0.05 |
| VOID | +1.00 | +0.08 |
| PRISMATIC | +2.00 | +0.12 |

```text
AffixIncome = min(8, MaterialIncome × (1 + sum(distinct mutation income bonuses)))
AffixDamage = 1 + min(0.25, material combat points + sum(distinct mutation combat points))
```

Example: Golden NEON ROYAL income factor = `1.5 × (1 + .15 + .50) = 2.475`. These are **pet multipliers**, not changes to CucumberMutations.TotalMult. Materials/mutations do not also increase proc chance or decrease attack interval in this release.

### 3.4 Combat formula

```text
BiomeDamageFactor = 1 + 0.05 × (eggTier - 1)
FighterFactor     = 1.15 if ability == None, otherwise 1.0
ShotDamage        = RarityShotDamage × BiomeDamageFactor × AffixDamage × FighterFactor
ShotInterval      = RarityBaseInterval
NominalDPS        = ShotDamage / ShotInterval
```

Higher rarity improves both damage and attack speed. Later eggs add a modest combat increase; they do **not** use the economy's ×8 scaling for damage. Keep fractional damage. No critical hits, splash, slowing, poison, or armor bypass yet.

A normal Cucumber Deer is 3 damage every 2.5 seconds, or 1.2 nominal DPS. An unmutated Narmek Mythical support pet is 24.3 damage every 1.5 seconds, or 16.2 DPS; maximum affix damage makes it 20.25 DPS. Six such pets can be powerful, especially against a 900-HP Titan, so test full teams as well as individual pets. These are proposed numbers, not a claim that raids are already balanced around them.

## 4. Cucumber abilities

### 4.1 Three effects

| Config key / display name | Effect | Duration | Visual |
|---|---|---|---|
| `Yield` / Lucky Harvest | Target cucumber earns ×1.50 its normal cash/sec. | 90 seconds | Gold coin sparkle and ×1.5 badge |
| `Haste` / Quick Grow | Target cucumber produces 25% faster: ×1.25 cash/sec. | 90 seconds | Cyan clock/arrow and +25% badge |
| `Guard` / Leaf Shield | Blocks one zombie theft attempt against that cucumber. | One charge, up to one full configured day/night cycle + 15 seconds | Green shield shell and one-charge badge |

At the inspected 180/45 cycle, a shield lasts at most **240 seconds**. Compute that duration when granted from the server's current cycle attributes, capped at 600 seconds for unusual admin settings. A later cycle configuration change does not extend already granted shields.

**Haste semantics:** both cucumber and pet cash continue to settle on the shared one-second income cadence. Quick Grow means +25% production, not a second payout loop. Use a faster local production sparkle/progress effect if desired; never send extra cash because an animation loop runs faster. This keeps “more money” and “faster production” understandable without introducing duplicate timers.

### 4.2 Timing and randomness

1. Only species assigned an ability roll. Each newly equipped ability pet starts a 60-second **active online** countdown.
2. Decrement with elapsed active time while the owner profile and plot are ready and the pet has successfully spawned. Presentation-pending, unavailable, and reserve pets do not advance the countdown. Normal earning and combat do not pause it.
3. At zero, reset to 60 **before** processing the roll. Draw once on the server using the rarity chance. A long server hitch must not replay a backlog of rolls.
4. On success, choose one uniformly random eligible cucumber on that owner's plot. Do not preferentially choose the most valuable cucumber.
5. No eligible target means no effect and no queued reward; the attempt is consumed. Do not reroll until a target is found.
6. Gregory uses `Wild`: choose uniformly from the ability types that currently have at least one eligible target, then choose a target uniformly within that type. Still only one chance roll and one effect per minute.
7. Unequipping resets that pet's countdown to 60. Re-equipping does not give an instant roll. Leaving/rejoining preserves the saved remaining countdown, paused offline; no offline proc accumulation.
8. Store remaining time in the loaded profile as gameplay advances and request a coalesced save after each roll/roster change. Do not request a datastore write on every countdown step. Normal autosave limitations still apply to an abrupt server crash.
9. Use one shared scheduler for these countdowns, not a forever-loop per pet. Spread initial countdown phases across players through join/equip times; do not roll every pet in the entire server at a global minute boundary.

For perspective, a single Legendary ability pet averages one successful roll every 12.5 active minutes, before eligibility failures. Six Mythical ability pets make an expected 0.72 successful rolls per minute; chance of at least one success across their six rolls is `1 - .88^6 ≈ 53.6%`. The individual events remain rare, but a good full team is noticeably useful. Show the chance, not an “ability ready in” promise.

### 4.3 Eligibility, stacking, and persistence

- Must be an owned `PlacedCucumber`, under the owner's current plot, still live, and neither stolen nor actively being moved/carried. Restore must be complete before eligibility.
- One active effect per type per cucumber. A Yield pet cannot target a cucumber already carrying Yield; likewise Haste and Guard. No duration refreshing by repeated same-type procs.
- Yield and Haste may coexist: combined rate multiplier is **1.875**, below a defensive hard cap of 2.0. Guard may coexist with both.
- No pet-on-pet buffs, no buffs to builds, and no boosts to the pet's own income from these abilities. Material and cucumber mutation multiplication happen before temporary effects.
- Store a stable `CucumberId` and each active effect's absolute expiry, kind, source pet ID, and charge count in the cucumber's saved record. Restore only unexpired valid effects. Offline time consumes duration but earns nothing.
- Moving a cucumber within the same plot preserves identity and remaining buffs; settle its earnings before state changes. Pickup, ownership change, permanent removal, or a successful steal clears its pet buffs. It must not return from a theft with an old shield silently restored.
- Unequipping the source pet does not cancel an already granted timed effect. This does not create extra rolls because newly equipped pets must wait 60 seconds.
- If a saved source pet is now unavailable, an already valid granted buff may finish its remaining duration. Its benefit belongs to the target, not a live source-model reference.

### 4.4 Exact protection behavior

Add a synchronous, non-yielding `TryBlockTheft(cucumber, zombie, now)` in PetBuffService. It validates the cucumber, checks expiry, atomically consumes one live charge, marks the record dirty, and emits a shield-break effect. It returns `true` when this attempt is denied.

When blocked, the zombie loses that target, briefly recoils/stuns for 0.8 seconds through the existing API, then resumes normal AI. Give the cucumber a **1.5-second theft rejection grace** after the charge is consumed, preventing another zombie from taking it in the same frame. Grace is a short runtime consequence of the block, not a new renewable shield; reject attempts during grace without consuming additional charges.

Integration points in ZombieRaidService:

1. Before ordinary `Grab` removes `PlacedCucumber`, reparents, welds, or sets `StolenBy`.
2. Before `StartGrapple` starts its physical pull. A blocked grapple must terminate the entire attempt.
3. At final grapple capture through `Grab`, in case a new shield was applied mid-pull. On denial, restore the cucumber to the correct recorded rest pose and clean up beam/anchor/path state.
4. Digging/surfacing capture must still pass the same final `Grab` guard.
5. Do not consume shields merely because a zombie considers or walks toward the target. Do not remove protected cucumbers from the raid's cucumber count or threat input; protection is a consumable defense, not invisibility.
6. Shield blocking awards no stolen count, kill reward, or fake “saved from carrying” reward. Existing cucumber drop/return handling remains authoritative.

## 5. Species assignments - all 49 current pets

Use the **internal key** in config/save records. The display column is only UI. `None` means a fighter with +15% shot damage. All rows still generate income and attack. No hatch weights or rarities are changed.

| Egg | Internal key | Display name | Rarity | Ability |
|---|---|---|---|---|
| Basic | Cat | Cucumber Deer | Common | Yield |
| Basic | Dog | Moss Turtle | Common | Guard |
| Basic | Bunny | Sprout Pup | Uncommon | None |
| Basic | Wolf | Bloom Bee | Rare | Haste |
| Basic | Tabby | Vine Gecko | Rare | None |
| Basic | Fox | Meadow Bunny | Legendary | Yield |
| Basic | Gregory | Gregory | Mythical | Wild |
| Desert | Barrel | Dune Scorpion | Common | None |
| Desert | Treasure Gem | Cactus Fox | Common | Yield |
| Desert | Cannon | Sand Scarab | Common | None |
| Desert | Chest | Oasis Turtle | Uncommon | Guard |
| Desert | Desert Overlord | Sun Lizard | Rare | None |
| Desert | Cactus | Relic Cobra | Legendary | Haste |
| Samurai | Dog Ninja | Sakura Kitsune | Common | None |
| Samurai | Good Ninja | Bamboo Panda | Uncommon | Guard |
| Samurai | Evil Ninja | Ronin Beetle | Uncommon | None |
| Samurai | Good Samurai | Lantern Crane | Rare | Yield |
| Samurai | Evil Samurai | Kappa Cub | Rare | None |
| Samurai | Sensei | Torii Dragon | Legendary | Haste |
| Farm | Hay | Barn Chick | Common | None |
| Farm | Bird | Hay Pup | Common | Haste |
| Farm | Panda | Tractor Beetle | Uncommon | None |
| Farm | Cow | Patch Piglet | Uncommon | Guard |
| Farm | Pig | Windmill Lamb | Rare | None |
| Farm | Farmer | Harvest Cow | Legendary | Yield |
| Frozen | Red Snowman | Frost Penguin | Common | None |
| Frozen | Blue Snowman | Glacier Wolf | Common | Haste |
| Frozen | Frozen Dragon | Snowy Seal | Uncommon | None |
| Frozen | Frozen Hydra | Icicle Owl | Uncommon | Guard |
| Frozen | Frozen Ice Shock | Polar Cub | Rare | None |
| Frozen | Frozen Gem | Crystal Hare | Legendary | Yield |
| Ocean | Oceanic Dog | Coral Axolotl | Common | None |
| Ocean | Oceanic Kitty | Bubble Turtle | Common | Guard |
| Ocean | Oceanic Bunny | Kelp Seahorse | Uncommon | None |
| Ocean | Oceanic Bear | Pearl Crab | Uncommon | Yield |
| Ocean | Ocean Dragon | Starfish Pup | Rare | None |
| Ocean | Atlantic Hydra | Clown Ray | Legendary | Haste |
| Lava | Lava Plume | Magma Hound | Common | None |
| Lava | Lava Golem | Ember Bat | Common | Haste |
| Lava | Lava Veltal | Obsidian Golem | Uncommon | None |
| Lava | Lava Trio | Flame Salamander | Rare | Yield |
| Lava | Lava Dragon | Coal Beetle | Rare | None |
| Lava | Demon Dog | Volcano Turtle | Mythical | Guard |
| Narmek | Moon Bunny | Moon Bunny | Common | None |
| Narmek | Satellite Pup | Satellite Pup | Common | Guard |
| Narmek | Alien Slime | Alien Slime | Uncommon | None |
| Narmek | Meteor Moth | Meteor Moth | Rare | Haste |
| Narmek | Nebula Fox | Nebula Fox | Legendary | None |
| Narmek | Cosmo Cat | Cosmo Cat | Mythical | Yield |

Gregory's hidden discovery behavior should remain as it is. Do not reveal it in an unowned collection list merely because this config names it. This release needs an owned-pets menu, not a redesign of the existing cucumber Index.

## 6. Zombie combat and pet motion

### Server targeting

Use the existing `ZombieAPI.Zombies()` list once per combat scan, then group candidates by the zombie model's `Owner` attribute. That attribute is set to the raid owner's UserId. Only consider candidates matching the pet owner's UserId, in range, alive, and eligible under ZombieAPI.

Priority within range:

1. A zombie carrying one of this owner's cucumbers.
2. A zombie actively grappling/attempting theft.
3. Nearest eligible approaching zombie.

Reuse current ZombieRaidService state names after inspecting their assignments; do not guess string values. Add read-only `ZombieAPI.GetTargetInfo(model)` only if the existing replicated attributes cannot reliably distinguish those states. Return primitive state/owner/carry information, not mutable internal raid tables.

Use a 0.2-second target scan and server timestamps for individual next-shot deadlines. Keep a valid target unless a higher-priority theft threat appears. Revalidate immediately before each damage call. Dead, `Shaded`, and `Underground` zombies cannot be hit; the API already filters/rejects those conditions and must remain the last authority.

For v1, shots are server-authoritative instant hits with cosmetic traveling projectiles. Friendly plot builds/cucumbers do not block them. Pets cannot fire outside their range or at another owner's raid. No physics projectile, `Touched` damage, or client hit reporting is needed. One shot consumes one cooldown even if the last-moment damage call rejects it; no catch-up burst after a hitch.

Call `ZombieAPI.Damage(zombie, damage, "Pet")`, without the fourth player-attacker argument. Use the existing kill/drop path so saved cucumbers, split children, raid totals, and rewards stay correct. If damage credit is later needed, add a distinct non-aggro credit field rather than reusing the attacker argument.

### Shared position and presentation

Create `PetMotion.Sample(attributes, serverNow)` as a pure function used by server and client. It calculates the current logical ground position from `RoamFrom`, `RoamTo`, `RoamStart`, `RoamEnd`, and `RoamGroundY`, with safe zero-duration/idle handling. Add a sequence/generation field so clients can ignore incomplete or stale roam updates; publish the sequence last and retain the last complete segment until the next one is valid.

- Server range checks, shot origin, and saved pet positions use this sample, not the unmoving server pivot.
- Client position interpolation uses the same segment and clock. Decorative bounce/lean is local; do not add a second low-pass position interpolation that materially trails server targeting.
- Keep only PetRoamClient as the pet model's `PivotTo` owner. Add aim direction and a brief shooting squash/lean to its animation state. A separate effects controller must never fight it for the model transform.
- A shot effect can start at the locally rendered pet's muzzle/root offset when streamed in, falling back to the event's server origin. This avoids visible projectiles starting at the pet's feet or old spawn location.
- Pets keep roaming while firing; they face the target briefly without charging into zombie collision. They are not damageable and cannot block players or cucumbers.
- Reuse current plot bounds/obstacle checks, anchoring, collision settings, size cap, and streamed-part readiness. On plot resize, clamp logical positions before planning the next leg.
- A missing/broken model stays owned in reserve with a “temporarily unavailable” status. It does not secretly earn or fire while invisible. Reconcile automatically when the asset becomes available; never erase it.

## 7. Income ownership and rate consistency

Extract the current payment/rate logic into **one** `ServerStorage.IncomeService` ModuleScript. LeaderstatsService retains stat display setup and subscribes to its totals; it no longer runs a parallel payment loop. PetService and PetBuffService only register/change producers and modifiers, never increment Cash themselves.

Expose these per-player totals:

```text
CucumberBaseCashPerSec = sum(unboosted eligible cucumber rates)
CucumberCashPerSec     = sum(cucumber base × active temporary multipliers)
PetCashPerSec          = sum(active, successfully spawned pet rates)
TotalCashPerSec        = CucumberCashPerSec + PetCashPerSec
Data.CashPerSec        = TotalCashPerSec                    -- existing HUD/player list
Raid threat income    = CucumberBaseCashPerSec              -- deliberate isolation
```

On cucumbers, keep `Rate` as the effective displayed rate so the current card continues to work; add `BaseRate` for the original value. Never feed the effective Rate back into CucumberValues or apply buffs twice. Recompute when material/mutations/size/zone/type/ownership/tag/temporary effect state changes. Use explicit ownership registration and cached producers instead of scanning every tagged object every frame.

Settlement requirements:

1. One shared roughly one-second income tick computes elapsed time. Preserve fractional cash; `DataService.Increment(..., true)` remains the authoritative profile update.
2. Settle a producer up to a state-change time **before** adding/removing a buff, unequipping, stealing, destroying, or moving it out of eligibility. A producer added mid-second earns only for its real active duration.
3. Split elapsed intervals at known buff expiry times, even if the scheduler wakes late. Never apply the expired rate to the entire overdue interval.
4. Clamp a single stalled-server catch-up interval to five seconds and record a diagnostic; no offline or unbounded catch-up. This is a deliberate hitch policy and should be tested/documented.
5. Aggregate cash deltas per owner before updating the profile. Settlement on an explicit state change uses the same ledger/last-settled timestamp, so the next regular tick cannot pay it again.
6. Emit the existing `CucumberIncome(models, amounts)` with actual paid amounts and compatible shape. Add `PetIncome` for pets from the **same settlement**, not another reward producer. No event if the profile credit fails.
7. Rate displays update on state changes; money animations merely represent successful settlements. Clearing a model after a settlement does not undo already earned cash.
8. The next model must search every reader of `CashPerSec` and `Rate` before refactoring. Change ZombieRaidService's threat source explicitly; do not silently reinterpret unrelated shop/progression readers.

## 8. Persistence and reliable hatching

### 8.1 Canonical schema

Use the existing profile/store. **Keep `Data.Base.Version = 2`** and introduce a separate pet schema field. Correct the template's base version to 2 for new profiles without changing the old cucumber migration condition.

Keep `Data.Base.Pets` as the canonical owned-record array to minimize cross-schema migration. Its records now include reserve pets. BaseSaveService must preserve this array from profile memory instead of rebuilding it from `PlotPet` tags.

```lua
Data.Base.PetSchemaVersion = 1
Data.Base.PetRoster = { "pet-guid-1", "pet-guid-2" } -- ordered active selection, max 6
Data.Base.Pets = {
    {
        Id = "pet-guid-1",           -- stable server-generated ID
        Pet = "Chest",               -- existing internal catalog key
        SourceEgg = "Desert Egg",
        SourceEggId = "egg-guid",    -- nil for legacy pets
        Material = "Golden",        -- empty for normal
        Mutations = { "NEON" },      -- distinct canonical known names + retained unknown metadata
        EggKg = 123,                 -- provenance only, optional
        AcquiredAt = 1790000000,     -- server epoch; 0/unknown allowed for legacy
        Pos = { 0, 0, 0 },           -- same back-edge plot-local convention as current BaseSave
        AbilityRemaining = 60,      -- active online seconds until next chance roll
    },
}
-- Existing saved egg records additionally gain Id.
-- Existing saved cucumber records additionally gain Id and PetBuffs:
PetBuffs = {
    { Kind = "Yield", ExpiresAt = 1790000090, SourcePetId = "pet-guid-1" },
    { Kind = "Guard", ExpiresAt = 1790000240, SourcePetId = "pet-guid-2", Charges = 1 },
}
```

Do not save Instances, Color3, CFrames, function closures, current target objects, or render animation state in this schema. Preserve existing scalar-array serialization for coordinates. Rarity, computed rate, damage, and chance derive from catalog/config rather than becoming competing saved truths. Keep unknown records intact for recovery, but exclude invalid records from active gameplay.

Ownership lifecycle belongs to PetService; saved model coordinates are incidental. An absent streamed model, spawn failure, temporary plot loss, or server cleanup must never remove the owned record. For duplicate **IDs**, keep the first valid occurrence, assign a new ID to any distinct recoverable later record, and report the repair; duplicate species are normal and must not be deduplicated.

### 8.2 Migration

Implement a pure `ServerStorage.PetDataMigration` module and invoke it in DataService **after `profile:Reconcile()` and before profiles are exposed or loaded callbacks run**.

- If PetSchemaVersion is missing/older, convert each old `{Pet, Pos}` in place. Generate IDs once, preserve order/position and all unknown fields, resolve SourceEgg from an explicit reverse catalog map, default missing material/mutations to normal/empty, and set the ability countdown to 60.
- Do not reconstruct old pet traits from nearby eggs or invent a mutation roll. Existing saves did not retain those traits; they cannot be recovered reliably.
- If the existing data already contains traits/IDs from another update, preserve and validate them rather than overwriting them with legacy defaults.
- Initial roster: highest calculated income first, then nominal DPS, then stable ID; select up to six valid spawnable pets. All others remain owned. Show a one-time migration explanation: “You can now choose six active pets. Your other pets are safe in Pets.” This auto-selection happens only for migration, not every join.
- Migrate stable IDs for already saved eggs/cucumbers too, before restoration. World restoration must reuse the saved ID.
- Set the schema marker only after conversion succeeds. Request a coalesced save. A repeated migration must not create more pets, reset valid mutations, or keep changing IDs.
- Unknown species and failed asset restores remain saved and visible as unavailable rows. Profile/world snapshots cannot drop them.
- Retain the current pre-v2 cucumber migration behavior, but add tests proving pet migration itself never initiates a cucumber wipe.

### 8.3 Hatch commit sequence

The authoritative hatch operation must grant an owned pet independently of the animation:

1. Validate owner, ready egg, stable EggId, profile availability, plot, and a per-egg in-progress lock.
2. Snapshot pending world placement changes through the base save API **before** the commit. Confirm the matching egg record exists in the profile. Do not yield during the subsequent table mutation.
3. Check for an existing owned pet with the same `SourceEggId`. If found, consume/remove a stale duplicate egg representation and return the existing reward; never reroll it.
4. Roll the species once, construct the complete owned pet record with inherited traits, and in one synchronous profile mutation append that record and remove the corresponding saved egg. Update roster only if a free slot is allowed under the combat lock.
5. Mark the live egg consumed so snapshots cannot re-add it, then destroy it. All ordinary egg snapshot collectors must ignore consumed eggs and eggs whose IDs already appear as a pet's SourceEggId.
6. Request a coalesced profile save. Send the reveal payload including PetId, an unpredictable/reliably unique reveal token, material/mutations, and derived display stats. The client can skip/fail/leave; ownership is already represented in the profile.
7. Spawn the active pet after the reveal acknowledgment or fallback for presentation, or immediately on restoration. Until successfully spawned, it contributes no income/attacks. Use a separate runtime presentation-pending state; do not serialize a permanent “awaiting client” blocker.
8. `Opened(token)` only finishes that presentation. It cannot select the pet, mint cash, grant a second copy, or reset cooldowns. Update all three current acknowledgment paths in EggHatchClient: busy, watchdog, normal finish.

This provides an idempotent in-memory transaction and a consistent profile snapshot. **It is not a claim of synchronous datastore durability:** RequestSave is coalesced. A process crash before persistence can roll the whole last transaction back to its prior saved state, normally leaving the old egg to hatch again. It must never persist both a usable egg and its granted pet, or neither, due to separate partial saves. Test failures at every boundary.

Pet deletion/trading is excluded from v1, so retained SourceEggId on each owned record is enough for consumed-egg deduplication; a permanent unbounded separate hatch-history log is unnecessary.

### 8.4 Save, leave, reset, and restore ordering

- BaseSave snapshots copy the canonical pet records/roster and update valid logical positions/countdowns. Preserve PetSchemaVersion and any unknown Base fields when constructing a new Base table. Never replace ownership with the current world tag list.
- Save cucumber buff state on apply/consume/clear through the normal coalesced snapshot path, plus regular snapshots. Save absolute expiry times, not a resetting “90 seconds” on every join.
- Add explicit synchronous pre-profile-close callbacks in DataService. Before EndSession, freeze new actions, settle income, write pet countdowns/positions, and snapshot owned world state while the plot still exists. Then end the session, then allow cleanup. Use an idempotent close guard shared by player leave and shutdown paths; inspect ProfileStore's shutdown behavior before wiring this.
- Avoid destructively clearing plots from independent PlayerRemoving handlers before that flush. Coordinate PlotService, BaseSaveService, EggPlacement, and PetService cleanup through the close lifecycle where necessary.
- Restore profile/migrate → allocate/upgrade plot → restore cucumbers/builds/eggs and buffs → attach the selected pets → register income/combat. Use explicit readiness signals or return values, not arbitrary sleeps.
- Character death does not remove pet ownership or duplicate pet models. Plot loss pauses gameplay and preserves inventory; a new owner must never inherit the previous owner's producers or effects.
- BaseSaveAPI.Reload pauses services and rebuilds runtime from the same records. Reset clears canonical inventory/roster and runtime together. Audit AdminService.ResetData and DataService.ResetProfile so no old references recreate deleted pets after a reset.

## 9. Script-by-script work list

Names below are recommended new scripts. Adapt a name only if the live place now has an equivalent; do not create two systems for the same job. Do not edit historical backup copies under ServerStorage.

### New modules/scripts

| Path | Responsibility and minimum contract |
|---|---|
| `ReplicatedStorage.Modules.PetBalance` | All tables in sections 3–5: slots, tier mappings, rarity stats, species abilities, trait scaling, durations, tick intervals, FX limits. Validate full catalog coverage. |
| `ReplicatedStorage.Modules.PetStats` | Pure `Calculate(record)` → income, shot damage, interval, DPS, range, ability, chance; validate finite numeric inputs; no state, instances, or randomness. |
| `ReplicatedStorage.Modules.PetMotion` | Pure logical roam segment sampling shared by server and PetRoamClient. |
| `ServerStorage.PetDataMigration` | Idempotent schema migration/validation, preserving unknown and failed records. No runtime spawning. |
| `ServerStorage.PetService` | Canonical ownership, indexes by PetId/SourceEggId, roster validation, spawn/despawn, roam planning, ability countdowns, snapshot/restore, and immutable UI snapshots. Extract existing spawn/roam code here. |
| `ServerStorage.PetBuffService` | Own cucumber effect state, eligibility, random target selection after a server roll, expiry, rate modifiers, serialization, synchronous theft denial. |
| `ServerStorage.PetCombatService` | Shared target scan, per-pet fire deadlines, own-raid filtering, damage API calls, batched shot effects. No ownership or cash writes. |
| `ServerStorage.IncomeService` | Unified cucumber/pet producer registry, interval settlement, aggregate totals, only routine income Cash writes, payment events. |
| `ServerScriptService.PetServer` | Bootstrap modules/remotes, validate menu actions, connect lifecycle, start shared ability/combat schedulers once. No duplicate gameplay formulas. |
| `StarterPlayer.StarterPlayerScripts.PetEffectsClient` | Shot/projectile/impact, proc link, shield break, and bounded effect pooling; cosmetic only. |
| `StarterPlayer.StarterPlayerScripts.PetCardClient` | Stream-aware name/rarity/income cards and PetIncome popups; use existing FredokaOne/outlined green cash style and NumberAbbrev. |
| `StarterGui.CucumberMenus.PetView` | Owned-pet card grid, selected-detail pane, six-slot row, responsive sizing, local preview pooling. |
| `StarterGui.CucumberMenus.PetController` | PetState subscription, menu requests, sorting/filtering, pending/error states, equip actions through remotes. |

### Existing scripts to change

| Existing path | Required edits |
|---|---|
| `ServerScriptService.PetHatchService` | Replace transient reward grant with committed hatch transaction; move spawn/roam responsibilities into PetService; preserve trigger/roll/reveal behavior; forward compatibility APIs without duplicate ownership grants. |
| `ServerScriptService.EggPlacement` | Stamp stable IDs for new placed eggs; restore saved IDs; refuse consumed duplicates. Preserve existing timers and look attributes. |
| `ServerScriptService.BaseSaveService` | Canonical pet records/roster; egg/cucumber IDs; buff serialization/restoration; consumed-egg filtering; readiness; non-destructive failures; coordinated close/reset/reload. |
| `ServerStorage.DataService` | Pet schema/template fields; migration before loaded callbacks; explicit close/reset lifecycle integration; keep existing datastore and monetary fields. |
| `ServerScriptService.LeaderstatsService` | Delegate producer math/payment to IncomeService; retain player stat display wiring; remove original independent PayIncome loop after extraction. |
| `ServerScriptService.ZombieRaidService` | Threat uses baseline cucumber income; ordinary/grapple/digger protection hooks; clear buffs on actual steal; optional read-only targeting metadata; verify own-raid combat lock query. |
| `StarterPlayer.StarterPlayerScripts.EggHatchClient` | Server reveal token on every Opened acknowledgment; inherited pet preview appearance; compact stat/ability reveal; restore HUD/camera on all failure paths. |
| `StarterPlayer.StarterPlayerScripts.PetRoamClient` | Shared logical motion; attack facing/pose; render-time muzzle lookup; preserve streaming guards; still the only pet transform animator. |
| `StarterPlayer.StarterPlayerScripts.PlacedCucumberCardClient` | Effective rate remains Rate; add three compact buff badges/countdowns; use replicated expiry/state; keep current income popup contract. |
| `StarterGui.CucumberMenus.MenuController` | Register Pets; use an explicit panel→opener map instead of assuming every opener sits under LeftMenu; keep existing fit/close/transition behavior. |
| `StarterGui.CucumberMenus.MenuClient` | Start PetController with the existing menu instance; no second global menu manager. |
| `StarterGui.CucumberHUDDesign.HUDClient` | Wire the new Pets opener if not handled entirely by MenuController; follow existing ButtonFX style; no new cash calculation. Ensure only one script owns the click connection. |
| `ServerScriptService.AdminService` | Reset/reload integration with canonical pet state; bounded Studio-only test actions if needed, with the same permission checks as existing admin actions. |

### Conditional integration checks, not automatic rewrites

- `PlotService`: adjust cleanup ordering only where needed for the pre-close snapshot; preserve allocation/ownership behavior.
- `CucumberCarry` and `CucumberMoveServer`: ensure stable CucumberId survives moves and that pickup clears effects. Prefer registration/tag hooks plus a small explicit move-state hook over broad rewrites. Audit all placement/restore APIs before patching.
- `BaseHUDController`: existing left slots remain intact. New Pets opener follows relevant bench/build/hatch visibility state without repurposing Manage.
- `EggShop`: egg traits already exist. No price, stock, roll, or tool-persistence redesign is required. IDs can originate at placement for this scope.
- `DefenceService`, `ZombieCatalog`, `CucumberValues`, `CucumberMutations`: reuse and regression-test. No blanket rebalance or mutation rewrite.
- `PetsCatalog`: preserve all weights/names/rarities. Correct stale comments if touched; use its public data rather than duplicating model resolution.
- HUD strength popup, BenchBonusClient, BenchServer, SlowModeClient, StrengthProgressionServer, and CucumberLift: regression coverage only; this update does not require modifying those features.

### Dependency/startup rules

Use explicit `Init(dependencies)` and `Start()` for stateful server modules; avoid cyclic requires and side effects at require time. DataService only requires the pure migration module for loading. PetService should expose synchronous `EnsureProfileState(player)` so both bootstrap and BaseSave restore can safely call it regardless of spawned callback order.

```text
PetsCatalog + PetBalance → PetStats / PetDataMigration
DataService load → migration → profile ready
BaseSave restore → PetService.AttachPlot / restore PetBuffService state
PetService producers + PetBuffService modifiers → IncomeService → Cash + rate displays
PetService active pets + PetMotion + ZombieAPI → PetCombatService
PetBuffService.TryBlockTheft ← ZombieRaidService
Server snapshots/effects → menu, cards, roam and effects clients
```

Publish compatibility `PetHatchAPI.SpawnPet` and `ClearPets` only as adapters if remaining callers require them. Distinguish **spawn an existing record** from **grant ownership** in their contracts. A reload must never interpret SpawnPet as “grant another pet.”

## 10. Remote contracts and replicated state

Add under `ReplicatedStorage.Remotes`:

| Remote | Direction | Payload / rules |
|---|---|---|
| `PetRequest` RemoteEvent | Client → server | `{RequestId, Action, PetId?, SortMode?}`. Actions: `GetState`, `Equip`, `Unequip`, `EquipBest`. No caller-provided UserId, stats, species, mutation, chance, or target. |
| `PetState` RemoteEvent | Server → owner | `{Revision, RequestId?, Result?, Slots=6, EquippedIds, Pets, Totals, CombatLocked}`. Full state on first open; small revisioned deltas afterward. Never broadcast a private inventory to all players. |
| `PetEffects` RemoteEvent | Server → nearby clients | Batched `Shot`, `AbilityApplied`, `ShieldBlocked` records with event ID, relevant PetId/target, origin/end position, kind, and server time. No client-to-server effects handler. |
| `PetIncome` RemoteEvent | Server → owner/nearby observers | Model/PetId and actual paid amount batches from IncomeService. Purely visual; skip unavailable streamed targets. |

Extend existing `PetHatch` rather than replacing it: `Begin` gains PetId/token/traits/stats, `Opened` returns that token. Keep the existing reveal UI lifecycle intact.

Validation:

- Bound incoming string/payload lengths; accept only known action keys. Rate-limit state requests (for example one/second) and roster changes (two/second with small burst allowance) per player.
- Profile loaded, plot ownership, combat lock, record ownership, availability, and slot cap must all be checked on the server.
- Set membership operations are idempotent: equipping an equipped PetId does nothing; unequipping an absent ID does nothing. A repeated EquipBest produces the same roster.
- `EquipBest` accepts only `Income` or `Combat`, sorts by computed rate or nominal DPS, then the other metric, then stable ID. Apply the roster atomically; unchanged slots keep cooldowns, newly equipped slots start at 60. No client-provided ordering score.
- Every success/error acknowledges RequestId with current Revision. Client ignores older state and requests a full snapshot if it detects a gap.
- Close callbacks reject further actions; deferred reveal/effect callbacks carry a profile generation so they cannot act on a reset/reloaded profile.

Pet world attributes should include PetId, PetName, existing display/owner/plot fields, material/mutation visual strings, effective pet rate, ability key, shot damage/interval/range, and complete roam segment fields. These are replicated display snapshots; server calculations use canonical records. Add concise cucumber buff expiry/charge attributes for card rendering; clients must not infer income from their own countdown completion.

## 11. UI and visual polish specification

### Pet menu

Add a compact paw-shaped **Pets** opener in a separate HUD utility area to the right of the existing left-menu cluster. Keep Slow Mode directly under Index and preserve Build/Manage/bench layouts. Register this explicit opener with MenuController; do not reuse Manage, whose behavior already belongs to base management. Test placement against the bottom-left night indicator and small-screen controls.

Use the game's current bright colors, FredokaOne typography, dark outlines, rounded panels, and hover/press animation. Match existing panel transitions instead of introducing a new UI style.

Menu layout:

1. Header “Pets”, active count `4 / 6`, close button.
2. Six active slots; selecting one shows that individual pet's details.
3. Owned grid with model preview, display name, rarity accent, material/mutation chips, `$X/s`, and equipped status. Reserve/unknown-asset pets remain visible.
4. Selected details: cash/sec; damage, interval, nominal DPS and range; ability name, exact effect, chance per minute, duration, and “Next chance roll in …”. Fighters explicitly show “Fighter: +15% damage.”
5. Equip/Unequip, “Best income”, and “Best combat”. On full roster, prompt to select a slot to replace through one atomic server request extension, or clearly ask the player to unequip one first; **choose the simpler unequip-first flow for v1**.
6. Sort by income/combat/rarity/newest and filter active/reserve. All sorting is local display except server-authoritative EquipBest.
7. Footer totals: pet cash/sec, cucumber cash/sec, combined cash/sec. Do not imply nominal pet DPS is guaranteed actual combat output.

During a live raid, keep the panel readable but disable roster actions with “Finish defending your plot to change pets.” Disable actions until server state arrives and show errors without hiding the panel. Support touch and gamepad focus as well as mouse. Scale/scroll the grid; don't shrink text into unreadability on a phone.

### World cards and effects

- Pet card: display name + rarity, green `$X/s`, small ability icon if applicable. Readable near the pet; fade/hide distant cards, using existing cucumber-card conventions.
- Income: small green `+$X` rising from the pet, representing paid cash. No extra screen-flying strength text; that existing behavior belongs to clicked bench bonus circles.
- Shot: short muzzle flash, colored seed/orb traveling approximately 0.12–0.2 seconds, small hit sparkle. Cosmetic projectile reaches the old endpoint even if the target dies; do not create another damage call on impact.
- Ability: 0.25–0.4-second arc from pet to cucumber, brief target pulse, icon badge. Owner toast example: “Bloom Bee gave Quick Grow to your cucumber - +25% for 90s.”
- Shield: subtle green outline/shell rather than an opaque bubble hiding the cucumber. Burst/shard ring when consumed; one restrained sound, no screen shake for every block.
- Hatch: show inherited material/mutations on the revealed pet, plus cash/sec and ability line. Avoid hiding critical camera/HUD restoration behind a successful network response.
- Respect streaming and destroy effects when their model disappears. Pool reusable effects and preview models; cap active particles/projectiles, rate-limit repeated income sounds, and cull offscreen/distant cosmetic work.

Repurpose existing suitable sound/assets after inspection; new simple projectiles and rings can be built from native Roblox parts/attachments/particles. Asset creation is not required to make the gameplay functional.

## 12. Performance, lifecycle, and diagnostics

- Target scan once per 0.2 seconds, grouped by owner; six active pets per owner. Do not scan the entire Workspace for every shot.
- Cache active pet/cucumber registries using tags and explicit lifecycle hooks. Disconnect every connection on removal, reset, and session close.
- Ability scheduler can run every 0.25 seconds with elapsed-time countdowns. Expiry must also be respected by income settlement and theft validation, not only a periodic sweeper.
- Batch cosmetic events by tick and send only to the owner plus nearby viewers. Cap effects around 64 active projectiles and 32 income popups per client as an initial rendering budget; dropping a cosmetic effect must never drop a reward/damage operation.
- Measure with maximum configured server players, six pets each, full cucumber plots, and high-level waves. Record server script time, network event rate, and client frame time before/after; do not declare optimization complete from an empty single-player plot.
- Validate all loaded/calculated numeric values are finite, in range, and nonnegative where required. Unknown pet data should fail closed for gameplay while remaining recoverable in the profile.
- Add bounded diagnostic counters: active/reserve pets, invalid records, migration repairs, spawn failures, paid pet cash, proc attempts/successes/no-target outcomes, shield blocks, pet damage, denied requests, dropped cosmetic effects. Avoid logging every shot or full player inventories.
- Test hooks must be Studio-only or behind the existing server admin permission checks. Do not trust a client setting a dev attribute. Inject RNG/clock into modules for tests rather than weakening production randomness or timing.

## 13. Ordered implementation tasks

Each stage should leave the place runnable. Capture original affected sources or a place backup before implementation. Work on the active scripts, never their backup copies.

1. **Config and stat contract.** Add PetBalance/PetStats; validate all 49 species, existing rarity/name mappings, formulas, clamps, and sample outputs. No income changes yet.
2. **Canonical ownership and migration.** Add migration, PetService records/roster, IDs, non-destructive BaseSave behavior, explicit lifecycle readiness/close handling. Verify old-profile round trips before proceeding.
3. **Reliable hatch path.** Commit pet+egg consumption together, inherit traits, tokenize reveal acknowledgment, make adapters idempotent. Test leave/watchdog/duplicate-ack failures.
4. **Shared motion and runtime attachment.** Extract spawn/roam into PetService, add PetMotion, switch PetRoamClient, verify positions at two clients and plot resizing. Restore only selected pets while preserving all reserves.
5. **Unified income.** Extract IncomeService, register pets, preserve fractional payments and CucumberIncome shape, expose totals, isolate raid threat from added income. Remove old duplicate payout loop.
6. **Buffs and protection.** Add proc timing, eligibility, stacking, expiry/save behavior, effective cucumber rates, and every theft-path guard. Test with injected clock/RNG and actual zombie varieties.
7. **Combat.** Add owner-filtered targeting, damage deadlines, existing ZombieAPI integration, and lightweight shot events. Verify tower/raid behavior still works.
8. **Management and presentation.** Add PetsPanel/opener/controllers, cards, buff badges, inheritance visuals, effects, request feedback, and phone/gamepad layouts.
9. **Migration/combat/load regression pass.** Run the matrix below with test profiles and multi-client playtests. Review starting balance against actual progression.
10. **Implementation handoff.** Report changed paths, actual test results, screenshots of menu/active pets/buffs, final chosen numbers, and any remaining issues. Publishing is a separate action; this plan itself does not request publication.

Do not build a large UI first and leave saves/payment integration for last. Those are the highest-risk dependencies for a usable pet update.

## 14. Verification and acceptance matrix

Use mocked ProfileStore data or dedicated test profiles for destructive scenarios. The inspected AdminService warns that Studio can still use live profiles; ordinary Studio mode alone is not sufficient isolation.

| Area | Required case and passing result |
|---|---|
| Catalog | Exactly 49 existing keys covered; no odds/rarity/name changes; Gregory remains hidden until discovered; unknown new key warns instead of crashing. |
| Stats | Check all sample formulas; duplicate mutation names counted once; income cap 8 and damage cap 1.25; rankless Gregory valid; no NaN/infinity propagation. |
| Legacy saves | Old `{Pet,Pos}` records migrate once; repeat load preserves IDs; more than six pets remain owned; duplicates of species remain separate; unknown asset records survive later snapshots. |
| Existing base | Version-2 cucumbers/builds/eggs untouched; version-1 migration behavior unchanged; plot upgrade/local-coordinate placement still correct. |
| Hatch transaction | Interrupt before grant, after profile mutation, after egg destruction, during reveal, and after acknowledgment. Reload yields a consistent egg-or-pet state without duplicate usable rewards. |
| Reveal | Busy path, watchdog, normal close, stale/forged/duplicate token all safe; client cannot grant a different species; camera and HUD always restore. |
| Mutation inheritance | Golden/diamond and multiple egg mutations survive hatch, menu, spawned look, save, rejoin, and reload; old normal pets do not acquire invented traits. |
| Income | $0.50/sec pet earns $30 in an uninterrupted 60-second controlled-clock test; reserve pets earn zero; no double-payment at equip/steal/expiry boundaries. |
| Buff math | Base $10/sec → Yield $15, Haste $12.50, both $18.75; same-kind procs do not stack/refresh; base rate returns correctly after expiry. |
| Timing | Every eligible ability pet rolls once per 60 active seconds; failure/no-target consumes attempt; no join/equip or offline catch-up roll; long hitch causes no burst of rolls. |
| Probability | Seeded large sample matches 1/2/4/8/12% within an explicit statistical tolerance; Wild picks eligible kinds correctly; target selection is unbiased. Do not treat one observed success as validation. |
| Buff saves | Expiry uses absolute time; no offline cash; moving preserves ID/buffs, pickup/steal clears them; missing source pet does not reset duration. |
| Shield | Normal grab, grappler before pull, shield added mid-pull, digger surface, simultaneous two-zombie attempts, and expired shield tested. One charge consumed, no stolen count on block, no stuck weld/anchor. |
| Combat ownership | Pets only damage their owner's zombies; no player/guardian/neighbor damage; pet damage does not mark the owner as a player attacker. |
| Zombie states | Shaded/underground/dead targets rejected; carry priority works; split children use existing registry; normal drop/return/raid-end still runs. |
| Cadence | Server limits rate regardless of FPS/network spam; no missed-time burst; cosmetic projectile completion never deals a second hit. |
| Motion | Two clients see shots originate at the moving pet; server range checks agree with logical motion; streaming out/in, model removal, and plot resize recover. |
| Raid balance | Adding/equipping pets or temporary boosts alone does not raise the baseline cucumber-derived raid threat; removing/stolen cucumbers retains existing threat semantics. |
| Roster | Six-slot cap, ownership checks, atomic EquipBest, unavailable assets, spam/replayed requests, and combat lock all enforced server-side. |
| Lifecycle | Death/respawn, plot reassignment, leave, profile close, reload, admin reset, and shutdown produce no duplicate models, income loops, stale callbacks, or inventory loss. |
| UI | Mouse/touch/gamepad, narrow phone viewport, opening near/away from base, bench/build/hatch states, streaming targets; Slow Mode and night timer remain usable. |
| Existing systems | Bench circles still pop and send only clicked bonus strength to top HUD; normal bench gains unchanged; cash stays green; Slow Mode still sets WalkSpeed 16 and restores progression speed. |
| Load | Full server, six pets per player, heavy plots and simultaneous raids: collect before/after timings and bounded effects; no per-frame all-world scans or growing connection counts. |

### Balance review after functional correctness

Measure pet cash as a percentage of same-biome cucumber cash, time to afford the next meaningful purchase, full-team zombie kill times, prevented theft per night, and actual proc frequency. Run at least starter, midgame, and max-tier teams, with and without towers. Review the special case of Gregory's low biome-scaled income versus its extremely rare hatch odds.

Adjust only PetBalance first. Do not “fix” a too-strong pet team by secretly increasing the raid threat formula, changing cucumber rewards, or nerfing existing towers. Any such change should be a separate deliberate balance decision.

## 15. Paste-ready instructions for the implementing model

> Implement the attached Pet-System-Implementation-Plan.md in New Map Cucumber Game, PlaceId 87967102884366, using the default Roblox Studio MCP or the connected chxxrz MCP. Reinspect the live scripts before patching. The document's observed architecture is from September 22, 2026; proposed balance numbers are starting defaults. Preserve all owned pets and existing cucumber/build/egg saves, internal pet names, hatch odds, HUD positions, green cash, bench bonus behavior, and Slow Mode. Build in the specified order, with canonical persistence and reliable hatch transactions before UI. Use one authoritative income system and existing ZombieAPI damage/raid lifecycle. Keep pet income out of the existing raid threat calculation and cover ordinary, grapple, and digger theft with consumable shield checks. Implement all 49 species assignments, inherited egg traits, six active slots plus reserve inventory, server-validated management, client effects, and the required lifecycle handling. Do not edit historical backup scripts or publish automatically. Use isolated test profiles for resets/destructive tests. Finish with concrete test results, changed script paths, screenshots, and an honest list of anything still incomplete.
