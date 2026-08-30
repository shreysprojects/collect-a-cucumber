# Progression & Economy Design Principles for Roblox Simulator Games
### Research report — Grow a Garden, Steal a Brainrot, Pet Simulator 99, Bee Swarm, Mining Simulator 2, Arm Wrestle Simulator, and genre-wide analyses
*(compiled 2026-08-28 for the Collect a Cucumber economy redesign)*

---

## Part A — Underlying Principles (with evidence)

### A1. The first purchase happens in the first 60 seconds; the first complete loop in under 5 minutes
- **Grow a Garden**: you spawn with exactly **20 Sheckles — enough for 2 carrot seeds (10 each)**. Carrots grow in **~5 minutes** and sell for ~18-22 (≈1.8× ROI). The entire loop (buy → plant → wait → harvest → sell → buy more) completes inside the first 10 minutes.
- **Steal a Brainrot**: you spawn with **$100** and the game's explicit first task is "buy a Noobini Pizzanini" (a ~$25 Common) — the game literally doesn't "start" (you're steal-protected) until you complete the first purchase. Commons cost $25-$1,750 and immediately generate $1-14/sec, so income begins within the first minute.
- **Pet Simulator 99**: the first egg (Cracked Egg) costs **90 coins** — hatched within the first ~30 seconds of breaking objects. Area 2 costs **900 coins** (~2-4 min of play).
- Genre-wide guidance (Roblox devforum / production guides): "the first few purchases should happen within 30 seconds of joining."

**Principle:** the tutorial *is* the economy. The first spend should be forced, near-instant, and visibly multiply output.

### A2. Front-loaded exponential ladders: ~2.5-3.5× cost per step, with step *time* doubling
PS99's actual area costs run at **≈2.5-3.5× per area**, and Steal a Brainrot's rebirth cash requirements run **≈3-5× per level**. Because income also grows exponentially (new pets/brainrots/areas), the *time per step* only roughly doubles — early steps take minutes, late steps take hours. This is the core trick: **costs and income race on parallel exponentials; the gap between them (= time) is the only thing the designer actually tunes.**

### A3. Numbers are fireworks; ratios are the game
Pet Sim 99 displays K → M → B → T → Qa → Qi → … and flips to **scientific notation (e.g. 1.23e141) past ~999.99Z**. Players routinely reach Qa-Dc (10¹⁵-10³³). Nothing about the *gameplay* changes at those magnitudes — kill-time and upgrade cadence stay constant. Inflation is pure spectacle; it makes returning players feel powerful and makes screenshots shareable.

### A4. Inflation firewalls: reset or partition currencies before they rot the economy
- PS99: **coins reset per world** (Normal/Tech/Void coins are separate); Diamonds are the stable cross-world trading currency.
- Steal a Brainrot & Mining Simulator 2: **rebirth wipes cash** (MS2 gives +10× coin multiplier per rebirth; tools double in price after each rebirth).
- Grow a Garden: no reset, but the **real** economy runs on rare *items* (pets, mutated crops), not Sheckles.

**Principle:** let the display number explode, but keep one hard-currency / item economy insulated from it.

### A5. Passive accrual + visible "delta" on return (the single biggest retention lever of 2025)
Grow a Garden's defining mechanic: **plants grow while you're offline**, so every login shows a before/after payoff. asimo3089's widely-shared analysis thread names this first. Offline progress guarantees a reward on Day-2 login; being online is strictly better, so it doesn't cannibalize sessions.

### A6. Timed scarcity loops (restock FOMO)
- GAG seed shop restocks **every 5 minutes** with random stock (rare seeds have low stock-chance: e.g. Legendary Egg 12%, Mythical 7%, Bug Egg 3% chance per restock); the pet-egg shop restocks **every 30 min**.
- Weathers/events are **server-synced globally** — a thunderstorm happens in *every* server at once, creating platform-wide spike moments.
- Weekly countdown-timed live events (Saturdays, cinematic cutscenes) concentrate the audience.

**Principle:** a short repeating timer ("what's in stock *now*?") converts idle waiting into check-in behavior.

### A7. Jackpots are engineered as *public* events
- Steal a Brainrot: when a **Brainrot God**-tier spawns on the conveyor, **its name is announced out loud to the server**; Secrets (<0.001%-0.05% spawn chance) cause server-wide frenzies.
- PS99: rare/huge hatches "light up global chat"; huge odds are ~**1 in 500K-1M**, boostable via displayed multipliers (Huge Party weekends: 3×/6×/12×).
- GAG: lightning strikes (Shocked ×100) are visible, physical, and hit *someone's* garden during a shared storm.

**Principle:** the 1-in-N moment must be seen by N players, not just the winner. Announce + VFX + displayed odds.

### A8. Rarity curves converge on "~1% chase item per container, ~50/30/15/4/1 shape"
Grow a Garden's egg tables are remarkably consistent: 3-6 pets per egg, top pet at **1% (Tiger, Dragonfly, Queen Bee)** or **0.25-0.5%** for super-chase (Disco Bee 0.25%), mid-pets 4-10%, floor pets 30-45%. Steal a Brainrot's conveyor mirrors this across 8 rarity tiers. The EV of a container is dominated by its floor; the *appeal* is dominated by its 1%.

### A9. Additive-inside-brackets stacking tames multiplicative explosions
Grow a Garden's actual crop formula:

```
Value = Base × (Weight/BaseWeight)² × Variant × [1 + Σ(mutation multipliers) − N]
```

- **Variant** is one exclusive slot: Normal ×1 / Silver ×5 / Gold ×20 / Rainbow ×50 (only one can apply).
- **Environmental mutations stack additively inside the bracket**, not multiplicatively: Shocked(100) + Frozen(30) + Bloom(40) on a Rainbow crop = 50 × [1 + 170 − 3] = **×8,400**, not 50×100×30×40 = ×6,000,000.
- Mutation count is capped (~4-5 per crop); many mutations are mutually exclusive or upgrade-replace (Wet+Chilled → Frozen).

**Principle:** one big multiplicative slot for identity ("it's RAINBOW"), additive stacking for everything else, hard cap on stack count, and top-end mutations gated behind rare *events* rather than rerollable RNG. Jackpots then equal minutes-to-hours of income — thrilling but not economy-breaking.

### A10. Deterministic craft-up ladders act as pity systems and dupe sinks
PS99: Golden = fuse normals, Rainbow = fuse goldens, **Shiny = 125 normal copies** end-to-end; enchant duplicates suffer diminishing returns (100% → 60% → 38.3%). Pure-RNG games (GAG) skip pity but keep odds *displayed* and floors valuable. Explicit "guaranteed after N" pity is rare in Roblox simulators — **quantity-based crafting is the genre's pity system** and doubles as the dupe sink that keeps hatching worthwhile forever.

### A11. Rebirth: reset the cheap stuff, keep the identity stuff, pay a permanent multiplier
- PS99 (max 9 rebirths): resets **areas + coins**; keeps **pets, diamonds, items, enchants**; each rebirth = **+75% permanent pet damage** plus a feature unlock (teleport, auto-hatch, pet teams, new world…).
- Steal a Brainrot (19 rebirths): resets cash + brainrots; rewards **+1× income multiplier per level**, +1 base slot, +10s base-lock, exclusive gear; cash requirements scale ~3-5×/level from $500K to $30Qa.
- Mining Simulator 2: rebirth cost ≈ 10M×(n+1) coins, +10× coin multiplier each.
- Arm Wrestle Simulator adds a **second prestige layer** (Super Rebirth at rebirth 31+).

**Principle:** rebirth must make the replayed content 2-5× faster each loop, and each rebirth should also unlock a *feature*, not just a number.

### A12. Overlapping goal ladders: something completes every 5-15 minutes, forever
Every studied game runs 5-8 concurrent progression tracks so a near-term goal always exists: **areas** (minutes-hours), **tools/pickaxes** (minutes), **eggs/pets** (minutes + timers), **collection index/mastery** (passive), **quests/dailies** (session-scoped), **rebirth** (hours), **events** (weekly). When one track's next step is 3 hours away, another's is 4 minutes away.

### A13. A social/risk layer multiplies retention beyond any tuning
Steal a Brainrot's stealing loop turns the idle-income game into player-vs-player theater; analysts credit this tension loop — not the economy — for its record CCUs.

### A14. Time-gating shifts from cost-gating as the game matures
GAG gates late progression with **grow timers and hatch timers** (Common egg 10 min → Bug/Jungle eggs 8 h), not just prices. This caps no-life grinding, protects the economy, and creates natural return appointments.

---

## Part B — Concrete Numbers Found

### B1. Pet Simulator 99 — area unlock costs (areas 2-25)

| Area | Cost | Ratio vs prev |
|---|---|---|
| 2 | 900 coins | — |
| 3 | 2.5K | ×2.8 |
| 4 | 8K | ×3.2 |
| 5 | 20K | ×2.5 |
| 6 | 60K | ×3.0 |
| 7 | 150K | ×2.5 |
| 8 | 400K | ×2.7 |
| 9-25 | 1 → 750,000 Gold Bars | ×2.2-2.7 per area |

274 areas total across 4 worlds; **coins reset per world**. First egg 90 coins; ~Area 20 ≈ 1 hour of play (estimate).

### B2. PS99 pet variants, odds & sinks
- Variant chain (craft-up): Golden ≈ ×1.5, Rainbow ≈ ×3, Shiny ≈ ×5 (sources conflict on exact values; the shape "each variant tier ≈ 2-3× the last, built from ~5 copies of the previous tier, 125 normals → 1 Shiny" is consistent).
- Huge pets: **~1/500K-1/1M base**; golden huges 3-5× rarer; rainbow ~10× rarer (~1/10M) (player-estimated).
- Luck stack (displayed %): Lucky +200%, Ultra Lucky +500%, Mega Lucky +800% (Robux); weekend events 3×/6×/12×.
- Enchant dupes: 100% → 60% → 38.3% effectiveness.
- Notation: K/M/B/T/Qa/Qi… → scientific past ~999.99Z. Max 9 rebirths, +75% damage each.

### B3. Grow a Garden — economy tables
**Start:** 20 Sheckles; carrot seed 10 (sells ~18-20, 5-min grow); seed shop restock 5 min; seed prices run 10 → **315M**; multi-harvest crops are the early compounding purchase.

**Variant slot (exclusive):** Silver ×5 · Gold ×20 · Rainbow ×50. Natural roll ≈ **1% gold, 0.1% rainbow** (player-estimated).

**Environmental mutations (additive stack, cap ~5):** Wet/Chilled ×2 · Glossy ×10 · Frozen ×10-20 · Radioactive/Toxic ×15 · Gold ×25 · Disco ×25-30 · Starlit ×35 · Bloom/Moonlit ×40 · Frostbite ×45 · **Shocked ×100** (lightning) · Eternal ×110 · Celestial ×120 · **Voidtouched ×135** · Abyssal ×240 (combo). Blood Moon-type events raise rare-mutation odds ~3-5×.

**Egg shop (30-min restock; price / stock-chance / hatch timer / top-pet odds):**

| Egg | Price | Stock chance | Hatch time | Chase pet odds |
|---|---|---|---|---|
| Common | 50K | 100% | 10 min | (3 pets @ 33%) |
| Uncommon | 150K | 54% | 20 min | 25% each |
| Rare | 600K | 24% | 2 h | Monkey 8.3% |
| Legendary | 3M | 12% | 4 h | Polar Bear 2.1% |
| Mythical | 8M | 7% | 5 h | Red Fox 1.8% |
| Bug | 50M | 3% | 8 h | Dragonfly **1%** |
| Jungle | 60M | 2% | 8 h | Tiger **1%** |
| Anti Bee (craft) | — | — | 4 h | Disco Bee **0.25%** |

Elegant curve: price ×3-6 per tier, stock-chance halves, hatch timer grows, chase odds shrink 33% → 0.25%.

**Earning rates:** ~1.1M Sheckles per focused 2-hour session at base mid-game stats; ~5M+/2h with boosts; overnight AFK ≈ 1.2M.

### B4. Steal a Brainrot — rarity/income and rebirth tables
**Rarity tiers (buy price → income/sec):**

| Tier | Price range | Income/s |
|---|---|---|
| Common | $25-1,750 | $1-14 |
| Rare | $2K-9.7K | $15-75 |
| Epic → Mythic | (interpolating) | ~$100-15K |
| Brainrot God (~97 units) | $5M-77M | $17.5K-320K |
| Secret (~188-270 units) | $6M-$400B | up to ~$950K/s for named tops |

Roughly **×4-6 price and ×5 income per tier**; ~10-12 units per tier. Secret conveyor spawn chance **<0.001%-0.05%**; Brainrot God spawns name-announced server-wide.

**Mutations (one slot, income multiplier):** Gold ×1.25 · Diamond ×1.5 · Bloodrot ×2.5 · Candy ×4 · Lava ×6 · Galaxy ×7 · Yin Yang ×7.5 · Radioactive ×8.5 · Cursed ×9 · Rainbow/Divine ×10 · Cyber ×11 · Disco ×12 · Crystal ×13.

**Rebirth ladder (19 levels):** $500K → $1.5M → $12.5M → $35M → $100M → $350M → $1B → $5B → $12.5B → $125B → $800B → $3.5T → $14T → $40T → $100T → $1Qa → $2Qa → $10Qa → $30Qa (≈ ×3-5/level), each granting +1× income multiplier, +1 base slot, +10s base lock.

### B5. Others
- **Mining Simulator 2:** rebirth ≈ 10M×(n+1) coins; +10× coin multiplier per rebirth; tool prices double post-rebirth; block HP ×1.5-1.8 per depth layer.
- **Bee Swarm Simulator:** months-long marathon; low-rarity bees stay useful by design.
- **Arm Wrestle Sim:** +15% strength per rebirth; Super Rebirth meta-prestige at rebirth 31+.
- **Time-to-late-game (estimates):** PS99 world 1 ≈ 20-40 h active average; GAG "seen everything core" ≈ 2-4 weeks casual; SAB rebirth 19 ≈ weeks-months, but tier-8 spectacle is *witnessed* in session one. Genre norm: **the ladder's top is 50-100× further away than the point where the player has seen every mechanic (~2-5 h).**

---

## Part C — Recommended Progression Skeleton (click-to-mine collector, 8 areas)

Targets honored: Area 2 @ 5-10 min · A3 @ 20-35 min · A4 @ 1-1.5 h · A5 @ ~3 h · A6 @ ~6 h · A7 @ ~10 h · A8 @ 15-20 h; **1M cumulative before hour 1; trillions by late game.**

### C1. The control law
1. **Kill-time invariant:** a cucumber dies in 3-6 hits with the area's mid pickaxe, 1-2 hits with its top pickaxe. (~12-20 kills/min active.)
2. **Parallel exponentials:** value ×25/area, HP ×15/area (HP grows *slower* than value so each area feels more lucrative).
3. **Time doubling:** each area takes ≈2× the previous one's incremental time — that alone produces the 7 min → 17 h schedule.
4. **Spend split:** area unlock ≈ 50-60% of an area's expected earnings; pickaxes ≈ 25%; eggs ≈ 20%. If a playtest misses a time target, move the *unlock cost*, never the value/HP ratios.

### C2. Per-area master table (recommended starting values — tune ±30%)

| Area | Cuke base value | Cuke HP | Top pickaxe dmg | Top pickaxe cost | Egg cost | Area unlock cost | Cumulative time |
|---|---|---|---|---|---|---|---|
| 1 | 1 | 3 | 5 | 150 | 75 | — | 0 |
| 2 | 25 | 45 | 75 | 4K | 2K | **250** | ~7 min |
| 3 | 625 | 675 | 1.1K | 100K | 50K | **8K** | ~27 min |
| 4 | 15.6K | 10K | 17K | 2.7M | 1.25M | **280K** | ~1.2 h |
| 5 | 390K | 150K | 250K | 75M | 30M | **10M** | ~3 h |
| 6 | 9.8M | 2.3M | 3.8M | 2B | 750M | **400M** | ~6 h |
| 7 | 244M | 34M | 57M | 55B | 20B | **15B** | ~10 h |
| 8 | 6.1B | 512M | 850M | 1.5T | 500B | **600B** | ~15-20 h |

**Per-area ratios:** value ×25 · HP ×15 · pickaxe damage ×15 · pickaxe cost ×27 · egg cost ×25 · area unlock ×30-40 (front-load: ×25-30 for A2-A4, ×35-40 for A5-A8).
**Within each area:** 4-5 pickaxes at ×2-2.2 damage / ×3 cost each; first pickaxe of a new area affordable within ~2 minutes of arriving.
**Damage budget per area (×15):** ≈ ×5 from the pickaxe line + ≈ ×3 from the new egg's pets.
**Number checkpoints:** avg value ≈ ×1.7 base from rarity EV → Area 4 income ≈ 300-400K/min → cumulative crosses **1M around minute 50-65** ✓; Area 8 income ≈ 100-200B/min → **trillions within the first hour of Area 8** ✓.

### C3. Rarity curve (cucumber spawns)

| Rarity | Odds | Value mult | Presentation |
|---|---|---|---|
| Common | 84.9% | ×1 | — |
| Uncommon | 10% | ×2 | tint |
| Rare | 4% | ×5 | glow + sound |
| Epic | 1% | ×15 | particles, local ping |
| Legendary | 1/500 (0.2%) | ×50 | beam of light, server chat message |
| **Jackpot** | **1/1,500** | **×300** | server-wide announcement + screen shake + displayed "1 in 1,500!" |

EV ≈ ×1.70 base. Jackpot cadence ≈ one per 1.5-2 h of active play. Show the odds on the spawn banner.

### C4. Mutation tier table (GAG-style, on value)
**Variant slot (exclusive, rolled at spawn):** Normal ×1 (94.4%) · Silver ×5 (4%) · Golden ×20 (1.5%) · Rainbow ×50 (0.1%).
**Environmental mutations (additive: value × [1 + Σ(m−1)], max 3 stacked):**

| Mutation | Mult | Source |
|---|---|---|
| Wet | ×2 | rain event (common, server-synced) |
| Chilled | ×2 | snow event |
| Frozen | ×10 | Wet + Chilled combine |
| Charged | ×8 | thunderstorm ambient |
| **Shocked** | ×100 | direct lightning strike (announced) |
| Disco | ×25 | rare disco event |
| Voidshocked (endgame) | ×135 | limited-time events only |

**Guardrails:** one variant slot only; additive bracket, never raw multiplication; stack cap 3; top two tiers event-gated; theoretical max ≈ ×12,900 ≈ *tens of minutes to a few hours* of current income — a screenshot, not a retirement. Rule of thumb: **any single drop's value ≤ 2-3 hours of the player's current income rate.**

### C5. Eggs & pets
- 1 egg per area; 4-5 pets per egg: floor pet ~40%, mids 25/20%, chase **1%**, super-chase 0.25% in Areas 6-8 eggs.
- Pet damage multipliers within an egg: floor ×(area baseline), chase ≈ ×4-6 the floor. Egg EV ≈ 1.4× floor.
- **Variant craft-up as pity/dupe-sink:** 5 dupes → Golden (×2), 5 Goldens → Rainbow (×5 vs normal).
- Guarantee the Area 1 egg's best pet within the first ~10 hatches (secret pity).
- Equip 3 pets (+1 slot at rebirth / gamepass). *(Note: Collect a Cucumber uses 4 base + board upgrades.)*

### C6. Multi-system overlap & rebirth
Concurrent tracks: pickaxe (2-5 min cadence) · egg/pet (5-15 min) · area (doubling) · collection index (+2% permanent income per completed set) · daily quests (3/day, pay ~15 min of income) · weather/mutation hunting · CUCUMBER SMASH (appointment) · **rebirth**.

**Rebirth:** resets areas + cash; keeps pets, collection, gamepasses; grants **+100% income per rebirth (multiplier = 1+R)**; requirement ×3 per rebirth. Loop 2 ≈ ⅓ of loop 1. Converts the 15-20 h ladder into a 50-100 h retention tail.

### C7. First-session script (minute-by-minute)
0:00 spawn, arrow to first cucumber, 3 clicks = kill · 0:45 first pickaxe (forced, cheap) · 2:00 first egg → first pet, damage visibly jumps · 4:00 pickaxe 3 · **6-8:00 Area 2 gate opens** (celebrate hard) · 10:00 first Rare spawn glow · 15:00 Area 2 egg · 20:00 first weather event · **25-30:00 Area 3** · by session end (~30-40 min) the player has ~12-15 distinct reward moments.

---
*Sources: gagdata.com (mutations/stacking), mygagcalculator.com, growagardentradevalues.com, GameSpot GAG guide, asimo3089 design thread, playbrainrot.org, stealabrainrot.fandom.com, mitchcactus.co, rblxguide.com, eldorado.gg, progameguides.com, bloxodes.com (PS99 areas), rowatcher.com, marix.app, holdtoreset.com, pet-simulator.fandom.com, bloxcontrol.com, mining-simulator.fandom.com, arm-wrestling-simulator.fandom.com, ggwtb.com, Medium (Onett spotlight), game-ace.com, metablox.gg, skycoach.gg.*
