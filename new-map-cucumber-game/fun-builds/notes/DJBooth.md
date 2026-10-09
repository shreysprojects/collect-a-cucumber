# DJBooth package: DJ booth + dance floor behaviours (2026-09-24)

## Files
| file | installs as |
|---|---|
| `src/behaviours/server/DJBooth.lua` | `ServerStorage.FunBehaviours.DJBooth` |
| `src/behaviours/client/DJBooth.lua` | `ReplicatedStorage.FunBehavioursClient.DJBooth` |
| `src/behaviours/client/DanceFloor.lua` | `ReplicatedStorage.FunBehavioursClient.DanceFloor` (no server half) |
| `tests/DJBooth/` | offline test: mock DataModel that runs the REAL FunBuildService + FunBuildClient + these modules (see below) |

No framework changes are needed. No models, so there are no renders.

## DJ booth (x1.3)
**Server:** prompts sit on an invisible helper part (`DJBoothPrompts`, runtime folder) at authored (0, 2.95, 0.45), just above the mixer:
* `DJPlayPrompt`: "Play music" / "Stop music" (E / ButtonX). Anyone can use it, with a 0.75 s cooldown.
* `DJNextPrompt`: "Next track" (R / ButtonY). It is parented only while the music plays and sits one prompt-height lower (UIOffset 72), the same approach as the TV. Its ObjectText reads `Track i/n  <Name>`.
* State: `Fun_Playing` (bool), `Fun_Track` (index into `FunAssets.Music`), `Fun_StartedAt` (`Kit.Now()`). Play and Next both reset `StartedAt`.

**Client** (everything local, driven by that state + `Kit.Now()`):
* **Music:** one looped Sound `DJBoothMusic` in the booth's Hitbox (Volume 0.6, RollOff 14..120, InverseTapered). Every 0.5 s (and on each state change) `TimePosition` is compared with `(Kit.Now() - StartedAt) % TimeLength` and re-seeked when the drift is over 0.6 s.
  * It pauses when the camera is more than 200 studs away, or when the LocalPlayer attribute `MusicMuted` is true (the MusicClient convention).
  * The lobby music ducks to 0.15 via `MusicManager.SetDuck("FunDJBooth")` while the character is within 70 studs of a playing booth. The DJ track is NOT registered with MusicManager, otherwise the duck would duck it too.
* **Records:** the prop's `Records` part is ONE mesh holding both vinyls, so each deck gets a runtime Neon disc (`DJRecordA/B`, 0.71 authored diameter, centre at authored y 3.10 over `Pivot_Deck?Platter`). Each disc has two dark groove marks and spins clockwise at 45 rpm, hue cycling.
* **Spot cans:** these are merged into `Hardware`, so each gets a runtime beam anchor (`DJSpotBeam`: a SpotLight plus a camera-facing Beam, width 0.4 -> 3.6 authored, 11 authored long, fading out) and a Neon lens cap (`DJSpotLens`) over the real lens.
  * The beams sweep between `State_SpotAimFloor` (-120, as built) and `State_SpotAimCrowd` (-100), with a mirrored yaw of ±28°, so they cross over the floor. Colours cycle and the two cans are half a hue apart. That makes 2 lights in total.
  * All runtime parts live in a local `workspace.DJBoothFX` folder, not the camera, so the SpotLights light the world.
* **Beat:** `Letters`, `LedStrip` and `SpotGlow` pulse Transparency by 0 to +0.5, and `LedStrip` also cycles hue.
  * While the track is audible, `Sound.PlaybackLoudness` drives the pulse (an onset follower). Otherwise a fixed 120 BPM pulse runs on the `StartedAt` grid.
  * On idle, cleanup, or when the build is broken, the original Color and Transparency are restored. A broken build keeps `max(T, 0.65)`, the same as BuildHealthService, so the fade is not undone locally.
* **Far camera:** when the camera is more than `StepRange` (220) away, the beams, discs and lights come down instead of freezing in the sky.
* **Shared with the floor:** `B.Live[model] = {Pulse, Beat, At}` is read by the DanceFloor client.

**Tonearms / spot-can tilt: not animated on the shipped prop.** Both tonearms and both spot cans are merged into `Hardware` together with the platters and horns, so they cannot move alone.
* The arms stay in their built pose, which is the PLAYING pose (`State_ArmPlaying = 0`).
* The code already supports split parts and moves them if the model ever gets:
  * `DeckATonearm` / `DeckBTonearm`: swing about `Pivot_Deck?Tonearm` between ArmParked 20 and ArmPlaying 0 (negated on deck B).
  * `DeckAPlatter` / `DeckARecord` (+B): spin instead of the runtime discs.
  * `SpotA` / `SpotB`: the can follows its beam.
* Split parts are restored relative to the Hitbox's current CFrame, so a move never leaves them behind.

## Dance floor (x1.5)
* **Tiles:** `Tile_r<row>_c<col>`, where row 0 = +Z (back) and col 0 = +X, per the prop's grid contract.
  * **Idle:** the shipped checkerboard at `State_Dim` (Transparency 0.45). The lit half swaps every 2 s using the prop's GLOW hexes.
  * **Playing:** when any `DJBooth` build (tag `PlacedBuild`, base key DJBooth) within 60 studs has `Fun_Playing = true`, the tiles go to `State_On` (0) and cycle through three patterns, 8 beats each: checker swap, rainbow wave, and a ripple from the centre.
    * The beat comes from that booth's `DJBooth.Live` pulse while that booth's client Step is live, else 120 BPM from its `Fun_StartedAt`, so floors next to one booth flash together.
    * `PowerLight` turns lime while playing.
* **Footsteps:** the tile under ANY character lights up: brighter while playing, switched on while idle.
* **Writes:** at most 30 Hz, and only when a value changes, so an idle floor writes nothing between swaps.
* **Cleanup:** restores every tile's Color, Material and Transparency (a broken floor keeps the 0.65 fade) and PowerLight.
* **Dancing:** while the LOCAL character stands on a floor (inside the frame, grounded, not seated), a bottom-centre button shows in `PlayerGui.FunDanceGui`.
  * It sits above the hotbar, is styled like the HUD (FredokaOne, green gradient / red when active, dark UIStroke, rounded, UIScale from the viewport) and gets the `ButtonFX` press pop. It is also bound to key **G** through ContextActionService (G is unused in the game's scripts; a small "G" hint shows on keyboard devices).
  * **DANCE** plays the next R15 dance as a looped Action-priority track on the local Animator (507771019 -> 507776043 -> 507777268 -> ...). The Animator replicates it to everyone. **STOP** ends it.
  * The dance also stops on walking (MoveDirection > 0.1), jumping (`Jump` / Jumping / Freefall state), sitting, dying, or leaving the floor.
  * One module-level controller and one GUI serve every floor.

## How to test in Studio
1. Place a DJBooth and a DanceFloor within 60 studs of each other. Press E on the booth's "Play music" prompt.
2. On the server, check the booth's attributes `Fun_Playing` / `Fun_Track` / `Fun_StartedAt`.
3. On the client, check:
   * `Hitbox.DJBoothMusic` is `IsPlaying`, with `TimePosition ≈ (workspace:GetServerTimeNow() - Fun_StartedAt) % TimeLength`
   * `workspace.DJBoothFX` holds 2 record discs, 2 beam anchors and 2 lenses
   * the tiles are at Transparency 0
4. Press R ("Next track"): `Fun_StartedAt` resets and the track restarts. With a single track in `FunAssets.Music` it just restarts.
5. Walk onto the floor: `PlayerGui.FunDanceGui.Enabled` should be true. Press G or tap DANCE, then walk to stop.
6. Break the booth with `workspace:SetAttribute("BuildHealthDev", "break")` while it plays. The Neon parts should stay at 0.65 and the FX should disappear.

**Offline:**
```
cd FB\tests\DJBooth; py build_test.py; & C:\Users\shrey\.rokit\tool-storage\luau-lang\luau\0.739.0\luau.exe run_test.luau
```
Result on 2026-09-24: 0 failed checks, 0 runtime errors, 0 warnings.

The test runs the real FunBuildService + FunBuildClient against a mock DataModel with an environment that errors on any unknown global. It covers:
* prompts, state and sync / drift / next track / track wrap
* beams, lights and the Neon pulse
* floor dim / lit / out of range, and footsteps on specific tiles
* dance start / cycle / stop on move, jump, STOP or leaving the floor, the G binding, and GUI hide
* mute, far camera, stop, broken + mended, moved, and sold

## Wishes / open points
* **FunAssets.Music** has one track. Please add 3-5 loopable dance tracks (~120-128 BPM, verified to load); the Next prompt already lists them.
* **Record scratch sfx:** none is listed, so no sfx plays on play or next. A `Sfx.Scratch` could be added later.
* **Dance emotes:** R15 only. On an R6 rig the track loads but shows nothing, with no error.
* **Spot-can tilt and tonearm swing** need the model split (see above). Without the split, the beams sweep from the static lenses (up to ~28°/20° off the can axis).
