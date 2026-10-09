# BeanBag - functional behaviour (2026-09-24)

Files: `src/behaviours/server/BeanBag.lua` -> `ServerStorage.FunBehaviours.BeanBag`,
`src/behaviours/client/BeanBag.lua` -> `ReplicatedStorage.FunBehavioursClient.BeanBag`.
Serves BeanBag_A (Pouf), BeanBag_B (Slouch), BeanBag_C (Ottoman) through the base key. Build scale x1.4.

## What it does
* **Server**: one seat per variant (`BeanBagSeat`, prompt **"Flop down"**, distance 7, anyone may use it),
  facing the build's front (-Z). Hips rest on the top centre of the variant's seat part, measured as it
  will be SQUASHED (x0.88 about the floor), 0.06 authored sunk in, never below 1.05 authored above the
  floor (1.47 studs, so sitting feet clear the floor):
  * A Pouf: on `A_Body` (top 1.61 authored) -> hips ~1.89 studs
  * B Slouch: in the hollow `B_Seat` (top 1.19) -> hips ~1.55 studs, back against the tall bolster (+Z)
  * C Ottoman: on `C_Dome` (top 1.45) -> hips ~1.70 studs
  If a named part is missing it uses the variant's tallest part. State: `Fun_Occupied` (bool).
* **Client**: while occupied every `<Variant>_*` part is squashed about the floor point under the bag:
  Y x0.88, X/Z x1.05 - each part resized in its own frame (factor along each of its axes) and its centre
  moved by the same squash, so the bag stays in one piece. Rigid materials (Wood, Metal ... = `C_Feet`,
  `B_Zip`) move but never resize. A damped spring (k 220, c 15: ~15% overshoot, settles in ~0.85 s) dips a
  touch deeper when someone flops in and puffs up a touch when they get up; nothing is written at rest.
  A soft "poof" (`FunAssets.Sfx.Whoosh`, volume 0.22, pitch 0.62) plays on sit. Streaming in on an
  occupied bag shows it squashed at once, silently. Cleanup restores every part's exact rest Size and
  CFrame (relative to where the Hitbox is now).

## Sounds
* `FunAssets.Sfx.Whoosh` pitched down. **Wish:** a real soft fabric / bean-bag "poof" (a beanbag flop or
  pillow thump) - then set `POOF_SPEED` back to 1.

## How to test
1. Place each variant (Pouf / Slouch Bag / Ottoman); walk up: prompt "Flop down" (E).
2. Trigger it: the avatar sits on top facing the build's front; `Fun_Occupied = true`; the bag sinks with a
   little bounce and a soft poof. Jump off: it springs back (slight puff) and settles.
3. A second client sees the squash when the state flips. Move / sell / break it while squashed: the parts
   return to their exact rest shape.

## Known limits
* MeshPart.Size is set at runtime on the client (supported; scales the mesh). The seat itself is static
  (the hips don't ride the spring's ~2% overshoot - invisible).
* The squash centre is the Hitbox's floor point (the variant's bounding-box centre); B's hitbox floor is
  0.06 authored above the true floor (its lowest mesh starts there) - harmless.
