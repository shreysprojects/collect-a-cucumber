# HotTub - working hot tub (2026-09-24)

Files
- `src/behaviours/server/HotTub.lua` -> `ServerStorage.FunBehaviours.HotTub`
- `src/behaviours/client/HotTub.lua` -> `ReplicatedStorage.FunBehavioursClient.HotTub`
- No model change (existing `Fun/HotTub`, `props/build_hot_tub.py`, template scale 1.4).

## What it does
Server
- **Water / Foam / Steam: CanCollide = false** while it runs (restored from the TEMPLATE's values on cleanup,
  skipped while `Broken` because BuildHealthService owns the collisions then).
- **`OWN_COLLIDERS = true`** (top of the server file): Shell / StavesMid / StavesPale / Steel also stop colliding, and
  27 invisible anchored blocks in the runtime folder take over, matching the authored tub exactly:
  `HotTubWall0-11` (r 2.62..3.20, floor to rim top 2.56), `HotTubBench0-11` (r 1.98..2.64, floor to 1.35, solid),
  `HotTubFloor` (cylinder, top 0.28), `HotTubStep1-2` (the two treads). Reason: the Shell is one hollow mesh, and so are the
  staves and steel. If their CollisionFidelity is Hull or Box, the whole cavity is solid and nobody can step in. I could not
  check the fidelity from files. If `ServerStorage.Builds.Fun.HotTub.Shell.CollisionFidelity` is
  PreciseConvexDecomposition (or Default and it tests fine), you can set `OWN_COLLIDERS = false`.
- **4 seats** `HotTubSeat1-4` (ctx:Seat, 2 x 0.4 x 2) at authored r 2.22, angles 0/90/180/270 (right, back, left, front; the
  panel is at 232), facing the centre, **sunk below the bench top** so a seated player is chest-deep:
  - A sitting root rides `SIT_ROOT_OVER_TOP` = 1.7 over the seat's top face (the CONTRACT's playtest: ~1.9 over a 0.4 seat's
    centre). A seat resting ON the bench (top 1.35 x 1.4 = 1.89 world) would put the root at 3.59, which is 0.44 OVER the
    water (2.25 x 1.4 = 3.15). That leaves the waterline at the hips.
  - So each seat drops by `seatSink = (BenchTop - WaterTop) * scale + 1.7 + ROOT_UNDER_SURFACE`. With `ROOT_UNDER_SURFACE = 0.7`
    that is 1.14 at x1.4. It is clamped so the seat top stays `SEAT_MIN_OVER_FLOOR` = 0.2 over the tub floor.
  - World numbers at x1.4: seat centre 0.55 over the tub origin, seat top 0.75 (2.40 under the surface), root 2.45 (**0.70
    under the surface**). On a default R15 (torso proportions from the engine's R15 rig) the UpperTorso spans the root +0.06 to
    +1.9, so the waterline sits on the lower chest. The shoulders are about 0.95 over the water and the head centre about 1.8.
    The thighs dip into the (submerged) bench slab. The soles hang about 0.2 under the seat top, clear of the floor.
  - Why 0.7 and not 0.3: with 0.3 the waterline would be 0.24 over the waist (belly-deep), which is not the chest-deep look
    the brief asks for.
  - The "Hop in" prompt floats 1 stud over the rim behind each seat, at the same world spot as before (the lift includes
    `seatSink`). Its reach is `max(4.5, 3.6*scale)` = 5.04. From a seat, the neighbouring seats' prompts are 5.55 away (the
    opposite one 7.49) and stay hidden, so a sitter only sees the jets prompt (3.4 to 7.1 away, reach 10).
- **Jets**: `JetsPrompt` on `Panel` at `Pivot_PanelTop` + 0.5 up. ActionText switches between "Bubbles on" and "Bubbles off". It toggles
  model attribute **`Fun_Jets`** (starts false). There is a 0.4 s debounce and anyone can use it.
- **Splash**: fired to all clients as `"Splash" {Position, Big}` when a seat gets an occupant, or when a client sends
  `Splash` after its character stepped into the water. The server ignores the payload and checks the player's real position:
  r <= wall + 0.8 and feet no more than 6 studs over the surface (a falling character arrives late). The cooldown is 1.5 s per player and 0.2 s
  per tub. Seated players are ignored.

Client
- The Water shimmers (Transparency ±0.05 and a Color lean toward pale cyan; the part never moves) and the Steam mesh breathes.
  Soft white steam rises from the whole surface all the time (smoke texture, Rate 5, or 9 with the jets on).
- With jets on: 8 bubble jets on the bench ring (angles 22.5 + k*45, between the seats, tilted 20 degrees inward), Rate 5 each.
  There are also 8 foam-ring emitters on the surface (flat rings, Rate 2 each), surface fizz (Rate 18), the water turns paler and livelier,
  one underwater PointLight fades in, the PanelLights pulse (dim `PANEL_OFF` while off), and `FunAssets.Sfx.BubblesLoop` plays looped at
  volume 0.28, only while the camera is within 55 studs. A `Click` plays on toggle.
- Splash: spray burst + ring + `Sfx.Splash` (random pitch). The local character entering the water triggers one splash
  per entry, so jumping in, or jumping about inside, splashes.
- Every emitter is off beyond 170 studs of camera distance, and Step sleeps beyond 150. Particle textures are built-in:
  `rbxasset://textures/particles/smoke_main.dds` and `.../explosion01_shockwave_main.dds` (a soft ring; checked in the
  local Roblox content folder).
- Cleanup restores Water / Foam / Steam / PanelLights Color and Transparency from the template. While Broken it keeps the
  0.65 fade.

Parts and pivots it relies on: `Water`, `Foam`, `Steam`, `Panel`, `PanelLights`, `Shell`, `StavesMid`, `StavesPale`, `Steel`,
`Pivot_WaterSurface` (fallback 0,2.25,0), `Pivot_PanelTop`. The authored radii and heights come from `props/build_hot_tub.py`.

## Sounds wished for
- `BubblesLoop` is currently "Water Splash 2", probably a one-shot, so looped it would sound like repeated splashes. It needs a real
  bubbling / jacuzzi loop (about 3-10 s, seamless).
- `Splash` "Water Splash" and `Click` are fine.

## How to test
1. Place a Hot Tub. Check `workspace.FunBuildRuntime.HotTub_<owner>_<hex>`: 4 Seats and 27 `HotTub*` collider parts.
   The model's `Water.CanCollide` should be false, and `Fun_Jets` false.
2. Walk up the front steps and hop over the rim. You land in the water on the floor or the bench, with a splash and spray.
3. "Hop in" on a seat prompt: the character sits facing the middle, and the water line should cross the lower chest (head,
   shoulders and upper chest out). Numeric check: `root.Position.Y - Kit.Pivot(model, "WaterSurface").Y` should be about
   **-0.70** for a default avatar. Accept -1.0 to -0.4, since the 1.7 sit offset is itself a measurement. Also check
   `seat.Position.Y - Kit.Origin(model).Y`, which should be 0.55. The seat top is 2.40 under the surface at x1.4.
   - Result near -0.7: done.
   - Result outside -1.0 to -0.4: the real sit offset is not 1.7. Set `SIT_ROOT_OVER_TOP` to the measured
     `root.Y - (seat.Position.Y + 0.2)`, and the code re-sinks the seats so the root lands at -0.7 again.
   - On target but the look is wrong: tune `ROOT_UNDER_SURFACE`. A bigger value sits deeper, 0.3 is belly-deep, 1.0 is mid-chest.
   - Then jump off the seat. The character should pop up out of the seat cleanly (see Known limits).
4. Press "Bubbles on" at the panel (also from a seat). `Fun_Jets` should be true and the prompt should read "Bubbles off". On the
   client, `workspace.CurrentCamera.HotTubFX` should have its Bubbles / FoamRings / Fizz emitters Enabled, and the `Bubbles` sound
   IsPlaying should be true within 55 studs and false beyond.
5. Run `workspace:SetAttribute("BuildHealthDev", "break")`, then `"heal"`: while broken, nothing runs (seats and colliders are gone, and the water
   stays faded and non-colliding). After the heal, everything comes back.

## Known limits
- Bubbles rise through the translucent Water part. Transparent sorting can hide some of them from some angles; ZOffset 0.6
  pulls them forward.
- The colliders form a 12-sided ring. The rim's collision edge is 0-0.11 outside the visual rim, and the steel hoops stand 0.1
  proud of it. The Panel keeps its own mesh collision.
- The seat depth is one static number for every avatar, tuned to the default one (`SIT_ROOT_OVER_TOP` 1.7,
  `ROOT_UNDER_SURFACE` 0.7). Bigger physique stages have a larger sit offset, so they sit higher. For a 1.3x body the root is
  about 0.2 under the surface and the waterline is at the belly. Nobody's head goes under.
  - A per-avatar fit is possible if wanted: on `SeatWeld` added, shift `C0` down by (the root's height over the surface + 0.7),
    the same way the framework's Lie seats edit C0.
- While seated, the HumanoidRootPart's bottom (root - 1) is 0.44 inside the bench collider. That does not matter while
  welded to the anchored seat. When the player jumps off, physics pushes the root up out of the bench along with the jump.
  Watch for a pop in the playtest. If it is rough, lower `ROOT_UNDER_SURFACE` to about 0.3, which leaves almost no overlap
  but makes the water belly-deep.
- Other scales: the sink is worked out from `ctx.Scale`. At x1.2 the root sits 0.46 under the surface. At x1.0 the floor
  clamp leaves it only 0.07 under, because the tub is too shallow to be chest-deep at that scale.
- Footsteps inside the tub sound like Wood (the collider material).

## Offline checks (fix pass, 2026-09-24)
- Headless Blender cutaway renders of the real tub (props/build_hot_tub.py) with seated R15 blockouts (engine R15 rig
  proportions, 1.7 sit offset) at the behaviour's seats, old seat vs the sunk seat, are in the session scratchpad:
  `HotTub_sit_old_vs_new.png` (level section: old = torso fully out, thighs at rim height; new = waterline on the lower
  chest) and `HotTub_sit_new_three.png` (3/4 view, 4 sitters: heads and shoulders over the rim). Script: `hottub_sit.py`.
