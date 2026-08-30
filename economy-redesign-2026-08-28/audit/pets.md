# Pet & Egg Economy Audit — 2026-08-28

Sources: `backups/EconomyRedesign_2026-08-28/scripts/` (file names below abbreviated; all under that dir).
Companion data file: `pets.json` (same folder).

---

## 1. What pet stats actually DO (end-to-end formula)

Every pet carries three numbers (`Dictionaries__Pets.lua`): `Multi1`, `Damage`, `Multi2`.

### Equip bookkeeping
- `PlayerData.Pets.Multi1` starts at **1**, `Multi2` starts at **1**, `Damage` starts at **0** (`ProfileService__InstanceValues.lua:142-156`).
- Equipping a pet **adds** its stats to those values; unequipping subtracts (`PetService__EquipService.lua:40-64`, `Mulitpliers()`).
- So the player-wide totals are: `TotalMulti1 = 1 + Σ equipped Multi1`, `TotalMulti2 = 1 + Σ equipped Multi2`, `TotalDamage = Σ equipped Damage`.
- Legacy pets without a saved Damage derive `max(1, ceil(Multi1/2))` (`EquipService.lua:51`).

### Where each total enters the economy

**Multi1 → cucumber income (the farm loop).** `CurrencyHandler.GetMulipliers` (`CurrencyHandler.lua:79-93`):

```
Cucumbers granted = base × rebirthMult × (2 if "2x Cucumbers" gamepass)
                    × Pets.Multi1 × (2 if 2x boost active) × (1.5 if group member)
```
Applied to **every** cucumber grant from breaking (`BreakablesService` Break() → `CurrencyHandler.AddCurrency`, split by damage contribution, `BreakablesService.lua:1107-1123`).

**Multi2 → direct coin drops ONLY.** When a breakable with `BonusCoins > 0` dies (`BreakablesService.lua:1127-1133`):

```
coins = max(1, floor(BonusCoins × zoneMulti × damageShare × Pets.Multi2))
```
Multi2 is deliberately **NOT** applied when selling cucumbers at the vendor (`CurrencyHandler.lua:94-100`: "NO pet multi here"). So Multi2 is a niche stat — it only fattens golden/tree/boss direct-drop coins.

**Damage → the pet swarm's DPS (pets are the main damage source).**
- `TimeSkipRateService.GetPetStrike` (`:230-241`): `strike = max(1, 2 + Pets.Damage)`, 0 if no pets equipped.
- Pets auto-swing every **AUTO_TICK = 0.6s** at the committed target while within 10 studs (`BreakablesService.lua:50-55, 4654-4671`: `ApplyDamage(plr, part, DamageOf(plr))`).
- The pickaxe click is a separate damage source: pickaxe `Damage` × friend boost × weak-point combo (+0.05x per hit, cap 2x), 0.25s debounce (`BreakablesService.lua:41-49, 1554-1557, 1875-1889`). The comment at `:50` says it outright: "pets do ALL the damage now".
- Pet damage also directly scales **Time Skip product payouts** (Robux products quote `GetPetStrike` into the farming rate, `TimeSkipRateService.lua:245-251`).

**Chain: hatch pet → equip → Damage breaks cucumbers faster → each break pays Cucumbers × Multi1 → sell cucumbers for coins (rebirth-scaled, pet-agnostic) → buy next egg.** Damage is throughput, Multi1 is income-per-break, Multi2 is a side bonus.

---

## 2. Eggs — prices, pools, mechanics

All eggs are priced in **Coins** and require standing on the pad (raycast, `EggService.lua:104-127`) **and** owning the zone (`EGG_REQUIRED_ZONE`, `EggService.lua:57-66`).

| Egg | Price | Zone | Top odds | Bottom odds |
|---|---|---|---|---|
| Basic | 2,500 | Spawn | Cat 40% | Fox 1.5% + **Gregory 0.002% (secret)** |
| Desert | 10,000 | Desert | Barrel 40% | Cactus 0.5% |
| Samurai | 40,000 | Samurai | Dog Ninja 40% | Sensei 0.5% |
| Farm | 150,000 | Farm | Hay 40% | Farmer 0.1% |
| Frozen | 600,000 | Snow | Red Snowman 40% | Frozen Gem 0.5% |
| Ocean | 1,500,000 | Underwater | Oceanic Dog 40% | Atlantic Hydra 0.1% |
| Lava | 2,500,000 | Volcano | Lava Plume 40% | Demon Dog 0.01% |
| Narmek | 5,500,000 | Narmek | Moon Bunny 40% | Cosmo Cat 0.01% |
| Food Cuke | (reward-only) | — | Popcorn 30% | Ice Cream Cuke 0.01% |

Full per-pet weights: `pets.json → eggs[]` (all from `Dictionaries__Eggs.lua`).

### Hatch types & gamepasses (`EggService.lua:31-50, 392-446`)
- **Single** — 1 roll, 1× price. Hotkey E.
- **Triple** — 3 rolls, **3× price**, needs "Triple Egg Hatch" pass (1903566581). Hotkey R.
- **Instant** — 1 roll, 1× price, needs "Instant Egg Hatch" pass (1911700950); skips the reveal animation (also upgrades Triple/Auto reveals when owned).
- **Auto** — needs "Auto Egg Hatch" pass (1898883147); server resolves to Triple if the Triple pass is owned, else Single; the client's reveal completion immediately queues the next request (`UiController.lua:396-415`). Stop button always available.
- **Hatch speed**: reveal tweens divide by `PlayerData.FastHatch` — which is hard-coded to **1** and never raised by anything (`InstanceValues.lua:76-79`, `UpgradeService.lua:91`). Dead knob.

### Roll mechanics (`EggService.lua:181-307`)
1. Float-weighted roll over `Percent` sums (integer roll fixed 2026-08-23; fractional pets now honest).
2. **First-ever pet** (Basic Egg, empty `Unlocked`) upgraded to Rare+ via weighted re-roll → Wolf 66.6% / Tabby 23.3% / Fox 10.0% / Gregory 0.013%.
3. **Pity: `PITY_LIMIT = 25`** — see quirks below. Global counter (`profile.EggPity`), guarantees the **rarest pet of whatever egg you're hatching** on the 25th non-rarest hatch. Player notified every 5 hatches.
4. Auto-delete handshake: client settings can discard Common/Uncommon/Rare hatches (pet never granted, coins still spent); server waits up to 5s per roll (`EggService.lua:260-278`).
5. Hatches at ≤10% announced game-wide (`RareHatchChat`); ≤0.1% logged to analytics (`SecretHatch_*`).

---

## 3. Expected value per egg

E[stat] per hatch (pool-normalized; ignores pity/first-hatch/auto-delete). "M1/1000c" = expected additive cucumber-multi per 1,000 coins spent.

| Egg | Price | E[Multi1] | E[Damage] | E[Multi2] | M1/1000c | Dmg/1000c | Best case |
|---|---:|---:|---:|---:|---:|---:|---|
| Basic | 2.5k | 1.008 | 2.37 | 1.040 | 0.4033 | 0.950 | Gregory 12/500/12 |
| Desert | 10k | 1.637 | 4.82 | 1.721 | 0.1637 | 0.4815 | Cactus 2.1/10/2.1 |
| Samurai | 40k | 2.376 | 9.33 | 2.466 | 0.0594 | 0.2333 | Sensei 2.7/20/2.8 |
| Farm | 150k | 3.015 | 18.76 | 3.065 | 0.0201 | 0.1251 | Farmer 3.4/40/3.6 |
| Frozen | 600k | 3.737 | 37.92 | 3.817 | 0.00623 | 0.0632 | Frozen Gem 4.2/80/4.3 |
| Ocean | 1.5M | 4.475 | 75.50 | 4.565 | 0.00298 | 0.0503 | Atlantic Hydra 4.9/160/5.1 |
| Lava | 2.5M | 5.235 | 150.6 | 5.315 | 0.00209 | **0.0602** | Demon Dog 5.6/320/5.8 |
| Narmek | 5.5M | 5.955 | 176.5 | 6.055 | 0.00108 | 0.0321 | Cosmo Cat 6.6/375/6.8 |
| Food Cuke | free | 1.813 | 11.76 | 1.813 | ∞ | ∞ | Ice Cream Cuke 6/50/6 |

Observations:
- **Per-coin efficiency falls monotonically** (correct treadmill shape) **except Lava > Ocean on damage/coin** (0.0602 vs 0.0503): Lava is a better damage buy than the egg before it, and Narmek then halves efficiency for a ~17% per-hatch stat step. Narmek's 5.5M price (raised from 2.5M on 2026-08-22) buys +4.4% E[Multi1] over Lava at 2.2× the price — the marginal hatch is very expensive.
- Hatch-and-sell recovers ~10% of egg cost (e.g. Basic E[sell] ≈ 241 coins of 2,500; rarity values §6), so eggs are a proper coin sink.
- Triple hatch is EV-neutral per coin (3× price, 3 rolls) — it only saves time, and each roll still ticks pity.

### Pity-adjusted long-run EV (hatching the same egg forever, worst case pity always at 25)
Effective rarest-pet rate becomes ≥ 1/25 = 4%:
- **Basic**: E[Damage] jumps 2.37 → **22.3/hatch** (Gregory every ≤25 hatches ≈ ≤62.5k coins). Damage per 1000c ≈ **8.9** — 150× better than any other egg in the game.
- Lava: 150.6 → 157.4; Narmek: 176.5 → 184.4 (chase odds there are so tiny the guarantee IS the real drop rate: Demon Dog/Cosmo Cat are effectively 4% pets, not 0.01% pets).

---

## 4. Equip rules

- Base **4** slots (`InstanceValues.lua:123`).
- **Board upgrade "Pet equips"**: +1/level, max 3 levels, 30,000 Coins each (`Dictionaries__Upgrades.lua:107-123`; clamp at `:57`).
- **Legacy dev product "+2 Pets Equip"** (3609836815): +2 per buy, capped at +6 total (`ProductHandler.lua:164-175`).
- **Gamepass "+4 Pet Slots"** (1903134517): +4 (`Upgrades.lua:66-77`).
- Stacked total: `4 + board(≤3) + legacy(≤6) + pass(4)` = theoretical **17** — but `EquipService.lua:149` hard-caps at **`math.min(MaxEquipped, 10)`**. Anything past 10 is purchasable yet unusable (see quirks).
- **EquipBest** ranks owned pets by **Multi1 + Multi2 descending — Damage is ignored** (`UserInterfaceLoader__Pets.lua:729-755`), unequips all, equips top N until the server refuses (`PetService.lua:87-104`).
- No "team-up" mechanic exists; the swarm shares one committed target, leash 110 studs, pets must be within 10 studs of the target to land hits, chain range 15 studs (`BreakablesService.lua:50-55`).
- **Inventory**: base 30 + "+10 Pet Inventory" product (3609836686, persisted) + "+75 Pet Storage" pass (1899609194, applied on join). Hatching is blocked at cap (`EggService.lua:434-436`).

## 5. Evolve system (the only "variant" system)

- Select **3 copies of one Normal pet** in the Evolving UI (`Evolving.lua:289-331` enforces same-name, Normal-only, 3 max).
- Server: costs **600,000 Coins**, deletes the 3, grants **1 Golden** copy: **×1.5 Multi1/Multi2 (rounded), ×1.5 Damage** (`EvolveService.lua:32-88`, `PetDefaults.SetGoldenDefaults:64-100`).
- Golden = gold recolor + particles (`EquipService.lua:66-84`); sells for ×1.5 (`PetSellValues.lua:30`).
- There is **no shiny/rainbow ladder** — Golden is the entire evolution system.
- Join-time stat resync preserves the golden ×1.5 against dictionary retunes (`PetService.lua:206-241`).

## 6. Sell values (`PetSellValues.lua`, paid by `SellVendorServer.lua`)

Common 100 · Uncommon 250 · Rare 600 · Epic 1,500 (defensive, zero pets use it) · Legendary 3,500 · Special 5,000 · Mythical 10,000 · Omega 25,000 · Golden ×1.5 · unknown rarity → 100.
Vendor: max **50/batch**, 0.5s cooldown, equipped pets refused, inventory recounted after batch (`SellVendorServer.lua:23-24, 170-265`).
Note: an Omega **Blazing Pickle sells for 25,000** and is free every 30-minute session → ~50k coins/hour faucet for AFK-ish players (plus King Cuke = another 25k at 90 min).

## 7. Special obtain paths

| Pet | Stats (M1/Dmg/M2) | Path |
|---|---|---|
| Lil Pickle | 1/2/1 | Tutorial completion, one-time (`ServerNetwork.lua:244-280`) |
| OG Pickle | 1.5/5/1.5 | Launch-window gift via OGPetService — **script missing from this dump** |
| Blazing Pickle | 8/100/8 (Omega) | Playtime reward 6 (30 min), **every session** |
| King Cuke | 15/300/15 (Omega) | Playtime reward 9 (90 min), **every session** |
| Golden Cucumber | 8.2/400/8.2 | Season Cucumbers champion (`SeasonService.lua:24-28`) |
| Solid Gold Coin | 4.4/120/4.4 | Season Coins champion |
| Silver Pickle | 2.2/16/2.2 | Season Cucumbers top-10 |
| Diamond Gherkin | 4.4/120/4.4 | **No grant path anywhere — unobtainable orphan** |
| Gregory | 12/500/12 (Mythical) | Basic Egg secret 0.002%; hidden from egg UI (no Rank) |
| Colossus pets ×8 | 6→24 / 125→245 | 10 shards of that zone's boss each, repeatable (`BreakablesService.lua:93-108, 993-1045`) |
| Red Demon | 25/500/25 (Omega) | Robux product 3609774225; also in Starter Pack 3609836817 (+20k coins) |
| Purple Hydra | 30/500/30 (Omega) | Robux product 3609774320 |
| Heavenly Angel | 30/500/30 (Mythical) | Robux product 3609773882 |

Colossus ladder: Colossal 6/125, Cactus 8/145, Shogun 10/165, Harvest 12/185, Frozen 14/200, Abyssal 17/215, Magma 20/230, Cosmic 24/245 — deliberately under the Robux tier (30x/500).

## 8. Quirks, bugs, risks

1. **Global pity trivializes chase pets (biggest economy risk).** `profile.EggPity` is one counter across ALL eggs (`EggService.lua:221-237`). Build 24 pity on 2,500-coin Basic eggs (60k coins), then hatch ONE Lava/Narmek egg → **guaranteed Demon Dog or Cosmo Cat**. Repeat every 25 hatches. It also makes **Gregory a guaranteed ≤62.5k-coin pet** despite 1-in-50,000 branding — and every pity Gregory fires the game-wide RareHatchChat "0.002%" announcement, deflating the flex.
2. **Evolve charges before validating and trusts the client's pet name.** `EvolveService.lua:34-41` removes 600k Coins first; a validation failure still costs the money. Worse, the server never checks `PetData[id].Name == SelectedPet` (or Craft/ownership): 3 junk Commons + `SelectedPet="Purple Hydra"` mints a **Golden Purple Hydra (45/750/45) for 600k coins** from an exploited client. Highest-severity finding in this domain.
3. **Equip slots sold past the usable cap.** Theoretical `MaxEquipped` = 17 (board 3 + legacy product 6 + gamepass 4), but `EquipService.lua:149` caps live equips at **10**. A player owning +4 Pet Slots plus legacy +2s can pay for slots that do nothing (refund/UX risk).
4. **EquipBest ignores Damage** (`Pets.lua:740`) while pets deal essentially all damage. It ranks by Multi1+Multi2, so e.g. Moon Bunny (11.9 multi, 150 dmg) outranks Demon Dog (11.4 multi, 320 dmg). "Best" actively lowers DPS for chase-pet owners.
5. **Multi2 is near-dead.** It only multiplies `BonusCoins` direct drops (3–8 base coins per break before zone multi). Pets carry it as ~equal weight to Multi1 but its real economic value is a tiny fraction; the UI shows it as a headline "cash" stat (`Pets.lua:256`).
6. **Heavenly Angel = Purple Hydra stats (30/500/30) at Mythical rarity** — two Robux products with identical stats; Red Demon (25/500/25) is strictly worse than both. Check intended price ladder.
7. **Free Omega faucet:** Blazing Pickle + King Cuke re-earnable **every session** (`PlaytimeRewards` in-memory ladder) — each sells 25k; also power-creeps every egg below Lava (King Cuke 15/300 beats everything hatchable except nothing — it's stronger than Cosmo Cat on multi×2.3 and near it on damage) for 90 minutes of presence.
8. **Diamond Gherkin unobtainable; OGPetService absent from dump** — dictionary entries with no live grant path (verify OGPetService exists in the place, else OG Pickle is also ungrantable).
9. **Dead systems:** pet Levels/XP written at grant, never incremented anywhere; `FastHatch` always 1; "Epic" rarity has colors + sell value but zero pets.
10. **Auto-delete still spends coins** (discarded pet, price paid) — intended, but worth knowing for EV; and each roll's 5s server handshake wait (`EggService.lua:267`) throttles server-side hatch throughput if a client stalls.
11. **Basic Egg weight sum is 100.002** (Gregory rides on top) and Lava's is 100.01 — harmless with the float roll, but percent labels in the UI are nominal, not exact.
12. **Bypass accounts** own all gamepasses free: UserIds 1, 1660029941, 1196256323 (`ProductController.lua:24-28`) — fine for testing, confirm before shipping.
13. Sell vendor + PetSellValues note a live design coupling: pet-sell coins feed SeasonService coin standings (`PetSellValues.lua:12-15`) — mass-selling hatched Commons is a (small) season-leaderboard vector.
