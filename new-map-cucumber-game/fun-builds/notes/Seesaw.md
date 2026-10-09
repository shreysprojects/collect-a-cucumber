# Seesaw - functional behaviour (2026-09-24)

Files:
* `src/behaviours/server/Seesaw.lua` -> `ServerStorage.FunBehaviours.Seesaw`
* `src/behaviours/client/Seesaw.lua` -> `ReplicatedStorage.FunBehavioursClient.Seesaw`
* `tests/Seesaw/` (prelude.luau, driver.luau, run.ps1): offline harness that runs the real Kit + both halves in the
  Luau CLI against stub CFrames (no Studio needed). `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Seesaw\run.ps1`

## What it does
* **Two seats**, one on each yellow seat pad ("Ride" prompt, anyone may ride, Object text `Seesaw (red)` / `(blue)`).
* **Nobody on:** the plank drifts back to rest (RedDown, the shipped pose) in about 2 s and settles on the red tyre-stop
  with a very soft thump.
* **One rider:** their weight swings their end down onto its tyre-stop (about 1 s, a small bounce, a thump).
* **Two riders:** a see-saw ride between the two down poses, period 2.2 s: push off, swing across, land still
  moving (bump + 0.7 deg rebound), rest 0.2 s, push off again. Creak (`Sfx.Creak`) at every push-off,
  thump at every landing. The angle is a pure function of `Kit.Now() - Fun_Since` (+ `Fun_Lead`), so every
  client rides in step. The first push-off comes 0.35 s after the second rider sits.
* The runtime seats are carried with the plank **locally on every client** (same rotation, same pivot: seat =
  pose * seat offset), so the welded riders go up and down. The server's plank and seats never move.
* Cleanup puts every `Plank*` part back as shipped (relative to the Hitbox, so a move lands clean) and the seats
  back where the server put them.

## Geometry it relies on (all authored frame, scale 1, x ctx.Scale at runtime)
* Parts: every BasePart whose name starts `Plank` (PlankBeamRed, PlankBeamBlue, PlankSeats, PlankHandles,
  PlankPivotStrap) = one rigid plank. Sounds are parented to PlankPivotStrap (creak) and PlankBeamRed / PlankBeamBlue (thumps).
* `Pivot_PlankPivot` = (0, 1.35, 0) (fallback hard-coded). Swing axis = the build's authored **Z** (Blender Y ->
  Roblox Z: the axle runs across the plank). Swing(angle) = `CFrame.Angles(0, 0, -rad(angle))`: positive drops the red +X end.
* `State_RedDown` (+12, the shipped pose = rest), `State_BlueDown` (-12). The rig is taken relative to the LEVEL
  pose = the shipped parts un-rotated by State_RedDown.
* Seat pads (from `props/build_seesaw.py`, plank-local level frame, origin at the pivot): pad top 0.40 above the
  pivot line between x 2.42 and 3.06, backstop inner face at x 3.06. Seat = hips on the pad top (+0.03), rider's root
  0.6 studs in from the backstop (x = 3.06 * scale - 0.6 = 4.91 studs at x1.8), facing the pivot / grab bar.
  At x1.8 the down seat's top is ~2.1 studs off the floor (feet reach the ground), the up seat's ~4.2.
* Verified offline: at level the beams sit at authored (+/-1.90, 1.49, 0) = the Blender box centres; the seats stay
  on the pad top at every angle (error 0); nothing but Plank* ever moves; cleanup is exact, also after a move.

## State (model attributes)
| Attribute | Meaning |
|---|---|
| `Fun_RiderRed` / `Fun_RiderBlue` | UserId on the red (+X) / blue (-X) seat, 0 = empty, -1 = a non-player (scripted dummy) |
| `Fun_Since` | `Kit.Now()` when both seats became occupied, 0 otherwise |
| `Fun_Lead` | +1 / -1: the end that was down at Since (the ride starts there). If the second rider sits less than 0.64 s after the first (or 1.4 s after the plank started drifting back to rest), the plank has not passed level yet, so it counts as still down at the old end |
| `Fun_Id` | matches the `SeesawId` attribute on this build's two seats |

Seats (in `workspace.FunBuildRuntime/<folder>`, named `SeesawSeatRed` / `SeesawSeatBlue`, CollectionService tag
`FunSeesawSeat`) carry `SeesawId`, `SeesawSide` (+1 red / -1 blue) and `SeesawOffset` (Vector3: the seat's position in
the plank's level frame, world studs). The client finds them by tag + id and follows re-streams / server restarts.

## How to test (integrator)
1. Place a Seesaw. Walk to a seat pad, press E on "Ride". The blue end drops if you took blue (`Fun_RiderBlue` = your
   UserId). Jump off: it drifts back to red-down.
2. Ride with two players, or solo with a dummy: from a server eval, seat a rig humanoid on the other seat
   (`workspace.FunBuildRuntime:FindFirstChild("SeesawSeatRed", true):Sit(workspace.Rig.Humanoid)`: it counts as
   rider -1). `Fun_Since` appears and the plank oscillates. Unseat the dummy (`humanoid.Jump = true`, or destroy the seat's `SeatWeld`).
3. Look for: the seated character going up and down with the pad (no sliding), creak at each push-off, a thump at each
   landing, a smooth ride with no snapping on a second client, the plank back as shipped after a move / sell / break.

## Sounds wished for
* `Sfx.Creak`: a short wooden/metal creak (today "Click Sound"; the client plays it at PlaybackSpeed 0.72-0.9).
* `Sfx.Thump` (**new key, optional**): a soft rubbery thump for an end landing on its tyre-stop. Until it exists the
  client falls back to `Sfx.CanDrop` ("Big Thud") at volume 0.06-0.3, scaled by landing speed.

## Known limits / open questions
* Needs a two-client check in Studio: every client moves its own copy of the anchored seats, and the welded characters
  should follow the local seat on all clients. The rider's server-side position stays at the shipped pose (up to
  ~2.4 studs off on the blue seat). That only affects server-side distance checks; the physics is client-owned.
* Seated R15 thighs may brush the grab bar's uprights (the bar is ~1 stud in front of the root at x1.8). This is only
  visual: the rider is welded, so nothing collides.
* The server never CFrames the plank, so server-simulated things (zombies) collide with it in the shipped RedDown pose.
* No Actions / remotes are used. `B.StepRange` = 180.
