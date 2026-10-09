# PottedPlant (package HomeDecor, 2026-09-24)

New Home build: a big leafy monstera in a glazed pot. A round-bellied cobalt-glazed pot (dark foot, cream equator
band and a thinner lower band, eight yellow shoulder dots, a cream glazed lip) on a terracotta saucer, dark soil
(a disc sitting on the lip, a thin cream ring showing round it) with two pebbles, eleven fronds (each a stem from the soil to a heart-shaped leaf made of two ellipsoid halves
toed in at the tip and folded into a shallow V about a pale midrib, from tall upright leaves down to ones drooping
over the rim) and a rolled new leaf in the middle.

| | |
|---|---|
| Model source | `models/build_PottedPlant.py` -> `models/out/PottedPlant.parts.json` |
| Renders | `models/renders/PottedPlant_front.png`, `_three.png`, `_back.png` |
| Size | 3.97 x 6.23 x 4.11 studs (x, y, z) - the leaves; the pot + saucer are 2.5 wide, soil top 2.47 |
| Parts | 64 (budget 70); only the saucer, pot foot, belly, neck and lip collide |
| Attributes | `Cost` = 200, `DisplayName` = "Potted Plant", `Notes` |
| Scale | authored at 1 |

The brief asked for ~3 x 5.5 x 3; the leaves spread to ~4 so the plant reads as big and leafy. If it has to fit
a 3-stud cell, `BuildCatalog.SCALE.PottedPlant = 0.8` gives 3.2 x 5.0 x 3.3 (the behaviour handles any Scale).

## Behaviour
* **Client only** `src/behaviours/client/PottedPlant.lua` (no server half): every frond (`Frond<N>Stem`,
  `Frond<N>LeafL`, `Frond<N>LeafR`, `Frond<N>Rib`, N = 1..11, and `Frond0Spike`) sways gently about its stem base
  `Pivot_Frond<N>`: two slow sines per frond (3.9 s and 5.6 s, own phases) under a breeze that swells every 11 s;
  about 3 degrees at most, so the tallest leaf tips move ~0.15 studs. Driven by `Kit.Now()`, same on every client.
  One `ctx:Step` at 30 Hz, one BulkMoveTo, asleep beyond 90 studs. Cleanup puts every frond back at rest relative
  to the current hitbox. No sounds, no prompts.

## How to test
1. Install the model (`install/install_models.lua` with `{"PottedPlant"}`), add it to the build catalog (Home,
   200), install `FunBehavioursClient.PottedPlant`, place it: the leaves sway gently; the pot never moves.
2. Offline: `tests/HomeDecor` (see notes/Aquarium.md) runs it at scale 1 and 1.4 for 20 s: max sway 3 degrees,
   every frond part keeps its distance to its base, nothing else moves, cleanup restores every part.

## Known limits
* The monstera's leaf splits (fenestrations) are not modelled: a primitive leaf reads better whole.
* Fix pass (2026-09-24): the neck and lip are solid cylinders, so the soil used to sit hidden inside the lip (the
  pot top read as a flat cream plate). `SOIL_TOP` is now 2.47, 0.03 above the lip top: Soil (y 2.38-2.47, 1.84
  wide) and both pebbles show, with a 0.12 cream ring round them. Frond bases and `Pivot_Frond<N>` follow
  `SOIL_TOP` (all 0.14 higher); the client reads the pivots, so no Lua change was needed.
