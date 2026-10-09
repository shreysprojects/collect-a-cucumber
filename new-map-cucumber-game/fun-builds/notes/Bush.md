# Bush - functional behaviour (2026-09-24, package GardenLife)

File: `src/behaviours/client/Bush.lua` -> `ReplicatedStorage.FunBehavioursClient.Bush`. **Client only.**
Serves Bush_A Shrub, Bush_B Hedge and Bush_C Flowering Bush, all at x1.25.

## What it does
* **Trigger**: a rustle happens when any character's root enters the bush's footprint.
  - Characters are every player's `HumanoidRootPart`, plus zombies (CollectionService tag `"Zombie"`, root =
    PrimaryPart or HumanoidRootPart).
  - The footprint is the hitbox's X/Z box plus a 1.3-stud margin, because the bush is solid and people brush its
    edge. It reaches from just under the floor to 4.5 studs above the top, so standing on the bush counts.
  - Moving faster than 2.5 studs/s inside the footprint repeats the rustle, at most every 0.4 s.
* **Shake**: the foliage does a quick decaying shiver about the bush's foot: 6.5 Hz with a 0.3 s decay. It leans
  the way the character moves, with up to 6 deg for A/C and 3.5 deg for the Hedge. The Hedge only rocks front and
  back, about its long axis. Strength grows with speed. Measured max travel: 0.14-0.22 studs.
* **Leaves**: each rustle pops 2-3 leaves out of the top of the bush (a pool of 6). They fly outward, flutter down,
  lie on the grass for 1.2 s and fade. They take the colours of the canopy / body / top / blooms parts, so the
  Flowering Bush sheds pink petals too.
* **Sound**: a soft rustle, played quiet and pitched up to 1.35-1.75. See the wishes below.

## Relies on
* Shaking parts: everything with the variant prefix except `Soil`, `Litter`, `Shade`, `Base` and the Shrub's
  `Stems`.
* The foot positions are authored numbers: A (7,0,0), B (0,0,0), C (-7,0,0).

## Cost
One `ctx:Step` (StepRange 110). It scans for characters 12 times a second: the player list plus the `Zombie` tag.
The bush is posed with `BulkMoveTo` only while it shakes, with one final frame at rest. Cleanup puts the parts back
at rest relative to the current hitbox.

## Sounds - wishes
* **`FunAssets.Sfx.Rustle` is wanted**: a short leafy rustle, about 0.4 s. The code plays
  `FunAssets.Sfx.Rustle or FunAssets.Sfx.Whoosh`, so adding the entry is enough.
* It respects `SFXEnabled == false` and plays only with the camera within 70 studs.

## How to test
Place Bush_B (the hedge) and run along it: it rocks and sheds leaves as you pass. At night zombies brushing it do
the same. On the client, look for `FunLeaf` parts under `workspace.CurrentCamera`.

## Known limits
* Detection is per client, from replicated positions. Every client sees every character's rustle, but the leaves
  are random on each client.
* Zombie roots are found through the `"Zombie"` tag (`ZombieCatalog.TAG`). If that tag changes, update `ZOMBIE_TAG`.
