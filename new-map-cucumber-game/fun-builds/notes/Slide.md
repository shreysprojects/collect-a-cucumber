# Slide - functional build (2026-09-24, fix pass the same day)

Files:
- `FB\src\behaviours\server\Slide.lua` -> `ServerStorage.FunBehaviours.Slide`
- `FB\src\behaviours\client\Slide.lua` -> `ReplicatedStorage.FunBehavioursClient.Slide`
- `FB\tools\slide_check\check_slide.py` is an offline geometry check. It copies the server's truss maths and
  plots it over the real ladder, hoop and deck from `props/build_slide.py`. It also prints the per-physique
  start-window and sit-lift table. Run it with `py check_slide.py 1.5 out.png`. The plot is at
  `FB\notes\Slide_trusses_x1.5.png`.

No model changes. The existing `Fun/Slide` prop (6 MeshParts, BuildCatalog scale x1.5) is used as it is.

## What it does
1. **Ladder (server).** Two invisible anchored `TrussPart`s, `SlideLadderTruss1` and `SlideLadderTruss2`, go in
   the runtime folder side by side. A TrussPart's cross-section is fixed at 2 x 2, so one truss covered only
   the middle 2 studs of the ~4.3-stud ladder.
   - Each is 2 x 8 x 2 at x1.5. The length is a multiple of 2 and scales with `ctx.Scale`.
   - They are tilted 8.9 deg to match the ladder.
   - At x1.5 they sit 1 stud either side of the centre line, so they meet in the middle and span X -2.0..+2.0.
     That is inside the rail centre lines (+/-2.13) and reaches the rails' inner surfaces (+/-1.92).
   - On a smaller slide they overlap instead: the offset is `clamp(1.42 * Scale - 1, 0, 1)`. They never stick
     out past the rails.
   - Their climbing faces sit 0.25 studs out from the rung axis on the +Z (back) side. The top edges are 0.05
     under the deck surface, and the top faces slope lower toward the deck, so there is no invisible lip. The
     feet are about 1.7 studs in the ground.
   - Walking into the ladder anywhere between the rails climbs it, and sidestepping while climbing keeps you on.
2. **Mantle (client).** The blue grab hoop over the back of the deck is only 1.44 authored = 2.2 studs
   above the deck, so a climber cannot walk through it. The mantle fires when all of these are true:
   - the local humanoid is `Climbing` upward in the band behind the ladder (authored |X| < 1.8, Z 4.0..6.8)
   - its root is no lower than deck - 0.6 studs

   The client then carries the character along a 0.28 s arc over the hoop to the middle of the deck, facing
   the chute.

   The trigger is on the root on purpose. What the hoop blocks is the head, which sits about 2.3 over the root
   on every physique. So a tall body is mantled almost as soon as it starts to climb: an 8-stud Champion's
   root is already about 5.7 over the ground, and the deck is 6.6. For them it is a step up, not a climb.
3. **Ride (client).** A ride starts when all of these are true:
   - the local root is over the channel (|X| <= 1.37 authored) on the slope (t 0.02..0.8)
   - the root is between 0.3 studs and **its own standing root height + 1.6** above the riding surface. The
     standing root height is `HipHeight + root.Size.Y/2`, or 3 on R6. That gives 4.6 on a default R15 and
     about 7.3 on a Champion. The old fixed 4.6 ceiling never let Strong-and-up physiques walk or fall into
     a ride.
   - the character is not rising faster than 10 studs/s
   - a ray down hits the `Chute` part

   At the start: `Humanoid.Sit = true`, the Whee sound plays locally, and `Send("Ride")` makes the server
   relay the whee to every other client.

   Each frame, bound at `RenderPriority.Camera - 1`, with a Heartbeat fallback:
   - Speed builds from 12 by `150*sin(slope) - 6` and is capped at 45. That gives about 42.6 studs/s at the
     exit and a 0.45 s ride at x1.5.
   - The root follows the authored parabola `Y = 0.40 + 4(1-t)^2, Z = 2.45 - 7.85t`.
   - It is glued to the Chute's real collision surface by a ray, plus a **sitting lift of
     `0.85 x root.Size.Y + 0.1`** (2.2 on R6). That is 1.8 on a 2-stud root and about 2.65 on a Champion.
     CONTRACT.md measured a seated root at about 1.7 over a seat's top face. The lift follows the torso,
     because a seated rider's legs are folded forward. The old `0.55 x HipHeight` term made a Champion float
     about 1.3 over the chute floor, above its 1.11-stud walls.
   - It leans 70% of the way into the slope, and its velocity is set along the tangent.

   At the end (t = 1): Sit comes off, the state goes to Freefall, and the character is placed upright at
   the exit at its standing height, with a pop of `forward min(24, 0.55 v)` + `up 20`. Jumping out mid-ride
   ends the ride where they are. If the sit does not hold (Seated is not reached within 0.2 s), the ride
   falls back to `PlatformStand` and a jump press ends it.
4. **"Slide!" prompt (server).** It sits on the invisible helper part `SlideTop`, 2 authored studs above
   the middle of the deck, with a range of 4 x Scale (6 studs). There is a 1.2 s cooldown per player.
   - The server checks the player's **feet**: root height minus the standing root height, divided by Scale.
     The feet must be at most 1.5 authored under the deck surface. That means the deck or the top two rungs
     (3.38 and 4.24).
   - The feet are checked, not the root, because a Muscular-and-up root stands 5+ studs over the ground. The
     old root gate let those players press "Slide!" from the ground behind or beside the deck and get blended
     through the ladder up to the chute.
   - If the check passes, the server sends `FireTo(player, "Start")`, and the client rides from the mouth,
     blending in over 0.25 s.

## What it relies on
- Part `Chute` (MeshPart): the ray target for detection and glue. Without it, the ride uses the analytic
  curve only.
- There are no `Pivot_*` attributes on this prop. The geometry comes from the Blender author's @Notes and
  `props/build_slide.py`, turned into the Roblox authored frame `(x, z, -y)`. I checked it against the dump:
  Chute bbox Z -5.5..2.7 and Y 0.11..4.99 match the curve. The ladder rails are at x +/-1.42 with radius
  0.14. Every number goes through `Kit.Origin` / `ctx.Scale`.
- The default `Animate` script plays "sit" when `Humanoid.Sit` is set without a seat (as admin `:sit` does).

## Sounds
- `FunAssets.Sfx.Whee` ("Slide Whistle") at the start of every ride, heard by everyone.
- Wish list: a short whoosh/landing thump at the exit (`Sfx.Whoosh` could do it) and a quiet plastic
  "swish" loop during the ride. Neither is used yet.

## How to test (integrator)
- Place a Slide. The runtime folder should hold `SlideLadderTruss1`, `SlideLadderTruss2` and `SlideTop`.
- Walk into the ladder from behind (the +Z side, opposite the chute exit), once at the centre and once about
  1.5 studs off-centre. Both should climb. Near the top, the local player attribute `FunSlide` becomes
  `"mantle"`, then `nil`, and `FunSlideLast = "mantle 0.28s"`. You are now on the deck.
- Walk forward off the deck into the chute. `FunSlide = "ride"`, then at the exit
  `FunSlideLast = "exit v=42.x t=1.00 0.4xs sit lift=1.8x"`. The `lift=` value is the sitting lift used. If
  it shows `stand` instead of `sit`, the sit did not hold. If it shows `bail`, the ride ended early.
- Repeat on a high-physique account (Muscular / Champion). Walking or falling into the chute must start a
  ride too. Check that the rider's hips sit in the channel, neither buried nor floating. If they are off,
  tune `SIT_LIFT_K`: lift = K x root.Size.Y + 0.1.
- On the deck, the "Slide!" prompt gives the same ride. On a high-physique account standing on the ground
  next to the ladder or deck, pressing it must do nothing.
- A quick client eval without the ladder: put the root over the upper chute.
  `root.CFrame = CFrame.new(Kit.ToWorld(slide, Vector3.new(0, 4.2 + 2, 1.2)))`, where
  `Kit = require(ReplicatedStorage.Modules.FunBuildKit)`.
- Jump mid-ride. The result should be `bail`, and the character carries on in the air.
- `FunSlide*` are LOCAL player attributes (set on the client, not replicated). Read them with a client eval.

## Known limits / open questions
- **Chute collision fidelity is unknown** (it was not in the dump). If the Chute's collision fills the
  channel (Hull/Box), the glue rides on its top when that top is within 1.3 authored above the curve.
  Otherwise the rider keeps to the curve. Physics may then nudge the character, but the per-frame CFrame
  wins.
- **`SIT_LIFT_K = 0.85` has only one measurement behind it**: CONTRACT.md's seated root at about 1.7 over a
  seat top, on an avatar of unknown physique. If that avatar was bigger than 2-stud-root default, K is a
  little high, by at most about 0.3 studs of hover on a Beginner. `FunSlideLast` now reports `lift=` so a
  playtest can set K.
- The trusses keep `CanQuery = true` in case the humanoid's climb check needs it. Their 2-stud-deep bodies
  sit on the deck side of the ladder, under the back of the deck. That space is closed by the ladder anyway.
  Zombie humanoids could climb them too, which is harmless: they stop at the hoop.
- The whole ride is short (about 0.45 s), because the chute is only 6.6 studs tall at x1.5. `G_EFF` /
  `MAX_SPEED` are the knobs if it should feel longer (for example `G_EFF = 90` gives about 35 studs/s and
  0.58 s).
- The mantle threshold (`MANTLE_BELOW = 0.6`) was worked out from geometry: the climber's front is about
  0.05-0.2 authored behind the hoop tube. For tall physiques it fires almost at the foot of the ladder, a
  6-stud step up in 0.28 s (see Mantle above). Check how that looks in a playtest.
- The rider's legs can clip the chute floor in the sit pose on the 45 deg top section. This is cosmetic
  only, because R15 limbs do not collide.

## Fix pass (2026-09-24): the reviewer's findings, all accepted
1. Fixed ride-start height ceiling (client): the window now scales with the avatar, as `standH + 1.6`.
2. Sitting lift scaled with HipHeight (client): it is now `0.85 x root.Size.Y + 0.1` (R6 stays 2.2), and
   `lift=` is added to `FunSlideLast`.
3. One 2-stud truss in the middle of the ladder (server): there are now two side-by-side trusses covering
   the ladder between the rails.
4. Prompt gate on the root height (server): it now gates on the feet height, for every physique.
