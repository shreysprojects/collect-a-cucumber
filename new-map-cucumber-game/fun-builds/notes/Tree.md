# Tree - functional behaviour (2026-09-24, package GardenLife)

File: `src/behaviours/client/Tree.lua` -> `ReplicatedStorage.FunBehavioursClient.Tree`. **Client only, no server half.**
Serves Tree_A Oak (x1.6), Tree_B Pine (x1.6), Tree_C Sapling (x1.5).

## What it does
* **Wind sway**: the crown parts lean downwind and rock about the trunk foot. The rotation is about the authored
  trunk axis: A (10,0,0), B (0,0,0), C (-9.5,0,0), from the Blender author's notes. Amplitude: Oak 1.6 deg,
  Pine 0.9, Sapling 2.4. The whole map shares one wind direction (`WIND`, the same constant in Sunflower and Bush).
  Each tree's gust period (3-5 s) and phase come from its hitbox position. The pose is a pure function of
  `Kit.Now()`, so every client sees the same sway. The trunk and roots never move.
  Measured max crown travel: Oak 0.35-0.44 studs, Pine 0.19, Sapling 0.31-0.34.
* **Falling leaves** (Oak and Sapling only; the Pine gets none): every 1.6-4.2 s (Oak) or 3-6.5 s (Sapling) a flat
  oval leaf drops out of the underside of the crown. It flutters down in a pendulum swing, drifts with the wind,
  lies on the grass for 1.4 s and fades out over 1 s. Leaves are local `ctx:Part`s (Part + SpecialMesh Sphere)
  from a pool of 5 per tree. Colours: the crown colours plus 2 autumn tones. Leaves only spawn within 110 studs
  of the camera.

## Relies on
* Sway parts: `<V>_Crown*`, `<V>_Canopy*`, `<V>_Fruit`. Every other part stays put. The leaves fall out of the
  biggest Crown/Canopy part.
* The trunk-foot positions are authored numbers in `TREES`. There are no pivot attributes. A key without a variant
  falls back to the AuthoredCentre at y=0.

## Cost
One `ctx:Step` (StepRange 170). Crown parts are posed with one `BulkMoveTo`: every frame within 90 studs of the
camera, at 20 Hz beyond that, and not at all while the crown centre is off screen (unless the camera is within
40 studs). Cleanup puts the crown back relative to the CURRENT hitbox. That covers a move that raced the sway: the
Step stops posing as soon as the hitbox moves.

## How to test
Place a Tree_A and watch it from about 20 studs. The crown rocks gently and the trunk stays put. Now and then a leaf
falls and lies on the grass. On the client, `workspace.CurrentCamera` holds `FunLeaf` parts, and the visible ones
have Transparency < 1. Move the tree: no crown is left at the old spot. Sell it: the parts are at rest.
Offline check: `py tools/gardenlife-sim/build.py`.

## Known limits
* Leaves are random on each client (not synced). They are cosmetic only.
* Leaves land on the build's floor height. They fall through anything standing under the crown.
