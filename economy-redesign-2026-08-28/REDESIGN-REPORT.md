# Collect a Cucumber — Complete Economy Redesign
**2026-08-28 · dev place `135680492327917` ("collect cucumber game 8/25")**
Status: **modeled → implemented → validated in a live playtest with zero errors.** Not yet published to the live place.

---

## 1. Summary of the original economy

- Two currencies: **Cukes** (from breaking) and **Coins** (from selling Cukes 1:1 × rebirth bonus; chests, quests, vault pads). Coins bought everything (doors 4K→1.5B, 19 pickaxes 500→6B, eggs 2.5K→5.5M, rebirths 100K×3.5^R); Cukes only bought vault cucumber upgrades.
- Zone ladder was nearly flat in **value** (×1→×42 across all 8 areas) but steep in **HP** (×1→×500) — later areas paid *less per point of damage*; progression feel came almost entirely from multipliers.
- Cucumber income multipliers stacked multiplicatively: rebirth (1+0.5R, ×26 max) × 2x gamepass × pet Multi1 (up to ~×766 theoretical) × 2x boost × 1.5 group. Coins got the rebirth multiplier **again** at the sell vendor — a quadratic double-dip (~(1+0.5R)², ×676 at R50).
- Pets: Multi1 1–8.2 bands, Damage 2–500; damage-per-hit topped out at 2,200 (Rainbow Pickaxe). Golden evolve = 3 copies + flat 600K.
- Mutations: one flat ×25 daily mutation (2%), Diamond material 2% ×20, Golden 8% ×7, PRISMATIC 1/30,000 ×100, lightning 25–50×.
- Rebirths gated areas 4–8 (R1–R5) and MAX_REBIRTHS=50 was unreachable (R49 ≈ 4.6×10³¹ Coins).

## 2. Problems discovered (audit of ~14,000 lines across 106 scripts)

| # | Problem | Severity |
|---|---|---|
| 1 | **Value/HP inversion**: zone HP grew ×500 while value grew ×42 — every new area felt *worse* per hit | Core design |
| 2 | **Rebirth double-dip**: (1+0.5R) applied at earn AND sell → prices collapsed quadratically; late-game pricing meaningless | Core design |
| 3 | **Numbers never got big**: end-game breaks paid ~9K Cukes — no number fantasy | Core design |
| 4 | **Playtime ladder reset every session** → a free rebirth + duplicate Omega pets (Blazing Pickle, King Cuke) every 90 minutes, forever | Exploit/faucet |
| 5 | **EvolveService charged 600K BEFORE validating** and never checked the 3 sacrificed pets matched — a modified client could mint a Golden Purple Hydra from 3 junk Commons | Exploit |
| 6 | **Quest/minigame vault quotes uncapped** — scaled with vault size × rebirth mult (observed 6.5M/quest on the dev save); vault→quest→upgrade→vault feedback loop unbounded | Exploit/faucet |
| 7 | **Global 25-hatch egg pity** spanned all eggs: 24 cheap Basic hatches then 1 Narmek hatch = guaranteed Cosmo Cat | Economy leak |
| 8 | StarterPortalService wiped smash progress on **every join** (the other 4 portals reset on completion) | Bug |
| 9 | Escaped bosses paid the full kill rate — no reason to finish the fight | Design bug |
| 10 | SellCarried paid more than the displayed card value at R>0 (hidden rebirth mult) | UX bug |
| 11 | Pet equip hard cap 10 silently ate one slot from "+4 Pet Slots" gamepass buyers (4+3+4=11) | Bug |
| 12 | GoldenHour's churn filter (base HP ≤ 30) no-oped in 7 of 8 zones | Bug |
| 13 | VaultService's card formatter only knew K/M/B; SuffixNumber returned `nil` past its table | Display |
| 14 | Vault passive income used flat made-up bands (1.6^tier) that would go irrelevant under any inflation | Design |

## 3. The new economy philosophy

**Two parallel exponentials, one tuned gap.** Costs and income both race upward per area; the *gap between them* is the only thing that controls time. Numbers are fireworks; ratios are the game (Pet Sim 99 / Grow a Garden principle).

- **Value ladder ×8 per area** (zone value = 8^tier: 1 → 2,097,152) × **pet multiplier supply ×3 per area** = income grows **×24 per area**.
- **HP ladder ×12–13 per area** vs damage supply (pickaxes ×2.75/step at ~2.4 steps/area + pet Damage ×~12/egg tier) — kill times stay flat (~1.5–3s commons) while damage numbers explode from 5 to 147M+.
- **Rebirth = the ×2 engine**: income multiplier is now **2^R** on Cukes (replacing 1+0.5R), the coin side is a flat honest 1:1. Costs ride the door gates through R5, then ×2.9/rebirth — each post-game loop takes ~×1.45 longer: a tail that never hard-walls (R50 cap intact).
- **Jackpots are tiered, public, and budgeted**: five overlapping rarity systems (type ladder, materials, daily mutation, VOID, PRISMATIC, lightning), with the stacked material×mutation product **capped at ×5,000** so the biggest hit ≈ an hour of income, never a broken economy.
- **The vault rides the same ladder**: a stored cucumber re-earns its own break value every ~220s, multiplied by the owner's live pet×rebirth power — passive income stays ~5–15% of active at every stage, and quest quotes are capped at farm-equivalent.
- **First session is dense**: first egg at 250 Coins (tutorial's 2,500-coin gift ≈ 10 hatches), Stone Pickaxe 400, first door at ~6 min, ~10+ purchase moments in the first 10 minutes.

## 4. Area unlock costs (Doors — all Coins)

| Area | Zone | Door price | Rebirth gate | Zone value (Orb×Multi) | Zone HP wall |
|---|---|---|---|---|---|
| 1 | Spawn (Grassy) | free | — | ×1 | ×1 |
| 2 | Desert (Wild West) | **60K** | — | ×8 | ×13 |
| 3 | Samurai Palace | **5M** | — | ×64 | ×165 |
| 4 | The Farm | **300M** | R1 | ×512 | ×2,050 |
| 5 | The Arctic (Snow) | **60B** | R2 | ×4,096 | ×24,500 |
| 6 | The Ocean (Underwater) | **5T** | R3 | ×32,768 | ×285,000 |
| 7 | The Volcano | **400T** | R4 | ×262,144 | ×3.25M |
| 8 | The Greenland (Narmek/Space) | **25Qa** | R5 | ×2,097,152 | ×36.5M |

Door backfill (buying a later door grants earlier ones) is unchanged — it makes post-rebirth rebuilds feel great (~3–6 min at doubled income).

## 5. Cucumbers — HP, value, rarity, spawn odds

Every zone uses the same 5-tier internal ladder (base values; **the engine multiplies value by the zone's Orb×Multi and HP by the zone's HP wall**):

| Tier | Base value | Base HP | Spawn share* | Effective value |
|---|---|---|---|---|
| Common | 8 | 30 | ~58–61% | ×1 |
| Uncommon | 15–20 | 46–57 | ~24–25% | ×2.5 |
| Rare | 28–56 | 70–105 | ~10–14% | ×7 |
| Epic | 56–173 | 105–199 | ~4–7% | ×18 |
| **Tree (guaranteed 1 standing/zone)** | **360** | **300** | ~1–2% | **×45** |

*Zones with 6–8 types interpolate between tiers. Sliced quota types: 8 HP / 3 base value (tap candy, separate spawn quota).*

Full per-zone table (Weight / HP / Reward as shipped in `ZONE_EXCLUSIVE_TYPES`):

- **Spawn**: Cucumber 61/30/8 · Slice Stack 24/57/20 · Vined 10/105/56 · Flowered 4/180/144 · Cucumber Tree 2/300/360 (sliced: Sliced Cucumber 8 HP/3)
- **Desert**: Prickly 46/30/8 · Sliced 25/46/15 · Sun-Baked 14/70/28 · Wrapped 7/105/56 · Cactus 4/150/105 · Desert Palm 2/213/195 · Sandstone Tree 1/300/360 (Sun-Dried Slice 3)
- **Samurai**: Katana 53/30/8 · Bamboo 25/50/17 · Lantern 12/82/37 · Bamboo Grove 6/130/82 · Torii Gate 3/199/173 · Sakura Tree 1/300/360
- **Farm**: Muddy 61/30/8 · Crate 24/57/20 · Windmill Plant 10/105/56 · Hay Bale 4/180/144 · Cucumber Tree 2/300/360 (Cucumber Basket 3)
- **Snow**: Snowcap 46/30/8 · Snowball Slice 25/46/15 · Crystal 14/70/28 · Frozen 7/105/56 · Snow Tree 4/150/105 · Icicle Tree 2/213/195 · Frozen Tree 1/300/360 (Frozen Slice 3)
- **Underwater**: Seaweed 46/30/8 · Shell Slice 25/46/15 · Coral 14/70/28 · Pearl 7/105/56 · Kelp Tree 4/150/105 · Bubble Tree 2/213/195 · Coral Tree 1/300/360 (Bubble Slice 3)
- **Volcano**: Charred 53/30/8 · Molten 25/50/17 · Flame 12/82/37 · Obsidian Tree 6/130/82 · Volcano Cucumber 3/199/173 · Magma Tree 1/300/360 (Molten Slice 3)
- **Narmek**: Meteor 46/30/8 · Planet Slice 25/46/15 · Astronaut 14/70/28 · Neon Alien 7/105/56 · Moon Tree 4/150/105 · Alien Tree 2/213/195 · Galaxy Tree 1/300/360 (Moon Slice 3)

Worked example: a plain **Narmek Galaxy Tree** pays 360 × 2,097,152 ≈ **755M Cukes** base — before materials, mutations, pets, and 2^R.

## 6. Materials & mutations (the jackpot stack)

**Materials** (exclusive slot, rolled at spawn, baked into the type — they also add HP):

| Material | Chance | Value | HP | Coins drip | Rate seen |
|---|---|---|---|---|---|
| GOLDEN | 4% (×4 in Golden Hour) | **×12** | ×3 | ×10 | ~1 in 25 |
| DIAMOND | 0.6% | **×50** | ×5 | ×25 | ~1 in 167 |

**Mutations** — an **always-on weighted rarity mix** (2026-08-28 later, user call: the daily rotation meant every session showed exactly one mutation; now every spawn can roll any of them, commons often and ROYAL rarely). All stack multiplicatively on materials:

| Mutation | Per-spawn odds | Value | Notes |
|---|---|---|---|
| NEON / SHADOW | 1 in 100 each | ×15 | the common sparkle |
| FROZEN | 1 in 250 | ×20 | keeps 0.8× vault earn + theft-proof mechanics |
| RADIOACTIVE / MOLTEN | 1 in 400 each | ×25 | MOLTEN keeps the vault heat ramp (to 2.5×/h) |
| ROYAL | 1 in 667 | **×40** | the rotation-pool jackpot |
| **VOID** (new) | **1 in 1,200** | **×150** | deep void-purple body; mid-tier chase |
| **PRISMATIC** | **1 in 20,000** | **×750** | server-wide announcement, rainbow hue-cycle, quest wildcard |
| CHARGED (lightning) | bolt every **2–4 min**/zone (was 30–90s — at that cadence a charged stood in every zone ~100% of the time) | ×40–80 (rolled) | 75s window, one per zone; ~40% uptime now — an event again |

Total mutation rate ≈ 3.05% (`MUTATION_CHANCE` = the sum of the per-mutation chances — keep in sync). `TodaysMutation` survives only for the admin spawner's "TODAY" option, and `CarryRarityOf` now uses each mutation's true odds, so a ROYAL or PRISMATIC catch reports its real "[1 IN X]" and wins the strictly-rarer carry swap correctly (closes an audit quirk).

**Guardrail:** the combined material × mutation × lightning product is clamped to **×5,000** (`MUTATIONS.StackCap`) — e.g. Diamond(×50) + PRISMATIC(×750) = ×37,500 raw → pays ×5,000. Jackpot budget: a PRISMATIC common ≈ **~10 minutes of income**; the rarest realistic stack ≈ ~1 hour. Thrilling, never economy-breaking.

## 7. Pickaxes (19, sequential, Coins)

| # | Pickaxe | Price | Damage |
|---|---|---|---|
| 0 | Wood | free | 3 |
| 1 | Stone | 400 | 5 |
| 2 | Bronze | 6K | 14 |
| 3 | Iron | 60K | 38 |
| 4 | Steel | 500K | 105 |
| 5 | Gold | 2.5M | 290 |
| 6 | Emerald | 10M | 800 |
| 7 | Ruby | 60M | 2,200 |
| 8 | Amethyst | 300M | 6,000 |
| 9 | Diamond | 2B | 16.5K |
| 10 | Valentine | 10B | 45K |
| 11 | Magma | 60B | 124K |
| 12 | VoidNeon | 250B | 340K |
| 13 | CosmicIce | 1T | 935K |
| 14 | YinYang | 6T | 2.6M |
| 15 | Galaxy | 40T | 7M |
| 16 | SolarFlare | 200T | 19.5M |
| 17 | BloodMoon | 1Qa | 53.5M |
| 18 | Rainbow | 5Qa | **147M** |

Every step is a real **×2.75 damage jump** (never a useless +10%); prices grow ×3.4–5 so each next pickaxe is ~4–6 minutes of income at its intended moment — ~2.4 pickaxes per area.

## 8. Eggs & pets

**Egg prices** (Coins, zone-gated): Basic **250** · Desert **100K** · Samurai **3M** · Farm **200M** · Frozen **10B** · Ocean **500B** · Lava **30T** · Narmek **2Qa** (Food Cuke Egg stays playtime-only).

**Pool odds** (all zone eggs): 40 / 30 / 15 / 9 / **5 / 1%** chase — Lava & Narmek keep an **0.05% ultra-chase** slot (Demon Dog / Cosmo Cat) and Basic keeps secret Gregory at 0.002%.
**Pity** (fixed): **per-egg** counters now — rarest pet guaranteed within **25 hatches** (50 for ultra eggs).

**Pet stats** (Multi1 = Cukes income, additive across ≤7–11 equips; Damage = swarm DPS every 0.6s). Floor→chase per egg:

| Egg | Floor (40%) | Chase (1%) | Ultra |
|---|---|---|---|
| Basic | Cat 1 / 2 | Fox 4.5 / 9 | Gregory 50 / 10K (0.002%) |
| Desert | Barrel 3.5 / 25 | Cactus 16 / 110 | — |
| Samurai | Dog Ninja 10 / 280 | Sensei 45 / 1.3K | — |
| Farm | Hay 30 / 3.2K | Farmer 140 / 14K | — |
| Frozen | Red Snowman 90 / 38K | Frozen Gem 400 / 170K | — |
| Ocean | Oceanic Dog 280 / 430K | Atlantic Hydra 1.2K / 1.9M | — |
| Lava | Lava Plume 800 / 5M | Lava Dragon 2.2K / 14M | Demon Dog 3.6K / 22M (0.05%) |
| Narmek | Moon Bunny 2.5K / 60M | Nebula Fox 7K / 170M | **Cosmo Cat 11K / 270M** (0.05%) |

**Boss-forge pets** (10 shards each): Colossal Cucumber 8/40 → Cactus 28/450 → Shogun 80/5K → Harvest 240/60K → Frozen 700/700K → Abyssal 2K/8M → Magma 6K/100M → **Cosmic Colossus 18K/450M** (strongest obtainable pet).
**Specials**: Lil Pickle 2/3 (tutorial), OG Pickle 3/8, Blazing Pickle 25/5K (30 min — **one-time now**), King Cuke 60/25K (90 min — **one-time now**), Gregory 50/10K, Red Demon 500/500K, Purple Hydra & Heavenly Angel 800/900K (Robux), Golden Cucumber 1.2K/2M (season champion), Solid Gold Coin 600/800K, Silver Pickle 300/300K, Diamond Gherkin 600/800K (still unwired), Food Cuke pets 4/60 → Ice Cream Cuke 40/3K.
**Golden evolve**: 3 same-name Normal copies + **2× the pet's egg price** (was flat 600K) → ×1.5 all stats; server now fully validates before charging.

## 9. Rebirths

| R | Cost (Coins) | Income multiplier after |
|---|---|---|
| 0→1 | 90M | ×2 |
| 1→2 | 20B | ×4 |
| 2→3 | 1.5T | ×8 |
| 3→4 | 100T | ×16 |
| 4→5 | 7.5Qa | ×32 |
| 5→6 | 21.8Qa | ×64 |
| 7→8 | 183Qa | ×256 |
| 9→10 | 1.54Qi | ×1,024 |
| R≥5 rule | ×2.9 per rebirth | ×2 per rebirth |

Keeps: pickaxes, pets, upgrades, vault, shards. Resets: Cukes, Coins, doors. +1 vault slot per rebirth. The playtime **free rebirth is one-time forever** now.

**Board upgrades** (linear formula kept): Vault slots 500K/1.5M/2.5M · Pet equips 25K/75K/125K · Smashes-required 50K/200K/350K.

## 10–12. Income, time-in-area, and cumulative progression (simulated)

Average-player **entry** income (mid-area runs 3–8× entry as pickaxes/eggs land):

| Area | Entry income/min | Unlocked at (cumulative) | Time in area |
|---|---|---|---|
| 1 Spawn | ~1–35K/min ramping | 0 | ~6 min |
| 2 Desert | 34.4K | **6 min** | ~23 min |
| 3 Samurai | 1.82M | **29 min** | ~31 min |
| 4 Farm | 68.1M | **1.0h** | ~1.7h |
| 5 Arctic | 4.11B | **2.7h** | ~2.7h |
| 6 Ocean | 262B | **5.4h** | ~4.6h |
| 7 Volcano | 16.5T | **10.1h** | ~7.1h |
| 8 Space | 1.01Qa | **17.2h** ✅ | endgame + rebirth tail |

Four simulated profiles: **casual** (70% active, unlucky) mid-Area-7 at 20h, Area 8 ~24h · **average** Area 8 at **17.2h** (target 15–20h ✅) · **lucky** 12.2h · **optimized whale** (2x pass + boosts + group, 97% active) ~2h — paying + perfect play is meant to be fast.

Wallet magnitude trajectory (average): 1 min ≈ 800 · 10 min ≈ 267K · 30 min ≈ 11.8M · 1h ≈ 519M · 3h ≈ 462B · 6h ≈ 52T · 15h ≈ 32Qa · 20h ≈ 7.5Qi — then the rebirth tail (R6–R11 land in hours 17–20, each loop ×1.45 longer) carries numbers toward Sx/Sp/Oc over weeks. The formatter renders cleanly through vigintillion (`Vgn`, 10^63) with a scientific fallback at 10^153.

## 13. The rare/jackpot system, layer by layer

1. **Type ladder** — every ~50 kills a Tree (×45) spawns; one is always standing as the field's visible payday.
2. **GOLDEN** (1/25, ×12) — the constant small hit. **DIAMOND** (1/167, ×50) — the "ooh" moment, ~every 8 minutes.
3. **Daily mutation** (1/50, ×15–40 by day) — ROYAL day (×40) is a login appointment.
4. **VOID** (1/1,500, ×150) — the session highlight, ~1–2 per hour of active play.
5. **PRISMATIC** (1/25,000, ×750) — ~one per day of active play; server-wide announcement, rainbow body, quest wildcard.
6. **Lightning** (every 30–90s per zone, ×40–80, 75s window) — a race-to-it event.
7. Stacks multiply but cap at ×5,000 — the lottery win is ~1 hour of income, a screenshot, not a retirement.
8. Storing a jackpot catch in the vault turns it into a proportional passive-income monument (value/220 per second) — and something worth stealing.

## 14. Files modified (all in the dev place)

**Dictionaries (values)**: `ServerController.Dictionaries.Doors / Pickaxes / Eggs / Upgrades / Pets`
**Post-ship tuning (2026-08-28 later, user)**: lightning interval 30–90s → **120–240s**; rotation mutation 2% → **2.5%**, VOID → **1/1,200**, PRISMATIC → **1/20,000**. **Vault rates made fractional** (user screenshot: a Golden Sliced and a plain Sliced both showed 1.4/s / 348 / 911 — the integer floor `max(1, floor(value/220))` collapsed every record worth <440 to the same 1/s): `EarnRateOf` now returns `max(0.01, value/220)` exactly proportional, so every type × zone × material × mutation combo earns a distinct rate/value/cost; RateText shows 2 decimals below 1/s, upgrade cost floors at 1 Cuke, and the migration stamp bumped RateV 2→3 so already-migrated records recompute on next join. **Vault quotes made honest again**: the farm-equivalent cap briefly lived inside `VaultTimeSkipService.Quote`, which clamped store coin quotes to the exact cuke quotes whenever the vault out-earned active farming (e.g. post-rebirth); the cap moved to a new `QuoteCapped` (half farm-equivalent) used only by the quest board's free coins. Sim after tuning: value EV 2.34→2.50, average Area 8 ≈ **16.5h** (still in band).

**Services**: `BreakablesService` (ZONE_HP, 58 type entries, golden/diamond, tiered mutations + VOID + StackCap + MultOf export, lightning 40–80, boss HP/rewards, escape half-rate, ApplyStoredLook VOID), `CarryService` (EarnRateOf = breakValue/220, RateOf export, CHARGED=50 parity, boss trophy rate, RateV stamp), `VaultService` (accrual × owner Multi1×2^R, VaultMultSnap, RateV migration in LoadVault, offline × snapshot, Abbrev→NumberController), `RebirthService` (cost table + ×2.9 tail, Multiplier=2^R, Mult/NextMult payload), `CurrencyHandler` (coin side flat), `VaultTimeSkipService` (owner-mult rate + farm-equivalent cap), `PetService.EvolveService` (validate-then-charge, dynamic cost), `PetService.EggService` (per-egg pity 25/50 + migration), `PetService.EquipService` (cap 11), `PlaytimeRewards` (one-time pets/rebirth + consolation grants), `ServerScriptService.StarterPortalService` (reset moved to completion)
**Shared/client**: `NumberController` (SuffixNumber hardening), `UserInterfaceLoader.RebirthNewFrame` (×2^R display)

## 15. Backups (do not delete)

- **`backups/EconomyRedesign_2026-08-28/`** — `rbxm/` full binary exports (ServerController, all services, full Workspace), `scripts/` 106 plain-text `.lua` pre-redesign dumps, `values/` baseline JSON snapshots + this design's `final-design.json`, `README.md` with three revert paths.
- **In-Studio**: `ServerStorage.EconomyBackup_PreRedesign_2026_08_28` — clones of all 33 economy scripts + `README_REVERT`.
- Roblox cloud version history remains the nuclear option.

## 16. Save compatibility & migrations (all shipped + live-verified)

- **Vault records**: `RateV=2` stamp; un-stamped records recompute Rate from live tables on restore (golden/diamond prefixes re-apply their bake). Verified against the dev save's real 14-record vault — every card matched the formula exactly. Accrued/OfflineCash/Level preserved.
- **EggPity**: legacy number migrates into a per-egg table (seeds Basic Egg).
- **Pet stats**: existing owned pets re-sync to new dictionary stats on join (existing system — verified live: "re-synced 8 pets").
- **PlaytimeRewards.Once** flags: additive profile field, defaults empty.
- Old balances/doors/pickaxes/rebirths untouched. **Veteran saves get a one-time windfall** (they own late doors and now earn new-scale income) — acceptable update-hype; their rebirth counts now grant 2^R.

## 17. Assumptions & remaining risks

**Assumptions**: sell cadence ≈ continuous (Cukes≈Coins); average player ≈ 85% active clicking at 3 cps; ~10 eggs bought per area; kills/min capped ~26 by spawn supply; the 2x-pass/boost/group multipliers modeled only in the whale profile.

**Risks / watch-list**:
1. **Whale velocity**: permanent 2x pass + stacked boosts is ~6× income → Area 8 in ~2h. Intended monetization posture, but monitor.
2. **Robux time skips** (up to 1 week) quote at full multipliers — at R10+ a 1-week skip is enormous. Quotes are locked at purchase; consider capping duration ≥1d products post-launch.
3. **Boss HP** now scales with the much bigger ZONE_HP; hpBase values (3.5K–8.5K) are sim-estimated for 60–100s solo kills mid-area — worth one real fight per zone to confirm feel.
4. **VOID mutation** verified statically (identical machinery to PRISMATIC) but not yet observed organically; the admin panel's mutation cycler doesn't list VOID yet (cosmetic; add later).
5. **Evolving UI** shows no cost label (never did); the new dynamic cost is server-enforced — a cost row in the UI would be a nice follow-up.
6. Old **Boosts/BoostTotals** and season stats operate on the new magnitudes fine (doubles), but any external dashboards reading raw values will see a step change on 2026-08-28.
7. The dev save was used for validation: it gained an egg hatch, pet equips, test income, and its vault records migrated (by design). Its `EggPity` is now a table.

**The one thing left for you:** the edits live in the open Studio session — **File → Save/Publish** the dev place when you're happy, and (when shipping to the live place 116126086405931) port the same script set per the parity notes.
