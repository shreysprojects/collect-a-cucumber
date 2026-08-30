# Economy Audit — Progression Systems (2026-08-28)

Source dump: `backups/EconomyRedesign_2026-08-28/scripts/`. All refs are `file:line` in that dump.
Currencies: **Cucumbers** (leaderstat displayed as `Cukes`) and **Coins**. Machine-readable version: `progression.json`.

---

## 1. Doors / Areas

Defined in `Dictionaries__Doors.lua:16-256`. All 8 use **Coins** (Aug 2026 pass).

| Order | Index | Display name | Price (Coins) | Min rebirths | Orbs.Multi | Orbs.Orb |
|---|---|---|---:|---:|---:|---:|
| 1 | Spawn | Spawn | 0 | — | 1 | 1 |
| 2 | Desert | The Wild West | 4,000 | — | 1.5 | 2 |
| 3 | Samurai | Samurai Palace | 30,000 | — | 2 | 2.5 |
| 4 | Farm | The Farm | 1,000,000 | 1 | 2.5 | 3 |
| 5 | Snow | The Arctic | 7,500,000 | 2 | 3 | 3.5 |
| 6 | Underwater | The Ocean | 45,000,000 | 3 | 4 | 5 |
| 7 | Volcano | The Volcano | 250,000,000 | 4 | 5 | 6 |
| 8 | Narmek | The Greenland | 1,500,000,000 | 5 | 6 | 7 |

`Orbs.Multi × Orbs.Orb` is the zone's cucumber value scalar (used both by BreakablesService drops and TimeSkip quotes, `TimeSkipRateService.lua:171-202`). Price history comments (`:53-56`, `:84-86`): Desert was 10k, Samurai was 175k→85k — cut 2026-08-22 to land the first unlock in session one.

**Charge flow** (`DoorService.lua`):
- `HitPart.Touched` → `PromptPurchase` (`:209-233`): rebirth gate checked *before* the prompt (`:221-226`), then client `PromptDoor` UI (`UserInterfaceLoader__Door.lua:137-157`).
- Client fires `PurchaseDoor` → `DoorService.PurchaseDoor` (`:131-207`): re-checks rebirth gate (`:150-153`), `CurrencyHandler.CheckIfEnough` (`:156`), `RemoveCurrency` with sku `Door:<name>` (`:174`), appends to the `DoorData` " # "-separated string and the live `Doors.OwnedString` mirror.
- **Backfill:** buying a later door free-unlocks every earlier door (`:163-171`); a join-time pass also self-heals older saves (`:64-83`). Analytics `ZoneProgression` funnel steps at `:180-186`.
- Join spawn: finished-tutorial players spawn at their vault stall, else the furthest owned biome's pad (`:30-129`).

## 2. Rebirth

`RebirthService.lua`. Config `:15-18`:

- **Cost:** `100,000 × 3.5^R` **Coins** (`CostOf :27-29`; charged in Coins since 2026-08-26, `:44-46` — the `BASE_COST` comment still says "cucumbers", stale).
  R0→100k, R1→350k, R2→1.23M, R3→4.29M, R4→15M, R5→52.5M, R6→184M, R7→643M, R8→2.25B, R10→27.6B … R49→~4.6e31 (see quirks).
- **MAX_REBIRTHS = 50** (`:18`), hard-checked in both paid (`:39-42`) and free (`:147-150`) paths.
- **Resets** (exactly three things, `:55-84`): Cucumbers→0, Coins→0, `DoorData`→"Spawn" (+ live mirror `:90-94`), then respawn at Spawn (`:126`).
- **Persists:** pickaxes (owned/equipped/BuyAmount — explicitly not reset since 2026-08-05, `:59-65`), pets (unequip→re-equip dance `:96-114`, `:128-137`), board upgrades, boss shards, vault contents, quests, walkspeed.
- **Bonus:** `BONUS_PER_REBIRTH = 0.5` → `Multiplier = 1 + 0.5R` (`:175-180`), applied to **cucumber income and coin income from selling** (`CurrencyHandler.lua:76-99`). Also **+1 vault slot per rebirth**: capacity `6 + R (cap 50) + Vault-slots upgrade (max 3)` = max 59; new floor every 10 slots — floor 2 @ R5, 3 @ R15, 4 @ R25, 5 @ R35, 6 @ R45 (`BankBuilder.lua:9-12, 69-75`). Trading unlocks at R1 (`TradeService.lua:20`); doors Farm→Narmek gate at R1→R5.
- **Free rebirth:** `GrantFree` (`:143-173`, playtime reward) — +1 rebirth, no cost, no reset.
- **`GetRebirthInfo` payload** (`:223-256`): `Rebirths, Bonus(=50R%), NextBonus, Cost, Coins, CanAfford, MaxRebirths, AtMax, VaultSlots, NextVaultSlots, VaultFloors, NextVaultFloors`. Rendered by `RebirthNewFrame.lua:46-72` ("CUCUMBERS & SELL VALUE +N%", vault slot/floor callouts, double-click confirm `:273-288`).

## 3. Pickaxes

`Dictionaries__Pickaxes.lua:36-306`. 19 tiers, all priced in **Coins**; damage feeds combat and TimeSkip quotes alike (`TimeSkipRateService.lua:219-228` reads `PlayerData.Pickaxes.Equipped` → dictionary `Stats.Damage`, default 4).

| # | Name | Price | Dmg | Range | | # | Name | Price | Dmg | Range |
|---|---|---:|---:|---:|---|---|---|---:|---:|---:|
| 0 | Wood | 0 | 4 | 6 | | 10 | Valentine | 4M | 133 | 16 |
| 1 | Stone | 500 | 5 | 7 | | 11 | Magma | 10M | 189 | 17 |
| 2 | Bronze | 2K | 8 | 8 | | 12 | VoidNeon | 25M | 268 | 18 |
| 3 | Iron | 6K | 11 | 9 | | 13 | CosmicIce | 60M | 381 | 19 |
| 4 | Steel | 15K | 16 | 10 | | 14 | YinYang | 150M | 542 | 20 |
| 5 | Gold | 40K | 23 | 11 | | 15 | Galaxy | 400M | 769 | 21 |
| 6 | Emerald | 100K | 32 | 12 | | 16 | SolarFlare | 1B | 1093 | 22 |
| 7 | Ruby | 250K | 46 | 13 | | 17 | BloodMoon | 2.5B | 1550 | 23 |
| 8 | Amethyst | 600K | 66 | 14 | | 18 | Rainbow | 6B | 2200 | 24 |
| 9 | Diamond | 1.5M | 93 | 15 | | | | | | |

Price steps run ~2.4–2.7×, damage ~1.4×. **Gating is purely sequential**, not zone-based: buyable only while `Order <= ToolData.BuyAmount` (`PickaxeService.lua:113`); `BuyAmount` starts at 1 and increments per purchase (`:133-135`). The shop UI (`Shop__Pickaxes.lua`) derives cards straight from the dictionary, `LayoutOrder = Order` (`:269`), and swaps to the Locked state frame past `BuyAmount` (`:251-258`). Purchase/equip is one server function (`PickaxeService.FunctionButton :85-155`); `CharacterJoined` re-grants the saved equipped pickaxe every respawn and self-heals Equipped∉Owned desyncs back to Wood Pickaxe (`:157-196`).

**"Gift pickaxe":** none — `PickaxeShopGiftServer.lua` is a one-time **500 Coins** tutorial gift at the shop (`:23`, `:73-95`), with a once-per-session top-up back to 500 on tutorial replays (`:78-93`), range- and flag-guarded.

## 4. Board upgrades

`Dictionaries__Upgrades.lua:87-144`; purchase in `UpgradeService.lua:43-79`. All **Coins**. Price formula (`:56`): `RoundNumber(Base + Base×level×Increment, 100)`.

| Upgrade | Base | Incr | Max | Level prices | Effect |
|---|---:|---:|---:|---|---|
| Vault slots | 150,000 | 1.0 | 3 | 150k / 300k / 450k | +1 vault podium each (stacks on 6+R capacity) |
| Pet equips | 30,000 | 0.6 | 3 | 30k / 48k / 66k | +1 equip slot each (base 4 → 7; +4 gamepass & legacy stack above the cap, `:47-82`) |
| Smashes required | 25,000 | 0.45 | 3 | 25k / ~36.3k / 47.5k | −3 portal smash requirement each (max −9; portals only, `PortalCucumberProgress.lua:133-145`) |

Retired: *Faster walkspeed* (flat 29 base now) and *Hatch speed* — scrubbed from saves on join (`UpgradeService.lua:90-100`). Walkspeed stack (`Dictionaries__Upgrades.lua:10-45`): 29 × 2 (Sprint pass) × 3 (hoverboard) × 2 (Super Strength) ÷ 1.5 (carrying stolen).

## 5. Selling (`SellVendorServer.lua`)

- **SellAll** (`:70-90`): converts the whole `Cukes` leaderstat into Coins **1:1 base**, then `AddCurrency` applies coin multipliers → **effective rate = 1 × (1 + 0.5R)** (rebirth only; pet multi / 2x pass deliberately excluded on the coin side, `CurrencyHandler.lua:94-99`). Zeroes Cucumbers. 1s debounce. There is **no sell gamepass** — rebirth is the only sell lever.
- **SellCarried** (`:105-151`): sells the carried cucumber at `CarryService.ValueOf = floor(EffectiveRate × 250)` where `EffectiveRate = Rate × 1.18^(Level−1)`, ×0.8 if FROZEN (`CarryService.lua:417-429`). Paid via `AddCurrency` **without** flags, so the rebirth coin multiplier applies on top of the displayed green value. 0.5s cooldown.
- **SellPets** (`:170-290`, UI in `NewPetSellController.lua` + pet tab of `CucumberVendorClient.lua`): flat rarity table (`PetSellValues.lua:16-27`) — Common 100, Uncommon 250, Rare 600, Epic 1500 (unused), Legendary 3.5k, Special 5k, Mythical 10k, Omega 25k; Golden ×1.5. Paid with `MultipliersApplied=true` → **no rebirth bonus**. Max 50 per request (client mirrors cap), equipped refused, mid-trade refused, dedupe, absolute `Inventory.Value` recompute to repair drift (`:255-265`).

## 6. Time skips

- **Cucumber rate** — `TimeSkipRateService.lua`: deterministic expected cukes/sec against the **highest unlocked zone's** baseline spawn mixture (15 sliced + 24 weighted slots; per-zone exclusive tables `:58-139`), scaled by `ZONE_HP` (Spawn 1 → Narmek 500, `:21-30`) and the door's `Orb×Multi`; 10% crit ×5; pickaxe tick 0.25s, pet tick 0.6s (pet strike `2 + Σ pet damage`, 0 with no pets). `Quote(sec) = max(1, floor(rate × cucumber-multipliers × sec))` (`:279-314`); `Grant` awards flat (`WasPurchase`, `:327-337`).
- **Vault (coins) rate** — `VaultTimeSkipService.lua:30-80`: coins/sec = Σ `EffectiveRate` of stored vault cucumbers × coin multipliers; empty vault quotes 0 and `Grant` refuses.
- **Products** (`ProductController.lua:222-243`; receipts `ProductHandler.lua:119-150`): cucumber skips 1m/5m/30m/5h/1d/1w = ids 3609921759/…779/…799/…818/…841/…920. **VaultTimeSkips: all `Id = 0` placeholders — not yet purchasable.** Robux prices live on the dashboard only.
- **WalkCucumberService** (`WalkCucumberService.lua`): walk-over "Time Skip" pickups worth a random **10–60s of `Quote()`** to a zone-owning collector; 5 world + 1 per player, 10s respawn. **Disabled** — `MAP_PICKUPS_ENABLED = false` (`:16`, `:294-297`).

## 7. Quests (`QuestBoardService.lua`)

3 quests per board (`:104-128`): **Smash 30–40**, **Chests 3–5**, **Catch 1** specific weight-rolled type from a random *unlocked* biome (PRISMATIC catch = wildcard, `:177-179`). Claim per quest (`:130-139`, `:188-201`, 0.3s debounce): a **dual time skip** whose duration is rolled per quest from `{60,180,300,600}`s — pays `TimeSkipRateService.Grant(sec)` cucumbers **and** `max(VaultTimeSkipService.Quote(sec), 500)` Coins (**500-coin floor pays even with an empty vault**). All three claimed → `ResetAt = now + 6h`; a 15s watcher rerolls once expired (`:253-264`). No player reroll (Studio-only dev hook `:266-292`). State in `UserData.QuestBoard`, replicated as JSON attribute `QuestState`.

## 8. Minigames / portals

Requirements `PortalCucumberProgress.lua:10-16` (per-player, DataStore `PortalCucumberProgress_v1`); smashes count only in the portal's biome, only while off cooldown (e.g. `StarterPortalService.lua:423-427`).

| Portal | Minigame | Counting biome | Smashes | −upgrades (max) | Cooldown |
|---|---|---|---:|---:|---|
| Starter | Classic Obby | Spawn | 18 | 9 | 1h |
| Desert | Wild West Rat Hunt | Desert | 27 | 9 | 1h |
| Snow | Avalanche | Snow | 54 | 9 | 1h |
| Lava | Lava Run | Volcano | 78 | 9 | 1h |
| Void | Bloxout Incorporated | Samurai (physical location) | 90 | 9 | 1h |

Cooldown is a per-portal absolute `os.time()` expiry in its own DataStore, **armed by completion** (not entry, `StarterPortalService.lua:255-266`); smash progress resets when it arms. Paid skip: **"Unlock Portal Now!"** product 3709119039 (`PortalUnlockService.lua`) — a persisted one-use credit per portal that bypasses cooldown *and* smashes, consumed on entry.

**Reward spinner** (`MinigameCompletionService.lua:15-33`, total weight 127): cucumber prizes = `Quote` over 1m(17) 2m(15) 3m(12) 5m(10) 10m(8) 15m(9) 30m(5) 1h(4); coin prizes = vault `Quote` over 2m(10) 5m(8) 15m(6) 30m(3) — empty vault downgrades to the same-duration cucumber card (`:218-227`); shards ×1(9)/×3(4) into the highest-zone boss bucket (10 forge that boss pet); Food Cuke Egg(7) = real hatch. Amounts are **locked at pick time** (`:190-205`) and granted once via token handshake (`:290-306`). `MinigameTimeService.lua` only persists best times (`MinigameBestTimes_v1`) — no economy payout.

**NukeService** (`NukeService.lua`): dev product **3610280695** (Robux; no in-game cost). Missiles hit every `SpawnArea`, kill+return players standing in them, then `BreakablesService.NukeAll(purchaser)` pays **the buyer** the reward of every live breakable (`:348-400`). Queued serially, 2s apart.

## 9. Save schema (compatibility contract)

Profile template `UserData.lua:12-115` — economy-relevant fields and defaults:

| Field | Default | Notes |
|---|---|---|
| `Stats.Cucumbers` / `Stats.Coins` | 0 / 0 | mirrored from leaderstats `.Changed` (`InstanceValues.lua:47-55`) — **leaderstats is the source of truth** |
| `Stats.Radius` | 7 | overwritten by equipped pickaxe range |
| `Stats.DoneTutorial/TutorialStep` | false / 0 | tutorial gating |
| `Stats.PetShopGiftGiven` / `PickaxeShopGiftGiven` | false | one-time 2,500 / 500 Coin gifts |
| `ToolData` | Wood Pickaxe ×3, BuyAmount 1 | " # "-separated Owned string |
| `DoorData` | "Spawn" | " # "-separated door indexes |
| `Boosts/BoostTotals["2x Cucumbers"]` | 0 | boost seconds |
| `PetData` | `{Unlocked=""}` | id→pet tables; `Unlocked` is "\|"-separated discovered names (Index) |
| `Upgrades` | all 0 | Vault slots / Pet equips / Smashes required |
| `Rebirths` | 0 | leaderstat-mirrored |
| `VaultLoot/VaultCucumbers/VaultLastSave` | 0 / {} / 0 | vault podium contents `{Spot,Zone,Name,Rate,Level,Rarity,Mutation,Accrued,OfflineCash}` |
| `IndexClaimed` | 0 | index milestones taken |
| `ColossalShards` → `BossShards` | 0 / {} | legacy pool migrates to `BossShards.Spawn` |
| `QuestBoard` | {} | `{Quests, ResetAt}` |
| `EggPity`, `MaxEquipIncrement`, `MaxPetInventoryIncrement` | 0 | legacy product increments |
| `SeasonStats/ClaimedSeasonRewards/GoldenChampion` | 0s/{}/false | season system |
| `Streak`, `GoalIndex/GoalProgress`, `PlaytimeRewards` | 0s | daily streak, goal chain, playtime ladder |
| `OfflineData` | {LastSeen=0, Rate=0, Vault=0} | offline pet-rate checkpoint (`TimeSkipRateService.GetPetRate`) |

Live instance tree (`InstanceValues.lua:16-177`): leaderstats `{Coins, Cukes, Rebirths}`; `PlayerData` `{DoneTutorial, Scale, Doors.OwnedString, FastHatch, AutoTarget, Pickaxes{Owned,Equipped,BuyAmount}, Pets{Equipped, MaxEquipped = 4+legacy+board(clamped 0..6), Inventory, MaxInventory = 30+incr, Unlocked, Multi1, Multi2, Damage}, Upgrades{IntValues}}`. **Only leaderstats writes back to the profile** — Pickaxes/Doors/Upgrades values must be double-written by services (`RebirthService.lua:86-89`).

Outside the profile (separate DataStores — a redesign must keep or migrate these): `PortalCucumberProgress_v1`, `StarterPortalCooldown_v1` (+Desert/Snow/Lava/Void), `PortalUnlockState_v1`, `MinigameBestTimes_v1`.

## 10. Index & Trade

- **IndexService** (`IndexService.lua:14-16, 47-74`): every 5 discovered pets = 1 milestone; claiming milestone N pays **500 × N Coins** flat (WasPurchase). Unbounded, grows with collection. Also hosts the boss-shard Forge (10 shards → that biome's boss pet, repeatable).
- **TradeService**: pets only, **both sides ≥ 1 rebirth** (`:20`), max 4/side (`:21`), equipped untradeable, every pet re-validated at execution (`:107-113`), selling mid-trade refused (`SellVendorServer.lua:188-191`). Transfers move the pet table by id between live profiles (`:115-142`); `Inventory.Value` is adjusted relatively (`:126-127`) — drift possible in theory, but repaired by SellPets' absolute recompute. **No currency trading and no dupe path found.**

---

## Quirks / bugs / risks

1. **Rebirth double-dip (by design, but the dominant lever):** `1+0.5R` multiplies cucumber earnings *and* the vendor's cuke→coin conversion (`CurrencyHandler.lua:79-99`) → farm-loop coins scale ~`(1+0.5R)²` while all prices are static. At R5 that's ×12.25 income against fixed prices; door/pickaxe pacing collapses in the late-mid game.
2. **MAX_REBIRTHS 50 unreachable:** cost 100k×3.5^R hits 27.6B at R10 and ~4.6e31 at R49. Vault floors 5–6 (R35/R45) and the 50-cap are effectively decorative; either the growth (3.5) or the cap needs to move in the redesign.
3. **Starter portal progress wipe on join (likely bug):** `StarterPortalService.lua:118` calls `PortalProgress.Reset` inside `loadCooldown` (every join); the other four portals reset only inside `startCooldown` (completion — e.g. `SnowPortalService.lua:125`). Starter's 18-smash progress never survives a rejoin despite the persistent store.
4. **Door backfill = area skip:** any later door grants all earlier doors free (`DoorService.lua:163-171`). With rebirth gates the max skip is bounded (e.g. save 4k+30k by jumping straight to Farm at 1M), but any redesign of prices must keep the cascade in mind — the sum of earlier doors must stay << the later door.
5. **SellCarried pays above the displayed value at R>0:** the vault card's green number is flat `ValueOf`, but the payout path adds the rebirth coin multiplier (`SellVendorServer.lua:126` lacks `MultipliersApplied`). Cosmetic-to-minor faucet inflation that scales with R.
6. **Quest coin floor:** every claim pays ≥ 500 Coins even with an empty vault (`QuestBoardService.lua:43,134-136`) — up to 1,500 Coins/6h guaranteed. Tiny now; re-check if coin prices are rebalanced downward.
7. **Time-skip quotes include multipliers:** minigame prizes, quest halves, and the Robux 1-day/1-week skips all scale with rebirth/pet/gamepass/group multipliers (`TimeSkipRateService.lua:283-293`). Deterministic + locked-at-pick prevents spinner-time manipulation, but a 1-week skip at high R is a very large single grant — price the Robux SKUs accordingly.
8. **leaderstats is the persistence hot-wire:** any `.Value` write to Coins/Cukes/Rebirths persists instantly through the `.Changed` mirror (`InstanceValues.lua:47-55`). All faucets/sinks funnel through CurrencyHandler today; keep it that way — direct leaderstat writes (as `PickaxeShopGiftServer.lua:95` does deliberately, to dodge multipliers) are permanent the moment they happen.
9. **Known drift trap already mitigated:** client-reachable `PetService.DeletePet` decrements `Inventory.Value` across a yield → free pet-storage drift; `SellPets` recomputes absolutely to repair it (`SellVendorServer.lua:255-265`). Any new pet-removal path must do the same.
10. **Pet-equips clamp mismatch:** `InstanceValues.lua:125` clamps the board term to 0..6 while the board itself caps at 3 (`Dictionaries__Upgrades.lua:57,114`); harmless until someone raises `MaxUpgrade`.
11. **Dormant systems:** VaultTimeSkips products all `Id=0` (wired, unsellable, `ProductController.lua:236-243`); WalkCucumberService map pickups disabled (`WalkCucumberService.lua:16`); "SellAll" legacy window coexists with the newer carried-sale dialog (`SellVendorServer.lua:98-104`).
