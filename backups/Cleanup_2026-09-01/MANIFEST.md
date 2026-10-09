# Cleanup 2026-09-01: unused code and in-place backups removed from the live game

Place: `[NEW] Collect a Cucumber 🥒` (place `116126086405931`, universe `10439954561`), edited in the open Studio session (Team Create) on 2026-09-01.
Everything deleted was first exported to the four `.rbxm` files in this folder. Three read-only audit agents grepped all 490 scripts (and ran an ObjectValue scan) to prove each item had zero live references; the evidence summary is in each section below.

## Restore

Right-click in the Studio Explorer → **Insert from File** → pick the `.rbxm` → move the restored instances back to the paths listed here. `04-edited-scripts-before.rbxm` holds the pre-edit copies of the five scripts that were surgically edited (paste their Source over the live script to revert the edits).

| File | Contents |
|---|---|
| `01-serverstorage-backups-and-staging.rbxm` | 23 ServerStorage/ReplicatedStorage backup, staging and plugin-residue instances (1.8 MB) |
| `02-dead-code-and-orb-system.rbxm` | 26 dead modules, the legacy orb system, unused assets, inert kit scripts |
| `03-ui-and-client-leftovers.rbxm` | 18 disabled client scripts, orphan ScreenGuis, unused templates |
| `04-edited-scripts-before.rbxm` | ServerNetwork, Server, UserInterfaceLoader, UIPreloaderClient, StarterPlayerScripts.Client before the edits |

## 1. ServerStorage backups, staging and plugin residue (deleted)

| Path | What it was | Evidence |
|---|---|---|
| `ServerStorage.__OldPetsBackup` (2,549 desc.) | 42 old pet models | 0 references; live pets load from `ReplicatedStorage.Assets.Pets` |
| `ServerStorage.__OldBossPetsBackup` (290) | 8 old boss-pet models | 0 references |
| `ServerStorage.Leaderboard` (ScreenGui) | authored design; integrated as `StarterGui.SmashLeaderboard.LeaderboardFrame` | 0 references |
| `ServerStorage.Rebrith` (ScreenGui) | authored rebirth frame; integrated as `Display.Frame.Frames.Rebirth` | 0 references (unique misspelling) |
| `ServerStorage.Rewards` (ScreenGui) | authored playtime panel; integrated as `Display.Frame.Frames.Playtime` | 0 references |
| `ServerStorage.SellPets` (ScreenGui) | authored pet-sell frame; integrated as `CucumberVendorUI.PetSellLayerNew` | all `SellPets` hits are the RemoteFunction |
| `ServerStorage.UIFrameIntegrationStaging` | 2026-08-24 staging (2 disabled scripts, 2 module copies) | 0 references |
| `ServerStorage.UIFrameBackups` (336) | pre-integration Playtime/Rebirth frames | 0 references |
| `ServerStorage.__BrokenPanelBackup_2026-08-24` (1,627) | broken-panel incident frames + 3 dead modules | 0 references |
| `ServerStorage.LobbyBackup_20260825` (467) | lobby Area 1 snapshot (also in `backups/LobbyArea1_backup_2026-08-25.rbxm`) | 0 references |
| `ServerStorage.CucumberBankBackup_v1` (446) | v1 bank geometry (also in `backups/CucumberBank_v1_backup_2026-08-26.rbxm`) | only a header comment in VaultService |
| `ServerStorage.BankUserWalls_v1_backup` | four v1 bank walls | 0 references |
| `ServerStorage.VaultBackup_PreFloors_2026_08_26` (450) | pre-floors VaultService/RebirthService/geometry | only a header comment in VaultService |
| `ServerStorage.SFXPassBackup_2026_08_26` (112) | 49 pre-SFX-pass script copies | 0 references |
| `ServerStorage.RecoveredVaultCucumbers` (StringValue) | recovery JSON from the 2026-08-26 vault wipe incident | 0 references |
| `ServerStorage.UpgradeBoardsBackup_2026_08_27` | pre-overhead-card scripts | comments only |
| `ServerStorage.MegaCucumberBackup_2026_08_27` | deleted meteor event scripts | 0 references |
| `ServerStorage.DoorLockModelBackup_2026_08_30` (36) | six `*_Lock` door models | 0 references |
| `ServerStorage.changeinblender_original_2in1_backup_2026_08_27` (MeshPart) | original 2-in-1 cornice mesh | 0 references, mesh id unused |
| `ServerStorage.PluginCurves`, `ServerStorage["COF's Eyedropper"]` | plugin residue | 0 references |
| `ServerStorage.EconomyBackup_PreRedesign_2026_08_28` (167) | 33 pre-redesign economy scripts + README_REVERT | 0 references; the same pre-redesign code is in `backups/EconomyRedesign_2026-08-28/` (rbxm + .lua dumps); its README said "do not delete", overridden by the cleanup request with this export as the replacement |
| `ReplicatedStorage.UpgradeSignTemplate` (Part + SurfaceGui) | podium sign template from the removed sign design | only cloned by a script inside the deleted UpgradeBoardsBackup |

## 2. Dead server and shared code (deleted)

| Path | Why unused | Evidence |
|---|---|---|
| `ServerController.PathService` | first-session "choose your path" picker; its three pets no longer exist | no `GetModule("PathService")`, no client invokes `GetPathState`/`ChoosePath` |
| `ServerController.WalkCucumberService` | map time-skip pickups, `MAP_PICKUPS_ENABLED = false`, Initialize returns immediately | only self-references |
| `ReplicatedStorage.Assets.TimeSkip` (Model, 40 children) | pickup model used only by WalkCucumberService | single reference (WalkCucumberService:14) |
| `StarterGui.UITemplates.PickupLabel` | pickup label used only by WalkCucumberService | single reference |
| `ServerController.CollectionService` | legacy walk-over orb system, never lifecycle-called (blacklisted from Initialize, in no whitelist) | only ServerNetwork line 14 (unused variable) and a stale comment |
| `FrameworkLoader.Client.ClientHandler.CollectionClient` (+ `OrbTween`, `ZoneDetection`) | client half of the orb system; `Initialize` is a no-op, its loop had no callers | only self-references |
| `Workspace.Collectables`, `ReplicatedStorage.Assets.Particles.Collectables` | orb spawn folder and particles | only CollectionClient referenced them |
| `ServerStorage.Assets.Circle` | orb-era pickup ring, only cloned by the never-called `CollectionService.CharacterJoined` | PickaxeService and Client only resized/hid it if present |
| `ServerController.ArmorHandler` | empty Initialize, functions only called from itself | 0 external references |
| `ServerController.ChatHandler` | no-op shim | 0 references |
| `ControllerLoader.Imported.MyTimer` | unused library | 0 matches in 490 scripts |
| `FrameworkLoader.Client.CraftController` | empty module | 0 references |
| `UserInterfaceLoader.Teleport` + `Display.Frame.Frames.Teleport` | orphan panel replaced by the HUD BUY/BIOME/SELL pills | only the loader entry (edit E4) and a tolerant preload list (edit E5) |
| `UserInterfaceLoader.Stats` | Stats panel removed 2026-07-03, never loaded | 0 references, no frame |
| `ServerScriptService.GoldenCucumberStatue` | empty Script (`""`) | 0 references (the workspace statue model stays) |
| `Workspace.Points.Sell.VendorDecor["Circle Light"].MovingRingBeam.RotateRingBeam`, `Workspace.ShopNew["Circle Light"].MovingRingBeam.RotateRingBeam` | disabled server spinners replaced by `RingBeamSpinnerClient` | RingBeamSpinnerClient's header documents the replacement |
| Inert kit scripts inside minigame templates: `Avalanche.MapHandler`, 5× `Avalanche.Cannons.Model.Script`, `LavaRun.MapHandler`, `BloxoutIncorporated.MapHandler`, 5× `BloxoutIncorporated.Interior.Building.TripWire.ScaledModel.Script`, `BloxoutIncorporated.Exterior.Decoration.Arrow.LocalScript2`, `Wild_West.Bank.Vault.VaultScript`, `ReplicatedStorage.Missle.Tip.Boom`, `ReplicatedStorage.AvalancheBall.Script` | every portal service (and NukeService for the missile) force-disables all scripts in each clone; the services reimplement cannons, tripwires, spinners and the missile blast | `MapHandler` 0 hits; disable loops at SnowPortalService 421, LavaPortalService 395, DesertPortalService 544, VoidPortalService 402, NukeService 100 |

Kept on purpose: `ServerStorage.Assets.Collectables` (BreakablesService reads it for every spawn's base colour), both `Module3D` copies (both required), `CameraShaker` (BreakablesClient), `ZonePlus`, `Leaderboards`, `SeasonService` + `HallOfGreen` (planned feature behind a flag), `Revolver` kit internals (toggled live), `CarryControls` (style source), `MessageHandler` (welcome chat line), `ReplicatedStorage.petsize` (EquipService size cap).

## 3. Disabled client scripts and orphan UI (deleted)

| Path | Why unused | Evidence |
|---|---|---|
| `StarterPlayerScripts.IntroCutsceneClient` (disabled, 1,812 lines) | intro cinematic retired; TutorialClient publishes the inactive attributes itself | other scripts only read `IntroCutsceneActive` with nil-safe guards |
| `StarterPlayerScripts.StarterPackClient` (disabled) + `Display.Frame.StarterPack` frame | timed Starter Pack popup; nothing else renders the pack (the Offers panel has no pack card) | only mutual references; server handlers left intact |
| `StarterPlayerScripts.HudTooltips` (disabled) + `StarterGui.HudTooltip` | targeted `Display.Frame.Left` which no longer exists | MinigameHudController lists the gui name but nil-checks |
| `StarterPlayerScripts.RewardArrowClient` (disabled) + `StarterGui.RewardArrow` | superseded by PlaytimeReadyClient's HUD READY wobble | comments only |
| `StarterPlayerScripts.ShardArrowClient` (disabled) + `StarterGui.ShardArrow` | pointed at a removed left-rail button | comments only |
| `StarterGui.RebirthArrow` | orphan; the live arrow is `HUD.LeftRail["Group 300"].Rebirth.Arrow` | no `WaitForChild("RebirthArrow")` anywhere |
| `StarterPlayerScripts.ObjectTween` (disabled) | looped over a non-existent `workspace.PetsTween` | 0 references |
| `StarterGui.PostTutorialQuests` | checklist removed 2026-08-25; TutorialClient only destroyed it | nil-safe FindFirstChild + Destroy |
| `StarterGui.Parts` | empty folder | 0 references |
| `StarterGui.UITemplates.ThiefTag`, `.VaultTag` | never cloned; VaultService builds its own labels | 0 references |
| `ReplicatedStorage.Assets.Animations.Pets.WalkFront` | pet Movement only loads WalkSide/WalkIdle (asset was permission-blocked anyway) | one comment reference |

## 4. Code edits (surgical)

| Edit | Script | Change |
|---|---|---|
| E1 | `ServerController.ServerNetwork` | removed `local CollectionService = ServerController.GetModule("CollectionService")` (unused variable; module deleted) |
| E2 | `ServerController.ServerNetwork` | removed the `Collect` / `ChangedZones` no-op event bindings (their only firer, CollectionClient, is deleted) |
| E3 | `ServerScriptService.Server` | removed `"CollectionService"` from the Initialize blacklist |
| E6 | `ServerScriptService.Server` | removed `"VaultService"` from the PlayerJoined whitelist: VaultService defines no `PlayerJoined`, so the loader called nil and silently aborted the join loop for any module after it (latent bug; VaultService assigns stalls from its own Initialize) |
| E4 | `ReplicatedStorage.Modules.UserInterfaceLoader` | removed the `Teleport = UserInterfaceLoader.new(...)` panel entry (required: the loader has no pcall, a missing module or frame would abort every later panel's OnStart) |
| E5 | `StarterPlayerScripts.UIPreloaderClient` | removed `"Teleport"` from `FRAME_PRIORITY` |
| E7 | `StarterPlayerScripts.Client` | removed the orb-era block that waited up to 600 s for a `Circle` under every other player's root part |

## 5. Deliberately NOT deleted (judgement calls, see audit notes)

- Loose `workspace.Part` at (203.85, 8.43, 7.55): hand-placed bank boundary wall kept at workspace root so bank rebuilds do not destroy it.
- The two `workspace.BankSign` models: different plaza positions, both real signage.
- `HD Admin`, `TutorialTestOverride`, `ForceTutorialOnJoin`, `PanelMetricsTest` + `PanelMetricsWatchdog`: dev tooling that still runs.
- Stale comments pointing at deleted backups (VaultService header, BankBuilder, BossBarClient, TopStatusLayout, CarryService, BreakablesService line ~1723): cosmetic, left alone to avoid touching live modules.
