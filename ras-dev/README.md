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
