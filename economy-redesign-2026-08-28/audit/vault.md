# Vault / Carry Economy Audit (2026-08-28)

Sources: `backups\EconomyRedesign_2026-08-28\scripts\` — all `file:line` refs below are into that dir.
Currencies: **Coins** (vault pads, sell vendor, quests) and **Cukes/Cucumbers** (mining; pays vault upgrades).

---

## 1. Carry catch odds

**100% CATCH MODE is active** (2026-08-27, user call). `CarryService.TryAwardFromBreak`
(`ServerStorage__ServerController__CarryService.lua:301-364`) awards a carry on **every break** by the
last attacker — the odds rolls are *bypassed, not removed* (comment at `CarryService.lua:330-337`;
pre-change module backed up in `ServerStorage.CarryOddsBackup_2026_08_27`).

What remains of the old odds (unused `ChanceFor`, `CarryService.lua:30-31,64-70`):

```
chance = 0.04 + 0.16 * clamp(Weight/35, 0, 1)     -- FLOOR_CHANCE + BASE_CHANCE scale
golden -> chance *= 0.5
```

Still-active gates in TryAwardFromBreak:
- **Template types only** (`:307`) — every regular biome breakable qualifies.
- **Tutorial gate** (`:313-318`): no carries mid-tutorial except `TutorialCarryPending` (guaranteed
  first catch, consumed at `:349`) or when already carrying.
- **Strictly-rarer swap** (`:323-329`): while carrying, `if rarity >= current.Rarity then return` —
  only a strictly LOWER `CarryRarityOf` value (rarer) replaces the arm cucumber.
- Showcase "1 IN X" = `round(1 / clamp(rarity,1e-9,1))` — spawn share alone in 100% mode (`:352-360`).

**Boss trophy** (`CarryService.lua:374-405`): defeated boss's cucumber goes to top damager,
guaranteed, replaces any carry; `Rarity = 1e-4`, `Rate = floor(8 * 1.6^(tier-1))`.

### CarryRarityOf (`ServerStorage__ServerController__BreakablesService.lua:3682-3706`)

Effective spawn probability, LOWER = RARER (comparison + display only):

```
p  = Weight / sum(Weights of zone's effective type pool)
p /= 2^(tier-1)                       -- tier = index in ZONES {Spawn..Narmek} (BreakablesService.lua:158)
golden:    p *= clamp(GoldenChanceFor(zone), 0.001, 1)   -- 0.08 base, x4 during Golden Hour (:2521-2522,2545-2547)
mutation:  p *= 0.02                  -- MUTATION_CHANCE (:605)
lightning: p *= 0.05                  -- (:3699-3701)
diamond:   p *= 0.02                  -- DiamondMod.Chance (:618-619)
```
PRISMATIC spawn chance itself is 1/30000 (`:613`) but as a `data.Mutation` it uses the generic 0.02
factor in rarity comparison — a PRISMATIC compares no rarer than a daily mutation. (Quirk, see §8.)

## 2. EarnRateOf — base coin rate (`CarryService.lua:76-88`)

```
base = 1 + (35 - clamp(Weight, 1, 35)) / 35 * 4        -- 1.0 (W35) .. 4.89 (W1); trees (W8) ~4.09
rate = base * 1.6^(tier - 1)                           -- tier from ZONE_FIELD_INDEX (CarryService.lua:39-42):
                                                       --   Spawn=1, Desert=2, Samurai=3, Farm=4,
                                                       --   Snow=5, Underwater=6, Volcano=7, Narmek=8
                                                       --   1.6^7 = x26.84 for Narmek
golden:              rate *= 3
diamond:             rate *= 8       -- spawn-rolled material, stacks with mutation, exclusive w/ golden at spawn
mutation:            rate *= (Mutation == "PRISMATIC" and 20 or 5)
lightning (CHARGED): rate *= 4
Rate = max(1, floor(rate))                             -- INTEGER, stored in record.Rate forever
```
Golden vs Diamond are exclusive at spawn (elseif, `BreakablesService.lua:3661-3667`); mutation and
lightning each stack on top of either and on each other. Theoretical max base Rate (Narmek W5
diamond PRISMATIC CHARGED): `4.43*26.84*8*20*4 ≈ 76,000 coins/s` — before levels.

### EffectiveRate (`CarryService.lua:417-423`)

```
EffectiveRate(record) = (record.Rate or 1) * 1.18^((record.Level or 1) - 1)
FROZEN mutation: *= 0.8              -- theft-proof tradeoff, applies everywhere it earns or is valued
```
Returns a FLOAT; callers floor at pay time. Level 20 (MAX) = ×1.18^19 ≈ **×23.2**.

## 3. ValueOf — sell price (`CarryService.lua:427-429`)

```
ValueOf(record) = floor(EffectiveRate(record) * 250)    -- ~4 min of its earn rate
```
Shown on vault cards (`VaultService.lua:961`) and paid by the carried-cucumber sale
(`ServerScriptService__SellVendorServer.lua:101-126`). **Quirk:** SellCarried's payout goes through
`AddCurrency` with no `MultipliersApplied`/`WasPurchase` flag, so `CurrencyHandler.GetMulipliers`
(`CurrencyHandler.lua:66-103`, Coins branch `:94-100`) multiplies it by the **rebirth mult**
`1 + 0.5*rebirths` (`RebirthService.lua:17,175-180`, max ×26 at 50 rebirths) — the vendor actually
pays up to 26× the card's green number.

## 4. Vault economics (`VaultService.lua`, `BankBuilder.lua`)

### Accrual (VaultService.lua:2069-2115)
- Loop ticks 5×/s (`TICK = 0.2`), each stored cucumber: `Accrued += EffectiveRate(rec) * dt`.
- **MOLTEN** (`:2092-2095`): `rate *= 1 + 1.5 * (HeatT/3600)`, `HeatT += dt` capped 3600 →
  ramps to **×2.5 after 1h uncollected**; `HeatT` saved with the vault (`:468`, load clamp `:1101`);
  reset to 0 on every Collect (`:1663`). Live tick only — offline coins use the flat rate.
- Profile write-through ~1s cadence (`SaveVault`, `:452-483`) with the `VaultLoaded` hard gate
  (`:456-459`) so a not-yet-restored stall can never save emptiness over real data.

### Collect (VaultService.lua:1648-1682)
- Owner steps on the per-cucumber CollectPad; pays `floor(Accrued) + floor(OfflineCash)`;
  sub-1 remainder keeps ticking; 1s per-record debounce.
- **`MultipliersApplied = true`** (`:1672`): pad payout is FLAT — exactly the label, no rebirth/coin
  multipliers (user fix 2026-08-27). Deliberately not `WasPurchase` so season stats track it.

### Upgrades (VaultService.lua:56-61, 176-178, 1598-1645)
```
MAX_LEVEL = 20;  COST_MULT = 1.35;  BASE_COST_PER_RATE = 500
UpgradeCostFor(record) = floor(record.Rate * 500 * 1.35^((Level or 1) - 1))    -- paid in CUKES
per level: rate *= 1.18
```
- Cost scales off the **base Rate**, not EffectiveRate.
- Cumulative L1→20 cost = `Rate * 500 * (1.35^19 − 1)/0.35 ≈ Rate * 426,000 Cukes`; buys ×23.2 rate.
- Marginal ROI shrinks: +18% rate per level for a 35%-dearer price each level.
- Level rides in the record — survives take-back, replace, **steal**, and the vendor sale price
  (`CarryService.lua:413-416`).

### Capacity (BankBuilder.lua:43-75)
```
CapacityFor(level, extra) = 6 + clamp(rebirths, 0, 50) + clamp(extraSlots, 0, 3)   -- max 59
FloorsFor(capacity)       = max(1, ceil(capacity / 10))                            -- SLOTS_PER_FLOOR 10, max 6 floors
WidthFor(level)           = 36 + 5.75 * clamp(level, 0, 5) studs
```
- Stall level = owner's `leaderstats.Rebirths`, watched live (`VaultService.lua:1345-1375`);
  extra = `PlayerData.Upgrades["Vault slots"]` board purchases (`:1313-1343`). 12 stalls total (`:54`).
- Physical fit caps a floor at `floor((width−4.8)/5.9)+1` podiums (10 at typical, 11 at max width) —
  `BankBuilder.lua:79-98`.

### Offline coins (VaultService.lua:1041-1060, 1104-1106)
```
away = clamp(os.time() - Data.VaultLastSave, 0, 57600)     -- counted absence caps at 16h
away < 120 -> nothing (quick rejoin)
equivSeconds = min(away, 21600)*0.5 + max(0, away-21600)*0.3   -- max 21600s = 6h of full rate
per cucumber: rec.OfflineCash += EffectiveRate(rec) * equivSeconds
```
- Mirrors `OfflineService.lua:15-26` cukes tiers (50% first 6h, then 30%, 6h-equivalent cap).
- Flat EffectiveRate: no MOLTEN ramp, no multipliers. Stamped from `Data.VaultLastSave`
  (`SaveVault`, `:479-481`) because OfflineService's LastSeen resets on join first.
- Uncollected OfflineCash **carries over and stacks** across absences (`:1104-1106`); shown gray on
  the pad, granted with the next Collect; zeroed if the cucumber is stolen (`:1913-1914`).

## 5. Vault-derived income: VaultTimeSkipService (`VaultTimeSkipService.lua`)

```
CoinsPerSecond(plr) = Σ EffectiveRate(record) over stored cucumbers      (:30-42)  -- FROZEN 0.8 in, MOLTEN heat OUT
GetRate  = GetMulipliers(Coins, CoinsPerSecond)  = CoinsPerSecond * (1 + 0.5*rebirths)   (:45-54)
Quote(s) = floor(GetRate * seconds)                                       (:56-59)
Grant    = AddCurrency(Quote, WasPurchase=true)  -- flat; refuses empty vault (:64-80)
```
Consumers:
- **Dev products** `ProductController.lua:236-243`: 1min…1week skips — all `Id = 0` placeholders,
  granted in `ProductHandler.lua:139-146` when ids land. Live card quotes: `TimeSkipQuoteServer.lua:5-17`
  → `Store.lua:67`.
- **Quest board** `QuestBoardService.lua:40-43,130-139`: each of 3 quests rolls a reward duration from
  {60,180,300,600}s; claim pays `max(VaultTimeSkipService.Quote(plr, seconds), 500)` Coins **plus** a
  cukes skip (`TimeSkipRateService.Grant`). All 3 claimed → 6h reset.
- **Minigames** `MinigameCompletionService.lua:59-72,112-130,190-242`: coin prizes quote the vault over
  {120,300,900,1800}s (pool weights 10/8/6/3 of 127 total); empty vault downgrades to the
  same-duration cucumber prize; payout locked at pick time via `PendingMinigameRewardAmount`.

## 6. Steal system economics (`VaultService.lua:1876-1958`, Heist `:1377-1505`)

- **Transfer**: thief gets the full record — base Rate, Level (up to ×23.2, worth `Rate*426K` Cukes of
  investment), Mutation all ride along. Victim's profile forgets it **immediately** (`SaveVault`,
  `:1957`). `Accrued`/`OfflineCash` are zeroed first (`:1913-1914`) — pad money never changes hands.
- **Windows**: lever lock lasts `SECURE_DURATION = 300s` (`:65`); fresh owners start locked (`:1517`);
  after lapse ANY non-owner can hold F (2.5s) — server re-validates lock, 14-stud presence, empty
  hands, 1s steal rate limit (`:1885-1906`). FROZEN records are theft-immune at 0.8× earnings (`:1880-1884`).
- **Heist fight** (`:1377-1505`): thief carries at 1.5× slower; victim reclaims automatically after
  **3 hits** (range 16, 0.7s cooldown); thief wins by banking it in their own vault; thief leaving
  mid-heist returns it, victim leaving forfeits (`:1543-1548`).

## 7. Expected vault income — simulator pieces

```
EffRate_i        = Rate_i * 1.18^(L_i-1) * (FROZEN? 0.8 : 1)
padRate(t)       = Σ_i EffRate_i * (MOLTEN_i? 1 + 1.5*min(t_i,3600)/3600 : 1)     coins/s, paid FLAT
questClaim       = max(Σ EffRate_i * (1+0.5*R) * s, 500),  s ∈ {60,180,300,600}   -- 3 per 6h + cukes skip
minigameCoinWin  = Σ EffRate_i * (1+0.5*R) * s,            s ∈ {120,300,900,1800}
offlineBank      = Σ EffRate_i * (0.5*min(away,21600) + 0.3*max(0,away-21600)),   away ∈ [120, 57600]
carriedSale      = floor(EffRate * 250) * (1+0.5*R)        -- rebirth mult double-dips (see §3 quirk)
```
Worked examples (passive pads, flat):
- Early: 6 × Spawn common L1 (Rate 1) → 6/s ≈ **360 coins/min**.
- Mid: 8 × golden Farm W16 L5 (Rate 38, EffRate 73.7) → 590/s ≈ **35K/min**.
- Late: 10 × golden Narmek tree L20 (Rate 329, EffRate 7,637) → 76.4K/s ≈ **4.6M/min**;
  a single 10-min quest claim at R50 quotes `76.4K * 26 * 600 ≈ 1.19B` coins.

Active-play coin sources for comparison: direct `BonusCoins` per break are 1–30
(`BreakablesService.lua:179-336` samples) — vault passive dwarfs them past the first biomes; the
main active loop is Cukes → vendor sell (rebirth-multiplied), a different currency.

## 8. Quirks / bugs / risks

1. **Quest & minigame rewards scale with vault size, uncapped** — `Quote = ΣEffRate × rebirthMult ×
   seconds` with no ceiling (`VaultTimeSkipService.lua:56-59`; floor 500, no cap at
   `QuestBoardService.lua:135`). The dev save's observed **6.5M/quest** ≈ e.g. ΣEffRate ~800/s ×
   R25 (13.5×) × 600s. A 30-min minigame coin card is up to 3× a 10-min quest.
2. **Multiplier asymmetry / double-dip**: pad Collect is deliberately flat (`MultipliersApplied`,
   `VaultService.lua:1672`), but time-skip quotes multiply by rebirth (`CurrencyHandler.lua:94-100`)
   — "skipping" 10 minutes pays up to 26× what 10 real minutes of pads pay. Same double-dip on the
   carried sale (§3): card shows `EffRate*250`, vendor pays `×(1+0.5R)` on top.
3. **Feedback loop**: vault income → (coins fund doors/pickaxes/eggs; quests also grant Cukes) →
   Cukes fund vault upgrades (×1.18/level) → higher ΣEffRate → bigger quest/minigame/timeskip
   quotes → repeat. Capacity (59) and MAX_LEVEL (20) are the only brakes; per-cucumber Rate is
   unbounded (PRISMATIC CHARGED diamond Narmek ≈ 76K/s base, ≈1.8M/s at L20 — **one** cucumber).
4. **100% catch mode + strictly-rarer swap** ratchets every player's arm to their rarest-ever break
   with zero luck gate; pet auto-farm breaks proc carries silently (`VaultService.lua:307-311`
   comment) — vault stocking is effectively free.
5. **PRISMATIC undervalued by rarity compare**: `CarryRarityOf` uses the generic 0.02 mutation factor
   (`BreakablesService.lua:3696-3698`) though PRISMATIC spawns at 1/30000 (`:613`) — a PRISMATIC on
   the arm can be displaced by odds math that thinks it's common, and its "1 IN X" under-reports.
6. **Accrued is uncapped** — pads accumulate forever while online (no AFK ceiling); with MOLTEN the
   ramp caps at 2.5× but the pile itself doesn't. Offline is capped (6h-equivalent per absence) but
   uncollected `OfflineCash` stacks across absences with no ceiling (`VaultService.lua:1104-1106`).
7. **Steal loses real money**: level investment (up to Rate×426K Cukes) transfers to the thief and the
   victim's profile is rewritten instantly (`:1957`); no victim-side recovery beyond the 3-hit heist
   window. FROZEN is the only hedge (0.8× forever).
8. **VaultTimeSkips products are Id 0** — the monetized skip path is wired but dormant
   (`ProductController.lua:236-243`); QuestBoard/minigames already give the same quotes free.
9. **Quest coin floor** (500, `QuestBoardService.lua:43`) pays even with an empty vault — trivial,
   but it means quests never quote honestly at 0 like Grant does.
10. **MOLTEN live-only ramp** is fine, but note the time-skip quote also ignores heat — buying a
    skip on a hot MOLTEN vault quotes LESS than letting it sit (only case where passive beats quote,
    ignoring rebirth mult).
