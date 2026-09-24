# RAS - Dev (place 128775411268189) — resort props, ball flight, smashing

Source mirrors of the scripts changed on 2026-09-16 live in `src/`. The Studio copies are
the live ones; `install.lua` pushes `src/` into Studio (compile-checked) while
`pets-remake/serve.ps1 -Port 8771 -Root <repo>/ras-dev/src` is running.

## What is where

| File | Studio path | Role |
| --- | --- | --- |
| `MountainConfig.lua` | ReplicatedStorage.Assets.Modules.Shared.MountainConfig | All knobs: `PROPS` (scatter densities, ski-lift spacing, fade), `FLIGHT` (lift, tricks, momentum keeper), `SMASH`, `SOUNDS`, `LAUNCH.Elasticity` |
| `PlaceMountainProps.lua` | ServerStorage.Modules.PlaceMountainProps | Procedural resort: edge tree lines, cabin hamlets with satellites, ski-lift lines (towers + resized cables + chairs), distance/slope/welcome signs, warning poles at ramp/cliff lips, ponds in valleys, smashable lane clutter, finish arch + lodge. Honours designer sockets (`Destructible_N`, `LandmarkPoint`, `PropModel` attribute). Output: `workspace.MountainDecor/<PieceName>/<Prop>` (Atomic models, tag `MountainProp`, streamable). |
| `CLIENT_SnowballFX.lua` | ReplicatedStorage...ClientFunctions.Modules.CLIENT_SnowballFX | Owner client: lift while falling, one air trick per flight, clean pre-touchdown spin, momentum keeper on kink impacts, smash detection (swept box query) → local fade + `SmashProp` to the server, finish-floor auto-stop. Every client: spray/trail/wind/landing/crash particles, sounds, prop fade on `Smashed`. |
| `CLIENT_Snowball.lua` | ...Modules.CLIENT_Snowball | Ride camera; now calls `StartAirPhysics`/`StopAirPhysics` and applies `GetCameraKick`. |
| `SERV_Snowball.lua` | ServerStorage.Modules.ServerFunctions.Modules.SERV_Snowball | `SmashProp` validation (distance-gated) → `Smashed` attribute, `SmashCount` on the ball, destroy after the fade; softer ball elasticity. |
| `SERV_MountainGeneration.lua` | ...SERV_MountainGeneration | Spawn on the launch pad (the LaunchPoint socket sits just outside the pad's front wall, so Launch never showed). |
| `ClientMain.lua` | StarterPlayer.StarterPlayerScripts.ClientMain | Calls `StartSnowballFX` once. |

Edit-mode place changes made by `install.lua`: `workspace.FallenPartsDestroyHeight = -10000`
(the run drops ~2,600 studs; the default -500 deleted the ball at 14 s) and the three lobby
BillboardGuis on `StartPlatform.Circles` sized `14 x 3.5` studs with `TextScaled` (world-scaled
instead of fixed pixels).

## Later the same day: combo, wander, gap guard

- **Combo** (`SMASH.Combo*`): every smash stacks while hits arrive within `ComboWindow`
  (2.5 s). Each hit pops "xN COMBO!" ("SMASH!" for the first) big at 40 % of the screen and
  Back-eases up to a small orange label at 7.5 %; it fades after the window. Stacks also
  scale the camera kick, debris and crash pitch. Server mirrors it as `Combo` / `BestCombo`
  attributes on the ball (client: `ClientCombo` / `ClientBestCombo`).
- **Wander** (`FLIGHT.Wander`): noise-driven target across the track, pulled toward the
  nearest structure ahead (`Seek`), sideways speed capped to `MaxHeading` of the forward
  speed, hard edge safety at `EdgeLimit` (40). Measured: x from -37 to +37, never off-track.
- **Gap guard** (`FLIGHT.GapGuard`): JumpRamp pieces have a hole between kicker and
  landing; a ball already airborne from the previous piece could drop into it. While
  airborne, if no track lies under the ball's near-future position but track exists further
  ahead, gravity is cancelled and sink damped (gentle climb if the landing is higher).

## Hold-to-launch + smaller ball

- `LAUNCH.BallScale = 1/1.5`: the launched model is scaled down server-side before the radius
  and BaseScale attributes are read, so growth (max scale 8) is also 1.5x smaller.
- `LAUNCH.Charge`: standing on the pad, hold click/touch (anything not eaten by a GUI): the bar
  fills over `Time` (1.5 s) to 100 %, release fires `Launch` with the charge fraction; the
  server maps it to `MinSpeed..MaxSpeed` (30..150) and stamps `LaunchCharge` / `LaunchSpeed`
  on the ball. Taps under `MinCharge` do nothing; stepping off the pad cancels.
- The bar is RAS - Maps' `StarterGui.LoadingProgressGui` (export in `assets/`), stored as
  `ReplicatedStorage.Assets.UserInterfaces.ChargeBar`; the client clones it, strips its
  ProgressController script and drives `ProgressBar.Track.Fill` + `Percent` directly.
  A "HOLD TO LAUNCH" prompt (`ChargeHint` gui) shows while on the pad. The old Launch button and
  speed box are gone; Stop remains. Dev hook: `PlayerGui:SetAttribute("DevChargeHold", bool)`.

## 2026-09-17: instant vanish + white burst, race progress bar

- Smashed structures no longer fade: every part goes invisible at once (server removes the
  model 0.5 s later) and a silent white burst plays at the structure's bounding-box centre
  (`SMASH.Explosion`: glowing puffs, one flash, an expanding Neon sphere; scaled by prop
  radius). Crash sounds are off (`SMASH.SmashSound = false`); landing thuds/whoosh remain.
- `StarterGui.RaceProgressGui` (from RAS - Maps, export in `assets/`): its own
  RaceProgressController draws one headshot marker per player from the replicated player
  attribute `Distance` (also hides the Roblox topbar via SetCore, as authored). The server
  writes `Distance` every 0.15 s while a ball rides (`SERV_Snowball:GetRun` = start root
  origin/axis, total = furthest Exit; stamped as `RunLength` on the mountain), resets it to 0
  on launch and leaves the final value after the ride. The client sets the gui's `MaxDistance`
  and finish label from `RunLength` (`CLIENT_SnowballFX.SetupRaceProgress`). The combo label
  now settles at 172 px so it sits under the 132 px bar.

### Compact race bar (2026-09-17, second pass)

Per the user's markup the bar is now half the screen wide at the very top: `Root.Track`
anchored (0.5, 0) at y 14, size (0.5, 0, 0, 34), pill corners, 3 px outline; `TrackShadow` and
`Markers` share that box; `StartLabel` / `FinishLabel` sit just below the bar ends (y 51, 18 px). The
controller (`src/RaceProgressController.lua`, installed over the original) draws a 44 px
headshot ring that rides on the bar (marker anchor 0.5/0.5, target `UDim2.new(f, 0, 0.5, 0)`)
instead of the 82 px portrait-plus-pointer that hung above it. Combo label at 108 px.
`race-bar-layout.lua` re-applies this layout to a freshly imported `assets/RaceProgressGui.rbxm`
(the export still has the original tall layout); then set the controller Source from `src/`.

## 2026-09-18 audit after the user's revert

Studio sources = `src/` mirrors = GitHub `kinqxz/RAS` Rojo tree (all 7 identical by checksum,
`ChargeBar.rbxm` identical), RaceProgressController identical to `src/`, compact bar layout with
labels below, `FallenPartsDestroyHeight` -10000, 3 lobby billboards 14x3.5 studs, 8 prop themes
(Frostpeak 33), 12 pieces, 30 balls + BallColision. Test ride: 150 studs/s launch, radius 0.67,
8 smashes / x9 combo in 8 s, race marker live. Nothing missing.

## 2026-09-18: HUD in game (src/HUD.lua -> ServerStorage.Modules.UserInterfaces.HUD)

The frames the user authored in `ServerStorage.Assets.UserInterfaces.HUD` (MainUI with
Rebirth / Shop / Mountains / Invite / DistanceBoost / Auto buttons, Level bar, friend boost;
Shop and Mountains panels; the empty Interface) are moved under the HUD module by
`SERV_General.SetupInterfaces`; GUIFramework spawns `Interface` into `PlayerGui.HUD.Base` as
"HUD". The module clones `MainUI` into it and wires the buttons: Shop / Mountains / Rebirth
open the frame of the same name IF it exists (spawned panel -> module template -> anything in
ReplicatedStorage.Assets.UserInterfaces -> anything already in PlayerGui). Panels are cloned
into `PlayerGui.Menu.Basis.Window` (Menu DisplayOrder raised to 5), one open at a time, the
panel's `X` closes it, the button toggles it. `PlayerGui` attribute `PanelOpen` = the open
panel; hold-to-launch ignores presses while it is set. Rebirth only warns until a frame named
"Rebirth" is added anywhere above. Dev hook: `PlayerGui:SetAttribute("DevPanel", name)`.
The "HOLD TO LAUNCH" hint and the Stop button moved to y 0.86 (above the level bar).

## Numbers from the 2026-09-16 test rides

- Generation: 550-1,400 props (7-13k parts) in ~0.1-0.2 s depending on the seed; 3 ski-lift
  lines of 2-3 pieces, 8 distance signs per 9,000 studs.
- Ride: 40-73 confirmed smashes per run, speeds 150-370 studs/s, auto-stop ~1 s after the ball
  leaves the finish platform.
- Sounds are Pro Sound Effects clips (ids in `SOUNDS`); volumes are guesses, tune in Studio.

## Known limits

- Everything is destructible, including the finish lodge and arch.
- Valley bowls can still trap a slow ball (terrain grammar); the momentum keeper only fires on
  impacts (speed collapse >30% within a fraction of a second).
- Other themes (Christmas, Candy, ...) generate from `PropInfo.Category`; only Frostpeak was
  tested.

## 2026-09-17: overwritten by a Rojo sync, restored, now in the GitHub repo

The place was synced from the Rojo project at https://github.com/kinqxz/RAS (Eric's repo,
we have write access) at its 2026-09-10 state, which put the old scripts back, deleted
`CLIENT_SnowballFX` and the `ChargeBar` template, and left everything Rojo does not map
(RaceProgressGui, place properties, the prop library, billboards). The mirrors in `src/`
were the only surviving copy.

Restored the same day and committed to that repo as `daf124d` (all seven sources in the
Rojo tree + `src/ReplicatedStorage/Assets/UserInterfaces/ChargeBar.rbxm`), so a sync now
carries the work instead of wiping it. **Keep the repo and `src/` in step: after editing in
Studio, copy the source into both.**

Transfer recipe that works through the official Roblox Studio MCP (Edit mode, no HTTP):
wrap each source in an `.rbxmx` (`ProtectedString` Source in CDATA), copy the files into
`%LOCALAPPDATA%\Roblox\Versions\<running version>\content\`, then `game:GetObjects("rbxasset://name.rbxmx")`
and copy `.Source` across (38 KB in one call, `loadstring` compile check available).
Gotchas: the eval thread cannot reparent a script into the sandboxed folders (Modules,
UserInterfaces: "additional values for the Capabilities property") - create new scripts with
the MCP `multi_edit` tool and strip LuaSourceContainers out of GUIs before parenting them;
it also cannot `require` the game modules or `FireServer`, so drive a ride with the
`DevChargeHold` PlayerGui attribute (true, wait 1.7 s, false).

## 2026-09-22: pulled Eric's and Ali's work, Studio synced to GitHub

GitHub main moved from `c97ec0b` to `2e1cb4c` (Ali's UI polish merged, "System changes",
"Major changes", "added a bunch of stuff", "rebirth"): player data store, XP / coins /
levels, snowball + launcher catalogs with a gear multiplier, mountain places and travel,
rebirths, mountain borders (`BuildMountainBorders` + `Storage.BorderClusters`), a snow field,
panel UI modules and a much larger HUD. Our physics, smash, combo and hold-to-launch code is
still in it. The launch is now `charge -> MinSpeed..MaxSpeed (22..78) x gear x rebirth boost`,
so starter gear rolls a few hundred metres.

Studio was behind: five scripts were an older draft of the lifetime-totals work and HUD was one
commit behind. Nothing in Studio was missing from GitHub. The six scripts were set to `2e1cb4c`
and checksum-verified; every script in the place now equals the repo. The files in `src/`
were refreshed from `2e1cb4c` too (the ones we mirror; the repo is the full source).

## 2026-09-22: six fixes (HUD overlap, shop, purchase FX, first-join spawn, side stance, gear audit)

All in GitHub kinqxz/RAS main `e26b1e8` (branches fix/race, fix/shop, fix/spawn, fix/facing, fix/gear
merged, plus two follow-up commits); every script in RAS - Dev equals that commit. The files in
`src/` were refreshed from it.

- **Race bar vs HUD** (`src/RaceProgressController.lua`, also in the repo as
  `extras/RaceProgressGui/RaceProgressController.lua` because StarterGui.RaceProgressGui is not in
  the Rojo tree): the gui draws at DisplayOrder -1 (under HUD 0 / Menu 5), slides out while the
  PlayerGui attribute `PanelOpen` is set, and a runtime UIScale `Root.LayoutScale` shrinks the
  team's 58 px bar just enough to end above MainUI.DistanceRolled / CoinsMade (result in the gui
  attributes LayoutScale / LayoutClearTop / LayoutBottom). To make it bigger, move those HUD labels
  down. Do NOT re-run `race-bar-layout.lua` on the current gui (it resets the 58 px Track to 34);
  the live gui is exported as `assets/RaceProgressGui_2026-09-22.rbxm`.
- **Combo counter** (CLIENT_SnowballFX `comboSettlePosition`, SMASH.ComboAvoid / ComboClearGap /
  ComboAvoidPop): settles under DistanceRolled / CoinsMade (measured at rest plus the biggest
  EarnPop) instead of the fixed 108 px that covered CoinsMade.
- **Shop**: the purchase gate and the UI read the same unlocks (`PlayerProgress.EffectiveUnlocks`:
  saved unlocks + Studio `StudioSettings.UnlockAll`, never saved). Gear stays gated by mountain on
  live servers (`GEAR_REQUIRES_MOUNTAIN = true`, switchable); locked cards read "BEAT <mountain>",
  out-of-order presses say "Buy <next> first". BuySnowball / BuyLauncher go through ReFunction and
  return true or false + reason. `EQUIP_ON_BUY = false` keeps buy-then-EQUIP. The ride coins
  readout counts only gains, so a mid-ride buy no longer zeroes it.
- **Purchase effects**: `Client/UI/PurchaseFX` + `Client/UI/Notify` = port of the New Map Cucumber
  Game ButtonFX / Notify (press pop, flash, big pop, "UNLOCKED!" float, sparkles seen by others,
  Cash Register 120891770644830 + Magic Shimmer 3199238931, Button Pop 9113263444, Error 550209561).
  Plays on snowball, blaster and rebirth purchases. Robux products do not exist yet; when added,
  fire the client mode `PurchaseConfirmed` after ProcessReceipt grants.
- **First-join spawn**: ServerMain connects player handlers before generating; SERV_PlayerEvents
  holds (anchors) each new character until the mountain is ready and the client reports the pad
  floor (`SpawnReady`, CLIENT_SpawnGuard), then places / releases it; `workspace.MountainSpawn`
  SpawnLocation on the pad; a 0.5 s failsafe returns fallen non-riding characters to the pad.
  Studio test knobs: StudioSettings attributes `GenerationDelay` / `SpawnFloorDelay` (inert live).
- **Side stance**: `MountainConfig.LAUNCHER.PadStance` (Yaw -90 = right side to the camera, eased,
  AutoRotate while walking). Use -60 / -45 if the launcher should point more down the track.
- **Gear audit**: all 30 launchers + 30 snowballs from RAS - Assets were already in Dev, in the shop
  and animated (30 procedural charge/fire profiles). Fixed: catalog `Asset` names (Revolver,
  Dragoon Launcher, Candy Cane, Black Hole showed the wrong model), Snowball Flipper icon id,
  shop multiplier = Order (x1..x30, what the game uses), and `CLIENT_LauncherObservers` so other
  players see the launcher pose. No Blender work was needed; Blender would only add moving parts to
  the rigid launcher meshes.

Tested live (solo + 2-player): mid-generation join held then placed, 15 s GenerationDelay held 18 s
with no fall, -200 stud drop back on the pad in 0.4 s, stance right.back = 1.000 idle and charging,
ball launches down the track, bar hides on panel open, real clicks buy / refuse with toasts, the
four fixed items load their own meshes, observers see ready pose + wind-up/fire, no script errors.
Note: the charge bar ping-pongs (FillTime 0.42 s, Time 1.2 s); releasing at the bottom of the swing
(< MinCharge 0.03) launches nothing, by design. Test holds of ~1.6 s land there.

## 2026-09-22: player-save fixes (SERV_PlayerData + SERV_PlayerEvents)

kinqxz/RAS commit `6321c61` (on top of `e26b1e8`); both scripts in RAS - Dev equal it byte for byte.
Not mirrored in `src/` (the repo is the source).

- **Blank profile over a real save**: the join placeholder is `Loaded = false` and `SavePlayerData`
  skips anything not Loaded or `LoadFailed`. A read that fails all 5 tries kicks the player ("Couldn't
  load your data, please rejoin."); in Studio they play on defaults with saving off. A load that ends
  after the player left returns nil and PlayerAdded skips setup. `EnforceMountainAccess` ignores an
  unloaded profile. Extra guard: the UpdateAsync transform refuses a payload whose lifetime totals
  are behind the stored ones (they only grow; rebirth keeps them), so a stale session cannot roll a
  save back. Admin rollbacks therefore have to go through `SetAsync`, not SavePlayerData.
- **Forced save during an autosave**: a leave / shutdown / travel / unlock / rebirth save now waits
  for that player's in-flight autosave and writes a fresh snapshot. Dirty is cleared before the
  snapshot and restored on failure.
- PlayerRemoving keeps the profile when the same user already rejoined this server mid-save.

Tests: `tests/playerdata-harness.lua` runs any two versions of the scripts with fake
DataStore / Players / RunService / TeleportService / MountainPlaces in the Studio edit peer (serve the
folder holding the sources + harness on 127.0.0.1:18794, then
`loadstring(HttpService:GetAsync(".../harness.lua"))()("SERV_PlayerData.luau", "SERV_PlayerEvents.luau", "T1 T5")`).
New code passes all 9 cases (T1 read fails live: kick, 0 writes; T2 Studio: no kick, 0 writes; T3
transient failure recovers; T4 leave mid-load: 0 writes; T5 leave mid-autosave: writes 5010 then 5110;
T6 stale totals refused; T7 new player saves; T8 locked mountain still redirects; T9 rejoin keeps
the profile). The old code wiped the save to 0/0 in T1 and T4, lost the +100 in T5 and regressed
totals in T6. A real playtest with the real DataStore confirmed normal load, a forced save that waited out an
in-flight autosave (stored 15314 = latest), and a real leave-mid-load on a throwaway key (nothing
written). The test account was restored to its baseline afterwards and verified after the stop.

## 2026-09-23: launcher visible on the pad + a readable throw

Branch `fix/launcher-visibility` in kinqxz/RAS (on `e26b1e8`); the five scripts in RAS - Dev equal it.
Mirrors: `src/MountainConfig.lua`, `src/CLIENT_Snowball.lua`, `src/SERV_Launcher.lua`,
`src/AnimationMath.lua`, `src/Profiles.lua`. Pre-change export:
`backups/RASDev_launcher-visibility_before_2026-09-22.rbxm`.

Complaint: "can't see the snowball launcher, it's like hidden; can't see the animation or it's too
fast." Measured before: pad camera 24 studs back (LAUNCH.PadCameraDistance 24 / Height 8 /
LookAhead 10) put the character at 127 px and the launcher at 48x38 px of a 1301x611 viewport; a
full charge moved the shoulder 8 degrees; the release flick peaked 0.12 s after release and lasted
0.48 s; SERV_Snowball.Launch fired BindSnowballCamera in the frame it spawned the ball and the client
snapped to the chase on frame 1, so the flick played with the camera already gone.

- **Launcher scale** `LAUNCHER.Scale = 1.5` (MountainConfig), applied in SERV_Launcher.GiveLauncher with
  `Model:ScaleTo` about the grip pivot (every template in Storage/SnowballLaunchers is one MeshPart with
  its PivotOffset at the grip and no Grip attachment, so the generic hand offset in alignToHand is what
  everyone gets). Flipper 0.69x1.72x2.93 -> 1.04x2.58x4.40, grip still 0.4 studs from the hand.
- **Pad camera** 13 / 3 / 3: character 264x301 px, launcher 177x117 px.
- **Wind-up** (AnimationMath.TUNING): scoop/flipper/catapult/sling pull the launcher arm 32 degrees low and
  back at full charge, the others raise it 26 degrees to the aim line; elbow +22, torso -8, sway 1.0x at 0%
  to 2.4x at 100% of the profile's sway. Release kick x2.6 (toss) / x1.8 (others). Measured flipper throw:
  shoulder 37 -> 25 dip -> 90 peak at 0.32 s -> 22 overshoot at 0.52 s -> settled by 0.65 s, launcher travel
  2.6 studs.
- **Release timing** Profiles: `RELEASE_TIME_SCALE = 2.0` on every duration/fireAt (flipper 0.48 -> 0.96 s,
  fireAt 0.09 -> 0.18 s).
- **Ball leaves at the fire moment**: CLIENT_Snowball parks the charge in `vars.PendingLaunch`; the
  ChargeController's OnFire sends `Launch` (measured 0.184 s after release); a `fireAt + 0.25 s` timer is
  the fallback, and with no controller it launches at once as before.
- **Camera hold + blend** `LAUNCH.ReleaseCamera = { Hold = 0.45, Blend = 0.6, BlendMaxDistance = 150 }`:
  BindSnowballCamera keeps the pad frame for Hold seconds after the ball arrives, then smoothsteps into the
  chase; if the ball is already further than BlendMaxDistance when the blend would start (gear 6 = 430
  studs/s here) it cuts instead (a 0.6 s dolly over 300 studs read as a glitch in the first test).
  Measured: camera static until 0.72 s after release, then the cut.

Test recipe: `eval_client_runtime` sampler on RenderStepped keyed on `vars.Charging` true->false, then
`PlayerGui:SetAttribute("DevChargeHold", true)`, 0.6 s, false; `vars.Functions:StopRide()` 2 s later. Two
short rides (~800 and ~600 studs) went onto the test account's real profile.

### Follow-up: launcher gone after leaving the pad and coming back (same branch)

Server log of a walk off and back: `UnequipLauncher` arrived while the server still saw the player on
the pad, and `EquipLauncher` arrived while it saw them 4 studs OUTSIDE it (the client's own pad check
runs a few replication ticks ahead of the position the server has), so `EquipLauncher` skipped the
hand-out and nothing asked again. Fix: SERV_Launcher.EquipLauncher polls `IsPlayerOnLaunchPad` for up
to 1 s (EQUIP_GRACE / EQUIP_POLL) before giving up, with a per-player request counter
(`sself.LAUNCHER_REQUEST`, weak keys) that an Unequip or a later Equip bumps to cancel a waiting one;
CLIENT_Snowball.WatchLaunchPad re-sends `EquipLauncher` at most every 2 s while standing alive on the
pad with no launcher in the character (`vars.LauncherRequestAt`). Measured: launcher back 0.27 / 0.35 s
after stepping on in two consecutive rounds.


## 2026-09-23: new launcher animations for all 30 launchers (Blender), the ball comes out of the launcher

Branch `feat/launcher-clips` in kinqxz/RAS (on `fix/launcher-visibility`). Blender work in
`launcher-anims/` (see its `BRIEF.md`), mirrors of the changed scripts in `src/`.

**What the player sees.** Every launcher has its own animation set, authored in Blender: `Ready`
(carried on the pad), `ChargeLo` / `ChargeHi` (the charging action while the mouse is held, blended
by the live charge), `Fire` (release, the shot, follow-through). The snowball is visible where it
belongs: on the shovel blade / in the scoop, flipper cup, sling pouch, catapult cup, on the crossbow
rails, in the slingshot pouch-hand with elastic bands drawn from the fork tips; barrel launchers
fire it out of the muzzle with a burst (snow / smoke / sparks / fire / steam / toxic, per launcher)
and some have a charge effect at the muzzle. At the clip's fire moment the ball leaves the launcher
and **the server spawns the ride ball at that exact point** (Launch gets the origin; validated: within
`LAUNCH.MuzzleSpawn.MaxDistance` 14 studs of the root, nothing solid in between, above the floor;
anything else keeps the old ground spawn). The shovel scrapes the floor while charging, digs,
scoops and heaves; the ball flies off the blade.

**How it works (no Animation assets, so it plays in any game whoever owns it).**
- `launcher-anims/launcherlib.py`: R15 rig + all 30 launcher meshes/textures (pulled from the place
  with EditableMesh / EditableImage), IK (`hold`, `left_hand_to`, `stance`), an elbow guard, keying,
  export, checks (fire direction, ball clearance, loops, floor) and a frame-by-frame motion audit
  (elbow flips, one-frame snaps, arm / launcher inside the body on realistic avatar sizes), preview
  sheets from the real pad camera / front / down the track. `meta/NN.json` = each launcher's Muzzle,
  Seat, Grip2 (left hand), Tip, Bands, Back points in its grip-pivot frame.
- `launchers/NN/build.py` = one script per launcher (headless: `blender -b LauncherAnims.blend
  --python launchers/NN/build.py`), 30 authored by parallel agents from per-launcher concepts,
  reviewed from the preview sheets (all 30 passed, 7-8/10), audited clean (0 problems, 0 flips / snaps,
  arm <= 0.17, launcher <= 0.14 studs into the body, shot within 12 deg of the track).
  `tools/rebuild_all.py` re-runs all of them; `tools/to_luau.py out luau` writes the modules.
- Game side: `SnowballAnimations/LauncherClips/L01..L30` (generated data, ~44 KB each, required
  lazily), `ClipPlayer` (Catmull-Rom sampling of 15 fps loops / 30 fps Fire), `ChargeController`
  (writes the joint Transforms incl. the legs and the `LauncherGrip` grip, legs handed back to the
  Animator while walking / airborne, root height scaled by the avatar's HipHeight, falls back to the
  old procedural profiles for a launcher without clips), `LauncherBall` (the visible ball in the
  seat, the flying copy that eases onto the real ride ball when it arrives: covers network delay,
  never snaps back; bands; bursts; charge effects; snowball looks from
  `ReplicatedStorage.Assets.SnowballVisuals`, published by SERV_Launcher at boot).
- Floor contact: the shovel and the scoop carry a per-frame `Tip` height track; the controller tilts
  the launcher in the hand so the tip keeps that height above the floor on any avatar (measured on
  the tall test avatar: 8-9 deg of tilt, blade 0.1-0.2 studs above the snow while scraping).
- Other players: the owner sends `LauncherPose` hold / release / idle; SERV_Launcher relays it as the
  player attribute `LauncherPose = "<state>:<n>"` (coalesced, a quick tap's release is never dropped);
  CLIENT_LauncherObservers plays the same clips from it (falls back to the ball appearing).
- Code review (3 lenses + adversarial verify) found 9 real issues, all fixed before install: observer
  handoff to a ball that arrives before their fire frame, pose-relay drops, a second click during the
  throw, the snap-back of the copy on a slow connection.

## 2026-09-23 (late): chase camera from the moment the ball leaves + the standing-shake diagnosis

- **Camera follows the ball from the frame it spawns** (user ask: "follow the ball from the second it's
  launched instead of delaying"). `LAUNCH.ReleaseCamera` (Hold 0.45 s + 0.6 s blend, added the same
  morning) is gone. `BindSnowballCamera` now looks at the ball on its very first frame; when the launch
  came from the pad the camera *position* starts where the pad camera was (`LAUNCH.ChaseFromPadCamera =
  true`, new) and the existing 10/s follow lerp carries it up behind the ball in ~0.3 s, so there is no
  hold and no cut (set it false for a straight cut to the chase framing). The ball still spawns at the
  clip's fire moment (`fireAt`, ~0.2 s after release), so the throw plays on the pad camera until the
  ball exists and the chase takes over the same frame. Files: CLIENT_Snowball (BindSnowballCamera),
  MountainConfig (LAUNCH), Profiles (comment only). Studio == repo == mirrors, checksummed.
- **Avatar "shaking" while just standing with the launcher = a blend ping-pong in ChargeController, NOT
  the clips, physics or the pad stance** (diagnosed first, then fixed on the user's go-ahead, see below). Measured in a
  playtest (Hand Catapult, 60 Hz PreSimulation sampler wrapped around `Controller._step`): root part,
  angular velocity, camera, FloorMaterial (always Plastic), MoveDirection (0) and Humanoid state are all
  perfectly still, and the authored Ready pose moves the hips only ~0.1 deg/frame; yet the written joint
  Transforms jump 2-4.6 deg *every other frame* (LeftHip max 4.6, RightHip 3.2, RightKnee 3.1, Root/
  LowerTorso 2.7). Cause: the leg blend
  `self.LegWeight = math.clamp(self.LegWeight + (if legTarget > self.LegWeight then rate else -rate), 0, 1)`
  never rests at its target. With legTarget = 1 and LegWeight = 1 the test `1 > 1` is false, so it steps
  DOWN by dt/0.15 (to 0.889, or 0.861 on a 1/48 s frame), next frame it is below the target so it steps
  back UP to 1, and so on: 114 dips in 242 frames. Every dip blends the whole lower body (LowerTorso,
  hips, knees, feet) 11-14 % toward the Animator's idle pose for one frame and back = a 30 Hz vibration
  of the body above the hips. The bottom end is stable only because the clamp at 0 absorbs the extra
  `-rate`. `HoldBlend` (ready <-> charge loops, HOLD_BLEND 0.2) has the same shape, so while HOLDING the
  charge the whole pose (arms included) flickers 8 % between the ready and charge poses each frame too;
  `CLIENT_LauncherObservers` runs the same controller, so other players' characters do it as well.
  FIX (ChargeController, both blends): move toward the target by at most one step and rest AT it:
  `self.LegWeight = math.clamp(legTarget, self.LegWeight - rate, self.LegWeight + rate)` and
  `self.HoldBlend = math.clamp(target, self.HoldBlend - step, self.HoldBlend + step)`. Verified with the
  same 60 Hz probe: standing, holding (SetHolding(true) on the live controller, no launch) and back to
  ready, see the numbers in the summary of that session.
- **Chase camera trailing far behind at launch** (user: "at launch camera goes too far away from ball"): the
  chase eased `camPos` toward its spot with a fixed `1 - exp(-10 dt)`, i.e. a 0.1 s time constant, and an
  exponential follower trails a moving target by speed x time constant: at this account's gear 18 the ball
  leaves at ~1,300 studs/s, so the camera settled ~130 studs behind its framing (140 studs from the ball)
  within 0.3 s of the launch (measured `gap` 19 -> 124 studs). Fix: the follow rate is now
  `max(LAUNCH.CameraFollowRate 10, speed / LAUNCH.CameraMaxLag 6)`, so the trail is capped at 6 studs at any
  speed while the low-speed feel (rate 10) is unchanged. Files: CLIENT_Snowball (BindSnowballCamera),
  MountainConfig (LAUNCH.CameraFollowRate / CameraMaxLag).

## 2026-09-23 (night): chase camera stays behind the ball, no leap over it at launch

User: "camera is weird and just goes completely over the ball - fix it, keep it behind and normal from
launch." Measured with a Heartbeat sampler (ball vs camera per frame, this account launches at ~600
studs/s now): the chase framing was `CameraDistance 18 / CameraHeight 16` = a 38-42 degree look-down,
growing to 42 studs above the ball as it scaled up (the horizon sat at the top edge of the screen), and
the speed-tightened follow (`max(10, speed/6)` = 100/s at 600 studs/s) turned the intended 0.3 s ease
from the pad camera into a ONE-FRAME snap: pad view (3 up, pitch 11) -> 14 up, pitch 38 in 16 ms. That
snap plus the steep framing is the "leaps over the ball". Two more launch hops hid under it: the
ground-clearance ray (`liftAboveGround`) counted the launch pad's invisible, non-colliding 15-stud-tall
trigger volume `StartPlatform_N.LaunchPlatform.Collision` (CanCollide false, CanQuery true) as ground
and lifted the camera 8 studs on frame 2, and the player's own character was not excluded from it.

Fix (CLIENT_Snowball `BindSnowballCamera` + `liftAboveGround`, MountainConfig LAUNCH; Studio == repo
main == mirrors, checksummed):
- **Camera = anchor + offset.** The anchor still eases toward the ball with the lag-capped rate
  (`CameraFollowRate 10` / `CameraMaxLag 6`). The camera's OFFSET from the anchor now lives in ball space
  and eases separately at `LAUNCH.CameraOffsetRate 8` (1/s). From the pad the offset starts as the pad
  camera's offset from the ball, so the shot settles into the chase framing in the same ~0.4 s at every
  gear (a world-space lerp settles in speed x time-constant studs, i.e. instantly once the ball is fast).
- **Lower framing:** `CameraHeight 16 -> 8` over `CameraDistance 18` = a 24 degree look-down with the
  track ahead in view. Growth with the snowball scale is now `CameraGrowDistance 0.5` / `CameraGrowHeight
  0.5` per scale step (was hard-coded 0.5 / 0.4 of the 16), so a scale-8 ball is framed from 81 back /
  36 up instead of 81 / 61 (same angle as at scale 1).
- **Slope follow:** the behind offset tilts with the ball's travel pitch (`asin(v.y/|v|)`, eased at
  `CameraPitchRate 2.5`, clamped `CameraPitchMin -20 .. CameraPitchMax 8` degrees), so on a downhill the
  camera sits up the slope behind the ball instead of being pushed over it by the clearance ray, and a
  climbing ball is watched from nearly level. -20 (not -30) so dives do not swing the camera far above.
- **Clearance ray:** `RaycastParams.RespectCanCollide = true` (solid geometry only) + the local character
  in the ignore list; the lift itself is eased (`lift` rises at once, settles back at `CameraLiftSettle 4`
  1/s) so a rail or bump under the camera reads as a small lift rather than a pop.
- Verified (Heartbeat sampler, 60 Hz then a 15 fps throttled Studio window): launch pitch 10 -> 15 ->
  18 -> 20 -> 21 degrees over the first 0.4 s, camera 0.6 -> 7 studs above the ball, largest one-frame
  rise 0 (was 13 studs); rolling framing 18-24 back / 7-9 up at scale 1; the two screenshots (before:
  horizon at the top edge, after: horizon a third of the way down, ball centred on the track) are in the
  session summary. Test rides added ~7 km / ~60K coins to awesomeotheraccount's real profile.
- Gotcha: when the Studio window is not in front, Roblox renders at ~15 fps while Heartbeat stays at 60,
  so a Heartbeat sampler sees the camera update only every 4th sample (a 4-sample sawtooth in "behind").
  Read the first sample after each camera update, and add v x dt to it: the chase sets the camera from
  the ball's pre-physics position, so a Heartbeat sample sees the ball one step (10 studs at 600 studs/s)
  further on. `RunService.RenderStepped` count per second tells you the render rate.

## 2026-09-23 (night): Rojo workflow set up on this machine

- **Tooling:** `rokit` 1.2.0 (`C:\Users\shrey\.rokit\bin`, on the user PATH) installs the repo's pinned
  `rojo-rbx/rojo@7.7.0` from `aftman.toml` (`rokit install` inside the clone). The Rojo Studio plugin was
  installed with `rojo plugin install` -> `%LOCALAPPDATA%\Roblox\Plugins\RojoManagedPlugin.rbxm`
  (Studio loads it on its next start).
- **Persistent clone = the source of truth:** `C:\Users\shrey\RAS` (kinqxz/RAS main, `core.longpaths`
  on). The `ras-dev/src` mirrors here are now only a backup copy; edit the clone.
- **Serve:** `rojo serve C:\Users\shrey\RAS\default.project.json` (port 34872), then Plugins > Rojo >
  Connect in Studio. Rojo is one-way (files -> Studio). Before connecting the first time, the place was
  checked against the repo: all 74 scripts identical, nothing a sync would delete (the project's service
  nodes and `init.meta.json` files carry `ignoreUnknownInstances`, so the Studio-only backup folders
  under ServerStorage, `ServerStorage.Assets.*`, `SnowballAnimations.Clips`, StarterGui guis all survive).
  `$properties` on Lighting/SoundService/Workspace already match the place (Technology is unreadable
  from plugin code, so it is unverified).
- **Studio -> repo (what Rojo cannot do):** manifest check recipe = `scratchpad/manifest.py` builds a
  Luau table of every repo script (instance path, class, LF-normalised length + `(h*31+b) % 2147483647`
  checksum) and every path-backed directory with its expected children; an edit-peer `execute_luau`
  compares it with the DataModel and reports differing/missing scripts, children a sync would delete,
  and Studio scripts unknown to the repo. Line-level diff of one script: per-line checksums from Studio
  (`fx_linediff.py`), then `get_script_source` with a `line_range`. Found and pulled today:
  CLIENT_SnowballFX combo tweak (COMBO_CENTER_HOLD 1, pop x0.6 capped at 0.51 of the width) = repo
  948e18d.
- Gotcha: a shell heredoc containing one ~14 KB line fails to parse in this Bash tool ("unexpected EOF
  while looking for matching quote"); write the script with the Write tool instead.

## 2026-09-23 (night): the place brought back to the owner's architecture

Rule (from Eric via the user): one Script (ServerMain), one LocalScript (ClientMain), one RemoteEvent
(ReEvent; its ReFunction stays), everything else modules; every UI = frames in
`ServerStorage.Assets.UserInterfaces/<UI>` + `ServerStorage.Modules.UserInterfaces/<UI>.luau` + an entry in
the `Default` manifest; backups in one folder. Done (kinqxz/RAS main `a0d20a4`, verified in a playtest):

- StarterGui.RaceProgressGui (+ RaceProgressController LocalScript + SetDistance bindable), StarterGui.ChargeHint
  and ReplicatedStorage.Assets.UserInterfaces.ChargeBar (+ ProgressController + SetProgress) became UIs:
  `Interface` ScreenGui templates in the UI folder, modules RaceProgressGui / ChargeHint / ChargeBar, manifest
  entries with `Parent = {}` (GUIFramework spawns a whole ScreenGui straight into PlayerGui, keeping its
  DisplayOrder). CLIENT_Snowball / CLIENT_SnowballFX / ClientMain fetch them with `GUIFramework:GetUI`.
- StarterGui.HUD.Base.MainUI moved back next to the other HUD frames; HUD.luau clones the template.
- ServerStorage root = Assets, Modules, Backups. `Backups` holds the 16 former loose items, `Backups.Unused`
  the old SnowballAnimations.Clips KeyframeSequences, the empty leftover folders, StarterGui.Test and the two
  retired StarterGui guis. Pre-change export: `backups/RASDev_ui-before-architecture-cleanup_2026-09-23.rbxm`.
- Repo: `extras/ServerStorage_UserInterfaces.rbxm` refreshed, `extras/RaceProgressGui` + the StarterGui snapshot
  removed, README rules added. Mirrors here: RaceProgressGui.lua / ChargeHint.lua / ChargeBar.lua / UI_Default.lua
  added, RaceProgressController.lua removed.
- Test gotcha: `DevPanel` set to the same value twice does not close the panel (no changed signal) and an open
  panel blocks charging; close with `vars.Functions.GUIFramework:InvokeUI("HUD", "ClosePanels")`.
- Another session committed `99b3d07` ("chase camera stays behind the ball") into the same clone meanwhile;
  Rojo synced it, main carries both.

## 2026-09-24: sound design for every feature + snowball growth without a cap

- **Growth (user: "gets noticeably bigger but there seems to be a cap; remove it, grow fast first then
  really slow"):** the old model was Volume += 1.6 per snow unit, scale = cbrt(volume ratio) clamped to
  8. Measured on a Frostpeak ride the ball hit 8x after ~420 snow units (1.7 km) and stayed flat for the
  remaining 3 km. New model (SERV_Snowball `growthScale`, `LAUNCH.GrowStep` 0.15 / `GrowDecay` 1.9):
  `scale = 1 + Decay * ln(1 + snow * Step / Decay)` = the growth per snow unit decays e-fold for every
  Decay of scale gained; no cap. Measured: 40 snow (400 m) 3.7x, 430 (1 km) 7.8x, 1,000 9.3x, 1,600 ~10.2x,
  a full 10 km run ~12.5x. One snow unit = 16 studs^2 of snow (~0.8 per 3.5-stud tile);
  `state.Snow` accumulates it (SnowCollected stays the reward counter). Camera distance/height still
  grow linearly with scale (Eric's CameraGrow*), so a 12x ball sits ~120 studs back.
- **Audio module** `ReplicatedStorage.Assets.Modules.Client.Audio` (repo `Client/Audio.luau`, Eric's
  plain-module layout like LaunchPropAnimations): catalog `MountainConfig.SOUNDS.Library` (37 entries),
  `MUSIC` (Lobby "Leisure Simulation Game" 2:29 / Ride "Bouncy Way" 1:11, both APM Sylvain Michel Ott
  video-game loops, crossfade 1.2 s), `AUDIO.Groups` (Music 0.4 / SFX 1 / UI 0.9 / Ambience 0.7 as
  SoundGroups), a wind bed (`WindLobby`, Pro Sound Effects). `Play` (2D), `PlayAt` (3D on a part or a
  point), `Attach` (a loop you drive; attribute BaseVolume = catalog base), `Release`, `Loop`/`SetLoop`/
  `StopLoop`, `SetMusic`, `Duck`, `ThrowSoundFor(launcherId)`. Player attributes `SFXEnabled` /
  `MusicEnabled` = false mute a side. Sources: Roblox_UI_* set (creator Roblox), Pro Sound Effects
  (9xxxxxxxxx ids), APM Music (18xxxxxxxx), classic Roblox (12222103 slingshot, 3149249837 cannon); all
  53 candidates load in Studio (`IsLoaded`/`TimeLength` probe in the edit DM).
- **Hooks:** ChargeController = charge loop on the launcher (pitch 0.7 -> 1.4 with the charge, 3D) +
  the throw by launcher family (scoop/flipper/catapult/sling swish, bow rubber band, crossbow, blaster/
  pistol pneumatic, heavy cannon, mortar low cannon, energy laser cannon, rocket jet) - every observer's
  controller plays them so the whole server hears each throw; CLIENT_Snowball = music Ride/Lobby on
  bind/unbind, BallAway swish at the ball, RideEnd whoosh, Finish sting + kids' "Yeah" + music duck in
  HoldAtFinish; CLIENT_SnowballFX = RideRoll (crunchy rumble, volume with speed and size, pitch down as
  it grows) + RideWind loops on the FX rig (attached AFTER the rig is parented), SizeUp whump per whole
  scale step, ComboPop per smash stack (pitch up), smashes audible again (`SMASH.SmashSound = true`,
  Crash volumes 1.2 / 0.9), HelperGrant for the owner; LaunchPropAnimations = HelperLaunch / Bounce /
  Dash by catalog kind (replaces the Whoosh/Thud hardcode); HUD = UIClick on the main buttons, UIOpen /
  UIClose on panels, UITab, LevelUp (+ UISuccess), Rebirth shimmer, Teleport on travel, CoinPop on the
  run readout (rate-limited 0.35 s); Notify = UIError / UISuccess / UIInfo per toast kind; PurchaseFX
  sounds routed into the SFX group.
- **Eric bug fixed on the way:** CLIENT_SnowballFX called `powerMultiplier` inside `checkSmash` before
  its `local function` line (his 4c40820 fast-smash change) -> "attempt to call a nil value" on every
  smash, aborting that frame's stepBall. Hoisted above checkSmash.
- **Test recipe:** client eval counts Sound instances by name (`Audio_*`, `Music_*`) via
  SoundService/workspace DescendantAdded while DevChargeHold launches a ride; server eval samples
  `sapi.SNOWBALLS[player].Snow/TargetScale` every 2 s. Gotcha found: a loop attached with `Volume = 0`
  must keep the catalog base in BaseVolume (first version stored the zero and stayed silent).

## 2026-09-24: level bar, level-gated rebirth, free-look camera

User: "make level bar work (XP as the ball rolls, very easy to level up), make the rebirth system
(reach certain levels, each rebirth more power / whatever the UI says, easy), let the camera be
moveable/draggable. Push everything." kinqxz/RAS main, Studio == repo == mirrors.

- **Why the bar looked dead:** the XP system was complete (snow 1 XP/unit, smashes, run multiplier,
  ApplyXp, HUD SetProgress) but the test account sat at the old `MAX_LEVEL` 100 with an empty
  "0/4060" bar and every award discarded. Measured on a ride at 5x gear: level 1 -> 17 in 22 s over
  2.7 km (~0.5 XP per stud at 1x). Fix: `MAX_LEVEL` 1000, a full "Level N: MAX" bar at the cap,
  plus distance XP (`PlayerProgress.DISTANCE_XP` 0.25 per stud x the run multiplier, fraction carried
  in `SERV_Snowball.updateDistance`, awarded through AwardProgress with 0 coins). Starter gear after a
  rebirth (2x gear x 1.5 boost): level 6 after a 430 m ride, level 10 in about one full ride.
- **Rebirth by level:** `RebirthLevel(rebirths)` = `REBIRTH_LEVEL_BASE` 10 + `REBIRTH_LEVEL_STEP` 5
  per rebirth done (capped at MAX_LEVEL); `CanRebirth` / `ApplyRebirth` gate on it; the coin cost and
  `RebirthCost` are gone. A rebirth still resets level, coins (`REBIRTH_KEEPS_COINS = false`),
  mountains and gear, keeps the lifetime totals, and adds `REBIRTH_EARNINGS_PER` 0.5x coins + XP (the
  boost the panel shows) and `REBIRTH_LAUNCH_PER` 0.15x launch. Server (`SERV_PlayerData.Rebirth`)
  answers "Reach level N first"; `RebirthLevel` is a replicated player attribute. HUD now drives the
  Studio frame `HUD/Rebirth` the way it was designed: CurrentBoost / UpcomingBoost = "X1" -> "X1.5",
  Background.Level bar = "level/needed" with the BackFrame filled (pinFillLeft + tweenFill, same as
  the main bar, `api:SetRebirthLevelBar`), Buy = "REBIRTH!" grayed below the level (was showing
  "$25K"). Verified: press at level 100 -> level 1, rebirth 1, X1.5 -> X2, bar 1/15 at 6.5 %, coins 0,
  Classic + Wooden Shovel; the test profile was restored + saved afterwards.
- **Free look:** `LAUNCH.CameraOrbit` (Enabled, Sensitivity 0.28 deg/px, TouchSensitivity 0.4,
  GamepadRate 150 deg/s, PitchMin -30 / PitchMax 45, ReturnDelay 1.5 s, ReturnRate 3, Zoom 0.5-2.5 by
  0.12 per notch). CLIENT_Snowball keeps `vars.CameraOrbit` {Yaw, Pitch, Zoom}: right-mouse drag
  (MouseBehavior LockCurrentPosition while held, Default on release / focus loss), touch drag off the
  GUI, right stick; `orbitVector` rotates the framing vector (camera minus look target) in heading +
  elevation and scales it by the zoom, applied in BindPadCamera (about the pad look point) and in the
  chase loop (`anchor + orbitVector(offset)`, before the ground-clearance lift), so follow / slope
  tilt / clearance are untouched. The chase starts from `vars.PadCameraBase` (the un-orbited pad
  framing) so a dragged pad view carries over as the same orbit, no jump. Verified numerically: yaw
  -30 deg turns the view 30 deg to the right (Roblox convention), pitch +20 deg lifts the look-down
  from 7 to 27 deg, zoom 2 doubles the distance, the angles return to 0 within 2.5 s; mid-ride yaw 90
  put the camera 86 deg off the ball's heading and it settled back behind. Off the pad the default
  Roblox camera is unchanged (already draggable).
- **Tooling:** `ras-dev/tools/manifest.py` + `compare.lua` = the Studio == repo check (was a scratchpad
  script). Architecture audit clean (ServerMain, ClientMain, ReEvent + ReFunction, no bindables,
  ScreenGuis only as UI templates + the framework's three in StarterGui, ServerStorage = Assets /
  Modules / Backups).

## 2026-09-24 (later): Rebirth panel restyled, attention arrows, Ascend

User: "make the rebirth UI look better, similar style to the frames from my New Map Cucumber Game
place, keep a backup of the previous one; notifications (NOT distracting) - arrows / pop-ups when a
new purchase or a rebirth is available; an 'ascend' feature: level 100, every piece of data resets,
permanent x13 power multiplier, its own UI, opened by stepping near the heavenly wings in the lobby."

- **Panels (Studio frames, not in the Rojo tree):** `extras/panels/build_panels.lua` builds
  `ServerStorage.Assets.UserInterfaces.HUD.Rebirth` and `.Ascend` in the New Map "Manage" look
  (maroon drop shadow, white body + pink/gold vertical gradient, tiled stud texture 14905298636,
  cream inner rim + coloured edge, banner header on the top edge with the rebirth icon, red X,
  gradient boost card with the arrow 113666736365393, level bar track + fill, green / gold button
  with an inner rim, FredokaOne + ink outline). Run it from an edit-mode execute_luau (it fetched
  fine through `ras-dev/tools/serve-src.ps1 -Root C:\Users\shrey\RAS` + `loadstring`). Layout is
  all Scale inside a window of 80 % screen height with a 1.25 UIAspectRatioConstraint; the
  constraint is FitWithinMaxSize, so the Size's width must be a real bound (a 0 width collapsed the
  whole panel to 0 x 0 on the first try). Names the HUD reads are unchanged (CurrentBoost,
  UpcomingBoost, Level + BackFrame + Frame.TextLabel/TextShadow, Buy + TextLabel/TextShadow, X).
  Backup of the old Rebirth frame: `ServerStorage.Backups.UI_Rebirth_before-restyle_2026-09-24`
  and `extras/Rebirth_before-restyle_2026-09-24.rbxm`; the UI snapshot
  `extras/ServerStorage_UserInterfaces.rbxm` was re-exported.
- **Ascend:** `PlayerProgress.ASCEND_LEVEL` 100, `ASCEND_POWER` 13; `AscendMultiplier` = 13 ^
  Ascensions, `RewardMultiplier(profile)` = rebirth boost x that (SERV_Snowball launch earnings);
  `ApplyAscend` replaces the whole profile with a fresh one (level, XP, coins, rebirths, mountains,
  gear, lifetime totals) keeping only Ascensions + 1. Saved as `Ascensions`; the stale-write guard
  now treats a payload with more ascensions as newer (fewer = stale) so the reset can be written
  even though the totals drop. `SERV_PlayerData.Ascend` mirrors Rebirth (shared `finishReset`).
  Attributes Ascensions / AscendLevel / AscendMultiplier. HUD: `Ascend` in CIRCLE_PANELS - the
  `Ascend` model (stairs + arrow + wings) inside the lobby's StartPlatform is the trigger,
  bounding box + `CIRCLE_RADIUS_PAD.Ascend` 4 studs; trigger models are cached
  (`api:GetCircleModel`) instead of a recursive FindFirstChild per frame. Panel logic =
  Rebirth's (RefreshAscendPanel / PressAscend / SetupAscendPanel, `SetPanelLevelBar` drives both
  bars, DevPress "Ascend"). PurchaseFX sparkles on `Ascensions` too. Verified in a playtest at
  level 100: everything reset, Ascensions 1, X13 -> X169, bar 1/100; test profile restored
  through `SetAsync` (the guard refuses 1 -> 0 on purpose).
- **Attention (quiet):** `AttentionState` = next buyable item per catalog (in order, mountain open,
  affordable), rebirth level reached, ascend level reached. A gold arrow (the panel arrow tinted,
  rotated to point at the button) bobs beside the Shop / Rebirth buttons (to the RIGHT: above them
  sit the coin counter and the button before), an "ASCEND!" billboard bobs over the wings, and each
  new key (item name / rebirth number / ascension number) gets one Notify.Info toast, queued one
  every 6 s after a 4 s settle on join. Hidden while that panel is open or during a ride;
  re-checked on attribute changes and every 2 s (the lobby generates after the HUD starts).
- **Rojo gotcha:** the rojo serve on 34872 was restarted by another session at 03:02 and the Studio
  plugin dropped ("WebSocket error ... forcibly closed"), so the second batch of edits never
  synced. Studio == repo was kept by pushing the sources through `ras-dev/tools/serve-src.ps1`
  (loopback, GetAsync + `Source =` in the edit DM, checksummed) until the user reconnects the
  plugin. Also seen in the console: the user rebirthed twice on the test account between my
  playtests (profile now rebirths 2, level 22, 7,691 coins).

## 2026-09-24 (later still): the shop remade in the New Map look, buy / equip made satisfying

User: "backup all frames and everything, and remake the shops taking inspiration from frames from
another open place 'new map cucumber game'. Also make sure purchasing/equipping things is smooth
and even more satisfying effects for that."

- **Backups first:** every UI frame + module of the place exported to
  `backups/RASDev_ui-before-shop-remake_2026-09-24.rbxm` (RobloxGames repo: ServerStorage.Assets
  .UserInterfaces, ServerStorage.Modules.UserInterfaces, ReplicatedStorage.Assets.UserInterfaces
  + .Modules, StarterGui HUD/Menu/Graphics); the old Shop frame itself lives on as
  `ServerStorage.Backups.UI_Shop_before-remake_2026-09-24`.
- **Reference:** the New Map's `StarterGui.CucumberMenus.ShopPanel` / `BuyShopPanel` / card
  templates (dumped with properties, plus an edit-mode capture): a left tab rail of square gradient
  tabs with a stud texture, a ribbon header overlapping the body, a chunky red X plate, rounded
  stud-textured cards with an inner rim, a green purchase pill, FredokaOne with an ink outline.
- **New frame** `ServerStorage.Assets.UserInterfaces.HUD.Shop` (Studio-only, built by
  `ras-dev/shop-remake/build_shop_frames.lua`, copy in the RAS repo at
  `extras/panels/build_shop_frames.lua`; idempotent, tagged with the attribute `ShopRemake`): the
  same structure on the RAS icy palette (navy #102A43 outlines, frost body gradient, blue ribbon
  with the shop icon, purple / blue tabs with the existing snowball + blaster icons, gold balance
  pill with the coin icon, cards 296 x 236 in a 3-column grid, rarity gradients Common ice blue ->
  Uncommon green -> Rare blue -> Epic purple -> Legendary gold, gold "x8" multiplier chip, padlock
  over locked icons, an EQUIPPED ribbon stamp, a Buy pill with a coin icon). Authored at 1140 x
  735 design px; `Panel.Fit` (UIScale) = min((W-40)/1140, (H-120)/735) clamped 0.35..1.1 and the
  panel sits at y 0.46 so the Notify strip (91.5 %) stays clear below it. The full-screen root
  keeps HUD.luau's PanelScale pop; an oversized Dimmer button behind the panel closes it.
- **Logic** moved out of HUD.luau into the new `ReplicatedStorage/Assets/Modules/Client/UI/
  ShopPanel.luau` (HUD.luau keeps OpenPanel / HidePanel / PanelManager / circles and delegates:
  SetupShopPanel -> ShopPanel.Setup, RefreshShopPanel -> Refresh, DisconnectShop -> Teardown,
  DevPress -> ShopPanel.DevPress; the four rule wrappers shopCatalog / nextShopOrder /
  shopOrderForSale / shopOwnedMap stay for the attention arrows). States per card: EQUIPPED (gold,
  inert) / EQUIP (green) / price green when affordable, amber when not / price grey + padlock when
  an earlier item must be bought first / "BEAT <MOUNTAIN>" grey + padlock. The next card for sale
  pulses a gold outline and the grid scrolls to it on open (row geometry from the UIGridLayout,
  not AbsolutePosition: a card mid pop-in reports its shrunken rect). Cards pop in with a 30 ms
  stagger, lift 3.5 % on hover (mouse only). Buying is client-checked first (mountain, order,
  coins -> Fail shake + toast) then invoked; a purchase plays Success on the pill, pops the card,
  floats UNLOCKED!, bursts 34 confetti pieces + a gold shockwave ring, sweeps a shine, flies 8
  coins from the pill into the balance pill which then rolls down in red, and toasts. Equipping is
  optimistic: the EQUIPPED ribbon stamps onto the card (2.6x -> 1, -24 deg -> -8 deg, thud) with a
  shimmer + shine, the old card's ribbon shrinks away, the replicated attribute confirms (revert
  after 2.5 s if it never does). `PurchaseFX` gained Confetti / Shockwave / Shine / Stamp /
  Unstamp / CoinFly (Heartbeat-stepped, parented to the LayerCollector at ZIndex 70+).
- **Verified in solo playtests** (test account awesomeotheraccount, rebirths 2 / level 22 / 7,691
  coins): 30 cards per tab, correct states, buy Rocky (7,691 -> 5,191, EQUIP, toast, all five
  effect layers present at 0.2 s), equip Rocky (stamp 2.02 -> 1.38 -> 1.00 -> 0.85 -> 1.00, server
  attribute confirmed) and back, Blasters tab + buy Snow Scoop (2,691, Snowball Flipper amber),
  reopen keeps the tab, canvas 0 on open after the scroll fix, toast clear of the panel. Profile
  restored to exactly rebirths 2 / level 22 / 7,691 coins / starter gear and force-saved.
- **Gotchas:** `card.Name` is the instance name, so the card's name label is `Title`; a UIScale'd
  child of a UIGridLayout reports the top-left of its scaled rect (the layout centres it in the
  cell), so scroll targets come from the layout maths; the Notify strip at 91.5 % of the screen
  bounds how tall a centred panel can be (FIT_MARGIN.Y 120 + centre 0.46 at 1301 x 611 leaves 14
  px); another session (Ascend / attention arrows) was editing HUD.luau in the same clone at the
  same time - pulled its 1003c19 first, patched only the shop hunks with exact-match Python
  patches, kept its wrappers, pushed through a checksum-guarded loopback GET (port 8797); the Rojo
  plugin was disconnected the whole time (the user has to click Connect).
