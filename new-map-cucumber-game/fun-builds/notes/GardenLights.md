# GardenLights: Lantern, TikiTorch, Fountain, Pond (2026-09-24)

This package adds behaviours to four existing Garden builds. Everything except the Fountain's collision change is
client-only VFX, driven by `Kit.Now()` so every client shows the same thing.

## Install

| file | goes to |
|---|---|
| `src/behaviours/client/Lantern.lua` | `ReplicatedStorage.FunBehavioursClient.Lantern` (serves Lantern_A/B/C) |
| `src/behaviours/client/TikiTorch.lua` | `ReplicatedStorage.FunBehavioursClient.TikiTorch` (serves TikiTorch_A/B/C) |
| `src/behaviours/client/Fountain.lua` | `ReplicatedStorage.FunBehavioursClient.Fountain` |
| `src/behaviours/server/Fountain.lua` | `ServerStorage.FunBehaviours.Fountain` |
| `src/behaviours/client/Pond.lua` | `ReplicatedStorage.FunBehavioursClient.Pond` |

No server half for Lantern, TikiTorch or Pond. There are no prompts, remotes or `Fun_*` states. Particle textures
are the engine's built-in `rbxasset://textures/particles/...` ones, so nothing needs uploading.

## What each one does, and what it relies on

### Lantern
- Adds a PointLight (warm 255,190,120, `Shadows = false` because it sits inside the glass or paper shell). It hangs
  on a runtime Attachment `FunLanternLight` at `Pivot_<V>_Light`, parented to the variant part nearest that point:
  A_Glass, B_Paper or C_Glass. Brightness flickers every frame and Range flickers at 10 Hz.
- At night it gets brighter and its range grows (A: 1.2 -> 2.6 brightness, range 10.5 -> 20 studs at x2.1). The
  change eases over about 1.5 s. Night means `workspace.CyclePhase == "Night"`, or `Lighting.ClockTime` < 6.5 or
  > 18.
- Post lamp (A), at night only: fireflies drift in a box around the lamp head (`Camera.FunFireflies`, 3 per second,
  box-volume emission).
- Paper lantern (B): the ball swings about `Pivot_B_Hang`, ±4° over 2.8 s, plus a ±1.2° cross sway over 4.3 s.
  - The moving parts are B_Paper, B_Brass, B_Core, B_CoreTip and B_Tassel. The light rides along on B_Paper.
  - B_Iron (the hook and hanger) stays still.
  - On cleanup the ball goes back to rest relative to the current hitbox, so a move leaves it in the right place.

### TikiTorch
- A local invisible anchor `Camera.FunTorchFlame` sits at `Pivot_<V>_FlameAnchor` and carries:
  - a Fire. Size is authored 1.5/1.5/2.0 × scale, clamped to the 2..30 engine range; Heat is 5/6/4 (the brazier
    burns lower and wider).
  - a flickering PointLight, brighter at night.
  - rising embers, 6/6/9 per second.
  - the crackle loop `FunCrackle` (`FunAssets.Sfx.FireLoop`, volume 0.22). It plays only while the camera is
    within 40 studs and stops beyond 46.
- It does not touch any build part.

### Fountain
- **Server half:** makes WaterSurface, WaterBed, Jets and Foam `CanCollide = false`, as the prop author asked, so
  people can wade into the basin (down to the BasinWall floor at 0.40 authored). It remembers each part's original
  value in the part attribute `FunCollideOriginal` and restores it on cleanup. While the build is `Broken` it
  leaves collisions alone: BuildHealthService owns them then and restores its own record on mend. The test
  harness covers the break → mend → move sequence.
- **Client half:** everything hangs off `Camera.FunFountainFX`, placed at the authored origin:
  - **Plume:** droplets rise from `Pivot_JetOrigin` to just over `Pivot_JetTop` (measured peak 4.22 against 4.20)
    and fall back onto `Pivot_BowlWaterTop`, landing about 0.6 from the finial.
  - **Five streams:** droplets ride the Jets mesh's five parabolas from the bowl lip into the basin. They are
    re-solved from `props/build_fountain.py` (`_arc_points`, `JET_ANGLES`) and land at r 2.38 / 2.20, y 0.73.
  - **Splashes:** flat splash rings on the basin water where the streams land (every 0.4 s, each with a kicked-up
    droplet), rings where the plume lands in the bowl (every 0.45 s), a mist puff every 1.8 s, and a constant faint
    mist over the bowl.
  - **Wading ripples** under anyone moving through the basin water.
  - **Water loop:** `FunWater` (`FunAssets.Sfx.WaterLoop`), heard only within 40 studs.

### Pond
- **Koi:** three koi are built from local parts, 10 parts each: ellipsoid body, eyes, koi spots, pectoral fins,
  dorsal fin and a forked two-wedge tail.
  - They swim lazy elliptical loops near the Fish1..3 pivots, 0.15–0.17 below `Pivot_WaterSurface`.
  - Speed glides in and out, they bank into turns, and the tail beat follows their speed.
  - Fish1's dorsal fin breaks the surface, as the authored fish's did, and leaves a small wake ring.
  - The loops were fitted offline to the real shoreline, recomputed from `props/build_pond.py`'s seeded ring. Nose
    and tail keep 0.23–0.32 authored studs of clearance (see `GardenLights_koi_loops.png`).
- **Hiding the static koi:** Fish1..3, FishEyes and FishMarks are hidden with `LocalTransparencyModifier = 1`, which
  is client-only and never touches the server's Transparency or the broken fade. It is set back to 0 on cleanup.
  - Fix pass (2026-09-24): BuildMenuClient's move ghost writes `LocalTransparencyModifier` on every part of a
    build being moved (0.85 while it is on the mouse; `StopPlacing` puts 0 back). A cancelled move, or a drop on
    the same spot, leaves the hitbox where it was, so nothing restarts the behaviour. Before the fix the frozen
    static koi then stayed visible next to the swimming ones. Each hidden part now has a
    `GetPropertyChangedSignal("LocalTransparencyModifier")` handler that puts 1 back whenever the value drops
    below 1. The handler is guarded by `ctx:Alive()` because `FunBuildClient.Stop` marks the ctx dead before it
    runs the cleanup that sets 0. ArcadeCabinet handles the same case.
  - The swimming koi are local parts, so BuildMenuClient never ghosts them. They copy the move-ghost value from
    `Bank` (falling back to `Water`, then `Bed`), so during a move they fade with the rest of the pond instead of
    swimming at full strength in a ghosted pond.
- **Ripples:** random open-water ripples every 1.4–3.2 s, kept off the shore and the pads. There is also a ripple
  every 3–6 s where a koi noses the surface, and ripples under anyone walking on the pond.
- **Lily pads:** LilyPads and LilyLotus bob together (±0.03 authored, 0.6° tilt, 1.5° drift). They are restored on
  cleanup.
- **Water stays COLLIDABLE (my call).** It is the pond's surface, a zero-thickness sheet, and the water is only
  about 0.45 studs deep in the world. Letting people sink to the bed would only push their feet through the koi and
  the lily pads, so they walk on the pond and leave ripples instead.

## How to test
- Place Lantern_A/B/C, TikiTorch_A/B/C, Fountain and Pond on a plot.
- Client checks (Explorer on the client):
  - Lantern: `A_Glass/B_Paper/C_Glass.FunLanternLight.PointLight`.
  - `workspace.Camera` holds FunFireflies (post lamp), FunTorchFlame (Fire, PointLight, Embers, FunCrackle),
    FunFountainFX (attachments Plume, Stream1..5, BasinSplash, BowlSplash, Mist, Sound) and FunPondFX, plus 30
    `Koi*` parts per pond.
- Night: the admin panel night, or `workspace:SetAttribute("CyclePhase", "Night")`, makes lanterns and torches
  brighter and switches the fireflies on.
- Server check: the Fountain's WaterSurface/WaterBed/Jets/Foam have `CanCollide == false` and a
  `FunCollideOriginal` attribute. Walk into the basin to see ripples, and walk onto the pond to see ripples there.
- Broken: `BuildHealthDev = "break"` stops everything. Static koi reappear (faded), lanterns go dark, and the
  fountain's collisions follow BuildHealthService. `"heal"` restarts it all.
- Headless test harness in `tests/GardenLights/`:
  - Run `py gen.py`, then `luau.exe run.luau`.
  - It runs all five modules against a mocked Roblox with real CFrame maths and the props-dump geometry, placed with
    a 37° yaw and catalog scales. It currently reports 1803 checks, 0 failed.
  - The mock fires `GetPropertyChangedSignal` handlers immediately, and the test ctx follows `FunBuildClient.Stop`'s
    order: mark the ctx dead, run cleanups, then disconnect. The Pond test replays BuildMenuClient's move ghost
    (0.85 on every part, then 0) for a cancelled move, a stop, and a restart during the ghost. Mutation check: with
    the re-hide removed, 4 checks fail; with the `ctx:Alive()` guard removed, 6 fail because the handler fights
    the cleanup.
  - Redirect its output to `out.txt`, then run `blender -b --factory-startup --python koi_preview.py` to render the
    runtime koi (`notes/GardenLights_koi_top.png`, `_three.png`).

## Sounds / assets wished for
- `FireLoop`: a real soft fire-crackle loop. The current "Rock Crumble" is only a stand-in.
- `WaterLoop`: a real fountain or trickle loop. The current "Water Splash" is a one-shot being looped.
- Optional `FunAssets.Textures = {Droplet = ..., Ripple = ..., Mist = ...}` (IMAGE ids). If present, Fountain.lua
  uses them; otherwise it keeps the built-in textures.

## Known limits
- LilyPads and LilyLotus are each one merged mesh, so all pads bob together. The motion is kept subtle for that
  reason.
- Hard-coded geometry has to be refitted if the props are re-authored: the koi loops, the shore polygon and the pad
  list follow the current pond mesh, and the fountain's JETS table follows `build_fountain.py`. The tools are in
  `tests/GardenLights/`: `pond_paths.py` with `fish_final.py` checks shore clearance.
- The game's "bright night" keeps day lighting, so the night boost is visible but not dramatic.
- `Fire.Size` cannot go below 2, so the torch Fire is a little fuller than the neon flame meshes.
- The lantern light Attachment is added client-side inside a build part, as the brief asked. A client script that
  clones placed builds would copy it, which is harmless.
- During a build-mode move, only the Pond's koi follow the ghost fade. The torch Fire, the lantern light and the
  fountain and pond particles stay at full strength on the faint original until the move ends. This is cosmetic
  and lasts only while the build is on the mouse.
- Fountain particle budget is about 23 per second continuous plus about 8 per second in splash bursts. Pond ripples
  are about 2 per second. Each build has one light (0 for the Fountain and Pond) and one `ctx:Step`.
