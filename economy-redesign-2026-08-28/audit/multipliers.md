# Economy Multiplier Audit — Collect a Cucumber (2026-08-28)

Sources: `backups/EconomyRedesign_2026-08-28/scripts/` (file:line refs below are within that dir).

## 1. Currencies

| Id (save key) | Leaderstat | Storage | Notes |
|---|---|---|---|
| `Cucumbers` | **Cukes** | NumberValue (double) | Renamed display 2026-07-30; id/save key unchanged (CurrencyHandler.lua:22-28) |
| `Coins` | Coins | NumberValue (double) | InstanceValues.lua:33-36; leaderstats→profile mirror on `.Changed` |
| Boss shards | (none) | `profile.BossShards[zone]` | 10 forge a boss pet, spent on forge (BreakablesService.lua:1026-1045) |

"Orbs" is legacy naming only (code var for the Cukes stat; Leaderboards__Orbs = cucumber board). No third earnable leaderstat currency exists.

## 2. AddCurrency flow (CurrencyHandler.lua)

`AddCurrency({Player, Currency, Amount, HasTotal, WasPurchase, MultipliersApplied, Hide}) -> finalAmount` (lines 105-179).

1. `Amount = GetMulipliers(InfoTable)` (line 112; **the typo is the canonical API name** — callers in TimeSkipRateService:288/303, VaultTimeSkipService:49, BreakablesService:3911 all spell it `GetMulipliers`).
2. `GetMulipliers` (66-103) returns `Amount` **unchanged** when `WasPurchase` **or** `MultipliersApplied` (line 72). Otherwise applies the per-currency stack (§3) and rounds with `NumberController.RoundNumber(Amount, 1)` = `math.round` to a whole number (line 102; NumberController.lua:15-20).
3. Mirrors into leaderstats: `Cukes.Value += Amount` / `Coins.Value += Amount` (120-134). Persistence is via the leaderstats→profile `.Changed` mirror (InstanceValues.lua:50-58).
4. If **not** `WasPurchase` (140-156): `SeasonService.AddSeasonStat` (post-multiplier amount), `OfflineService.NoteEarnings` (**no-op stub**, OfflineService.lua:40-42), `VaultService.Skim` (guarded — function doesn't exist yet, draft).
   - Note the asymmetry: `MultipliersApplied` grants **do** count toward seasons; `WasPurchase` grants don't.
5. `Indicate` client popup unless `Hide` or `Amount <= 0` (158-160); per-minute aggregated AnalyticsService Source event (34-64, 162-169); `HasTotal` → `Total<Currency>` in `TotalStats` (171-173).

**Caps / overflow:** none anywhere. Both currencies are NumberValues (IEEE doubles) — integer precision is lost above 2^53 (~9.0e15); `+=` past that silently drops increments. No negative floor either: `RemoveCurrency` (181-206) subtracts unconditionally (callers must `CheckIfEnough` first, 233-251; leaderstats is the source of truth).

**Silent-drop guard:** if `leaderstats` or `PlayerData` is missing (early join), the grant does nothing and still returns the multiplied amount (115-119).

## 3. Multiplier stacks (all multiplicative, applied in this order)

### Cucumbers (CurrencyHandler.lua:79-93)

```
final = round( base
  × (1 + 0.5 × Rebirths)          -- RebirthService.Multiplier, cap 50 → ×1..×26   (:77,80; RebirthService.lua:17,175-180)
  × 2 if "2x Cucumbers" gamepass  -- id 1902852565, CheckGamepassCached            (:81-83)
  × Pets.Multi1.Value             -- 1 + Σ equipped pets' Multi1                   (:84; EquipService.lua:45-58)
  × 2 if "2x Cucumbers" boost     -- BoostHandler.ValidateBoosts                   (:85-87)
  × 1.5 if InGroupFrenzy          -- group 14583228, cached attribute              (:88-93)
)
```

### Coins (CurrencyHandler.lua:94-100)

```
final = round( base × (1 + 0.5 × Rebirths) )   -- rebirth ONLY, by design ("Rebirth is THE sell-value lever")
```

Pet coin stat **Multi2** is applied *outside* AddCurrency, only on direct coin drops in `Break()`:
`coins = BonusCoins × zoneMulti × damageShare × Multi2` → then AddCurrency applies rebirth on top (BreakablesService.lua:1127-1134).

### Base-value multipliers (before the personal stack)

- Zone economy `Orb × Multi` (Dictionaries__Doors.lua:29-239): Spawn 1×1 → zone2 2×1.5 → 2.5×2 → 3×2.5 → 3.5×3 → 5×4 → 6×5 → Narmek 7×6 (**×42**). Applied at BreakablesService.lua:1065-1067 and CollectionService.lua:178.
- Boss ×6 per-HP (BreakablesService.lua:1070-1072; escapes pay the same, 3901-3913).
- Daily mutation ×25, PRISMATIC ×100, lightning ×rolled bolt multiplier (1074-1103).
- Friend boost: +10%/friend in server, cap 5 (×1.5) — **pickaxe damage**, not currency (1503-1558); intentionally excluded from time-skip/offline quotes (TimeSkipRateService.lua:216-218).

### Pet Multi1 arithmetic

`Pets.Multi1` starts at **1** (InstanceValues.lua:142-145); each equip **adds** the pet's Multi1, unequip subtracts (EquipService.lua:45-58). Equip slots: `4 base + board level (max +3, MAX_PET_EQUIPS=7) + legacy dev product (+2 each, capped +6) + gamepass +4` → **17 max** (Dictionaries__Upgrades.lua:8,57-81; ProductHandler.lua:164-175). Golden-evolved pets get Multi1 ×1.5 (PetDefaults.lua:82; PetService.lua:217-228).

Pet Multi1 bands: egg pets 1→6.6; Robux pets Red Demon 25, Purple Hydra 30, Heavenly Angel 30 (Dictionaries__Pets.lua:704-746); reward pets Blazing Pickle 8, King Cuke 15 (1063,1071); boss pets 6→24 (771-874); Gregory 12; season pets Golden Cucumber 8.2 / Solid Gold Coin 4.4 / Silver Pickle 2.2 (903-976).

### Range estimates

| Profile | Cucumbers | Coins |
|---|---|---|
| Fresh player | ×1 | ×1 |
| Free ceiling | ~×9,000–13,500 (26 × [1+~114 free pets, 7 slots] × 2 boost × 1.5 group) | ×26 |
| Whale realistic | ~×45,000 (26 × 2 × ~287 [17 slots incl. 3×30 Robux pets] × 2 × 1.5) | ×26 (+Multi2 on drops) |
| Whale theoretical | ~×119,500 (Multi1 = 1+17×45 golden = 766) | ×26 |

## 4. Gamepasses (ProductController.lua:30-141)

| Pass | Id | Economy effect |
|---|---|---|
| 2x Cucumbers | 1902852565 | ×2 cucumber income (the only direct income pass) |
| Sprint | 1899183262 | 2× walkspeed |
| Autofarm | 1919162313 | AFK auto-strike farming (indirect income) |
| Jetpack | 1919180303 | mobility |
| Auto Egg Hatch | 1898883147 | QoL |
| Triple Egg Hatch | 1903566581 | 3 eggs/hatch |
| Instant Egg Hatch | 1911700950 | QoL |
| +75 Pet Storage | 1899609194 | MaxInventory +75 |
| +4 Pet Slots | 1903134517 | +4 equips → more Multi1 |

Detection: `CheckGamepass` (UserOwnsGamePassAsync) with `CheckGamepassCached` on hot paths — **pessimistic false** until the async check resolves (ProductController.lua:304-330); cache invalidated on purchase. **Bypass list** grants user ids 1, 1660029941, 1196256323 every pass (24-28).

## 5. Robux dev products (ProductController.lua:143-261; receipts in ProductHandler.lua)

Boosts: 15m/1h/5h of 2x Cucumbers — 3609774448 / 3609774551 / 3609774625 (duration adds to remaining).
Pets: Red Demon 3609774225, Purple Hydra 3609774320, Heavenly Angel 3609773882.
Starter Pack 3609836817: 20,000 Coins **flat** + Red Demon; one-time (ProductHandler.lua:87-116).
+10 Pet Inventory 3609836686; +2 Pets Equip 3609836815 (cap +6 total).
Time Skips (cucumbers, quote = fully-multiplied rate × seconds, granted flat): 1m 3609921759, 5m 3609921779, 30m 3609921799, 5h 3609921818, **1d 3609921841, 1wk 3609921920**.
Vault Time Skips (coins): 6 durations, **all Id 0 placeholders** — skipped until dashboard products exist.
Skip Boss/Event Requirement 3709040752; Unlock Portal Now! 3709119039.
**Nuke Server 3610280695**: purchaser is credited 100% damage on *every* live breakable → full multiplied payout for the whole field (NukeService.lua:12,386; BreakablesService.lua:1324-1349).
Robux prices are not in source (dashboard-side).

### Time-skip rate model (TimeSkipRateService.lua)

Deterministic expected cukes/sec from the highest unlocked zone's spawn mixture (pickaxe tick 0.25s + pet tick 0.6s, 10% crit ×5, lines 15-18, 245-271), then **× the full cucumber multiplier stack once** (288-293); `Grant` awards flat with `WasPurchase` (327-337). VaultTimeSkipService mirrors this for coins: Σ stored-cucumber `EffectiveRate` × coin multipliers once (VaultTimeSkipService.lua:30-59).

## 6. Offline earnings (OfflineService.lua)

- Pays **Cucumbers** into `OfflineData.Vault`; `ClaimVault` grants flat (`WasPurchase`, line 80-93).
- Tiers **verified**: 50% of the first **6h** away; then 30% until **6h of full-rate income** is banked ⇒ second tier spans 10h; wall-clock cap **16h** away (lines 14-27: `SECOND_TIER_SECONDS = ceil((21600−10800)/0.3) = 36000`).
- Minimum absence 120s; session must run 60s before its rate is trusted; checkpoint every 30s (27-29, 54-70).
- Rate is **pet-only** (`GetPetRate`) and **includes all cucumber multipliers at checkpoint time** (63-66; TimeSkipRateService.lua:300-308). No pets equipped ⇒ 0 offline income.

## 7. Playtime rewards (PlaytimeRewards.lua:40-50, 137-199)

| # | Time | Reward |
|---|---|---|
| 1 | 30s | 2,500 Coins flat (`MultipliersApplied`) |
| 2 | 2m | 1 Food Cuke Egg |
| 3 | 5m | 10 min 2x Cucumbers boost |
| 4 | 10m | 15-min time skip (flat, pre-multiplied quote) |
| 5 | 18m | 3 Food Cuke Eggs |
| 6 | 30m | **Blazing Pickle** (Multi1/Multi2 8, Dmg 100) |
| 7 | 45m | **+1 FREE rebirth** (permanent +50%, no cost/reset) |
| 8 | 1h | 2-hour time skip |
| 9 | 1h30m | **King Cuke** (Multi1/Multi2 15, Dmg 300) |

Post-tutorial session time only; **whole ladder resets every rejoin** (lines 9-13, 211-214).

## 8. Chests (Dictionaries__Chests.lua:17-96; ChestHandler.lua)

All flat Coins (`WasPurchase`, ChestHandler.lua:33-37), per-player 12h (43200s) cooldown persisted in `profile.Chests`:

| Chest | Coins | Gate |
|---|---|---|
| Daily | 500 | — |
| Group | 1,000 | group 14583228 (touch refreshes `InGroupFrenzy`; non-members get join prompt, ChestHandler.lua:148-166) |
| Treasure | 1,500 | — |
| Samurai | 4,000 | — |
| Snow | 10,000 | — |
| Volcano | 15,000 | — |

## 9. Season pass (SeasonService.lua)

**Disabled** (`SEASON_ENABLED = false`, line 16). Weekly (epoch 1783296000). "XP" = post-multiplier Cucumbers and Coins earned via non-`WasPurchase` AddCurrency (76-84). Rewards on finalize (24-28, 159-196): Cucumbers #1 → **Golden Cucumber** (8.2×) + permanent crown/aura; Coins #1 → **Solid Gold Coin** (4.4×); Cucumbers top-10 → **Silver Pickle** (2.2×). No direct income multiplier; only the pets.

## 10. Goals / Streaks

- GoalService (17-23, 63-87): 5 sequential goals paying flat Coins 200 / 400 / 600 / 1,000 / 2,000 (`WasPurchase`, `HasTotal=false`).
- StreakService (15, 31-45): daily-login Coins 300/500/800/1,200/1,800/2,600/4,000 (day 7 repeats; miss ⇒ reset). Flat.

## 11. Everything else that grants currency

| Source | Payout | Multiplied? | Ref |
|---|---|---|---|
| Breakable smash | Reward × zone(Orb×Multi) [×6 boss ×25 mut ×100 prismatic ×N lightning] × dmg share | **Full cuke stack** | BreakablesService.lua:1065-1123 |
| Direct coin drops | BonusCoins × zoneMulti × share × **Multi2** | + rebirth | 1127-1134 |
| Boss escape | 6× per-HP to every damager | Full stack | 3901-3913 |
| Boss pickup chunks | 500 base Cukes/Coins per chunk | **Full stack** | 3187, 3208-3214 |
| Collection orbs | zone Orb×Multi cukes | Full stack | CollectionService.lua:177-180 |
| Sell all Cukes | Cukes→Coins 1:1 | × rebirth | SellVendorServer.lua:70-90 |
| Carried-cuke sale | EffectiveRate × 250 coins | flat | SellVendorServer.lua:105-151 |
| Pet selling | PetSellValues per pet | flat | SellVendorServer.lua:170-290 |
| Vault collect pads | accrued coins/sec (rate × 1.18^(lvl−1), FROZEN ×0.8) | flat (`MultipliersApplied`, still season-tracked) | VaultService.lua:1647-1682; CarryService.lua:417-428 |
| Quest board (3/6h) | 1/3/5/10-min skip: cukes + coins (min 500) | flat (pre-multiplied quotes) | QuestBoardService.lua:40-46, 130-139 |
| Minigame spinner | 2/5/15/30-min production cards, vault coin cards, shards | flat | MinigameCompletionService.lua:55-150 |
| SMASH podium | winner spinner; runner-up 5-min production | flat | SmashEventService.lua:54-99 |
| Pet index | 500 × milestone# per 5 discoveries | flat | IndexService.lua:14-15, 61-74 |
| Tutorial top-up | one-time cukes = cheapest vault upgrade cost | flat | TutorialProgressServer.lua:131-155 |

Vault stored-cuke earn rate roll-up (CarryService.lua:76-88): base 1–5 by in-biome rarity × 1.6^(biomeTier−1) × golden 3 × diamond 8 × mutation 5 (PRISMATIC 20) × charged 4; boss trophies base 8 × 1.6^(tier−1) (374-405).

## 12. Quirks / bugs / risks

1. **Infinite session-reset rewards** (PlaytimeRewards.lua:9-13, 211-214): the free rebirth (#7) and both exclusive pets (#6/#9) re-earn every rejoin. 45 min/session × 50 sessions maxes rebirths (×26 income) for free; duplicate King Cukes/Blazing Pickles flood the trade economy (TradeService exists).
2. **Rebirth double-dip on the farm→sell loop**: cucumbers earned ×R, then selling those cukes ×R again ⇒ effective R² (×676 at cap) on the core loop. Deliberate per comments (CurrencyHandler.lua:96-99) but the strongest compounding lever in the game.
3. **Same-name ×4**: "2x Cucumbers" gamepass and boost stack multiplicatively (CurrencyHandler.lua:81-87).
4. **ValidateBoosts nil crash** (BoostHandler.lua:58): `Boosts[BoostName] > 0` throws if the key is absent from the profile; it is called un-pcall'd on every cucumber grant (CurrencyHandler.lua:85).
5. **Boss pickup chunks fully multiplied** (BreakablesService.lua:3208-3214): 500-base chunks run the whole personal stack — at whale multipliers a single chunk pays tens of millions; likely meant to be flat like chests.
6. **Time skips snapshot temporary multipliers** (TimeSkipRateService.lua:288-293, 310-337): buying the 1-week skip while the 2x boost / group ×1.5 are active bakes them into 604,800s of income. Same for the offline rate checkpoint (OfflineService.lua:63-66) — a boost active at the last checkpoint pays for the entire absence.
7. **No caps or overflow guards anywhere**: NumberValue doubles lose integer precision above 2^53; week-skips × ~10^5 multipliers × Narmek base rates make this reachable. `RemoveCurrency` has no floor (negative balances possible on any caller bug).
8. **Gamepass Bypass list** (ProductController.lua:24-28): user ids 1, 1660029941, 1196256323 own every pass — remove/verify before economy relaunch.
9. **Season accrual counts post-multiplier income** and includes `MultipliersApplied` grants but not `WasPurchase` ones (CurrencyHandler.lua:140-144) — the (disabled) leaderboard measures multiplier stacks more than activity, and vault-pad coins count while chests/streaks don't.
10. **CheckGamepassCached pessimistic-false** (ProductController.lua:308-319): the first cucumber grant(s) after join miss the paid ×2 until the async check lands.
11. **Nuke Server product** (3610280695): full-field payout at full multipliers; in a busy Narmek server this is an enormous single-purchase cucumber injection (NukeService.lua:386; BreakablesService.lua:1324-1349).
12. **OfflineService.NoteEarnings is a dead stub** (OfflineService.lua:40-42) and `VaultService.Skim` doesn't exist (guarded, CurrencyHandler.lua:149-155) — both are silent no-ops in the AddCurrency fan-out.
13. Cosmetic: StreakService notif format strings pass extra/unused args (StreakService.lua:50-53); `GetMulipliers` typo is load-bearing across 5 files — renaming it breaks TimeSkipRateService, VaultTimeSkipService, BreakablesService.
