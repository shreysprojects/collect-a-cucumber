# Trampoline - bouncy (2026-09-24)

**File:** `FB\src\behaviours\client\Trampoline.lua` → `ReplicatedStorage.FunBehavioursClient.Trampoline`
(`B.Keys = {"Trampoline"}`, `B.StepRange = 220`). **There's no server half.** The bounce is physics on the local player's own
character, and the mat animation is only cosmetic. There's no prompt.

## What it does
* **Bounce (local character only).** Every frame, while the root is inside the mat radius (authored r 2.95 × Scale = 4.43 studs at
  ×1.5) and not rising, the code casts a ray down from the root. The ray includes only the `Mat*` parts, and its length is the hip
  height + 0.4 + 1.1 × this frame's fall. If the ray misses but `FloorMaterial` is the mat's material with the feet at mat height,
  that counts as a hit too. On a hit the code calls `Humanoid:ChangeState(Jumping)` and sets
  `root.AssemblyLinearVelocity.Y = 55 / 75 / 95 / 110`, adding +15 while Space, gamepad A or the touch jump is held. Horizontal
  velocity is kept.
  * **Chain:** a bounce counts as consecutive when it lands within *expected airtime + 0.6 s* of the last launch. The brief said
    "within 0.6 s of the last", but that can't work, because the airtime alone is 0.56–1.27 s. If the player lands on anything that
    isn't the mat, or misses the window, the chain goes back to level 1. Since the fix pass, landing somewhere else resets
    the chain even beyond the 14-stud wake radius. Before, that check came after the early return for being far away.
  * **Launch guard (two-sided, fix pass 2026-09-24):** nobody has measured yet whether the Jumping state's own impulse
    (~53 studs/s) *replaces* our Y velocity or *adds* to it, and the Running controller also eats bare velocity writes. So for
    0.15 s after a launch the guard sets the vertical speed to `sqrt(V² − 2g·rise)`, whenever the root is more than 1.5 studs/s
    off it in **either** direction. That is the speed that still peaks at the launch apex from the height the root has already
    reached. It pushes up when the impulse replaced the launch and pulls down when it stacked on top. The target is worked out
    from height, not time, so the one frame flown at the wrong speed is paid back too. Without the pull-down, an additive jump
    sent the bounces to about 29 / 41 / 56 / 68 studs (measured offline). The guard lets go if the root is more than 1 stud
    below the launch height or more than 4 studs above the launch trajectory, which means a teleport or something else moved it.
  * **No bounce** when the character is seated, dead, swimming, climbing, ragdolled / FallingDown / GettingUp, PlatformStand,
    anchored or at WalkSpeed 0. It also doesn't bounce when Jumping is disabled or jump power is 0 (the collect/carry freezes).
  * **Front flip** on every level-4 bounce. It is visual only: the root joint's `Transform` (Motor6D `C0` or AnimationConstraint
    `Attachment0`; the joint from HumanoidRootPart to LowerTorso/Torso, never a carried prop) is turned 360° about the root centre
    in `RunService.Stepped`. It runs from 12 % to 74 % of the airtime. The physics root stays upright, so nothing can trip. If the
    Animator didn't write the joint that frame, the rotation isn't stacked on top of itself (tested). Only this client sees its own
    flip, because joint transforms don't replicate. The flip stops if the player lands early. Whoosh sound when it starts.
* **Mat animation (every player this client sees).** `Mat*` (MatSurface) drops by `State_Bottom` × Scale (−0.75 studs), pressing
  down in 0.06 s. It then springs back with a damped cosine (decay 0.075 s, period 0.22 s, rest after about 0.4 s, overshoot about
  +0.19 studs). `Springs` follows 35 % of the dip. What triggers it:
  * the local bounce (depth 0.7 / 0.85 / 1 × bottom by level);
  * another player's root inside the radius, moving down and within `clamp(fall × 0.08 s, 0.8, 4)` studs above the mat. The
    same root triggers again only after it rises, climbs more than 5 studs, or after 0.6 s.
    **Fall speed (fix pass):** the faster-falling of two readings wins. One is the replicated `AssemblyLinearVelocity`
    projected on up. The other is a position rate that samples only when the root has actually moved, over the real
    `os.clock()` time since it last moved. `ctx:Step` runs on RenderStepped *and* Heartbeat whenever they are ≥ 4 ms
    apart, and one of those runs sees no new position. The old per-call `dt` read a real 110 studs/s landing as 69. Both
    readings must agree before a root counts as rising. The kick comes up to 4 studs before contact, so the impact speed
    (for pitch and ring) is extrapolated down to the mat: `sqrt(v² + 2g·gap)`.
  Parts are posed relative to the Hitbox and nothing is written at rest. Cleanup puts them back only if they were moved.
* **Sound / FX.**
  * `FunAssets.Sfx.Boing` plays on each bounce from a pool of 3. Pitch is 0.95 / 1.08 / 1.21 / 1.34 by level, +0.05 while jump is
    held. For other players the pitch comes from impact speed.
  * Level ≥ 3 bounces, or another player landing at ≥ 80 studs/s, trigger a dust + sparkle burst. These are `Emit` bursts only
    (Rate 0), using built-in `rbxasset://textures/particles/smoke_main.dds` / `sparkles_main.dds`. They use a Disc shape with
    `ShapePartial = 1` so the burst comes off the rim as a ring. Shape properties are set inside a pcall.
  * The sounds and emitters live on a local, invisible helper part `TrampolineFX` (via `ctx:Part`, under CurrentCamera) above the
    mat centre.

## Relies on
`MatSurface` (any `Mat*`), `Springs` (optional), `Pivot_MatCentre` (0, 0.68, 0) with an authored fallback,
`State_Bottom` (−0.5, default −0.5) and model `Scale`. The mat must be query-able (CanQuery true, which is the template default).
If it isn't, the FloorMaterial fallback still works.

## Tested offline
`FB\tests\trampoline\run.ps1` runs the real Kit + FunAssets + this module against mocked Vector3/CFrame/Instances. The humanoid
is scripted: the ground controller eats bare velocity writes, and the Jumping impulse can be set to replace, add,
max(Y,0)+add, or leave the velocity alone, and can land late. The Step can run once or twice per frame (RenderStepped +
Heartbeat). The build is yawed 30°. Theory is V²/2g = 7.7 / 14.3 / 23.0 / 30.8. The measured apexes run about 0.2–1 stud
higher because the lookahead launches the root just before it touches the mat.

| Test | Result |
|---|---|
| Drop onto the mat, jump impulse **replaces** Y | apex 7.8 / 14.5 / 23.3 / 31.9, pitches 0.95 → 1.34 |
| … impulse **adds** to Y (was 29 / 41 / 56 / 68 before the fix) | 7.9 / 14.5 / 23.3 / 31.8 |
| … max(Y,0) + jump | 7.9 / 14.5 / 23.3 / 31.8 |
| … leaves Y alone | 7.8 / 14.5 / 22.8 / 30.7 |
| … adds, one physics step late | 7.9 / 14.5 / 23.2 / 31.8 |
| … adds at 30 fps / replaces at 30 fps | 8.5 / 15.2 / 24.2 / 30.2 and 8.4 / 15.2 / 24.1 / 30.4 |
| … adds, Step on RenderStepped + Heartbeat | 7.9 / 14.5 / 23.3 / 31.8 |
| Space held | 41 studs (theory 39.8) |
| Walk off onto grass | no more bounces |
| Back on after a rest | level 1 again |
| Stand on the pad collar | no bounce |
| Walk in from the pad | bounces |
| Flip (Animator writing and not writing) | joint tilt 0.0° at every bounce |
| A carried Motor6D on the root | untouched |
| Remote lands at 69 → 75 (single Step) | estimated 69 / 72, one boing each + a dip |
| Remote at 95, two Steps per frame, no replicated velocity (was read as 58) | 94, small ring |
| Remote at 110, two Steps, replicated velocity (was 69, no ring) | 110, big ring |
| Remote at 110, two Steps / one Step, positions only | 108 / 108, big ring |
| Cleanup | mat and springs exactly at rest |

## How the integrator can test in Studio
Place a Trampoline, walk onto the mat and don't press anything:

* Heights should climb 7.7 → 31 studs and the boing should rise in pitch. **Most important Studio check:** if a level-1
  bounce goes clearly higher than ~8 studs (for example ~30), the Jumping impulse is stacking and the guard is not catching
  it, so report that. The quickest measure is to print `root.AssemblyLinearVelocity.Y` for 3 frames after a bounce.
* From the 4th bounce on, the character flips.
* Hold Space to gain about 9 studs more.
* Walk off to reset the chain.
* With 2 clients, the mat should dip on the watching client when the other player lands.

## Open issues / wishes
* **Reach:** 31 studs straight up (about 40 with Space) plus ~1.1–1.3 s of air control could carry players over plot walls, night
  barriers or onto roofs. Check the map for places the lobby shouldn't reach. If there are any, lower `LAUNCH`, or skip the
  bounce while the player has `CarryingCucumber` set.
* The Jumping impulse's real behaviour is still unmeasured in Studio. Offline, the two-sided guard holds the apex whether the
  impulse replaces, adds, adds a frame late, or does nothing. What it can't cover is an impulse that lands more than 0.15 s
  after the launch, or one that keeps pushing for longer than that. Neither is how Roblox jumps are known to behave.
* Ceiling: if the root hits something inside the 0.15 s window, the guard keeps asking for the launch speed until the window
  closes. That's harmless (0.15 s), and it was already the behaviour before the fix.
* Zombies / NPCs don't dip the mat. Only `Players` characters are watched, to keep it to one cheap loop.
* **Sound wish:** a real trampoline "boing" (a spring twang). `Button Pop` is only a stand-in.
