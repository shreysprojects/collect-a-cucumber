# Sunflower - functional behaviour (2026-09-24, package GardenLife)

File: `src/behaviours/client/Sunflower.lua` -> `ReplicatedStorage.FunBehavioursClient.Sunflower`. **Client only.**
Serves Sunflower_A Tall, Sunflower_B Medium (with a bud on a side shoot) and Sunflower_C Clump, all at x1.5.

## What it does
* **Sun tracking**: the flower follows `Lighting:GetSunDirection()` in two parts:
  - The whole plant turns about the vertical through its stem foot, up to 22 deg. The stem foot is authored
    A (5,0,0), B (0,0,0), C (-5.4,0,0).
  - The head lifts about the neck toward the sun's height, by up to 8 deg (A/B) or 4 deg (C).

  Together that is never more than 25 deg. Why the whole plant turns: the side-shoot bud's yellow nose is merged
  into `B_PetalsYellow`, the sepal collar is merged into `A_Stem`, and the Clump's three heads are one mesh.
  Turning the plant keeps all of them attached. Measured bud-nose gap: at most 0.055 studs.
  - A sun behind the flower fades the turn back to 0, so the flower doesn't flip from side to side.
  - A sun near the zenith doesn't turn the flower either.
  - The turn eases in with a 5 s time constant. A flower that was off screen or asleep snaps straight to its target.
* **Night**: when the sun is below the horizon or `workspace.CyclePhase == "Night"`, the flower faces front and
  its head droops 9 deg (C: 4 deg).
* **Nod**: the head parts nod +/-3.5 deg (C: 2 deg) about the neck, with a 2.6-3.6 s period per build.
  The neck is `Pivot_A_Neck` / `Pivot_B_Neck`, or the average of `Pivot_C_Neck1..3` for the Clump.
* **Wind**: the whole plant leans 1.2-2 deg with the map-wide wind (the same as the trees). Everything runs off the
  server clock.

## Relies on
* Head parts: `<V>_Disc` / `C_Discs`, `<V>_PetalsYellow`, `<V>_PetalsOrange`.
* The rest of the plant (`<V>_Stem(s)`, `<V>_Leaves`) turns with it. `C_Mound` never moves.
* Pivots `Pivot_A_Neck`, `Pivot_B_Neck`, `Pivot_C_Neck1..3`. If they are missing, it falls back to the centre of
  the head parts.

## Cost
One `ctx:Step` (StepRange 140) and one `BulkMoveTo` of 5-6 parts. It poses every frame within 70 studs, at 15 Hz
beyond that, and not at all while off screen (unless the camera is within 25 studs). Cleanup puts every part back at
rest relative to the current hitbox.

## How to test
Set `Lighting.ClockTime` to 8, 12, 16 and then 22. The heads swing toward the sun (morning / afternoon), lift a
little, and droop at night. `workspace:SetAttribute("CyclePhase", "Night")` also makes them droop.

## Known limits
* The A head's green sepal collar is part of `A_Stem`, so it doesn't follow the nod or lift. Those are 11 deg at
  most, so only a sliver shows.
* The Clump's three heads nod as one group, because they are one merged mesh.
