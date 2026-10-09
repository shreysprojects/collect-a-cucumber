# Collect a Cucumber: Complete Game Map

**Snapshot date:** 2026-09-01 (updated the same evening after the unused-code cleanup, see `backups/Cleanup_2026-09-01/MANIFEST.md`)
**Source of truth:** the LIVE place as read directly from Roblox Studio (`[NEW] Collect a Cucumber 🥒`, place `116126086405931`, universe `10439954561`, owned by the Group Frenzy group `14583228`). Every number and behaviour in this document was read from the live scripts and dictionaries on the snapshot date. Where design documents or older notes disagree with the live code, the live code wins and the difference is called out.

This is the reference for "what is going on right now and how it all ties together". Read Part 1 for the player's journey, Part 2 for every system in depth, Part 3 for the code map you need when adding features.

---

## Table of contents

**Part 1: The game from the player's side**
1. [What the game is](#1-what-the-game-is)
2. [The world](#2-the-world)
3. [The player journey from first join to endgame](#3-the-player-journey-from-first-join-to-endgame)

**Part 2: Every system in depth**
4. [Currencies, multipliers and the number pipeline](#4-currencies-multipliers-and-the-number-pipeline)
5. [Breakables: cucumbers, spawning, damage, materials, mutations, lightning](#5-breakables)
6. [Areas and doors](#6-areas-and-doors)
7. [Pickaxes](#7-pickaxes)
8. [Pets, eggs, evolving, index, forge](#8-pets-eggs-evolving-index-forge)
9. [The upgrade board](#9-the-upgrade-board)
10. [Rebirth](#10-rebirth)
11. [Carry system (cucumbers on your arm)](#11-carry-system)
12. [The Cucumber Bank: vaults, earnings, upgrades, locks, stealing, heists, break-ins](#12-the-cucumber-bank)
13. [Bosses, goals and biome events](#13-bosses-goals-and-biome-events)
14. [Portals and minigames](#14-portals-and-minigames)
15. [Free reward faucets: quests, goals, streaks, playtime, chests, offline, index](#15-free-reward-faucets)
16. [Time skips](#16-time-skips)
17. [Monetization: gamepasses and developer products](#17-monetization)
18. [Onboarding: loading, tutorial, gifts, first-session prompts](#18-onboarding)
19. [HUD, panels and every ScreenGui](#19-hud-panels-and-every-screengui)
20. [Audio, VFX and game feel](#20-audio-vfx-and-game-feel)
21. [Social: friends, group, trading, leaderboards, badges, chat](#21-social)
22. [Admin, dev hooks and testing](#22-admin-dev-hooks-and-testing)
23. [Save data and DataStores](#23-save-data-and-datastores)
24. [Performance and streaming](#24-performance-and-streaming)

**Part 3: Code map and status**
25. [Architecture and boot sequence](#25-architecture-and-boot-sequence)
26. [Script index (every script, one line each)](#26-script-index)
27. [Player attributes and replicated values](#27-player-attributes-and-replicated-values)
28. [Dormant, disabled and orphaned systems](#28-dormant-disabled-and-orphaned-systems)
29. [Dev-save work that is NOT on the live place](#29-dev-save-work-that-is-not-on-the-live-place)
30. [Backups and revert points](#30-backups-and-revert-points)
31. [Rules to keep when adding features](#31-rules-to-keep-when-adding-features)

---

# Part 1: The game from the player's side

## 1. What the game is

Collect a Cucumber is a click-to-smash collector simulator. You swing a pickaxe at cucumbers, they pay **Cukes**, your pets do most of the damage, you sell Cukes for **Coins**, and Coins buy the things that make the loop faster: pickaxes, eggs (pets), new areas, board upgrades and rebirths.

Layered on top of that classic loop are the things that make this game its own:

- **Catching and carrying.** Every cucumber you smash lands on your arm. You carry it home and store it in your own vault stall in the **Cucumber Bank**, where it prints Coins forever.
- **Vault stakes.** Your stall has a lever that locks it with lasers for a limited time. When the lock lapses, anyone can walk in and steal your cucumbers, and you can fight to get them back. A Robux product lets a thief break into a locked base.
- **Jackpots.** Cucumbers spawn as Golden or Diamond, can roll one of eight mutations (up to PRISMATIC at 1 in 20,000), and get struck by lightning. Stacked jackpots multiply value up to a hard cap.
- **Bosses and events.** Smashing enough cucumbers in a biome summons a walking Colossus boss. Killing it drops shards that forge boss pets, launches a payback nuke over the field, and starts a biome event (Golden Hour, Super Strength or the Cucumber Smash race).
- **Portals.** Each of five biomes has a portal to a private minigame (obby, rat hunt, avalanche, lava run, Bloxout). Completing one spins a reward wheel.

Two currencies only. Cukes come from breaking and are multiplied by everything. Coins come from selling Cukes at a flat 1:1, from vault pads, chests, quests and rewards, and Coins buy everything except vault cucumber upgrades (which cost Cukes).

## 2. The world

The map is one long strip running west along the negative X axis. The lobby sits at the east end; each biome is a roughly 145-stud-wide slab further west, walled off by a 60-stud-tall door wall. All coordinates are studs.

### 2.1 The lobby (Area 1, around x -31..36)

| Landmark | Where | What it does |
|---|---|---|
| Spawn pad (`SpawnLocation`) | (-17, 3, 9) | Fresh players spawn here. Returning players who finished the tutorial spawn at their vault stall instead. |
| Pickaxe shopkeeper (`workspace.ShopNew.Vendor`) | (-8, 5, -17) | Walk up, "Talk", pick "pickaxes" in the dialog, the Shop panel opens. The tutorial gifts 500 Coins here once. |
| Cucumber Vendor (`workspace.Points.Sell.Vendor`) | (-6, 6, 35) | Walk up, "Talk". Options: sell the cucumber on your arm, sell all Cukes for Coins 1:1, or sell pets. |
| Quest Board (`workspace.QuestBoard`) | (-23, 7, -12) | Three rolling quests; each pays a time skip of Cukes plus vault Coins. |
| Upgrade board (`workspace.Upgrader`) | (-25, 6, 28) | Three board upgrades: Vault slots, Pet equips, Smashes required. |
| Shards God NPC (`workspace.Shards`) | (-41, 13, -42) | "Talk" prompt opens the Shards forge dialog (10 boss shards forge that boss's pet). |
| Daily chest / Group chest (`workspace.Chests`) | (-93, 6, -67) / (-67, 6, -67) | 500 / 1,000 Coins every 12 hours. Group chest nudges non-members to join Group Frenzy. |
| Golden Cucumber statue (`workspace.Statues`) | lobby | "View Hall of Green" prompt opens the (currently placeholder) season hall. |
| Leaderboards (`workspace.Leaderboards`) | lobby | Four physical top-100 boards: TotalCoins, TotalTime, TotalOrbs (Cukes), TotalBreaks. Refresh every 90 s. |
| Promoted pet stands (`workspace.PromotedPets`) | lobby | Physical Robux stands for Purple Hydra and Red Demon with live price billboards. |
| Cucumber Bank (`workspace.CucumberBank`) | docks on the lobby's EAST side, deck from x 42 to about 290 | 8 vault stalls (4 per row), regenerated at runtime. See section 12. |
| Bank sign (`workspace.BankSign`) | (21, 6, -7) | Signage at the bank entrance. |

### 2.2 The eight biomes

Zone order is fixed everywhere in code: `Spawn, Desert, Samurai, Farm, Snow, Underwater, Volcano, Narmek`. Each biome has a cucumber field (`workspace.SpawnArea.<index>`), a teleport pad (`workspace.Doors.Locations.<zone>`), a door wall on its east edge (`workspace.Doors.<zone>`), an egg stand (`workspace.Eggs`), detection volumes (`workspace.Zones.<zone>`) and a `Game.Area N` map folder.

| # | Zone key | Display name | Field centre (x) | Door wall (x) | Teleport pad (x) | Egg | Extras in this biome |
|---|---|---|---|---|---|---|---|
| 1 | Spawn | Spawn | -98 | none (free) | -47 | Basic Egg (-81, 8, 71) | Starter Portal (-146, 7, 71) |
| 2 | Desert | The Wild West | -231 | -155 | -150 | Desert Egg (-226, 7, 6) | Treasure chest (-199, 2, 59), Desert Portal (-287, 7, -58) |
| 3 | Samurai | Samurai Palace | -371 | -300 | -296 | Samurai Egg (-358, 38, -107), on the high platform | Samurai chest (-374, 25, 123), Void Portal (-419, 7, -43) |
| 4 | Farm | The Farm | -518 | -445 | -435 | Farm Egg (-512, 6, -44) | |
| 5 | Snow | The Arctic | -662 | -590 | -582 | Frozen Egg (-712, 7, -51) | Snow chest (-658, 5, 63), Snow Portal (-725, 8, 69), Evolving altar (-661, 11, -73) |
| 6 | Underwater | The Ocean | -806 | -735 | -730 | Ocean Egg (-810, 8, 50) | |
| 7 | Volcano | The Volcano | -958 | -881 | -876 | Lava Egg (-976, 8, -53) | Volcano chest (-940, 5, 68), Lava Portal (-1003, 8, 74) |
| 8 | Narmek | The Greenland | -1111 | -1029 | -1023 | Narmek Egg (-1105, 7, 3) | A "Soon" door wall at x -1177 reserves a ninth area |

Owned doors are removed client-side (the door model is parked in `ReplicatedStorage.Assets.DoorReserve`) so you can walk through. Buying a later door also unlocks every earlier door.

### 2.3 Minigame instances

Portals teleport you into private copies of a map spawned far above the world: Classic Obby (origin (-500, 500, 4000)), Wild West rat hunt (-2000, 600, 9000), Avalanche (-2000, 600, 6000), Lava Run (-2000, 600, 7500) and Bloxout Incorporated (-3500, 700, 12000). Each copy is per player, spaced 500 to 900 studs apart.

## 3. The player journey from first join to endgame

### 3.1 First 60 seconds: loading and spawn

1. `ReplicatedFirst.LoadingBootstrap` throws up the custom loading cover on the first client frame, removes Roblox's default one, and creeps the percentage to 40% until the real loader takes over. A SKIP button becomes a hard escape at 20 s and the cover is force-cleared at 60 s.
2. The server loads the profile (`ProfileService`, store `CucumberData_Launch3`), builds the replicated stat tree, then `DoorService.PlayerJoined` removes owned doors on the client and teleports the character: fresh players to the furthest owned biome pad (Spawn for a new account), finished-tutorial players straight to their vault stall. The loading screen waits for the `InitialAreaTeleportComplete` attribute before it lifts.
3. There is no intro cutscene: the retired `IntroCutsceneClient` was deleted in the 2026-09-01 cleanup, and the tutorial publishes the "cutscene decided, inactive" attributes itself so the guards in other scripts stay harmless.

### 3.2 The tutorial (new accounts only)

The tutorial (`TutorialClient`, version 3) is a 7-step guided loop with a top banner, a step pill and arrows. It opens with the vault so a new player has passive income within two minutes.

| Pill | What the player does | How the game helps | Funnel step reported |
|---|---|---|---|
| 1/7 | Smash a sliced cucumber until one lands on your arm, walk it through the bank arch, store it on your first podium | `wantcarry` arms a guaranteed catch server-side; arrows point at the lowest-HP cucumber, then the bank arch, then Pedestal1 | 2 StoredInVault |
| 2/7 | Press the green UPGRADE pill on the stored cucumber's card | `wantupgradecukes` gifts exactly the cheapest upgrade cost in Cukes once; the pill is ringed on screen | 3 UpgradedCucumber |
| 3/7 | Read the "your cucumber earns Coins, step on the pad" banner (3.5 s), then pull the vault lever | Arrow on the lever hinge; completion is the `VaultLeverPulls` attribute ticking | 4 LockedVault |
| 4/7 | Buy your next pickaxe: teleport via the BUY pill or walk to the shopkeeper, choose "pickaxes", pick a card, press BUY | 500 Coins gifted once on arrival at the shop | 5 BoughtPickaxe |
| 5/7 | Walk to an egg stand and hatch | 2,500 Coins gifted at step start (retries every 3 s until they land; that is 10 Basic hatches) | 6 HatchedPet |
| 6/7 | Open BACKPACK and click the new pet to equip it | Screen arrows on the button and the tile | 7 EquippedPet |
| 7/7 | Close the pet inventory | | 8 ClosedPetMenu |

Completion fires the `Tutorial` network event: the server marks `DoneTutorial`, grants **Lil Pickle** and, for non-skippers, **+250 Coins** flat, then logs funnel step 9. Skipping is allowed at any time (a skipper still gets Lil Pickle, not the 250). Progress persists per step so a quitter resumes where they left off. The gift servers can never refund a gift that was already spent in the same session.

### 3.3 The core loop in the first hour

- **Click** cucumbers in the Spawn field. Each click is pickaxe damage; your equipped pets swarm the committed target and land a hit every 0.6 s. Cucumbers show HP bars, squash on hit, and explode with damage numbers.
- **Catch** every cucumber you break (100% catch mode). It rides on your shoulder with an overhead card showing its name and value. A green chevron trail leads to the nearest open podium in your stall.
- **Store or sell.** Store it on a podium to earn Coins per second, or sell it at the vendor for its card value. Or press DROP to plant it back in its home field.
- **Sell Cukes** at the vendor 1:1 into Coins whenever you need to buy something.
- **Spend Coins** in this order of first affordability: Stone Pickaxe (400), Basic Eggs (250 each), Desert door (60K at about 6 minutes for an average player), Desert Egg (100K), Bronze Pickaxe (6K), Iron (60K).
- **Bank the vault.** Step on the green pad in front of each podium to collect its accrued Coins. Spend Cukes on the UPGRADE pill to raise a stored cucumber's rate by 18% per level.
- **Pull the lever** before you leave the stall. The lock lasts 75 s plus 15 s per rebirth. When it lapses, your podiums are open to thieves.

Meanwhile the passive systems fire on their own: playtime rewards unlock at 30 s / 2 m / 5 m / 10 m / 18 m / 30 m / 1 h / 1.5 h, the daily streak pays on join, three quest cards fill up, chests reset every 12 h, friends in the server add pickaxe damage, and the Group Frenzy popup appears 60 s in for non-members.

### 3.4 Mid game (areas 3 to 5, first rebirths)

- Areas cost 5M (Samurai), 300M (Farm, needs 1 rebirth), 60B (Arctic, 2 rebirths). The first rebirth costs 90M Coins, doubles all Cuke income permanently, resets Cukes, Coins and doors, and adds a vault slot and 15 s of lock time.
- Each biome's egg is the real damage jump; pet Multi1 (Cuke multiplier) and Damage roughly triple and twelve-fold per area.
- Bosses appear every 90 to 450 breaks per biome. Killing one hands its cucumber to the top damager as a trophy carry, drops shards, and starts an event.
- Portals become worth it: 18 to 90 smashes in the biome (minus 3 per board level) unlock a minigame with a 1-hour cooldown after completion and a reward spinner at the end.
- Trading unlocks at 1 rebirth (pets only, up to 4 per side).
- The vault becomes a real income line: value/220 per second per cucumber, multiplied live by pet Multi1 times 2^rebirths, with offline earnings for absences.

### 3.5 Late game and endgame

- Areas 6 to 8 cost 5T, 400T and 25Qa Coins, gated at 3, 4 and 5 rebirths. Pickaxes climb to the Rainbow Pickaxe at 5Qa (147M damage). Eggs climb to the Narmek Egg at 2Qa with Cosmo Cat as the 0.05% chase.
- Rebirth costs ride the door ladder through R5 then grow 2.9x per rebirth up to the hard cap of 50. Income doubles each time, so every loop takes about 1.45x longer than the previous one.
- The vault grows a floor every 10 slots (capacity 6 + rebirths + up to 3 bought slots, max 59 across 6 floors).
- Jackpot hunting (VOID, PRISMATIC, Diamond, charged) and stacked-mutation vault records become the number fantasy. A PRISMATIC common is worth roughly 10 minutes of income; the biggest stack is capped at 5,000x.
- The economy model targets an average player reaching area 8 at about 17 hours of play, a whale with the 2x pass and boosts in about 2 hours.

---

# Part 2: Every system in depth

## 4. Currencies, multipliers and the number pipeline

### 4.1 The two currencies

| Currency | Save key | Earned from | Spent on |
|---|---|---|---|
| **Cukes** ("Cucumbers" in code) | `Stats.Cucumbers` | Smashing cucumbers, boss pools, time skips, quest skips, offline pet farming, minigame spinner | Vault cucumber upgrades only |
| **Coins** | `Stats.Coins` | Selling Cukes 1:1, selling carried cucumbers, vault pads, chests, quests, streak, goals, playtime, index milestones, Starter Pack, vault time skips | Doors, pickaxes, eggs, rebirths, board upgrades, evolving |

`Player.RawStats.Cukes` and `Player.RawStats.Coins` are the real NumberValues every script reads and writes. `Player.leaderstats.Cukes` and `.Coins` are **StringValues** holding the abbreviated display text (the core playerlist's own abbreviation stops at billions). `leaderstats.Rebirths` stays a NumberValue. Any new code must read and write `RawStats`, never `leaderstats`.

The `RawStats.Changed` signals mirror into the profile immediately, so any direct `.Value` write persists the moment it happens.

### 4.2 The multiplier stack (`CurrencyHandler.GetMulipliers`, spelled exactly that way in code)

Every grant goes through `CurrencyHandler.AddCurrency({Player, Currency, Amount, HasTotal, WasPurchase, MultipliersApplied, Hide})`. If `WasPurchase` or `MultipliersApplied` is set the amount is granted flat; otherwise:

```
Cukes:  amount × 2^Rebirths × 2 (2x Cucumbers pass) × Pets.Multi1 × 2 (2x boost active) × 1.5 (Group Frenzy member)
Coins:  amount (FLAT since the 2026-08-28 redesign; the old rebirth double-dip is gone)
```

`Pets.Multi1` starts at 1 and each equipped pet adds its Multi1. Non-purchase grants also feed season stats. Purchases and multiplier-applied grants skip the coin popup only if `Hide` is set.

### 4.3 Number formatting

`NumberController.SuffixNumber` renders K/M/B/T/Qa/Qi and onward to vigintillion (10^63) with a scientific fallback past 10^153. HP bars use `BreakablesService.FormatHP` (raw below 100k, then truncated k/M/B/T with 2 decimals).

## 5. Breakables

All server logic is in `ServerStorage.ServerController.BreakablesService` (4,991 lines, at Luau's 200-local limit: never add top-level locals there, use function fields or table keys). Client feel is `StarterPlayerScripts.BreakablesClient` (2,569 lines).

### 5.1 Spawning and population

- Templates: `ServerStorage.Assets.BreakableModels` (58 zone-prefixed models, for example `Desert Prickly Cucumber`). Live cucumbers spawn into `workspace.Breakables.<Zone>` at 0.75 world scale (2x during Super Strength).
- Each zone has two quotas: **sliced** (tap candy, 8 HP, reward 3) and **other** (the weighted regular pool). Targets scale with server player count: other = clamp(12 + 3 per extra player, 12, 32); sliced = clamp(7 + 3 per extra player, 7, 28). Idle biomes keep 2 sliced + 3 other.
- **Active zones** are every player's current biome plus its two neighbours (so streaming players always see populated fields next door). A round-robin worker does one spawn or removal per 0.08 s.
- A destroyed cucumber respawns after 6 s. A **tree** is guaranteed to be standing in every zone (the next regular spawn is forced to the tree type if none exists).
- `PruneZone` removes over-target extras but never bosses, lightning jackpots or player-dropped carries.

### 5.2 Zone ladders

The dictionary rewards are zone-free; the engine multiplies them at spawn and break time:

| Zone | Value multiplier (Doors `Orb × Multi`) | HP wall (`ZONE_HP`) |
|---|---|---|
| Spawn | 1 | 1 |
| Desert | 8 | 13 |
| Samurai | 64 | 165 |
| Farm | 512 | 2,050 |
| Snow | 4,096 | 24,500 |
| Underwater | 32,768 | 285,000 |
| Volcano | 262,144 | 3.25M |
| Narmek | 2,097,152 | 36.5M |

Value climbs 8x per area and HP about 12 to 13x, while pickaxes and pets supply damage at the same pace, so kill times stay flat and only the numbers explode.

### 5.3 Cucumber types per zone (Weight / base HP / base reward)

Common 30 HP everywhere; trees 300 HP / 360 reward everywhere. Sliced types are on their own quota (8 HP / 3).

- **Spawn:** Cucumber 61/30/8 · Slice Stack 24/57/20 · Vined 10/105/56 · Flowered 4/180/144 · Cucumber Tree 2/300/360 (sliced: Sliced Cucumber)
- **Desert:** Prickly 46/30/8 · Sliced 25/46/15 · Sun-Baked 14/70/28 · Wrapped 7/105/56 · Cactus 4/150/105 · Desert Palm 2/213/195 · Sandstone Tree 1/300/360 (Sun-Dried Slice)
- **Samurai:** Katana 53/30/8 · Bamboo 25/50/17 · Lantern 12/82/37 · Bamboo Grove 6/130/82 · Torii Gate 3/199/173 · Sakura Tree 1/300/360
- **Farm:** Muddy 61/30/8 · Crate 24/57/20 · Windmill Plant 10/105/56 · Hay Bale 4/180/144 · Cucumber Tree 2/300/360 (Cucumber Basket)
- **Snow:** Snowcap 46/30/8 · Snowball Slice 25/46/15 · Crystal 14/70/28 · Frozen 7/105/56 · Snow Tree 4/150/105 · Icicle Tree 2/213/195 · Frozen Tree 1/300/360 (Frozen Slice)
- **Underwater:** Seaweed 46/30/8 · Shell Slice 25/46/15 · Coral 14/70/28 · Pearl 7/105/56 · Kelp Tree 4/150/105 · Bubble Tree 2/213/195 · Coral Tree 1/300/360 (Bubble Slice)
- **Volcano:** Charred 53/30/8 · Molten 25/50/17 · Flame 12/82/37 · Obsidian Tree 6/130/82 · Volcano Cucumber 3/199/173 · Magma Tree 1/300/360 (Molten Slice)
- **Narmek:** Meteor 46/30/8 · Planet Slice 25/46/15 · Astronaut 14/70/28 · Neon Alien 7/105/56 · Moon Tree 4/150/105 · Alien Tree 2/213/195 · Galaxy Tree 1/300/360 (Moon Slice)

Each type also carries `BonusCoins` (1 to 90) paid directly as Coins on break, scaled by the zone Multi and the pet Multi2 stat.

### 5.4 Materials (rolled at spawn, exclusive, baked into the type)

| Material | Chance per spawn | Value | HP | Direct coins | Looks |
|---|---|---|---|---|---|
| GOLDEN | 4% (16% during Golden Hour) | ×12 | ×3 | ×10 | gold Foil |
| DIAMOND | 0.6% (rolled first, exclusive with golden) | ×50 | ×5 | ×25 | icy Glass, name prefix "Diamond " |

### 5.5 Mutations (always-on weighted mix, stack on top of materials)

| Mutation | Odds per spawn | Value | Special behaviour |
|---|---|---|---|
| NEON | 1 in 100 | ×15 | |
| SHADOW | 1 in 100 | ×15 | |
| FROZEN | 1 in 250 | ×20 | In the vault: 0.8x earn rate but **cannot be stolen** |
| RADIOACTIVE | 1 in 400 | ×25 | |
| MOLTEN | 1 in 400 | ×25 | In the vault: pad rate ramps up to 2.5x over an hour uncollected (heat resets on collect) |
| ROYAL | 1 in 667 | ×40 | |
| VOID | 1 in 1,200 | ×150 | deep purple body |
| PRISMATIC | 1 in 20,000 | ×750 | server-wide chat announcement, live rainbow hue cycle, completes any quest-board Catch quest |

`MUTATION_CHANCE = 0.0305` is the sum of the rotation entries and must be kept in sync. The material × mutation × lightning product is clamped at **5,000x** (`MUTATIONS.StackCap`). Colours are mirrored for UI text in `ReplicatedStorage.Modules.MutationColors`.

### 5.6 Lightning (CHARGED)

Each zone runs its own clock: every 120 to 240 s a bolt converts one plain, non-mutated cucumber (golden or diamond allowed) into CHARGED with a flat multiplier rolled from 40 to 80. One live jackpot per zone; unclaimed ones fizzle after their lifetime (75 s) plus one grace extension if damaged. Charged carries display the tag "CHARGED" and price as ×50 in the vault.

### 5.7 Damage model

- **Click** (`PickaxeStrike` remote, validated server-side with a 0.25 s debounce, range = surface radius + 30 studs, locked-biome guard): `floor(floor(PickaxeDamage × FriendBoost) × ComboMult)`, then ×5 under Super Strength, then a 10% crit for ×5. Combo grows +0.05x per consecutive accepted hit within a 3 s window, capped at 2x. Combo is per player, not per target. Indirect (auto-aim) strikes are flat 1x. Clicks beyond reach but within 55 studs only commit the target for pets.
- **Friend boost:** +10% pickaxe damage per friend in the server, up to 5 (+50%). Shown by `FriendBoostClient`; excluded from time-skip quotes.
- **Pets:** one combined swarm strike every 0.6 s = `max(1, 2 + Σ equipped pet Damage)`, same 10% crit, ×2 under Super Strength. All equipped pets must be within 10 studs of the target surface; leash 110 studs from the player; after the target dies pets chain to another cucumber within 15 studs.
- **Autofarm** (gamepass): the server auto-strikes for you (`AutoFarmEnabled` attribute, toggled from the right rail).

### 5.8 Break payout

```
totalReward = Type.Reward × zone Orb × Multi [× material] [× mutation] [× lightning] (product capped 5000x) [× 6 if boss]
per damager: max(1, floor(totalReward × myDamage / totalDamage)) → AddCurrency("Cucumbers") with the full multiplier stack
BonusCoins → floor(BonusCoins × zone Multi × share × Pets.Multi2), min 1 → AddCurrency("Coins")
```

Break also credits TotalBreaks and GoldenBreaks, counts toward the boss meter and any active Cucumber Smash, fires `PortalCucumberDestroyed` (portals, quests), and hands the cucumber to the last attacker as a carry (section 11).

### 5.9 Client feel

`BreakablesClient` owns idle bob and spin, hover glow, squash-and-stretch, damage numbers, the "Nx COMBO" popup, pet attack bolts, chunk explosions and camera kicks. The milestone celebration (Star Sting, confetti, camera kick) only fires on real server combos of 5, 10 and 25. Mutation sparkles and lights are client-local and distance-budgeted (8 sparkles / 4 lights on low-end devices, 20 / 10 otherwise). Tapping Roblox's movement thumbstick never swings.

## 6. Areas and doors

Dictionary: `ServerController.Dictionaries.Doors`. Service: `DoorService`. Client: `DoorClient` (FrameworkLoader) and `DoorArrowClient` (floor arrow to the next affordable door).

| Order | Zone | Name | Price (Coins) | Min rebirths |
|---|---|---|---|---|
| 1 | Spawn | Spawn | free | |
| 2 | Desert | The Wild West | 60,000 | |
| 3 | Samurai | Samurai Palace | 5,000,000 | |
| 4 | Farm | The Farm | 300,000,000 | 1 |
| 5 | Snow | The Arctic | 60,000,000,000 | 2 |
| 6 | Underwater | The Ocean | 5,000,000,000,000 | 3 |
| 7 | Volcano | The Volcano | 400,000,000,000,000 | 4 |
| 8 | Narmek | The Greenland | 25,000,000,000,000,000 | 5 |

Flow: touching a door's hit part prompts the Door panel (rebirth gate checked first); confirming fires `PurchaseDoor`, the server re-checks the gate and balance, removes the Coins, appends the zone to the `DoorData` string (`"Spawn # Desert # ..."`) and mirrors it to `PlayerData.Doors.OwnedString`. Buying a later door backfills all earlier doors; a join-time pass self-heals old saves. The client hides owned doors by parking them in `DoorReserve`, re-derived from `OwnedString` whenever it changes (streaming-safe). Rebirth resets `DoorData` to `"Spawn"` and restores the doors.

Teleports: `Teleport` (to an owned zone pad), `TeleportToShop`, `TeleportToSell`, `TeleportToVault` are network events; all are refused while carrying stolen loot.

## 7. Pickaxes

Dictionary: `Dictionaries.Pickaxes`. Service: `PickaxeService`. Purchase is strictly sequential: you can only buy the pickaxe whose Order equals your `BuyAmount` (starts at 1, +1 per purchase). The pickaxe is a plain Tool in the character; the hotbar is disabled (`BackpackHotbarDisable`).

| # | Pickaxe | Price | Damage | Range |
|---|---|---|---|---|
| 0 | Wood | free | 3 | 6 |
| 1 | Stone | 400 | 5 | 7 |
| 2 | Bronze | 6,000 | 14 | 8 |
| 3 | Iron | 60,000 | 38 | 9 |
| 4 | Steel | 500,000 | 105 | 10 |
| 5 | Gold | 2.5M | 290 | 11 |
| 6 | Emerald | 10M | 800 | 12 |
| 7 | Ruby | 60M | 2,200 | 13 |
| 8 | Amethyst | 300M | 6,000 | 14 |
| 9 | Diamond | 2B | 16,500 | 15 |
| 10 | Valentine | 10B | 45,000 | 16 |
| 11 | Magma | 60B | 124,000 | 17 |
| 12 | VoidNeon | 250B | 340,000 | 18 |
| 13 | CosmicIce | 1T | 935,000 | 19 |
| 14 | YinYang | 6T | 2.6M | 20 |
| 15 | Galaxy | 40T | 7M | 21 |
| 16 | SolarFlare | 200T | 19.5M | 22 |
| 17 | BloodMoon | 1Qa | 53.5M | 23 |
| 18 | Rainbow | 5Qa | 147M | 24 |

Every step is a 2.75x damage jump. Range feeds `Stats.Radius`. `CharacterJoined` re-grants the saved equipped pickaxe on every respawn and self-heals an equipped-but-unowned desync back to Wood.

## 8. Pets, eggs, evolving, index, forge

Dictionaries: `Dictionaries.Pets` (77 pets) and `Dictionaries.Eggs`. Services: `PetService` with children `EggService`, `EquipService`, `EvolveService`, `PetDefaults`. Client: `PetController` (+`Movement`), `EggController` (+`UiController.Single/Triple`, `RarityController`), panels `Pets`, `Evolving`, `Index`, `Shards`. Models: `ReplicatedStorage.Assets.Pets`.

### 8.1 What the three stats do

- **Multi1**: added to `Pets.Multi1` on equip; multiplies every Cuke grant. The real progression stat.
- **Damage**: summed into `Pets.Damage`; the pet swarm hits for `2 + Damage` every 0.6 s. Pets do almost all the damage.
- **Multi2**: summed into `Pets.Multi2`; only scales the small direct `BonusCoins` drops on break. (On the dev save this stat has been replaced by a WalkSpeed bonus, see section 29.)

### 8.2 Eggs (Coins, must own the zone, stand on the pad)

| Egg | Price | Pool (percent) |
|---|---|---|
| Basic | 250 | Cat 40, Dog 30, Bunny 15, Wolf 9, Tabby 5, Fox 1, Gregory 0.002 (secret, hidden from the UI) |
| Desert | 100K | Barrel 40, Treasure Gem 30, Cannon 15, Chest 9, Desert Overlord 5, Cactus 1 |
| Samurai | 3M | Dog Ninja 40, Good Ninja 30, Evil Ninja 15, Good Samurai 9, Evil Samurai 5, Sensei 1 |
| Farm | 200M | Hay 40, Bird 30, Panda 15, Cow 9, Pig 5, Farmer 1 |
| Frozen | 10B | Red Snowman 40, Blue Snowman 30, Frozen Dragon 15, Frozen Hydra 9, Frozen Ice Shock 5, Frozen Gem 1 |
| Ocean | 500B | Oceanic Dog 40, Oceanic Kitty 30, Oceanic Bunny 15, Oceanic Bear 9, Ocean Dragon 5, Atlantic Hydra 1 |
| Lava | 30T | Lava Plume 40, Lava Golem 30, Lava Veltal 15, Lava Trio 9.95, Lava Dragon 5, Demon Dog 0.05 |
| Narmek | 2Qa | Moon Bunny 40, Satellite Pup 30, Alien Slime 15, Meteor Moth 9.95, Nebula Fox 5, Cosmo Cat 0.05 |
| Food Cuke | reward-only (playtime, spinner) | Popcorn 30, Cotton Candy 24, Lollipop 18, Fried Egg 12, Cupcake 8, Taco 4, Watermelon 2.5, Burger 1, Pizza 0.49, Ice Cream Cuke 0.01 |

Hatch types: **Single** (E), **Triple** (R, 3x price, needs the Triple Egg Hatch pass), **Instant** (skips the reveal, needs the pass), **Auto** (needs the pass; resolves to Triple if owned; the client queues the next hatch on reveal end; STOP button in `AutoHatchControls`).

Roll rules: float-weighted roll; a brand-new player's first-ever Basic Egg pet is upgraded to at least Rare; **pity is per egg**: the rarest pet is guaranteed within 25 hatches (50 for eggs whose rarest pet is under 0.1%: Lava, Narmek, Basic's Gregory). Hatches at 10% or rarer are announced in chat (`RareHatchChat`); secret hatches log analytics. Settings can auto-delete Common / Uncommon / Rare hatches (Coins still spent). Inventory cap 30 + purchases; hatching is refused at cap.

### 8.3 The full pet table (Multi1 / Damage / Multi2)

**Basic Egg:** Cat 1 / 2 / 1 · Dog 1 / 2.5 / 1 · Bunny 1.5 / 3 / 1 · Wolf 2 / 4 / 1 · Tabby 3 / 5.5 / 1.5 · Fox 4.5 / 9 / 1.5 · Gregory 50 / 10,000 / 6 (Mythical)
**Desert Egg:** Barrel 3.5 / 25 / 1.5 · Treasure Gem 4.5 / 31 / 1.5 · Cannon 5.5 / 40 / 1.5 · Chest 7.5 / 52 / 2 · Desert Overlord 10 / 70 / 2 · Cactus 16 / 110 / 2.5 (Flying)
**Samurai Egg:** Dog Ninja 10 / 280 / 2 · Good Ninja 12 / 350 / 2 · Evil Ninja 16 / 450 / 2.5 · Good Samurai 21 / 590 / 3 · Evil Samurai 28 / 780 / 4 · Sensei 45 / 1,300 / 5.5
**Farm Egg:** Hay 30 / 3,200 / 4 · Bird 38 / 4,000 / 5 · Panda 48 / 5,100 / 6 · Cow 63 / 6,700 / 7.5 · Pig 84 / 9,000 / 9.5 · Farmer 140 / 14,000 / 15
**Frozen Egg:** Red Snowman 90 / 38K / 10 · Blue Snowman 110 / 48K / 12 · Frozen Dragon 140 / 61K / 15 · Frozen Hydra 190 / 80K / 20 · Frozen Ice Shock 250 / 110K / 26 · Frozen Gem 400 / 170K / 41
**Ocean Egg:** Oceanic Dog 280 / 430K / 29 · Oceanic Kitty 340 / 540K / 35 · Oceanic Bunny 440 / 690K / 45 · Oceanic Bear 580 / 900K / 59 · Ocean Dragon 770 / 1.2M / 78 · Atlantic Hydra 1,200 / 1.9M / 120
**Lava Egg:** Lava Plume 800 / 5M / 81 · Lava Golem 1,000 / 6.2M / 100 · Lava Veltal 1,300 / 8M / 130 · Lava Trio 1,700 / 10M / 170 · Lava Dragon 2,200 / 14M / 220 · Demon Dog 3,600 / 22M / 360 (Mythical)
**Narmek Egg:** Moon Bunny 2,500 / 60M / 250 · Satellite Pup 3,100 / 75M / 310 · Alien Slime 4,000 / 96M / 400 · Meteor Moth 5,200 / 130M / 520 · Nebula Fox 7,000 / 170M / 700 · Cosmo Cat 11,000 / 270M / 1,100 (Mythical)
**Food Cuke Egg:** Popcorn 4 / 60 / 1.5 · Cotton Candy 5 / 80 / 1.5 · Lollipop 6.5 / 110 / 1.5 · Fried Egg 8 / 150 / 2 · Cupcake 10 / 210 / 2 · Taco 13 / 280 / 2.5 · Watermelon 16 / 380 / 2.5 · Burger 20 / 500 / 3 · Pizza 28 / 900 / 4 · Ice Cream Cuke 40 / 3,000 / 5 (Omega)
**Boss forge (10 shards each, repeatable):** Colossal Cucumber 8 / 40 / 1.5 · Cactus Colossus 28 / 450 / 3 · Shogun Colossus 80 / 5,000 / 8 · Harvest Colossus 240 / 60K / 25 · Frozen Colossus 700 / 700K / 70 · Abyssal Colossus 2,000 / 8M / 200 · Magma Colossus 6,000 / 100M / 600 · Cosmic Colossus 18,000 / 450M / 1,800 (strongest obtainable pet)
**Specials:** Lil Pickle 2 / 3 / 1 (tutorial) · Blazing Pickle 25 / 5,000 / 3.5 (playtime 30 m, once ever) · King Cuke 60 / 25,000 / 7 (playtime 90 m, once ever) · Red Demon 500 / 500K / 51 (Robux, also in the Starter Pack) · Purple Hydra 800 / 900K / 81 (Robux) · Heavenly Angel 800 / 900K / 81 (Robux, Mythical) · Golden Cucumber 1,200 / 2M / 120 (season Cukes champion) · Solid Gold Coin 600 / 800K / 61 (season Coins champion) · Silver Pickle 300 / 300K / 31 (season top 10) · Diamond Gherkin 600 / 800K / 61 (no grant path yet)

Existing saves re-sync every owned pet's stats from the live dictionary on join (Golden keeps its 1.5x), so retuning the dictionary reaches everyone. Retired OG Pickle copies are purged from saves on join.

### 8.4 Equipping

Slots = 4 base + board "Pet equips" (max +3) + legacy "+2 Pets Equip" product (max +6) + "+4 Pet Slots" pass, hard-capped at **11** live equips in `EquipService`. **Equip Best** ranks owned pets by Multi1 and fills every slot. Equipped pets follow the character (`PetController.Movement`, `Character.Pets` folder), are re-cloned on respawn, and a join-time race guard books stats even if the character is not ready yet. Stale over-cap equip flags self-heal on join.

### 8.5 Evolving (the only variant system)

Select 3 Normal copies of one pet at the Evolving altar in the Arctic; the server validates ownership, same name and not-already-Golden **before** charging **2x the pet's egg price** (1M for pets with no egg), deletes the three and grants one **Golden** copy: 1.5x Multi1, Multi2 and Damage, gold recolour plus particles, sells for 1.5x.

### 8.6 Pet Index and the Shards forge

- **Index** (`IndexService`, `Index` panel): every 5 distinct pets discovered = 1 milestone; claiming milestone N pays 500 × N Coins flat.
- **Shards** (`Shards` panel, Shards God NPC): killing a boss you damaged drops 1 shard of that boss; 10 shards forge that zone's boss pet (shards are spent, repeatable). Legacy `ColossalShards` migrate into `BossShards.Spawn` on the next kill.

### 8.7 Selling pets

`SellPets` RemoteFunction at the vendor: Common 100, Uncommon 250, Rare 600, Epic 1,500, Legendary 3,500, Special 5,000, Mythical 10,000, Omega 25,000 Coins, Golden ×1.5, flat. Max 50 per request, equipped pets and pets mid-trade refused, inventory count recomputed absolutely.

## 9. The upgrade board

Physical board `workspace.Upgrader` at the bank entrance; dictionary `Dictionaries.Upgrades`; server `UpgradeService.FunctionButton` via the `PurchaseUpgrade` remote; client `UpgraderBoardClient`. Price ladder is `{1, 15, 100} × Price` (mirrored in server and client); the authored card text on the board is stale and overwritten at runtime.

| Upgrade | Base price | Level prices | Max | Effect |
|---|---|---|---|---|
| Vault slots | 500,000 | 500K / 7.5M / 50M | 3 | +1 podium each (VaultService watches the replicated IntValue and relayouts the stall) |
| Pet equips | 25,000 | 25K / 375K / 2.5M | 3 | +1 equip slot each |
| Smashes required | 50,000 | 50K / 750K / 5M | 3 | −3 cucumbers per level on every portal requirement (portals only, not bosses) |

Retired upgrades "Faster walkspeed" and "Hatch speed" are scrubbed from saves on join. Base walkspeed is a flat 29.

## 10. Rebirth

`RebirthService`; panel `RebirthNewFrame`; HUD arrow `RebirthArrowClient` (left-rail button wobbles READY when affordable).

- **Cost** (Coins): R0→1 90M, R1→2 20B, R2→3 1.5T, R3→4 100T, R4→5 7.5Qa, then ×2.9 per rebirth. Hard cap **50**.
- **Gain:** income multiplier becomes **2^R** on Cukes; +1 vault slot; +15 s vault lock time. Trading unlocks at R1; doors 4 to 8 need R1 to R5.
- **Resets exactly three things:** Cukes to 0, Coins to 0, doors back to Spawn (then a respawn at Spawn). Pickaxes, pets, board upgrades, shards, quests and the vault all survive; pets are unequipped and re-equipped around the respawn.
- The panel shows "CUCUMBER EARNINGS x2 → x4", vault slot and lock-time callouts, a progress bar filled by Coins/cost, and needs a double click to confirm. Celebration FX ride the `RebirthFX` event.

## 11. Carry system

`CarryService` (server), `CarryClient` (UI), `CarryShowcaseClient` (centre-screen "NEW CUCUMBER" popup), `CarryVaultTrailClient` (green chevron trail to an open podium), `HideOwnTagClient`.

- **100% catch mode:** every template-type cucumber you break lands on your arm (boss, nuke and mid-tutorial breaks excluded; the tutorial's `TutorialCarryPending` guarantees the first catch). While already carrying, only a **strictly rarer** break swaps the arm cucumber; rarity = `BreakablesService.CarryRarityOf` (spawn share ÷ 2 per zone tier × material/mutation/lightning odds).
- The carry is a welded shoulder model ("CarriedCucumber" in the character) with an IK-steadied left hand; the pickaxe stays equipped and mining continues. Player attributes `CarryingCucumber` (full display name including mutation prefix) and `CarryingCucumberValue` drive the UI.
- The overhead billboard on the carried cucumber shows a colour-coded name, the coin value and a DROP button (scaled 0.6 on phones, 0.8 on tablets). The showcase popup shows the model spinning with "[1 IN X]" odds; jackpots (≥1 in 1000) hold longer with confetti.
- **Drop:** inside the cucumber's home field it replants at your feet as a real breakable (full HP, `Carried=true` so the pruner leaves it); anywhere else it flies to a random spot in its home field.
- Carrying is a 1.25x walk. Teleports are allowed while carrying, but refused while carrying **stolen** loot (1.5x slower walk).
- **Boss trophy:** a killed boss's cucumber goes to its top damager as a guaranteed carry (rate = value × 6 / 220), announced in gold chat, and can be stored in the vault.
- Value of a carry = `EffectiveRate × 250` Coins, paid flat by the vendor's "I have a cucumber to sell" option.

## 12. The Cucumber Bank

Server: `VaultService` (2,712 lines) with child `BankBuilder` (pure geometry) and `ServerStorage.BaseBreakInService`; guard script `VaultPickaxeGuard`; clients `VaultFXClient`, `VaultTextClient`, `HeistCombatClient`.

### 12.1 Geometry and capacity

`BankBuilder.Build(levels, extras)` destroys and regenerates `workspace.CucumberBank` from per-stall levels on boot and on every upgrade, sampling Material/Color per part kind from the current bank so Studio restyling survives. **8 stalls** (4 per row, ids 1 to 8, north/south across a walkway; assigned per session, so players 9 and up in a 60-player server get no vault).

- Stall level = owner's rebirths. Width 36 + 5.75 per level (capped at 5 levels). Capacity = **6 + rebirths (≤50) + Vault slots upgrade (≤3)** = max 59.
- Every **10 slots** adds a storey (floor 2 opens at 5 rebirths, 3 at 15, 4 at 25, 5 at 35, 6 at 45), reached by a corner hole and gold truss ladder. Storeys are 14 studs tall.
- Each stall: NameSign (owner headshot + "NAME'S VAULT", or "EMPTY"), vertical neon laser bars across the door, invisible DoorZone that bounces intruders, a row of gold pedestals with invisible `Spot<i>` markers, a green CollectPad in front of each pedestal, a security lever (`VaultLever`, clone of `ReplicatedStorage.Lever`) with a countdown card, and prompts.
- The upgrade board follows the deck's west edge on every rebuild.

### 12.2 Storing, taking back, replacing

One `PodiumPrompt` per pedestal (hold 0.25 s), owner only: empty podium + carrying = **Store**; occupied + empty-handed = **Take Back**; occupied + carrying = **Replace** (swap). Stored models are anchored, scaled 1.25x, faced toward the door, and carry an `EarnBillboard` card: `[level] NAME` (GOLDEN / DIAMOND words coloured, rainbow gradient at [MAX]), mutation line in its own colour, `$rate/s`, `$value`, and a green UPGRADE pill with the Cuke cost. Cards scale per device and zoom 1.5x while you stand in your own stall.

### 12.3 Earning

- Base rate per stored cucumber: `EarnRateOf = max(0.01, breakValue / 220)` where `breakValue = Type.Reward × 8^(tier−1) × mutation multiplier (× 50 if charged)`, golden/diamond already baked into Reward. **Spawn-zone records get a flat +0.5/s.** Records are stamped `RateV = 4`; any rate-formula change must bump that stamp so saved records recompute on the next join.
- Effective rate = base × 1.18^(level−1), ×0.8 if FROZEN, × MOLTEN heat (1 + 1.5 × min(heat, 3600)/3600).
- The accrual loop ticks 5x per second and pays `EffectiveRate × ownerMult × dt` into `rec.Accrued`, where ownerMult = `Pets.Multi1 × 2^rebirths` read live. The card's $/s shows the paid rate.
- **Collect:** the owner steps on the pad; pays `floor(Accrued) + floor(OfflineCash)` flat (`MultipliersApplied`, still season-tracked), keeps the fraction, resets MOLTEN heat; cash-register SFX and a coin flight to the wallet.
- **Offline coins:** on load, time since `VaultLastSave` (ignored under 120 s, counted up to 16 h) converts at 50% for the first 6 h then 30% (6 full-rate hours max) × the saved `VaultMultSnap`, into `rec.OfflineCash`, shown as a grey line on the pad and paid with the next collect.
- **Upgrades:** cost = `Rate × 500 × 1.35^(level−1)` **Cukes**, max level 20 (×23.2 rate). Click the pill (VaultFXClient screen-rect hit test → `VaultUpgradeClick`). Level rides in the record and survives take-back, replace, steal and sale.
- `VaultTimeSkipService.Quote(seconds)` = Σ EffectiveRate × ownerMult × seconds; `QuoteCapped` = min(quote, half of farm-equivalent) for free faucets.

### 12.4 Persistence

`Data.VaultCucumbers` holds `{Spot, Zone, Name, Rate, Level, Rarity, Mutation, Accrued, OfflineCash, HeatT, RateV}` per record. `SaveVault` writes through on every mutation and about once per second, hard-gated on `stall.VaultLoaded` so a not-yet-restored stall can never save emptiness. `LoadVault` resolves types via `BreakablesService.FindType`, rebuilds models via `CarryService.BuildFromTemplate`, re-applies looks via `ApplyStoredLook`, migrates old rate stamps, and carries unbuildable entries forward untouched.

### 12.5 Locks, lasers and stealing

- Stalls start **locked** on assignment. `PullLever` (owner, hold 0.4 s) relocks for **75 s + 15 s per rebirth** and ejects non-friends. Locked = lasers on, door bounces intruders, card shows a countdown. A 1-minute warning notif fires before expiry; expiry drops the lasers, shows a red "YOUR VAULT IS OPEN" toast and a klaxon.
- While a stall is unlocked, every stored cucumber's `StealPrompt` (hold 1 s) is live for other players. `VaultService.Steal` re-validates everything server-side: lock state, thief within 14 studs of the spot, empty hands, not the owner, 1 s rate limit, and FROZEN records are immune. Success: uncollected pad money is zeroed, the record moves to the thief's arm (`CarryingStolen` attribute: 1.5x slower walk, no teleports, no sprint), alarm bell and siren at the stall, red sparkle trail, both players notified, and the victim's profile forgets the record immediately.
- Owners never see STEAL or BREAK IN prompts on their own stall; visitors never see podium prompts (per-viewer prompt filtering in VaultFXClient).

### 12.6 Heist combat

A successful steal starts a `Heist` session pairing thief and victim (`StealCombat` attribute on both). Both keep their pickaxes on the deck; a click opens a 0.55 s swing window and physical pickaxe contact deals 20 HP (`HeistCombatClient` draws custom HP bars and damage numbers; strike range 16 studs, 0.7 s cooldown). The victim respawns into the defence. Thief death or any carry loss returns the cucumber to its original spot (or the first free one); depositing it in the thief's own vault completes the steal. A thief leaving auto-returns the loot; the victim leaving forfeits.

### 12.7 Paid break-in

Each locked stall exposes a `BreakInPrompt` (hold 0.5 s, "NAME's Base") to visitors. `RequestPaidBreakIn` validates (locked, not the owner, near the door), `BaseBreakInService.Prepare` persists the victim id in DataStore `BaseBreakInState_v1` and prompts the **Break Into Base** product (id 3710299055). The receipt calls `GrantPaidBreakIn`: the lock drops to 0, lasers fall, the victim is told who broke in. Persisting the target first means a retried receipt after a rejoin still grants.

### 12.8 Related guards and UI

- `VaultPickaxeGuard` parks your pickaxe Tool while you stand on the bank deck (and BreakablesClient refuses to swing there) so vault clicks cannot mine; heist combatants are exempt.
- `VaultTextClient` scales bank billboards per device and zooms your own stall's cards.
- Finished-tutorial players spawn at their stall (`VaultService.StallSpawnCFrame`); the HUD's BIOME pill reads "VAULT" outside the bank and fires `TeleportToVault`.
- Boss bar, door arrows and portal arrows all hide on the deck and in the bank courtyard.

## 13. Bosses, goals and biome events

### 13.1 Boss summon

Each zone has a break meter in `ReplicatedStorage.BossProgress.<zone>` (attributes `Required`, `BossActive`, `BossHP`, `BossName`, event fields). Required = `Breaks × (1 + 0.05 × players in server)`. Only non-boss, non-nuke breaks count, and only while no boss or event is running. The HUD boss bar (`BossBarClient`) shows the meter for your sticky zone and flips red while the boss lives.

| Zone | Boss | Breaks | HP base | Direct coins |
|---|---|---|---|---|
| Spawn | COLOSSAL CUCUMBER | 90 | 3,500 | 250 |
| Desert | CACTUS COLOSSUS | 135 | 4,000 | 275 |
| Samurai | SHOGUN COLOSSUS | 180 | 4,500 | 300 |
| Farm | HARVEST COLOSSUS | 225 | 5,000 | 325 |
| Snow | FROZEN COLOSSUS | 270 | 5,500 | 350 |
| Underwater | ABYSSAL COLOSSUS | 330 | 6,500 | 400 |
| Volcano | MAGMA COLOSSUS | 390 | 7,500 | 450 |
| Narmek | COSMIC COLOSSUS | 450 | 8,500 | 550 |

Boss HP = `(HPBase + 800 × (players − 1)) × ZONE_HP`. Reward pool = `900 × zone value × 6`, split by damage share; every damager gets 1 shard of that boss; the top damager gets the trophy carry. A boss that survives 6 minutes escapes and pays **half** the per-HP rate with no coins, shards or trophy.

### 13.2 Mobile bosses

All eight bosses are walking Humanoid characters (`Mobile = true`, walk speed 11 to 13): they flee the nearest player within 60 studs, roam within 34 studs of the summon point, slam (1.15 s wind-up, 12-stud fling radius, telegraph ring) every 7 s when someone is in reach, unlock charges below 60% HP, and enrage below 25% (faster walk and attacks). Attacks fling players but never kill. `BossMotionClient` mirrors the timings for poses, telegraphs and shakes.

### 13.3 Boss Payback Nuke

1.4 s after a real kill, one missile falls on the zone's field (`NukeService.BossStrike`, 3 s travel, banner "BOSS PAYBACK NUKE", never harms players). Cucumbers below half damage vaporise unpaid; those over half damage break normally for their damagers. A fast respawn wave refills the field with at least 25% specials (forced Diamond / Golden / mutation).

### 13.4 Goal and events after a kill

A kill starts a **goal**: land `100 + 25 × (players in biome − 1)` non-boss hits to start an event. Events are declared in `BiomeEventRegistry` and run for 30 s:

| Event | Effect |
|---|---|
| GOLDEN HOUR | Golden spawn chance ×4 (16%) and the field's commons churn |
| SUPER STRENGTH | Click damage ×5, pet damage ×2, splash to everything within 10 studs, cucumbers and players scaled 2x, walk speed 2x (reverts in the lobby, courtyard and deck) |
| CUCUMBER SMASH | Needs 2+ players in the biome. Per-zone smash race: the boss bar shows "M:SS LEFT • YOUR SMASHES: N"; at the end a podium (`SmashLeaderboard`) shows the top 3; 1st gets the minigame reward spinner, 2nd and 3rd get 5 minutes of their own production in Cukes |

Events fire the `BiomeActivityPrompt` travel popup ("X started in Y! Go there?") to players in other owned biomes. The **Skip Boss/Event Requirement** product (3709040752) skips the current meter.

## 14. Portals and minigames

Five standalone portal services in `ServerScriptService` share `ServerStorage.PortalCucumberProgress` (per-player smash requirements, DataStore `PortalCucumberProgress_v1`) and `PortalUnlockService` (paid one-use credits, `PortalUnlockState_v1`). Each portal has a matching `<Zone>PortalClient` that renders the "READY / countdown / N more cucumbers needed" billboard and the iris transition (`PortalFXShared`).

| Portal | Minigame | Counts smashes in | Smashes required | Template |
|---|---|---|---|---|
| Starter Portal (Spawn) | Classic Obby (`InStarterObby`) | Spawn | 18 | `ServerStorage.Classic Obby` |
| Desert Portal | Wild West Rat Hunt: 10 rats with a revolver (`InDesertHunt`) | Desert | 27 | `Wild_West`, `Revolver`, `Rat` |
| Void Portal (in Samurai) | Bloxout Incorporated (`InVoidBloxout`) | Samurai | 90 | `BloxoutIncorporated` |
| Snow Portal | Avalanche (`InSnowAvalanche`) | Snow | 54 | `Avalanche`, `AvalancheBall` |
| Lava Portal | Lava Run (`InLavaRun`) | Volcano | 78 | `LavaRun` |

Rules: the Smashes required board upgrade subtracts 3 per level; completing a run arms a **1-hour cooldown** and resets progress; the **Unlock Portal Now!** product (3709119039) is a persisted one-use credit that bypasses both cooldown and smashes. Inside a minigame the jetpack, hoverboard, sprint, carry UI and showcase are all suppressed via the `In<Minigame>` attributes. `MinigameHudController` shows the run timer and best time (hidden for the rat hunt); `MinigameTimeService` persists best times (`MinigameBestTimes_v1`) and publishes `BestTime_<key>` attributes. `MinigameMusicController` swaps music; `MinigameIsolationClient` hides the outside world.

**Reward spinner** (`MinigameCompletionService` + `SelectingRewardClient`), weighted pool of 127: Cukes over 1 m (17), 2 m (15), 3 m (12), 5 m (10), 10 m (8), 15 m (9), 30 m (5), 1 h (4) quoted from your production; boss shards ×1 (9) / ×3 (4) into your highest zone's bucket; Food Cuke Egg (7); vault Coins over 2 m (10), 5 m (8), 15 m (6), 30 m (3) (an empty vault downgrades to the same-duration Cukes card). Amounts lock at pick time and grant once via a token handshake.

## 15. Free reward faucets

| Faucet | Where | Rule | Payout |
|---|---|---|---|
| **Quest Board** (`QuestBoardService`, `QuestBoardClient`) | lobby board | 3 quests: Smash 30-40, Collect 3-5 daily chests, Catch one specific weight-rolled type from a random unlocked biome (PRISMATIC is a wildcard). Each quest rolls a duration from 1 / 3 / 5 / 10 min. Claim on the board when done. All three claimed → 6 h reset | Cukes time skip for the duration plus vault Coins for the duration (capped at half farm-equivalent, min 500) |
| **Goals** (`GoalService`) | silent | Sequential: Smash 10 (200) → Hatch first egg (400) → Sell 2,500 Cukes (600) → Smash a GOLDEN (1,000) → Unlock The Wild West (2,000) | flat Coins, no notifications by design |
| **Daily streak** (`StreakService`) | on join | Consecutive days 1-7: 300 / 500 / 800 / 1,200 / 1,800 / 2,600 / 4,000; day 7 repeats; a missed day resets | flat Coins |
| **Playtime rewards** (`PlaytimeRewards`, `Playtime` panel, `PlaytimeReadyClient`) | gift button | Session-based post-tutorial timer: 30 s 2,500 Coins · 2 m Food Cuke Egg · 5 m 10-min 2x boost · 10 m 15-min time skip · 18 m 3 Food Cuke Eggs · 30 m Blazing Pickle (once ever, later sessions 30-min skip) · 1 h 2-h time skip · 1 h 30 m King Cuke (once ever, later sessions 1-h skip) | as listed |
| **Chests** (`ChestHandler`, `Chests` dictionary) | world | 12 h per-player cooldown: Daily 500, Group 1,000 (members only), Treasure 1,500, Samurai 4,000, Snow 10,000, Volcano 15,000 | flat Coins |
| **Offline Cukes** (`OfflineService`, `Vault` panel "Keep Farming") | on rejoin | Pet-only farming rate checkpointed every 30 s; absences under 120 s ignored; 50% of the first 6 h then 30%, capped at 6 full-rate hours (16 h wall clock) | Cukes, claimed from the panel |
| **Offline vault Coins** | vault pads | same tiers applied to the stored cucumbers' rates | Coins on next collect |
| **Index milestones** (`IndexService`) | Index panel | every 5 discovered pets | 500 × N Coins |
| **Group Frenzy** (`GroupOfferService`) | join the group | +50% Cukes forever, group chest access; popup 60 s into each session for non-members and on walking into the group chest | |
| **Tutorial** | once | Lil Pickle + 250 Coins (completion only) + 2,500 and 500 Coin gifts during the steps | |
| **Starter Pack offer** | first ask stamps a 30-min real-time expiry | 20,000 Coins + Red Demon (Robux) | |

## 16. Time skips

Two independent skip mechanics with one contract each: the quote already includes multipliers, so grants are flat.

- **Cucumber time skips** (`TimeSkipRateService`): a deterministic expected Cukes-per-second from your pickaxe (0.25 s tick), pet strike (0.6 s tick), 10% crit ×5 and the highest unlocked zone's baseline spawn mixture, times the full Cuke multiplier stack once. Consumers: Robux products (1 m / 5 m / 30 m / 5 h / 1 d / 1 w), playtime tiers, quest claims, spinner cards, Cucumber Smash runner-ups, offline farming.
- **Vault time skips** (`VaultTimeSkipService`): Σ stored EffectiveRate × ownerMult × seconds. Consumers: Robux vault products (same 6 durations, ids live), quest claims (capped variant), spinner coin cards. `TimeSkipQuoteServer` serves both quotes to the Store via `GetTimeSkipQuote` / `GetVaultTimeSkipQuote`.

The old walk-over map pickups (`WalkCucumberService`) were deleted in the 2026-09-01 cleanup.

## 17. Monetization

Definitions in `ReplicatedStorage.Modules.ControllerLoader.Custom.ProductController`; receipts in `ServerController.ProductHandler`; pass effects in `GamepassHandler`. Robux prices live on the dashboard only. Three user ids (1, 1660029941, 1196256323) bypass every pass for testing.

### 17.1 Gamepasses

| Pass | Id | Effect |
|---|---|---|
| 2x Cucumbers | 1902852565 | ×2 on every Cuke grant |
| Sprint | 1899183262 | ×2 walk speed, toggle on the right rail; off in minigames and while carrying stolen loot |
| Autofarm | 1919162313 | server auto-strikes, toggle on the right rail |
| Jetpack | 1919180303 | flight with fuel (1,400 max, 220/s spend, 160/s refill, thrust 46); off in minigames |
| Auto Egg Hatch | 1898883147 | hatch loop with STOP button |
| Triple Egg Hatch | 1903566581 | 3 rolls for 3x price |
| Instant Egg Hatch | 1911700950 | skips reveals |
| +75 Pet Storage | 1899609194 | inventory cap |
| +4 Pet Slots | 1903134517 | equip slots |

### 17.2 Developer products

| Product | Id | Effect |
|---|---|---|
| 2x Cucumbers boost 15 m / 1 h / 5 h | 3609774448 / 3609774551 / 3609774625 | boost seconds add to the remaining timer |
| Red Demon / Purple Hydra / Heavenly Angel | 3609774225 / 3609774320 / 3609773882 | pet grants (also the physical stands and the Store bundle cards) |
| Starter Pack | 3609836817 | 20,000 Coins + Red Demon, burns the offer timer |
| +10 Pet Inventory | 3609836686 | persisted |
| +2 Pets Equip | 3609836815 | legacy, capped at +6 |
| Time Skips 1 m / 5 m / 30 m / 5 h / 1 d / 1 w | 3609921759 / 779 / 799 / 818 / 841 / 920 | Cukes at the farming quote |
| Vault Time Skips 1 m / 5 m / 30 m / 5 h / 1 d / 1 w | 3710297823 / 863 / 865 / 866 / 867 / 869 | Coins at the vault quote |
| Skip Boss/Event Requirement | 3709040752 | completes the current meter |
| Unlock Portal Now! | 3709119039 | one-use portal credit |
| Break Into Base | 3710299055 | drops a locked vault's lasers |
| Nuke Server | 3610280695 | missiles hit every field, the buyer is paid for every live breakable at full multipliers |

The **Store** panel (SHOP button) has tabs Pickles (Cuke skips), Vault (coin skips), Bundles (pet cards) and Boosts. `GamepassPopup` shows a detail card before prompting. The Offers panel lists the pet products and the Starter Pack.

## 18. Onboarding

- **Loading:** `LoadingBootstrap` (ReplicatedFirst) → `UserInterfaceLoader.LoadingScreen` preloads and lifts the cover after the server's initial teleport (10 s cap in the loader, 20/60 s watchdogs in the bootstrap).
- **Tutorial:** section 3.2. Server side: `TutorialProgressServer` (funnel analytics, `TutorialStep` persistence and attribute, `wantcarry` / `wantupgradecukes` gifts), `PetShopGiftServer` (2,500 Coins once, must be within 20 studs of an egg stand), `PickaxeShopGiftServer` (500 Coins once at the shopkeeper), `TutorialTestOverride` (applies `ServerStorage.ForceTutorialOnJoin` for replays), and the `Tutorial` handler in `ServerNetwork` (completion, Lil Pickle, 250 Coins).
- **Intro cutscene:** `IntroCutsceneClient` is present but disabled.
- **First-session prompts:** `FavoritePromptService` + `FavoritePromptClient` (native favourite prompt, first session only), `GroupOfferService` + `GroupOfferClient` (Group Frenzy popup), Starter Pack offer (`GetStarterOffer` and the receipt handler still exist server-side, but the timed popup client was deleted in the 2026-09-01 cleanup and no panel currently sells the pack), `LikePromptClient` (the "LIKE THE GAME!" banner once per session after a new pet, a rebirth or a big win, 5-min session gate), chat tips every 4 to 10 minutes.

## 19. HUD, panels and every ScreenGui

### 19.1 `StarterGui.HUD` (Figma chrome, laid out by `HUD.TopStatusLayout` and scaled by `HudMetrics`)

| Element | Contents | Wiring |
|---|---|---|
| Wallet (bottom-left) | Coins and Cukes with icons, a "+" button | `+` opens the Store |
| TopStatus (top-centre) | BUY / BIOME / SELL pills | BUY → `TeleportToShop`; SELL → `TeleportToSell`; BIOME → teleport to the newest biome from the lobby, or "VAULT" → `TeleportToVault` elsewhere |
| LeftRail | Rebirth button (wobbles READY when affordable), Hoverboard button | Rebirth panel; `ToggleHoverboard` (×3 speed, hover 3 studs) |
| RightRail | Jetpack, Sprint, Nuke, Autofarm (and an Admin item for admins) | owners get ON/OFF toggles, others see the Robux price and get the gamepass popup |
| ButtonBar (bottom-centre) | BACKPACK, expanding to SHOP / PET INDEX / TRADING (`ButtonBarMenu`) | Pets panel, Store panel, Index panel, Trade panel |
| BossBar (separate ScreenGui) | zone meter / boss HP / event countdown, Skip button (Robux) | `BossBarClient`; hides in the lobby and bank, and while any panel is open |
| Settings gear | TopbarPlus icon next to the Roblox pills (`TopbarSettingsButtonClient`) | Settings panel |
| FriendBoostGui | friend-boost pill and invite button | `FriendBoostClient` |

Device classes: phone (short axis under 620 px, scale 0.36 to 0.46), tablet and desktop (0.5). Phones get a two-column right rail grid and a lifted toast stack.

### 19.2 `StarterGui.Display.Frame.Frames` panels (opened by `UserInterfaceLoader.Main.OpenFrame`, one module each under `ReplicatedStorage.Modules.UserInterfaceLoader`)

Offers · Shop (pickaxes, via the shopkeeper dialog) · Evolving · Vault (offline "Keep Farming" claim) · Index · Trade · Shards · Settings · Door (purchase prompt) · Store (Robux) · Pets (inventory, equip, Equip Best, Unequip All) · Rebirth · Playtime.

Settings rows: Mute Music, Mute Sfx, Disable Pop Ups, Low Quality, Disable Haptics, Hide My Pets, Hide Other Pets, Auto Delete Common / Uncommon / Rare. `PanelMetrics` keeps every panel on a shared canvas scale; `PanelMetricsTest` (run by `PanelMetricsWatchdog` in playtests) asserts ZIndex ordering.

### 19.3 Other ScreenGuis

EggUi (world hatch billboard) · EggRevealUI · SellBloom · HallOfGreen (season hall, placeholder text) · ShardsGodUI · GroupRewardsGui · TutorialGui + TutorialWorldArrow · ShopVendorUI + ShopVendorDialogBubble · CucumberVendorUI + VendorDialogBubble (with `NewPetSellController`) · ShardsGodDialogBubble · AutoHatchControls · EffectBursts · UITemplates (DamageNumber, ComboPopup, ClickCooldown, Viewport3D, HPBar, BossFaceGui) · NukeUI · SelectingReward · GamepassPopup · AdminPanel · BiomeActivityPrompt · SmashLeaderboard · CarryControls (style source only; the live carry UI is a billboard on the carried cucumber) · PromotedPets (folder holding `PromoteHandler`). The orphan RebirthArrow, RewardArrow, ShardArrow, HudTooltip and PostTutorialQuests guis were deleted in the 2026-09-01 cleanup.

Client-built guis at runtime: CarryBillboardHost, CarryShowcase, VaultFXGui, VaultOpenToast, QuestBoardGuiLocal, the heist HP bars, the like banner.

## 20. Audio, VFX and game feel

- **Sounds:** 48 templates in `ReplicatedStorage.Assets.Sounds`, each stamped with an `AuthoredVolume` attribute so the SFX mute toggle restores the authored mix. `SoundController.PlayFX(name, {Volume, Speed, Pitch, Parent, Key, MinInterval, MaxConcurrent, Variants, RollOff, Looped})` and `PlayFXAt(pos)` on the client (SFX-setting gated, throttled, capped); `SoundController.PlaySound` on the server for social 3D one-shots (alarms, lever, zap, deposits, construction) with roll-off caps.
- **Music:** `MusicManager` (register, play, stop, pause, fades, mute, ducking); lobby music `SoundService["Background Music"]`; boss and event themes duck it; minigames swap tracks.
- **Haptics:** `HapticUtil.Pulse`, gated by the Haptics setting.
- **Net FX events:** `VaultFX` (deposit, take-back, collect coin fountain, upgrade ding, max fanfare, lock zap sequence, expiry klaxon, stolen/robbed, floor unlocked), `CarryFX`, `RebirthFX`, `BreakableHit` / `BreakableBroken` payloads carrying Mutation / Charged / Diamond / Boss flags for the rarity ladder of sounds and bursts.
- **Feel rules that were tuned in:** milestone celebration only on real 5/10/25 combos; hit sound slots release on `Ended`; boss alarm only when the bar is visible; pet plinks throttled; charged hits have their own sound; one UIScale per element.

## 21. Social

- **Friends:** +10% pickaxe damage per friend in the server (max 5).
- **Group Frenzy** (14583228): +50% Cukes, group chest, admin ranks.
- **Trading** (`TradeService`, Trade panel): pets only, both sides at 1+ rebirth, 4 per side, equipped pets untradeable, every pet re-validated at execution, selling mid-trade refused.
- **Leaderboards:** four world boards (Coins, Time, Cukes, Breaks) refreshed every 90 s from ordered DataStores; `Leaderboards.Excluded` hides listed user ids on write and read.
- **Badges** (`BadgeAwardService`, `BadgeController`): Boss Slayer (first shard), Cuke Destroyer (500 breaks), Record Breaker (Classic Obby under 30 s), Hatch a Pet, Astronaut (enter Narmek).
- **Chat:** rare hatch announcements, PRISMATIC announcements, boss trophy lines, tips; `ChatCustomization` and `ChatHandler` for tags. Player identity tags over heads are hidden for yourself only.
- **Seasons:** `SeasonService` is fully built (weekly ordered stores, champion pets, Hall of Green) but `SEASON_ENABLED = false`.

## 22. Admin, dev hooks and testing

- **Admin panel** (`StarterGui.AdminPanel`, `AdminPanelService`): Group Frenzy rank 254+ (or any Studio playtest). Actions: SetCurrency, SetRebirths, GetPlaytime, ListPets, GivePets, ResetData (also wipes portal progress), UnlockVault, SpawnMutated (any mutation, TODAY or PRISMATIC; VOID is not in the cycler yet), StartEvent / StopEvent per biome, SpawnBoss, KillBoss, Lightning. `HD Admin` is also installed.
- **Workspace attribute hooks** (Studio, set from a server context): `StartEventDev = "Biome:EventId"`, `SmashEventDemo = true`, `SpawnBossDev`, `KillBossDev = "Zone:PlayerName"`, `QuestBoardDev = "reroll:Name" | "bump:Name:idx:n" | "claim:Name:idx" | "expire:Name"`, `VaultStealDev = "seed:Name" | "grab:Name:Thief"`. Client-side: `LikePromptDev = true`, player attribute `ForceIntroCutscene` (cutscene disabled now).
- **Tutorial replay:** set `ServerStorage.ForceTutorialOnJoin` to true (reset it after).
- **Telemetry:** Roblox AnalyticsService funnels (onboarding steps, ZoneProgression, RebirthDepth, StarterPack, TutorialSkipped, SecretHatch, LikePromptShown via `TelemetryRelayServer`), per-minute currency source events in `CurrencyHandler`.
- **Guards:** `PetRosterValidator` warns at boot if any egg-pool pet lacks a model; `PanelMetricsWatchdog` checks panel ZIndex in playtests; `Shutdown` handles soft shutdown migration.

## 23. Save data and DataStores

Profile store `CucumberData_Launch3`, key `*Player{}{}_<UserId>`, ProfileService with `ForceLoad`. Template (`ProfileService.UserData`):

| Field | Default | Purpose |
|---|---|---|
| `Stats.Cucumbers`, `Stats.Coins` | 0 | currencies (mirrored from RawStats) |
| `Stats.Radius` | 7 | pickaxe range |
| `Stats.DoneTutorial`, `TutorialStep`, `TutorialVersion`, `ClaimedTutorialPet`, `PetShopGiftGiven`, `PickaxeShopGiftGiven`, `ClaimedGroupPet` | false / 0 | onboarding flags |
| `Stats.Scale` | 1 | character scale (legacy) |
| `TotalStats` | 0s | TotalCucumbers, TotalCoins, TotalTime, TotalEggsOpened, TotalBreaks, GoldenBreaks |
| `ToolData` | Wood Pickaxe, BuyAmount 1 | pickaxes (`" # "`-separated Owned string) |
| `DoorData` | "Spawn" | owned zones (`" # "`-separated) |
| `Boosts`, `BoostTotals` | 0 | 2x Cucumbers seconds |
| `PetData` | `{Unlocked = ""}` | pet id → table; `Unlocked` is the `|`-separated index |
| `Chests` | {} | per-chest cooldown expiry |
| `QuestBoard` | {} | `{Quests, ResetAt}` |
| `Upgrades` | 0s | Vault slots, Pet equips, Smashes required |
| `EggPity` | 0 → per-egg table | pity counters |
| `MaxEquipIncrement`, `MaxPetInventoryIncrement` | 0 | legacy products |
| `SeasonStats`, `ClaimedSeasonRewards`, `GoldenChampion` | | seasons |
| `Streak` | Day 0, Count 0 | daily streak |
| `GoalIndex`, `GoalProgress` | 1 | goal chain |
| `Rebirths` | 0 | |
| `VaultLoot` | 0 | unused draft |
| `VaultCucumbers`, `VaultLastSave`, `VaultMultSnap` | {} / 0 | vault records, offline maths |
| `IndexClaimed` | 0 | |
| `ColossalShards` (legacy), `BossShards` | 0 / {} | per-zone shards |
| `SeenShardHint`, `ChosenPath`, `SeenStarterOffer`, `SeenGroupOffer`, `SeenFavoritePrompt`, `StarterOfferExpiry` | | one-time flags |
| `PlaytimeRewards.Once` | {} | BlazingPickle / KingCuke / FreeRebirth one-time flags |
| `OfflineData` | LastSeen, Rate, Vault | offline Cukes checkpoint |

Separate DataStores: `PortalCucumberProgress_v1`, `StarterPortalCooldown_v1`, `DesertPortalCooldown_v1`, `SnowPortalCooldown_v1`, `LavaPortalCooldown_v1`, `VoidPortalCooldown_v1`, `PortalUnlockState_v1`, `MinigameBestTimes_v1`, `BaseBreakInState_v1`, the four leaderboard ordered stores, and the season stores (`CucumberSeasonWinners_L2`, `CucumberSeasonL2_<season>_<stat>`). Admin ResetData wipes the profile and portal progress.

Migrations already in place: EggPity number → table, vault `RateV` stamps, `ColossalShards` → `BossShards`, legacy upgrade purge, OG Pickle purge, pet stat re-sync, door backfill, tutorial version reset.

## 24. Performance and streaming

- `StreamingEnabled` is on. Portals, promoted stands and the upgrade board are Persistent or Atomic so their billboards never ghost. Any world-anchored per-player UI must re-adorn on stream-in and never stay enabled with a nil adornee.
- `StreamTierClient` benchmarks FPS after load and reports to `DeviceStreamingServer`, which stamps the `StreamTier` attribute; High-tier clients get the neighbouring biomes streamed and rendered, Low-tier keep own-biome culling (`BreakablesClient` cull tick).
- `PerformanceClient` demotes touch and sub-38 fps clients to a Low tier (shadows and decoration off, pet distance culling). The Low Quality setting disables particles, beams, trails and textures.
- `CharacterModule` normalises oversized R15 avatars to 6 studs and clones the overhead Tag.

---

# Part 3: Code map and status

## 25. Architecture and boot sequence

### 25.1 Loaders

- `ReplicatedStorage.Modules.ControllerLoader`: shared utilities (`Custom`: ComponentController, SoundController, NumberController, TweenController, SettingsController, BadgeController, ProductController; `Imported`: CameraShaker, Module3D, ZonePlus, Network, FastWait). `GetController(name)` requires and caches.
- `ReplicatedStorage.Modules.FrameworkLoader`: client gameplay modules (`Client`: ClientHandler → ToolClient, DoorClient, ChestClient; ClientNetwork; PetController; EggController).
- `ReplicatedStorage.Modules.UserInterfaceLoader`: one module per panel plus Main, Animations, PopUps, Stats, Notifications, LoadingScreen.
- `ServerStorage.ServerController`: the server module registry. `GetModule(name)` requires and caches a child; `GetDictionary(name)` caches `Dictionaries.*`; `InitializeModulesWithBlacklist`, `PlayerJoinedWithWhitelist`, `PlayerLeftWithWhitelist`, `CharacterJoinedWithWhitelist` (after a 3 s wait) dispatch lifecycle calls.

### 25.2 Server boot (`ServerScriptService.Server`)

1. `InitializeModulesWithBlacklist({ProfileService, CharacterModule, GamepassHandler, PickaxeService, TeleportService, UpgradeService})` calls `.Initialize()` on every other ServerController module in parallel coroutines. One pcall wraps the whole loop, so a synchronous error in one module's Initialize aborts the rest: keep Initialize functions non-throwing.
2. `PlayerAdded` (0.5 s later): `PlayerJoined` on ProfileService, GamepassHandler, DoorService, BoostHandler, PetService, ChestHandler, UpgradeService, SeasonService, OfflineService, PlaytimeRewards, StreakService, GoalService, GroupOfferService, FavoritePromptService. (VaultService was removed from this list on 2026-09-01: it defines no `PlayerJoined` and assigns stalls from its own Initialize, and the nil call used to abort the loop silently for any later module.)
3. `CharacterAdded` (3 s later, sequential): CharacterModule, GamepassHandler, PickaxeService, PetService, SeasonService, RebirthService, UpgradeService.
4. `PlayerRemoving`: ProfileService only (everything else writes through to the live profile table).
5. `CharacterResetRequest` remote implements the clean reset used by Roblox's Reset button.

Every standalone `ServerScriptService` Script boots on its own and talks to the registry via `require(ServerStorage.ServerController).GetModule`.

### 25.3 Client boot (`StarterPlayerScripts.Client`)

Waits for `game.Loaded`, initialises FrameworkLoader modules (except ClientHandler), then `UserInterfaceLoader.Initialize()`, then ClientHandler modules (except ChestClient), and rebinds the Reset button. Every other LocalScript in StarterPlayerScripts runs independently.

### 25.4 Networking

The EasyNetwork-style `Network` module multiplexes named events and functions over a single pair of remotes: `Network:BindEvents{}` / `BindFunctions{}` on the server, `Network:FireServer(name, ...)` / `InvokeServer(name, ...)` on the client, `FireClient` / `FireAllClients` on the server. Server-side handlers are registered in `ServerNetwork.Initialize` (GetData, GetTimeSkips, GetPetStats, GetUserData, GetStarterOffer, PurchasePickaxe, PurchaseUpgrade, EquipPet, OpenEgg, UnequipAll, EquipBest, EvolvePet, GetVault, ClaimVault, PurchaseDoor, Teleport, TeleportToSell, TeleportToShop, TeleportToVault, ToggleHoverboard, ToggleSprint, Tutorial, ValidateSetting) and inside individual services (PickaxeStrike, DropCucumber, StealStrike, VaultUpgradeClick, QuestClaim, GetBossShards, ForgeBossPet, GetIndexProgress, ClaimIndexReward, trade events, and more). Plain RemoteEvents/Functions exist for subsystems that predate or sit outside the framework: `VendorRemotes` (OpenSellShop, SellAll, SellCompleted, SellPets, SellCarried, OpenShardsGod), `TutorialProgress`, `TutorialPetShopArrived`, `TutorialPickaxeShopArrived`, `AdminPanelRemote`, `<Zone>PortalRemotes`, `MinigameEffects`, `PortalUnlockRemotes`, `BaseBreakInRemotes`, `JetpackRuntime`, `NukeEvent`, `GroupJoinRemote`, `TelemetryRelay`, `StreamTierReport`, `GetTimeSkipQuote`, `GetVaultTimeSkipQuote`, `CharacterResetRequest`.

## 26. Script index

Line counts are from the live place. Backups, HD Admin and third-party library internals are omitted.

### ServerStorage.ServerController (35 modules + Dictionaries)

| Module | Lines | Role |
|---|---|---|
| ServerController | 152 | module registry and lifecycle dispatch |
| ServerNetwork | 311 | binds the shared remote handlers, tutorial completion, stolen-loot teleport gate |
| ProfileService (+InstanceValues 204, ProfileService lib 1735, UserData 116) | 215 | profile load/save, replicated value tree, template |
| CurrencyHandler | 321 | AddCurrency / RemoveCurrency / CheckIfEnough, multiplier stack, analytics |
| BreakablesService | 4991 | cucumbers, spawning, damage, jackpots, bosses, events, autofarm, lightning |
| CarryService | 599 | arm carries, rates, values, drop, boss trophy |
| VaultService (+BankBuilder 486) | 2712 | the Cucumber Bank |
| VaultTimeSkipService | 115 | vault coin quotes |
| TimeSkipRateService | 345 | Cuke production quotes |
| RebirthService | 303 | rebirth |
| DoorService | 260 | areas, join teleport |
| PickaxeService | 202 | pickaxe purchase and equip |
| UpgradeService | 161 | board purchases, legacy purge, walkspeed recomputes |
| PetService (+EggService 473, EquipService 293, EvolveService 147, PetDefaults 102) | 322 | pets end to end |
| ChestHandler | 224 | chests |
| ProductHandler | 248 | Robux receipts |
| BoostHandler | 110 | 2x boost timers |
| GamepassHandler | 49 | pass effects on spawn |
| PlaytimeRewards | 315 | playtime ladder |
| StreakService | 60 | daily streak |
| GoalService | 111 | silent goal chain |
| IndexService | 78 | index milestones, shard forge remotes |
| TradeService | 278 | pet trading |
| SeasonService | 272 | seasons (disabled) |
| OfflineService | 137 | offline Cukes |
| GroupOfferService | 88 | Group Frenzy membership and popup |
| FavoritePromptService | 39 | first-session favourite prompt |
| SmashEventService | 212 | Cucumber Smash scores and podium |
| BiomeEventRegistry | 63 | event definitions |
| NukeService | 459 | server nuke and boss payback nuke |
| HoverboardService | 157 | hoverboard mount |
| TeleportService | 48 | zone teleports |
| ServerHandler | 140 | shop/sell teleports, legacy pad wiring |
| CharacterModule | 146 | avatar normalisation, overhead tag |
| Leaderboards (+Coins, Orbs, Breaks, Time, Excluded) | 53 | world leaderboards |
| Dictionaries: Pickaxes 308, Doors 252, Pets 1109, Eggs 311, Chests 97, Upgrades 163 | | data tables |

### ServerStorage (standalone modules)

PortalCucumberProgress 255 · PortalUnlockService 216 · BaseBreakInService 146. Also `ForceTutorialOnJoin` BoolValue, minigame templates (Avalanche, LavaRun, Wild_West, Revolver, BloxoutIncorporated, Classic Obby), `Assets` (BreakableModels, Collectables, Tag). All dated backup folders were removed on 2026-09-01 (exported to `backups/Cleanup_2026-09-01/`).

### ServerScriptService (26 scripts)

Server 177 · Shutdown 51 · DisableCollisoins 44 · SellVendorServer 340 · ShopVendorServer 79 · PetShopGiftServer 122 · PickaxeShopGiftServer 108 · JetpackSystem 413 · StarterPortalService 449 · SnowPortalService 557 · LavaPortalService 517 · DesertPortalService 692 · VoidPortalService 525 · MinigameCompletionService 317 · ShardsGodServer 35 · MinigameTimeService 236 · TutorialTestOverride 22 · TimeSkipQuoteServer 18 · AdminPanelService 340 · TutorialProgressServer 181 · PetRosterValidator 29 · VaultPickaxeGuard 85 · QuestBoardService 297 · TelemetryRelayServer 38 · BadgeAwardService 67 · DeviceStreamingServer 95.

### ReplicatedStorage.Modules

ControllerLoader 31 (Custom: ComponentController 87, SoundController 143, NumberController 112 + Data, TweenController 39 + Data, SettingsController 357, BadgeController 122, ProductController 387; Imported: Module3D 247, Network 1086, FastWait 43, CameraShaker, ZonePlus) · FrameworkLoader 49 (ClientHandler 51, ToolClient 36, DoorClient 334, ChestClient 77, ClientNetwork 379, PetController 112 + Movement 440, EggController 167 + UiController 892 + Single 695 + Triple 426 + RarityController 56) · UserInterfaceLoader 155 (Animations 84, PopUps 181, Store 505, Door 159, Shop 88 + Pickaxes 364, LoadingScreen 324, Trade 186, Offers 135, Settings 191, Pets 823, Notifications 155, Evolving 356, Main 810, Vault 158, Index 357, PlaytimeNewFrame 162, Shards 187, RebirthNewFrame 332) · HudMetrics 130 · PetSellValues 57 · PetDisplayNames 66 · PanelMetrics 289 · PanelMetricsTest 331 · MusicManager 158 · HapticUtil 43 · PortalFXShared 117 · MutationColors 45. Plus `Shared` (Promise, Module3D), `topbarplus`, `Jetpack` (JetpackService, JetpackController), `Rat.AIScript` 317.

### StarterPlayer.StarterPlayerScripts (51 LocalScripts)

Client 52 · CucumberVendorClient 1264 · ShopVendorClient 250 · VendorHeadTrack 121 · BreakablesClient 2569 · NukeClient 244 · UpgraderBoardClient 154 · FriendBoostClient 383 · FavoritePromptClient 36 · BossBarClient 538 · GroupOfferClient 248 · RebirthArrowClient 88 · HudScaler 60 · TutorialClient 1194 · DoorArrowClient 297 · PerformanceClient 129 · RingBeamSpinnerClient 53 · JetpackClient 140 · StarterPortalClient 380 · SnowPortalClient 264 · LavaPortalClient 252 · DesertPortalClient 373 · VoidPortalClient 171 · MinigameMusicController 66 · MinigameCompletionClient 92 · MinigameHudController 237 · PlaytimeReadyClient 119 · HoverboardPresentationClient 192 · UIPreloaderClient 211 · ShardsGodClient 217 · PortalArrowClient 306 · MinigameIsolationClient 160 · BackpackHotbarDisable 45 · BossMotionClient 261 · PortalUnlockClient 105 · LikePromptClient 299 · OfflineEarnsBannerClient 165 · VaultFXClient 751 · PanelMetricsWatchdog 90 · SmashEventClient 289 · TopbarSettingsButtonClient 84 · CarryClient 515 · VaultTextClient 249 · CarryShowcaseClient 470 · StreamTierClient 183 · BossTrophyChatClient 33 · QuestBoardClient 291 · HideOwnTagClient 28 · HeistCombatClient 164 · CarryVaultTrailClient 310 · MessageHandler 14. (The six disabled scripts that used to sit here were deleted on 2026-09-01.) StarterCharacterScripts: chat tips LocalScript 24.

### StarterGui scripts

ChatCustomization 13 · PromotedPets.PromoteHandler 131 · HallOfGreen.Controller 20 · CucumberVendorUI.NewPetSellController 249 · SelectingReward.SelectingRewardClient 386 · HUD.TopStatusLayout 357 · HUD.ButtonBarMenu 205 · GamepassPopup.PopupController 248 · AdminPanel.AdminPanelClient 321 · BiomeActivityPrompt.BiomeActivityPromptClient 296 · Evolving grid LocalScript 31. ReplicatedFirst: LoadingBootstrap 82.

## 27. Player attributes and replicated values

**Replicated instance tree per player:** `leaderstats` (Rebirths number, Coins string, Cukes string), `RawStats` (Coins, Cukes numbers), `PlayerData` (DoneTutorial, Scale, Doors.OwnedString, FastHatch, AutoTarget, Pickaxes.Owned/Equipped/BuyAmount, Pets.Equipped/MaxEquipped/Inventory/MaxInventory/Unlocked/Multi1/Multi2/Damage, Upgrades.<name> IntValues).

**Player attributes (server-set unless noted):** `CurrentBiome` (last zone hit, never cleared), `InitialAreaTeleportComplete`, `TutorialStep`, `ForceTutorialOnJoin`, `IntroCutsceneDecided` / `IntroCutsceneActive` (client), `TutorialCarryPending`, `TutorialUpgradeCukesGranted`, `CarryingCucumber`, `CarryingCucumberValue`, `CarryingStolen`, `StealCombat`, `VaultStallId`, `VaultLeverPulls`, `VaultUpgrades`, `QuestState` (JSON), `OwnsSprint` / `SprintEnabled`, `OwnsJetpack` / `JetpackEnabled`, `OwnsAutofarm` / `AutoFarmEnabled`, `Hoverboarding`, `SuperStrengthActive`, `SuperStrengthBaseScale`, `PlayerEventZone` (sticky zone), `InGroupFrenzy`, `GroupOfferPing`, `FavoritePromptAllowed`, `IsGameAdmin`, `StreamTier` / `StreamTierWhy`, `InStarterObby` / `InSnowAvalanche` / `InLavaRun` / `InDesertHunt` / `InVoidBloxout`, `MinigameKey`, `MinigameRunStart`, `BestTime_<key>`, `MinigameCompletionToken`, `MinigameRewardSecuredToken`, `PendingMinigameRewardAmount`, `PortalTransitionReady`, `LastBossShardEarned`, `CleanResetInProgress`, `LikePromptActive` (client), `SmashScore_<zone>` (client).

**Workspace/ReplicatedStorage state:** `ReplicatedStorage.BossProgress.<zone>` meter attributes (Required, BossActive, BossHP, BossName, EventPhase, EventId, EventDuration), `ReplicatedStorage.QuestTargetModels`, `workspace.Breakables.<zone>`, `workspace.CucumberBank`, `workspace.PlayerObbies` and the other minigame instance folders, `workspace.NukeEffects`.

## 28. Dormant, disabled and orphaned systems

The 2026-09-01 cleanup deleted everything that had been sitting here as disabled or orphaned: the intro cutscene client, the path-picker service, the map pickup service, the whole walk-over orb system, the Teleport panel, the six disabled client scripts, the PostTutorialQuests gui, the podium sign template and every in-Studio backup folder. The full list with evidence and restore steps is `backups/Cleanup_2026-09-01/MANIFEST.md`. What remains dormant:

| Item | State | Notes |
|---|---|---|
| Seasons / Hall of Green | built, `SEASON_ENABLED = false` | placeholder text in the hall; season pets have no live grant path |
| Diamond Gherkin | in the dictionary and models, no grant path | reserved for a future reward |
| Starter Pack product | server handlers and product entry exist, no client sells it | the timed popup client was deleted; add a card to Offers if the pack should return |
| `VaultLoot` / `VaultService.Skim` | draft field, function never implemented | CurrencyHandler's call is guarded |
| `Multi2` pet stat | still in the live dictionary and UI ("cash" side of the tooltip) | only affects direct coin drops; replaced by WalkSpeed on the dev save |
| Gamepass bypass ids | three user ids own every pass | review before any economy relaunch |
| 8 vault stalls vs 60 max players | players 9+ get no vault | |
| Quest coin floor of 500 | pays even with an empty vault | tiny |
| VOID in the admin mutation cycler | missing | cannot be force-spawned from the panel |
| Evolving UI cost label | none | cost is server-enforced only |

## 29. Dev-save work that is NOT on the live place

The project has a second, canonical dev save: **"collect cucumber game 8/25"**, place `135680492327917`, universe `10513208747` (not group-owned, so Robux products cannot be created against it). Work done there on 2026-09-01 has **not** reached the live place as read for this document:

1. **Pet walkspeed boosts.** `Multi2` replaced by a per-pet `WalkSpeed` stat (Basic 9 to Narmek 60, Cosmic Colossus 66); `Upgrades.setWalkSpeed` adds the equipped sum to the base 29 only while the `InBiome` attribute is true (biomes only, not the lobby, bank or minigames), with a Heartbeat gate in `BreakablesService.RefreshBiomeWalkSpeedGate`, `CheckGamepassCached` in the hot path, and `UpgradeService.PrimeSprintCache`. Pet tooltips show "+N" speed. Backup `ServerStorage.PetSpeedBackup_2026_09_01`.
2. **BUY / BIOME / SELL pills deleted; boss bar moved into the top-centre slot.** `HUD.TopStatus` becomes an empty layout anchor (it must never be destroyed: TopStatusLayout, CarryClient and TutorialClient wait for it), the boss bar shrinks 25% and lifts into the transparent topbar band when it fits, and hides upward. Tutorial step 4 routes to the shopkeeper instead of the BUY pill.
3. **Product pet remake.** Red Demon, Purple Hydra and Heavenly Angel rebuilt in Blender in the house low-poly style (`pets-remake/` in this repo), delivered through `ReplicatedStorage.Modules.PetRuntimeMesh` + `PetRuntimeMeshClient` with runtime EditableMesh (needs Game Settings → Security → "Allow Mesh & Image APIs", otherwise a fallback clones the old MeshParts). Backup `ServerStorage.__ProductPetsBackup_2026_09_01`.

On the live place, `Dictionaries.Pets` still has `Multi2`, the pills still exist, the boss bar still stacks above the bottom button bar, and the product pets are the toolbox-mesh originals. Conversely the live place has work the older notes do not describe: 8 stalls (was 12), lock time 75 s + 15 s per rebirth (was a flat 3:00), the paid Break Into Base product and prompt, heist combat with real HP, vault time-skip products with live ids, the reordered vault-first tutorial, and door lock models (backup `DoorLockModelBackup_2026_08_30`). Confirm which save you are editing before porting either way.

## 30. Backups and revert points

**In this repo:** `backups/Cleanup_2026-09-01/` (four rbxm exports of everything removed from the place on 2026-09-01, pre-edit copies of the five edited scripts, and `MANIFEST.md` with restore steps), `backups/EconomyRedesign_2026-08-28/` (full rbxm exports of ServerController, all services, Workspace, plus 106 pre-redesign `.lua` dumps and baseline values), `backups/CucumberBank_v1/v2_backup_2026-08-26.rbxm`, `backups/LobbyArea1_backup_2026-08-25.rbxm`, `backups/misc/petsim99_destroy_vfx.rbxm`, `economy-redesign-2026-08-28/` (REDESIGN-REPORT.md, final-design.json, audits, simulator), `HANDOVER-cucumber-vault-bank.md`, `SFX-PROPOSAL-cucumber.md`, `pets-remake/`.

**In ServerStorage (live place):** none. Every in-Studio backup folder was exported to `backups/Cleanup_2026-09-01/` and deleted on 2026-09-01; keep it that way and put future safety copies in this repo instead. Roblox cloud version history is the nuclear option.

## 31. Rules to keep when adding features

1. **Read and write `RawStats`, never `leaderstats`,** for Cukes and Coins. Route every grant through `CurrencyHandler.AddCurrency`; pass `WasPurchase` for flat purchases and `MultipliersApplied` for amounts that are already final but should still count toward seasons.
2. **BreakablesService and VaultService are at the 200-local limit.** New state goes in function scope, as table fields, or as function fields on the module (`BreakablesService.FormatHP` style).
3. **Any rate-formula change in `CarryService.EarnRateOf` must bump the `RateV` stamp** in GiveCarry and LoadVault so saved records recompute.
4. **Keep mirrored constants in sync:** `MUTATION_CHANCE` with the per-mutation chances; `GOLDEN_REWARD_MULT` with `MUTATIONS.GoldenRewardMult`; `MutationColors` with the mutation tables; `TimeSkipRateService.ZONE_EXCLUSIVE_MIX` with `ZONE_EXCLUSIVE_TYPES`; the `{1, 15, 100}` board ladder in UpgradeService and UpgraderBoardClient; the minigame attribute list across Jetpack, Hoverboard, Carry, Sprint and HUD scripts; the client HP/damage mirrors in DoorArrowClient and RebirthArrowClient (both must read Coins, not Cukes, for affordability).
5. **The bank is destroyed and rebuilt on every relayout.** Never cache bank instances; re-resolve from `workspace.CucumberBank` at use time. Add any new podium attachment to `StripPodiumAttachments`.
6. **Setting a `.Value` on a replicated stat persists instantly.** Restore test writes before stopping a playtest.
7. **Grants that "top up to X" must never fire in a session that already paid the normal grant.**
8. **World-anchored per-player UI must survive streaming:** rebind on ChildAdded/Removed and never leave a BillboardGui enabled with a nil adornee.
9. **A UI that must reach the physical screen edge needs both `IgnoreGuiInset = true` and `ClipToDeviceSafeArea = false`.** Only one UIScale per element is honoured. `AbsolutePosition` is inset-space even on IgnoreGuiInset guis; `WorldToViewportPoint` and mouse positions are render-space (add `GuiService:GetGuiInset()`).
10. **Never destroy `HUD.TopStatus` or `HUD.TopStatus["Group 280"]`;** three scripts wait on them.
11. **Playtest evaluation caveats:** each `execute_luau` eval requires a fresh module chain, so drive live server code through the game's own remotes and workspace-attribute dev hooks; script edits do not reach an already-running playtest; keep client evals under about 20 s.
12. **Edits land in the open Studio session.** Save or publish in Studio, and note which place you edited.
