# RAS - Dev (place 128775411268189) - resort props, ball flight, smashing

Source mirrors of the scripts changed on 2026-09-16 live in `src/`. The Studio copies are
the live ones; `install.lua` pushes `src/` into Studio while
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


## Development

Keep the source mirrors in `src/` aligned with the Studio scripts when making changes.
Configuration for props, flight, smashing, sounds and launching lives in `MountainConfig.lua`.
UI assets are in `assets/`; the supporting scripts are stored alongside their feature folders.
