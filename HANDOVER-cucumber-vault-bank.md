# Handover - Collect a Cucumber: Carry / Bank / Vault systems

**Date:** 2026-08-25 → 2026-08-26
**Place:** "collect cucumber game 8/25" (Studio save of place 116126086405931; MCP instance id `place:135680492327917`)
**IMPORTANT:** All edits live in the open Studio edit session - **save/publish in Studio** if you haven't.

---

## What was built (in order)

### 1. Carry system (`ServerStorage.ServerController.CarryService`)
- Breaking a cucumber has a chance to put a mini copy of it **on the killer's LEFT ARM** (welded Model, NOT a Tool - pickaxe stays equipped, mining keeps working).
- Odds by spawn Weight: `0.04 + 0.16 × Weight/35`, golden ×0.5. Boss/nuke/mid-tutorial/non-Template breaks excluded.
- Hooked in `BreakablesService.Break` right before `RecycleBreakable` (function-scope `GetModule` - **BreakablesService is AT Luau's 200-local limit, never add top-level locals there**).
- **Rarity upgrades:** while carrying, only a *strictly rarer* break rolls a pickup and swaps the arm cucumber. Rarity = `BreakablesService.CarryRarityOf(data)` (lower = rarer): Weight share of zone pool ÷ 2^(biome tier) × golden/mutation/lightning odds.
- `CarryingCucumber` player attribute drives the **DROP CUCUMBER** button (`StarterGui.CarryControls`, styled clone of the auto-hatch STOP button; client = `StarterPlayerScripts.CarryClient`).
- **Drop:** in the cucumber's home field → re-plants at your feet as a REAL breakable (`BreakablesService.SpawnCarriedAt`, full HP + bar, `Carried=true` exempts it from PruneZone). Anywhere else → flies home to a **random spot in its home field** (`BreakablesService.RandomZonePoint`) + green notif (no red refusal anymore).
- Home field = `workspace.SpawnArea.<index>` parts (Spawn=1 … Narmek=8), NOT `SlabZoneAt` (Spawn's slab covers the whole lobby).

### 2. Cucumber Bank (world build)
- Floating vault deck off the lobby's **back door** (red-carpet pier behind the hall, over the void, deck top y=2.8). Access: plaza SE corner → south apron (z≈-40) → back courtyard → gold "CUCUMBER BANK" arch.
- **Everything is runtime-generated** by `VaultService.BankBuilder` (child ModuleScript): `Build(levels)` rebuilds `workspace.CucumberBank` from 16 per-stall upgrade levels. The edit-time model is a placeholder AND the **style source**: Build samples Material/Color/MaterialVariant per part *kind* (trailing digits stripped) from the current bank - restyle ONE part of a kind in Studio and all copies follow. (User styled everything Plastic + "Inlet" variant.)
- User's 4 loose gray "Part" walls (entry header, 2 wings, east cap) at workspace top level are auto-refit each rebuild (position-identified: X>55; east cap X>150).
- 16 stalls, 2 rows; stall = NameSign, 4 red laser cylinders + invisible DoorZone (bounces non-owners 6 studs), single row of gold podiums along the back, green CollectPads 1 stud in front of each podium.

### 3. Vault gameplay (`ServerStorage.ServerController.VaultService`)
- Stall assigned per player on join; sign = "NAME'S VAULT (n/cap)"; lasers arm when owned.
- **Vault level = owner's `leaderstats.Rebirths`** (watched live; every rebirth = +1). Capacity = **6 + level** podiums (**2026-08-26: base 3→6**; one row only, 13 per floor). Ground floor exactly full at rebirth 7 → **floor 2 opens at rebirth 8**, floor 3 at 21, 4 at 34, 5 at 47; max capacity 56 at the rebirth-50 cap. Row re-packs so neighbors never overlap; deck/rails/carpet/east-cap stretch to fit. `Relayout()` detaches stored models → rebuild → `Rebind` → re-display (stored cucumbers survive). Verified: levels 0/7/8/50 → 6/13/14(+ladder)/56(4 ladders) podiums; live boot shows "(0/6)" signs and the deck + user east-cap refit in lockstep.
- **1.5× podium/pad scale-up (2026-08-26, later):** pedestals now 3.6 dia × 3.0 tall, collect pads 3.3×3.3, and the whole stall plan scaled with them so nothing overlaps: **base width 26, +3.75/level (max 56), depth 13→19.5**, podium row at d=15.9, pads at d−4.45 (1-stud podium gap kept), spacing eases 4.65→3.9, edge margin 4.8 (outermost podium stays 0.6 off the shared walls → 3.1 studs to the neighbor's space through the 2.5 wall). Deeper stalls keep upper-floor pads 3.0 studs clear of the ladder hole (at depth 13 they'd overhang it). Overlap audit at levels 0 / mixed / 8 / all-50: every podium-podium, pad-pad, wall, hole, and lever gap positive (tightest = 0.35 between podiums at rebirth 7). Live-verified: deposit sits on the taller podium (+0.2), pad collection works.
- **Per-podium E-prompt** (`PodiumPrompt` on each Pedestal): empty+carrying = Store on THAT podium; occupied+empty-handed = Take Back; occupied+carrying = **Replace** (swap arm ↔ podium). Titles retitled live from the owner's carry state.
- **Display card** (BillboardGui, SaB style): **[X] NAME** white (bare level number, **[MAX] at level 20**; prefix added 2026-08-26) / MUTATION magenta (only if mutated - no rarity line by design) / **$rate/s yellow** / **$value green**. Mutated cards are taller + higher.
- **Money pads:** earnings ACCRUE per cucumber ("Collect / $N" label); owner steps on the pad to collect (verified exact amounts). Accrued survives relayouts and follows the record. **2026-08-26:** accrual ticks 5×/s at rate×actual-dt (same $/s, labels count up smoothly; profile writes stay ~1s); collect grants floor(accrued) and KEEPS the sub-dollar fraction; feedback = 3D cash SFX `rbxassetid://120891770644830` at the pad (green "COLLECTED" notif removed, user call).
- **Cucumber upgrades (R-prompt** on each stored cucumber, coexists with E): `money/s = base × 1.18^(Level−1)` (`CarryService.EffectiveRate`), `cost = baseRate × 500 × 1.35^(Level−1)` **Cukes** (`CurrencyHandler.CheckIfEnough` + `RemoveCurrency`), **max level 20**. Prompt simplified 2026-08-26: just **"Upgrade" + "N Cukes"** (level/income projections removed; level now lives on the card's [LVL X] line; max = "MAX LEVEL" / blank); hidden while carrying (Replace owns that state). Level rides in the record → survives take-back/replace and raises the vendor sale price.
- Value everywhere = `CarryService.ValueOf` = floor(EffectiveRate × 250) - single source of truth.
- **Client zoom:** `StarterPlayerScripts.VaultTextClient` - standing in a stall renders THAT stall's card/pad texts 1.5× (client-only, exact restore on exit).

### 4. Sell vendor (`ServerScriptService.SellVendorServer` + `CucumberVendorClient`)
- Dialog option is now **"I have a cucumber to sell"** - sells the ARM cucumber at `CarryService.ValueOf` via new `SellCarried` RemoteFunction (returns {Ok, Coins}; client shows the +cash popup). Old sell-all-Cukes option removed; `SellAll` remote + legacy window left intact.
- Gotcha fixed there: `SellCooldown` declaration moved ABOVE both RemoteFunction closures (Lua upvalue-ordering trap - a later local is silently captured as nil global).

### 5. Lever security + stealing (2026-08-26)
- **Security lever** in every stall: `BankBuilder` clones `ReplicatedStorage.Lever` → `VaultLever`, placed between the podium row and the gate (east side, clear of the door + west ladder column; its unused `ActivateRoll` prompt is stripped). Countdown BillboardGui (`LeverTimer` on `LeverHinge`) + `LeverPrompt` are added by `VaultService.Rebind` every rebuild.
- **Lock cycle:** stalls start LOCKED for `SECURE_DURATION = 300`s on assign; owner pulls the lever (`VaultService.PullLever`) to re-lock for 5:00 (works early too). While locked: lasers visible, DoorZone bounces intruders, ball green, card "🔒 LOCKED M:SS". On expiry (1s security tick in Initialize): lasers drop, door open, ball red, card "🔓 UNLOCKED! PULL LEVER!", owner notified.
- **Stealing:** while a stall is unlocked, every stored cucumber's `StealPrompt` (hold **F** 1.5s, created in DisplayOn next to the R upgrade prompt) arms. `VaultService.Steal` puts it on the thief's arm via `CarryService.Restore` - normal carry from there (teleports blocked, walk it home, bank it via own podiums). Accrued pad money is zeroed on steal. Victim gets a 🚨 notif. No victim-side recovery yet (per user).
- **Server anti-cheat in `Steal`:** `IsSecured` check is the authority (locked ⇒ refuse + `warn` telemetry, regardless of client prompt state), plus thief-at-podium distance check (≤14 studs of the Spot, warn on fail), empty-hands check, owner/self check, 1s per-player rate limit (`LastSteal`).
- `StripPodiumAttachments` now sheds EarnBillboard/StealPrompt/UpgradePrompt whenever a model leaves a podium (take-back/replace/steal) - also fixes the old lingering-UpgradePrompt-on-arm quirk.
- Verified in a 2-player playtest: secured steal blocked, far steal blocked, real steal + re-bank in thief's vault, lever re-lock, non-owner lever refusal, relayout survival (timer carries through a rebirth rebuild).

### 6. Tutorial bank arc (2026-08-26)
- Tutorial extended 6 → **8 macro-steps** (`TutorialClient`, progress pill now n/8): after the pet-equip/close steps, a state-driven **bank arc** - catch a cucumber on your arm → carry it to your vault stall → store on a podium (completion = the stall's `Stored` folder gaining a child) - then a **lever step** (money-pad hint banner 3.5s, then "pull your LEVER", completion = the replicated `VaultLeverPulls` player attribute ticking up). Outro gained an `OutroSteal` banner ("vaults unlock every 5 mins… raid unlocked vaults!").
- **Guaranteed catch:** mid-tutorial breaks are carry-excluded, so the client fires `TutorialProgress:FireServer("wantcarry", 0)` (gift-style 3s retry); TutorialProgressServer validates (tutorial running + empty hands) and sets `TutorialCarryPending` on the player; `CarryService.TryAwardFromBreak` lets that attribute bypass BOTH the tutorial exclusion and the odds roll, consuming it on award.
- **New player attributes from VaultService:** `VaultStallId` (set on assign, cleared on release - client finds `workspace.CucumberBank.Stalls.Stall_<id>`), `VaultLeverPulls` (increments in PullLever). Vault-lock-expired notif is now suppressed while DoneTutorial is false.
- **Funnel renumbered:** TutorialProgressServer steps 7 `StoredInVault`, 8 `LockedVault` (MAX_CLIENT_STEP 8); ServerNetwork's completion log moved 7 → 9 `TutorialCompleted`. Client resume clamp 0..8. Streaming-safe arrows: stall targets re-resolved every tick, long-range waypoint = the bank `ArchBeam`; 10s no-stall bail so a full server can't hang the tutorial.
- Verified end-to-end in a forced-replay playtest (early steps fast-forwarded, bank arc played for real: wantcarry arm → strike-to-catch → guidance handoffs sign→pedestal→lever → deposit → pull → outro → gui teardown). **ForceTutorialOnJoin reset to false after testing.**
- **Rework (same day, user request): catch-first opening.** Step 1 now runs until a cucumber actually lands on the ARM (not just any break): the arrow targets sliced cucumbers (lowest HP) and `TutorialCarryPending` in `CarryService.TryAwardFromBreak` grades the catch by what broke - **name contains "Slice" = 100%, name exactly "Cucumber" = 75%, anything else = 25%** - and a missed roll KEEPS the flag armed, so they smash until one sticks (banner flips "smash that cucumber" → "Keep smashing - CATCH…" after the first break). Step 2 then sells THAT carried cucumber: the old SELL-teleport step was removed (teleports are carry-blocked + CarryClient hides the button row), replaced by a walk to the Cucumber Vendor → "I have a cucumber to sell" (`SellCarried`; `SellVendorServer` now fires `SellCompleted` on carried sales - was legacy-SellAll-only - which is the step's completion signal). Losing the cucumber en route (drop/death/resume) re-arms the catch and points back at the field. Funnel step 2 renamed `CaughtCucumber`; bank-arc banner now reads "Catch ANOTHER cucumber - this one's for your VAULT!". Verified in a second forced replay: tree break missed at 25% and kept the flag armed, slice caught instantly, drop-fallback re-caught, sale paid 750 and advanced, bank arc + lever + outro completed clean.
- **Rarer-swap mid-tutorial (2026-08-26):** CarryService's mid-tutorial gate lets ALREADY-CARRYING players through (`... and not Carrying[plr]`), so the strictly-rarer swap path works mid-tutorial at normal odds (empty-hand tutorial breaks stay carry-excluded unless pending). Verified live with DoneTutorial forced false: Slice Stack carry swapped to Cucumber Tree on a tree break. The tutorial's banner callout for this ("Smash a RARER cucumber…", STRINGS.RarerSwap) was **removed same day by user request** - the mechanic still works, it's just untaught.
- **Banner position (2026-08-26):** a while-carrying reposition (banner dropped to y=36% to dodge the CarryControls cluster) was added then **REVERTED same day** - the user saw the banner "move to the middle" and wants it fixed at its resting spot (y=20%) at all times. In practice the rendered carry cluster is small (~y −28..67) and clears the resting banner on real viewports, so no dodge is needed. The banner now never moves.

### 7. Misc fixes
- **Carpet seam (2026-08-26):** the walkway `Carpet` used to start at x=98 while `ApronCarpet` ended at 97, leaving a 1-stud strip of bare deck at the bank entrance (user reported it after the deck grew). Both now meet exactly at x=97 at the same y (2.88); verified 0.00 gap at level 0 and all-level-50.
- **Boss bar** hidden across the whole lobby→courtyard→bank route (`BossBarClient.inBank`: static courtyard box x30..100/z-55..50 + live DeckSlab footprint, looked up per call since the deck regenerates).
- Camera left in Scriptable once (user couldn't orbit) - fixed; framing tools must restore `CameraType = Fixed`.

---

## Backups / revert
| What | Where |
|---|---|
| Lobby (Area 1) | `backups/LobbyArea1_backup_2026-08-25.rbxm` + `ServerStorage.LobbyBackup_20260825` |
| Bank v1 | `backups/CucumberBank_v1_backup_2026-08-26.rbxm` + `ServerStorage.CucumberBankBackup_v1` |
| Bank v2 | `backups/CucumberBank_v2_backup_2026-08-26.rbxm` |
| User's 4 walls | `ServerStorage.BankUserWalls_v1_backup` |

Full revert of bank/vault: delete `workspace.CucumberBank`, the `VaultService` module (incl. `BankBuilder` child), `VaultTextClient`, and CarryService's "Vault interop" block (Get/Take/Restore/ValueOf/EffectiveRate). Carry system revert: delete CarryService/CarryClient/CarryControls + the marked hooks in BreakablesService/BreakablesClient.

---

## Known gaps / next steps
- ~~NO PERSISTENCE~~ **DONE (2026-08-26, VaultService v5):** vault contents SAVE. `Data.VaultCucumbers` on the profile ({Spot, Zone, Name, Rate, Level, Rarity, Mutation, Accrued} per cucumber; default added in `UserData`). **Write-through:** `SaveVault(stall)` rewrites the list on Deposit/TakeBack/Replace/Steal/Upgrade/Collect AND each 1s accrual tick (GetUserData returns the live profile table - cheap; ProfileService owns DataStore cadence; no save-on-leave hook needed, ReleaseStall can wipe freely). **Restore:** `LoadVault(plr, stall)` on stall assignment - waits for PlayerData, resolves types via new `BreakablesService.FindType(zone, name)` (declared beside CarryRarityOf, no new top-level locals), builds display models via new `CarryService.BuildFromTemplate(typeDef)` (reuses BuildCarryModel), places at saved spots (first-free fallback); restores silently (welcome-back notif removed same day, user call). Out-of-capacity spots no-op until the rebirth relayout re-displays. Caveat: golden tint/mutation VISUALS don't survive (stats incl. Mutation tag + Rate do). Verified across two playtest sessions: Lv5 Vined (Spawn) + Prickly (Desert) restored to exact spots with accrued money intact.
- 16 stalls vs `Players.MaxPlayers = 60` - players 17+ get no vault.
- Laser door push never tested with a 2nd player physically touching it (steal/lock logic IS multiplayer-tested, but the Touched bounce itself wasn't).
- No victim-side recovery of stolen cucumbers yet (explicitly deferred by user).
- Tutorial-ending-with-vault-deposit: DONE (see §6).
- Physical podium cap: one row fits max 13 podiums (reached at rebirth 10) though capacity formula keeps counting.

## Testing gotchas (Studio)
- Pets auto-farm and attribute kills to the player → **organic carries proc mid-test** and pollute state.
- Cukes/Coins drift passively (thousands/s on the dev profile) - verify grants by instrumenting `CurrencyHandler.AddCurrency` in the live VM, never by balance deltas.
- Script edits do NOT reach an already-running playtest; `execute_luau` requires are isolated (use `eval_server_runtime`/`eval_client_runtime` for live require-cache access).
- Playtest screenshots: game's DepthOfField blurs scripted cameras; Studio window must be visible/unminimized.
- Fuller notes live in auto-memory: `collect-a-cucumber-game.md` (loads automatically in new chats).
