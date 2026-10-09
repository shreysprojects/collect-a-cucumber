# Cucumber Heist revamp: what was built on 2026-09-02, what is verified, what the owner must do

**Place:** `cucumber testing`, place id `93583372707682`, universe `10764881036` (a copy of the live *Collect a Cucumber*, place `116126086405931`). Nothing in this document touches the live game.
**Date of work:** 2026-09-02 (pre-backup 19:01 UTC, build phase to ~20:15 UTC, QA phase 20:17–21:20 UTC; the agent notes use UTC, local file times are UTC−4). The place is edited in the open Studio session and is **NOT saved or published** by the agents; the owner saves.
**Source spec:** the owner's "Hook audit, version 2 · Cucumber Heist · September 2026" (`SPEC.md`). It inventories sixteen retention mechanisms: (1) variable reward, (2) the luck moment, (3) near miss, (4) loss aversion, (5) collection with a book, (6) status display, (7) appointment timers, (8) endowed progress, (9) competence and autonomy, (10) social presence, (11) rivalry, (12) time investment that grows, (13) streaks and ladders, (14) mastery, (15) identity, (16) the character. It also fixes the screen-by-screen target ("The ideal game"), the store rules ("The store as a hook", "Lines we don't cross") and the tuning table ("Numbers to tune first"). Eight build agents (HEIST, PICKLE, FIELD, CLOCK, TUTORIAL, INDEX, HUD, STORE) implemented it under `BRIEF.md`; three QA agents (QA1 tutorial, QA2 field/clock/index/HUD/store/playtime, QA3 heist/pickling) tested it.
**Backups:** `backups/Revamp_2026-09-02/pre-<Service>.rbxm` (9 files, 15:01 local: Lighting, ReplicatedFirst, ReplicatedStorage, ServerScriptService, ServerStorage, SoundService, StarterGui, StarterPlayer, Workspace) = the untouched place BEFORE any agent edit. `backups/Revamp_2026-09-02/post-build-<Service>.rbxm` (same 9 services, 17:19 local) = the place AFTER the build and QA fixes. A pre-edit `.lua` mirror of every script also exists in the session scratchpad (`SP\src\`), but the scratchpad is temporary; the rbxm files are the durable revert point.
**Companion documents:** `GAME-MAP.md` (the pre-revamp map; its numbers for locks, catch chance, currencies, tutorial and HUD are superseded by this file), `HANDOVER-cucumber-vault-bank.md`.

---

## 1. Verification status (honest)

Every script compiles (`checkall.js`: 283 scripts, 0 failures, last run 21:07 UTC). One solo playtest ran (QA2, 20:19–20:46 UTC). No 2-player playtest ran. No human has looked at the screen.

| Slice | Owner agents | Status | Evidence |
|---|---|---|---|
| Field: catch roll, sizes, HP/value scaling, mutation announce, VOID, secret, combo meter, restock, Harvest Moon ×3, Sticky Hands, Field Restock, BIG GHERK | FIELD | **LIVE** (QA2 checks 1–12) | 100 breaks → 20 catches; 100 spawns → 21/64/15 sizes; chat "✨ … caught a NEON Cucumber! [1 in 1,619]"; secret paid 24,102,000 coins; restock 16→16 in 3.4 s |
| Clock: boot attributes, forced Golden Hour, stop, Dill chat lines, boss spawn/kill | CLOCK | **LIVE** (QA2 13–15); `ClockSpeedDev=60` cycle only PARTIAL (observer eval timed out) | `ActiveEvent=GOLDEN_HOUR` at the real :20 window; chip "✨ GOLDEN HOUR 1:57" |
| Index: attributes, discovery rewards, ladder, trail, panel | INDEX | **LIVE** (QA2 16–19) | +1,500 / +2,500 / +160,000 exact; `trail_green` at 10; panel "DISCOVERED 5 / 1,485" |
| HUD: boot layout, store gate, boss-bar gating, rebirth panel | HUD | **LIVE** (QA2 20–23) | chip (512,8) 276×29 at 1301×611; `TopSlotBottom=37` |
| Store: one currency, vault upgrade in Coins, leaderstats, gate, Starter Pack, Second Arm attribute | STORE | **LIVE** (QA2 24–28); "no Robux prompt before DoneTutorial" **STATIC** (29) | `AddCurrency{Cucumbers,100}` → +150 Coins; leaderstats = Coins/Rebirths/Steals |
| Playtime ladder (8 tiers) | HUD | **LIVE** (QA2 30) | claims +1,000 / +2,500 / boost / +15,300 / +5,000 / +10,000 (trail already owned) / +122,400 / Golden Cucumber |
| Heist loop: lock timer, klaxon, UNPROTECTED, 60-s clock, beam, alarm, cooldown, revenge, DASH, Second Arm, Vault Insurance, break-in removal, TOP THIEVES | HEIST | **STATIC only** (QA3, 15 checks read from the live source + edit-mode evals; TopThieves existence PASS) | 19 driver scripts ready in `SP\lua\qa3\` |
| Pickling: stages, jars, labels, card line, micro-buttons, Pickle Day, "While you were gone", theft carries age | PICKLE | **STATIC only** (QA3 check 14) | build-phase sandbox tests passed (`pickle-test-vs.lua`, `pickle-test-cs2.lua`) |
| Tutorial: spawn framing, six beats, Dill, practice vault, first-five-minutes quiet | TUTORIAL | **STATIC only** (QA1, final 21:32 UTC: D1 spawn framing PASS numerically in edit mode - sign at x 0.62 of the viewport for even stalls, 0.38 for odd; a contract audit of the live sources - remote kinds, attributes, stall children, `DillService` auto-Initialize - all line up; every live beat NOT RUN) | 12 driver scripts ready in `SP\lua\qa1\` |
| Fixes made AFTER the only playtest | QA2 fixes 2–4, QA1 fixes 1–2, FIELD's Spawn-meter-inert change | **compile-checked only** (QA2 fix 1 verified by a tree walk) | see §5 |

### 1.1 The blocker (exact repro)

Studio's engine holds a zombie play session that only a human can clear.

- 20:17:27 UTC QA2 acquires the playtest lock and starts a solo playtest (~20:19). From ~20:19 the Studio window renders no frame (`capture_screenshot`: "Studio window appears minimized or not rendering (no frame in 3382 s)").
- 20:42:28 UTC `pt-lock.js` treats any lock older than 1500 s as stale, so QA1 silently takes the lock while QA2's playtest is still running; QA2's client peer goes flaky from ~20:37.
- 20:46 UTC QA2 `solo_playtest stop` → **"EndTest failed"**; four restarts time out ("did not become ready before timeout", roles = `edit` only).
- QA1 `solo_playtest stop` → "Playtest stopped.", but every `start` since (play and run mode, solo and 1-player multiplayer, 15+ attempts over 35 min, plus a direct `StudioTestService:ExecutePlayModeAsync({})` from an edit eval) fails with Studio's own error **"Failed to start the test because a previous one is still in progress."** QA3 (21:07–21:16 UTC) gets the same error on every attempt (17 such warnings in the edit-peer log). QA1 stopped retrying and released the lock at 21:32 UTC; nobody holds the lock now.
- State observed: `RunService:IsRunning()` = false, `StudioTestService.EditModeActive` = true, only the `edit` peer connected, one `RobloxStudioBeta.exe` (2.9 GB), no dialog windows. No-ops tried: `RunService:Stop()`, `StudioTestService:EndTest()` ("can only be called from the server DataModel of a running Studio play session"), `multiplayer_playtest end` ("already ended"), `solo_playtest stop` ("No active playtest to stop").
- **Recovery (human, ~10 s):** restore / un-minimize the Studio window; press **Stop** (or the test's End Test / Cleanup button). If it is greyed out: save the place first (the 8-agent edits are unsaved), restart Studio, then restart the bridge daemon (`SP\bridge\start-daemon.sh`).

---

## 2. What the owner must do next

1. **Clear Studio:** restore the window, press Stop / End Test (see §1.1). If greyed: save, restart Studio, restart the bridge daemon.
2. **Check for a stray edit-mode attribute** `workspace.QA1CamRestore` (a CFrame-ish string QA3 saw at 21:16 UTC; QA1's final note at 21:32 UTC says it left no QA attributes or instances behind and restored the edit camera) - if it is still there, delete it before saving. Workspace should carry 0 attributes in edit mode.
3. **Re-run the blocked QA** (or ask a session to): QA3's 2-player protocol `node SP\lua\qa3\run.js <server|client-1|client-2> <file>` in the order listed in `SP\agent-notes\QA-QA3.md` (t1-lock → t2-grab → t3-expire → t4-bank → t5-revenge → t6-dash → t7-secondarm → t8-insurance → t9-misc → t10a/b/c/d-pickle → t11-upgrade); QA1's solo protocol `node SP\lua\qa1\run.js client-1 SP\lua\qa1\<x>.lua` (watch-install → state → smash → prompt(store) → prompt(pad, lever) → prompt(practice1) → prompt(store) → raidwait → tag → choice → srv-state → watch-read). Also re-check the four post-playtest fixes (§5.2) and FIELD's Spawn-meter change (break 100+ Spawn cucumbers at rebirth 0 → no boss).
4. **Save / publish** the place (File → Save to Roblox / Publish). Nothing the agents did is saved yet.
5. **Game Settings → Players.MaxPlayers = 8** (read-only from Luau; the Studio file still says 60 per the spec's tuning table).
6. **Create six Developer Products** on the Creator Dashboard, then paste each id into `ReplicatedStorage.Modules.ControllerLoader.Custom.ProductController` → `Products.Micro[<Key>].Id` (all are `0` now; with `0` the buttons show "🚧 COMING SOON!" and never prompt):

| Dashboard name | Price | Key | Effect on receipt |
|---|---|---|---|
| Pickle Now | 10 R$ | `PickleNow` | `VaultService.PickleAdvance(player, spot)`: jar → next stage |
| Sticky Hands | 10 R$ | `StickyHands` | player attribute `StickyHands` += 5 (next 5 smashes catch) |
| Field Restock | 15 R$ | `FieldRestock` | `BreakablesService.RestockZone(zone, DisplayName)`: refills the buyer's field for everyone, name in chat |
| Second Arm | 15 R$ | `SecondArm` | `SecondArmUntil` = max(now, current) + 600 |
| Vintage Now | 25 R$ | `VintageNow` | `VaultService.PickleToVintage(player, spot)` |
| Vault Insurance | 25 R$ | `VaultInsurance` | `VaultService.RecoverLastStolen(player)` |

7. **Rename the passes** on the dashboard: gamepass `1902852565` → "2x Coins", `1919162313` → "Auto Smash" (the game already displays those names via `ProductController.DisplayName`).
8. **Take off sale:** Nuke Server (`3610280695`) and Break Into Base (`3710299055`). Their receipts now return `NotProcessedYet` → Roblox retries then refunds; nothing is granted.
9. **Starter Pack** (`3609836817`) keeps its id but now pays 20,000 Coins + a GOLDEN Spawn cucumber on the arm: update its dashboard description/icon.
10. Optional: create a "Bigger Vault" pass and add it to `Gamepasses` in ProductController (TODO comment; no id → not shown).
11. **Studio text edit:** `GroupRewardsGui` card art still reads "1.5x cucumbers" (authored label, not code) → "1.5x Coins".
12. Tooling: raise `pt-lock.js`'s stale threshold from 1500 s to ≥ 3600 s (or make QA agents renew) so a lock cannot be taken mid-playtest again.
13. **Eyeball in a playtest** (merged from all QA reports, de-duplicated):
    1. Fresh spawn: stand on the walkway ~16 studs east of your door facing west; your stall sign centre-right (x ≈ 0.62–0.70 of the screen), field ahead; 0.7 s sign close-up then 1.5 s glide feels calm (tweens freeze when the window is unfocused).
    2. First five minutes: nothing on screen but the tutorial banner + HUD (chip, coins, steals, chest, streak, rebirth, backpack); no favourite / group / playtime / gamepass prompts. The LIKE banner may appear right after completion if the session is already > 5 min (Lil Pickle counts as a new pet; SPEC says leave LikePromptClient as is).
    3. Beat 5: Dill walks IN through your door (not on the roof / in a wall), holds a copy of your jar, the podium looks empty only to you; tagging him snaps the jar back with the gold burst.
    4. Practice vault at (18, ~3, 30): slab flush with the lobby ramp, jars on gold pedestals, "STEAL ME" cards, Dill dancing beside it at (27, 19).
    5. VOID catch: 2-s freeze, FOV push, desaturation; a plain NEON catch pops WITHOUT slow-mo (QA2 fix 3).
    6. HP-bar "GIANT"/"SMALL" title badges on sized cucumbers (QA2 did not see them; only the secret's title was present).
    7. Restock wave "≥ 25 % specials" (QA2 saw 3/16 on one wave); combo meter fade timing (~6 s after the last hit).
    8. Event chip colours (gold / purple / red / lime) and the boss-bar layout during BIG GHERK at rebirth 0.
    9. Index: SECRET row flipping to "THE LEGEND – FOUND!" after a real secret; the 1,143-descendant panel on a phone; stud texture against the green background.
    10. Playtime tier 8 refusal toast "STORE YOUR CUCUMBER FIRST!"; "+N COINS" boss-kill / escape toasts after the string fixes.
    11. TOP THIEVES board (38.1, 12.9, 51.6), 17 studs north of TOTAL COINS with the same footprint: clipping against the building shell?
    12. Jar visuals from the aisle at PICKLE (glass cylinder + dark-green lid), AGED (cream label "NAME'S PICKLE"), VINTAGE (gold lid + sparkle); the card StageLine on phones (144 px at scale 1, ~0.6× on phones); the 🫙 emoji (U+1FAD9) may render as a box on old emoji fonts (fallback "🥫"/"🍶").
    13. Heist HUD cards (top-centre, y = 92 px) vs the event chip (bottom y 40 desktop); RUN BACK button placement; REVENGE button above the bottom bar on phones.
    14. Klaxon + laser flicker feel at 10 s; UNPROTECTED card readable from 40 studs (MaxDistance 110).
    15. Chat: emoji + coloured mutation words render in TextChatService (rich text falls back to the legacy system message if filtered).
    16. Nametag: the name row is bigger for everyone (deliberate, "readable from 40 studs").

---

## 3. Hook by hook

| # | Hook (SPEC) | What was built | Where | Verified |
|---|---|---|---|---|
| 1 | Variable reward | Per-smash catch roll 20 % → 5 % floor over 400 breaks; guaranteed catch on the 3rd smash of a first session; mutation gate 4 % (×3 under Harvest Moon); three sizes SMALL/NORMAL/GIANT; secret 1-in-50,000 | `BreakablesService` (`MUTATIONS.Catch`, `MUTATIONS.Sizes`, `MUTATIONS.Secret`, `PlanCatch`/`ResolveCatch`), `MutationColors` | LIVE (QA2 1–6) |
| 2 | The luck moment | Every mutation catch announced server-wide with the catcher's name and "[1 in X]" via `SystemChat`; 2-s slow-mo on VOID and above; showcase size badge / secret headline | `BreakablesService.AnnounceCatch`, `BreakablesClient` (`HeistFX.slowMo`), `CarryShowcaseClient` | LIVE (QA2 4–5); slow-mo threshold fix STATIC |
| 3 | Near miss | 60-s heist clock shown to both players; red beam + Highlight + "🥷 THIEF" marker on the thief; siren + "NAME IS ROBBING YOU!" banner with RUN BACK; thief at two-thirds speed; expiry snaps the jar back | `VaultService.Heist.*`, `HeistHudClient` (new), `Dictionaries.Upgrades` | STATIC (QA3 3–4) |
| 4 | Loss aversion | Lock 90 s + 15 s/rebirth; klaxon at 10 s at the lever and to the owner anywhere; lasers flicker (`LockLeft`); lever card red; "🔓 UNPROTECTED" door card at zero; toast "YOUR VAULT IS OPEN - PULL THE LEVER!"; jars gain value with age (hook 12) | `VaultService` security tick, `VaultFXClient`, `BankBuilder` | STATIC (QA3 1–2) |
| 5 | Collection with a book | Cucumber Index: 55 unique types × 3 materials × 9 mutations = 1,485 tiles, greyed until caught; Coins per first discovery; a cosmetic every 10; size badges; SECRET row | `CucumberIndexService` (new), `UserInterfaceLoader.CucumberIndex` (new), panel `Display.Frame.Frames.CucumberIndex` | LIVE (QA2 16–19) |
| 6 | Status display | Stall NameSign 18 × 4.2 studs with headshot, "NAME'S VAULT", "BEST: <jar>" (mutation-coloured), neon `BannerStrip`; TOP THIEVES physical board; `leaderstats.Steals`; HUD Steals pill "🥷 N" | `VaultService.RefreshSign`, `BankBuilder`, `Leaderboards.Steals` (new), `workspace.Leaderboards.TopThieves` (new), `HUD.Wallet.Steals` | Sign/board STATIC (QA3 13 existence PASS); Steals pill + leaderstats LIVE (QA2 20, 26) |
| 7 | Appointment timers | One UTC server clock: GOLDEN_HOUR :00/:20/:40 (2 min), HARVEST_MOON :50 (2 min), BOSS :30, CUCUMBER_SMASH when 3+ in a field, PickleDay on Saturdays; countdown chip always on the HUD; random post-boss selector OFF | `EventClock` (new) + `ReplicatedStorage.EventClock` folder, `HUD.EventChip` + `EventChipClient` | LIVE (QA2 13–14, 20) |
| 8 | Endowed progress | Five empty podiums glow for the first session; boss summon meter hidden until first rebirth; the Spawn meter no longer charges at all (boss only on the clock) | `TutorialClient` (glow), `BossBarClient`, `BreakablesService` (`MeterInert`) | Meter hide LIVE (QA2 20, 22); glow STATIC (QA1 D4); Spawn meter inert STATIC (post-QA2) |
| 9 | Competence and autonomy | Six-beat tutorial ending on a save; CHOICE card "LOCK NOW or GO STEAL?"; persistent combo meter "×1.35 COMBO" | `TutorialClient` (rewrite), `TutorialProgressServer` (v4), `BreakablesClient` (`ComboMeter`) | Combo LIVE (QA2 7); tutorial STATIC (QA1) |
| 10 | Social presence | Every heist named in chat with the mutation coloured; REVENGE button 10 min; Steals leaderboard; Dill mocks thieves by name | `VaultService` chat lines, `RevengeClient` (new), `EventClock` mocking | Dill event lines LIVE (QA2 14); heist lines STATIC |
| 11 | Rivalry | `RevengeTeleport` to the thief's door when their lock drops, per-victim cooldown waived once; "😈 ROBBED YOU N TIMES" on the thief's sign, viewer-only | `VaultService.RevengeTeleport`, `RevengeClient`, `VaultTextClient` | STATIC (QA3 7) |
| 12 | Time investment that grows | FRESH → PICKLE (10 min ×1.5) → AGED (1 h ×2.5) → VINTAGE (24 h ×5); glass jar, name label, gold lid; theft carries the age; "WHILE YOU WERE GONE" card with a jar-filling graphic | `VaultService` pickling block, `CarryService.EffectiveRate`, `PickleCardClient` (new), `OfflineEarnsBannerClient` (rewrite) | STATIC (QA3 14) |
| 13 | Streaks and ladders | Playtime ladder rebuilt (Coins, boost, skips, `trail_gold`, Golden cucumber); chest shows the next tier's timer; streak chip "DAY N" with a 7-day card, no join popup; Dill hands out the streak line | `PlaytimeRewards`, `PlaytimeNewFrame`, `PlaytimeReadyClient`, `StreakService`, `StreakChipClient` (new), `EventClock` | Playtime LIVE (QA2 30); chip LIVE (QA2 20); `StreakPaid` → Dill line not observed live |
| 14 | Mastery | Combo meter on screen; DROP becomes DASH while carrying stolen goods (0.35 s at 3× speed, 6 s cooldown, cooldown ring) | `BreakablesClient`, `CarryClient`, `VaultService.Heist.Dash` | Combo LIVE (QA2 7); DASH STATIC (QA3 8) |
| 15 | Identity | 10 carry trails + 8 stall banners (catalog), equip flow, trails rendered on every player's carry; jar labels with the owner's name; banner strip over the door | `CosmeticCatalog` (new), `CosmeticsService` (new), `CarryTrailClient` (new), `VaultService.RefreshJar`, `BankBuilder.BannerStrip` | Trail LIVE (QA2 18); labels/banner STATIC |
| 16 | The character | The Shards God is now **Dill**: walks, talks (`[DILL]` chat + speech bubble), runs the practice vault, chases, raids, announces every event, mocks thieves, hands out the streak; the Spawn boss is **BIG GHERK THE COLOSSAL** on the clock | `DillService` (new), `workspace.Dill`, `EventClock`, `BreakablesService.BOSS_TYPES.Spawn` | Dill lines + BIG GHERK LIVE (QA2 12, 14); walk/chase/raid STATIC (QA1) |

---

## 4. Per workstream

### 4.1 HEIST (hooks 3, 4, 10, 11, 14; lock timer, heist limit, per-victim cooldown)

Files:
- `ServerStorage.ServerController.VaultService` (shared with PICKLE; 23 anchored edits, no new top-level locals): lock 90 + 15/rebirth; `VaultLockedUntil`; `RefreshUnprotectedCard` (BillboardGui `UnprotectedCard` on `DoorZone`, MaxDistance 110); 10-s klaxon + `VaultFX LockWarn` + stall attribute `LockLeft` (10..1); expiry toast + `HeistEvent vaultOpen`; `PullLever` fires `vaultLocked`; `RefreshSign` rewrite; break-in prompt no longer built, `RequestPaidBreakIn`/`GrantPaidBreakIn` refuse; `VaultService.Heist` table (Duration 60, VictimCooldown 90, Cooldowns, LastDash, LastStolen) with `CooldownLeft/PushCooldowns/StampCooldown/EventPayload/AttachBeam/RemoveBeam/PushState/Tick/Dash/OnBanked/End/Return/Start`; `Steal` gets the cooldown check, pending-arm check, `Uid` stamp; binds `HeistDash`, `RevengeTeleport`.
- `VaultService.BankBuilder`: NameSign 18 × 4.2 studs (was ≤ 16 × 2.5), centre y 12.7; new neon part `BannerStrip` per stall over the door (green default, dim when unowned).
- `ServerStorage.ServerController.CarryService` (shared): `CarryService.PendingCarries`, `GetPending`, `EquipPending`; `GiveCarry` copies every meta field (StoredAt/AgeSec/PickleStage/Uid/Size survive steals); `Take` returns every field; `TryAwardFromBreak` Second-Arm rules.
- `ServerStorage.ServerController.Dictionaries.Upgrades` (cross-edit): `Speed *= 2 / 3` while `CarryingStolen` (value unchanged from `/1.5`).
- `ServerStorage.BaseBreakInService`: retired stub (`Prepare` → false, `GrantPending` → warn + true, grants nothing; remotes folder kept).
- `StarterPlayerScripts.VaultFXClient`: break-in listener removed; StealPrompt reads "COOLDOWN Ns" for stalls whose `OwnerUserId` is in the viewer's `StealCooldowns`; handlers `LockWarn` (klaxon + amber toast "10 SECONDS - LOCK IT!"), `HeistBanked`, `HeistLost`, `Revenge`; 0.5-s loop tweens laser bars of any stall with `LockLeft` (faster ≤ 3 s).
- `StarterPlayerScripts.VaultTextClient`: viewer-only `RobbedLine` "😈 ROBBED YOU N TIMES" on a thief's sign (replaces the BEST line locally).
- `StarterPlayerScripts.CarryClient`: DROP pill → orange DASH while `CarryingStolen`, cooldown ring; `HeistDashGo {Duration, Speed, Cooldown}` applies a 0.35-s LinearVelocity burst (XZ plane).
- NEW `StarterPlayerScripts.HeistHudClient` (`SP\lua\HeistHudClient.lua`): top-centre stack at y 92 px (UIScale = `HudMetrics.deviceFactor`): "🏃 ESCAPE · 0:59" / "🚨 ROBBED BY NAME · 0:59" (red, blinks ≤ 10 s) + jar name in mutation colour; victim banner "NAME IS ROBBING YOU!" + RUN BACK (only outside the deck footprint; fires `TeleportToVault`); siren (Klaxon + Alarm Bell); result card 5 s; on a lost heist `MicroStore.MakeButton(card, "VaultInsurance")` if present and DoneTutorial.
- NEW `StarterPlayerScripts.RevengeClient` (`SP\lua\RevengeClient.lua`): bottom-right REVENGE button (lifted by `HudMetrics.jumpClearance()`), "their vault unlocks in M:SS" from the thief's `VaultLockedUntil`, pulses + "GO NOW" when open, click → `Network:FireServer("RevengeTeleport")`; hides after use/expiry/while carrying stolen loot.
- `ServerStorage.ServerController.Leaderboards`: pcall-requires child `Steals`, `Steals:Update()` on the 90-s cycle. NEW `Leaderboards.Steals` ModuleScript (`SP\lua\LeaderboardsSteals.lua`): ordered DataStore `<ProfileKey> TotalSteals`, raw integers, board `workspace.Leaderboards.TopThieves`.
- NEW `workspace.Leaderboards.TopThieves`: clone of `TotalCoins` retitled "TOP THIEVES" at (38.1, 12.9, 51.6), 17 studs north of TotalCoins.
- Unchanged but owned: `HeistCombatClient` (still binds the unused `HeistRolePrompt`), `VaultPickaxeGuard`.

Numbers:
- Lock **90 s + 15 s/rebirth** (was 75). Heist clock **60 s**. Per-victim cooldown **90 s**, stamped on every attempt that reached a podium with empty hands (success or fail).
- Thief speed **× 2/3** (29 → 19.33), no sprint, no teleports. DASH **0.35 s at 3× walk, 6 s cooldown**. Revenge window **600 s**. Laser flicker loop 0.5 s (faster ≤ 3 s).
- Worst-case 60-s walk, measured on the built level-0 bank (DeckSlab 168.5 × 86 at x 42–210.5, doors at x 66.5 / 105 / 143.5 / 182, podium rows z 37.9 / −21.9): far podium to far podium ≈ 169 studs ≈ **8.8 s**; at max width (level ≥ 5) ≈ 276 studs ≈ 14.3 s; plus a 6-storey climb ≈ **23 s** worst case, leaving ≥ 37 s of slack for the chase.

Contracts:
- BindableEvent `ServerStorage.Events.HeistEvent` `{kind, thief, victim, name, mutation, stage, spot, seconds}`, kind ∈ `start | banked | caught | expired | returned | vaultOpen | vaultLocked | revenge` (`caught` = thief died; `returned` = drop / thief left / other carry loss; `banked` also on a forfeit).
- Player attributes: `VaultLockedUntil` (os.time, 0 when open), `TotalSteals`, `RobbedBy` (JSON `{thief, userId, name, at}`), `RevengeUntil`, `RevengeTargetUserId`, `RobbedByCounts` (JSON `{[thiefUserId]=n}`), `StealCooldowns` (JSON `{[victimUserId]=expiry}`), `PendingCucumber` (Second Arm); honours `SecondArmUntil` (STORE) and `StallBanner` (INDEX).
- Stall model attributes: `OwnerUserId`, `BestJarText`, `LockLeft`.
- Profile: `UserData.TotalStats.TotalSteals`, `UserData.LastTheft = {thief, userId, name, at, stage}`, `UserData.RobbedByCounts[tostring(userId)]`; `leaderstats.Steals` IntValue created if missing.
- Server API: `VaultService.RecoverLastStolen(player) -> bool`, `RevengeTeleport(player) -> bool`, `ForceExpire(player) -> bool`, `StealCooldownLeft(thief, victim) -> seconds`, `SyncHeistProfile(player[, data])`, `VaultService.Heist`; helpers `GetEvent/FireHeistEvent/SystemChat/MutationHex/FullName/RichName/UserDataOf/JSON/NewUid/StageOf`; `CarryService.GetPending(plr)`, `EquipPending(plr)`, `PendingCarries`.
- Network: client → server `HeistDash`, `RevengeTeleport`; server → client `HeistState`, `HeistDashGo`; VaultFX kinds `LockWarn`, `HeistBanked`, `HeistLost`, `Revenge` (+ existing `Expired`, `Robbed`, `StoleIt`).
- Chat (SystemChat; thief name `#FF5555`, mutation word in its MutationColors hex): "🥷 T is robbing V's NEON Cucumber!", "💰 T got away with V's …!", "🛡️ V caught T - the jar snapped back!", "⏱️ Time ran out - V's … snapped back!", plus drop/left/forfeit/recovered variants.

Dev hooks (workspace attributes, server context): `VaultStealDev = "seed:A"` | `"seed:A:NEON"` | `"grab:A:B"`; `LockDev = "expire:A"` | `"left:A:12"`; `HeistDev = "expire:B"` | `"dash:B"` | `"cooldown:B"`; player attribute `SecondArmUntil = os.time()+600` enables Second Arm.

### 4.2 PICKLE (hook 12; pickle stages, offline cap)

Files:
- `CarryService` (`EffectiveRate` region): `CarryService.PickleStages` ladder + `CarryService.PickleStageOf(record) -> name, mult, rawSecondsToNext?, index`; `EffectiveRate` × stage (×1 / ×1.5 / ×2.5 / ×5) and × size (GIANT ×2 / SMALL ×0.6), multiplicative with level and FROZEN; `EarnRateOf` untouched, `RateV` stays 4.
- `VaultService` (own regions): `EnsureUpgradeRow` (LayoutOrder 5 → 6, coin icon); `Upgrade` charges **Coins** ("NOT ENOUGH COINS! NEED N"); `SaveVault`/`LoadVault` persist `StoredAt`, `AgeSec`, `Stage`, `Size`; `StripPodiumAttachments` stamps `VaultLeftAt` and strips `PickleJar`; `DisplayOn` → `AdoptAge`, `AddStageLine` (LayoutOrder 5, tag `PickleStageLine`, +18 px card height), `RefreshJar`, `StampAge`, `RefreshBestJar`; `LoadVault` computes offline coins with the stage as of leaving then `AgeOffline`; accrual tick: `AgeSpeed` once per tick, `PickleTick` per record, `RefreshBestJar` per stall; `Initialize` → `pcall(VaultService.InstallPickleDevHooks)`.
- NEW `StarterPlayerScripts.PickleCardClient`: ticks every `PickleStageLine` label (0.5 s) from the stored model's attributes → "🥒 FRESH · pickles in 6:12" / "🫙 PICKLE ×1.5 · ages in 48:10" / "🏷 AGED ×2.5 · vintage in 22:59:10" / "🥇 VINTAGE ×5"; owner-only micro-buttons via `MicroStore.MakeButton(holder, "PickleNow"|"VintageNow", {StallId, Spot, Kind="jar"})` projected in a ScreenGui under each own card (gated DoneTutorial, own stall, MicroStore present; FRESH/PICKLE → PickleNow, AGED → VintageNow, VINTAGE none).
- `StarterPlayerScripts.OfflineEarnsBannerClient` (rewrite): leave-intent banners "YOUR JARS KEEP AGEING OFFLINE 🫙" + "YOUR LOCK DROPS IN 1:14 🔒" / "YOUR VAULT IS OPEN - LOCK IT! 🔓"; "WHILE YOU WERE GONE" card from player attribute `WhileYouWereGone` (JSON): "AWAY 5H 12M", jar filling (hours/6, capped) + "+12.4K COINS BANKED", "🫙 2 JARS TURNED PICKLE" lines, red "🚨 STOLEN: NEON CUCUMBER BY DILL" or green "🛡 YOUR STALL IS INTACT", NICE! button, auto-hide 15 s, ≤ 92 % of the viewport, post-tutorial only.
- `VaultTimeSkipService`: not edited; quotes read `EffectiveRate` so vault skips include the stage multiplier.

Numbers:

| Stage | Age | Rate multiplier | Visual |
|---|---|---|---|
| FRESH | < 600 s | ×1 | plain cucumber; card "🥒 FRESH · pickles in 6:12" |
| PICKLE | 600 s | ×1.5 | glass jar (cylinder) + dark-green lid, shimmer sound, toast "🫙 CUCUMBER TURNED PICKLE! ×1.5" |
| AGED | 3,600 s | ×2.5 | cream label on the aisle side "<NAME>'S PICKLE" |
| VINTAGE | 86,400 s | ×5 | gold (Metal) lid + `VintageSparkle`, label "…'S VINTAGE", no countdown |

- A taken-back jar re-stored within **600 s** keeps its age, else resets to FRESH. Theft moves the same model instance inside the 60-s heist, so a banked steal keeps the age.
- Pickle Day (Saturday UTC) ages **×2**: `AgeSpeed` = `PickleSpeedDev` × 2 on Pickle Day.
- Offline: coins = EffRate (stage as of leaving) × the existing 50 % / 30 % tiers (6 h equivalent, 16 h counted) × `VaultMultSnap`; then `AgeSec += full wall-clock absence` (×1, no retro Pickle Day; stage flips counted for the banner). Absences under 120 s age the jar but bank no coins (unchanged rule).
- Vault rate also × size: GIANT ×2, SMALL ×0.6 (legacy records = NORMAL).

Contracts:
- Server API: `VaultService.PickleStageOf(rec) -> stageName, multiplier, secondsToNext` (nil at VINTAGE); `PickleAdvance(player, spot) -> bool` (jumps to the next threshold exactly, the clock keeps running; `spot` nil → `PickleSkipTarget` picks the non-VINTAGE jar closest to its next stage; false at VINTAGE / empty vault / no stall); `PickleToVintage(player, spot) -> bool`; `CanPickleSkip(player, "PickleNow"|"VintageNow") -> bool`; `BestJarOf(player) -> rec?`.
- Helpers: `VaultService.AgeSpeed()`, `IsPickleDay()`, `FormatAge(sec)`, `PickleStageDef(name)`, `RefreshBestJar(stall)`, `SendWhileYouWereGone(plr, stall, gone?)`; `CarryService.PickleStages` (`{Name, At, Mult, Emoji}` × 4), `CarryService.PickleStageOf(record)`.
- Stall model attributes (`workspace.CucumberBank.Stalls.Stall_N`): `BestJarText` ("NEON CUCUMBER · PICKLE", "" when empty), `BestJarStage`, `BestJarMutation` (refreshed by DisplayOn + every 1-s save pass).
- Stored-model attributes (`VaultService.StampAge`, ~1/s): `PickleStage`, `AgeSec`, `StageAt` (`workspace:GetServerTimeNow()`), `AgeSpeed`, `StoredAt`; `VaultLeftAt` (os.time, stamped when the model leaves a podium, cleared on arrival).
- Profile: `VaultCucumbers[i].StoredAt`, `.AgeSec`, `.Stage`, `.Size`; `UserData.LastTheftShownAt`.
- Player attribute `WhileYouWereGone` (JSON `{Stamp, Away, Coins, Stages={PICKLE,AGED,VINTAGE}, Stolen={name,thief,stage}?}`).
- Card: `EarnBillboard.StageLine` LayoutOrder 5 (tag `PickleStageLine`, attribute `Stage`); `UpgradeRow` LayoutOrder 6, still the last row (VaultFXClient's pill hit test holds); card height +18 px.

Dev hooks: `PickleSpeedDev = <number>` (Studio only, default 1); `PickleDev = "advance:Name[:spot]"` | `"vintage:Name[:spot]"` | `"age:Name:spot:sec"` | `"reset:Name"` | `"gone:Name"`; `OfflineBannerDev = true` previews the leave banners; `ReplicatedStorage.EventClock` attribute `PickleDay = true` (or `ClockDev = "pickle:on"`).

### 4.3 FIELD (hooks 1, 2, 14; catch chance, mutation gate, sizes, secret, smash rule)

Files:
- `ServerStorage.ServerController.BreakablesService` (at the 200-local cap; everything new is a `MUTATIONS.*` key or `BreakablesService.*` field): quotas; mutation gate; `MUTATIONS.GateMult(zone)`; `MUTATIONS.Sizes/RollSize/SizeOf`, `Size` attribute on model + hitbox, `ApplySizeTag/SetBarTitle`; `MUTATIONS.Secret` (+ `VariantFor(zone)`, `ApplyLook`), `SpawnMutatedDev(zone,"SECRET"|"VOID")`; `MUTATIONS.Catch`, `CatchChanceFor(TotalBreaks)`, `PlanCatch(part,data)` (sets `WillCatch/CatchWhy/CatchChance/OneIn/SlowMo`), `ResolveCatch(part,data)` (Second-Arm aware, decrements `StickyHands`, stamps `Size/OneIn/Secret`, `CarryingCucumberSize`), `AnnounceCatch`; `GetEvent`, `SystemChat`, `MutationHex`, `GuaranteeNextCatch`, `RestockZone`, `NoteClockEvent`, `StartFieldSmash`, `FieldTick`, `StartFieldLoop`; `EVENT_COOLDOWN_SECONDS 300 → 60`; `SetEventEffect` handles `HarvestMoon`; `SpawnBoss` returns true/false; `BOSS_TYPES.Spawn.Name = "BIG GHERK THE COLOSSAL"` (`FindType("Spawn","COLOSSAL CUCUMBER")` still resolves old trophies); zone folder attribute `Target`; Spawn meter `MeterInert = true` (post-QA2: `Break()` charge gated `data.Zone ~= "Spawn"`, `GrantRequirementSkip`/`RequestRequirementSkip` refuse Spawn when Phase == "None").
- `ServerStorage.ServerController.BiomeEventRegistry`: `GoldenHour Duration=120`; NEW `{Id="HarvestMoon", Name="HARVEST MOON", Duration=120}`; `CucumberSmash.MinPlayersInBiome 2 → 3`.
- `ReplicatedStorage.Modules.MutationColors`: `Mutations.LEGEND` (gold), `M.Sizes`, `M.SizeList`, `M.Secret {Name, Display, Color, Body, OneIn=50000}`, `M.Live` (9 tags), `M.Odds` ("1 in N" per tag).
- `StarterPlayerScripts.BreakablesClient`: `HeistFX` block - `ComboMeter` ScreenGui ("x1.35 COMBO", grows/shakes per hit, fades 3 s after the 3-s window, client attribute `ComboMult`); `HeistFX.slowMo(2, boom)` (burst frozen, FOV −14, ColorCorrection desaturate, PitchShift 0.6 octave, skippable, attribute `SlowMoUntil`); `CatchMissed` → `MicroStore.ShowContextual("StickyHands"|"SecondArm")` (DoneTutorial gate, 45 s per key); secret sting + gold sparkle fall.
- `StarterPlayerScripts.CarryShowcaseClient`: secret headline "THE LEGEND!!!" / "??? LEGENDARY PICKLE"; size badge before the name; waits for `SlowMoUntil`.
- `StarterGui.AdminPanel.AdminPanelClient`: mutation cycler adds VOID and SECRET.
- Cross-edit `CarryService`: showcase `OneIn` folds `data.CatchChance`; `Size` through GiveCarry meta → entry → `Take()`.

Numbers:
- Population quotas: `PER_ZONE 12 → 10`, `PER_ZONE_MAX 32 → 22`, `SLICED_BASE 7 → 6`, `SLICED_PER_PLAYER 3 → 2`, `SLICED_MAX 28 → 10` → Spawn field **16 (1 player) … 32 (8 players)**; zone folder attribute `Target` (QA2: 16 at boot, 21 with 2 players).
- Mutation gate `MUTATION_CHANCE 0.0305 → 0.04`; every rotation `Chance` scaled by 0.04 / 0.0305 (the sum stays exactly 0.04):

| Mutation | Odds per spawn | Under Harvest Moon (`MUTATIONS.GateMult` = 3) |
|---|---|---|
| NEON, SHADOW | 1 in 76 (was 1 in 100) | ×3 |
| FROZEN | 1 in 191 | ×3 |
| RADIOACTIVE, MOLTEN | 1 in 305 | ×3 |
| ROYAL | 1 in 508 | ×3 |
| VOID | 1 in 1,200 (unchanged) | ×3 (pre-roll) |
| PRISMATIC | 1 in 20,000 (unchanged) | ×3 (pre-roll) |
| THE LEGEND (secret) | 1 in 50,000 | FIELD's notes scale only the rotation gate and the VOID/PRISMATIC pre-rolls |

- Sizes per spawn: SMALL 25 % (value ×0.6, HP ×0.7, scale 0.75), NORMAL 60 %, GIANT 15 % (value ×2, HP ×1.6, scale 1.35). QA2: 100 spawns → 21 / 64 / 15; HP bars Cucumber 21 / 30 / 48, Tree 210 / 300 / 480.
- Catch: `chance = max(0.05, 0.20 − 0.15 × min(1, TotalBreaks / 400))` (`MUTATIONS.Catch {Base .20, Floor .05, Decay 400}`); guaranteed on the 3rd smash while `DoneTutorial == false` (`TotalBreaks == 3` after the increment); `TutorialCarryPending`, `StickyHands > 0` and the secret always catch. QA2: 100 breaks → 20 catches.
- Secret: pre-roll before the material layer on every non-sliced spawn, no material/mutation, NORMAL size, HP ≥ 300, Reward/BonusCoins ×1,000 (Spawn: HP 300 / Reward 8,000 / BonusCoins 2,000 / template "Spawn Cucumber"); dark-green body, gold neon ridges, gold `Highlight` rim, gold PointLight, gold HP-bar title.
- Cucumber Smash rule (`FieldTick` every 5 s): zone Phase "None", no live boss, `EventClock.ActiveEvent == ""`, ≥ 3 players whose `FindPlayerBiome` is that zone, ≥ 600 s since that zone's last field smash → `StartEvent("CucumberSmash", zone)` for 30 s.
- Restock: every 4th spawn of the wave is a forced special (≥ 25 %); carried-then-dropped cucumbers survive; QA2 saw the refill in 3.4 s.
- `EVENT_COOLDOWN_SECONDS 300 → 60`; GoldenHour / HarvestMoon registry Duration 120 s; `CucumberSmash.MinPlayersInBiome 2 → 3`.
- Slow-mo: 2 s, FOV −14, PitchShift 0.6 octave, skippable; threshold (after QA2 fix 3) spawn-share odds ≥ 1 in 1,000 (VOID, PRISMATIC, secret, Diamond+mutation, GIANT+mutation stacks). Combo meter grows per real combo hit and fades 3 s after the 3-s window closes. `CatchMissed` → `ShowContextual` at most once per key per 45 s.

Contracts:
- BindableEvent `ServerStorage.Events.CucumberCaught` (created eagerly in `Initialize`) on every landed catch, plain included: `{player, typeName (base type, "Golden "/"Diamond " stripped; "THE LEGEND" for the secret), zone, material="PLAIN"|"GOLDEN"|"DIAMOND", mutation (nil if none; CHARGED is not a mutation), size, charged, oneIn (spawn share × size share × catch chance = the showcase number), secret}`.
- Server API: `BreakablesService.RestockZone(zoneName, buyerName?) -> bool`; `GuaranteeNextCatch(player) -> bool`; `StartEvent("GoldenHour"|"HarvestMoon"|"CucumberSmash", zone) -> true, "GOLDEN HOUR" | false, reason`; `StopEvent(zone)`; `SpawnBoss("Spawn") -> bool` (false = one already up); `NoteClockEvent(id, zone, seconds)`; `TypeNamesFor(zone)`; `CarryRarityOf(data)`; `SpawnMutatedDev(zone, tag)`; `FindType(zone, name)`.
- Attributes: player `CarryingCucumberSize` (server-set, cleared with the carry); carried model `Size`, `OneIn`, `Secret`; breakable model + hitbox `Size`; zone folder `workspace.Breakables.<zone>.Target`; `ReplicatedStorage.BossProgress.Spawn` `BossName` = "BIG GHERK THE COLOSSAL", `MeterInert`; client-only player attributes `ComboMult`, `SlowMoUntil`.
- Network: server → client `CatchMissed {Kind="NoCatch"|"RarerWhileCarrying"|"RefusedWhileCarrying"|"SwappedWhileCarrying", Chance, Name}`; `BreakableBroken` payload gained `CukeSize`, `SlowMo`, `Secret`.
- Chat (SystemChat): "✨ NAME caught a <font color=hex>NEON</font> GIANT Sun-Baked Cucumber! [1 in N]" (🌈 for PRISMATIC); secret "🥒❓ NAME found THE LEGEND - ??? LEGENDARY PICKLE! [1 in 50,000]" + Notif to all; restock "🌱 BUYER restocked the SPAWN field!". PRISMATIC's existing smash fanfare untouched.
- Consumes: `StickyHands` (decremented per landed catch), `TutorialCarryPending`, `EventClock.ActiveEvent`, and `EventClock.SetExternalEvent("CUCUMBER_SMASH", os.time()+30)` when present (pcall).

Dev hooks: `CatchDev="force:Name"`, `SizeDev="Zone:GIANT|SMALL|NORMAL"`, `MutationDev="Zone:NEON|SHADOW|FROZEN|RADIOACTIVE|MOLTEN|ROYAL|VOID|PRISMATIC|DIAMOND|SECRET"`, `RestockDev="Zone[:Buyer]"`, `SmashDev="Zone"`, existing `StartEventDev="Zone:GoldenHour|HarvestMoon|CucumberSmash"`, `SpawnBossDev="Spawn"`, `KillBossDev="Zone:Name"`, `LightningDev`; `PostBossSelectorDev = true` restores the old random post-boss selector.

### 4.4 CLOCK (hooks 7, 16; Golden Hour row)

Files:
- NEW `ServerStorage.ServerController.EventClock` (31,550 chars; mirror `SP\lua\clock-EventClock.module.lua`, pushed in 5 chunks): auto-initialised by `Server`.
- NEW `ReplicatedStorage.EventClock` Folder with the contract attributes pre-set (`ActiveEvent=""`, `ActiveEventEndsAt=0`, `NextEventName=""`, `NextEventAt=0`, `PickleDay=false`, `BossNextAt=0`, `ServerTimeOffset=0`) + extras `ActiveEventLabel`, `NextEventLabel`, `ActiveEventZones`, `ClockSpeed`; re-created if missing.
- Cross-edit `BreakablesService.Break()`: post-boss selector gated on `PostBossSelectorDev == true` (OFF by default).

Schedule (one UTC wall clock):

| Event | When | Length | How it starts | Zones |
|---|---|---|---|---|
| GOLDEN_HOUR | every 20 min at :00 / :20 / :40 | 120 s | `BreakablesService.StartEvent("GoldenHour", zone)` | Spawn + every zone a player is in (`CurrentBiome`, validated against the 8 names) |
| HARVEST_MOON | hourly at :50 | 120 s | `StartEvent("HarvestMoon", zone)`; the attribute is published even if the registry entry is missing (one warn) | same |
| BOSS | hourly at :30 | until killed; `ActiveEventEndsAt` = activation + 360 s | `SpawnBoss("Spawn")`, skipped if `BossProgress.Spawn.BossActive`; `ActiveEvent="BOSS"` follows the live flag whatever summoned him | Spawn |
| CUCUMBER_SMASH | when FIELD's rule fires | 30 s | never started by the clock; mirrored from `BossProgress.<zone>` `EventPhase=="Active"` + `EventId=="CucumberSmash"`, or `SetExternalEvent` | that zone |
| PickleDay | Saturday UTC (`os.date("!*t").wday == 7`) | all day | flag only (PICKLE doubles ageing) | - |

- Priority when overlapping: scheduled HARVEST_MOON > GOLDEN_HOUR > live BOSS > external > meter-mirrored. Admin-panel / `StartEventDev` starts of GoldenHour / HarvestMoon are mirrored into `ActiveEvent` too.
- Effective window = min(120 s, registry Duration); at window end `StopEvent(zone)` if the zone effect would outlive it by > 2 s (only under `ClockSpeedDev` or a registry Duration > 120; shows the existing "X STOPPED IN ZONE." toast).
- Attributes are republished every tick (1 s at real speed); `ServerTimeOffset = os.time() − workspace:GetServerTimeNow()` (fractional; HUD counts down against the client's `os.time()`).

Announcements go through `DillService.Say(text)` when present, else `SystemChat` with the `<font color="#7CFC00">[DILL]</font>` prefix; identical lines within 3 s collapse; chat lines only, no toasts (first-session quiet).

| Moment | Line(s) |
|---|---|
| 60 s before | "GOLDEN HOUR in 60 seconds - get to the field!" / "HARVEST MOON rises in 60 seconds - mutations ×3!" / "BIG GHERK stomps in 60 seconds. Grab your pickaxe!" |
| Start | "GOLDEN HOUR! Golden cucumbers everywhere for 2 minutes!" / "HARVEST MOON rises - mutations ×3!" / "BIG GHERK is stomping into the field!" / "CUCUMBER SMASH! Most smashes in 30 seconds wins!" |
| End | "Golden Hour is over. Next one in N minutes!" / "The moon sets. Mutation odds back to normal." / "BIG GHERK is down! Nice smashing, everyone." (killed) or "BIG GHERK got away. Back next hour!" (lived ≥ 6 min − 3 s) |
| Pickle Day | "It's PICKLE DAY - jars age twice as fast today!" server-wide when the flag turns true; `SayTo` each joiner 20 s after join if DoneTutorial |
| Thief mocking (`HeistEvent` kinds start / caught / returned / banked / expired / revenge; 3 rotating variants each; **max one line per 8 s** server-wide; vaultOpen / vaultLocked ignored) | "Shrey, I SAW that." · "Manish got you, Shrey. Pathetic." · "Shrey is now a wanted criminal." · "Too slow, Shrey." · "Manish is coming for you, Shrey. REVENGE!" |
| Streak (`ServerStorage.Events.StreakPaid {player, day, amount}` → 1 s later `SayTo`) | "Day 3 streak! 800 Coins. See you tomorrow." |

Public API (`GetModule("EventClock")`): `StartEvent(id)` (GOLDEN_HOUR/HARVEST_MOON/BOSS now), `StopAll()`, `IsActive(id)`, `Now()`, `SetExternalEvent(id, endsAt)`, `ClearExternalEvent()`, `GetState()`, `Say(text)`, `SayTo(player, text)`, `Dev(cmd)`, `ActiveZones()`, `RunTick()`, `Stop()`.

Dev hooks: `ClockDev = "next:GOLDEN_HOUR|HARVEST_MOON|BOSS"` | `"stop"` | `"warn:<id>"` | `"pickle:on|off|auto"` | `"say:<text>"` | `"mock:start|caught|banked|expired|revenge"` | `"streak:<day>:<amount>"` | `"status"`; `ClockSpeedDev = <number>` (60 = a full hour in one real minute; windows shrink, "X STOPPED" toasts expected in this mode only).

### 4.5 TUTORIAL (hooks 8, 9, 16; moment map 0:00–5:00, "Spawn")

Files:
- NEW `ServerStorage.ServerController.DillService` (966 lines at build; QA1's `groundY` fix makes Studio 9 lines ahead of the mirror `SP\lua\tutorial-DillService.lua`): Dill NPC, practice vault, chase, bluff raid, fresh-spawn framing.
- `ServerScriptService.TutorialProgressServer` (rewritten, v4): funnel steps renumbered, `TutorialBeat` bindable, `TutorialBreaks` attribute mirror, `"beat"`/`"raid"` remote kinds, TutorialVersion 4 replay-once migration, `wantupgradecukes` removed.
- `StarterPlayerScripts.TutorialClient` (rewritten, 1,272 lines): six beats; banner/arrow/spotlight/chevron kit kept; SKIP restyled to small "skip" bottom-left (64×26, 26 px up / 96 px on phones); intro camera; podium glow; CHOICE card; `TutorialDev="beat:N"`.
- `ServerStorage.ServerController.ServerNetwork` (Tutorial handler): funnel bookend step 8; stamps `TutorialStep=8`, `TutorialVersion=4` on completion and on the `ClaimedTutorialPet` early return; +250 Coins via `CurrencyHandler.AddCurrency{WasPurchase=true, HasTotal=true}`; `TutorialPetReward` reveal popup removed (Lil Pickle lands silently).
- `ServerStorage.ServerController.DoorService.PlayerJoined`: players with `DoneTutorial ~= true` spawn at `DillService.FreshSpawnCFrame(Player)` (3-s retry for the stall assignment); biome pad fallback.
- `Workspace.SpawnLocation`: moved from (−16.7, 3.5, 8.9) to **(56, 3.5, 8) facing west** (walkway just inside the arch).
- `Workspace.Shards` → **`Workspace.Dill`** (permanent): `Humanoid.DisplayName="Dill"`, `Head.Tag` "DILL", forge prompt `ObjectText="Dill"`, rig scaled 3.21 → 1.46 (20.8 → 9.7 studs), `HumanoidRootPart.PivotOffset` reset, home (27, ground, 19).
- `ServerScriptService.ShardsGodServer` / `StarterPlayerScripts.ShardsGodClient`: look up `Dill` (fallback `Shards`); greeting "I'M DILL. GOT BOSS SHARDS?"; forge untouched.
- `ServerScriptService.PetShopGiftServer`, `PickaxeShopGiftServer`: RETIRED (`Enabled=false`; the 500 / 2,500 coin gifts are gone).
- Cross-edit `StarterPlayerScripts.FavoritePromptClient` (STORE's): favourite prompt waits for DoneTutorial (bounded 15 min) + 20 s.
- Runtime-built every boot: `workspace.DillPracticeVault` (FloorTile, BackWall, 2 SideWall, Roof, Fascia, NameSign "DILL'S PRACTICE VAULT / ANYONE CAN ROB THIS", LasersOff/LaserOff1-8, Pedestals/Pedestal1-2 + Spot1-2, Jars/PracticeJar1-2, Mat) centred (18, ground, 30), door facing −Z; `ReplicatedStorage.TutorialTagDill` RemoteEvent; `ServerStorage.Events.TutorialBeat`; `Dill.DillWalkAnim`, `Dill.Head.DillBubble`.

The six beats (pill "N/6"; `TutorialStep` persists so a quitter resumes; funnel step = beat + 1):

| Beat | Banner(s) | What happens | Done when |
|---|---|---|---|
| 1 COMPETENCE | "SMASH A CUCUMBER" | intro camera (fresh spawn only: 0.7 s on your stall sign, 1.5 s glide behind you facing the field, 3.5 s watchdog hands the camera back); arrow to the nearest sliced cucumber | `TutorialBreaks` rises |
| 2 JACKPOT | "AGAIN! SMASH ANOTHER!" → "ONE MORE! BIG ONE!" → "TAKE IT TO YOUR VAULT" → "STORE IT ON A PODIUM" | from the 2nd smash the client sends `wantcarry` (arms `TutorialCarryPending`; FIELD's 3rd-smash rule covers brand-new saves anyway); showcase card; chevrons to your sign / the arch; arrow on the first empty pedestal | Store (a v4 replay with a FULL vault skips the beat) |
| 3 OWNERSHIP | "STEP ON THE PAD" → "PULL THE LEVER" | arrow on the filled podium's CollectPad (45 s cap, done when `RawStats.Coins` rises); arrow on the lever hinge; the empty podiums of your stall glow (client-only Highlight + neon ring, re-resolved every second across bank rebuilds) until every podium is filled or 40 min | `VaultLeverPulls` |
| 4 TRANSGRESSION | "DILL'S VAULT IS OPEN... 👀" → "RUN HOME! STORE IT!" → "YOU'RE A THIEF NOW" | chevrons to a practice jar; hold F (`StealPrompt`, 1 s, ≤ 11 studs, empty hands) → a NON-stolen carry of the real Spawn type (`CarryService.BuildFromTemplate` + `Restore`; teleports allowed, normal speed); Alarm Bell + red light; Dill shouts "HEY! NAME! THAT'S MY CUCUMBER!" and chases 20 s at 0.9× your WalkSpeed (stalls inside 7 studs, never catches; gives up with "Fine. Keep it. I have MORE."); Drama Sting on store; jar refills after 30 s; outside the tutorial anyone can rob it (45 s per-player cooldown "DILL IS WATCHING. WAIT A BIT!", "ARMS FULL" refused) | Store |
| 5 NEAR MISS | "GO SMASH MORE" → "YOUR LOCK DROPPED! RUN BACK!" → "DILL'S IN YOUR VAULT! HIT HIM!" → "SAVED! 🎉" or "DILL GAVE UP. LUCKY YOU!" | 20 s of smashing (extended up to 45 s while within 40 studs of your stall) → `raid` → server `VaultService.ForceExpire(player)` (else `stall.SecureUntil = 0`); Dill appears on the aisle 7 studs outside your door, waits 1.6 s for the lasers, walks to the first stored spot, lifts a stripped CLONE of the jar welded to his left hand (the record never moves), says "NAME, your lasers are DOWN. Mine now.", crawls to the door at WalkSpeed 1.6 (up to 36 s); client plays the klaxon itself (HEIST's expiry toast/klaxon stay gated off mid-tutorial; the UNPROTECTED card may show), hides the original jar locally, chevrons to your door; within 30 studs of Dill an arrow on his head; any click/tap with Dill ≤ 16 studs → `TutorialTagDill` → server `OnTag` → `DillRaid="saved"`, `VaultFX{Kind="Deposit"}` gold burst, Big Thud, "OW! OK! OK! Take it back!", Dill flees home, fanfare + Crowd Cheer; no tag in time → "gaveup" ("Too heavy. Keep it. THIS time."); no stored jar / no stall → beat skipped silently | tag or give-up (funnel 6 SavedFromDill) |
| 6 CHOICE | card "LOCK NOW or GO STEAL?" with LOCK / STEAL / X | confetti; LOCK → arrow to your lever hinge (45 s or until pulled); STEAL → chevrons to the nearest OTHER stall with lasers down + something stored, else Dill's jar (60 s or until your carry changes); UIScale = `HudMetrics.deviceFactor`, 0.9 on phones | a button reports step 7 (ChoiceMade), then the `Tutorial` network event fires → `DoneTutorial`, Lil Pickle silently, +250 Coins (skippers: `Skipped=true`, no coins); card ignored 30 s → completes anyway |

Spawn framing (`FreshSpawnCFrame`): 16 studs east of your door, 3.5 studs past the aisle centre away from your row, facing west with an 8° yaw → door + sign 30° off-centre: RIGHT third for even (south-row) stalls, LEFT third for odd (north-row) stalls; QA1's `AssignStall` fix gives first-session players even stalls first (2,4,6,8 then 1,3,5,7). Walk to the field 130–260 studs (5–9 s at WalkSpeed 29).

Contracts:
- `DillService.Say(text)` → `ReplicatedStorage.SystemChat:FireAllClients('<font color="#7CFC00">[DILL]</font> ' .. text)` + 4-s speech bubble over Dill's head (0.4-s dedupe); `SayTo(player, text)` same via `FireClient`; `WalkTo(pos, timeout?) -> bool` (PathfindingService, straight `MoveTo` fallback, newer movers cancel older ones); `ReturnHome()` (walks home at 22, pops home if stuck, resumes the authored dance); `RunPracticeRaid(player) -> bool`; `RunPracticeSteal(player) -> bool`; extras `FreshSpawnCFrame(player) -> CFrame, look`, `OnTag(player) -> bool`, `TryPracticeSteal(player, jarIndex) -> bool`.
- `ServerStorage.Events.TutorialBeat {player, beat=1..6, done}` (`done=false` when the client starts a beat, `true` when funnel step beat+1 lands).
- `ReplicatedStorage.TutorialTagDill` RemoteEvent (client → server, no args; server checks an active raid + distance ≤ 16 studs; 0.25-s rate limit).
- Player attributes: `TutorialStep`, `TutorialBreaks` (mirror of `TotalStats.TotalBreaks` while the tutorial runs, 0.5-s poll), `TutorialCarryPending` (existing), `DillPractice` ("carrying" | "chased"), `DillRaid` ("approach" | "carrying" | "saved" | "gaveup" | "none"), `DillRaidSpot` (int).
- Funnel (AnalyticsService onboarding): 1 TutorialStarted, 2 FirstSmash, 3 StoredInVault, 4 LockedVault, 5 PracticeSteal, 6 SavedFromDill, 7 ChoiceMade, 8 TutorialCompleted (ServerNetwork); skips → custom event `TutorialSkippedAtStep`.
- Profile: `Stats.TutorialVersion = 4`, `Stats.TutorialStep` (0–8), `Stats.TutorialReplayedAt` (os.time, set once by the v4 migration).

Dev hooks: `ServerStorage.ForceTutorialOnJoin` (BoolValue, session-only replay); workspace `TutorialDev = "beat:N"` (client jumps; server state is whatever you set up); `DillDev = "raid:Name"` | `"steal:Name"` | `"say:<text>"` | `"home"` | `"walk:x,z"`.

### 4.6 INDEX (hooks 5, 15; "The index")

Files:
- NEW `ServerStorage.ServerController.CucumberIndexService` (20,010 chars; `SP\lua\src\CucumberIndexService.lua`).
- NEW `ServerStorage.ServerController.CosmeticsService` (8,064 chars).
- NEW `ReplicatedStorage.Modules.CosmeticCatalog` (3,751 chars): 10 trails + 8 banners.
- NEW `ReplicatedStorage.Modules.UserInterfaceLoader.CucumberIndex` (23,733 chars): panel driver (PanelMetrics 898×664 canvas).
- NEW `StarterPlayerScripts.CarryTrailClient` (5,382 chars): trail on every player's `CarriedCucumber*` model from their `CarryTrail` attribute (two attachments 1.1 studs apart, lifetime 0.7 s; rainbow hue-cycle 10 Hz).
- NEW `StarterGui.Display.Frame.Frames.CucumberIndex` (62 descendants static skeleton, built by the idempotent `SP\lua\INDEX-build-panel.lua`; `FORCE = true` rebuilds): `CloseButton`, `Bg`, `StudStyle`, `Outlines`, `Heading` "CUCUMBER INDEX", `CountLabel`, `NextLabel`, `Tabs.TabIndex/TabCosmetics`, `ZoneList`, `Grid`, `SecretCard`, `Legend`, `CosmeticsPage`, `ResponsiveScale`.
- Cross-edit `ReplicatedStorage.Modules.UserInterfaceLoader`: one `CucumberIndex = UserInterfaceLoader.new({...DoesUpdate = true})` line after `Playtime`.
- `IndexService` (pet index) untouched and alive.

Numbers:
- Total **1,485** = 55 unique type names × 3 materials × 9 mutations (NONE, NEON, SHADOW, FROZEN, RADIOACTIVE, ROYAL, MOLTEN, VOID, PRISMATIC); the Spawn zone counter reads "N / 162" (6 types × 27).
- First-discovery reward = **100 × zone tier (Spawn 1 … Narmek 8) × material {PLAIN 1, GOLDEN 3, DIAMOND 8} × mutation {none 1, rotation 5, VOID 25, PRISMATIC 200}**; secret **100,000**. Observed live (QA2, Coins delta exact): plain Spawn +100, NEON +500, GOLDEN NEON +1,500, PLAIN VOID +2,500, DIAMOND PRISMATIC +160,000, GOLDEN GIANT +300, Desert plain in an unowned zone +200, `discover:8` +17,400.
- Every **10** discoveries (`PER_COSMETIC = 10`) → the next ladder cosmetic, 18 steps: `trail_green, trail_gold, banner_green, trail_pickle, banner_gold, trail_neon, banner_red, trail_royal, banner_blue, trail_void, banner_purple, trail_rainbow, banner_rainbow, trail_frost, banner_black, trail_lava, banner_pink, trail_prismatic`; already owned or ladder exhausted → +5,000 Coins "📖 INDEX BONUS". A granted cosmetic auto-equips only into an empty slot.
- Sizes give badges only (no coins). Panel scale: phone ~0.47 (422×312 px), tablet ~0.75; zone buttons 70×25 px, tiles 14×12 px. `GetCucumberIndex` cached 0.5 s per player. Trail: two attachments 1.1 studs apart on the carried model's PrimaryPart, lifetime 0.7 s, light-emissive; rainbow entries hue-cycle at 10 Hz client-side.

Contracts:
- Consumes `ServerStorage.Events.CucumberCaught` (validates player / material / mutation / size / zone; `secret == true` → key `SECRET|PLAIN|NONE`; stray "Diamond " / "GOLDEN " / mutation prefixes stripped only when the full name is not itself a catalogued type; uncatalogued names such as boss trophies ignored with one warn).
- Profile: `UserData.CucumberIndex = {["<Type>|<MATERIAL>|<MUTATION|NONE>"] = os.time, Sizes = {["<Type>|<SIZE>"] = true}, LadderClaimed = n}`; `UserData.Cosmetics = {Owned = {[id]=true}, Trail = id|"", Banner = id|""}` (keys added at first use).
- Player attributes: `IndexDiscoveries` (int, set on join + every discovery), `CarryTrail` (id or ""), `StallBanner` (id or "").
- Rewards via `AddCurrency{Currency="Coins", WasPurchase=true, HasTotal=true}`; toasts "🥒 NEW DISCOVERY +N COINS", "🥒 THE LEGEND! +100,000 COINS", "✨ NEW TRAIL: GREEN TRAIL".
- Server API: `CosmeticsService.Grant(player, id) -> bool` (true only when NEW), `.Owns(player, id)`, `.Equip(player, id) -> bool` (refused unless owned), `.Unequip(player, "trail"|"banner")`, `.State(player) -> {Owned, Trail, Banner}`; `CucumberIndexService.GetSnapshot(player)`, `.GetCatalog()`, `.CountDiscoveries(idx)`; exported `LADDER, PER_COSMETIC, FALLBACK_TYPES, ZONES, MATERIALS, MUTATIONS, SIZES`.
- Catalog `ReplicatedStorage.Modules.CosmeticCatalog[id] = {Kind="trail"|"banner", Name, Color, Color2, Rarity, Order, Rainbow?}`: trails `trail_green, trail_gold, trail_pickle, trail_neon, trail_frost, trail_royal, trail_lava, trail_void, trail_rainbow, trail_prismatic`; banners `banner_green, banner_gold, banner_red, banner_blue, banner_purple, banner_pink, banner_black, banner_rainbow`. `Rainbow = true` = hue-cycle gradient.
- Remotes (Network): function `GetCucumberIndex` → `{Index, Sizes, Count, Total, Catalog = {Zones = {{Name, Tier, Types}}, Materials, Mutations, Sizes, UniqueTypes, Total, SecretKey}, OwnedZones, Cosmetics, Ladder, PerCosmetic, LadderClaimed, Secret, SecretKey}`; function `EquipCosmetic(id, kind)` → State (id "" unequips `kind`); client events `CucumberIndexChanged {Key?, SizeKey?, Count, Reward?, Secret?, TypeName, Zone}`, `CosmeticsChanged (State)`. There is no client path to write discoveries.
- Panel opens via `UserInterfaceLoader.Main.OpenFrame("CucumberIndex")` or server `Network:FireClient(player, "TriggerFrame", "CucumberIndex")`; only owned zones are selectable (others "🔒 … LOCKED"); discoveries in unowned zones still count and pay; live names from `BreakablesService.TypeNamesFor(zone)` merge behind the canonical order, so a new FIELD type appears automatically.

Dev hooks: `IndexDev = "discover:Name:N"` | `"catch:Name:Type_Name:MATERIAL:MUTATION:SIZE"` (spaces as `_`, trailing parts optional) | `"secret:Name"` | `"reset:Name"` (wipes index AND cosmetics); `CosmeticDev = "grant:Name:id"` | `"grantall:Name"` | `"clear:Name"`.

### 4.7 HUD (hooks 8, 13; "Spawn" HUD list, first pass/popup)

Files (build script `SP\lua\HUD-build.lua`, idempotent; sources `SP\lua\src\*.lua`):
- Instances under `StarterGui.HUD`: NEW `EventChip` Frame 600×64 design (+ `Pill`, `Gloss`, `Text` FredokaOne TextScaled max 40, `Badge` "PICKLE DAY" rotated −6°); `TopStatus["Group 280"].Visible = false` (BUY/BIOME/SELL hidden, anchor kept); `Wallet["15"]` (Cukes number) + cuke icon hidden; NEW `Wallet.Steals` pill 200×58 at (17,2); `LeftRail.Hoverboard.Visible = false`; NEW `LeftRail["Group 300"].Timer` under the chest; NEW `LeftRail.Streak` TextButton 123×58 "DAY N"; NEW `StreakCard` 460×190 (`Row.Tile1..7`); `RightRail.Nuke.Visible = false`, whole `RightRail.Visible` = store gate; `ButtonBar.PETS` (clone of PET INDEX), LayoutOrders BACKPACK 1 / PETS 2 / PET INDEX 3 / TRADING 4 / SHOP 5; NEW LocalScripts `HUD.EventChipClient`, `HUD.StreakChipClient`.
- `ServerStorage.Assets.Tag`: `Frame.PlayerName` Size (0.6,0.2) Pos (0.2,0.36); `Frame.RebirthBadge` Size (0.62,0.22) Pos (0.5,0.64); badge row ~0.66 studs tall at 40 studs (was 0.36).
- `ReplicatedStorage.Modules.HudMetrics` (rewrite): `CHIP_W/CHIP_H/TOP_SLOT_GAP`, `topChipScale()` (phone floor 0.42), `topSlotBottom()`, `storeGateOpen()`.
- `StarterGui.HUD.TopStatusLayout` (rewrite): `layoutTopSlot()` (chip at y = 8, anchor rect pinned onto the chip, attribute `TopSlotBottom`), RightRail gated, StreakCard placement.
- `StarterGui.HUD.ButtonBarMenu` (rewrite): satellites PETS / PET INDEX (book icon → `CucumberIndex`, falls back to the pet `Index`) / TRADING / SHOP (gated); BACKPACK only toggles the burst.
- `HUD.EventChipClient` (new): reads all EventClock attributes; "(timer) ..." placeholder + retry when the folder is absent; colours GOLDEN_HOUR gold / HARVEST_MOON purple / BOSS red / CUCUMBER_SMASH lime; pop + chime on event start (after DoneTutorial); last-60-s tint; binds `Wallet.Steals.Text` to `TotalSteals`.
- `HUD.StreakChipClient` (new): `GetStreakInfo` → "DAY N"; tap → 7-day card (today gold, past green, future white; auto-close 8 s); pulses 3× when `PaidToday` (after DoneTutorial) instead of a join popup.
- `StarterPlayerScripts.BossBarClient` (2 edits): `firstRebirthDone()`; meter hidden while `leaderstats.Rebirths == 0` unless `BossActive` or an active CucumberSmash.
- `StarterPlayerScripts.PlaytimeReadyClient` (rewrite): chest countdown "m:ss" / "OPEN!" / "DONE" (plain 🎁 before DoneTutorial).
- `StarterPlayerScripts.FriendBoostClient` (rewrite): boost pill top-centre under the chip (`TopSlotBottom` + 8).
- `ServerStorage.ServerController.PlaytimeRewards` (rewrite): new ladder; `buildState().Next = {Index, Remaining, Name, Ready}`; `PlaytimeSpeedDev`.
- `ReplicatedStorage.Modules.UserInterfaceLoader.PlaytimeNewFrame` (rewrite): new tile names/icons, no egg viewports (QA2 fixed a glyph ZIndex tie).
- `ServerStorage.ServerController.StreakService` (rewrite): fires `StreakPaid`, binds `GetStreakInfo`, no join Notif.
- `ServerStorage.ServerController.RebirthService` (2 edits): `GetRebirthInfo` + `lockSeconds`/`nextLockSeconds`; `UpdateTag` badge sizing.
- `ReplicatedStorage.Modules.UserInterfaceLoader.RebirthNewFrame` (Refresh/OnStart): headline "YOUR LOCK: 90s → 105s", "+1 PODIUM (6 → 7)" (+ "NEW FLOOR!"), "⭐ BADGE ON YOUR HEAD" / "BADGE N → N+1"; cost/bar/confirm untouched.
- Cross-edits: `UserInterfaceLoader.Main` (bar map, gated "+", Nuke binding removed); `UserInterfaceLoader.Notifications` (non-Error toasts dropped until DoneTutorial; `{Force = true}` bypasses).
- Kept: `NukeClient`/`NukeUI` (boss payback nuke still uses `BossStrike`/`Impact`), `RebirthArrowClient`, `Settings`, `CharacterModule`.

Playtime ladder (`PlaytimeRewards`; claim flow unchanged; no egg/pet tiers):

| Tier | Time | Reward | QA2 observed |
|---|---|---|---|
| 1 | 30 s | 1,000 Coins | +1,000 |
| 2 | 2 m | 2,500 Coins | +2,500 |
| 3 | 5 m | 2x Coins boost 10 min (`BoostHandler.AddBoost(P, "2x Cucumbers", 600)`, applied to Coins by the one-currency merge) | toast "2X COINS - 10 MIN!" |
| 4 | 10 m | 15-min time skip (`TimeSkipRateService` quote, paid in Coins) | +15,300 |
| 5 | 18 m | 5,000 Coins | +5,000 |
| 6 | 30 m | `trail_gold` once ever via `CosmeticsService.Grant` (already owned / later sessions: 10,000 Coins; the once-flag is not burned if the service is absent) | +10,000 (trail already owned from the index ladder) |
| 7 | 1 h | 2-h time skip | +122,400 |
| 8 | 1.5 h | GOLDEN Spawn "Cucumber" on the arm once ever (refused "STORE YOUR CUCUMBER FIRST!" while carrying and left claimable; later sessions 1-h skip) | refused while carrying, granted with an empty arm |

Layout (design px × scale; y = 0 is under the topbar): desktop 1920×1080 chip 300×32 at x 810..1110, y 8..40, `TopSlotBottom = 40`, friend pill top y 48, Steals pill 100×29, Streak chip 62×29, StreakCard 230×95 at x 160; iPhone 13 landscape 844×390 chip 252×27 at y 8..35, `TopSlotBottom = 35`, StreakCard 166×69 above the wallet; QA2 at 1301×611: chip (512,8) 276×29, `TopSlotBottom = 37`. Tutorial banner clamp: desktop keeps its authored 20 % rest; phones dock at anchor bottom + 2.

Contracts:
- Consumes: `ReplicatedStorage.EventClock` attributes (`ActiveEvent`, `ActiveEventEndsAt`, `ActiveEventLabel`, `NextEventName`, `NextEventAt`, `NextEventLabel`, `BossNextAt`, `PickleDay`), player attributes `TotalSteals`, `StoreGateOpen`; `CosmeticsService.Grant(player, "trail_gold")` (pcall; must return true on success).
- Fires: `ServerStorage.Events.StreakPaid {player, day, amount}` (day = streak count).
- Provides: Network functions `GetStreakInfo -> {Count, Day, Today, PaidToday, Amount, Rewards}`, `GetRebirthInfo.lockSeconds / nextLockSeconds`, `GetPlaytimeState.Next = {Index, Remaining, Name, Ready}`; HUD ScreenGui attribute `TopSlotBottom` (px, HUD/inset space); `HudMetrics.storeGateOpen()` (= `StoreGateOpen` attribute OR `HudDev` containing `gate:open`), `topSlotBottom()`, `topChipScale()`.
- Panels are opened by their real frame names `Rebirth`, `Playtime`, `CucumberIndex` (the brief's `OpenFrame("RebirthNewFrame")` would no-op). `GetStreakInfo.PaidToday` is per server session.

Dev hooks: `HudDev = "gate:open"` (client-side gate only); `PlaytimeSpeedDev = 60` (Studio); `PlaytimeRewards.DebugAddTime(player, sec)` from a server eval.

### 4.8 STORE (one currency, micro products, gate, removals)

Files (sources `SP\lua\store-*.lua`, region edits `SP\lua\edits\`):
- `ServerStorage.ServerController.CurrencyHandler` (full rewrite): `AddCurrency` with `Currency="Cucumbers"` keeps the Cuke multiplier stack (`GetMulipliers` unchanged: × 2^Rebirths × 2 pass × Pets.Multi1 × 2 boost × 1.5 group) and pays **Coins**; `Indicate` fires with `Currency="Coins"`; `HasTotal` credits `TotalCoins` (+ legacy `TotalCucumbers`); `RemoveCurrency`/`CheckIfEnough` with "Cucumbers" read/write Coins; `SetCurrency("Cucumbers")` still targets the inert `RawStats.Cukes`; `WalletCurrency(currency)` exported; `Initialize` loop re-syncs `leaderstats.Steals` every 10 s.
- `ProfileService.InstanceValues` (full rewrite): join-time migration of any saved `Stats.Cucumbers` into Coins 1:1 (logged "[CurrencyHandler] one-currency migration: NAME had N Cukes -> +N Coins"); `leaderstats` = `Coins` (StringValue), `Rebirths` (NumberValue), **`Steals`** (IntValue); **`leaderstats.Cukes` removed**; `RawStats.Cukes` kept inert.
- `ProfileService.UserData`: `TotalStats.TotalSteals = 0`, `PendingCarries = {}`, `LastTheftRecoveredAt = 0`.
- `ReplicatedStorage.Modules.ControllerLoader.Custom.ProductController` (full rewrite): gamepass `DisplayName` ("2x Cucumbers" → "2x Coins", "Autofarm" → "Auto Smash"; keys unchanged); `DisplayNameFor(id)`; `TutorialDone(player)`; `Products.Micro` (6 keys, `Id = 0`, prices 10/10/15/15/25/25); `Products.Legacy` (Nuke 3610280695, Break Into Base 3710299055); `Products["Break Into Base"]` removed; Starter Pack `Items = {Coins = 20000, GoldenCucumber = true}` (pet removed), "COINS + A GOLDEN CUCUMBER"; `CheckGamepass(..., true)` and `PromptProduct` refuse before DoneTutorial (`false, "TUTORIAL"` / `"NO_ID"`); Bigger Vault = TODO.
- `ServerStorage.ServerController.ProductHandler` (full rewrite): micro receipts by key → `MicroStoreServer.Grant`; Starter Pack → Coins + `MicroStoreServer.GrantGoldenCarry`; legacy ids → false → `NotProcessedYet` (refund); `NukeService`/`BaseBreakInService`/`FrameworkLoader` requires dropped.
- NEW `ServerStorage.ServerController.MicroStoreServer`: gate, server-side prompting with context, receipts, Starter Pack golden carry + `PendingCarries` delivery loop (5 s, across sessions), dev hooks.
- NEW `ReplicatedStorage.Modules.MicroStore` (client contract; server-side require returns a no-op stub). NEW `StarterPlayerScripts.MicroStoreClient` (requires it after `game.Loaded`).
- `UserInterfaceLoader.Store` (full rewrite): Pickles (farm skip) cards quote `+$N`; STARTER PACK card first in BUNDLES (spinning procedural golden cucumber viewport, live price); every buy → `PromptProduct`; "CUCUMBERS/CUKES" labels rewritten to COINS at runtime.
- `UserInterfaceLoader.Main` (`OpenFrame`): Store and Offers refuse to open while the gate is closed → toast "🔒 SHOP UNLOCKS AT FIRST REBIRTH!".
- `UserInterfaceLoader.Vault`: offline "Keep Farming" claim icon → coin (`rbxassetid://116353151524980`).
- `NukeService`: `Launch` is a refusing stub; `BossStrike` untouched. `GroupOfferService`: 60-s join popup removed (group chest `PromptJoin` and 1.5× perk stay). `GroupOfferClient`: toasts say "1.5x Coins".
- `ServerScriptService.SellVendorServer`: `SellAll` no longer touches any balance ("🥒 SELL THE CUCUMBER ON YOUR ARM!"). `QuestBoardService`: claim toast "⏱ TIME SKIP! +$N COINS!". `StarterGui.GamepassPopup.PopupController`: never opens before DoneTutorial; cards only when the gate is open (else "🔒 PASSES UNLOCK AT FIRST REBIRTH!"). `StarterGui.PromotedPets.PromoteHandler`: BUY through `PromptProduct` ("FINISH THE TUTORIAL FIRST!"), stat line "NX COINS".
- Cross-edit `ServerScriptService.MinigameCompletionService`: reward toast "+$N COINS!".
- Untouched on purpose: `TimeSkipRateService`, `OfflineService`, `Offers` module, `LikePromptClient`, `FavoritePromptService`, `CucumberVendorClient`.

Numbers:
- Gate: **`StoreGateOpen` = DoneTutorial AND (`leaderstats.Rebirths ≥ 1` OR session ≥ 15 min)**, refreshed at join and every 10 s. Skipping the tutorial still opens nothing until rebirth / 15 min.
- Products: display prices 10 / 10 / 15 / 15 / 25 / 25 R$; StickyHands +5 catches; SecondArm +600 s; Starter Pack **20,000 Coins** + GOLDEN Spawn "Cucumber" (`FindType("Spawn","Cucumber")` cloned with `Golden=true`, Reward ×12, `RateV=4`) via `CarryService.Restore` (arms full / mid-tutorial → `UserData.PendingCarries`, delivered by a 5-s loop, also across sessions).
- `MicroStorePrompt` 1.5-s rate limit. Contextual pill ~8 s (`opts.seconds`), bottom-centre above the button bar, title + one-line pitch + ✕, newest replaces current; per-key cooldown StickyHands / SecondArm / PickleNow / VintageNow 20 s, VaultInsurance 30 s, FieldRestock 60 s (`opts.force` bypasses).
- Auto hooks (no cross-edits): STICKY HANDS 0.7 s after a smash if `CarryingCucumber` is unchanged and `StickyHands == 0`; SECOND ARM 2.5 s after `CarryShowcase{Upgraded=true}`; VAULT INSURANCE 3 s after `RobbedBy` is set; FIELD RESTOCK when the 5-s watcher sees `#workspace.Breakables.<CurrentBiome>` < ½ × (`Target` | `TargetPopulation` | `Target_<zone>` | 12). FIELD's own `ShowContextual` calls are deduped by the cooldown.
- Vault Insurance pre-prompt fallback: `UserData.LastTheft.at` within 3,600 s and not already recovered. `leaderstats.Steals` re-synced every 10 s.
- One-currency maths unchanged: Cuke-sourced grants × 2^Rebirths × 2 (2x pass) × Pets.Multi1 × 2 (boost) × 1.5 (Group Frenzy) land in Coins; QA2: `AddCurrency{Currency="Cucumbers", Amount=100}` → +150 Coins, `WasPurchase=true` → +100 flat.

Contracts:
- Client `ReplicatedStorage.Modules.MicroStore`: `Prompt(productKey, context?)` (silent before DoneTutorial; `Id == 0` → toast "🚧 COMING SOON!"; else `Network:FireServer("MicroStorePrompt", key, context)`); `MakeButton(parent, productKey, context?) -> TextButton` (pill "🫙 PICKLE NOW · 10 R$", FredokaOne, UICorner 8, default Size (1,0,0,26), hidden until DoneTutorial, forwards `context`, live dashboard price once the id exists, never a countdown); `ShowContextual(productKey, opts?)`; `NoteSmash()`. Keys `PickleNow, StickyHands, FieldRestock, SecondArm, VintageNow, VaultInsurance, StarterPack`. Server-side require returns a no-op stub.
- Server `ServerStorage.ServerController.MicroStoreServer`: `RefreshGate(player)`, `GateOpen(player)`, `CanBuy(player, key, context) -> ok, reason` (PickleNow / VintageNow → `VaultService.CanPickleSkip`, else a stall scan; VaultInsurance → `VaultService.CanRecoverLastStolen` if present, else the profile window; FieldRestock zone = `CurrentBiome` | `BreakablesService.SlabZoneAt(root)` | "Spawn"); `Grant(player, key, receipt) -> bool` (from ProductHandler) → `Apply(player, key, context)` (owner APIs resolved through the registry at call time and pcall'd; a missing one warns "X.Y not available yet" → `NotProcessedYet` → retried, eventually refunded); `GrantGoldenCarry(player)`; `Pending[player] = {Key, Context, Id, At}`; `JoinedAt[player]`.
- Remotes: event `MicroStorePrompt(key, context)` (the SERVER calls `MarketplaceService:PromptProductPurchase`); function `MicroStoreCanBuy(key, context) -> ok, reason`. Analytics `MicroBuy_<Key>` per applied grant.
- `ProductController.TutorialDone(player)`, `DisplayNameFor(id)`, `PromptProduct(...) -> ok, reason` ("TUTORIAL" / "NO_ID"); `CheckGamepass(..., true)` skips the prompt before DoneTutorial; `GetProductInfo` skips id 0.
- Profile keys written: `PendingCarries`, `LastTheftRecoveredAt`; `leaderstats.Steals` (IntValue) mirrored from `TotalStats.TotalSteals` / the `TotalSteals` attribute (InstanceValues creates it; `SyncHeistProfile` is the backstop).

Dev hooks: `StoreDev = "gate:open" | "gate:close" | "gate:auto"`; `ProductDev = "grant:<Key>:<PlayerName>[:<spot>]"` | `"prompt:<Key>:<PlayerName>"` (keys above + `GoldenCarry`).

---

## 5. Cross-edits and QA fixes

### 5.1 Cross-edits log (`_CROSS-EDITS.md`, build phase)

| By | File | Edit |
|---|---|---|
| CLOCK | `BreakablesService.Break()` | post-boss hook `if not data.Nuke and StartEventChallenge then` → `... and workspace:GetAttribute("PostBossSelectorDev") == true`: random post-boss selector OFF. Runtime only: EventClock fills a MISSING `Duration` on GoldenHour/HarvestMoon registry entries with 120. |
| FIELD | `CarryService.TryAwardFromBreak` / `GiveCarry` / `Take` | showcase `OneIn` = `rarity * (data.CatchChance or 1)` (folds the catch roll into "[1 in X]"); carry `Size` carried through meta → entry → `Take()`. |
| INDEX | `UserInterfaceLoader.Initialize()` | one `CucumberIndex = UserInterfaceLoader.new({...DoesUpdate = true})` line after `Playtime`. |
| HEIST | `Dictionaries.Upgrades.setWalkSpeed` | `Speed /= 1.5` → `Speed *= 2 / 3` (value unchanged). |
| HEIST | `VaultService.SyncHeistProfile` | creates `leaderstats.Steals` IntValue if InstanceValues has not (STORE now owns it; same name). |
| HUD | `UserInterfaceLoader.Notifications.CreateNotification` | drops non-Error toasts until DoneTutorial; `{Force = true}` bypasses. |
| HUD | `UserInterfaceLoader.Main` | bottom-bar map PETS=Pets, "PET INDEX"=CucumberIndex (fallback Index), TRADING=Trade, SHOP=Store gated by `HudMetrics.storeGateOpen()`; wallet "+" gated (toast "UNLOCKS AT FIRST REBIRTH!"); Nuke rail binding removed (`local nuke = nil`). |
| TUTORIAL | `FavoritePromptClient` | native favourite prompt waits for DoneTutorial (bounded 15 min) + 20 s. |
| STORE | `MinigameCompletionService` | reward toast "+N CUCUMBERS!" → "+$N COINS!". |
| STORE | `UserInterfaceLoader.Main.OpenFrame` | Store/Offers gate block (self-contained at the top of the function; HUD edits the same file elsewhere). Listed in STORE.md only, not in `_CROSS-EDITS.md`. |

### 5.2 QA fixes (QA phase; all compile-checked; 2–7 not re-verified live)

| # | By | File | Fix | Cause |
|---|---|---|---|---|
| 1 | QA2 | `StarterGui.Display.Frame.Frames.Rebirth.InnerFrame.LockTimeValue` | ZIndex 71 → 72 (verified by a tree walk) | PanelMetricsTest tie with `VaultValue` (z=71) |
| 2 | QA2 | `UserInterfaceLoader.PlaytimeNewFrame.glyphFor()` | `g.ZIndex = icon.ZIndex + 1` → `= icon.ZIndex` | client log "ImageButton (z=30) does not sort above Glyph (z=30)" (sibling tie) |
| 3 | QA2 | `BreakablesService.PlanCatch` | slow-mo test `data.OneIn >= 1000` → `(1 / math.max(BreakablesService.CarryRarityOf(data), 1e-9)) >= 1000` (spawn-share odds only) | a plain NEON catch set `SlowMoUntil` because the folded odds read "1 in 1,619"; FIELD's own rule says a plain NEON must not slow-mo |
| 4 | QA2 | `BreakablesService` toast strings | "750X CUCUMBERS!" / "%dX CUCUMBERS!" / "+%s CUKES!" (boss kill) / "%s ESCAPED! +%d CUKES" → COINS | one currency (STORE's request to FIELD) |
| 5 | QA1 | `DillService.groundY()` | `RaycastParams.RespectCanCollide = true` + re-cast from `expected + 5` when the first hit is > 8 studs above the expected level | the bank `RowRoof` (y 18.4) sits over every podium and the aisle carpet is non-collidable: the raid's blocked-path "step in" would have put Dill on the roof and every aisle/spawn probe fell back |
| 6 | QA1 | `VaultService.AssignStall()` | first-session players (profile `DoneTutorial ~= true`, or profile not loaded) take even stall ids first (2,4,6,8 then 1,3,5,7); finished players keep 1..N; no new top-level local | sequential assignment gave the first fresh player Stall_1 (north row) whose door lands in the LEFT third of the spawn view |
| 7 | FIELD (post-QA2) | `BreakablesService` (4 anchors) | Spawn break meter INERT: no charge, no summon, paid skip refused in Spawn; attribute `MeterInert = true`; `Required`/`BossActive`/`BossHP`/`BossMaxHP` keep updating | QA2 saw the hidden meter still summon BIG GHERK after ~95 breaks at rebirth 0; the boss must arrive only on the clock |

QA3 made no edits.

---

## 6. Known gaps and deliberate deviations from the spec

Deviations (decided, documented):
- **Second Arm is the queue variant**, not two welded carries: one active carry + one parked visual on the right shoulder (`PendingCucumber`); the parked jar auto-equips when the arm frees ("NEXT CUCUMBER READY"), cannot be stored directly, and stealing needs both arms empty ("ARMS FULL!").
- **Index total is 1,485, not 1,566**: the key has no zone and three names are shared across zones (Sliced Cucumber ×3, Cucumber Tree ×2) → 55 unique names × 27. A shared name lights the tile in every zone it appears in.
- **"[1 in X]" folds spawn share × size share × catch chance** (same number in the chat line, the showcase card and `CucumberCaught.oneIn`): a NEON common reads ~1 in 787 at a fresh 20 % roll (FIELD's load test) and "1 in 1,619" as observed live by QA2 later in the session (the number grows as the catch chance decays with TotalBreaks), not the spec's illustrative "1 in 100". `MutationColors.Odds` holds the per-spawn "1 in 76" for UI that wants it. Slow-mo now keys off spawn-share odds only (QA2 fix 3).
- **Secret payout magnitude:** THE LEGEND is Reward ×1,000 - one Spawn break paid **24,102,000 coins** in QA2's playtest, its vault rate is ~36 coins/s in Spawn, and its first UPGRADE cost 18,431 Coins. By design; retune `MUTATIONS.Secret.Mult` if that is too much for a "free to find" legend.
- **Tutorial v4 replays once for EVERY existing save** (finished or not): next join sets `DoneTutorial=false`, `TutorialStep=0`, stamps `TutorialReplayedAt`. Until they finish or skip ("skip" is one tap): fresh-spawn framing, no ordinary catches (CarryService's mid-tutorial gate), quiet gates, and `StoreGateOpen` is false (it requires DoneTutorial). `ClaimedTutorialPet` prevents a second Lil Pickle / 250 Coins.
- **`leaderstats.Cukes` removed**; `RawStats.Cukes` stays as an inert value; any saved `Stats.Cucumbers` balance migrates into Coins 1:1 on the next join. The vendor's "sell all Cukes" is gone. `AdminPanel` "SetCurrency Cucumbers" still writes the inert value (migrates next join).
- **Micro products have `Id = 0`** until the owner creates them (§2 step 6): buttons show "COMING SOON", nothing prompts. Starter Pack keeps `3609836817`.
- **Spawn boss meter is inert** (FIELD post-QA2): BIG GHERK comes only from the clock (:30), `SpawnBossDev`, or the admin panel. The other seven zone meters still charge and summon. CLOCK's note "the boss meter keeps summoning by breaks" is stale for Spawn.
- **Vault rate honours size** (PICKLE: GIANT ×2 / SMALL ×0.6 in `CarryService.EffectiveRate`, matching the field payout); FIELD's note "vault EarnRate ignores size" is stale. Revert = delete the one `record.Size` line.
- **The random post-boss event selector is OFF** (`PostBossSelectorDev = true` restores it); zone event cooldown lowered 300 → 60 s so the clock's four events an hour do not block meters (CLOCK's "5 min cooldown" gap is resolved).
- **Odd (north-row) stalls land in the LEFT third** of the opening frame (the aisle runs east-west; only south-row stalls can be on the right while facing the field). Mitigated by QA1's even-stall-first assignment for first sessions.
- **A rarer field catch while hauling stolen loot is ignored** (was: swapped and returned the loot); parks if Second Arm is active.
- `EquipCosmetic` is a RemoteFunction (InvokeServer), not an event. Sizes give index badges only, no coins. The index enables only owned zones (locked zones refuse selection).
- Panels open by frame name (`Rebirth`, `Playtime`), not module name.
- HeistHud stack sits at a fixed y = 92 px rather than HUD's requested `TopSlotBottom + 8`; no overlap on desktop (chip bottom 40) - eyeball on phones.
- Practice-vault jar takes are NON-stolen carries (teleports allowed, normal speed); the beat-5 raid is a bluff (the record never moves).

Known gaps (not done / not verified):
- **No 2-player playtest ever ran** and no human has seen the screen: every heist, revenge, DASH, Second Arm, Vault Insurance, pickling visual, tutorial beat, Dill walk/chase/raid and phone layout is static-only (§1).
- **Vault Insurance works only while the stolen record is still in THIS server** (thief's arm or podium): HEIST asked PICKLE to persist `Uid` in `SaveVault`/`LoadVault`; PICKLE's report does not record doing it. STORE's pre-prompt check falls back to the profile's `LastTheft` window (3,600 s) because HEIST did not add `VaultService.CanRecoverLastStolen`.
- `Heist.Return`'s rebuilt-from-snapshot path (thief died, carry model destroyed): PICKLE flagged it would restart the jar FRESH; QA3's read of the live source says the snapshot now copies every field incl. `AgeSec` - confirm in t3-expire / t10c-theftage.
- `StreakPaid` → Dill's "Day N streak!" line, the friend-boost pill under the chip, the 60-s warning line at a real :19/:39/:59, and the `ClockSpeedDev=60` warn/start/end sequence were not observed live.
- Heist chat lines use `DisplayName`; TextChatService may filter emoji on some platforms (rich text falls back to the legacy system message).
- Heist clock text uses the client's `os.time()` (both UTC); ±1 s skew possible. `ServerTimeOffset` is fractional.
- `PickleSpeedDev`, `ClockSpeedDev`, `PlaytimeSpeedDev` are Studio-only. Offline ageing uses the previous session's `VaultLastSave` (a crash loses at most one second).
- `CurrentBiome` is "last zone hit, never cleared", so a player at the bank still counts their last zone for clock events (a little generous).
- Boss killed-vs-escaped is inferred from lifetime (≥ 6 min − 3 s = escaped).
- Dill walks with the default R15 walk animation (`rbxassetid://507777826`); pathfinding through the arch relies on the navmesh, with `MoveTo` and a PivotTo "step in" as fallbacks. The practice-vault slab overlaps `Points.Sell.SellAssets.Safe_Plane.001` below y 3 (hidden).
- `HeistCombatClient` still binds the now-unused `HeistRolePrompt` (harmless). `RebirthService.UpdateTag` badge block carries one extra indent level (cosmetic).
- Authored GUI art still shows cucumber icons on pet-bundle Multi1 stats and the boost card; `GroupRewardsGui` text says "1.5x cucumbers" (§2 step 11).
- The card's AGED StageLine renders small on phones until you stand in your own stall; 🫙 may render as a box on old emoji fonts.
- `TOP THIEVES` needs DataStore access to fill (this test place has none; empty board expected). Position picked by bounding-box parity with TotalCoins - eyeball for clipping.
- `TutorialDev="beat:N"` jumps the client only. Resume / replay-once (QA1 D9–10) cannot be tested in this place (fresh account every playtest, no DataStore).
- QA2's client recorder lost everything before 20:41:36 UTC, so the exact VOID / LEGEND / restock / "STORE YOUR CUCUMBER FIRST" chat + toast lines were not read back (the server paths ran without error).
- HP-bar GIANT/SMALL badges and the restock "≥ 25 % specials" wave (3/16 seen) not confirmed.

---

## 7. How to test each feature fast

All are workspace attributes set from the **server** context (`workspace:SetAttribute("Name", value)` in a server eval or the command bar with the Server view selected) unless marked client. Every playtest in this place is a fresh account (no DataStore → ProfileService mock): to skip the tutorial fire the game's own remote from a client eval, `Network:FireServer("Tutorial", true)`, then hide/disable `TutorialClient`. Run `node "$BR/checkall.js"` (expect 283/0) before any playtest. Playtest lock: `node "$BR/pt-lock.js" acquire <name> 3600` / `release <name>`.

| System | Attribute / call | What it does |
|---|---|---|
| Field | `CatchDev="force:Name"` | next break lands on the arm |
| Field | `SizeDev="Spawn:GIANT\|SMALL\|NORMAL"` · `MutationDev="Spawn:NEON\|…\|VOID\|PRISMATIC\|DIAMOND\|SECRET"` | spawn one of that size / mutation |
| Field | `RestockDev="Spawn[:Buyer]"` · `SmashDev="Spawn"` · `StartEventDev="Spawn:GoldenHour\|HarvestMoon\|CucumberSmash"` | restock / force a Cucumber Smash / start a zone event |
| Field | `SpawnBossDev="Spawn"` · `KillBossDev="Spawn:Name"` · `PostBossSelectorDev=true` | boss on/off; restore the old post-boss selector |
| Field | player attribute `StickyHands=3` | next 3 breaks catch |
| Clock | `ClockDev="next:GOLDEN_HOUR\|HARVEST_MOON\|BOSS"` · `"stop"` · `"warn:GOLDEN_HOUR"` · `"pickle:on\|off\|auto"` · `"say:hi"` · `"mock:start\|caught\|banked\|expired\|revenge"` · `"streak:3:800"` · `"status"` | force windows, lines, Pickle Day |
| Clock | `ClockSpeedDev=60` (reset to 1/nil after) | a full hour cycle per real minute |
| Heist | `VaultStealDev="seed:A"` / `"seed:A:NEON"` / `"grab:A:B"` | seed a jar on A's podium / teleport B and steal it |
| Heist | `LockDev="expire:A"` / `"left:A:12"` · `HeistDev="expire:B"` / `"dash:B"` / `"cooldown:B"` | drop A's lock / 12 s left; end B's heist / dash / clear B's cooldowns |
| Heist | player attribute `SecondArmUntil=os.time()+600` | Second Arm on |
| Heist | server eval `GetModule("VaultService").RecoverLastStolen(A)` | Vault Insurance path |
| Pickle | `PickleSpeedDev=60` (reset to 1) | ages 60 s per second (PICKLE at ~10 s, AGED ~60 s later) |
| Pickle | `PickleDev="advance:Name[:spot]"` / `"vintage:Name[:spot]"` / `"age:Name:spot:3599"` / `"reset:Name"` / `"gone:Name"` | stage jumps; `gone` shows the WHILE YOU WERE GONE card |
| Pickle | `OfflineBannerDev=true` · EventClock attribute `PickleDay=true` | leave-intent banners without the menu; ×2 ageing |
| Tutorial | `ServerStorage.ForceTutorialOnJoin=true` (BoolValue) · `TutorialDev="beat:N"` · `DillDev="raid:Name"\|"steal:Name"\|"say:hi"\|"home"\|"walk:x,z"` | replay; jump to beat N (client); drive Dill |
| Index | `IndexDev="discover:Name:10"` / `"catch:Name:Sun-Baked_Cucumber:GOLDEN:NEON:GIANT"` / `"secret:Name"` / `"reset:Name"` · `CosmeticDev="grant:Name:trail_gold"\|"grantall:Name"\|"clear:Name"` | discoveries, rewards, ladder, cosmetics |
| HUD | `HudDev="gate:open"` (client-side gate) · `PlaytimeSpeedDev=60` · server eval `PlaytimeRewards.DebugAddTime(player, sec)` | rail/SHOP visible; all playtime tiers ready in ~90 s |
| Store | `StoreDev="gate:open"\|"gate:close"\|"gate:auto"` · `ProductDev="grant:<Key>:Name[:spot]"` / `"prompt:<Key>:Name"` | open the gate; simulate a receipt (keys: PickleNow, StickyHands, FieldRestock, SecondArm, VintageNow, VaultInsurance, StarterPack, GoldenCarry) |
| Everything | `node "$BR/logs.js" server\|client-1\|client-2 [--level warn] [--grep text]` · `ServerStorage.Events.<HeistEvent\|CucumberCaught\|TutorialBeat\|StreakPaid>.Event:Connect(print)` from a server eval | read output; watch the contract events |

Reset every dev attribute (and `ForceTutorialOnJoin`) before stopping; leave no scratch instances. Ready-made drivers: `SP\lua\qa2\*.lua` (field/clock/index/HUD/store/playtime, `ev.js`), `SP\lua\qa3\*.lua` (2-player heist + pickling, `run.js`), `SP\lua\qa1\*.lua` (tutorial, `run.js`).
