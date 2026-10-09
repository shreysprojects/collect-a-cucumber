# Time skips, portal reward spinner, pet bolts (2026-09-23)

User: "make a time skip system for cash and strength. it should calculate how much user is earning per second
from cash, and how much they would earn per second if on benchpress. from other open place 'zombie cucumber
game' take: 1. pet damage bullet system (the bullets from pets that hit cucumbers - I want those bullets to hit
zombies in new map cucumber game) 2. portal rewards spinner system - holds all rewards from this game
including time skips (it just says the cash value / strength value given outright) 3. shop time skip purchase
system for each currency (cash and strength instead)."

Place: New Map Cucumber Game (87967102884366). Source place read only: Zombie Cucumber Game (82764986030640).
NOT saved / published by me. Sources: `timeskip/src`, `spinner/src`, staged copies + installers in
`../stage-2026-09-23b/` (install_new.lua manifest `_install.json`, `install_timeskip_cards.lua`,
`patch_peteffects.js`). Transferred GUI: `spinner/transfer/SelectingReward_from_zombie_2026-09-23.rbxm`
(export_rbxm -> Studio content dir -> `game:GetObjects("rbxasset://SelectingReward_transfer.rbxm")`).

## 1. Time skips (port of TimeSkipRateService / VaultTimeSkipService)
`ServerStorage.TimeSkipService` (ModuleScript)
* `CashRate(player)` = `player.Data.CashPerSec` (IncomeService's live total: placed cucumbers x modifiers + pet
  income); fallback = the sum of the player's placed cucumbers' `Rate` attributes while IncomeService is not
  running. 0 with nothing placed.
* `StrengthRate(player)` = strength per second IF on the bench: `GymService.StrengthPerRep(data)` (2^(bench
  level-1) x headband multiplier) x `GymService.RepSpeed(data)` / `CLIP_LENGTH` (2 s per clip loop at 1x,
  BenchServer). Deterministic: no potion / temporary boosts in a quote (like the zombie game's quotes).
* `Quote(player, seconds)` -> `{Cash, Strength, CashRate, StrengthRate, Seconds}`; `GrantCash` / `GrantStrength` /
  `Grant(player, "Cash"|"Strength", seconds)` = the only grant paths (DataService.Increment + RequestSave +
  a toast through `Remotes.ItemEvent` {Kind = "Toast"}). A 0 quote grants nothing and says why.
* `ServerScriptService.TimeSkipServer`: `Remotes.TimeSkipQuote` (RemoteFunction, 10 quotes/s per player) +
  Studio hook attribute `TimeSkipDev` = `cash:<s>` / `strength:<s>` / `quote:<s>`.

## 3. Shop time-skip cards (per currency)
v2 (user: "put the values in here replacing +x labels, do not mention duration, do not mention timeskips, delete the
new ones you made"): the EXISTING pack cards of `StarterGui.CucumberMenus.ShopPanel` are the products. Card N of
the strength / cash section sells the N-th duration of the zombie store's ladder (1 min, 5 min, 30 min, 5 h,
1 day, 1 week) and its Amount label shows ONLY the value the buyer would get ("+1.6M" / "+$2.93M"), refreshed by
`ShopController` (patched) from `Remotes.TimeSkipQuote` once at start, on every open and every 5 s while open.
Attributes: `TimeSkipSeconds`, `TimeSkipCurrency` ("Strength" / "Cash"), `ProductId` 0 (= "SOON": create the 12
Developer Products, paste the ids, no code change); the old StrengthAmount / CashAmount attributes are gone.
`ShopProductsServer` (patched) grants `TimeSkipSeconds` receipts through `TimeSkipService.Grant` (the quote at
receipt time, flat). The v1 StrengthSkips* / CashSkips* sections were deleted (`install_timeskip_cards.lua` v2).
Verified: 12 cards read +1.6M .. +16.1B and +$2.93M .. +$29.5B on the test profile, headers unchanged, no
leftover sections.

## 2. Portal reward spinner (port of MinigameCompletionService/Client + SelectingReward)
* `StarterGui.SelectingReward` = the zombie place's reel GUI (Place1 design) with a rewritten
  `SelectingRewardClient`: tiles show `cash_<d>` as "+$X Cash" (HUD cash icon), `strength_<d>` as "+X Strength"
  (arm icon), `item_<Key>` as "+1 <Name>" with a ViewportFrame of the real item model; rarity text per tile;
  the same 6 s Quart-out reel with EggClick ticks, winner flash + wobble, 3 s reveal.
* `ServerStorage.RewardSpinnerService`: weighted POOL of 22 rewards (cash 1m..1h, strength 1m..30m, the nine
  drop items; Void Seed rarest), `Award(player, source)` picks + LOCKS the payout (TimeSkipService quote at
  pick time; a cash prize with nothing placed swaps to the same-duration strength prize), fires
  `Remotes.RewardSpinner` {Kind = "Spin", Token, Selection} 1.4 s later, grants on
  `Remotes.RewardSpinnerFinished(token)` (or after 30 s if the client never answers), then {Kind = "Granted",
  Text}. Studio hook: `Remotes.RewardSpinner` attribute `RewardSpinnerDev` = `spin[:<id>]`.
* `ServerScriptService.RewardSpinnerServer` starts it and WRAPS `PortalService.ReturnHome`: a return with
  reason "Finished" (obby chest, Avalanche / Lava Run / Bloxout completion pads, the Wild West hunt) awards one
  spin. PortalService itself is untouched.
* `StarterPlayerScripts.RewardSpinnerClient`: confetti shower + win sting, then the reel, then Finished; the
  Granted message becomes a Notify toast + cash-register sounds.

## 1. Pet bolts
`PetEffectsClient` (patched from the pets-system mirror, which matched live byte for byte): the Shot effect is
now the zombie game's pet bolt (BreakablesClient.petBolts): a 0.4-stud neon ball that ACCELERATES into the
zombie (Quad In) while shrinking to 0.2, trailing a soft ribbon `Trail` (0.18 s, light emission 0.6, width
1 -> 0.2, transparency 0.2 -> 1). Colours = the zombie pale-green ball / green ribbon blended 50 % with the
pet's rarity glow. Trails are built once per pooled part and enabled only during a flight (`TrailOf`,
disabled again in `ReleasePart`). Damage / targeting unchanged (PetCombatService -> ZombieAPI.Damage).

## Verified (solo playtest, PetTest profile, 2026-09-23)
Boot lines for TimeSkipServer / RewardSpinnerService / RewardSpinnerServer ("ReturnHome wrapped") /
RewardSpinnerClient, no errors. Quote 1 h for the test profile: cash 175.9M (48,849/s = Data.CashPerSec),
strength 95.8M (26,624/s = 1664 per rep x speed 32 / 2 s, bench level 8 + Champion Band). Shop (v2): the six
strength cards read +1.6M / +7.99M / +47.9M / +479M / +2.3B / +16.1B and the six cash cards +$2.93M .. +$29.5B,
all "SOON" pills, headers unchanged, no leftover sections (screenshot taken). Spinner: dev `spin:cash_5m` locked 14,654,822, the client ran confetti + reel,
Finished came back 14 s later and the server logged "won cash_5m (14654822)"; the reel's LastReward attribute
= cash_5m; screenshots caught the reel mid-spin ("SELECTING REWARD..." with a Golden Seed model tile and
"+24M Strength" tiles) and the "+1 Zombie Egg!" reveal. Bolts: six fake Shot events -> six pooled parts each
gained a BoltTrail, no warnings. NOT exercised: a real portal completion end to end (the wrapper's only
logic is `reason == "Finished"` -> Award) and a Robux receipt (all ProductIds are 0).
