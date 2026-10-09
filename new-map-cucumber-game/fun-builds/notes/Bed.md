# Bed - new Home build + behaviour (HomeBedroom, 2026-09-24)

Files: `models/build_Bed.py` -> `models/out/Bed.parts.json` (install with `install/install_models.lua`, key `"Bed"`,
category Home), `src/behaviours/server/Bed.lua` -> `ServerStorage.FunBehaviours.Bed`,
`src/behaviours/client/Bed.lua` -> `ReplicatedStorage.FunBehavioursClient.Bed`.
Renders: `models/renders/Bed_front.png`, `_three.png`, `_back.png`.

## The model
67 parts, **8.0 wide** (on the 8-stud grid, like the Sofa) x 6.01 tall (moon roundel top) x 9.1 long, quilt top 2.2,
`Cost = 1200`, `Seats = 2`.
Wooden four-poster-style frame (turned posts, ball finials, brass foot caps), headboard at the BACK (+Z): wood panel,
round top rail, a padded dark-blue oval cushion with 8 yellow star dots (turned to the cushion's curve), and a wooden
roundel on the rail with a crescent moon (the night-light). Low footboard at the front (-Z) with two raised insets.
Cream mattress/sheet, blue patchwork quilt (4 x 3 checker) with draped sides and rounded edges, its top end folded
back (cream lining, blue stripe, rolled crease), two pale-yellow pillows (2.9 wide) leaning on the headboard. Back of
the headboard has an inset panel too.
The integrator may want a `DisplayName` ("Bed") and a BuildCatalog entry. **Do not give it a `BuildCatalog.SCALE`**:
it is built at real size for the 6-stud avatar, and SCALE is uniform (it would raise the quilt above the ~2.2 bed top
and the moon roundel with it).

Why 8 wide (fix pass 2026-09-24): lying blocky avatars are ~4 studs wide with their arms. The first 6.3-wide version
put the two inner arms in the same space and the outer arms in the air beside the frame. Now the pelvises sit at
x = +-2.0, so the inner arms meet edge to edge on the centre line, and the outer arms reach x +-4.0: mostly on the
quilt (edge 3.68), with the outer ~0.3 over the quilt edge, like an arm at the edge of a mattress. This was checked
with a temporary render of two lying blockouts built from the CONTRACT's measured lie extents (since deleted).

## What it does
* **Server**: two lying seats (`ctx:Seat{Lie = true}`, names `BedSeat1` / `BedSeat2`, prompt **"Sleep"**,
  object = DisplayName or "Bed", distance 8, anyone may use them). Seat top = `Pivot_Sleep<i>` (the quilt top
  at the pelvis spot, authored (+-2.0, 2.2, 1.1)) minus 0.08 sink; seat LookVector = the build's **+Z**
  (`origin.Rotation * CFrame.Angles(0, pi, 0)`), so the head lands on Pillow<i> (pillows span z 2.55..3.95,
  centres (+-1.9, 2.34, 3.25)). Per the CONTRACT's measured lie extents the head top ends at z ~3.6, about 0.3
  in front of the padded headboard at head height (room for taller physique stages), and the feet end near
  z -2.7 (the quilt runs to -4.05).
  Each prompt hangs 1.5 authored studs out over its own side of the bed and 1.2 up.
  State: `Fun_Sleeper1` / `Fun_Sleeper2` = UserId of the occupant (0 = empty).
* **Client**:
  * "Z z z": per sleeper a BillboardGui (in PlayerGui, `ResetOnSpawn = false`, adorned to the sleeper's Head,
    falling back to a local anchor at the pillow) floats three FredokaOne "Z"s (white-blue, dark UIStroke) up
    from the head: each grows, wobbles, tilts and fades over 2.7 s, staggered; timed from `Kit.Now()` so all
    clients match; the two sides are phase-offset.
  * night-light: while anyone sleeps every `Night*` part (NightLight = the moon disc, NightStar1..9 = star
    dots) turns Neon pale-yellow and a dim warm PointLight (Brightness 0.7, Range 12) in `NightLight` fades in
    over 1.2 s (out again when the bed empties), with a quiet Sparkle.
  * the sleeper's pillow squashes (SpecialMesh Scale/Offset only: 0.8 height, a touch wider), eased.
  * a low Creak when someone lies down.
  Cleanup restores every Night* part's material/colour and the pillow meshes.

## Relies on
* Parts `Pillow1`, `Pillow2` (Ellipsoid = Block + SpecialMesh Sphere), `NightLight`, `NightStar*` (prefix
  `Night`), `Mattress` (sound parent).
* Attributes `Pivot_Sleep1/2`, `Pivot_Pillow1/2` (fallbacks in both halves), `Pivot_NightLight` (informational).

## Sounds (wishes)
* `Sfx.Creak` (Click Sound pitched 0.55) on lie-down - **wish:** a soft bed/mattress creak or sheet rustle.
* `Sfx.Sparkle` (quiet, 0.8 pitch) when the night-light comes on - fine as is.
* **Wish:** a gentle snore loop (would play from the sleeper's head while `Fun_Sleeper<i>` ~= 0).

## How to test
1. Install `Bed`, place it, walk to either long side: prompt "Sleep" (E) over that side.
2. Trigger it: the avatar lies on its back, head on that side's pillow. Server: `BedSeat<i>.Occupant` set,
   model attribute `Fun_Sleeper<i>` = your UserId. Client: Zs float above the head, the moon + stars glow,
   PointLight `BedNightLight` under `NightLight` fades to 0.7, the pillow flattens a little.
3. Second player takes the other side: second set of Zs (out of phase). Both jump up: Zs gone, the glow fades
   out over 1.2 s, pillows puff back.
4. Move / sell / break the bed while someone sleeps: they are released (the seat is destroyed), parts at rest.

## Known limits
* Two blocky sleepers fill the 8-wide bed exactly: their inner arms touch on the centre line, and each outer arm
  hangs ~0.3 past the quilt edge. Wider avatars (bigger physique stages, Rthro) will overlap a little in the
  middle. Do NOT fix that with `BuildCatalog.SCALE`: it scales uniformly, so it would also raise the quilt
  above the ~2.2 bed top. Widen the model in `build_Bed.py` instead (POST_X / MAT_X / BL_X / SLEEP_X / PILLOW_X).
* People sleep on top of the quilt (no under-the-covers pose).
* The Zs are TextLabels in a BillboardGui (no verified "Z" particle texture in FunAssets).
