# Bathtub - new Home build + behaviour (HomeBath package, 2026-09-24)

Files:
* model `models/build_Bathtub.py` -> `models/out/Bathtub.parts.json` (70 parts, 8.06 x 3.98 x 3.81 studs, category
  **Home**, `Cost = 1000`), renders `models/renders/Bathtub_front.png / _three.png / _back.png`
* `src/behaviours/server/Bathtub.lua` -> `ServerStorage.FunBehaviours.Bathtub`
* `src/behaviours/client/Bathtub.lua` -> `ReplicatedStorage.FunBehavioursClient.Bathtub`

Build it at **scale 1** (no `BuildCatalog.SCALE` entry). It is sized for the 6-stud avatar already. A bigger
scale moves the seat up and out with the tub, but the avatar stays the same size, so the bather would sit
lower in the water.

## The model
A white clawfoot tub, ~7 long (X) x 2.8 to the rim x 3.4 wide (Z). Parts: a straight-sided stadium wall
(`WallMid` Block tangent to 2 upright `WallEnd*` Cylinders, y 1.5-2.62) turned under by a long `Belly`
Ellipsoid plus a shallow `BellyEnd*` Ellipsoid under each round end, a roll-top rim (2 long Cylinders +
4-segment half rings with Ball joints), and light-blue water 0.12 under the rim top (Block + 2 Cylinders, top
y 2.68). It has four gold lion-claw feet (a leg Cylinder + a Ball paw), heaps of foam (4 flat Ellipsoid
mounds and 8 Balls), a yellow rubber duck near the front, and a blue bath pillow on the head-end rim (-X). At the tap end (+X) is a freestanding gold filler: 2 floor pipes, a mixer, red and blue cross handles,
and a gooseneck spout that arches over the rim. The foam, bubbles, duck, pillow and spout do not collide.

## What it does
* **Server**
  * One **lying seat** (`ctx:Seat{Lie = true}`, name `BathSeat`, prompt **"Take a bath"** (E), distance 9,
    anyone may use it). Its top face is at `Pivot_BathSeat` (the pelvis, authored (-1.2, 1.8, 0)). Its
    LookVector points at `Pivot_BathHead`, so the head goes toward the end **without taps** (-X, onto the
    pillow), reclined 10 degrees.
  * With the measured lie offsets (head 2.5 toward LookVector, feet 3.8 back, body 0.8 above the seat), the
    torso sits at the water line and the face is up above the water. The feet stay inside the tub: I checked
    this with a blockout render.
  * The prompt floats over the front rim, mid-tub.
  * **"Bubbles"** prompt (R / ButtonY, distance 9) on `TapMixer` at `Pivot_Taps`. It toggles `Fun_Bubbles`,
    and switching on also stamps `Fun_BubblesAt = Kit.Now()`. The ActionText reads "Bubbles off" while they
    run. The bubbles turn themselves off after 300 s. You can reach the prompt from inside the tub.
  * Someone getting in or out: `Fun_Bathing` is set and `ctx:Fire("Splash", {Position, Big})` is sent.
* **Client**
  * **Always**: the duck (`Duck*`, one rigid group about `Pivot_Duck`) bobs, rolls and slowly turns. It moves
    about 2.6 times as much while bubbling or while someone bathes. Any `BubbleFloat*` parts would hover
    (optional; the model has none since the fix pass). Everything runs from `Kit.Now()`, so all clients show
    the same thing.
  * **Bubbles on**:
    * the `Foam*` mounds swell by 14% and wobble
    * the loose `Bubble*` balls jiggle
    * soft foam puffs rise off the whole water surface (Rate 10)
    * pink and blue ring-bubbles float up out of the tub and pop (Rate 12)
    * `Sfx.BubblesLoop` loops within 60 studs
  * **Fresh switch-on** (under 1.5 s old): a burst of foam and bubbles. The spout pours for 2.6 s: a local
    light-blue stream from `Pivot_SpoutTip` to the water, ripple rings where it lands, and `Sfx.WaterLoop`.
  * **Splash** event: spray and a ring on the water under the bather, plus `Sfx.Splash`.
  * Cleanup puts the duck, foam and bubbles back at rest, relative to where the Hitbox is now, and restores
    the foam sizes. Effects live in a local `BathFX` part and a `BathPour` part.

## Relies on
* Parts: `Duck*`, `Foam*`, `Bubble*` (a name starting `BubbleFloat` would mean a floating bubble; optional,
  none in the model now), `TapMixer` (the prompt host; falls back to the Hitbox).
* Attributes (authored Vector3): `Pivot_BathSeat`, `Pivot_BathHead`, `Pivot_Taps`, `Pivot_SpoutTip`,
  `Pivot_Duck`, `Pivot_WaterMin`, `Pivot_WaterMax`. Both halves hold the same numbers as fallbacks.
* State: `Fun_Bubbles` (bool), `Fun_BubblesAt` (server time, 0 = never), `Fun_Bathing` (bool).

## Sounds
All three are real, verified ids in `FunAssets.lua` (checked 2026-09-24). Keep them:
* `Sfx.BubblesLoop` = a 13.8 s stream-of-bubbles loop (plays looped while `Fun_Bubbles` is on).
* `Sfx.WaterLoop` = a 36 s running-water / fountain loop (plays looped while the spout pours after a switch-on).
* `Sfx.Splash` for getting in / out.
* **Wish** (the only one left): a rubber-duck squeak (it could squeak when someone gets in).

## How to test
1. Place a Bathtub (Home). Walk up to the long front side: **"Take a bath"** (E). The avatar lies in the
   water with the head on the pillow end (-X) and the face up. The other end has the gold taps.
   * Server: `workspace.FunBuildRuntime.<folder>.BathSeat.Occupant` is set and `Fun_Bathing = true`.
   * Every client sees a splash.
2. Stand near the gold taps (or stay in the tub): press **R "Bubbles"**. The spout pours for about 2.5 s,
   foam bursts, then the foam mounds swell and bubbles drift up.
   * `Fun_Bubbles = true` and `Fun_BubblesAt` is about `workspace:GetServerTimeNow()`.
   * The prompt now says "Bubbles off". Press it again: everything settles back over about 1 s.
3. The duck bobs all the time, and harder while bubbling or while someone is in the tub.
4. Move the build while bubbling: nothing is left behind. Sell or break it: the foam and duck are at rest.

## Known limits
* The long sides are straight (a Block tangent to the round-end Cylinders), like a real clawfoot tub's. In
  Roblox they shade as one smooth wall with the round ends. The first renders showed them as a pale flat
  "label": that was a preview artifact. primlib's cylinder mesh shares its ring vertices with the smooth-shaded
  caps, so Blender bends the cap normals into the side and short wide cylinders render like dark barrels.
  `build_Bathtub.py` now marks those edges sharp (`_roblox_shading`, render only, the part data is unchanged).
  **Integrator:** every model's short/wide cylinders have the same render artifact; the same few lines in
  `primlib._add` would fix all reviews.
* Fix pass 2026-09-24: tried long Ellipsoid side skins (WallSideF/B, the reviewer's first option). Every tuning
  read as a puffy pillow panel with creases where the skin crossed the round ends, the rim and the belly, so
  they were not kept. A painted exterior was also rendered; it still showed the preview's pale panel and the
  brief asks for a white tub.
* Fix pass 2026-09-24: the single Belly is an ellipse in plan and left a shadowed ledge under the wall around
  the round ends; `BellyEndL/R` (shallow Ellipsoids 0.02 inside the wall line) now turn the wall under all the
  way round. Paid for by dropping the two static `BubbleFloat*` balls (specks at play distance; the rising
  bubble particles do that job).
* The rim's round ends are 4-segment polylines with ball joints (a little octagonal from above).
* The body lies straight (the framework straightens lying joints) and reclines 10 degrees. Very tall physique
  avatars may push their feet through the tap end or the belly. If so, move `Pivot_BathSeat` toward -X or up
  in `build_Bathtub.py`, or lower `RECLINE`.
* The water top collides (like any furniture top), so people can stand on the bath instead of falling into
  it. Only the seat puts you "in" the water.
* 70 parts (the furniture limit).
