# Hammock - functional behaviour (2026-09-24)

Files: `src/behaviours/server/Hammock.lua` -> `ServerStorage.FunBehaviours.Hammock`,
`src/behaviours/client/Hammock.lua` -> `ReplicatedStorage.FunBehavioursClient.Hammock`. Build scale x1.35.

## What it does
* **Server**: one lying seat (`ctx:Seat{Lie = true}`, name `HammockSeat`, prompt **"Lie down"**, distance 9,
  anyone may use it). Seat top = the occupant's back = `Pivot_BedLow` + 0.14 authored up (the sheet's top
  at the centreline, so the body sinks a little into the crescent), shifted 0.25 authored toward -X because
  the body is longer below the root than above it. Seat LookVector = the build's local **-X**
  (`origin.Rotation * CFrame.Angles(0, pi/2, 0)`), so the head lies on the pillow (authored x -2.15..-1.35)
  and the feet end near x +2 (usable area x -2.2..2.2).
* **Client**: Bed / Weave / Cords swing as one rigid sling about the line through `Pivot_RingMinusX` and
  `Pivot_RingPlusX`: angle = amp * sin(2 pi * Kit.Now() / 3 s). amp = 0.6 deg idle sway, ramps to 5 deg over
  1.6 s after someone lies down and back over 2.8 s after they leave (from `Fun_Since`, so all clients
  agree). The runtime seat is CFramed with the sling locally, so the occupant rocks on every client.
  A Creak when someone drops in, then ~40% of swing ends creak (deterministic from the swing index).
  Everything is posed relative to the Hitbox each frame; cleanup puts the parts back at rest (relative to
  where the Hitbox is now) and the seat back at the server's CFrame.

## Relies on
* Parts `Bed`, `Weave`, `Cords` (swing); `Rings`, `Rails`, `Timber` stay put.
* Attributes `Pivot_BedLow`, `Pivot_RingMinusX`, `Pivot_RingPlusX` (fallback for BedLow: (0, 1.2, 0)).
* State: `Fun_Seat` = the server ctx's runtime folder name (client finds
  `workspace.FunBuildRuntime.<Fun_Seat>.HammockSeat`), `Fun_Occupied` (bool), `Fun_Since` (server time of
  the last change, 0 = never).

## Sounds
* `FunAssets.Sfx.Creak` (currently "Click Sound", pitched 0.5-0.68). **Wish:** a real rope / wood creak
  (short, ~0.5 s) - the click reads as a tick, not a creak.

## How to test
1. Place a Hammock, walk up to the middle of the long side: prompt "Lie down" (E).
2. Trigger it: the avatar lies flat, head on the pillow (-X end). Server: `seat.Occupant` set,
   model attribute `Fun_Occupied = true`, `Fun_Since` = now.
3. Watch the sling: it rocks +/-5 deg sideways (3 s period) with the avatar, creaks now and then; a second
   client sees the same swing in phase. Jump out: it eases back to a tiny sway over ~3 s.
4. Move the build while someone watches: no jump back to the old spot; sell / break it: the parts are at rest.

## Known limits
* The body is straight (the framework straightens lying joints) while the sheet is a catenary, so the
  feet sink ~0.5 stud into the fabric toward the +X end (reads as being "in" the hammock). Tune
  `BACK_ABOVE_LOW` / `TOWARD_PILLOW` in the server half if it looks off with the taller physique avatars.
* The swing is subtle by design (the ring line is only ~1 stud above the bed at x1.35): the roll is visible,
  the sideways travel is ~0.1 stud.
* Collidable build parts are CFramed locally every frame (3 parts) while the camera is within 150 studs.
